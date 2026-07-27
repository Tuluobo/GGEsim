package com.tuluobo.ggesim

import com.tuluobo.ggesim.data.GiffgaffApi
import com.tuluobo.ggesim.data.HttpFailure
import com.tuluobo.ggesim.data.SavedPaymentMethod
import okhttp3.Credentials
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class GiffgaffApiTest {
    private lateinit var server: MockWebServer
    private lateinit var api: GiffgaffApi

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        val base = server.url("/").toString()
        api = GiffgaffApi(
            identityBase = base,
            publicApiBase = base,
            clientId = "client-id",
            clientSecret = "client-secret"
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `member query sends captured client contract and parses nullable SIM`() {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"memberProfile":{"id":"42","memberName":"moon"},"sim":null}}
                """.trimIndent()
            )
        )

        val member = api.memberInfo("access-token")
        val request = server.takeRequest()
        val body = JSONObject(request.body.readUtf8())

        assertEquals("/gateway/graphql", request.path)
        assertEquals("Bearer access-token", request.getHeader("Authorization"))
        assertEquals("17.54.1", request.getHeader("x-gg-app-version"))
        assertEquals("722", request.getHeader("x-gg-app-build-number"))
        assertTrue(body.getString("query").contains("getMemberProfileAndSim"))
        assertEquals("moon", member.memberProfile.memberName)
        assertEquals(null, member.sim)
    }

    @Test
    fun `HTTP failures retain status and backend description`() {
        server.enqueue(
            MockResponse().setResponseCode(401).setBody("{\"error_description\":\"token expired\"}")
        )

        val failure = runCatching { api.memberInfo("expired") }.exceptionOrNull() as HttpFailure

        assertEquals(401, failure.statusCode)
        assertEquals("token expired", failure.message)
    }

    @Test
    fun `cookies received from GraphQL are reused by later API calls`() {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .addHeader("Set-Cookie", "session=abc; Path=/")
                .setBody("{\"data\":{\"memberProfile\":{\"id\":\"42\",\"memberName\":\"moon\"},\"sim\":null}}")
        )
        server.enqueue(
            MockResponse().setResponseCode(200).setBody("{\"data\":{\"paymentMethods\":[]}}")
        )

        api.memberInfo("access")
        api.paymentMethods("access")
        server.takeRequest()
        val second = server.takeRequest()

        assertEquals("session=abc", second.getHeader("Cookie"))
    }

    @Test
    fun `authorization and refresh token requests preserve the OAuth contract`() {
        server.enqueue(tokenResponse("access-one", "refresh-one"))
        server.enqueue(tokenResponse("access-two", "refresh-two"))

        val exchanged = api.exchangeAuthorizationCode("auth-code", "pkce-verifier")
        val refreshed = api.refreshToken("refresh-one")
        val exchangeRequest = server.takeRequest()
        val refreshRequest = server.takeRequest()

        assertEquals("access-one", exchanged.accessToken)
        assertEquals("refresh-two", refreshed.refreshToken)
        assertEquals("/auth/oauth/token", exchangeRequest.path)
        assertEquals(Credentials.basic("client-id", "client-secret"), exchangeRequest.getHeader("Authorization"))
        assertEquals(
            "grant_type=authorization_code&code=auth-code&redirect_uri=giffgaff%3A%2F%2Fauth%2Fcallback%2F&code_verifier=pkce-verifier",
            exchangeRequest.body.readUtf8()
        )
        assertEquals("grant_type=refresh_token&refresh_token=refresh-one", refreshRequest.body.readUtf8())
    }

    @Test
    fun `physical SIM API sequence matches MFA reserve swap and download contracts`() {
        server.enqueue(jsonResponse("""{"data":{"simSwapMfaChallenge":{"ref":"mfa-ref"}}}"""))
        server.enqueue(jsonResponse("""{"signature":"mfa-signature"}"""))
        server.enqueue(
            jsonResponse(
                """{"data":{"reserveESim":{"id":"reservation-1","memberId":"member-1","status":"RESERVED","esim":{"ssn":"new-ssn","activationCode":"activation-code","deliveryStatus":"RESERVED","associatedMemberId":"member-1"}}}}"""
            )
        )
        server.enqueue(
            jsonResponse(
                """{"data":{"swapSim":{"old":{"ssn":"old-ssn","activationCode":"old-code"},"new":{"ssn":"new-ssn","activationCode":"activation-code"}}}}"""
            )
        )
        server.enqueue(jsonResponse("""{"data":{"eSims":[{"ssn":"new-ssn"}]}}"""))
        server.enqueue(jsonResponse("""{"data":{"eSimDownloadToken":{"id":"token-1","host":"host","matchingId":"match","lpaString":"LPA:1-HOST-MATCH"}}}"""))

        assertEquals("mfa-ref", api.requestMfaChallenge("access"))
        assertEquals("mfa-signature", api.verifyMfaCode("access", "mfa-ref", "123456"))
        val reservation = api.reserveESim("access", "member-1", "SWITCH")
        assertEquals("new-ssn", reservation.esim.ssn)
        assertEquals(
            "new-ssn",
            api.swapSim("access", reservation.esim.activationCode, "mfa-signature", "mfa-ref")
        )
        api.downloadableESims("access")
        assertEquals("LPA:1-HOST-MATCH", api.eSimDownloadToken("access", "new-ssn"))

        val challengeBody = requestBody()
        assertTrue(challengeBody.getString("query").contains("simSwapMfaChallenge"))
        assertEquals("DOWNLOADABLE", challengeBody.getJSONObject("variables").getString("deliveryStatus"))

        val verifyRequest = server.takeRequest()
        assertEquals("/v4/mfa/validation", verifyRequest.path)
        assertEquals("123456", JSONObject(verifyRequest.body.readUtf8()).getString("code"))

        val reserveInput = requestBody().getJSONObject("variables").getJSONObject("input")
        assertEquals("member-1", reserveInput.getString("memberId"))
        assertEquals("SWITCH", reserveInput.getString("userIntent"))

        val swapVariables = requestBody().getJSONObject("variables")
        assertEquals("activation-code", swapVariables.getString("activationCode"))
        assertEquals("mfa-signature", swapVariables.getString("mfaSignature"))
        assertEquals("mfa-ref", swapVariables.getString("mfaRef"))

        assertEquals("DOWNLOADABLE", requestBody().getJSONObject("variables").getString("deliveryStatus"))
        assertEquals("new-ssn", requestBody().getJSONObject("variables").getString("ssn"))
    }

    @Test
    fun `new eSIM API sequence parses cards products order and SSO redirect`() {
        server.enqueue(
            jsonResponse(
                """{"data":{"paymentMethods":[{"default":true,"__typename":"Card","id":"card-1","lastDigits":"4242","type":"VISA","expired":false},{"default":false,"__typename":"Card","id":"card-2","lastDigits":"0000","type":"MASTER_CARD","expired":true},{"default":false,"__typename":"Paypal","email":"member@example.com"}]}}"""
            )
        )
        server.enqueue(
            jsonResponse(
                """{"data":{"reserveESim":{"id":"reservation-2","memberId":"member-2","status":"RESERVED","esim":{"ssn":"onboard-ssn","activationCode":"onboard-code","deliveryStatus":null,"associatedMemberId":null}}}}"""
            )
        )
        server.enqueue(
            jsonResponse(
                """{"data":{"purchasableProducts":[{"id":"GB0010","name":"Bag","category":"GOODYBAG","priceInPence":1000,"tags":[]},{"id":"CR0010","name":"£10","category":"CREDIT","priceInPence":1000,"tags":["supportsAutoTopup"]},{"id":"CR0005","name":"£5","category":"CREDIT","priceInPence":500,"tags":[]}]}}"""
            )
        )
        server.enqueue(jsonResponse("""{"data":{"createActivationOrder":{"order":{"id":"order-1"}}}}"""))
        server.enqueue(jsonResponse("""{"sso_code":"sso-1"}"""))

        val methods = api.paymentMethods("access")
        val reservation = api.reserveESim("access", "member-2", "ONBOARD_NEW")
        val products = api.creditProducts("access", reservation.esim.ssn)
        val orderId = api.createActivationOrder("access", reservation.esim.ssn, 1_000)
        val checkout = GiffgaffApi.webCheckoutUrl(orderId)
        val ssoUrl = api.ssoUrl("access", checkout)

        assertEquals(3, methods.size)
        assertEquals(1, methods.count(SavedPaymentMethod::isUsableCard))
        assertEquals("Visa •••• 4242", methods.first().displayName)
        assertTrue(methods[1].displayName.endsWith("（已过期）"))
        assertEquals("PayPal member@example.com", methods[2].displayName)
        assertEquals(listOf("CR0010", "CR0005"), products.map { it.id })
        assertEquals("£10.00", products.first().formattedPrice)
        assertEquals("order-1", orderId)
        assertTrue(ssoUrl.contains("code=sso-1"))
        assertTrue(ssoUrl.contains("redirect_uri="))

        requestBody()
        val reserveInput = requestBody().getJSONObject("variables").getJSONObject("input")
        assertEquals("ONBOARD_NEW", reserveInput.getString("userIntent"))
        val productVariables = requestBody().getJSONObject("variables")
        assertEquals("onboard-ssn", productVariables.getString("ssn"))
        assertEquals(
            "metadata.upsellProducts,metadata.oldAllowance,metadata.aggregates",
            productVariables.getString("extraFields")
        )
        val orderInput = requestBody().getJSONObject("variables").getJSONObject("input")
        assertEquals(1_000, orderInput.getInt("topupAmountInPence"))
        assertEquals("app", orderInput.getString("deviceChannel"))
        assertEquals("onboard-ssn", orderInput.getString("ssn"))
        val ssoRequest = server.takeRequest()
        assertEquals("/auth/v1/sso/code", ssoRequest.path)
        assertEquals("{}", ssoRequest.body.readUtf8())
    }

    @Test
    fun `GraphQL errors without data are surfaced`() {
        server.enqueue(jsonResponse("""{"data":null,"errors":[{"message":"reservation unavailable"}]}"""))

        val failure = runCatching { api.reserveESim("access", "member", "SWITCH") }.exceptionOrNull()

        assertEquals("reservation unavailable", failure?.message)
    }

    private fun requestBody(): JSONObject = JSONObject(server.takeRequest().body.readUtf8())

    private fun tokenResponse(access: String, refresh: String): MockResponse = jsonResponse(
        """{"token_type":"Bearer","access_token":"$access","refresh_token":"$refresh","expires_in":3600}"""
    )

    private fun jsonResponse(body: String): MockResponse = MockResponse()
        .setResponseCode(200)
        .addHeader("Content-Type", "application/json")
        .setBody(body)
}
