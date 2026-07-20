//
//  Contants.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/21.
//

import Foundation

enum Constants {
    static let kClientIdKey = "kClientIdKey"
    static let kClientSecretKey = "kClientSecretKey"
    
    static let kTokenStorageKey = "kTokenStorageKey"
    static let kGuideDocURLKey = "kGuideDocURLKey"

    /// 官方「管理 / 添加支付方式」页。经 `/auth/login/sso` 落地，用 WKWebView 打开即带登录态。
    static let paymentDetailsURL = "https://www.giffgaff.com/profile/payment-details"

    /// 网页收银台（Web Checkout）落地页。官方 App「有卡一键支付」正是跳到这里：
    /// 抓包（Stream-2026-07-26 21:36:16）里 SSO 的 redirect_uri 即为
    ///   https://www.giffgaff.com/app/payment?iphone-app=1&app=1&orderId=<orderId>
    /// 页面在登录态下列出已绑卡，用户点选即可一键付款。`iphone-app=1&app=1` 为固定的
    /// App 内标识（来自抓包，用户无关，固定写死），`orderId` 为下单接口返回的订单号。
    static func webCheckoutURL(orderId: String) -> String {
        "https://www.giffgaff.com/app/payment?iphone-app=1&app=1&orderId=\(orderId)"
    }
}
