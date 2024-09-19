//
//  Base.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import Foundation
import APIKit

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
        var headers = [String: String]()
        // Get cookies from shared HTTPCookieStorage
        if let cookies = HTTPCookieStorage.shared.cookies(for: self.baseURL) {
            headers.merge(HTTPCookie.requestHeaderFields(with: cookies)) {
                (_, new) in new
            }
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
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
