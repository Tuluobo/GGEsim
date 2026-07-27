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
    @StateObject private var topUpService = TopUpService()

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
    /// 当前要打开的网页 sheet（绑卡 / 网页收银台）。非空即弹出 WKWebView。
    @State private var webSheet: WebSheet?
    /// 正在换一次性 code、拼绑卡 SSO 链接。
    @State private var isPreparingBindCard = false
    /// sheet 关闭后的回调（绑卡→刷新支付方式；收银台→取 eSIM 出码）。
    @State private var onWebSheetDismiss: () -> Void = {}

    /// 统一的网页 sheet：绑卡与网页收银台都走同一套 WKWebView（避免 iOS 14 多 sheet 冲突）。
    private enum WebSheet: Identifiable {
        case bindCard(URL)   // 绑定 / 管理支付方式
        case checkout(URL)   // 网页收银台，用已绑卡付款

        var id: String {
            switch self {
            case .bindCard(let u): return "bind-\(u.absoluteString)"
            case .checkout(let u): return "pay-\(u.absoluteString)"
            }
        }
        var url: URL {
            switch self {
            case .bindCard(let u), .checkout(let u): return u
            }
        }
        var title: String {
            switch self {
            case .bindCard: return "绑定支付方式"
            case .checkout: return "支付并激活"
            }
        }
    }

    var body: some View {
        Spacer()
        VStack(spacing: 20) {
            if let lpa = topUpService.esimLPAString {
                // 支付激活成功、eSIM 可下载：只展示二维码，用户自行扫码由系统完成下载激活
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
        // 收银台 URL 由 startWebCheckout 异步产出，产出即弹出收银台 sheet。
        // 付款结果由 giffgaff://payment 回跳驱动（见下方 onPaymentReturn）。
        // 任意方式关闭（giffgaff:// 回跳 / 用户手动「完成」/ 下滑）都会走 onDismiss，
        // 统一刷新当前页（重新拉取已绑支付方式与状态）。
        .onChange(of: topUpService.webCheckoutURL) { newURL in
            guard let url = newURL else { return }
            onWebSheetDismiss = { topUpService.loadPaymentMethods() }
            webSheet = .checkout(url)
            topUpService.webCheckoutURL = nil
        }
        .sheet(item: $webSheet, onDismiss: { onWebSheetDismiss() }) { sheet in
            switch sheet {
            case .bindCard(let url):
                BindCardSheet(url: url, title: sheet.title)
            case .checkout(let url):
                BindCardSheet(url: url, title: sheet.title) { success, reason in
                    // 网页收银台回跳：成功→取 eSIM 出码；失败→提示原因。
                    if success {
                        topUpService.fetchESimForDownload()
                    } else {
                        topUpService.markPaymentFailed(reason: reason)
                    }
                }
            }
        }
    }

    /// 打开「绑定 / 管理支付方式」：先用登录态换一次性 SSO 链接，再用 WKWebView 打开。
    /// 登录态经 `/auth/v1/sso/code` → `/auth/login/sso` 带到网页（对齐官方 App）。
    private func openBindCard() {
        guard !isPreparingBindCard else { return }
        isPreparingBindCard = true
        onWebSheetDismiss = { topUpService.loadPaymentMethods() }
        Task {
            defer { isPreparingBindCard = false }
            do {
                let url = try await OAuthService.shared.makeSsoURL(
                    redirectUri: Constants.paymentDetailsURL
                )
                webSheet = .bindCard(url)
            } catch {
                // 换 code 失败兜底：仍打开目标页（未登录态，用户可自行登录），不卡死流程。
                appLog("[bindCard] 生成 SSO 链接失败: \(error.ggUnderlying)")
                if let fallback = URL(string: Constants.paymentDetailsURL) {
                    webSheet = .bindCard(fallback)
                }
            }
        }
    }

    // 订购区（未激活成功前）
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

            // 已绑定的银行卡 / 去绑定
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

            // 有可用银行卡才允许下单；否则 paymentMethodsSection 已给出“绑定”入口
            if topUpService.hasBoundCard {
                orderButton
            }
        }
    }

    // 下单 / 支付按钮：未预留 → 预留 eSIM；已预留 → 用已绑卡支付并激活
    @ViewBuilder
    private var orderButton: some View {
        let payCard = topUpService.boundCards.first
        let reserved = topUpService.state == .reserved
        Button {
            if reserved {
                // 有卡：下单 + 跳网页收银台，用已绑卡付款
                topUpService.startWebCheckout(memberId: memberInfo.memberProfile.id)
            } else {
                topUpService.startOnboarding(memberId: memberInfo.memberProfile.id)
            }
        } label: {
            Text(reserved
                 ? (topUpService.isPreparingCheckout
                    ? "正在打开收银台…"
                    : "用 \(payCard?.displayName ?? "已绑卡") 支付并激活")
                 : "订购 eSIM")
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(minWidth: 200)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(8)
        }
        .disabled(topUpService.isLoading || topUpService.isPreparingCheckout)
        .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
    }

    // 支付方式区：已绑银行卡则列出，未绑则给“绑定支付方式”按钮跳官网
    @ViewBuilder
    private var paymentMethodsSection: some View {
        if !topUpService.paymentMethodsLoaded {
            ProgressView()
                .padding(.vertical, 8)
        } else if !topUpService.hasBoundCard {
            VStack(spacing: 10) {
                Text("尚未绑定银行卡")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("订购前请先绑定一张 Visa / Mastercard 银行卡。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    openBindCard()
                } label: {
                    Label(isPreparingBindCard ? "正在打开…" : "绑定支付方式",
                          systemImage: "creditcard")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(minWidth: 200)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .disabled(isPreparingBindCard)
                .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
            }
            .frame(maxWidth: 280)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("支付方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(topUpService.boundCards) { method in
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
                    openBindCard()
                } label: {
                    Text(isPreparingBindCard ? "正在打开…" : "管理支付方式")
                        .font(.footnote)
                }
                .disabled(isPreparingBindCard)
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
        case .reserved:
            Text("已预留 eSIM，可用已绑卡支付并激活。")
                .font(.footnote).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
