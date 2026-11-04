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
        private const val EXTRA_SEG_TEXTS = "debug_send_text_seg"
    }

    /** am start 时注入的文本（多条用 \n 分隔），由 Dart 侧一次性取走 */
    private var pendingDebugTexts: String? = null

    /** 走真实发送路径（含分段）的注入文本 */
    private var pendingDebugSegTexts: String? = null

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
        val seg = intent.getStringExtra(EXTRA_SEG_TEXTS)
        pendingDebugTexts = multi ?: single ?: pendingDebugTexts
        pendingDebugSegTexts = seg ?: pendingDebugSegTexts
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
                    "takeDebugSegTexts" -> {
                        val texts = pendingDebugSegTexts
                        pendingDebugSegTexts = null
                        result.success(texts)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
