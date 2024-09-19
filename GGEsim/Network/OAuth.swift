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

    enum CodingKeys: String, CodingKey {
        case type = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
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

struct SendEmailCodeRequest: Request {

    struct SendEmailCodeResponse: Codable {
        let ref: String
    }

    typealias Response = SendEmailCodeResponse

    let baseURL = URL(string: "https://id.giffgaff.com")!
    let method: HTTPMethod = .post
    let path = "/v4/mfa/challenge/me"

    var bodyParameters: (any BodyParameters)? {
        JSONBodyParameters(JSONObject: [
            "source": "esim",
            "preferredChannels": ["EMAIL"],
        ])
    }
}

struct VerifyEmailCodeRequest: Request {

    struct VerifyEmailCodeResponse: Codable {
        let signature: String
    }

    typealias Response = VerifyEmailCodeResponse

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
