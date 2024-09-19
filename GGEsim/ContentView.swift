//
//  ContentView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var oauthService = OAuthService.shared
    @State private var showWebView = false
    
    var body: some View {
        VStack {
            if oauthService.oauthToken != nil {
                Text("Welcome! You're logged in.")
                if let memberInfo = oauthService.memberInfo {
                    Text("用户名：\(memberInfo.memberProfile.memberName)")
                    Text("手机号码：\(memberInfo.sim.phoneNumber)")
                    Text("手机状态：\(memberInfo.sim.status)")
                }
            } else {
                Button("Login") {
                    showWebView = true
                }
                .sheet(isPresented: $showWebView) {
                    SafariView(url: oauthService.startOAuthFlow())
                }
            }
        }
        .padding()
        .onOpenURL { url in
            showWebView = false
            oauthService.handleCallback(url: url)
        }
        .onChange(of: oauthService.oauthToken) { [oauthService] newValue in
            if newValue != nil {
                oauthService.getMember()
            }
        }
        .onAppear {
            oauthService.getMember()
        }
    }
}

#Preview {
    ContentView()
}
