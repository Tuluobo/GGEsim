package com.tuluobo.ggesim

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExampleInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun loginAndAboutScreensAreReachable() {
        composeRule.onNodeWithText("Giffgaff").assertIsDisplayed()
        composeRule.onNodeWithText("We’re up to good").assertIsDisplayed()
        composeRule.onNodeWithText("Login").assertIsDisplayed()

        composeRule.onNodeWithText("About GGEsim").performClick()

        composeRule.onNodeWithText("GGEsim").assertIsDisplayed()
        composeRule.onNodeWithText("版本 0.7.0").assertIsDisplayed()
        composeRule.onNodeWithText("导出日志").assertIsDisplayed()

        composeRule.runOnIdle {
            composeRule.activity.onBackPressedDispatcher.onBackPressed()
        }
        composeRule.onNodeWithText("Login").assertIsDisplayed()

        composeRule.onNodeWithText("About GGEsim").performClick()
        composeRule.onNodeWithContentDescription("关闭").performClick()
        composeRule.onNodeWithText("Login").assertIsDisplayed()
    }
}
