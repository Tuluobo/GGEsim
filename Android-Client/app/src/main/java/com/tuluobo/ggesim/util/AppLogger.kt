package com.tuluobo.ggesim.util

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import com.tuluobo.ggesim.BuildConfig
import java.io.File
import java.time.Instant

object AppLogger {
    private const val TAG = "GGEsim"
    private lateinit var applicationContext: Context

    fun initialize(context: Context) {
        applicationContext = context.applicationContext
        log("App started")
    }

    @Synchronized
    fun log(message: String) {
        runCatching { Log.i(TAG, message) }
        if (!::applicationContext.isInitialized) return
        runCatching {
            val directory = File(applicationContext.filesDir, "logs").apply { mkdirs() }
            File(directory, "ggesim.log").appendText("${Instant.now()} $message\n")
        }
    }

    fun share(context: Context) {
        val file = File(File(context.filesDir, "logs").apply { mkdirs() }, "ggesim.log")
        if (!file.exists()) file.writeText("${Instant.now()} Log exported\n")
        val uri = FileProvider.getUriForFile(
            context,
            "${BuildConfig.APPLICATION_ID}.fileprovider",
            file
        )
        context.startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                "导出日志"
            )
        )
    }
}
