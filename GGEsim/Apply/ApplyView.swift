//
//  ContentView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI

struct ApplyView: View {
    @EnvironmentObject private var oauthService: OAuthService
    @StateObject private var applyEsimService = ApplyEsimService()

    @State private var showEmailVerification = false

    var body: some View {
        VStack {
            if let memberInfo = oauthService.memberInfo {
                // 头部，用户信息
                HeadView(memberInfo: memberInfo)
                    .padding(.top, 40)
                Spacer()
                
                // ESIM 信息
                ESimView(applyEsimService: applyEsimService)
                Spacer()

                // 申请
                Button {
                    if let emailSignature = applyEsimService.emailSignature {
                        applyEsimService.apply(
                            emailSignature: emailSignature,
                            memberProfile: memberInfo.memberProfile
                        )
                    } else {
                        showEmailVerification = true
                    }
                } label: {
                    Text("Apply eSIM")
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .disabled(applyEsimService.isLoading || applyEsimService.esim != nil)
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
                .padding(.bottom, 32)
            } else {
                Button {
                    oauthService.getMember()
                } label: {
                    Text("状态异常，手动刷新")
                        .foregroundColor(.black)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
            }
        }
        .onChange(of: applyEsimService.emailSignature) { [applyEsimService] newValue in
            if let newValue {
                showEmailVerification = false
                applyEsimService.apply(
                    emailSignature: newValue,
                    memberProfile: oauthService.memberInfo!.memberProfile
                )
            }
        }
        .sheet(isPresented: $showEmailVerification) {
            EmailVerificationView(service: applyEsimService)
        }
    }
}

#Preview {
    ApplyView()
        .environmentObject({
            let oauthService = OAuthService.shared
            oauthService.memberInfo = MemberInfo(
                memberProfile: MemberProfile(id: "88888888", memberName: "preview"),
                sim: SimInfo(phoneNumber: "07512345678", status: "STATUS_ACTIVE")
            )
            return oauthService
        }())
}

struct HeadView: View {
    
    let memberInfo: MemberInfo
    
    var body: some View {
        VStack(spacing: 16) {
            Image("avatar_default")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
                .shadow(radius: 5)
            
            VStack(spacing: 8) {
                Text("Hi, \(memberInfo.memberProfile.memberName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\(memberInfo.sim.phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(
                    memberInfo.sim.status.replacingOccurrences(
                        of: "STATUS_", with: ""
                    ).capitalized
                )
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
                
                Text("Welcome! You're logged in.")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding(.top, 8)
            }
        }
    }
}

struct ESimView: View {
    
    @ObservedObject var applyEsimService: ApplyEsimService
    @State private var showGuideDocs = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("eSIM Info")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 20)
            
            
            if let esim = applyEsimService.esim {
                VStack(spacing: 15) {
                    Text("Your eSIM is ready!")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Image(uiImage: generateQRCode(from: esim))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
                    
                    Text("LPA: \(esim)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                Spacer()
                if applyEsimService.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        Text(applyEsimService.loadingMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .cornerRadius(10)
                } else if !applyEsimService.loadingMessage.isEmpty {
                    Text(applyEsimService.loadingMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("No eSIM applied yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            Spacer()
            // 指南
            Button {
                showGuideDocs = true
            } label: {
                Text("点击查看使用常见问题")
                    .font(.subheadline)
            }
        }
        .frame(width: 240)
        .padding()
        .background(Color.primary.opacity(0.1))
        .cornerRadius(15)
        .sheet(isPresented: $showGuideDocs) {
            SafariView(
                url: URL(string: Bundle.main.infoDictionary?[Constants.kGuideDocURLKey] as! String)!
            )
        }
    }
}
