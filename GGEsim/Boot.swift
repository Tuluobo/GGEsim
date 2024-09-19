//
//  Boot.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI
import UIKit
import Network

class AppDelegate: NSObject, UIApplicationDelegate {
    
    private var networkMonitor: NWPathMonitor?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        startNetworkMonitoring()
        return true
    }
    
    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
        networkMonitor?.pathUpdateHandler = { path in
            if path.status == .satisfied {
                print("网络连接正常")
            } else {
                print("网络连接不可用")
            }
        }
    }
}

@main
struct Boot: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(OAuthService.shared)
        }
    }
}
