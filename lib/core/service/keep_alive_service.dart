import 'package:flutter/services.dart';

import '../../app/config/app_config.dart';
import '../storage/storage_service.dart';
import '../utils/native_log.dart';

/// 后台保持连接（方案 B）通道：前台服务只负责"不被系统冻结"，
/// 心跳仍由 Dart 侧 45s 逻辑负责，服务里不跑业务。
class KeepAliveService {
  KeepAliveService._();

  static const MethodChannel _channel = MethodChannel('xiaole/keepalive');

  /// 起服务；系统拒绝（如 API 31+ 后台启动限制）返回 false，并落 [KEEPALIVE] start_denied
  static Future<bool> start() async {
    try {
      final ok = await _channel.invokeMethod<bool>('start') ?? false;
      return ok;
    } on PlatformException catch (e) {
      NativeLog.write('[KEEPALIVE] start_denied code=${e.code} msg=${e.message}');
      return false;
    } on MissingPluginException {
      NativeLog.write('[KEEPALIVE] start_denied code=NO_PLUGIN');
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // 停服务失败不阻塞主流程
    }
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> notificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Android 13+ 弹系统通知授权框；13 以下或已授权直接返回 true
  static Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 统一裁决"什么时候挂服务"：开关开 + 有活跃连接 + App 在后台。
class KeepAliveCoordinator {
  KeepAliveCoordinator._();

  static final KeepAliveCoordinator instance = KeepAliveCoordinator._();

  /// 设置项「后台保持连接」，默认开
  bool get enabled => StorageService.instance.getBool(AppConfig.keyKeepAlive) ?? true;

  bool _connected = false;
  bool _foreground = true;
  bool _serviceRunning = false;

  void onConnectionChanged(bool connected) {
    _connected = connected;
    sync();
  }

  void onForegroundChanged(bool foreground) {
    _foreground = foreground;
    sync();
  }

  Future<void> sync() async {
    final want = enabled && _connected && !_foreground;
    if (want == _serviceRunning) return;
    if (want) {
      _serviceRunning = await KeepAliveService.start();
    } else {
      await KeepAliveService.stop();
      _serviceRunning = false;
      NativeLog.write('[KEEPALIVE] service_released');
    }
  }

  /// 设置页关掉开关：落盘 + 立即停服务（含通知栏那条）
  Future<void> setEnabled(bool value) async {
    await StorageService.instance.setBool(AppConfig.keyKeepAlive, value);
    sync();
  }

  /// 设置页打开开关：先要通知权限，被拒则不落盘、不起服务，由 UI 回弹
  Future<bool> enableWithPermission() async {
    if (!await KeepAliveService.notificationsEnabled()) {
      final granted = await KeepAliveService.requestNotificationPermission();
      if (!granted) {
        NativeLog.write('[KEEPALIVE] notif_permission denied');
        return false;
      }
    }
    await StorageService.instance.setBool(AppConfig.keyKeepAlive, true);
    sync();
    return true;
  }
}
