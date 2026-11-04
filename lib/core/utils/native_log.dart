import 'package:flutter/services.dart';

/// release 包也能直读的关键日志。
///
/// Flutter 的 `debugPrint` 在 release 仍会走 `flutter` tag，但该缓冲区与系统日志
/// 共用、轮转很快（实测设备上一次 dump 只剩最近几分钟），排查时经常已经看不见。
/// 这里把验收要看的几类日志额外经 MethodChannel 交给原生 `Log.i("XiaoLe", ...)`，
/// 固定 tag/级别，`adb logcat -s XiaoLe` 即可直读，不受 Dart 侧日志实现影响。
class NativeLog {
  NativeLog._();

  static const MethodChannel _channel = MethodChannel('xiaole/log');

  /// 必须在 release 可见的四类前缀（MicGate 由原生侧用同名 tag 直接输出）
  static const List<String> requiredPrefixes = <String>[
    '[KEEPALIVE]',
    '[TEXTSPLIT]',
    '[RECONNECT]',
    '[PRECONNECT]',
    'MicGate',
  ];

  static bool isRequired(String message) =>
      requiredPrefixes.any(message.contains);

  /// 异步发送，失败静默：日志不能影响主流程。
  static void write(String message) {
    _channel.invokeMethod<void>('i', message).catchError((Object _) {});
  }
}
