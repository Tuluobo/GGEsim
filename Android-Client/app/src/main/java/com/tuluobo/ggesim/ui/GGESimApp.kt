package com.tuluobo.ggesim.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Bitmap
import android.provider.Settings
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.graphics.createBitmap
import androidx.core.graphics.set
import androidx.core.net.toUri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.border
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.SimCard
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.tuluobo.ggesim.BuildConfig
import com.tuluobo.ggesim.GGESimViewModel
import com.tuluobo.ggesim.R
import com.tuluobo.ggesim.data.BrowserKind
import com.tuluobo.ggesim.data.BrowserSession
import com.tuluobo.ggesim.data.MemberInfo
import com.tuluobo.ggesim.data.NoSimStage
import com.tuluobo.ggesim.data.SavedPaymentMethod
import com.tuluobo.ggesim.util.AppLogger
import kotlinx.coroutines.delay

@Composable
fun GGESimApp(viewModel: GGESimViewModel) {
    val context = LocalContext.current
    val browser = viewModel.browserSession

    when {
        browser != null -> WebBrowserScreen(
            session = browser,
            onClose = viewModel::closeBrowser,
            onPaymentUrl = viewModel::handlePaymentUrl
        )
        viewModel.aboutOpen -> AboutScreen(onClose = { viewModel.showAbout(false) })
        else -> MainContent(viewModel)
    }

    viewModel.authError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissAuthError,
            title = { Text("登录失败") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = viewModel::dismissAuthError) { Text("OK") } }
        )
    }
    if (viewModel.networkDialogVisible) {
        AlertDialog(
            onDismissRequest = viewModel::dismissNetworkDialog,
            title = { Text("Network Unavailable") },
            text = { Text("Please check your network settings") },
            confirmButton = {
                TextButton(onClick = {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            "package:${context.packageName}".toUri()
                        )
                    )
                    viewModel.dismissNetworkDialog()
                }) { Text("Settings") }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissNetworkDialog) { Text("Cancel") }
            }
        )
    }
    if (viewModel.timeRestrictionVisible) {
        AlertDialog(
            onDismissRequest = viewModel::dismissTimeRestriction,
            title = { Text("Application Time Restriction") },
            text = {
                Text("eSIM applications are only accepted between 4:30am and 9:30pm (GMT+1). Please try again during these hours.")
            },
            confirmButton = {
                TextButton(onClick = viewModel::dismissTimeRestriction) { Text("OK") }
            }
        )
    }
    if (viewModel.verificationOpen) VerificationDialog(viewModel)
}

@Composable
private fun MainContent(viewModel: GGESimViewModel) {
    Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
        when {
            viewModel.isMemberLoading -> LoadingScreen(Modifier.padding(padding))
            !viewModel.tokenAvailable -> LoginScreen(
                modifier = Modifier.padding(padding),
                onLogin = viewModel::startOAuthFlow,
                onAbout = { viewModel.showAbout(true) }
            )
            viewModel.memberInfo == null -> RefreshScreen(
                modifier = Modifier.padding(padding),
                error = viewModel.memberError,
                onRefresh = viewModel::loadMember,
                onSignOut = viewModel::signOut,
                onAbout = { viewModel.showAbout(true) }
            )
            else -> ApplyScreen(
                modifier = Modifier.padding(padding),
                memberInfo = viewModel.memberInfo!!,
                viewModel = viewModel
            )
        }
    }
}

@Composable
private fun LoadingScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        CircularProgressIndicator()
        Text("Loading ... ", modifier = Modifier.padding(top = 10.dp))
    }
}

@Composable
private fun LoginScreen(
    modifier: Modifier,
    onLogin: () -> String?,
    onAbout: () -> Unit
) {
    val context = LocalContext.current
    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.weight(1.7f))
        Text("Giffgaff", fontSize = 58.sp, fontWeight = FontWeight.Bold)
        Text(
            "We’re up to good",
            fontSize = 22.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
        )
        Spacer(Modifier.weight(1.15f))
        PrimaryButton(text = "Login") {
            onLogin()?.let { CustomTabsIntent.Builder().build().launchUrl(context, it.toUri()) }
        }
        Spacer(Modifier.weight(1f))
        AboutButton(onAbout)
    }
}

