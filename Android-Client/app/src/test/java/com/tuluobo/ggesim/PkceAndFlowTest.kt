package com.tuluobo.ggesim

import com.tuluobo.ggesim.util.Pkce
import com.tuluobo.ggesim.util.isWithinSimSwapWindow
import com.tuluobo.ggesim.util.parsePaymentReturn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PkceAndFlowTest {
    @Test
    fun `PKCE challenge matches RFC 7636 vector`() {
        val verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", Pkce.codeChallenge(verifier))
    }

    @Test
    fun `generated verifier has the required URL-safe shape`() {
        val verifier = Pkce.codeVerifier()

        assertEquals(43, verifier.length)
        assertTrue(verifier.matches(Regex("[A-Za-z0-9_-]+")))
    }

    @Test
    fun `SIM swap window follows London local time and includes endpoints`() {
        assertFalse(isWithinSimSwapWindow(Instant.parse("2026-07-27T03:29:00Z")))
        assertTrue(isWithinSimSwapWindow(Instant.parse("2026-07-27T03:30:00Z")))
        assertTrue(isWithinSimSwapWindow(Instant.parse("2026-07-27T20:30:00Z")))
        assertFalse(isWithinSimSwapWindow(Instant.parse("2026-07-27T20:31:00Z")))
    }

    @Test
    fun `payment return parses success and decoded refusal reason`() {
        assertTrue(parsePaymentReturn("giffgaff://payment?status=success")!!.success)

        val refused = parsePaymentReturn("giffgaff://payment?status=failed&reason=Card%20declined")!!
        assertFalse(refused.success)
        assertEquals("Card declined", refused.reason)
        assertNull(parsePaymentReturn("https://www.giffgaff.com/payment"))
    }
}
