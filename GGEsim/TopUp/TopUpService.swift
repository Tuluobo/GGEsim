//
//  TopUpService.swift
//  GGEsim
//
//  把「只充值、默认 £10、信用卡支付」的完整链路串成一个服务。
//
//  完整链路（全部为 giffgaff GraphQL）：
//    1. getPurchasableProducts (category == CREDIT)   取得可充值金额档位（默认锁定 £10 / CR0010）
//    2. getNativeCardPaymentMethod                    取得信用卡支付配置（Adyen scheme）+ clientKey
//    3. createActivationOrderWithBillingAddress       创建订单 → order.id + paymentSessionId
//    4. authorisePayment                              提交加密卡片数据 → resultCode + action
//    5. additionalActions                             3DS 挑战完成后回传 threeDSResult → 最终 resultCode
//
//  其中「卡片字段加密」和「3DS2 挑战」两步必须由 Adyen 客户端产出，
//  通过 `CardEncrypting` / `ThreeDSHandling` 两个协议注入（默认桩会抛未实现错误，
//  接入 Adyen iOS SDK 后替换即可）。
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

/// 信用卡支付配置（Adyen scheme），用于卡片信息页
struct NativeCardPaymentMethod: Codable {    let id: String                        // "NativeCard"
    /// Adyen 卡片组件配置，服务端以 JSON 字符串下发
    let cardPaymentMethod: String
    let creditPurchaseEnabled: Bool
    let goodybagPurchaseEnabled: Bool
    let simActivationEnabled: Bool
    let supportedCountries: [SupportedCountry]

    struct SupportedCountry: Codable {
        let name: String
        let code: String
        let stateRequired: Bool?
    }