@Composable
private fun RefreshScreen(
    modifier: Modifier,
    error: String?,
    onRefresh: () -> Unit,
    onSignOut: () -> Unit,
    onAbout: () -> Unit
) {
    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
        }
        PrimaryButton("状态异常，手动刷新", onClick = onRefresh)
        Spacer(Modifier.weight(1f))
        Footer(onSignOut, onAbout)
    }
}

@Composable
private fun ApplyScreen(
    modifier: Modifier,
    memberInfo: MemberInfo,
    viewModel: GGESimViewModel
) {
    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (memberInfo.sim == null || viewModel.noSimLpa != null) {
                NoSimScreen(memberInfo, viewModel)
            } else {
                SimSwapScreen(memberInfo, viewModel)
            }
        }
        Footer(
            onSignOut = viewModel::signOut,
            onAbout = { viewModel.showAbout(true) }
        )
    }
}

@Composable
private fun SimSwapScreen(memberInfo: MemberInfo, viewModel: GGESimViewModel) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(36.dp))
        MemberHeader(memberInfo)
        Spacer(Modifier.height(22.dp))
        ESimPanel(
            lpa = viewModel.simSwapLpa,
            loading = viewModel.applyLoading,
            message = viewModel.applyMessage
        )
        Spacer(Modifier.height(14.dp))
        PrimaryButton(
            text = "Apply eSIM",
            enabled = !viewModel.applyLoading && viewModel.simSwapLpa == null,
            onClick = viewModel::requestSimSwap
        )
        Text(
            "Between 4:30am and 9:30pm(GMT+1).",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            modifier = Modifier.padding(top = 6.dp, bottom = 12.dp)
        )
    }
}

@Composable
private fun MemberHeader(memberInfo: MemberInfo) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Image(
            painter = painterResource(R.drawable.avatar_default),
            contentDescription = null,
            modifier = Modifier
                .size(82.dp)
                .shadow(5.dp, CircleShape)
                .clip(CircleShape)
                .border(2.dp, Color.Gray, CircleShape),
            contentScale = ContentScale.Crop
        )
        Spacer(Modifier.height(14.dp))
        Text("Hi, ${memberInfo.memberProfile.memberName}", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        memberInfo.sim?.let { sim ->
            Text(
                sim.phoneNumber,
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.padding(top = 5.dp)
            )
            Text(
                sim.status.removePrefix("STATUS_").lowercase().replaceFirstChar(Char::uppercase),
                fontSize = 12.sp,
                modifier = Modifier
                    .padding(top = 6.dp)
                    .background(Color(0x3334C759), RoundedCornerShape(8.dp))
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            )
            Text(
                "Welcome! You're logged in.",
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color(0xFF007AFF),
                modifier = Modifier.padding(top = 12.dp)
            )
        }
    }
}

