import 'package:flutter/services.dart';

import '../../app/config/app_config.dart';
import '../storage/storage_service.dart';
import '../utils/native_log.dart';

/// 后台保持连接（方案 B）通道：前台服务只负责"不被系统冻结"，
/// 81 起原生闹钟只做 wakelock 自愈；82 起原生不再唤醒 Dart（只打 `wakeup#` 日志）。
class KeepAliveService {
  KeepAliveService._();

  static const MethodChannel _channel = MethodChannel('xiaole/keepalive');

  /// 82：原生闹钟（60s）只自愈 wakelock，不再 `invokeMethod("wakeup")`。
  /// 保留通道注册，但任何 method call 都不触发任何连接动作。
  static void init() {
    _channel.setMethodCallHandler((MethodCall call) async => null);
  }

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

  /// 80 轮：是否已在电池优化白名单（ColorOS 用这个状态决定是否冻结进程）
  static Future<bool> batteryExempt() async {
    try {
      return await _channel.invokeMethod<bool>('batteryExempt') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 80 轮：打开系统"忽略电池优化"授权；被 ROM 拦截时回退到电池优化列表页
  static Future<bool> requestBatteryExempt() async {
    try {
      return await _channel.invokeMethod<bool>('requestBatteryExempt') ?? false;
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
  bool _notifAsked = false;

  /// 82：服务/通知的存活只看前后台：后台断线也必须留着通知与前台服务
  /// （81 的 "-> 断线即 stopService" 会让息屏被回收后通知消失，验收判 FAIL）。
  void onConnectionChanged(bool connected) {
    _connected = connected;
    if (!_foreground) return; // 后台：无论连没连都保持服务，变化留给回前台时 sync
    sync();
  }

  void onForegroundChanged(bool foreground) {
    _foreground = foreground;
    // Android 13+ 没通知权限时前台服务能起、但通知栏看不见，验收会判 FAIL；
    // 回前台（有 Activity，可弹框）时补一次授权请求，只问一次。
    if (foreground) _ensureNotificationPermission();
    sync();
  }

  Future<void> _ensureNotificationPermission() async {
    if (_notifAsked) return;
    _notifAsked = true;
    if (!enabled) return;
    if (await KeepAliveService.notificationsEnabled()) return;
    final granted = await KeepAliveService.requestNotificationPermission();
    NativeLog.write('[KEEPALIVE] notif_permission requested granted=$granted');
  }

  Future<void> sync() async {
    // 82：服务/通知的存活只看前后台，不看 socket——后台断线也必须留着那条通知，
    // 否则息屏被服务端回收后通知消失，82 验收「后台通知在」直接 FAIL。
    final want = enabled && !_foreground;
    NativeLog.write('[KEEPALIVE] sync want=$want running=$_serviceRunning '
        'conn=$_connected fg=$_foreground enabled=$enabled');
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
