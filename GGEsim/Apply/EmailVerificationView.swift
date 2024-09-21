//
//  EmailVerificationView.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import SwiftUI

struct EmailVerificationView: View {
    @ObservedObject var service: ApplyEsimService
    @State private var verificationCode: String = ""
    @State private var countdown: Int = 60
    @State private var isCountingDown = false

    var body: some View {
        VStack(spacing: 20) {
            VStack {
                Text("Email Verification")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Enter the verification code sent to your email")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack {
                    if service.isLoading {
                        ProgressView()
                    }
                    if !service.loadingMessage.isEmpty {
                        Text(service.loadingMessage)
                            .foregroundColor(.red)
                    }
                }.padding(.top, 20)
            }
            .padding(.vertical, 20)

            HStack(spacing: 10) {
                TextField("输入验证码", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .frame(height: 50)
                    .padding(.horizontal)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                    .disabled(service.isLoading || service.emailCodeRef == nil)

                Button(action: {
                    service.sendEmailVerification()
                    startCountdown()
                }) {
                    Text(isCountingDown ? "\(countdown)s" : "发送")
                        .frame(width: 80, height: 50)
                        .background(
                            isCountingDown ? Color.gray : Color.accentColor
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .animation(.easeInOut, value: isCountingDown)
                }
                .disabled(service.isLoading || isCountingDown)
            }
            .padding(.horizontal)

            Button(action: {
                service.verifyEmailCode(verificationCode: verificationCode)
            }) {
                Text("Submit")
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(
                service.isLoading || service.emailCodeRef == nil || verificationCode.count != 6
            )
        }
        .padding()
    }

    private func startCountdown() {
        isCountingDown = true
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                isCountingDown = false
                timer.invalidate()
            }
        }
    }
}

#Preview {
    EmailVerificationView(service: ApplyEsimService())
}
