package com.tuluobo.ggesim

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.tuluobo.ggesim.ui.GGESimApp
import com.tuluobo.ggesim.ui.theme.GGESimTheme

class MainActivity : ComponentActivity() {
    private val viewModel: GGESimViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        consumeDeepLink(intent)
        setContent {
            GGESimTheme {
                GGESimApp(viewModel)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeDeepLink(intent)
    }

    private fun consumeDeepLink(intent: Intent?) {
        viewModel.handleDeepLink(intent?.data)
        // Prevent a callback code from being exchanged again after Activity recreation.
        intent?.data = null
    }
}
