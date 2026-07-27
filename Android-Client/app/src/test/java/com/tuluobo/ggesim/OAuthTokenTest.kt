package com.tuluobo.ggesim

import com.tuluobo.ggesim.data.OAuthToken
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OAuthTokenTest {
    @Test
    fun `token persistence retains absolute expiry`() {
        val token = OAuthToken(
            type = "Bearer",
            accessToken = "access",
            refreshToken = "refresh",
            expiresIn = 3_600,
            expiresAtMillis = System.currentTimeMillis() + 3_600_000
        )

        val restored = OAuthToken.fromJson(JSONObject(token.toJson().toString()))

        assertEquals(token, restored)
        assertFalse(restored.isExpired)
    }

    @Test
    fun `token expiring inside clock skew is treated as expired`() {
        val token = OAuthToken("Bearer", "access", "refresh", 3_600, System.currentTimeMillis() + 30_000)

        assertTrue(token.isExpired)
    }
}
