//
//  LoginView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/20.
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var oauthService: OAuthService
    @State private var showOAuthView = false
    @State private var showAboutView = false
    
    var body: some View {
        VStack {
            // Logo
            VStack {
                Text("Giffgaff")
                    .fontWeight(.bold)
                    .font(.largeTitle)
                    .scaleEffect(.init(width: 1.8, height: 1.8))
                    .padding(4)
                Text("We’re up to good")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 200)
            .padding(.bottom, 100)
            // 登录按钮
            Button(action: {
                showOAuthView = true
            }) {
                Text("Login")
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(showOAuthView)
            .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            
            Spacer()
            
            Button {
                showAboutView = true
            } label: {
                Label {
                    Text("About GGEsim")
                        .padding(.horizontal, -4)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .foregroundColor(.primary)
                .font(.footnote)
            }
            .padding(8)
        }
        .sheet(isPresented: $showOAuthView) {
            SafariView(url: oauthService.startOAuthFlow())
        }
        .fullScreenCover(isPresented: $showAboutView) {
            AboutView() {
                showAboutView = false
            }
        }
        .onOpenURL { url in
            showOAuthView = false
            oauthService.handleCallback(url: url)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(OAuthService.shared)
}