    /// 把服务端下发的 JSON 字符串解析成字典，供 Adyen 卡片组件初始化
    var cardComponentConfig: [String: Any]? {
        guard let data = cardPaymentMethod.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Adyen live client key。
    /// 注意：抓包显示该值不在本 GraphQL 响应里，而是 App 内置常量，故取自配置常量。
    var clientKey: String { Constants.adyenClientKey }
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

/// 卡片信息页所需的一次性上下文
struct TopUpCheckout {
    let product: CreditProduct
    let cardPaymentMethod: NativeCardPaymentMethod
    /// 当前余额（便士），可能为空（账号无 airtime summary）
    let currentBalanceInPence: Int?

    var formattedBalance: String? {
        currentBalanceInPence.map { String(format: "£%.2f", Double($0) / 100) }
    }
}

/// 姓名（卡片信息页填写）
struct FullName: Codable {
    let firstName: String
    let lastName: String
}

/// 账单 / 个人地址（卡片信息页填写）
struct BillingAddress: Codable {
    let buildingNumber: String
    let street: String
    let postalCode: String
    let city: String
    /// 部分国家/地区需要 state（见 supportedCountries.stateRequired）
    let state: String?
    /// 两位国家码，如 "CN" / "GB"
    let countryCode: String
}

/// 创建充值订单后返回的订单信息。
/// `paymentSessionId` 供后续 authorisePayment 使用（作为 input.id）。
struct TopUpOrder: Codable {
    let id: String
    let resultCode: String?
    let paymentSessionId: String?
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

// MARK: - Adyen 客户端注入点

/// Adyen 客户端加密后的卡片数据（authorisePayment.input.paymentMethod 使用）。
/// 四个 encrypted* 字段是 Adyen 用 clientKey 加密后的 JWE 串。
struct EncryptedCard {
    let encryptedCardNumber: String
    let encryptedExpiryMonth: String
    let encryptedExpiryYear: String
    let encryptedSecurityCode: String
    let holderName: String
}

/// 明文卡片输入（仅用于交给 Adyen 加密，绝不直接上送 giffgaff）。
struct CardInput {
    let number: String
    let expiryMonth: String
    let expiryYear: String
    let securityCode: String
    let holderName: String
}

/// 卡片加密注入点：由 Adyen iOS SDK / adyen card component 实现。
protocol CardEncrypting {
    /// 用 clientKey 把明文卡片加密成 Adyen JWE。
    func encrypt(card: CardInput, clientKey: String) async throws -> EncryptedCard
}

/// 3DS2 挑战注入点：由 Adyen 3DS2 SDK 实现。
protocol ThreeDSHandling {
    /// 处理 IdentifyShopper / Challenge 动作，返回 additionalActions 需要的 `threeDSResult`。
    func performChallenge(action: PaymentAction, clientKey: String) async throws -> String
}

// MARK: - 支付结果模型

/// authorisePayment / additionalActions 返回的后续动作。
/// 对应 GraphQL union（RedirectShopperAction / ChallengeIdentifyShopperAction）。
struct PaymentAction: Codable {
    let __typename: String
    // ChallengeIdentifyShopperAction
    let paymentData: String?
    let paymentMethodType: String?
    let type: String?
    let subtype: String?
    let authorisationToken: String?
    let token: String?
    // RedirectShopperAction
    let url: String?
    let method: String?
}

/// authorisePayment / additionalActions 的响应主体。
struct AuthoriseResult: Codable {
    let id: String
    let callerReferenceId: String?
    let amountInPence: Int?
    let resultCode: String            // Authorised / IdentifyShopper / Refused / ...
    let refusalReason: String?
    let refusalReasonDescription: String?
    let action: PaymentAction?

    /// 是否需要额外的 3DS 挑战。
    var needsChallenge: Bool {
        resultCode == "IdentifyShopper" || resultCode == "ChallengeShopper" || resultCode == "RedirectShopper"
    }
    var isAuthorised: Bool { resultCode == "Authorised" || resultCode == "Received" }
    var isRefused: Bool { resultCode == "Refused" || resultCode == "Error" || resultCode == "Cancelled" }
}

// MARK: - GraphQL response wrappers

private struct PurchasableProductsData: Decodable {
    let purchasableProducts: [CreditProduct]
}

private struct NativeCardPaymentMethodData: Decodable {
    let nativeCardPaymentMethod: NativeCardPaymentMethod
}

private struct CreateActivationOrderData: Decodable {
    struct Wrapper: Decodable {
        let order: TopUpOrder
    }
    let createActivationOrderWithBillingAddress: Wrapper
}

private struct AuthorisePaymentData: Decodable {
    let authorisePayment: AuthoriseResult
}

private struct AdditionalActionsData: Decodable {
    let additionalActions: AuthoriseResult
}

private struct DeletePaymentPreferenceData: Decodable {
    let deletePaymentPreference: Bool?
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
        case ready           // 卡片信息页可以弹出
        case orderCreated    // 订单已创建，拿到 paymentSessionId
        case authorised      // 支付成功（此时可询问是否删除支付卡）
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
    /// 准备完成后用于弹出卡片信息页
    @Published var checkout: TopUpCheckout?
    /// 卡片信息页提交后创建的订单（含 paymentSessionId）
    @Published var order: TopUpOrder?
    /// 支付授权/挑战后的最终结果
    @Published var paymentResult: AuthoriseResult?
    /// eSIM 激活码（LPA 串），供展示二维码；用户自行扫码由系统完成下载激活。
    @Published var esimLPAString: String?

    /// Adyen 卡片加密注入点（默认桩，接 SDK 后替换）
    private let cardEncrypter: CardEncrypting
    /// Adyen 3DS2 挑战注入点（默认桩，接 SDK 后替换）
    private let threeDSHandler: ThreeDSHandling

    init(
        cardEncrypter: CardEncrypting = UnimplementedCardEncrypter(),
        threeDSHandler: ThreeDSHandling = UnimplementedThreeDSHandler()
    ) {
        self.cardEncrypter = cardEncrypter
        self.threeDSHandler = threeDSHandler
    }

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
                state = .idle
            } catch {
                state = .failed("Failed to start eSIM order: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Step 2+3 — 准备信用卡支付并弹出卡片信息页

    /// 取信用卡支付配置（Adyen scheme），成功后 `state == .ready` 且 `checkout` 就绪，
    /// UI 据此弹出卡片信息页。
    func prepareCardCheckout() {
        guard let product = selectedProduct else {
            state = .failed("Please select a top-up amount first.")
            return
        }
        Task {
            do {
                state = .loading("Preparing payment…")

                // 取信用卡支付配置（Adyen scheme）
                let cardMethod = try await fetchNativeCardPaymentMethod()
                guard cardMethod.creditPurchaseEnabled else {
                    state = .failed("Credit top-up by card is not available on this account.")
                    return
                }

                checkout = TopUpCheckout(
                    product: product,
                    cardPaymentMethod: cardMethod,
                    currentBalanceInPence: nil
                )
                // 卡片信息页可以弹出了
                state = .ready
            } catch {
                state = .failed("Failed to prepare payment: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Step 4+5 — 一键完成支付：下单 → 授权 → 3DS → 补充动作

    /// 卡片信息页提交：把「创建订单 → 授权支付 →（如需）3DS 挑战 → 补充动作」整条链串起来。
    /// ssn 取自 startOnboarding 里 reserveESim 的预留结果。
    ///
    /// - Parameters:
    ///   - memberId: 会员 id（authorisePayment 需要）
    ///   - fullName: 持卡人姓名
    ///   - billingAddress: 账单地址
    ///   - card: 明文卡片（仅用于交给 Adyen 加密，不直接上送）
    ///   - personalAddress: 个人地址（默认与账单地址相同）
    ///   - saveBillingAddress: 是否保存账单地址
    func payWithCard(
        memberId: String,
        fullName: FullName,
        billingAddress: BillingAddress,
        card: CardInput,
        personalAddress: BillingAddress? = nil,
        saveBillingAddress: Bool = false
    ) {
        guard let checkout else {
            state = .failed("Payment is not prepared yet.")
            return
        }
        guard let ssn = reservation?.esim.ssn else {
            state = .failed("No reserved eSIM. Please start the order again.")
            return
        }
        Task {
            do {
                let clientKey = checkout.cardPaymentMethod.clientKey

                // Step 3: 创建订单，取 paymentSessionId
                state = .loading("Creating order…")
                let order = try await createActivationOrder(
                    topupAmountInPence: checkout.product.priceInPence,
                    ssn: ssn,
                    fullName: fullName,
                    billingAddress: billingAddress,
                    personalAddress: personalAddress ?? billingAddress,
                    saveBillingAddress: saveBillingAddress
                )
                self.order = order
                guard let paymentSessionId = order.paymentSessionId else {
                    state = .failed("Order did not return a payment session.")
                    return
                }
                state = .orderCreated

                // 用 Adyen 加密卡片字段（注入点）
                state = .loading("Encrypting card…")
                let encrypted = try await cardEncrypter.encrypt(card: card, clientKey: clientKey)

                // Step 4: 授权支付
                state = .loading("Authorising payment…")
                var result = try await authorisePayment(
                    callerReferenceId: order.id,
                    paymentSessionId: paymentSessionId,
                    memberId: memberId,
                    encrypted: encrypted,
                    billingAddress: billingAddress,
                    saveCard: saveBillingAddress
                )
                self.paymentResult = result

                // Step 5: 若需要 3DS 挑战，跑挑战 → additionalActions
                if result.needsChallenge, let action = result.action {
                    state = .loading("Verifying with your bank…")
                    let threeDSResult = try await threeDSHandler.performChallenge(
                        action: action, clientKey: clientKey
                    )
                    state = .loading("Completing payment…")
                    result = try await submitAdditionalActions(
                        paymentId: result.id,
                        paymentData: action.paymentData ?? "",
                        threeDSResult: threeDSResult
                    )
                    self.paymentResult = result
                }

                // 收尾：判定最终结果。成功后停在 .authorised，
                // 由 UI 先询问是否删除支付卡，再调 fetchESimForDownload 出二维码。
                if result.isAuthorised {
                    state = .authorised
                } else if result.isRefused {
                    state = .refused(result.refusalReasonDescription ?? result.refusalReason ?? "Payment refused")
                } else {
                    // 仍需进一步动作但已无 handler 可处理
                    state = .refused("Payment requires further action (\(result.resultCode)).")
                }
            } catch {
                state = .failed("Payment failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Step 6 — 取 eSIM 激活码用于展示二维码

    /// 支付成功后调用：取 eSIM 的 LPA 激活码，成功后 `state == .esimReady`。
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

    // MARK: 移除支付卡信息

    /// 删除已保存的支付方式偏好（对应官方 deletePaymentPreference，无参数）。
    /// 用户在支付成功后可选择删除，避免卡信息留存。
    func deletePaymentCard() async {
        do {
            try await deletePaymentPreference()
        } catch {
            // 删除失败不阻断主流程，仅记录。
            print("deletePaymentPreference failed: \(error.localizedDescription)")
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

    private func fetchNativeCardPaymentMethod() async throws -> NativeCardPaymentMethod {
        let query = """
            query getNativeCardPaymentMethod {
              nativeCardPaymentMethod {
                id
                cardPaymentMethod
                creditPurchaseEnabled
                goodybagPurchaseEnabled
                simActivationEnabled
                supportedCountries {
                  name
                  code
                  stateRequired
                  __typename
                }
                __typename
              }
            }
            """
        let request = GraphQLRequest<Response<NativeCardPaymentMethodData>>(query: query, variables: [:])
        let response = try await Session.response(for: request)
        return response.data.nativeCardPaymentMethod
    }

    /// 创建充值订单（信用卡 + 账单地址），返回含 paymentSessionId 的订单。
    private func createActivationOrder(
        topupAmountInPence: Int,
        ssn: String,
        fullName: FullName,
        billingAddress: BillingAddress,
        personalAddress: BillingAddress,
        saveBillingAddress: Bool
    ) async throws -> TopUpOrder {
        let query = """
            mutation createActivationOrderWithBillingAddress($input: SimActivationWithBillingAddressInput!) {
              createActivationOrderWithBillingAddress(input: $input) {
                order {
                  id
                  resultCode
                  paymentSessionId
                  __typename
                }
                __typename
              }
            }
            """

        let input: [String: Any] = [
            "credit": ["topupAmountInPence": topupAmountInPence],
            "product": "CREDIT",
            "deviceChannel": "app",
            "ssn": ssn,
            "fullName": [
                "firstName": fullName.firstName,
                "lastName": fullName.lastName,
            ],
            "billingAddress": addressDict(billingAddress),
            "personalAddress": addressDict(personalAddress),
            "saveBillingAddress": saveBillingAddress,
        ]

        let request = GraphQLRequest<Response<CreateActivationOrderData>>(
            query: query,
            variables: ["input": input]
        )
        let response = try await Session.response(for: request)
        return response.data.createActivationOrderWithBillingAddress.order
    }

    /// 授权支付：提交加密卡片数据，返回结果（可能带 3DS 挑战动作）。
    private func authorisePayment(
        callerReferenceId: String,
        paymentSessionId: String,
        memberId: String,
        encrypted: EncryptedCard,
        billingAddress: BillingAddress,
        saveCard: Bool
    ) async throws -> AuthoriseResult {
        let query = """
            mutation authorisePayment($input: AuthorisePaymentInput!) {
              authorisePayment(input: $input) {
                id
                callerReferenceId
                amountInPence
                resultCode
                refusalReason
                refusalReasonDescription
                action {
                  __typename
                  ... on RedirectShopperAction {
                    url
                    paymentMethodType
                    method
                    type
                    data {
                      MD
                      PaReq
                      TermUrl
                      __typename
                    }
                    __typename
                  }
                  ... on ChallengeIdentifyShopperAction {
                    paymentData
                    paymentMethodType
                    type
                    subtype
                    authorisationToken
                    token
                    __typename
                  }
                }
                __typename
              }
            }
            """

        let paymentMethod: [String: Any] = [
            "encryptedCardNumber": encrypted.encryptedCardNumber,
            "encryptedExpiryMonth": encrypted.encryptedExpiryMonth,
            "encryptedExpiryYear": encrypted.encryptedExpiryYear,
            "encryptedSecurityCode": encrypted.encryptedSecurityCode,
            "holderName": encrypted.holderName,
            // 以下为与用户无关的固定值，原样取自抓包
            "threeDS2SdkVersion": Self.threeDS2SdkVersion,
            "markAsDefault": false,
            "type": "CARD",
            "billingAddress": addressDict(billingAddress),
            "save": saveCard,
        ]

        let input: [String: Any] = [
            "callerReferenceId": callerReferenceId,
            "id": paymentSessionId,
            "memberId": memberId,
            "paymentMethod": paymentMethod,
            // 以下为与用户无关的固定值，原样取自抓包
            "browserInfo": ["userAgent": Self.userAgent],
            "platform": "IOS",
            "paymentChannel": "ACTIVATION",
            "returnUrl": Constants.paymentReturnUrl,
        ]

        let request = GraphQLRequest<Response<AuthorisePaymentData>>(
            query: query,
            variables: ["input": input]
        )
        let response = try await Session.response(for: request)
        return response.data.authorisePayment
    }

    /// 补充动作：3DS 挑战完成后回传 threeDSResult，返回最终支付结果。
    private func submitAdditionalActions(
        paymentId: String,
        paymentData: String,
        threeDSResult: String
    ) async throws -> AuthoriseResult {
        let query = """
            mutation additionalActions($input: AdditionalActionsInput!) {
              additionalActions(input: $input) {
                id
                resultCode
                refusalReason
                refusalReasonDescription
                action {
                  __typename
                  ... on RedirectShopperAction {
                    url
                    paymentMethodType
                    data {
                      MD
                      PaReq
                      TermUrl
                      __typename
                    }
                    __typename
                  }
                  ... on ChallengeIdentifyShopperAction {
                    paymentData
                    paymentMethodType
                    type
                    subtype
                    authorisationToken
                    token
                    __typename
                  }
                }
                __typename
              }
            }
            """
        let input: [String: Any] = [
            "details": ["threeDSResult": threeDSResult],
            "paymentData": paymentData,
            "paymentId": paymentId,
        ]
        let request = GraphQLRequest<Response<AdditionalActionsData>>(
            query: query,
            variables: ["input": input]
        )
        let response = try await Session.response(for: request)
        return response.data.additionalActions
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

    /// 删除已保存的支付方式偏好（deletePaymentPreference，无参数）。
    private func deletePaymentPreference() async throws {
        let query = """
            mutation deletePaymentPreference {
              deletePaymentPreference
            }
            """
        let request = GraphQLRequest<Response<DeletePaymentPreferenceData>>(query: query, variables: [:])
        _ = try await Session.response(for: request)
    }

    // MARK: - Helpers

    private func addressDict(_ a: BillingAddress) -> [String: Any] {
        [
            "buildingNumber": a.buildingNumber,
            "street": a.street,
            "postalCode": a.postalCode,
            "city": a.city,
            "state": a.state as Any,   // 允许为 null
            "countryCode": a.countryCode,
        ]
    }

    /// authorisePayment.input.browserInfo.userAgent，取自抓包，原样保留。
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    /// authorisePayment.input.paymentMethod.threeDS2SdkVersion，取自抓包，原样保留。
    private static let threeDS2SdkVersion = "2.4.2"
}

// MARK: - Adyen 注入点默认桩

/// 错误：Adyen 客户端能力尚未接入。
struct AdyenNotIntegratedError: LocalizedError {
    let what: String
    var errorDescription: String? {
        "Adyen \(what) is not integrated yet. 接入 Adyen iOS SDK 后替换此桩即可完成扣款。"
    }
}

/// 默认卡片加密桩：未接 Adyen SDK 前会抛错，防止明文卡号误上送。
struct UnimplementedCardEncrypter: CardEncrypting {
    func encrypt(card: CardInput, clientKey: String) async throws -> EncryptedCard {
        throw AdyenNotIntegratedError(what: "card encryption")
    }
}

/// 默认 3DS 挑战桩：未接 Adyen SDK 前会抛错。
struct UnimplementedThreeDSHandler: ThreeDSHandling {
    func performChallenge(action: PaymentAction, clientKey: String) async throws -> String {
        throw AdyenNotIntegratedError(what: "3DS2 challenge")
    }
}
