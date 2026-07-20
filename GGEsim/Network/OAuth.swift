//
//  OAuthRequest.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import APIKit
import Foundation

struct OAuthToken: Codable, Equatable {
    let type: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    /// 令牌到期的绝对时间。服务端只返回 expires_in（有效秒数），
    /// 首次拿到时按「当前时间 + expiresIn」换算成绝对时间，并随 token 一起持久化；
    /// 冷启动读取缓存时直接用它判断是否过期。
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case type = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        expiresIn = try c.decode(Int.self, forKey: .expiresIn)
        // 服务端响应里没有 expiresAt → 用 expiresIn 现算；本地缓存里有 → 直接用。
        if let stored = try c.decodeIfPresent(Date.self, forKey: .expiresAt) {
            expiresAt = stored
        } else {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }

    /// 是否已过期（预留 60s 时钟偏移，快到期即视为过期，提前刷新）。
    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

// MARK: - Request

struct AccessTokenRequest: Request {

    typealias Response = OAuthToken

    let clientId: String
    let clientSecret: String
    let data: [String: String]

    let baseURL = URL(string: "https://id.giffgaff.com")!
    let method = HTTPMethod.post
    let path = "/auth/oauth/token"

    var headerFields: [String: String] {
        // Headers
        var headers = [String: String]()
        // Get cookies from shared HTTPCookieStorage
        if let cookies = HTTPCookieStorage.shared.cookies(for: self.baseURL) {
            headers.merge(HTTPCookie.requestHeaderFields(with: cookies)) {
                (_, new) in new
            }
        }
        let authString = "\(clientId):\(clientSecret)"
        if let authData = authString.data(using: .utf8) {
            headers["Authorization"] = "Basic \(authData.base64EncodedString())"
        }
        return headers
    }

    var bodyParameters: (any BodyParameters)? {
        FormURLEncodedBodyParameters(formObject: data)
    }
}

/// 申请一次性 SSO code：用当前 access token 换一个短期一次性码，
/// 用于把 App 的登录态带到 giffgaff 网页（绑卡 / 管理支付方式等）。
///
/// 机制来自官方 App（Hermes bundle 反编译的 `toSsoUri`）：
///   POST https://id.giffgaff.com/auth/v1/sso/code
///   Authorization: Bearer <accessToken>   （由 Base.swift 的 headerFields 统一注入）
///   Accept / Content-Type: application/json
///   Body: {}
///   响应: { "sso_code": "<一次性 code>" }
struct SsoCodeRequest: Request {

    struct SsoCode: Decodable {
        let ssoCode: String
        enum CodingKeys: String, CodingKey { case ssoCode = "sso_code" }
    }

    typealias Response = SsoCode

    let baseURL = URL(string: "https://id.giffgaff.com")!
    let method = HTTPMethod.post
    let path = "/auth/v1/sso/code"

    var bodyParameters: (any BodyParameters)? {
        JSONBodyParameters(JSONObject: [:])
    }
}

struct VerifyCodeRequest: Request {

    struct VerifyCodeResponse: Codable {
        let signature: String
    }

    typealias Response = VerifyCodeResponse

    let ref: String
    let code: String

    let baseURL = URL(string: "https://id.giffgaff.com")!
    let method: HTTPMethod = .post
    let path = "/v4/mfa/validation"

    var bodyParameters: (any BodyParameters)? {
        JSONBodyParameters(JSONObject: [
            "ref": ref,
            "code": code,
        ])
    }
}
