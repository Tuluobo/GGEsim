//
//  WebLoginView.swift
//  GGEsim
//
//  应用内 WKWebView：用于打开「携带登录态」的 giffgaff 网页（绑卡 / 管理支付方式 / 网页收银台）。
//
//  为什么不用 SFSafariViewController：
//    SFSafariViewController 是沙箱浏览器，既不共享 App 的 URLSession cookie，
//    也不允许注入 header/cookie，而我们的 App 是用 Bearer token 认证的、
//    从没在浏览器里建立过 .giffgaff.com 的网页会话 —— 所以 Safari 永远是未登录态。
//
//  正确做法（对齐官方 App）：先用 access token 换一次性 sso_code，拼出
//    https://id.giffgaff.com/auth/login/sso?code=...&redirect_uri=...
//  用本 WKWebView 打开；服务端消费一次性 code、种下会话 cookie 并 302 跳到目标页。
//  WKWebView 默认使用持久化的共享 cookie 存储，登录态因此得以保留。
//
//  支付完成后如何回到 App（对齐官方 App 的 handlePaymentUrl）：
//    网页收银台以 iphone-app=1&app=1 打开后，付款完成会把 WebView 导航到
//      giffgaff://payment?status=success           （成功）
//      giffgaff://payment?status=<非success>&reason=… （失败）
//    官方 App 就是拦截 startsWith("giffgaff://payment") 的导航、关闭浏览器、读 status。
//    这里用 WKNavigationDelegate 拦 giffgaff:// scheme：取消该次网页加载，
//    解析 status/reason，回调上层（成功→取 eSIM 出码；失败→提示原因）。
//

import SwiftUI
import WebKit

struct WebLoginView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    let url: URL
    /// 支付回跳回调：`success` 来自 giffgaff://payment 的 status=success，`reason` 为失败原因。
    /// 绑卡等纯浏览场景传 nil（不会命中 giffgaff://payment，也就不会触发）。
    var onPaymentReturn: ((_ success: Bool, _ reason: String?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaymentReturn: onPaymentReturn)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 默认持久化数据存储：cookie 在本 App 的 WKWebView 之间共享并落盘。
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onPaymentReturn: ((Bool, String?) -> Void)?

        init(onPaymentReturn: ((Bool, String?) -> Void)?) {
            self.onPaymentReturn = onPaymentReturn
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // 拦自定义 scheme：giffgaff://payment... 是支付回跳；WKWebView 本身也打不开它。
            if let url = navigationAction.request.url, url.scheme == "giffgaff" {
                decisionHandler(.cancel)
                if url.absoluteString.hasPrefix("giffgaff://payment") {
                    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let status = comps?.queryItems?.first { $0.name == "status" }?.value
                    let reason = comps?.queryItems?.first { $0.name == "reason" }?.value
                    onPaymentReturn?(status == "success", reason)
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// 绑卡 / 管理支付方式 / 网页收银台的 sheet 容器：内嵌 `WebLoginView`，顶部给一个「完成」按钮。
/// - 纯浏览（绑卡）：关闭后由调用方在 `onDismiss` 里刷新已绑支付方式。
/// - 网页收银台：传入 `onPaymentReturn`，付款回跳时自动关闭本页并把结果回调上层。
struct BindCardSheet: View {
    let url: URL
    var title: String = "绑定支付方式"
    var onPaymentReturn: ((_ success: Bool, _ reason: String?) -> Void)? = nil
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            WebLoginView(url: url) { success, reason in
                // 支付回跳：先关闭收银台页，再把结果交给上层处理。
                presentationMode.wrappedValue.dismiss()
                onPaymentReturn?(success, reason)
            }
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarTitle(title, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
