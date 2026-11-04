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

  /// 配置引擎的 OpenAI 兼容模型（等价于 Mika 设置里的「添加服务商」）。
  static Future<bool> configureProvider({
    required String baseUrl,
    required String model,
    String apiKey = '',
  }) async =>
      await _channel.invokeMethod<bool>('configureProvider', {
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
      }) ??
      false;

  /// 打开 Mika 原有界面（配模型、看任务记录、开无障碍）。
  static Future<bool> openMikaUi() async =>
      await _channel.invokeMethod<bool>('openMikaUi') ?? false;

  /// 录音前申请麦克风租约。Mika 的按住说话用同一把锁：
  /// 拿不到说明 Mika 正在录音，本次通话应直接放弃，避免两路 MIC 把对方打成静音。
  ///
  /// 非 Android 平台（桌面/测试）没有这个通道，视为"随便用"。
  static Future<bool> acquireMic() async {
    try {
      return await _channel.invokeMethod<bool>('acquireMic') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// 停止录音后一定要还租约（异常路径也要还，否则麦克风会被永久占住）。
  static Future<void> releaseMic() async {
    try {
      await _channel.invokeMethod<bool>('releaseMic');
    } on MissingPluginException {
      // 非 Android 平台，忽略
    } on PlatformException {
      // 引擎没起或已销毁，忽略
    }
  }

  /// 当前麦克风持有者：`xiaole` / `mika` / `null`。调试与自检用。
  static Future<String?> micHolder() async {
    try {
      return await _channel.invokeMethod<String>('micHolder');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
