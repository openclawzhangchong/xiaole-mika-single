package com.zcstudy.xiaole

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: MikaBridge? = null

    companion object {
        private const val CHANNEL = "xiaole/debug"
        private const val LOG_CHANNEL = "xiaole/log"
        private const val LOG_TAG = "XiaoLe"
        private const val EXTRA_TEXTS = "debug_send_texts"
        private const val EXTRA_TEXT = "debug_send_text"
        private const val EXTRA_SEG_TEXTS = "debug_send_text_seg"
        private const val POWER_CHANNEL = "xiaole/power"
        private const val KEEPALIVE_CHANNEL = "xiaole/keepalive"
        private const val REQ_NOTIF = 7302
        private const val WAKE_LOCK_TAG = "XiaoLe:ws"
        // 上限 10 分钟：无论 Dart 侧是否来得及 release，系统到点自动释放，避免耗电失控
        private const val WAKE_LOCK_TIMEOUT_MS = 10 * 60 * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wakeLockAcquiredAt = 0L

    /** Android 13+ 通知权限申请的挂起回调 */
    private var pendingNotifResult: MethodChannel.Result? = null

    /** am start 时注入的文本（多条用 \n 分隔），由 Dart 侧一次性取走 */
    private var pendingDebugTexts: String? = null

    /** 走真实发送路径（含分段）的注入文本 */
    private var pendingDebugSegTexts: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 固定 tag 的启动锚点：装机后 `adb logcat -s XiaoLe` 第一行就该是它，
        // 用来说明 release 包确实在输出日志（Flutter 的 flutter tag 会被系统缓冲轮转掉）。
        Log.i(LOG_TAG, "BOOT MainActivity onCreate")
        readDebugExtra(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readDebugExtra(intent)
    }

    override fun onDestroy() {
        // 进程/页面退出兜底：绝不允许 wakelock 泄漏
        releaseWakeLock(null)
        // 79 轮：引擎即将销毁，服务侧不能再往这条通道发唤醒
        KeepAliveService.dartChannel = null
        super.onDestroy()
    }

    /** 息屏/后台期间持有，保证 CPU 不停机、Dart 45s 心跳继续；回前台立刻释放 */
    private fun acquireWakeLock(result: MethodChannel.Result) {
        if (wakeLock?.isHeld == true) {
            val held = (SystemClock.elapsedRealtime() - wakeLockAcquiredAt) / 1000
            Log.i(LOG_TAG, "[POWER] acquire wakelock（已持有 ${held}s，幂等跳过）")
            result.success(true)
            return
        }
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
        wakeLockAcquiredAt = SystemClock.elapsedRealtime()
        Log.i(LOG_TAG, "[POWER] acquire wakelock 上限=${WAKE_LOCK_TIMEOUT_MS / 1000}s")
        result.success(true)
    }

    /** 幂等释放；result 为 null 表示从生命周期兜底调用 */
    private fun releaseWakeLock(result: MethodChannel.Result?) {
        val wl = wakeLock
        if (wl?.isHeld == true) {
            val held = (SystemClock.elapsedRealtime() - wakeLockAcquiredAt) / 1000
            try {
                wl.release()
            } catch (e: Exception) {
                Log.w(LOG_TAG, "[POWER] release wakelock 异常: $e")
            }
            Log.i(LOG_TAG, "[POWER] release wakelock held=${held}s")
        } else {
            Log.i(LOG_TAG, "[POWER] release wakelock（未持有，跳过）")
        }
        wakeLock = null
        wakeLockAcquiredAt = 0L
        result?.success(true)
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

        // release 关键日志通道：固定 tag XiaoLe，供 `adb logcat -s XiaoLe` 直读
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "i" -> {
                        // Dart 侧（NativeLog.write）直接传字符串；同时兼容旧的 Map 写法
                        val msg = when (val args = call.arguments) {
                            is String -> args
                            is Map<*, *> -> args["msg"] as? String ?: ""
                            else -> ""
                        }
                        Log.i(LOG_TAG, msg)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // 息屏保活：只加 PARTIAL_WAKE_LOCK，不引入前台服务/常驻通知（方案 A 分诊）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> acquireWakeLock(result)
                    "release" -> releaseWakeLock(result)
                    else -> result.notImplemented()
                }
            }

        // 后台保持连接（方案 B）：前台服务只做"保活"，业务仍在 Dart 侧
        val keepAliveChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEEPALIVE_CHANNEL)
        // 79 轮 P0：把通道交给服务，让它能每 30s 唤醒 Dart 补一拍心跳
        KeepAliveService.dartChannel = keepAliveChannel
        keepAliveChannel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startKeepAlive(result)
                    "stop" -> {
                        KeepAliveService.stop(this)
                        Log.i(LOG_TAG, "[KEEPALIVE] service_stop")
                        result.success(true)
                    }
                    "isRunning" -> result.success(KeepAliveService.isRunning())
                    "notificationsEnabled" ->
                        result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                    "requestNotificationPermission" -> requestNotificationPermission(result)
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

    /** 起前台服务；被系统拒绝时把原因码打进 XiaoLe 日志，验收可直接 grep start_denied */
    private fun startKeepAlive(result: MethodChannel.Result) {
        try {
            KeepAliveService.start(this)
            Log.i(LOG_TAG, "[KEEPALIVE] service_start")
            result.success(true)
        } catch (e: Throwable) {
            val code = when {
                e.javaClass.simpleName == "ForegroundServiceStartNotAllowedException" ->
                    "FGS_BACKGROUND_NOT_ALLOWED"
                e is SecurityException -> "SECURITY_DENIED"
                else -> e.javaClass.simpleName
            }
            Log.w(LOG_TAG, "[KEEPALIVE] start_denied code=$code msg=${e.message}")
            result.error("start_denied", code, e.message)
        }
    }

    /** Android 13+：设置页打开开关时弹系统通知授权框；13 以下/已授权直接返回 true */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        ) {
            result.success(true)
            return
        }
        if (pendingNotifResult != null) {
            result.error("busy", "已有一次通知授权在进行中", null)
            return
        }
        pendingNotifResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_NOTIF,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIF) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        Log.i(LOG_TAG, "[KEEPALIVE] notif_permission granted=$granted")
        pendingNotifResult?.success(granted)
        pendingNotifResult = null
    }
}
