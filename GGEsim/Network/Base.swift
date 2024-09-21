//
//  Base.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import APIKit
import Foundation

enum GGNetworkError: Error {
    case unacceptableStatusCode(Int, String)
    case unexpectedObject(Any)
}

class OriginDataParser: DataParser {
    var contentType: String? {
        nil
    }

    func parse(data: Data) throws -> Any {
        data
    }
}

extension Request {
    var headerFields: [String: String] {
        // Headers
        var headers = [
            "x-gg-app-os": "iOS",
            "x-gg-app-os-version": "14",
            "x-gg-app-build-number": "722",
            "x-gg-app-device-manufacturer": "apple",
            "x-gg-app-device-model": "iphone15",
            "x-gg-app-version": "13.21.2",
        ]
        // Get cookies from shared HTTPCookieStorage
        if let cookies = HTTPCookieStorage.shared.cookies(for: self.baseURL) {
            headers.merge(HTTPCookie.requestHeaderFields(with: cookies)) { (_, new) in new }
        }
        // Authorization
        if let token = OAuthService.shared.oauthToken {
            headers["Authorization"] = "Bearer \(token.accessToken)"
        }
        return headers
    }

    var dataParser: DataParser {
        OriginDataParser()
    }

    func intercept(object: Any, urlResponse: HTTPURLResponse) throws -> Any {
        guard let data = object as? Data else {
            print("object is not `Data` type: \(object.self), object: \(object)")
            throw GGNetworkError.unexpectedObject(object)
        }
        let json = try JSONSerialization.jsonObject(with: data)
        print("json: \(json)")

        let error = (json as? [String: Any])?["error_description"] as? String
        if 400..<500 ~= urlResponse.statusCode {
            OAuthService.shared.updateToken(nil)
            throw GGNetworkError.unacceptableStatusCode(
                urlResponse.statusCode, error ?? "unauthorized request"
            )
        }
        guard 200..<300 ~= urlResponse.statusCode else {
            throw GGNetworkError.unacceptableStatusCode(
                urlResponse.statusCode,
                error ?? "the status code is not acceptable"
            )
        }

        return object
    }
}

extension Request where Response: Decodable {
    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Response {
        guard let data = object as? Data else {
            throw GiffgaffError(message: "object is not data type: \(object)")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
