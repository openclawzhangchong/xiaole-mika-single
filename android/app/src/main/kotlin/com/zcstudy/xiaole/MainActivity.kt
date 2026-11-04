package com.zcstudy.xiaole

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: MikaBridge? = null

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

        // 与 lib/core/mika/mika_bridge.dart 中的通道名保持一致
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xiaole/mika")
        val b = MikaBridge(this, channel)
        bridge = b
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "runTask" -> b.runTask(call.argument<String>("goal") ?: "", result)
                "cancel" -> b.cancel(call.argument<String>("id") ?: "", result)
                "answer" -> b.answer(
                    call.argument<String>("id") ?: "",
                    call.argument<String>("text") ?: "",
                    result,
                )
                "openMikaUi" -> b.openMikaUi(result)
                "configureProvider" -> b.configureProvider(
                    call.argument<String>("baseUrl") ?: "",
                    call.argument<String>("model") ?: "",
                    call.argument<String>("apiKey") ?: "",
                    result,
                )
                "engineInfo" -> b.engineInfo(result)
                // 麦克风互斥:小乐录音前拿租约,停止录音后还回去;Mika 侧的 PcmRecorder 用同一把锁。
                "acquireMic" -> b.acquireMic(result)
                "releaseMic" -> b.releaseMic(result)
                "micHolder" -> b.micHolder(result)
                else -> result.notImplemented()
            }
        }

        // 开发者模式 adb 注入通道（[DEBUGINJECT]，仅 devAuthed 使用）
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
