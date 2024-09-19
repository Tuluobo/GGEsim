//
//  Base.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import APIKit
import Foundation

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
}

extension Request where Response: Decodable {
    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Response {
        guard let data = object as? Data else {
            throw GiffgaffError(message: "object is not data type: \(object)")
        }
        let json = try JSONSerialization.jsonObject(with: data)
        print("json: \(json)")
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
