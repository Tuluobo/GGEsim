//
//  CardPaymentView.swift
//  GGEsim
//
//  无实体卡申请 eSIM 的「卡片信息页」：填写姓名 + 账单地址 + 卡片，
//  提交后调用 TopUpService.payWithCard 完成下单→授权→3DS→补充动作。
//
//  说明：卡片字段的 Adyen 加密与 3DS 挑战需由 Adyen iOS SDK 产出，
//  当前注入的是默认桩（未接 SDK 前提交会提示未集成），链路本身已串通。
//

import SwiftUI

struct CardPaymentView: View {
    let memberInfo: MemberInfo
    let checkout: TopUpCheckout
    @ObservedObject var topUpService: TopUpService

    @Environment(\.presentationMode) private var presentationMode

    // 姓名
    @State private var firstName = ""
    @State private var lastName = ""
    // 账单地址
    @State private var buildingNumber = ""
    @State private var street = ""
    @State private var postalCode = ""
    @State private var city = ""
    @State private var state = ""
    @State private var countryCode = "GB"
    // 卡片
    @State private var cardNumber = ""
    @State private var expiryMonth = ""
    @State private var expiryYear = ""
    @State private var securityCode = ""
    @State private var saveDetails = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("充值金额")) {
                    HStack {
                        Text(checkout.product.name)
                        Spacer()
                        Text(checkout.product.formattedPrice).fontWeight(.semibold)
                    }
                }

                Section(header: Text("持卡人")) {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }

                Section(header: Text("卡片信息")) {
                    TextField("Card number", text: $cardNumber)
                        .keyboardType(.numberPad)
                    HStack {
                        TextField("MM", text: $expiryMonth).keyboardType(.numberPad)
                        TextField("YY", text: $expiryYear).keyboardType(.numberPad)
                        TextField("CVC", text: $securityCode).keyboardType(.numberPad)
                    }
                }

                Section(header: Text("账单地址")) {
                    TextField("Building number", text: $buildingNumber)
                    TextField("Street", text: $street)
                    TextField("City", text: $city)
                    TextField("Postal code", text: $postalCode)
                    TextField("State (optional)", text: $state)
                    TextField("Country code", text: $countryCode)
                }

                Section {
                    Toggle("保存卡片与地址", isOn: $saveDetails)
                }

                if case .loading(let msg) = topUpService.state {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(msg).foregroundColor(.secondary)
                        }
                    }
                }
                if case .refused(let reason) = topUpService.state {
                    Section { Text(reason).foregroundColor(.red) }
                }
                if case .failed(let reason) = topUpService.state {
                    Section { Text(reason).foregroundColor(.red) }
                }
            }
            .navigationTitle("Card payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("支付") { submit() }
                        .disabled(!isValid || topUpService.isLoading)
                }
            }
            .onChange(of: topUpService.state) { newState in
                if newState == .authorised { presentationMode.wrappedValue.dismiss() }
            }
        }
    }

    private var isValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty
            && !cardNumber.isEmpty && expiryMonth.count == 2 && expiryYear.count == 2
            && !securityCode.isEmpty
            && !buildingNumber.isEmpty && !street.isEmpty && !city.isEmpty
            && !postalCode.isEmpty && countryCode.count == 2
    }

    private func submit() {
        let fullName = FullName(firstName: firstName, lastName: lastName)
        let address = BillingAddress(
            buildingNumber: buildingNumber,
            street: street,
            postalCode: postalCode,
            city: city,
            state: state.isEmpty ? nil : state,
            countryCode: countryCode
        )
        let card = CardInput(
            number: cardNumber,
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            securityCode: securityCode,
            holderName: "\(firstName) \(lastName)"
        )
        topUpService.payWithCard(
            memberId: memberInfo.memberProfile.id,
            fullName: fullName,
            billingAddress: address,
            card: card,
            saveBillingAddress: saveDetails
        )
    }
}
