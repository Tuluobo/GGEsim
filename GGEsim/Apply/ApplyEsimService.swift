//
//  ApplyEsimService.swift
//  GGEsim
//
//  Created by Tuluobo on 2024/9/17.
//

import APIKit
import Foundation
import SwiftUI

class ApplyEsimService: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = ""
    
    @Published var emailCodeRef: String?
    @Published var emailSignature: String?

    @Published var esim: String?

    func sendEmailVerification() {
        isLoading = true
        loadingMessage = "Sending email code ..."

        let request = SendEmailCodeRequest()
        Session.send(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let response):
                    self.emailCodeRef = response.ref
                    self.loadingMessage = ""
                case .failure(let error):
                    self.loadingMessage = "Failed to send email verification: \(error.localizedDescription)"
                }
            }
        }
    }

    func verifyEmailCode(verificationCode: String) {
        isLoading = true
        loadingMessage = "Verifying email code ..."

        let request = VerifyEmailCodeRequest(
            ref: emailCodeRef ?? "", code: verificationCode)
        Session.send(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let response):
                    self.emailSignature = response.signature
                    self.loadingMessage = ""
                case .failure(let error):
                    self.loadingMessage = "Failed to verify email code: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func verifyTime() -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        guard let hour = components.hour, let minute = components.minute else {
            return false
        }
        
        let currentMinutes = hour * 60 + minute
        let startMinutes = 4 * 60 + 30  // 4:30 AM
        let endMinutes = 21 * 60 + 30   // 9:30 PM
        
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes
    }

    func apply(emailSignature: String, memberProfile: MemberProfile) {
        Task {
            do {
                try await self.applyInner(
                    emailSignature: emailSignature,
                    memberProfile: memberProfile
                )
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.loadingMessage = "Failed to apply esim: \(error.localizedDescription)"
                }
            }
        }
    }

    func applyInner(emailSignature: String, memberProfile: MemberProfile) async throws {
        DispatchQueue.main.async {
            self.isLoading = true
            self.loadingMessage = "Started apply esim ..."
        }

        // Step 1: Reserve eSIM
        let reserveESimQuery = """
            mutation reserveESim($input: ESimReservationInput!) {
              reserveESim: reserveESim(input: $input) {
                id
                memberId
                reservationStartDate
                reservationEndDate
                status
                esim {
                  ssn
                  activationCode
                  deliveryStatus
                  associatedMemberId
                  __typename
                }
                __typename
              }
            }
            """
        let reserveESimVariables: [String: Any] = [
            "input": [
                "memberId": memberProfile.id,
                "userIntent": "SWITCH",
            ]
        ]

        let reserveESimRequest = GraphQLRequest<Response<ReserveESimData>>(query: reserveESimQuery, variables: reserveESimVariables)
        let reserveESimResponse = try await Session.response(for: reserveESimRequest)
        let esim = reserveESimResponse.data.reserveESim.esim
        DispatchQueue.main.async {
            self.loadingMessage = "Reserved SIM succeed."
        }

        // Step 2: Swap SIM
        let swapSimQuery = """
            mutation SwapSim($activationCode: String!, $mfaSignature: String!) {
              swapSim(activationCode: $activationCode, mfaSignature: $mfaSignature) {
                old {
                  ssn
                  activationCode
                  __typename
                }
                new {
                  ssn
                  activationCode
                  __typename
                }
                __typename
              }
            }
            """

        let swapSimVariables: [String: Any] = [
            "activationCode": esim.activationCode,
            "mfaSignature": emailSignature,
        ]
        let swapSimRequest = GraphQLRequest<Response<SwapSimData>>(query: swapSimQuery, variables: swapSimVariables)
        let swapSimResponse = try await Session.response(for: swapSimRequest)
        DispatchQueue.main.async {
            self.loadingMessage = "Swap SIM succeed."
        }

        // Step 3: Get eSIMs
        let getESimStatusQuery = """
        query getESims($deliveryStatus: ESimDeliveryStatus!) {
          eSims(deliveryStatus: $deliveryStatus) {
            ssn
            __typename
          }
        }
        """
        let getESimStatusRequest = GraphQLRequest<Response<GetESimsData>>(query: getESimStatusQuery, variables: ["deliveryStatus": "DOWNLOADABLE"])
        _ = try await Session.response(for: getESimStatusRequest)
        DispatchQueue.main.async {
            self.loadingMessage = "Get eSIM succeed."
        }
        
        // Step 4: Get eSIM download token
        let eSimDownloadTokenQuery = """
            query eSimDownloadToken($ssn: String!) {
              eSimDownloadToken(ssn: $ssn) {
                id
                host
                matchingId
                lpaString
                __typename
              }
            }
            """
        let eSimDownloadTokenVariables: [String: Any] = [
            "ssn": swapSimResponse.data.swapSim.new.ssn
        ]
        let eSimDownloadTokenRequest = GraphQLRequest<Response<ESimDownloadTokenData>>(query: eSimDownloadTokenQuery, variables: eSimDownloadTokenVariables)
        let eSimDownloadTokenResponse = try await Session.response(for: eSimDownloadTokenRequest)
        DispatchQueue.main.async {
            self.isLoading = false
            self.loadingMessage = "Apply eSIM succeed."
            self.esim = eSimDownloadTokenResponse.data.eSimDownloadToken.lpaString
        }
    }
}

struct ESim: Codable {
    let ssn: String
    let activationCode: String
}

// Add these structures to handle the responses
struct ReserveESimData: Codable {
    struct ReserveESim: Codable {
        let id: String
        let status: String
        let esim: ESim
    }

    let reserveESim: ReserveESim
}

struct SwapSimData: Codable {
    struct SwapSim: Codable {
        let old: ESim
        let new: ESim
    }

    let swapSim: SwapSim
}

struct GetESimsData: Codable {
    struct ESim: Codable {
        let ssn: String
    }
    
    let eSims: [ESim]
}

struct ESimDownloadTokenData: Codable {
    struct ESimDownloadToken: Codable {
        let id: String
        let host: String
        let matchingId: String
        let lpaString: String
    }

    let eSimDownloadToken: ESimDownloadToken
}
