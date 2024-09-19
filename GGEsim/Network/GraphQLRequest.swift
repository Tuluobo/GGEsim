//
//  GraphQLRequest.swift
//  GGEsim
//
//  Created by Tuluobo on 9/18/24.
//

import Foundation
import APIKit

struct GiffgaffError: Error {
    let message: String
}

struct Response<T: Decodable>: Decodable {
    let data: T
}

struct MemberInfo: Codable {
    let memberProfile: MemberProfile
    let sim: SimInfo
}

struct MemberProfile: Codable {
    let id: String
    let memberName: String
}

struct SimInfo: Codable {
    let phoneNumber: String
    let status: String
}


struct GraphQLRequest<T: Decodable>: Request {
    typealias Response = T
    
    let query: String
    let variables: [String: Any]
    
    let baseURL = URL(string: "https://publicapi.giffgaff.com")!
    let method = HTTPMethod.post
    let path = "/gateway/graphql"
    
    var bodyParameters: (any BodyParameters)? {
        return JSONBodyParameters(JSONObject: ["query": query, "variables": variables])
    }
}

