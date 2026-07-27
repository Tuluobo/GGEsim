//
//  ContentView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var oauthService: OAuthService
    
    var body: some View {
        VStack {
            if oauthService.isLogin {
                // 正在登陆
                ProgressView()
                Text("Loading ... ")
            } else {
                // 未登录或者登录结束
                if oauthService.oauthToken == nil {
                    // 未登录
                    LoginView()
                    Spacer()
                } else {
                    // 已登录，申请页面
                    ApplyView()
                }
            }
        }
        .onChange(of: oauthService.oauthToken) { [oauthService] _ in
            oauthService.getMember()
        }
        .onAppear {
            if oauthService.memberInfo == nil {
                oauthService.getMember()
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(OAuthService.shared)
}
