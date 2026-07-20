//
//  TopUpService.swift
//  GGEsim
//
//  无实体卡账号申请 eSIM 的服务。
//
//  设计（按产品要求）：
//    - App 内不再录入 / 添加银行卡信息（已移除填卡页 + Adyen 加密/3DS）。
//    - 申请前先展示用户「已绑定的银行卡（Visa/Master 等）」：
//        · 已绑卡  → 允许进入下一步（预留 eSIM），最终用已绑卡一键支付并激活。
//        · 未绑卡  → 跳官网绑定（SFSafariView 带登录态），绑好回来再继续。
//
//  仍为 giffgaff GraphQL：
//    getPaymentMethods            取已绑支付方式（Card / Paypal）
//    reserveESim(ONBOARD_NEW)     预留新 eSIM，拿到 ssn
//    getPurchasableProducts       取充值档位（默认锁定 £10 / CR0010，仅展示）
//    createActivationOrder        为 ssn 下单，拿到订单号 orderId
//    eSimDownloadToken            支付激活后取 LPA 串，出二维码
//
//  「有卡一键支付」怎么做（据官方 Hermes bundle + 抓包定论）：
//     官方原生 App 里【不存在】用已绑卡直接调 GraphQL 扣款的接口——
//     整个 bundle 无 storedPaymentMethodId / recurringDetailReference，
//     原生 authorisePayment 只收 Adyen 加密的新卡字段。已绑卡的复用只发生在
//     「网页收银台」：App 跳到 https://www.giffgaff.com/app/payment?...&orderId=<id>
//     （抓包 Stream-2026-07-26 21:36:16 证实），页面在登录态下列出已绑卡、一键付款。
//     所以本服务的支付 = 先 createActivationOrder 拿 orderId，再用 SSO 把登录态带到
//     该网页收银台（WKWebView 打开），用户在网页里用已绑卡完成付款；付款后回到 App
//     取 eSIM 下载串出码。全程 App 内不录卡，符合产品决策。
//

import APIKit
import Foundation
import SwiftUI

// MARK: - Models

/// 一个可充值的金额档位（category == CREDIT），如 £10 / £15 …
struct CreditProduct: Codable, Identifiable {
    let id: String            // e.g. "CR0010"
    let name: String          // e.g. "£10"
    let priceInPence: Int      // e.g. 1000
    let category: String       // "CREDIT"
    let tags: [String]

    /// 是否支持自动充值
    var supportsAutoTopup: Bool { tags.contains("supportsAutoTopup") }

    /// 格式化后的价格，如 "£10.00"
    var formattedPrice: String {
        String(format: "£%.2f", Double(priceInPence) / 100)
    }
}

/// 用户已绑定的支付方式（getPaymentMethods → Card / Paypal）。
struct SavedPaymentMethod: Identifiable {
    enum Kind {
        case card(lastDigits: String, type: String?, expired: Bool)
        case paypal(email: String)
    }
    let id: String
    let isDefault: Bool
    let kind: Kind

    /// 是否为可用于支付的银行卡（Card 且未过期）。
    var isUsableCard: Bool {
        if case let .card(_, _, expired) = kind { return !expired }
        return false
    }

    /// 卡号后四位（仅银行卡）。
    var lastDigits: String? {
        if case let .card(last, _, _) = kind { return last }
        return nil
    }

    /// 展示用标题，如 "Visa •••• 1234" / "PayPal user@x.com"
    var displayName: String {
        switch kind {
        case let .card(last, type, expired):
            let brand = (type ?? "Card").capitalized
            return "\(brand) •••• \(last)" + (expired ? "（已过期）" : "")
        case let .paypal(email):
            return "PayPal \(email)"
        }
    }
}

/// reserveESim 预留的新 eSIM（无卡申请，userIntent: ONBOARD_NEW）。
struct ESimReservation: Codable {
    let id: String
    let memberId: String
    let status: String
    let esim: ReservedESim

    struct ReservedESim: Codable {
        let ssn: String
        let activationCode: String
        let deliveryStatus: String?
        let associatedMemberId: String?
    }
}

