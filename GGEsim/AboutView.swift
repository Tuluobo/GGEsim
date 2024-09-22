//
//  AboutView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/22.
//

import SwiftUI

struct AboutView: View {
    let dismissAction: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private let infoDictionary = Bundle.main.infoDictionary

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(UIColor.systemGray6))
                .ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    Spacer()
                    Button(action: {
                        dismissAction()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title)
                    }
                    .padding()
                }
                .padding(.bottom)

                Text("GGEsim")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("版本 \(infoDictionary?["CFBundleShortVersionString"] ?? "1.0.0")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Links
                VStack(spacing: 20) {
                    LinkButton(
                        title: "数字牧民社区", url: "https://shuzimumin.com",
                        icon: "globe")
                    LinkButton(
                        title: "GitHub",
                        url: "https://github.com/tuluobo/GGEsim",
                        icon: "chevron.left.forwardslash.chevron.right")
                    LinkButton(
                        title: "反馈问题", url: infoDictionary?[Constants.kGuideDocURLKey] as? String ?? "",
                        icon: "envelope")
                }
                .padding(.top, 20)
                
                Spacer()

                Text("© 2024 GGEsim. All rights reserved.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 30)
            }
            .padding()
        }
    }
}

struct LinkButton: View {
    let title: String
    let url: String
    let icon: String

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
    }
}

#Preview {
    AboutView {}
}
