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

    var body: some View {
        VStack {
            if service.isLoading {
                ProgressView()
            } else if service.emailCodeRef != nil {
                TextField("Verification Code", text: $verificationCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)

                Button("Submit") {
                    service.verifyEmailCode(verificationCode: verificationCode)
                }
            } else {
                Button("Send Email Verification") {
                    service.sendEmailVerification()
                }
            }

            if !service.loadingMessage.isEmpty {
                Text(service.loadingMessage)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

#Preview {
    EmailVerificationView(service: ApplyEsimService())
}
