package com.zcstudy.xiaole

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.wangzan101.mika.core.remote.RemoteStatus
import com.wangzan101.mika.core.remote.StartOutcome
import com.wangzan101.mika.task.RemoteTaskHub
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Flutter 与本进程内 Mika 引擎之间的桥。
 *
 * 原先电脑侧经 adb forward 打到 Mika 的 MiniHttpServer(/api/v1/tasks);现在两者在同一进程,
 * 直接调 Mika 的 RemoteTaskHub,任务状态用与 HTTP 接口完全相同的 RemoteStatus.describe(JSON) 回给 Flutter。
 */
class MikaBridge(private val context: Context, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val hub: RemoteTaskHub
        get() = (context.applicationContext as com.wangzan101.mika.MikaApp).remoteTasks

    fun runTask(goal: String, result: MethodChannel.Result) {
        worker.execute {
            val id = UUID.randomUUID().toString()
            try {
                val outcome = hub.start(goal, null, id)
                if (outcome is StartOutcome.Refused) {
                    reply { result.success("""{"task_id":"$id","status":"refused","message":${quote(outcome.message)}}""") }
                    return@execute
                }
                var last = ""
                val started = System.currentTimeMillis()
                val deadline = started + 180_000
                while (System.currentTimeMillis() < deadline) {
                    val task = hub.get(id)
                    val status = RemoteStatus.of(task?.state)
                    if (status != last) {
                        last = status
                        emit("taskState", """{"task_id":"$id","status":"$status"}""")
                    }
                    if (RemoteStatus.finished(status)) break
                    if (task == null && System.currentTimeMillis() - started > LOST_MS) break
                    Thread.sleep(300)
                }
                val task = hub.get(id)
                val json = task?.let { RemoteStatus.describe(it).toString() }
                    ?: """{"task_id":"$id","status":"unknown"}"""
                reply { result.success(json) }
            } catch (e: Throwable) {
                reply { result.error("mika_run_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    fun cancel(id: String, result: MethodChannel.Result) {
        worker.execute { reply { result.success(hub.cancel(id)) } }
    }

    fun answer(id: String, text: String, result: MethodChannel.Result) {
        worker.execute { reply { result.success(hub.answer(id, text)) } }
    }

    fun openMikaUi(result: MethodChannel.Result) {
        try {
            context.startActivity(
                Intent(context, com.wangzan101.mika.ui.MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            result.success(true)
        } catch (e: Throwable) {
            result.error("mika_ui_failed", e.message ?: e.toString(), null)
        }
    }

    fun engineInfo(result: MethodChannel.Result) {
        result.success(
            mapOf(
                "version" to com.wangzan101.mika.BuildConfig.VERSION_NAME,
                "process" to android.os.Process.myPid(),
                "transport" to "in-process",
            )
        )
    }

    private fun emit(method: String, json: String) = main.post { channel.invokeMethod(method, json) }

    private fun reply(block: () -> Unit) = main.post(block)

    private fun quote(s: String): String =
        buildString {
            append('"')
            s.forEach { c ->
                when (c) {
                    '"' -> append("\\\"")
                    '\\' -> append("\\\\")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> if (c < ' ') append(String.format("\\u%04x", c.code)) else append(c)
                }
            }
            append('"')
        }

    private companion object {
        const val LOST_MS = 120_000L
    }
}