@Composable
private fun ESimPanel(lpa: String?, loading: Boolean, message: String) {
    Column(
        modifier = Modifier
            .width(270.dp)
            .heightIn(min = 330.dp)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), RoundedCornerShape(15.dp))
            .padding(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("eSIM Info", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(22.dp))
        when {
            lpa != null -> {
                Text("Your eSIM is ready!", color = Color(0xFF34C759), fontWeight = FontWeight.SemiBold)
                QrCode(lpa, 200)
                Text(
                    "LPA: $lpa",
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                )
            }
            loading -> {
                Spacer(Modifier.weight(1f))
                CircularProgressIndicator()
                Text(message, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
                Spacer(Modifier.weight(1f))
            }
            else -> {
                Spacer(Modifier.weight(1f))
                Text(
                    message.ifBlank { "No eSIM applied yet" },
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
                Spacer(Modifier.weight(1f))
            }
        }
        val context = LocalContext.current
        TextButton(onClick = { openUrl(context, BuildConfig.GGESIM_GUIDE_URL) }) {
            Text("点击查看使用常见问题", fontSize = 14.sp)
        }
    }
}

@Composable
private fun NoSimScreen(memberInfo: MemberInfo, viewModel: GGESimViewModel) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        viewModel.noSimLpa?.let { lpa ->
            Text("Your eSIM is ready!", color = Color(0xFF34C759), fontWeight = FontWeight.SemiBold)
            QrCode(lpa, 220)
            Text(
                "用手机相机或「设置 > 网络和互联网 > SIM > 添加 eSIM」扫描此二维码即可下载并激活。",
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.widthIn(max = 310.dp)
            )
            Text(
                "LPA: $lpa",
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.padding(top = 10.dp)
            )
            return@Column
        }

        Icon(
            Icons.Outlined.SimCard,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(56.dp)
        )
        Text(
            "Hi, ${memberInfo.memberProfile.memberName}",
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 14.dp)
        )
        Text("当前账号还没有 SIM 卡", fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 18.dp))
        Text(
            "是否订购一张 eSIM？无需实体卡，激活后即可使用。",
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(top = 6.dp).widthIn(max = 310.dp)
        )
        PaymentMethodsSection(viewModel, Modifier.padding(top = 18.dp))
        viewModel.selectedProduct?.let { product ->
            Row(
                modifier = Modifier
                    .padding(top = 16.dp)
                    .widthIn(max = 280.dp)
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(10.dp))
                    .padding(15.dp)
            ) {
                Text("充值金额", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f))
                Spacer(Modifier.weight(1f))
                Text(product.formattedPrice, fontWeight = FontWeight.SemiBold)
            }
        }
        StatusText(viewModel)
        if (viewModel.boundCards.isNotEmpty()) {
            val reserved = viewModel.noSimStage == NoSimStage.RESERVED
            val card = viewModel.boundCards.first()
            PrimaryButton(
                text = if (reserved) {
                    if (viewModel.isPreparingCheckout) "正在打开收银台…" else "用 ${card.displayName} 支付并激活"
                } else {
                    "订购 eSIM"
                },
                enabled = viewModel.noSimStage != NoSimStage.LOADING && !viewModel.isPreparingCheckout,
                modifier = Modifier.padding(top = 12.dp),
                onClick = if (reserved) viewModel::startWebCheckout else viewModel::startOnboarding
            )
        }
    }
}

