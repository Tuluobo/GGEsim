package com.tuluobo.ggesim.data

import com.tuluobo.ggesim.BuildConfig
import com.tuluobo.ggesim.util.AppLogger
import okhttp3.Credentials
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.JavaNetCookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.CookieManager
import java.net.CookiePolicy

class GiffgaffApi(
    identityBase: String = DEFAULT_IDENTITY_BASE,
    publicApiBase: String = DEFAULT_PUBLIC_API_BASE,
    private val clientId: String = BuildConfig.GGESIM_CLIENT_ID,
    private val clientSecret: String = BuildConfig.GGESIM_CLIENT_SECRET
) : GiffgaffGateway {
    private val identityBase = identityBase.trimEnd('/')
    private val publicApiBase = publicApiBase.trimEnd('/')
    private val cookieManager = CookieManager(null, CookiePolicy.ACCEPT_ALL)
    private val client = OkHttpClient.Builder()
        .cookieJar(JavaNetCookieJar(cookieManager))
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    override fun exchangeAuthorizationCode(code: String, verifier: String): OAuthToken = tokenRequest(
        FormBody.Builder()
            .add("grant_type", "authorization_code")
            .add("code", code)
            .add("redirect_uri", REDIRECT_URI)
            .add("code_verifier", verifier)
            .build()
    )

    override fun refreshToken(refreshToken: String): OAuthToken = tokenRequest(
        FormBody.Builder()
            .add("grant_type", "refresh_token")
            .add("refresh_token", refreshToken)
            .build()
    )

    private fun tokenRequest(form: FormBody): OAuthToken {
        requireConfigured()
        val request = Request.Builder()
            .url("$identityBase/auth/oauth/token")
            .header("Authorization", Credentials.basic(clientId, clientSecret))
            .post(form)
            .build()
        return OAuthToken.fromJson(executeJson(request))
    }

    override fun memberInfo(accessToken: String): MemberInfo {
        val data = graphQl(
            accessToken,
            """
            query getMemberProfileAndSim {
              memberProfile { id memberName __typename }
              sim { phoneNumber status __typename }
            }
            """.trimIndent()
        )
        val profile = data.getJSONObject("memberProfile")
        val sim = if (data.isNull("sim")) null else data.getJSONObject("sim").let {
            SimInfo(it.getString("phoneNumber"), it.getString("status"))
        }
        return MemberInfo(
            MemberProfile(profile.getString("id"), profile.getString("memberName")),
            sim
        )
    }

    override fun requestMfaChallenge(accessToken: String): String {
        val data = graphQl(
            accessToken,
            """
            mutation simSwapMfaChallenge {
              simSwapMfaChallenge {
                ref
                methods { value channel __typename }
                __typename
              }
            }
            """.trimIndent(),
            JSONObject().put("deliveryStatus", "DOWNLOADABLE")
        )
        return data.getJSONObject("simSwapMfaChallenge").getString("ref")
    }

    override fun verifyMfaCode(accessToken: String, ref: String, code: String): String {
        val body = JSONObject().put("ref", ref).put("code", code)
        val request = authenticatedRequest("$identityBase/v4/mfa/validation", accessToken)
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        return executeJson(request).getString("signature")
    }

    override fun reserveESim(accessToken: String, memberId: String, userIntent: String): ESimReservation {
        val variables = JSONObject().put(
            "input",
            JSONObject().put("memberId", memberId).put("userIntent", userIntent)
        )
        val data = graphQl(
            accessToken,
            """
            mutation reserveESim(${'$'}input: ESimReservationInput!) {
              reserveESim: reserveESim(input: ${'$'}input) {
                id memberId reservationStartDate reservationEndDate status
                esim { ssn activationCode deliveryStatus associatedMemberId __typename }
                __typename
              }
            }
            """.trimIndent(),
            variables
        ).getJSONObject("reserveESim")
        val esim = data.getJSONObject("esim")
        return ESimReservation(
            id = data.getString("id"),
            memberId = data.optString("memberId", memberId),
            status = data.getString("status"),
            esim = ESimReservation.ReservedESim(
                ssn = esim.getString("ssn"),
                activationCode = esim.getString("activationCode"),
                deliveryStatus = esim.nullableString("deliveryStatus"),
                associatedMemberId = esim.nullableString("associatedMemberId")
            )
        )
    }

    override fun swapSim(
        accessToken: String,
        activationCode: String,
        mfaSignature: String,
        mfaRef: String
    ): String {
        val variables = JSONObject()
            .put("activationCode", activationCode)
            .put("mfaSignature", mfaSignature)
            .put("mfaRef", mfaRef)
        val data = graphQl(
            accessToken,
            """
            mutation SwapSim(${'$'}activationCode: String!, ${'$'}mfaSignature: String!, ${'$'}mfaRef: String) {
              swapSim(activationCode: ${'$'}activationCode, mfaSignature: ${'$'}mfaSignature, mfaRef: ${'$'}mfaRef) {
                old { ssn activationCode __typename }
                new { ssn activationCode __typename }
                __typename
              }
            }
            """.trimIndent(),
            variables
        )
        return data.getJSONObject("swapSim").getJSONObject("new").getString("ssn")
    }

    override fun downloadableESims(accessToken: String) {
        graphQl(
            accessToken,
            """
            query getESims(${'$'}deliveryStatus: ESimDeliveryStatus!) {
              eSims(deliveryStatus: ${'$'}deliveryStatus) { ssn __typename }
            }
            """.trimIndent(),
            JSONObject().put("deliveryStatus", "DOWNLOADABLE")
        )
    }

    override fun eSimDownloadToken(accessToken: String, ssn: String): String {
        val data = graphQl(
            accessToken,
            """
            query eSimDownloadToken(${'$'}ssn: String!) {
              eSimDownloadToken(ssn: ${'$'}ssn) { id host matchingId lpaString __typename }
            }
            """.trimIndent(),
            JSONObject().put("ssn", ssn)
        )
        return data.getJSONObject("eSimDownloadToken").getString("lpaString")
    }

    override fun paymentMethods(accessToken: String): List<SavedPaymentMethod> {
        val nodes = graphQl(
            accessToken,
            """
            query getPaymentMethods {
              paymentMethods: paymentMethods {
                default __typename
                ... on Paypal { email __typename }
                ... on Card { id lastDigits type expired expiryDate __typename }
              }
            }
            """.trimIndent()
        ).getJSONArray("paymentMethods")
        return buildList {
            for (index in 0 until nodes.length()) {
                val node = nodes.getJSONObject(index)
                when (node.getString("__typename")) {
                    "Card" -> add(
                        SavedPaymentMethod(
                            id = node.optString("id", "card-$index"),
                            isDefault = node.optBoolean("default"),
                            kind = SavedPaymentMethod.Kind.Card(
                                lastDigits = node.getString("lastDigits"),
                                type = node.nullableString("type"),
                                expired = node.optBoolean("expired")
                            )
                        )
                    )
                    "Paypal" -> add(
                        SavedPaymentMethod(
                            id = node.optString("id", node.getString("email")),
                            isDefault = node.optBoolean("default"),
                            kind = SavedPaymentMethod.Kind.Paypal(node.getString("email"))
                        )
                    )
                }
            }
        }
    }

    override fun creditProducts(accessToken: String, ssn: String): List<CreditProduct> {
        val variables = JSONObject()
            .put("ssn", ssn)
            .put("extraFields", "metadata.upsellProducts,metadata.oldAllowance,metadata.aggregates")
        val nodes = graphQl(
            accessToken,
            """
            query getPurchasableProducts(${'$'}tags: [String], ${'$'}ssn: String, ${'$'}extraFields: [String]) {
              purchasableProducts(tags: ${'$'}tags, ssn: ${'$'}ssn, extraFields: ${'$'}extraFields) {
                id name description iconRef category priceInPence tags __typename
              }
            }
            """.trimIndent(),
            variables
        ).getJSONArray("purchasableProducts")
        return buildList {
            for (index in 0 until nodes.length()) {
                val node = nodes.getJSONObject(index)
                if (node.getString("category") != "CREDIT") continue
                val tags = node.optJSONArray("tags") ?: JSONArray()
                add(
                    CreditProduct(
                        id = node.getString("id"),
                        name = node.getString("name"),
                        priceInPence = node.getInt("priceInPence"),
                        category = node.getString("category"),
                        tags = List(tags.length()) { tags.getString(it) }
                    )
                )
            }
        }
    }

    override fun createActivationOrder(accessToken: String, ssn: String, amountInPence: Int): String {
        val input = JSONObject()
            .put("topupAmountInPence", amountInPence)
            .put("deviceChannel", "app")
            .put("ssn", ssn)
        val data = graphQl(
            accessToken,
            """
            mutation createActivationOrder(${'$'}input: SimActivationOrderInput!) {
              createActivationOrder(input: ${'$'}input) { order { id __typename } __typename }
            }
            """.trimIndent(),
            JSONObject().put("input", input)
        )
        return data.getJSONObject("createActivationOrder").getJSONObject("order").getString("id")
    }

    override fun ssoUrl(accessToken: String, redirectUri: String): String {
        val request = authenticatedRequest("$identityBase/auth/v1/sso/code", accessToken)
            .post("{}".toRequestBody(JSON_MEDIA_TYPE))
            .build()
        val code = executeJson(request).getString("sso_code")
        return "$identityBase/auth/login/sso".toHttpUrl().newBuilder()
            .addQueryParameter("code", code)
            .addQueryParameter("redirect_uri", redirectUri)
            .build()
            .toString()
    }

    private fun graphQl(
        accessToken: String,
        query: String,
        variables: JSONObject = JSONObject()
    ): JSONObject {
        val body = JSONObject().put("query", query).put("variables", variables)
        val request = authenticatedRequest("$publicApiBase/gateway/graphql", accessToken)
            .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
            .build()
        val response = executeJson(request)
        val errors = response.optJSONArray("errors")
        if (errors != null && errors.length() > 0 && response.isNull("data")) {
            throw IllegalStateException(errors.getJSONObject(0).optString("message", "GraphQL request failed"))
        }
        return response.getJSONObject("data")
    }

    private fun authenticatedRequest(url: String, accessToken: String): Request.Builder =
        Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $accessToken")
            // These identify the captured official client contract, not GGEsim's own build metadata.
            .header("x-gg-app-os", "iOS")
            .header("x-gg-app-os-version", "26.1")
            .header("x-gg-app-build-number", "722")
            .header("x-gg-app-device-manufacturer", "Apple")
            .header("x-gg-app-version", "17.54.1")
            .header("x-gg-app-device-model", "iPhone")
            .header("x-gg-app-device-id", "iPhone17,1")
            .header("Accept", "application/json")

    private fun executeJson(request: Request): JSONObject {
        AppLogger.log("[HTTP] ${request.method} ${request.url}")
        return client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            AppLogger.log("[HTTP] ${response.code} ${request.url.encodedPath}")
            if (!response.isSuccessful) {
                val message = runCatching {
                    JSONObject(text).optString("error_description").ifBlank { text }
                }.getOrDefault(text).ifBlank { "HTTP ${response.code}" }
                throw HttpFailure(response.code, message)
            }
            runCatching { JSONObject(text) }.getOrElse {
                throw IllegalStateException("Invalid server response", it)
            }
        }
    }

    private fun requireConfigured() {
        check(clientId.isNotBlank() && clientSecret.isNotBlank()) {
            "请先配置 GGESIM_CLIENT_ID 和 GGESIM_CLIENT_SECRET"
        }
    }

    private fun JSONObject.nullableString(name: String): String? =
        if (has(name) && !isNull(name)) getString(name) else null

    companion object {
        const val REDIRECT_URI = "giffgaff://auth/callback/"
        const val PAYMENT_DETAILS_URL = "https://www.giffgaff.com/profile/payment-details"
        private const val DEFAULT_IDENTITY_BASE = "https://id.giffgaff.com"
        private const val DEFAULT_PUBLIC_API_BASE = "https://publicapi.giffgaff.com"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

        fun webCheckoutUrl(orderId: String): String =
            "https://www.giffgaff.com/app/payment?iphone-app=1&app=1&orderId=$orderId"
    }
}
