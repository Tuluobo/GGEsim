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

enum Constants {
    static let kTokenStorageKey = "kTokenStorageKey"
    static let kClientIdKey = "kClientIdKey"
    static let kClientSecretKey = "kClientSecretKey"
}

class OAuthService: ObservableObject {
    @Published var oauthToken: OAuthToken?
    @Published var memberInfo: MemberInfo?

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
        return components.url!
    }

    func handleCallback(url: URL) {
        print("Callback url: \(url)")
        guard
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
        else {
            print("Error: No code found in callback URL")
            return
        }

        fetchAccessToken(code: code)
    }

    func getMember() {
        guard oauthToken != nil else { return }

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
        Session.send(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("self.memberInfo: \(response.data)")
                    self.memberInfo = response.data
                case .failure(let error):
                    print("error: \(error.localizedDescription)")
                }
            }
        }
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

        let request = AccessTokenRequest(clientId: OAuth.clientId, clientSecret: OAuth.clientSecret, data: data)
        Session.send(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.updateToken(response)
                case .failure(let error):
                    print("error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func updateToken(_ token: OAuthToken?) {
        self.oauthToken = token
        print("oauthToken is empty: \(token == nil)")
        do {
            if let token {
                let token = try JSONEncoder().encode(token)
                UserDefaults.standard.set(token, forKey: Constants.kTokenStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.kTokenStorageKey)
            }
        } catch {
            print("UserDefaults save token error: \(error)")
        }
    }

    @discardableResult
    private func getToken() -> OAuthToken? {
        guard let tokenData = UserDefaults.standard.data(forKey: Constants.kTokenStorageKey) else {
            return nil
        }
        do {
            let token = try JSONDecoder().decode(OAuthToken.self, from: tokenData)
            return token
        } catch {
            print("UserDefaults get token error: \(error)")
            return nil
        }
    }
}