@Composable
private fun PaymentMethodsSection(viewModel: GGESimViewModel, modifier: Modifier = Modifier) {
    when {
        !viewModel.paymentMethodsLoaded -> CircularProgressIndicator(modifier = modifier.size(28.dp))
        viewModel.boundCards.isEmpty() -> Column(
            modifier = modifier.widthIn(max = 300.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("尚未绑定银行卡", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            Text(
                "订购前请先绑定一张 Visa / Mastercard 银行卡。",
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 5.dp)
            )
            PrimaryButton(
                text = if (viewModel.isPreparingBindCard) "正在打开…" else "绑定支付方式",
                enabled = !viewModel.isPreparingBindCard,
                leadingIcon = { Icon(Icons.Filled.CreditCard, contentDescription = null) },
                modifier = Modifier.padding(top = 10.dp),
                onClick = viewModel::openBindCard
            )
        }
        else -> Column(
            modifier = modifier
                .widthIn(max = 300.dp)
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(10.dp))
                .padding(15.dp)
        ) {
            Text("支付方式", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f))
            viewModel.boundCards.forEach { PaymentMethodRow(it) }
            TextButton(onClick = viewModel::openBindCard, enabled = !viewModel.isPreparingBindCard) {
                Text(if (viewModel.isPreparingBindCard) "正在打开…" else "管理支付方式", fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun PaymentMethodRow(method: SavedPaymentMethod) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Filled.CreditCard, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(method.displayName, fontSize = 14.sp, modifier = Modifier.padding(start = 8.dp))
        if (method.isDefault) {
            Text(
                "默认",
                fontSize = 10.sp,
                modifier = Modifier
                    .padding(start = 7.dp)
                    .background(Color(0x3334C759), RoundedCornerShape(4.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            )
        }
    }
}

@Composable
private fun StatusText(viewModel: GGESimViewModel) {
    when (viewModel.noSimStage) {
        NoSimStage.LOADING -> Row(
            modifier = Modifier.padding(top = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(viewModel.noSimMessage, fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
        }
        NoSimStage.RESERVED -> Text(
            viewModel.noSimMessage,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            modifier = Modifier.padding(top = 14.dp)
        )
        NoSimStage.REFUSED, NoSimStage.FAILED -> Text(
            viewModel.noSimMessage,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.padding(top = 14.dp)
        )
        else -> Unit
    }
}

@Composable
private fun VerificationDialog(viewModel: GGESimViewModel) {
    var code by remember { mutableStateOf("") }
    var countdown by remember { mutableIntStateOf(0) }
    LaunchedEffect(countdown) {
        if (countdown > 0) {
            delay(1_000)
            countdown -= 1
        }
    }
    Dialog(onDismissRequest = viewModel::closeVerification) {
        Surface(shape = RoundedCornerShape(8.dp), color = MaterialTheme.colorScheme.background) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    IconButton(onClick = viewModel::closeVerification) {
                        Icon(Icons.Filled.Close, contentDescription = "关闭")
                    }
                }
                Text("Verification", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Enter the verification code sent to your phone number",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp)
                )
                if (viewModel.applyLoading) CircularProgressIndicator(Modifier.padding(top = 18.dp))
                if (viewModel.applyMessage.isNotEmpty()) {
                    Text(
                        viewModel.applyMessage,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(top = 10.dp)
                    )
                }
                Row(
                    modifier = Modifier.padding(top = 20.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = code,
                        onValueChange = { code = it.filter(Char::isDigit).take(6) },
                        placeholder = { Text("输入验证码") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        enabled = !viewModel.applyLoading && viewModel.mfaRef != null,
                        singleLine = true,
                        modifier = Modifier.weight(1f).height(56.dp)
                    )
                    Button(
                        onClick = {
                            countdown = 60
                            viewModel.sendVerificationCode()
                        },
                        enabled = !viewModel.applyLoading && countdown == 0,
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.padding(start = 10.dp).widthIn(min = 82.dp).heightIn(min = 52.dp)
                    ) { Text(if (countdown > 0) "${countdown}s" else "发送") }
                }
                PrimaryButton(
                    text = "Submit",
                    enabled = !viewModel.applyLoading && viewModel.mfaRef != null && code.length == 6,
                    modifier = Modifier.padding(top = 20.dp),
                    onClick = { viewModel.submitVerification(code) }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun WebBrowserScreen(
    session: BrowserSession,
    onClose: () -> Unit,
    onPaymentUrl: (String) -> Boolean
) {
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        TopAppBar(
            title = { Text(session.title, fontSize = 17.sp) },
            actions = { TextButton(onClick = onClose) { Text("完成") } },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            modifier = Modifier.statusBarsPadding()
        )
        AndroidView(
            modifier = Modifier.fillMaxWidth().weight(1f).navigationBarsPadding(),
            factory = { context ->
                WebView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webChromeClient = WebChromeClient()
                    webViewClient = object : WebViewClient() {
                        private fun intercept(url: String): Boolean {
                            AppLogger.log("[WebView] navigate: $url")
                            if (url.startsWith("giffgaff://")) {
                                val paymentHandled = session.kind == BrowserKind.CHECKOUT && onPaymentUrl(url)
                                if (!paymentHandled) onClose()
                                return true
                            }
                            return false
                        }

                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean =
                            request?.url?.toString()?.let(::intercept) ?: false

                        @Suppress("DEPRECATION")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean =
                            url?.let(::intercept) ?: false

                        override fun onPageFinished(view: WebView?, url: String?) {
                            CookieManager.getInstance().flush()
                            super.onPageFinished(view, url)
                        }
                    }
                    loadUrl(session.url)
                }
            }
        )
    }
}

@Composable
private fun AboutScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    BackHandler(onBack = onClose)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(if (isSystemInDarkTheme()) Color.Black else Color(0xFFF2F2F7))
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = onClose) {
                Icon(Icons.Filled.Cancel, contentDescription = "关闭", tint = Color.Gray, modifier = Modifier.size(30.dp))
            }
        }
        Spacer(Modifier.height(24.dp))
        Text("GGEsim", fontSize = 36.sp, fontWeight = FontWeight.Bold)
        Text(
            "版本 ${BuildConfig.VERSION_NAME}",
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
            modifier = Modifier.padding(top = 20.dp)
        )
        Column(
            modifier = Modifier.padding(top = 38.dp).widthIn(max = 420.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            AboutRow("数字牧民社区", Icons.Filled.Public) { openUrl(context, "https://shuzimumin.com") }
            AboutRow("GitHub", Icons.Outlined.Code) { openUrl(context, "https://github.com/tuluobo/GGEsim") }
            AboutRow("反馈问题", Icons.Outlined.Email) { openUrl(context, BuildConfig.GGESIM_GUIDE_URL) }
            AboutRow("导出日志", Icons.Filled.Share, Icons.Filled.Description) { AppLogger.share(context) }
        }
        Spacer(Modifier.weight(1f))
        Text(
            "© 2024 GGEsim. All rights reserved.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
            modifier = Modifier.padding(bottom = 12.dp)
        )
    }
}

@Composable
private fun AboutRow(
    title: String,
    leading: androidx.compose.ui.graphics.vector.ImageVector,
    trailing: androidx.compose.ui.graphics.vector.ImageVector = Icons.AutoMirrored.Filled.OpenInNew,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onBackground
        ),
        shape = RoundedCornerShape(10.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
    ) {
        Icon(leading, contentDescription = null, tint = Color(0xFF007AFF))
        Text(title, modifier = Modifier.padding(start = 12.dp))
        Spacer(Modifier.weight(1f))
        Icon(trailing, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(17.dp))
    }
}

@Composable
private fun Footer(onSignOut: () -> Unit, onAbout: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        TextButton(onClick = onSignOut) {
            Text("退出当前账号", fontSize = 12.sp)
        }
        AboutButton(onAbout)
    }
}

@Composable
private fun AboutButton(onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onBackground),
        modifier = Modifier.padding(bottom = 2.dp)
    ) {
        Icon(Icons.Filled.Info, contentDescription = null, modifier = Modifier.size(16.dp))
        Text("About GGEsim", fontSize = 12.sp, modifier = Modifier.padding(start = 5.dp))
    }
}

