package com.zcstudy.xiaole

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "xiaole/debug"
        private const val EXTRA_TEXTS = "debug_send_texts"
        private const val EXTRA_TEXT = "debug_send_text"
    }

    /** am start 时注入的文本（多条用 \n 分隔），由 Dart 侧一次性取走 */
    private var pendingDebugTexts: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readDebugExtra(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readDebugExtra(intent)
    }

    private fun readDebugExtra(intent: Intent?) {
        if (intent == null) return
        val multi = intent.getStringExtra(EXTRA_TEXTS)
        val single = intent.getStringExtra(EXTRA_TEXT)
        pendingDebugTexts = multi ?: single ?: pendingDebugTexts
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeDebugTexts" -> {
                        val texts = pendingDebugTexts
                        pendingDebugTexts = null
                        result.success(texts)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
