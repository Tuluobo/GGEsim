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

    /// Adyen live client key（抓包所得，App 内置常量）
    static let adyenClientKey = "live_JFQERMU4E5ESPF3IWTUIXRQ5HMK5LJHE"
    /// 支付完成后 Adyen 重定向回 App 的 URL scheme
    static let paymentReturnUrl = "giffgaff://payment-redirect"
    /// 官方「管理 / 添加支付方式」页（跳系统浏览器，SFSafariViewController 共享 cookie 带登录态）
    static let paymentDetailsURL = "https://www.giffgaff.com/profile/payment-details"
}
