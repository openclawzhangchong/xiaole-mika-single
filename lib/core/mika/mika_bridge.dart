import 'dart:convert';

import 'package:flutter/services.dart';

/// Flutter ↔ 同进程 Mika 引擎的桥。
///
/// 原链路是电脑经 `adb forward` 调 Mika 的 HTTP 接口(`/api/v1/tasks`)；
/// 合并成单包后这里直接调 Kotlin 侧的 `MikaBridge`(进程内 `RemoteTaskHub`)，
/// 返回的 JSON 与 Mika HTTP 接口的 `status` 响应结构一致。
class MikaBridge {
  MikaBridge._();

  static const MethodChannel _channel = MethodChannel('xiaole/mika');

  /// 任务状态变化（starting/running/queued/paused/done/failed/cancelled）。
  static void Function(Map<String, dynamic> event)? onTaskState;

  static bool _listening = false;

  /// 注册通道回调；页面初始化时调用一次即可。
  static void install() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'taskState' && call.arguments is String) {
        try {
          final event =
              Map<String, dynamic>.from(jsonDecode(call.arguments as String));
          onTaskState?.call(event);
        } catch (_) {
          // 忽略解析失败，避免影响任务本身
        }
      }
      return null;
    });
  }

  /// 进程内引擎信息：版本、PID、传输方式。
  static Future<Map<String, dynamic>> engineInfo() async {
    final info = await _channel.invokeMethod<Map<Object?, Object?>>('engineInfo');
    return Map<String, dynamic>.from(info ?? const {});
  }

  /// 提交一条任务，阻塞到终态（最长 180s），返回与 Mika HTTP 接口一致的 JSON。
  static Future<Map<String, dynamic>> runTask(String goal) async {
    final raw =
        await _channel.invokeMethod<String>('runTask', {'goal': goal}) ?? '{}';
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<bool> cancel(String id) async =>
      await _channel.invokeMethod<bool>('cancel', {'id': id}) ?? false;

  static Future<bool> answer(String id, String text) async =>
      await _channel.invokeMethod<bool>('answer', {'id': id, 'text': text}) ??
      false;

  /// 打开 Mika 原有界面（配模型、看任务记录、开无障碍）。
  static Future<bool> openMikaUi() async =>
      await _channel.invokeMethod<bool>('openMikaUi') ?? false;
}