private struct OnboardReserveESimData: Decodable {
    let reserveESim: ESimReservation
}

/// createActivationOrder 响应：只取订单号 `order.id`（即 Web Checkout 需要的 orderId）。
/// 官方 bundle 里这条 mutation 就是 `{ order { id } }`（SimActivationOrderInput）。
private struct CreateActivationOrderData: Decodable {
    let createActivationOrder: OrderPayload
    struct OrderPayload: Decodable {
        let order: Order
        struct Order: Decodable { let id: String }
    }
}

// MARK: - GraphQL response wrappers

private struct PurchasableProductsData: Decodable {
    let purchasableProducts: [CreditProduct]
}

/// getPaymentMethods 响应（paymentMethods 是 Card/Paypal 的 union）。
private struct PaymentMethodsData: Decodable {
    let paymentMethods: [PaymentMethodNode]

    struct PaymentMethodNode: Decodable {
        let __typename: String
        let `default`: Bool?
        // Card
        let id: String?
        let lastDigits: String?
        let type: String?
        let expired: Bool?
        // Paypal
        let email: String?

        func toSaved() -> SavedPaymentMethod? {
            switch __typename {
            case "Card":
                guard let last = lastDigits else { return nil }
                return SavedPaymentMethod(
                    id: id ?? UUID().uuidString,
                    isDefault: `default` ?? false,
                    kind: .card(lastDigits: last, type: type, expired: expired ?? false)
                )
            case "Paypal":
                guard let email = email else { return nil }
                return SavedPaymentMethod(
                    id: id ?? email,
                    isDefault: `default` ?? false,
                    kind: .paypal(email: email)
                )
            default:
                return nil
            }
        }
    }
}

// MARK: - Service

@MainActor
final class TopUpService: ObservableObject {

    /// 默认充值档位 id（£10）。界面只展示、不可选。
    static let defaultProductId = "CR0010"

    enum State: Equatable {
        case idle
        case loading(String)
        case reserved        // 已预留 eSIM + 载入 £10，可用已绑卡支付
        case esimReady       // eSIM 可下载：已拿到 lpaString，展示二维码
        case refused(String) // 支付被拒（含原因）
        case failed(String)  // 链路出错
    }

    @Published var state: State = .idle
    /// 用户已绑定的支付方式（申请前展示）
    @Published var paymentMethods: [SavedPaymentMethod] = []
    /// 是否已加载过支付方式（用于区分“加载中/无绑定”）
    @Published var paymentMethodsLoaded = false
    /// 可充值的金额档位（仅展示）
    @Published var creditProducts: [CreditProduct] = []
    /// 锁定的充值档位（默认 £10）
    @Published var selectedProduct: CreditProduct?
    /// 无卡申请：reserveESim 预留的新 eSIM，提供后续所需的 ssn
    @Published var reservation: ESimReservation?
    /// eSIM 激活码（LPA 串），供展示二维码；用户自行扫码由系统完成下载激活。
    @Published var esimLPAString: String?
    /// 网页收银台的 SSO 落地 URL（带登录态）。非空即弹出 WKWebView 让用户用已绑卡付款。
    @Published var webCheckoutURL: URL?
    /// 是否正在准备网页收银台（下单 + 换 SSO code），用于按钮 loading。
    @Published var isPreparingCheckout = false

    /// 已绑定、可用于支付的银行卡（Card 且未过期，如 Visa / Master）。
    var boundCards: [SavedPaymentMethod] {
        paymentMethods.filter { $0.isUsableCard }
    }
    /// 是否已绑定可用银行卡。
    var hasBoundCard: Bool { !boundCards.isEmpty }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    // MARK: Step 0 — 申请前：载入已绑定的支付方式

    /// 载入用户已绑定的支付方式，供无卡申请前展示。
    /// 无绑定时 `paymentMethods` 为空，UI 展示“绑定支付方式”跳官网。
    func loadPaymentMethods() {
        Task {
            do {
                let methods = try await fetchPaymentMethods()
                paymentMethods = methods
                paymentMethodsLoaded = true
            } catch {
                // 失败也标记已加载，让 UI 退回“去绑定”入口，不卡住。
                paymentMethods = []
                paymentMethodsLoaded = true
            }
        }
    }

