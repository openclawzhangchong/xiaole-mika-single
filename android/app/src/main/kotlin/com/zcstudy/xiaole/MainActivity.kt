package com.zcstudy.xiaole

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: MikaBridge? = null

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
                else -> result.notImplemented()
            }
        }
    }
}
