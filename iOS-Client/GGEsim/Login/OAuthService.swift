//
//  OAuthService.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import APIKit
import CommonCrypto
import Foundation
import SwiftUI

class OAuthService: ObservableObject {

    @Published var isLogin: Bool = false

    @Published var oauthToken: OAuthToken?
    @Published var memberInfo: MemberInfo?

    /// 正在进行的刷新任务；同一时刻只刷新一次，其余调用复用同一结果，避免并发重复刷新。
    private var refreshTask: Task<OAuthToken?, Never>?

    private enum OAuth {
        static let redirectUri = "giffgaff://auth/callback/"
        static let clientId = Bundle.main.infoDictionary?[Constants.kClientIdKey] as! String
        static let clientSecret = Bundle.main.infoDictionary?[Constants.kClientSecretKey] as! String
        static let authorizeUrl = "https://id.giffgaff.com/auth/oauth/authorize"
    }

    static let shared = OAuthService()

    private init() {
        self.oauthToken = getToken()
    }

    func startOAuthFlow() -> URL {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(codeVerifier: codeVerifier)

        var components = URLComponents(string: OAuth.authorizeUrl)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuth.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read"),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "redirect_uri", value: OAuth.redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
        ]

        UserDefaults.standard.set(codeVerifier, forKey: "codeVerifier")
        
        // 基于抓包，构造跳转到主站的入口连接，让其再重定向回来
        let authorizeString = components.url!.absoluteString
        var entryComponents = URLComponents(string: "https://www.giffgaff.com/auth/login")!
        entryComponents.queryItems = [
            URLQueryItem(name: "device", value: "app"),
            URLQueryItem(name: "redirect", value: authorizeString)
        ]
        
        return entryComponents.url!
    }

    func handleCallback(url: URL) {
        appLog("Callback url: \(url)")
        guard
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
        else {
            appLog("Error: No code found in callback URL")
            return
        }

        fetchAccessToken(code: code)
    }

    func getMember() {
        guard let token = oauthToken else { return }
        Task { await loadMember(startingWith: token) }
    }

    /// 冷启动 / 刷新后加载用户信息，保证 access token 有效：
    /// 1) 本地判断已过期，就先用 refresh token 刷新；
    /// 2) 拉取用户信息，若返回 401 说明 access token 实际已失效，刷新后重试一次；
    /// 3) 刷新失败才登出，回到登录页。
    @MainActor
    private func loadMember(startingWith token: OAuthToken) async {
        isLogin = true
        defer { isLogin = false }

        // 1) 提前刷新：本地判断已过期就先换新 token。
        if token.isExpired {
            appLog("[getMember] access token 本地已过期，先刷新")
            guard await refreshAccessToken(using: token) != nil else {
                appLog("[getMember] 提前刷新失败 → 登出")
                signout()
                return
            }
        }

        // 2) 拉取用户信息。
        do {
            memberInfo = try await requestMemberInfo()
            appLog("[getMember] 成功 member=\(memberInfo?.memberProfile.memberName ?? "-") sim=\(memberInfo?.sim?.phoneNumber ?? "nil")")
            return
        } catch {
            logError("[getMember] 首次请求失败", error)
            // 只有 access token 实际失效（HTTP 401）才刷新重试；其余错误直接返回。
            guard error.ggHTTPStatusCode == 401 else { return }
        }

        // 3) 401：刷新后重试一次。
        appLog("[getMember] 收到 401，尝试刷新 token 后重试")
        guard let current = oauthToken,
              await refreshAccessToken(using: current) != nil else {
            appLog("[getMember] 401 后刷新失败 → 登出")
            signout()
            return
        }
        do {
            memberInfo = try await requestMemberInfo()
            appLog("[getMember] 刷新后重试成功")
        } catch {
            logError("[getMember] 刷新后重试仍失败", error)
        }
    }

    /// 统一打印错误：剥出 SessionTaskError 外壳，暴露底层类型 / 状态码 / 描述。
    private func logError(_ prefix: String, _ error: Error) {
        let underlying = error.ggUnderlying
        if let code = error.ggHTTPStatusCode {
            appLog("\(prefix)：HTTP \(code) - \(underlying.localizedDescription)")
        } else {
            appLog("\(prefix)：\(type(of: underlying)) - \(underlying)")
        }
    }

    @MainActor
    private func requestMemberInfo() async throws -> MemberInfo {
        let request = GraphQLRequest<Response<MemberInfo>>(
            query: """
                query getMemberProfileAndSim {
                  memberProfile {
                    id
                    memberName
                    __typename
                  }
                  sim {
                    phoneNumber
                    status
                    __typename
                  }
                }
                """, variables: [:])
        return try await Self.send(request).data
    }
}

