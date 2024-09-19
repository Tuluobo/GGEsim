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
    @StateObject private var applyEsimService = ApplyEsimService()

    @State private var showWebView = false
    @State private var showEmailVerification = false
    
    var body: some View {
        VStack {
            if oauthService.oauthToken != nil {
                Text("Welcome! You're logged in.")
                if let memberInfo = oauthService.memberInfo {
                    VStack {
                        Text("用户名：\(memberInfo.memberProfile.memberName)")
                        Text("手机号码：\(memberInfo.sim.phoneNumber)")
                        Text("手机状态：\(memberInfo.sim.status)")
                    }.padding()
                    
                    // 申请
                    if applyEsimService.esim == nil {
                        Button {
                            if let emailSignature = applyEsimService.emailSignature
                            {
                                applyEsimService.apply(
                                    emailSignature: emailSignature,
                                    memberProfile: memberInfo.memberProfile)
                            } else {
                                showEmailVerification = true
                            }
                        } label: {
                            Text("Apply Esim")
                        }.sheet(isPresented: $showEmailVerification) {
                            EmailVerificationView(service: applyEsimService)
                        }.disabled(applyEsimService.isLoading)
                    }
                    
                    // 展示
                    if applyEsimService.isLoading {
                        ProgressView()
                        Text(applyEsimService.loadingMessage)
                    } else if let esim = applyEsimService.esim {
                        Text("LPA: ")
                        Text(esim)
                        Image(uiImage: generateQRCode(from: esim))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    } else if !applyEsimService.loadingMessage.isEmpty {
                        Text(applyEsimService.loadingMessage)
                    }
                } else {
                    Button {
                        oauthService.getMember()
                    } label: {
                        Text("刷新")
                    }
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
        }.onChange(of: applyEsimService.emailSignature) {
            [applyEsimService] newValue in
            if let newValue {
                showEmailVerification = false
                applyEsimService.apply(
                    emailSignature: newValue,
                    memberProfile: oauthService.memberInfo!.memberProfile)
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