@Composable
private fun PrimaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leadingIcon: (@Composable () -> Unit)? = null,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = Color.Black
        ),
        modifier = modifier.widthIn(min = 232.dp, max = 340.dp).heightIn(min = 52.dp)
    ) {
        if (leadingIcon != null) {
            leadingIcon()
            Spacer(Modifier.width(8.dp))
        }
        Text(text, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    }
}

@Composable
private fun QrCode(value: String, size: Int) {
    val bitmap = remember(value) { generateQrCode(value) }
    Image(
        bitmap = bitmap.asImageBitmap(),
        contentDescription = "eSIM QR code",
        modifier = Modifier
            .padding(vertical = 14.dp)
            .size(size.dp)
            .shadow(5.dp, RoundedCornerShape(10.dp))
            .background(Color.White, RoundedCornerShape(10.dp))
            .padding(12.dp),
        contentScale = ContentScale.Fit
    )
}

private fun generateQrCode(value: String): Bitmap {
    val hints = mapOf(
        EncodeHintType.MARGIN to 1,
        EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M
    )
    val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, 512, 512, hints)
    return createBitmap(512, 512).apply {
        for (y in 0 until 512) {
            for (x in 0 until 512) {
                this[x, y] = if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
            }
        }
    }
}

private fun openUrl(context: android.content.Context, url: String) {
    if (url.isBlank()) return
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri())) }
}
