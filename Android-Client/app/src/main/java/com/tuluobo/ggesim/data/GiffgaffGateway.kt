package com.tuluobo.ggesim.data

interface GiffgaffGateway {
    fun exchangeAuthorizationCode(code: String, verifier: String): OAuthToken
    fun refreshToken(refreshToken: String): OAuthToken
    fun memberInfo(accessToken: String): MemberInfo
    fun requestMfaChallenge(accessToken: String): String
    fun verifyMfaCode(accessToken: String, ref: String, code: String): String
    fun reserveESim(accessToken: String, memberId: String, userIntent: String): ESimReservation
    fun swapSim(
        accessToken: String,
        activationCode: String,
        mfaSignature: String,
        mfaRef: String
    ): String
    fun downloadableESims(accessToken: String)
    fun eSimDownloadToken(accessToken: String, ssn: String): String
    fun paymentMethods(accessToken: String): List<SavedPaymentMethod>
    fun creditProducts(accessToken: String, ssn: String): List<CreditProduct>
    fun createActivationOrder(accessToken: String, ssn: String, amountInPence: Int): String
    fun ssoUrl(accessToken: String, redirectUri: String): String
}
