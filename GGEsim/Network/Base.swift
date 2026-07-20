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
            "x-gg-app-os-version": "26.1",
            "x-gg-app-build-number": "722",
            "x-gg-app-device-manufacturer": "Apple",
            "x-gg-app-version": "17.54.1",
            "x-gg-app-device-model": "iPhone",
            "x-gg-app-device-id": "iPhone17,1"
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
        print("request: \(self.bodyParameters)")
        print("json: \(json)")

        let error = (json as? [String: Any])?["error_description"] as? String
        // 注意：这里不再因为任意 4xx 就清空登录态。是否是「token 失效需要登出」，
        // 交给上层（OAuthService）判断——它会先尝试用 refresh token 刷新并重试，
        // 刷新失败才登出。直接在这里清 token 会把 refresh token 一起丢掉，无法刷新。
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
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            print("[decode 失败] \(Response.self) status=\(urlResponse.statusCode) error=\(error)\nbody=\(body)")
            throw error
        }
    }
}

extension Error {
    /// 剥掉 APIKit 的 SessionTaskError 外壳，取出底层真正的错误。
    /// SessionTaskError 有三种：connectionError(0)/requestError(1)/responseError(2)。
    var ggUnderlying: Error {
        guard let e = self as? SessionTaskError else { return self }
        switch e {
        case .connectionError(let err), .requestError(let err), .responseError(let err):
            return err
        }
    }

    /// 若底层是我们抛出的非 2xx HTTP 错误，返回其状态码。
    var ggHTTPStatusCode: Int? {
        if case let GGNetworkError.unacceptableStatusCode(code, _) = ggUnderlying {
            return code
        }
        return nil
    }
}
