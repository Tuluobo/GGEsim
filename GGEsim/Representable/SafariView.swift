//
//  SafariView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    typealias UIViewControllerType = SFSafariViewController
    
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

#Preview {
    SafariView(url: URL(string: "https://baidu.com")!)
}
