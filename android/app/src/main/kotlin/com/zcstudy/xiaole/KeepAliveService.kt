package com.zcstudy.xiaole

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/**
 * 后台保持连接（方案 B）：负责让进程在后台时不被系统冻结，并做原生心跳兜底。
 * 业务与发包仍在 Dart 侧：这里每 30s 打一拍 `[KEEPALIVE] tick#N 来源=native`
 * 并经 MethodChannel 唤醒 Dart（Dart 按需补发 `listen:stop` 到服务端）。
 */
class KeepAliveService : Service() {

    companion object {
        private const val TAG = "XiaoLe"
        private const val ACTION_START = "com.zcstudy.xiaole.KEEPALIVE_START"
        private const val ACTION_STOP = "com.zcstudy.xiaole.KEEPALIVE_STOP"
        private const val CHANNEL_ID = "xiaole_keepalive"
        private const val CHANNEL_NAME = "后台保持连接"
        private const val NOTIFICATION_ID = 7301
        private const val STOP_ACTION_ID = 1
        // v6.11.21（78 轮）：服务自己也要持锁——只靠 Activity 侧
        // chat_page 的 acquire，一旦页面不在栈顶/删路径漏调，息屏照样冻结。
        // 上限 30 分钟：服务随回前台必停，超时只是兜底，避免长期耗电。
        private const val WAKE_LOCK_TIMEOUT_MS = 30 * 60 * 1000L
        private const val WAKE_LOCK_TAG = "XiaoLe:keepalive"

        // v6.11.22（79 轮 P0）：原生心跳。只靠 Dart 定时器一旦被 OEM 降权就毫无证据；
        // 这里每 30s 打一拍日志并唤醒 Dart（Dart 侧按需补发 listen:stop 到服务端）。
        private const val TICK_INTERVAL_MS = 30_000L

        // v6.11.23（80 轮）：ColorOS HANS 会连进程一起冻结，Handler 也停。
        // 加 AlarmManager 闹钟兜底：即使 Handler 停摆，系统闹钟仍有机会唤醒进程。
        // 注意：深度 doze 下不保证 60s 一发，闹钟只是"被冻结后仍有一次唤醒机会"。
        private const val ACTION_ALARM = "com.zcstudy.xiaole.KEEPALIVE_ALARM"
        private const val ALARM_INTERVAL_MS = 60_000L
        private const val ALARM_REQUEST_CODE = 7303

        /** 由 MainActivity 在 configureFlutterEngine 里注入，onDestroy 置空 */
        @Volatile
        var dartChannel: MethodChannel? = null

        @Volatile
        private var running = false

        fun isRunning(): Boolean = running

        /** 起前台服务；失败（如 API 31+ 后台启动限制）抛异常，交给调用方记 start_denied */
        fun start(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java)
                .setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KeepAliveService::class.java))
            running = false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private var wakeLock: PowerManager.WakeLock? = null

    private val handler = Handler(Looper.getMainLooper())
    private var tickSeq = 0
    private var ticking = false
    private val tickRunnable = object : Runnable {
        override fun run() {
            emitTick("native", TICK_INTERVAL_MS / 1000)
            handler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    /** 同一拍逻辑：自愈 wakelock（ColorOS 会强摘）→ 打日志 → 唤醒 Dart */
    private fun emitTick(source: String, intervalSec: Long) {
        tickSeq++
        ensureWakeLock()
        val ch = dartChannel
        Log.i(
            TAG,
            "[KEEPALIVE] tick#$tickSeq 来源=$source 间隔=${intervalSec}s " +
                "唤醒Dart=${if (ch == null) "否(无回调)" else "是"}",
        )
        try {
            ch?.invokeMethod("wakeup", null)
        } catch (_: Exception) {
            // Dart 已销毁/引擎 detached：不能影响下一拍
        }
    }

    /** ColorOS OplusProxyWakeLock 会把服务自持的锁强摘，每拍检查并按需重取 */
    private fun ensureWakeLock() {
        if (wakeLock?.isHeld == true) return
        Log.w(TAG, "[KEEPALIVE] wakelock_reacquire 原因=系统已释放")
        wakeLock = null
        acquireWakeLock()
    }

    private fun startTicking() {
        if (ticking) return
        ticking = true
        tickSeq = 0
        handler.post(tickRunnable)
    }

    private fun stopTicking() {
        if (!ticking) return
        ticking = false
        handler.removeCallbacks(tickRunnable)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
        Log.i(TAG, "[KEEPALIVE] wakelock on 上限=${WAKE_LOCK_TIMEOUT_MS / 1000}s")
    }

    private fun releaseWakeLock() {
        val wl = wakeLock ?: return
        if (wl.isHeld) {
            try {
                wl.release()
            } catch (_: Exception) {
            }
        }
        wakeLock = null
        Log.i(TAG, "[KEEPALIVE] wakelock off")
    }

    private fun alarmPendingIntent(): PendingIntent = PendingIntent.getService(
        this,
        ALARM_REQUEST_CODE,
        Intent(this, KeepAliveService::class.java).setAction(ACTION_ALARM),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun scheduleNextAlarm() {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        val at = SystemClock.elapsedRealtime() + ALARM_INTERVAL_MS
        // API 31+ 需要 SCHEDULE_EXACT_ALARM 授权；没有就用 allow-while-idle 非精确版
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        try {
            if (exact) {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    at,
                    alarmPendingIntent(),
                )
            } else {
                am.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    at,
                    alarmPendingIntent(),
                )
            }
            Log.i(TAG, "[KEEPALIVE] alarm_scheduled exact=$exact next=${ALARM_INTERVAL_MS / 1000}s")
        } catch (e: Exception) {
            Log.w(TAG, "[KEEPALIVE] alarm_schedule_failed $e")
        }
    }

    private fun cancelAlarm() {
        try {
            (getSystemService(ALARM_SERVICE) as AlarmManager).cancel(alarmPendingIntent())
            Log.i(TAG, "[KEEPALIVE] alarm_cancelled")
        } catch (_: Exception) {
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_ALARM) {
            // 闹钟到达：服务还活着才补拍；不在这里强行 startForeground
            if (!running) {
                Log.w(TAG, "[KEEPALIVE] alarm_ignored service_not_running")
                return START_NOT_STICKY
            }
            emitTick("alarm", ALARM_INTERVAL_MS / 1000)
            scheduleNextAlarm()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            // 通知栏「停止」：用户点一下就必须真停
            Log.i(TAG, "[KEEPALIVE] stop_action")
            stopTicking()
            cancelAlarm()
            releaseWakeLock()
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        acquireWakeLock()
        running = true
        startTicking()
        scheduleNextAlarm()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val exempt = pm.isIgnoringBatteryOptimizations(packageName)
        Log.i(
            TAG,
            "[KEEPALIVE] foreground_on id=$NOTIFICATION_ID battery_exempt=$exempt " +
                "dartChannel=${if (dartChannel == null) "未注入" else "已注入"}",
        )
        // 不自动重启：只在"有连接且进后台"时由 App 启动，避免常驻白挂
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        stopTicking()
        cancelAlarm()
        releaseWakeLock()
        Log.i(TAG, "[KEEPALIVE] service_destroyed")
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            // 低调：无声音、无震动、无横幅
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "小乐在后台时保持与云端的连接"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopService = PendingIntent.getService(
            this,
            STOP_ACTION_ID,
            Intent(this, KeepAliveService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            // 单色小图标：状态栏不出现彩色方块
            .setSmallIcon(R.drawable.ic_stat_keepalive)
            .setContentTitle("小乐正在保持连接")
            .setContentText("点按返回小乐")
            .setContentIntent(openApp)
            .addAction(0, "停止", stopService)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .build()
    }
}