extension OAuthService {
    private func fetchAccessToken(code: String) {
        let codeVerifier = UserDefaults().string(forKey: "codeVerifier")!
        let data = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuth.redirectUri,
            "code_verifier": codeVerifier,
        ]

        let request = AccessTokenRequest(
            clientId: OAuth.clientId, clientSecret: OAuth.clientSecret,
            data: data)
        Session.send(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.updateToken(response)
                case .failure(let error):
                    appLog("error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 用 refresh token 换取新的 access token。
    /// 复用抓包里唯一的 token 端点 /auth/oauth/token + Basic 认证，只把 grant_type 换成
    /// 标准的 refresh_token。成功则写回并持久化新 token；失败返回 nil（由调用方登出）。
    @MainActor
    private func refreshAccessToken(using token: OAuthToken) async -> OAuthToken? {
        // 已有刷新在进行中 → 复用同一结果，避免并发重复刷新。
        if let task = refreshTask { return await task.value }

        let clientId = OAuth.clientId
        let clientSecret = OAuth.clientSecret
        let refreshToken = token.refreshToken
        let task = Task { @MainActor () -> OAuthToken? in
            let request = AccessTokenRequest(
                clientId: clientId, clientSecret: clientSecret,
                data: [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                ])
            do {
                let newToken = try await Self.send(request)
                self.updateToken(newToken)
                appLog("[refresh] 刷新成功，新 token 有效期 \(newToken.expiresIn)s")
                return newToken
            } catch {
                self.logError("[refresh] 刷新失败", error)
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    /// 生成携带登录态的 SSO 落地 URL——把 App 的登录态带到 giffgaff 网页。
    ///
    /// 步骤对齐官方 App（Hermes bundle 反编译的 `toSsoUri`）：
    ///   1) POST /auth/v1/sso/code（Bearer）换一次性 `sso_code`；
    ///   2) 拼 https://id.giffgaff.com/auth/login/sso?code=<sso_code>&redirect_uri=<页面>。
    /// 该 URL 用 WKWebView 打开后，服务端消费一次性 code、种下 .giffgaff.com 会话 cookie，
    /// 再 302 跳到 redirectUri —— 落地页即为登录态。
    ///
    /// - Parameter redirectUri: 登录后要跳转到的 giffgaff 网页（如 payment-details）。
    @MainActor
    func makeSsoURL(redirectUri: String) async throws -> URL {
        let code = try await Self.send(SsoCodeRequest()).ssoCode
        var comps = URLComponents(string: "https://id.giffgaff.com/auth/login/sso")!
        comps.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
        ]
        guard let url = comps.url else {
            throw GiffgaffError(message: "无法拼出 SSO URL")
        }
        return url
    }

    /// 把 APIKit 回调式的 Session.send 包成 async/await。
    private static func send<R: Request>(_ request: R) async throws -> R.Response {
        try await withCheckedThrowingContinuation { continuation in
            Session.send(request) { result in
                continuation.resume(with: result)
            }
        }
    }

    func updateToken(_ token: OAuthToken?) {
        self.oauthToken = token
        appLog("oauthToken is empty: \(token == nil)")
        do {
            if let token {
                let token = try JSONEncoder().encode(token)
                UserDefaults.standard.set(
                    token, forKey: Constants.kTokenStorageKey)
            } else {
                UserDefaults.standard.removeObject(
                    forKey: Constants.kTokenStorageKey)
            }
        } catch {
            appLog("UserDefaults save token error: \(error)")
        }
    }

    func signout() {
        UserDefaults.standard.set(nil, forKey: Constants.kTokenStorageKey)
        self.isLogin = false
        self.oauthToken = nil
        self.memberInfo = nil
    }

    
    private func getToken() -> OAuthToken? {
        guard
            let tokenData = UserDefaults.standard.data(forKey: Constants.kTokenStorageKey)
        else {
            return nil
        }
        do {
            // 过期不在这里拦截：冷启动照常返回缓存 token，由 getMember 里
            // 「本地判过期→先刷新」+「401→刷新重试」的链路保证其有效。
            return try JSONDecoder().decode(OAuthToken.self, from: tokenData)
        } catch {
            appLog("UserDefaults get token error: \(error)")
            return nil
        }
    }
}