    // MARK: Step 1 — 预留新 eSIM + 载入充值档位（默认锁定 £10）

    /// 无卡申请入口：先 reserveESim(ONBOARD_NEW) 预留一张新 eSIM 拿到 ssn，
    /// 再用该 ssn 载入充值档位并锁定默认 £10（仅展示，不可选）。无验证码。
    func startOnboarding(memberId: String) {
        Task {
            do {
                // Step 1: 预留新 eSIM（ONBOARD_NEW），拿到 ssn
                state = .loading("Reserving eSIM…")
                let reservation = try await reserveNewESim(memberId: memberId)
                self.reservation = reservation

                // Step 2: 用 ssn 载入充值档位，锁定默认 £10
                state = .loading("Loading top-up…")
                let products = try await fetchCreditProducts(ssn: reservation.esim.ssn)
                creditProducts = products
                selectedProduct = products.first(where: { $0.id == Self.defaultProductId })
                    ?? products.min(by: { $0.priceInPence < $1.priceInPence })
                state = .reserved
            } catch {
                state = .failed("Failed to start eSIM order: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Step 2 — 跳网页收银台，用已绑卡一键支付并激活

    /// 用已绑定的银行卡完成支付（对齐官方 App 的 Web Checkout 路径）：
    ///   1) createActivationOrder 为已预留的 ssn + 选定档位下单，拿 orderId；
    ///   2) 拼网页收银台 redirect_uri（Constants.webCheckoutURL(orderId:)）；
    ///   3) 用 OAuthService.makeSsoURL 把 App 登录态带过去，WKWebView 打开该 SSO URL；
    ///      页面在登录态下列出已绑卡，用户点选即可一键付款。
    /// 付款在网页里完成，回到 App 后再 `fetchESimForDownload()` 取码出二维码。
    func startWebCheckout(memberId: String) {
        guard !isPreparingCheckout else { return }
        guard let ssn = reservation?.esim.ssn else {
            state = .failed("No reserved eSIM.")
            return
        }
        let amount = selectedProduct?.priceInPence
            ?? creditProducts.first(where: { $0.id == Self.defaultProductId })?.priceInPence
            ?? 1000
        isPreparingCheckout = true
        Task {
            defer { isPreparingCheckout = false }
            do {
                // 1) 下单拿 orderId
                let orderId = try await createActivationOrder(ssn: ssn, amountInPence: amount)
                // 2) 拼网页收银台落地页
                let checkout = Constants.webCheckoutURL(orderId: orderId)
                // 3) 用登录态换 SSO 链接
                let url = try await OAuthService.shared.makeSsoURL(redirectUri: checkout)
                webCheckoutURL = url
            } catch {
                state = .failed("发起支付失败：\(error.ggUnderlying.localizedDescription)")
            }
        }
    }

    /// 网页收银台回跳失败时调用（giffgaff://payment?status=<非success>&reason=…）。
    func markPaymentFailed(reason: String?) {
        state = .refused(reason ?? "支付未完成，请重试。")
    }

    // MARK: Step 3 — 取 eSIM 激活码用于展示二维码

    /// 支付激活成功后调用：取 eSIM 的 LPA 激活码，成功后 `state == .esimReady`。
    /// 之后只需展示二维码，用户自行扫码由系统完成下载与激活，无需 app 再发请求。
    func fetchESimForDownload() {
        guard let ssn = reservation?.esim.ssn else {
            state = .failed("No reserved eSIM.")
            return
        }
        Task {
            do {
                state = .loading("Preparing your eSIM…")
                let lpa = try await fetchESimDownloadToken(ssn: ssn)
                esimLPAString = lpa
                state = .esimReady
            } catch {
                state = .failed("Failed to get eSIM: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Network calls

    /// 预留一张新 eSIM（无卡申请，userIntent: ONBOARD_NEW），返回含 ssn 的预留信息。无验证码。
    private func reserveNewESim(memberId: String) async throws -> ESimReservation {
        let query = """
            mutation reserveESim($input: ESimReservationInput!) {
              reserveESim: reserveESim(input: $input) {
                id
                memberId
                reservationStartDate
                reservationEndDate
                status
                esim {
                  ssn
                  activationCode
                  deliveryStatus
                  associatedMemberId
                  __typename
                }
                __typename
              }
            }
            """
        let input: [String: Any] = [
            "memberId": memberId,
            "userIntent": "ONBOARD_NEW",
        ]
        let request = GraphQLRequest<Response<OnboardReserveESimData>>(
            query: query,
            variables: ["input": input]
        )
        let response = try await Session.response(for: request)
        return response.data.reserveESim
    }

    /// 为已预留的 ssn 下一张激活订单，返回订单号 orderId（网页收银台需要）。
    ///
    /// 用官方原生的 `createActivationOrder`（SimActivationOrderInput）——最小下单，
    /// 只回 `{ order { id } }`；账单地址 / 卡信息由网页收银台收集，App 内不录。
    /// 入参结构与抓包（Stream-2026-07-26 22:12:23）完全一致：顶层扁平的
    /// topupAmountInPence / deviceChannel:"app" / ssn，没有 credit 包裹、没有 product 字段。
    private func createActivationOrder(ssn: String, amountInPence: Int) async throws -> String {
        let query = """
            mutation createActivationOrder($input: SimActivationOrderInput!) {
              createActivationOrder(input: $input) {
                order {
                  id
                  __typename
                }
                __typename
              }
            }
            """
        let input: [String: Any] = [
            "topupAmountInPence": amountInPence,
            "deviceChannel": "app",
            "ssn": ssn,
        ]
        let request = GraphQLRequest<Response<CreateActivationOrderData>>(
            query: query,
            variables: ["input": input]
        )
        let response = try await Session.response(for: request)
        return response.data.createActivationOrder.order.id
    }

    private func fetchCreditProducts(ssn: String) async throws -> [CreditProduct] {
        let query = """
            query getPurchasableProducts($tags: [String], $ssn: String, $extraFields: [String]) {
              purchasableProducts(tags: $tags, ssn: $ssn, extraFields: $extraFields) {
                id
                name
                description
                iconRef
                category
                priceInPence
                tags
                __typename
              }
            }
            """
        let request = GraphQLRequest<Response<PurchasableProductsData>>(
            query: query,
            variables: [
                "ssn": ssn,
                "extraFields": "metadata.upsellProducts,metadata.oldAllowance,metadata.aggregates",
            ]
        )
        let response = try await Session.response(for: request)
        // 只保留充值类产品
        return response.data.purchasableProducts.filter { $0.category == "CREDIT" }
    }

    /// 取 eSIM 的 LPA 激活码（供展示二维码）。
    private func fetchESimDownloadToken(ssn: String) async throws -> String {
        let query = """
            query eSimDownloadToken($ssn: String!) {
              eSimDownloadToken(ssn: $ssn) {
                id
                host
                matchingId
                lpaString
                __typename
              }
            }
            """
        let request = GraphQLRequest<Response<ESimDownloadTokenData>>(
            query: query,
            variables: ["ssn": ssn]
        )
        let response = try await Session.response(for: request)
        return response.data.eSimDownloadToken.lpaString
    }

    /// 取用户已绑定的支付方式（getPaymentMethods）。
    private func fetchPaymentMethods() async throws -> [SavedPaymentMethod] {
        let query = """
            query getPaymentMethods {
              paymentMethods: paymentMethods {
                default
                __typename
                ... on Paypal {
                  email
                  __typename
                }
                ... on Card {
                  id
                  lastDigits
                  type
                  expired
                  expiryDate
                  __typename
                }
              }
            }
            """
        let request = GraphQLRequest<Response<PaymentMethodsData>>(query: query, variables: [:])
        let response = try await Session.response(for: request)
        return response.data.paymentMethods.compactMap { $0.toSaved() }
    }
}
