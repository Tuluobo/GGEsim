package com.tuluobo.ggesim.util

import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.time.ZoneId
import java.util.Base64

object Pkce {
    fun codeVerifier(): String {
        val bytes = ByteArray(32).also(SecureRandom()::nextBytes)
        return base64Url(bytes)
    }

    fun codeChallenge(verifier: String): String = base64Url(
        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII))
    )

    private fun base64Url(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}

fun isWithinSimSwapWindow(instant: Instant = Instant.now()): Boolean {
    val time = instant.atZone(ZoneId.of("Europe/London")).toLocalTime()
    val minutes = time.hour * 60 + time.minute
    return minutes in (4 * 60 + 30)..(21 * 60 + 30)
}

data class PaymentReturn(val success: Boolean, val reason: String?)

fun parsePaymentReturn(url: String): PaymentReturn? {
    val uri = runCatching { URI(url) }.getOrNull() ?: return null
    if (uri.scheme != "giffgaff" || uri.host != "payment") return null
    val parameters = uri.rawQuery.orEmpty().split('&').mapNotNull { pair ->
        if (pair.isBlank()) return@mapNotNull null
        val parts = pair.split('=', limit = 2)
        URLDecoder.decode(parts[0], Charsets.UTF_8.name()) to
            URLDecoder.decode(parts.getOrElse(1) { "" }, Charsets.UTF_8.name())
    }.toMap()
    return PaymentReturn(
        success = parameters["status"] == "success",
        reason = parameters["reason"]
    )
}
