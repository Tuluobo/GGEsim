package com.tuluobo.ggesim.data

import org.json.JSONObject

data class OAuthToken(
    val type: String,
    val accessToken: String,
    val refreshToken: String,
    val expiresIn: Int,
    val expiresAtMillis: Long
) {
    val isExpired: Boolean
        get() = System.currentTimeMillis() >= expiresAtMillis - 60_000L

    fun toJson(): JSONObject = JSONObject()
        .put("token_type", type)
        .put("access_token", accessToken)
        .put("refresh_token", refreshToken)
        .put("expires_in", expiresIn)
        .put("expires_at", expiresAtMillis)

    companion object {
        fun fromJson(json: JSONObject): OAuthToken {
            val expiresIn = json.getInt("expires_in")
            return OAuthToken(
                type = json.getString("token_type"),
                accessToken = json.getString("access_token"),
                refreshToken = json.getString("refresh_token"),
                expiresIn = expiresIn,
                expiresAtMillis = json.optLong(
                    "expires_at",
                    System.currentTimeMillis() + expiresIn * 1_000L
                )
            )
        }
    }
}

data class MemberProfile(val id: String, val memberName: String)

data class SimInfo(val phoneNumber: String, val status: String)

data class MemberInfo(val memberProfile: MemberProfile, val sim: SimInfo?)

data class CreditProduct(
    val id: String,
    val name: String,
    val priceInPence: Int,
    val category: String,
    val tags: List<String>
) {
    val formattedPrice: String
        get() = "£%.2f".format(priceInPence / 100.0)
}

data class SavedPaymentMethod(
    val id: String,
    val isDefault: Boolean,
    val kind: Kind
) {
    sealed interface Kind {
        data class Card(
            val lastDigits: String,
            val type: String?,
            val expired: Boolean
        ) : Kind

        data class Paypal(val email: String) : Kind
    }

    val isUsableCard: Boolean
        get() = kind is Kind.Card && !kind.expired

    val displayName: String
        get() = when (val value = kind) {
            is Kind.Card -> {
                val brand = value.type?.lowercase()?.replaceFirstChar(Char::uppercase) ?: "Card"
                "$brand •••• ${value.lastDigits}" + if (value.expired) "（已过期）" else ""
            }
            is Kind.Paypal -> "PayPal ${value.email}"
        }
}

data class ESimReservation(
    val id: String,
    val memberId: String,
    val status: String,
    val esim: ReservedESim
) {
    data class ReservedESim(
        val ssn: String,
        val activationCode: String,
        val deliveryStatus: String?,
        val associatedMemberId: String?
    )
}

enum class BrowserKind { BIND_CARD, CHECKOUT }

data class BrowserSession(
    val url: String,
    val title: String,
    val kind: BrowserKind
)

enum class NoSimStage { IDLE, LOADING, RESERVED, READY, REFUSED, FAILED }

class HttpFailure(val statusCode: Int, message: String) : Exception(message)
