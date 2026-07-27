package com.tuluobo.ggesim

import android.app.Application
import android.content.Context
import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.tuluobo.ggesim.data.CreditProduct
import com.tuluobo.ggesim.data.ESimReservation
import com.tuluobo.ggesim.data.GiffgaffGateway
import com.tuluobo.ggesim.data.HttpFailure
import com.tuluobo.ggesim.data.MemberInfo
import com.tuluobo.ggesim.data.MemberProfile
import com.tuluobo.ggesim.data.NoSimStage
import com.tuluobo.ggesim.data.OAuthToken
import com.tuluobo.ggesim.data.SavedPaymentMethod
import com.tuluobo.ggesim.data.SimInfo
import com.tuluobo.ggesim.ui.GGESimApp
import com.tuluobo.ggesim.ui.theme.GGESimTheme
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.util.Collections

@RunWith(AndroidJUnit4::class)
class GGESimFlowInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @After
    fun clearStoredTestToken() {
        ApplicationProvider.getApplicationContext<Application>()
            .getSharedPreferences("ggesim", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    @Test
    fun physicalSimCompletesMfaSwapAndDisplaysQrCode() {
        val gateway = FakeGateway(
            member = MemberInfo(
                memberProfile = MemberProfile("member-1", "test-member"),
                sim = SimInfo("07512345678", "STATUS_ACTIVE")
            )
        )
        val viewModel = testViewModel(gateway)
        show(viewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.memberInfo != null }
        composeRule.onNodeWithText("Hi, test-member").assertIsDisplayed()
        composeRule.onNodeWithText("07512345678").assertIsDisplayed()
        composeRule.onNodeWithText("Active").assertIsDisplayed()
        composeRule.onNodeWithText("Apply eSIM").performScrollTo().assertIsDisplayed().performClick()

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.verificationOpen }
        composeRule.onNodeWithText("Verification").assertExists()
        composeRule.onNodeWithText("发送").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.mfaRef == "mfa-ref" }
        composeRule.onNodeWithText("输入验证码").performTextInput("123456")
        composeRule.onNodeWithText("Submit").performClick()

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.simSwapLpa == TEST_LPA }
        composeRule.onNodeWithText("LPA: $TEST_LPA").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Your eSIM is ready!").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("eSIM QR code").assertIsDisplayed()
        assertCallsInOrder(
            gateway.calls,
            "member:access-token",
            "mfaChallenge",
            "verify:mfa-ref:123456",
            "reserve:SWITCH",
            "swap",
            "downloadable",
            "download:swap-ssn"
        )
    }

    @Test
    fun noSimCompletesReservationCheckoutReturnAndDisplaysQrCode() {
        val gateway = FakeGateway(
            member = MemberInfo(MemberProfile("member-2", "new-member"), null),
            methods = listOf(
                SavedPaymentMethod(
                    id = "card-1",
                    isDefault = true,
                    kind = SavedPaymentMethod.Kind.Card("4242", "VISA", expired = false)
                )
            )
        )
        val viewModel = testViewModel(gateway)
        show(viewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.paymentMethodsLoaded }
        composeRule.onNodeWithText("当前账号还没有 SIM 卡").assertIsDisplayed()
        composeRule.onNodeWithText("Visa •••• 4242").assertIsDisplayed()
        composeRule.onNodeWithText("默认").assertIsDisplayed()
        composeRule.onNodeWithText("订购 eSIM").performScrollTo().assertIsDisplayed().performClick()

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.noSimStage == NoSimStage.RESERVED }
        composeRule.onNodeWithText("£10.00").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("已预留 eSIM，可用已绑卡支付并激活。").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("用 Visa •••• 4242 支付并激活")
            .performScrollTo()
            .assertIsDisplayed()
            .performClick()

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.browserSession != null }
        composeRule.onNodeWithText("支付并激活").assertIsDisplayed()
        composeRule.runOnIdle {
            assertTrue(viewModel.handlePaymentUrl("giffgaff://payment?status=success"))
        }

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.noSimLpa == TEST_LPA }
        composeRule.onNodeWithText("Your eSIM is ready!").assertIsDisplayed()
        composeRule.onNodeWithText("LPA: $TEST_LPA").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithContentDescription("eSIM QR code").performScrollTo().assertIsDisplayed()
        assertCallsInOrder(
            gateway.calls,
            "member:access-token",
            "paymentMethods",
            "reserve:ONBOARD_NEW",
            "products:onboard-ssn",
            "order:onboard-ssn:1000",
            "sso",
            "download:onboard-ssn"
        )
    }

    @Test
    fun paymentReturnAfterRecreationRestoresOrderAndDisplaysQrCode() {
        val firstGateway = FakeGateway(
            member = MemberInfo(MemberProfile("member-5", "new-member"), null)
        )
        val firstViewModel = testViewModel(firstGateway)
        show(firstViewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) { firstViewModel.memberInfo != null }
        composeRule.runOnIdle { firstViewModel.startOnboarding() }
        composeRule.waitUntil(timeoutMillis = 5_000) {
            firstViewModel.noSimStage == NoSimStage.RESERVED
        }

        val restoredGateway = FakeGateway(
            member = MemberInfo(
                MemberProfile("member-5", "activated-member"),
                SimInfo("07512345678", "STATUS_ACTIVE")
            )
        )
        val restoredViewModel = testViewModel(restoredGateway)
        show(restoredViewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) {
            restoredViewModel.memberInfo != null && restoredViewModel.reservation != null
        }
        composeRule.runOnIdle {
            assertTrue(restoredViewModel.handlePaymentUrl("giffgaff://payment?status=success"))
        }

        composeRule.waitUntil(timeoutMillis = 5_000) { restoredViewModel.noSimLpa == TEST_LPA }
        composeRule.onNodeWithText("Your eSIM is ready!").assertIsDisplayed()
        composeRule.onNodeWithText("LPA: $TEST_LPA").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithContentDescription("eSIM QR code").performScrollTo().assertIsDisplayed()
        assertFalse(restoredGateway.calls.any { it.startsWith("reserve:") })
        assertCallsInOrder(
            restoredGateway.calls,
            "member:access-token",
            "download:onboard-ssn"
        )
        assertNull(
            ApplicationProvider.getApplicationContext<Application>()
                .getSharedPreferences("ggesim", Context.MODE_PRIVATE)
                .getString("pending_onboarding", null)
        )
    }

    @Test
    fun unauthorizedMemberRequestRefreshesOnceAndRetries() {
        val gateway = FakeGateway(
            member = MemberInfo(MemberProfile("member-3", "refresh-member"), null),
            unauthorizedMemberRequests = 1
        )
        val viewModel = testViewModel(gateway)
        show(viewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) { viewModel.memberInfo != null }
        composeRule.onNodeWithText("Hi, refresh-member").assertIsDisplayed()
        assertCallsInOrder(
            gateway.calls,
            "member:access-token",
            "refresh:refresh-token",
            "member:refreshed-access-token"
        )
    }

    @Test
    fun failedRefreshClearsSessionAndReturnsToLogin() {
        val gateway = FakeGateway(
            member = MemberInfo(MemberProfile("member-4", "expired-member"), null),
            unauthorizedMemberRequests = 1,
            refreshFails = true
        )
        val viewModel = testViewModel(gateway)
        show(viewModel)

        composeRule.waitUntil(timeoutMillis = 5_000) {
            !viewModel.tokenAvailable && !viewModel.isMemberLoading
        }
        composeRule.onNodeWithText("Login").assertIsDisplayed()
        assertCallsInOrder(
            gateway.calls,
            "member:access-token",
            "refresh:refresh-token"
        )
    }

    @Test
    fun oauthCallbackLoadsMemberWithoutRestart() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        application.getSharedPreferences("ggesim", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .putString("code_verifier", "pkce-verifier")
            .putString("oauth_state", "expected-state")
            .commit()
        val gateway = FakeGateway(
            member = MemberInfo(MemberProfile("member-6", "new-login"), null)
        )
        val viewModel = GGESimViewModel(
            application = application,
            api = gateway,
            now = { Instant.parse("2026-07-27T12:00:00Z") },
            initialToken = null
        )
        show(viewModel)

        composeRule.runOnIdle {
            viewModel.handleDeepLink(
                "giffgaff://auth/callback/?code=auth-code&state=expected-state".toUri()
            )
        }

        composeRule.waitUntil(timeoutMillis = 5_000) {
            viewModel.memberInfo != null && !viewModel.isMemberLoading
        }
        composeRule.onNodeWithText("Hi, new-login").assertIsDisplayed()
        assertTrue(viewModel.tokenAvailable)
        assertCallsInOrder(
            gateway.calls,
            "exchange:auth-code:pkce-verifier",
            "member:access-token"
        )
    }

    private fun testViewModel(gateway: FakeGateway): GGESimViewModel = GGESimViewModel(
        application = ApplicationProvider.getApplicationContext<Application>(),
        api = gateway,
        now = { Instant.parse("2026-07-27T12:00:00Z") },
        initialToken = validToken()
    )

    private fun show(viewModel: GGESimViewModel) {
        viewModel.dismissNetworkDialog()
        composeRule.activity.setContent {
            GGESimTheme {
                GGESimApp(viewModel)
            }
        }
    }

    private fun assertCallsInOrder(calls: List<String>, vararg expected: String) {
        var previous = -1
        expected.forEach { call ->
            val index = calls.indexOf(call)
            assertTrue("Missing or out-of-order call '$call' in $calls", index > previous)
            previous = index
        }
    }

    private fun validToken() = OAuthToken(
        type = "Bearer",
        accessToken = "access-token",
        refreshToken = "refresh-token",
        expiresIn = 3_600,
        expiresAtMillis = Long.MAX_VALUE
    )

    private class FakeGateway(
        private val member: MemberInfo,
        private val methods: List<SavedPaymentMethod> = emptyList(),
        unauthorizedMemberRequests: Int = 0,
        private val refreshFails: Boolean = false
    ) : GiffgaffGateway {
        val calls: MutableList<String> = Collections.synchronizedList(mutableListOf())
        private var remainingUnauthorizedMemberRequests = unauthorizedMemberRequests

        override fun exchangeAuthorizationCode(code: String, verifier: String): OAuthToken =
            token().also { calls += "exchange:$code:$verifier" }

        override fun refreshToken(refreshToken: String): OAuthToken {
            calls += "refresh:$refreshToken"
            if (refreshFails) throw HttpFailure(401, "refresh rejected")
            return token("refreshed-access-token")
        }

        override fun memberInfo(accessToken: String): MemberInfo {
            calls += "member:$accessToken"
            if (remainingUnauthorizedMemberRequests > 0) {
                remainingUnauthorizedMemberRequests -= 1
                throw HttpFailure(401, "access token expired")
            }
            return member
        }

        override fun requestMfaChallenge(accessToken: String): String = "mfa-ref".also {
            calls += "mfaChallenge"
        }

        override fun verifyMfaCode(accessToken: String, ref: String, code: String): String =
            "mfa-signature".also { calls += "verify:$ref:$code" }

        override fun reserveESim(
            accessToken: String,
            memberId: String,
            userIntent: String
        ): ESimReservation {
            calls += "reserve:$userIntent"
            val ssn = if (userIntent == "SWITCH") "reserved-swap-ssn" else "onboard-ssn"
            return ESimReservation(
                id = "reservation",
                memberId = memberId,
                status = "RESERVED",
                esim = ESimReservation.ReservedESim(
                    ssn = ssn,
                    activationCode = "activation-code",
                    deliveryStatus = "RESERVED",
                    associatedMemberId = memberId
                )
            )
        }

        override fun swapSim(
            accessToken: String,
            activationCode: String,
            mfaSignature: String,
            mfaRef: String
        ): String = "swap-ssn".also { calls += "swap" }

        override fun downloadableESims(accessToken: String) {
            calls += "downloadable"
        }

        override fun eSimDownloadToken(accessToken: String, ssn: String): String = TEST_LPA.also {
            calls += "download:$ssn"
        }

        override fun paymentMethods(accessToken: String): List<SavedPaymentMethod> = methods.also {
            calls += "paymentMethods"
        }

        override fun creditProducts(accessToken: String, ssn: String): List<CreditProduct> = listOf(
            CreditProduct("CR0010", "£10", 1_000, "CREDIT", emptyList())
        ).also { calls += "products:$ssn" }

        override fun createActivationOrder(
            accessToken: String,
            ssn: String,
            amountInPence: Int
        ): String = "order-1".also { calls += "order:$ssn:$amountInPence" }

        override fun ssoUrl(accessToken: String, redirectUri: String): String =
            "https://example.com/checkout".also { calls += "sso" }

        private fun token(accessToken: String = "access-token") = OAuthToken(
            type = "Bearer",
            accessToken = accessToken,
            refreshToken = "refresh-token",
            expiresIn = 3_600,
            expiresAtMillis = Long.MAX_VALUE
        )
    }

    private companion object {
        const val TEST_LPA = "LPA:1-HOST-MATCH"
    }
}
