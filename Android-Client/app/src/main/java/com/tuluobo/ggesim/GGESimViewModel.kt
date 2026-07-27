package com.tuluobo.ggesim

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.tuluobo.ggesim.data.BrowserKind
import com.tuluobo.ggesim.data.BrowserSession
import com.tuluobo.ggesim.data.CreditProduct
import com.tuluobo.ggesim.data.ESimReservation
import com.tuluobo.ggesim.data.GiffgaffApi
import com.tuluobo.ggesim.data.GiffgaffGateway
import com.tuluobo.ggesim.data.HttpFailure
import com.tuluobo.ggesim.data.MemberInfo
import com.tuluobo.ggesim.data.NoSimStage
import com.tuluobo.ggesim.data.OAuthToken
import com.tuluobo.ggesim.data.SavedPaymentMethod
import com.tuluobo.ggesim.util.AppLogger
import com.tuluobo.ggesim.util.Pkce
import com.tuluobo.ggesim.util.isWithinSimSwapWindow
import com.tuluobo.ggesim.util.parsePaymentReturn
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

class GGESimViewModel internal constructor(
    application: Application,
    private val api: GiffgaffGateway,
    private val now: () -> Instant,
    initialToken: OAuthToken? = null
) : AndroidViewModel(application) {
    constructor(application: Application) : this(application, GiffgaffApi(), Instant::now)

    private val preferences = application.getSharedPreferences("ggesim", Context.MODE_PRIVATE)
    private val refreshMutex = Mutex()
    private val connectivityManager = application.getSystemService(ConnectivityManager::class.java)
    private var currentToken: OAuthToken? = initialToken ?: restoreToken()

    var tokenAvailable by mutableStateOf(currentToken != null)
        private set
    var memberInfo by mutableStateOf<MemberInfo?>(null)
        private set
    var isMemberLoading by mutableStateOf(false)
        private set
    var memberError by mutableStateOf<String?>(null)
        private set
    var authError by mutableStateOf<String?>(null)
        private set

    var aboutOpen by mutableStateOf(false)
        private set
    var networkDialogVisible by mutableStateOf(false)
        private set
    var timeRestrictionVisible by mutableStateOf(false)
        private set

    var verificationOpen by mutableStateOf(false)
        private set
    var applyLoading by mutableStateOf(false)
        private set
    var applyMessage by mutableStateOf("")
        private set
    var mfaRef by mutableStateOf<String?>(null)
        private set
    private var mfaSignature: String? = null
    var simSwapLpa by mutableStateOf<String?>(null)
        private set

    var paymentMethods by mutableStateOf<List<SavedPaymentMethod>>(emptyList())
        private set
    var paymentMethodsLoaded by mutableStateOf(false)
        private set
    var reservation by mutableStateOf<ESimReservation?>(null)
        private set
    var selectedProduct by mutableStateOf<CreditProduct?>(null)
        private set
    var noSimStage by mutableStateOf(NoSimStage.IDLE)
        private set
    var noSimMessage by mutableStateOf("")
        private set
    var noSimLpa by mutableStateOf<String?>(null)
        private set
    var isPreparingBindCard by mutableStateOf(false)
        private set
    var isPreparingCheckout by mutableStateOf(false)
        private set
    var browserSession by mutableStateOf<BrowserSession?>(null)
        private set

    val boundCards: List<SavedPaymentMethod>
        get() = paymentMethods.filter(SavedPaymentMethod::isUsableCard)

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            viewModelScope.launch { networkDialogVisible = false }
        }

        override fun onLost(network: Network) {
            viewModelScope.launch { networkDialogVisible = !hasNetwork() }
        }
    }

    init {
        AppLogger.initialize(application)
        if (currentToken != null) restoreNoSimCheckpoint()
        networkDialogVisible = !hasNetwork()
        connectivityManager.registerDefaultNetworkCallback(networkCallback)
        if (currentToken != null) loadMember()
    }

    fun startOAuthFlow(): String? {
        authError = null
        if (BuildConfig.GGESIM_CLIENT_ID.isBlank() || BuildConfig.GGESIM_CLIENT_SECRET.isBlank()) {
            authError = "请先配置 GGESIM_CLIENT_ID 和 GGESIM_CLIENT_SECRET"
            return null
        }
        val verifier = Pkce.codeVerifier()
        val state = UUID.randomUUID().toString()
        preferences.edit {
            putString(KEY_CODE_VERIFIER, verifier)
            putString(KEY_OAUTH_STATE, state)
        }
        val authorize = "https://id.giffgaff.com/auth/oauth/authorize".toUri().buildUpon()
            .appendQueryParameter("client_id", BuildConfig.GGESIM_CLIENT_ID)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", "read")
            .appendQueryParameter("state", state)
            .appendQueryParameter("redirect_uri", GiffgaffApi.REDIRECT_URI)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("code_challenge", Pkce.codeChallenge(verifier))
            .build()
        return "https://www.giffgaff.com/auth/login".toUri().buildUpon()
            .appendQueryParameter("device", "app")
            .appendQueryParameter("redirect", authorize.toString())
            .build()
            .toString()
    }

    fun handleDeepLink(uri: Uri?) {
        if (uri == null || uri.scheme != "giffgaff") return
        AppLogger.log("Callback url: ${uri.toString().replace(Regex("code=[^&]+"), "code=<redacted>")}")
        if (uri.host == "payment") {
            parsePaymentReturn(uri.toString())?.let(::handlePaymentReturn)
            return
        }
        if (uri.host != "auth" || !uri.path.orEmpty().startsWith("/callback")) return
        val code = uri.getQueryParameter("code")
        val verifier = preferences.getString(KEY_CODE_VERIFIER, null)
        val expectedState = preferences.getString(KEY_OAUTH_STATE, null)
        val returnedState = uri.getQueryParameter("state")
        if (code.isNullOrBlank() || verifier.isNullOrBlank()) {
            authError = uri.getQueryParameter("error_description") ?: "OAuth 回调缺少授权码"
            return
        }
        if (expectedState.isNullOrBlank() || returnedState != expectedState) {
            authError = "OAuth 状态校验失败，请重新登录"
            return
        }
        isMemberLoading = true
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { api.exchangeAuthorizationCode(code, verifier) } }
                .onSuccess {
                    saveToken(it)
                    preferences.edit {
                        remove(KEY_CODE_VERIFIER)
                        remove(KEY_OAUTH_STATE)
                    }
                    isMemberLoading = false
                    loadMember()
                }
                .onFailure {
                    isMemberLoading = false
                    authError = "登录失败：${it.userMessage()}"
                    AppLogger.log("[OAuth] ${it.stackTraceToString()}")
                }
        }
    }

    fun loadMember() {
        if (currentToken == null || isMemberLoading) return
        isMemberLoading = true
        memberError = null
        viewModelScope.launch {
            runCatching { authenticated(api::memberInfo) }
                .onSuccess { info ->
                    memberInfo = info
                    isMemberLoading = false
                    AppLogger.log("[Member] member=${info.memberProfile.memberName} sim=${info.sim?.phoneNumber}")
                    if (info.sim == null) loadPaymentMethods()
                }
                .onFailure {
                    isMemberLoading = false
                    memberError = "获取账号状态失败：${it.userMessage()}"
                    AppLogger.log("[Member] ${it.stackTraceToString()}")
                }
        }
    }

    fun signOut() {
        currentToken = null
        preferences.edit {
            remove(KEY_TOKEN)
            remove(KEY_PENDING_ONBOARDING)
        }
        tokenAvailable = false
        memberInfo = null
        memberError = null
        resetFlows()
    }

    fun showAbout(show: Boolean) {
        aboutOpen = show
    }

    fun dismissAuthError() {
        authError = null
    }

    fun dismissNetworkDialog() {
        networkDialogVisible = false
    }

    fun dismissTimeRestriction() {
        timeRestrictionVisible = false
    }

    fun requestSimSwap() {
        val profile = memberInfo?.memberProfile ?: return
        if (!isWithinSimSwapWindow(now())) {
            timeRestrictionVisible = true
            return
        }
        val signature = mfaSignature
        val ref = mfaRef
        if (signature != null && ref != null) {
            applySimSwap(profile.id, signature, ref)
        } else {
            verificationOpen = true
        }
    }

    fun closeVerification() {
        if (!applyLoading) verificationOpen = false
    }

    fun sendVerificationCode() {
        if (applyLoading) return
        applyLoading = true
        applyMessage = "Sending code ..."
        viewModelScope.launch {
            runCatching { authenticated(api::requestMfaChallenge) }
                .onSuccess {
                    mfaRef = it
                    applyMessage = ""
                    applyLoading = false
                }
                .onFailure {
                    applyMessage = "Failed to send verification code: ${it.userMessage()}"
                    applyLoading = false
                }
        }
    }

    fun submitVerification(code: String) {
        val ref = mfaRef ?: return
        if (code.length != 6 || applyLoading) return
        applyLoading = true
        applyMessage = "Verifying code ..."
        viewModelScope.launch {
            runCatching { authenticated { api.verifyMfaCode(it, ref, code) } }
                .onSuccess { signature ->
                    mfaSignature = signature
                    applyMessage = ""
                    applyLoading = false
                    verificationOpen = false
                    memberInfo?.memberProfile?.id?.let { applySimSwap(it, signature, ref) }
                }
                .onFailure {
                    applyMessage = "Failed to verify code: ${it.userMessage()}"
                    applyLoading = false
                }
        }
    }

    private fun applySimSwap(memberId: String, signature: String, ref: String) {
        if (applyLoading) return
        applyLoading = true
        applyMessage = "Started apply esim ..."
        viewModelScope.launch {
            runCatching {
                val reserved = authenticated { api.reserveESim(it, memberId, "SWITCH") }
                applyMessage = "Reserved SIM succeed."
                val newSsn = authenticated {
                    api.swapSim(it, reserved.esim.activationCode, signature, ref)
                }
                applyMessage = "Swap SIM succeed."
                authenticated { api.downloadableESims(it) }
                applyMessage = "Get eSIM succeed."
                authenticated { api.eSimDownloadToken(it, newSsn) }
            }.onSuccess {
                simSwapLpa = it
                applyMessage = "Apply eSIM succeed."
                applyLoading = false
            }.onFailure {
                applyMessage = "Failed to apply esim: ${it.userMessage()}"
                applyLoading = false
                AppLogger.log("[SIM swap] ${it.stackTraceToString()}")
            }
        }
    }

    fun loadPaymentMethods() {
        if (!tokenAvailable) return
        viewModelScope.launch {
            runCatching { authenticated(api::paymentMethods) }
                .onSuccess {
                    paymentMethods = it
                    paymentMethodsLoaded = true
                }
                .onFailure {
                    paymentMethods = emptyList()
                    paymentMethodsLoaded = true
                    AppLogger.log("[Payment methods] ${it.stackTraceToString()}")
                }
        }
    }

    fun startOnboarding() {
        val memberId = memberInfo?.memberProfile?.id ?: return
        if (noSimStage == NoSimStage.LOADING) return
        noSimStage = NoSimStage.LOADING
        noSimMessage = "Reserving eSIM…"
        viewModelScope.launch {
            runCatching {
                val reserved = reservation ?: authenticated {
                    api.reserveESim(it, memberId, "ONBOARD_NEW")
                }.also {
                    reservation = it
                    persistNoSimCheckpoint()
                }
                if (selectedProduct == null) {
                    noSimMessage = "Loading top-up…"
                    val products = authenticated { api.creditProducts(it, reserved.esim.ssn) }
                    selectedProduct = products.firstOrNull { it.id == DEFAULT_PRODUCT_ID }
                        ?: products.minByOrNull(CreditProduct::priceInPence)
                }
                check(selectedProduct != null) { "No credit product is available" }
                persistNoSimCheckpoint()
            }.onSuccess {
                noSimStage = NoSimStage.RESERVED
                noSimMessage = "已预留 eSIM，可用已绑卡支付并激活。"
            }.onFailure {
                noSimStage = NoSimStage.FAILED
                noSimMessage = "Failed to start eSIM order: ${it.userMessage()}"
            }
        }
    }

    fun openBindCard() {
        if (isPreparingBindCard) return
        isPreparingBindCard = true
        viewModelScope.launch {
            val result = runCatching {
                authenticated { api.ssoUrl(it, GiffgaffApi.PAYMENT_DETAILS_URL) }
            }
            browserSession = BrowserSession(
                url = result.getOrElse {
                    AppLogger.log("[Bind card] SSO failed: ${it.stackTraceToString()}")
                    GiffgaffApi.PAYMENT_DETAILS_URL
                },
                title = "绑定支付方式",
                kind = BrowserKind.BIND_CARD
            )
            isPreparingBindCard = false
        }
    }

    fun startWebCheckout() {
        val ssn = reservation?.esim?.ssn ?: run {
            noSimStage = NoSimStage.FAILED
            noSimMessage = "No reserved eSIM."
            return
        }
        if (isPreparingCheckout) return
        val amount = selectedProduct?.priceInPence ?: 1_000
        isPreparingCheckout = true
        viewModelScope.launch {
            runCatching {
                val orderId = authenticated { api.createActivationOrder(it, ssn, amount) }
                authenticated { api.ssoUrl(it, GiffgaffApi.webCheckoutUrl(orderId)) }
            }.onSuccess {
                browserSession = BrowserSession(it, "支付并激活", BrowserKind.CHECKOUT)
                isPreparingCheckout = false
            }.onFailure {
                noSimStage = NoSimStage.FAILED
                noSimMessage = "发起支付失败：${it.userMessage()}"
                isPreparingCheckout = false
            }
        }
    }

    fun closeBrowser() {
        browserSession = null
        loadPaymentMethods()
    }

    fun handlePaymentUrl(url: String): Boolean {
        val result = parsePaymentReturn(url) ?: return false
        handlePaymentReturn(result)
        return true
    }

    private fun handlePaymentReturn(result: com.tuluobo.ggesim.util.PaymentReturn) {
        browserSession = null
        loadPaymentMethods()
        if (result.success) {
            fetchOnboardingESim()
        } else {
            noSimStage = NoSimStage.REFUSED
            noSimMessage = result.reason ?: "支付未完成，请重试。"
        }
    }

    private fun fetchOnboardingESim() {
        val ssn = reservation?.esim?.ssn ?: return
        noSimStage = NoSimStage.LOADING
        noSimMessage = "Preparing your eSIM…"
        viewModelScope.launch {
            runCatching { authenticated { api.eSimDownloadToken(it, ssn) } }
                .onSuccess {
                    noSimLpa = it
                    noSimStage = NoSimStage.READY
                    noSimMessage = ""
                    clearNoSimCheckpoint()
                }
                .onFailure {
                    noSimStage = NoSimStage.FAILED
                    noSimMessage = "Failed to get eSIM: ${it.userMessage()}"
                }
        }
    }

    private suspend fun <T> authenticated(block: (String) -> T): T {
        var token = ensureValidToken()
        return try {
            withContext(Dispatchers.IO) { block(token.accessToken) }
        } catch (failure: HttpFailure) {
            if (failure.statusCode != 401) throw failure
            token = refreshAfterUnauthorized(token.accessToken)
            withContext(Dispatchers.IO) { block(token.accessToken) }
        }
    }

    private suspend fun ensureValidToken(): OAuthToken {
        val token = currentToken ?: throw IllegalStateException("Not logged in")
        return if (token.isExpired) refreshAccessToken(force = false) else token
    }

    private suspend fun refreshAccessToken(force: Boolean): OAuthToken = refreshMutex.withLock {
        val token = currentToken ?: throw IllegalStateException("Not logged in")
        if (!force && !token.isExpired) return@withLock token
        try {
            withContext(Dispatchers.IO) { api.refreshToken(token.refreshToken) }.also(::saveToken)
        } catch (failure: Throwable) {
            signOut()
            throw failure
        }
    }

    private suspend fun refreshAfterUnauthorized(failedAccessToken: String): OAuthToken =
        refreshMutex.withLock {
            val token = currentToken ?: throw IllegalStateException("Not logged in")
            if (token.accessToken != failedAccessToken) return@withLock token
            try {
                withContext(Dispatchers.IO) { api.refreshToken(token.refreshToken) }.also(::saveToken)
            } catch (failure: Throwable) {
                signOut()
                throw failure
            }
        }

    private fun saveToken(token: OAuthToken) {
        currentToken = token
        preferences.edit { putString(KEY_TOKEN, token.toJson().toString()) }
        tokenAvailable = true
    }

    private fun restoreToken(): OAuthToken? = preferences.getString(KEY_TOKEN, null)?.let {
        runCatching { OAuthToken.fromJson(JSONObject(it)) }
            .onFailure { AppLogger.log("[Token] Could not restore token: $it") }
            .getOrNull()
    }

    private fun persistNoSimCheckpoint() {
        val pendingReservation = reservation ?: return
        val json = JSONObject()
            .put("id", pendingReservation.id)
            .put("member_id", pendingReservation.memberId)
            .put("status", pendingReservation.status)
            .put("ssn", pendingReservation.esim.ssn)
            .put("activation_code", pendingReservation.esim.activationCode)
            .put("delivery_status", pendingReservation.esim.deliveryStatus)
            .put("associated_member_id", pendingReservation.esim.associatedMemberId)
        selectedProduct?.let { product ->
            json.put(
                "product",
                JSONObject()
                    .put("id", product.id)
                    .put("name", product.name)
                    .put("price_in_pence", product.priceInPence)
                    .put("category", product.category)
                    .put("tags", JSONArray(product.tags))
            )
        }
        preferences.edit { putString(KEY_PENDING_ONBOARDING, json.toString()) }
    }

    private fun restoreNoSimCheckpoint() {
        val encoded = preferences.getString(KEY_PENDING_ONBOARDING, null) ?: return
        runCatching {
            val json = JSONObject(encoded)
            reservation = ESimReservation(
                id = json.getString("id"),
                memberId = json.getString("member_id"),
                status = json.getString("status"),
                esim = ESimReservation.ReservedESim(
                    ssn = json.getString("ssn"),
                    activationCode = json.getString("activation_code"),
                    deliveryStatus = json.nullableString("delivery_status"),
                    associatedMemberId = json.nullableString("associated_member_id")
                )
            )
            selectedProduct = json.optJSONObject("product")?.let { product ->
                val tags = product.optJSONArray("tags")
                CreditProduct(
                    id = product.getString("id"),
                    name = product.getString("name"),
                    priceInPence = product.getInt("price_in_pence"),
                    category = product.getString("category"),
                    tags = if (tags == null) emptyList() else {
                        List(tags.length()) { index -> tags.getString(index) }
                    }
                )
            }
            noSimStage = NoSimStage.RESERVED
            noSimMessage = "已恢复待完成的 eSIM 订单。"
        }.onFailure {
            AppLogger.log("[Onboarding] Could not restore pending order: $it")
            clearNoSimCheckpoint()
        }
    }

    private fun clearNoSimCheckpoint() {
        preferences.edit { remove(KEY_PENDING_ONBOARDING) }
    }

    private fun JSONObject.nullableString(key: String): String? =
        if (isNull(key)) null else getString(key)

    private fun resetFlows() {
        verificationOpen = false
        applyLoading = false
        applyMessage = ""
        mfaRef = null
        mfaSignature = null
        simSwapLpa = null
        paymentMethods = emptyList()
        paymentMethodsLoaded = false
        reservation = null
        selectedProduct = null
        noSimStage = NoSimStage.IDLE
        noSimMessage = ""
        noSimLpa = null
        browserSession = null
    }

    private fun hasNetwork(): Boolean {
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    override fun onCleared() {
        connectivityManager.unregisterNetworkCallback(networkCallback)
        super.onCleared()
    }

    private fun Throwable.userMessage(): String = message?.takeIf(String::isNotBlank)
        ?: this::class.java.simpleName

    companion object {
        private const val KEY_TOKEN = "oauth_token"
        private const val KEY_CODE_VERIFIER = "code_verifier"
        private const val KEY_OAUTH_STATE = "oauth_state"
        private const val KEY_PENDING_ONBOARDING = "pending_onboarding"
        private const val DEFAULT_PRODUCT_ID = "CR0010"
    }
}
