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
    @StateObject private var topUpService = TopUpService(
        cardEncrypter: AdyenPaymentController.shared,
        threeDSHandler: AdyenPaymentController.shared
    )

    @State private var showVerification = false
    @State private var showAlertView = false
    @State private var showAboutView = false

    var body: some View {
        VStack {
            if let memberInfo = oauthService.memberInfo {
                if memberInfo.sim == nil {
                    // 无实体卡：走今天抓包的「申请新 eSIM」流程（TopUpService），没有验证码
                    NoSimView(
                        memberInfo: memberInfo,
                        topUpService: topUpService
                    )
                } else {
                    // 有实体卡：走之前的 SIM swap 流程（含验证码）
                    loggedInContent(memberInfo: memberInfo)
                }
            } else {
                Spacer()
                VStack(spacing: 16) {
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
                Spacer()
            }

            // 只要已登录（有 token），都提供退出入口
            if oauthService.oauthToken != nil {
                Button {
                    oauthService.signout()
                } label: {
                    Text("退出当前账号")
                        .foregroundColor(Color.accentColor)
                        .font(.footnote)
                }
                .padding(.bottom, 4)
            }

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
            .padding(.bottom, 8)
        }
        .onChange(of: applyEsimService.mfaSignature) { [applyEsimService] newValue in
            if let newValue, let mfaRef = applyEsimService.mfaRef {
                showVerification = false
                applyEsimService.apply(
                    mfaSignature: newValue,
                    mfaRef: mfaRef,
                    memberProfile: oauthService.memberInfo!.memberProfile
                )
            }
        }
         .alert(isPresented: $showAlertView) {
             Alert(
                 title: Text("Application Time Restriction"),
                 message: Text("eSIM applications are only accepted between 4:30am and 9:30pm (GMT+1). Please try again during these hours."),
                 dismissButton: .default(Text("OK"))
             )
         }
        .sheet(isPresented: $showVerification) {
            VerificationView(service: applyEsimService)
        }
        .fullScreenCover(isPresented: $showAboutView) {
            AboutView() {
                showAboutView = false
            }
        }
    }

    // 已登录且有实体卡时的主内容
    @ViewBuilder
    private func loggedInContent(memberInfo: MemberInfo) -> some View {
        // 头部，用户信息
        HeadView(memberInfo: memberInfo)
            .padding(.top, 40)
        Spacer()

        // ESIM 信息
        ESimView(applyEsimService: applyEsimService)
        Spacer()

        // 申请
        VStack {
            Button {
                startApply(memberProfile: memberInfo.memberProfile)
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

            Text("Between 4:30am and 9:30pm(GMT+1).")
                .font(.footnote)
                .opacity(0.7)
        }
        .padding()
    }

    // 有实体卡：转 eSIM（SIM swap 流程，需验证码）
    private func startApply(memberProfile: MemberProfile) {
        if !applyEsimService.verifyTime() {
            showAlertView = true
        } else if let mfaSignature = applyEsimService.mfaSignature,
                  let mfaRef = applyEsimService.mfaRef {
            applyEsimService.apply(
                mfaSignature: mfaSignature,
                mfaRef: mfaRef,
                memberProfile: memberProfile
            )
        } else {
            showVerification = true
        }
    }
}

#Preview("Has SIM") {
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

#Preview("No SIM") {
    ApplyView()
        .environmentObject({
            let oauthService = OAuthService.shared
            oauthService.memberInfo = MemberInfo(
                memberProfile: MemberProfile(id: "37396773", memberName: "moon3033"),
                sim: nil
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

                if let sim = memberInfo.sim {
                    Text("\(sim.phoneNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(
                        sim.status.replacingOccurrences(
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
}

/// 当前账号没有实体卡时的界面：走今天抓包的「申请新 eSIM」流程（TopUpService），无验证码。
struct NoSimView: View {

    let memberInfo: MemberInfo
    @ObservedObject var topUpService: TopUpService
    @State private var showCardPage = false
    @State private var showDeleteCardAlert = false
    @State private var showPaymentDetailsPage = false

    var body: some View {
        Spacer()
        VStack(spacing: 20) {
            if let lpa = topUpService.esimLPAString {
                // 支付成功、eSIM 可下载：只展示二维码，用户自行扫码由系统完成下载激活
                esimQRSection(lpa: lpa)
            } else {
                orderSection
            }
        }
        .padding()
        Spacer()
        .onAppear {
            if !topUpService.paymentMethodsLoaded {
                topUpService.loadPaymentMethods()
            }
        }
        .sheet(isPresented: $showCardPage) {
            if let checkout = topUpService.checkout {
                CardPaymentView(
                    memberInfo: memberInfo,
                    checkout: checkout,
                    topUpService: topUpService
                )
            }
        }
        .sheet(isPresented: $showPaymentDetailsPage, onDismiss: {
            // 从官网绑卡返回后刷新已绑支付方式
            topUpService.loadPaymentMethods()
        }) {
            SafariView(url: URL(string: Constants.paymentDetailsURL)!)
        }
        .onChange(of: topUpService.state) { state in
            switch state {
            case .ready:
                // 准备好后弹出卡片信息页
                showCardPage = true
            case .authorised:
                // 支付成功：先问是否删除支付卡，再取二维码
                showDeleteCardAlert = true
            default:
                break
            }
        }
        .alert(isPresented: $showDeleteCardAlert) {
            Alert(
                title: Text("移除支付卡信息"),
                message: Text("是否删除本次使用的支付卡信息？"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        await topUpService.deletePaymentCard()
                        topUpService.fetchESimForDownload()
                    }
                },
                secondaryButton: .cancel(Text("保留")) {
                    topUpService.fetchESimForDownload()
                }
            )
        }
    }

    // 订购区（未支付成功前）
    private var orderSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "simcard.2")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("Hi, \(memberInfo.memberProfile.memberName)")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text("当前账号还没有 SIM 卡")
                    .font(.headline)

                Text("是否订购一张 eSIM？无需实体卡，激活后即可使用。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // 已绑定的支付方式 / 去绑定
            paymentMethodsSection

            // 展示默认套餐金额（£10，仅展示，不可选）
            if let product = topUpService.selectedProduct {
                HStack {
                    Text("充值金额")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(product.formattedPrice)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding()
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
                .frame(maxWidth: 260)
            }

            // 流程状态提示
            statusText

            // 有已绑支付方式才允许下单；否则只显示“绑定支付方式”
            if !topUpService.paymentMethods.isEmpty {
                Button {
                    if topUpService.selectedProduct == nil {
                        // 先预留 eSIM + 载入套餐
                        topUpService.startOnboarding(memberId: memberInfo.memberProfile.id)
                    } else {
                        // 已就绪，进入卡片信息页
                        topUpService.prepareCardCheckout()
                    }
                } label: {
                    Text("订购 eSIM")
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .disabled(topUpService.isLoading || topUpService.state == .authorised)
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            }
        }
    }

    // 支付方式区：已绑定则列出，未绑定则给“绑定支付方式”按钮跳官网
    @ViewBuilder
    private var paymentMethodsSection: some View {
        if !topUpService.paymentMethodsLoaded {
            ProgressView()
                .padding(.vertical, 8)
        } else if topUpService.paymentMethods.isEmpty {
            VStack(spacing: 10) {
                Text("尚未绑定支付方式")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button {
                    showPaymentDetailsPage = true
                } label: {
                    Label("绑定支付方式", systemImage: "creditcard")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            }
            .frame(maxWidth: 280)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("支付方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(topUpService.paymentMethods) { method in
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.accentColor)
                        Text(method.displayName)
                            .font(.subheadline)
                        if method.isDefault {
                            Text("默认")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                }
                Button {
                    showPaymentDetailsPage = true
                } label: {
                    Text("管理支付方式")
                        .font(.footnote)
                }
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(10)
            .frame(maxWidth: 280)
        }
    }

    // eSIM 二维码区（支付成功、可下载）
    private func esimQRSection(lpa: String) -> some View {
        VStack(spacing: 16) {
            Text("Your eSIM is ready!")
                .font(.headline)
                .foregroundColor(.green)

            Image(uiImage: generateQRCode(from: lpa))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)

            Text("用手机相机或「设置 > 蜂窝网络 > 添加 eSIM」扫描此二维码即可下载并激活。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("LPA: \(lpa)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch topUpService.state {
        case .loading(let msg):
            HStack(spacing: 8) {
                ProgressView()
                Text(msg).font(.footnote).foregroundColor(.secondary)
            }
        case .authorised:
            Text("支付成功 🎉")
                .font(.subheadline).foregroundColor(.green)
        case .refused(let reason):
            Text(reason).font(.footnote).foregroundColor(.red)
                .multilineTextAlignment(.center)
        case .failed(let reason):
            Text(reason).font(.footnote).foregroundColor(.red)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
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
