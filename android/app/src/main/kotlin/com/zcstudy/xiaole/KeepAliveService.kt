package com.zcstudy.xiaole

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 后台保持连接（方案 B）：只负责让进程在后台时不被系统冻结，服务内不跑任何业务。
 * 心跳仍然是 Dart 侧 45s 那套，服务本身不发包、不判活，只贴一条低调的常驻通知。
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

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 通知栏「停止」：用户点一下就必须真停
            Log.i(TAG, "[KEEPALIVE] stop_action")
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        running = true
        Log.i(TAG, "[KEEPALIVE] foreground_on id=$NOTIFICATION_ID")
        // 不自动重启：只在"有连接且进后台"时由 App 启动，避免常驻白挂
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
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
