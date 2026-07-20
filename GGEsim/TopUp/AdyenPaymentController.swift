//
//  AdyenPaymentController.swift
//  GGEsim
//
//  用 Adyen iOS SDK 实现 TopUpService 的两个注入点：
//    - CardEncrypting：用 clientKey 取 publicKey，再用 CardEncryptor 加密卡片字段。
//    - ThreeDSHandling：用 ThreeDS2Component 处理 IdentifyShopper/Challenge，
//      产出 giffgaff additionalActions 需要的 threeDSResult。
//
//  说明：加密只依赖稳定的 AdyenEncryption.CardEncryptor；publicKey 通过 Adyen 公开的
//  /checkoutshopper/v1/clientKeys/{clientKey} 接口获取（与抓包一致）。
//  3DS2 用 AdyenActions 的 ThreeDS2Component，走 fingerprint→challenge，
//  最终从 didProvide 的 details 中取 threeDSResult 回传。
//

import Adyen
import AdyenActions
import AdyenEncryption
import Foundation
import UIKit

@MainActor
final class AdyenPaymentController: NSObject, CardEncrypting, ThreeDSHandling {

    static let shared = AdyenPaymentController()

    enum AdyenError: LocalizedError {
        case publicKeyFetchFailed
        case encryptionFieldMissing
        case unsupportedAction(String)
        case missingActionField(String)
        case threeDSResultMissing
        case challengeFailed(String)

        var errorDescription: String? {
            switch self {
            case .publicKeyFetchFailed: return "无法获取 Adyen public key"
            case .encryptionFieldMissing: return "卡片加密结果缺少字段"
            case .unsupportedAction(let t): return "不支持的支付动作：\(t)"
            case .missingActionField(let f): return "支付动作缺少字段：\(f)"
            case .threeDSResultMissing: return "3DS 校验结果缺失"
            case .challengeFailed(let m): return "3DS 校验失败：\(m)"
            }
        }
    }

    // MARK: - CardEncrypting

    func encrypt(card: CardInput, clientKey: String) async throws -> EncryptedCard {
        let publicKey = try await fetchPublicKey(clientKey: clientKey)

        let adyenCard = Card(
            number: card.number,
            securityCode: card.securityCode,
            expiryMonth: card.expiryMonth,
            expiryYear: card.expiryYear,
            holder: card.holderName
        )
        let encrypted = try CardEncryptor.encrypt(card: adyenCard, with: publicKey)

        guard
            let number = encrypted.number,
            let month = encrypted.expiryMonth,
            let year = encrypted.expiryYear,
            let cvc = encrypted.securityCode
        else {
            throw AdyenError.encryptionFieldMissing
        }

        return EncryptedCard(
            encryptedCardNumber: number,
            encryptedExpiryMonth: month,
            encryptedExpiryYear: year,
            encryptedSecurityCode: cvc,
            holderName: card.holderName
        )
    }

    // MARK: - ThreeDSHandling

    private var threeDSComponent: ThreeDS2Component?
    private var challengeContinuation: CheckedContinuation<String, Error>?

    func performChallenge(action: PaymentAction, clientKey: String) async throws -> String {
        let context = try makeAdyenContext(clientKey: clientKey)
        let component = ThreeDS2Component(context: context)
        component.delegate = self
        component.presentationDelegate = self
        self.threeDSComponent = component

        return try await withCheckedThrowingContinuation { continuation in
            self.challengeContinuation = continuation
            do {
                try dispatch(action: action, to: component)
            } catch {
                self.finishChallenge(.failure(error))
            }
        }
    }

    /// 把 giffgaff 的 action 映射成 Adyen 的 3DS2 Action 并交给组件处理。
    private func dispatch(action: PaymentAction, to component: ThreeDS2Component) throws {
        guard let token = action.token else {
            throw AdyenError.missingActionField("token")
        }
        // giffgaff resultCode: IdentifyShopper → fingerprint；ChallengeShopper → challenge
        switch action.type {
        case "IdentifyShopper", "identifyShopper", nil:
            let fingerprint = ThreeDS2FingerprintAction(
                fingerprintToken: token,
                authorisationToken: action.authorisationToken,
                paymentData: action.paymentData
            )
            component.handle(fingerprint)
        case "ChallengeShopper", "challengeShopper":
            let challenge = ThreeDS2ChallengeAction(
                challengeToken: token,
                authorisationToken: action.authorisationToken,
                paymentData: action.paymentData
            )
            component.handle(challenge)
        default:
            throw AdyenError.unsupportedAction(action.type ?? action.__typename)
        }
    }

    private func finishChallenge(_ result: Result<String, Error>) {
        challengeContinuation?.resume(with: result)
        challengeContinuation = nil
        threeDSComponent = nil
    }

    // MARK: - Helpers

    private func makeAdyenContext(clientKey: String) throws -> AdyenContext {
        let apiContext = try APIContext(environment: Environment.live, clientKey: clientKey)
        return AdyenContext(apiContext: apiContext, payment: nil)
    }

    /// 从 Adyen 公开接口用 clientKey 取 cardPublicKey。
    private func fetchPublicKey(clientKey: String) async throws -> String {
        let url = Environment.live.baseURL
            .appendingPathComponent("checkoutshopper/v1/clientKeys/\(clientKey)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let publicKey = json["publicKey"] as? String
        else {
            throw AdyenError.publicKeyFetchFailed
        }
        return publicKey
    }

    /// 把 Adyen 的 details 编码后取出 threeDSResult。
    private func extractThreeDSResult(from details: AdditionalDetails) throws -> String {
        let data = try JSONEncoder().encode(AnyEncodable(details))
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["threeDSResult"] as? String
        else {
            throw AdyenError.threeDSResultMissing
        }
        return result
    }
}

// MARK: - ActionComponentDelegate

extension AdyenPaymentController: ActionComponentDelegate {

    func didProvide(_ data: ActionComponentData, from component: ActionComponent) {
        do {
            let result = try extractThreeDSResult(from: data.details)
            finishChallenge(.success(result))
        } catch {
            finishChallenge(.failure(error))
        }
    }

    func didComplete(from component: ActionComponent) {
        // fingerprint 完成但无 details 时不应发生；容错为失败。
        if challengeContinuation != nil {
            finishChallenge(.failure(AdyenError.threeDSResultMissing))
        }
    }

    func didFail(with error: Error, from component: ActionComponent) {
        finishChallenge(.failure(AdyenError.challengeFailed(error.localizedDescription)))
    }
}

// MARK: - PresentationDelegate

extension AdyenPaymentController: PresentationDelegate {

    func present(component: PresentableComponent) {
        // 3DS challenge 需要 present 一个 UI（挑战页）。
        guard let top = Self.topViewController() else { return }
        let viewController = component.viewController
        top.present(viewController, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// 类型擦除，让 `AdditionalDetails`（Encodable）可被 JSONEncoder 编码。
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        self.encodeFunc = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
