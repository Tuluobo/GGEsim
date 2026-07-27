package com.tuluobo.ggesim

import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeepLinkInstrumentedTest {
    @Test
    fun callbackIntentIsConsumedAfterDispatch() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(
            Intent.ACTION_VIEW,
            "giffgaff://auth/callback/?error_description=cancelled".toUri(),
            context,
            MainActivity::class.java
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val instrumentation = InstrumentationRegistry.getInstrumentation()

        val activity = instrumentation.startActivitySync(intent) as MainActivity
        instrumentation.waitForIdleSync()
        assertNull(activity.intent.data)
        instrumentation.runOnMainSync {
            activity.finish()
        }
    }
}
