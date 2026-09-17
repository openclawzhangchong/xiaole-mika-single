import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/presentation/services/app_feats.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_script_store.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_poll_service.dart';
import 'package:xiaozhi_client_flutter/presentation/pages/incoming_call_page.dart';

/// 主动来电「后台化」（v6.8.0，技术路线 V1：WorkManager 周期唤醒）
/// ------------------------------------------------------------------
/// 让已经做好的主动来电在用户退出 App / 锁屏后也能巡检并触发来电：
/// - 系统按最小 15 分钟周期拉起 App 跑**一轮**巡检再睡（无常驻通知/前台服务）；
/// - 命中触发时用**高优先临时通知**呈现（"小乐想和你通话"），点通知进入来电流程。
///
/// ⚠️ 本文件运行在**两个隔离的 Dart isolate**：
/// ① 前台 isolate（App 进程内）：`ensureWorkmanagerInitialized` / `syncWithSwitch` /
///    `maybeShowPendingCallOnForeground` / `initNotifications`；
/// ② 后台 isolate（WorkManager 拉起）：`callbackDispatcher` 内的 `executeTask` 闭包。
/// 两者通过 [StorageService]（SharedPreferences，跨进程/隔离共享）交换心跳与待处理来电。
///
/// 红线：不改动前台主动来电既有行为；不碰 `lib/core/network`；Device-Id 恒为 MAC 小写、
/// 巡检 Client-Id 每轮新生成（沿用 `ProactivePollService`）；任何后台异常都 catch，**绝不崩溃**。

// ===== 常量 =====
const String kWorkManagerTaskName = 'proactive_poll';
const String kNotifChannelId = 'proactive_call_channel';

/// 待处理来电持久化键（后台命中触发后写入；前台启动/回到前台时读取并进入来电页）
const String kPendingCallKey = 'xw_proactive_pending_call';

/// 最近一次前台"活跃 agent"持久化键（后台持久化待处理来电时，用于回填 agentId/agentName）
const String kLastAgentIdKey = 'xw_proactive_last_agent_id';
const String kLastAgentNameKey = 'xw_proactive_last_agent_name';

/// 通知权限被拒标记（开发者中心据此提示"通知被禁，来电无法提醒"）
const String kNotifDeniedKey = 'xw_proactive_notif_denied';

/// 前后台互斥阈值：前台心跳在最近 5 分钟内更新过 → 视为前台正在巡检，后台跳过。
const int kFgMutexThresholdMs = 5 * 60 * 1000;

/// 全局根导航键（用于通知点击 / 待处理来电进入来电页）
final GlobalKey<NavigatorState> appRootNavigatorKey = GlobalKey<NavigatorState>();

final Logger _logger = Logger('ProactiveBg');

/// 待处理来电数据模型（后台命中触发后持久化，供前台进入来电页）。
class PendingProactiveCall {
  final String opening;
  final String agentId;
  final String agentName;
  final int createdAt;

  const PendingProactiveCall({
    required this.opening,
    required this.agentId,
    required this.agentName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'opening': opening,
        'agentId': agentId,
        'agentName': agentName,
        'createdAt': createdAt,
      };

  factory PendingProactiveCall.fromJson(Map<String, dynamic> j) => PendingProactiveCall(
        opening: (j['opening'] as String?) ?? '',
        agentId: (j['agentId'] as String?) ?? '',
        agentName: (j['agentName'] as String?) ?? '小乐',
        createdAt: (j['createdAt'] as int?) ?? 0,
      );
}

/// 主动来电后台化的统一入口（命名空间）。
class ProactiveBackground {
  ProactiveBackground._();

  // ===== 纯函数（可单测，不发网络） =====

  /// 前后台互斥判定：前台心跳是否在阈值内。
  /// [heartbeatMillis] 为前台最近一次 tick 写入的时间戳；`null` 表示前台从未巡检过。
  static bool isForegroundActiveRecent(
    int? heartbeatMillis,
    int nowMillis,
    int thresholdMs,
  ) {
    if (heartbeatMillis == null) return false;
    // 防御：异常值或时钟回拨导致 now < heartbeat
    if (heartbeatMillis < 0 || nowMillis < heartbeatMillis) return false;
    return (nowMillis - heartbeatMillis) <= thresholdMs;
  }

  // ===== 待处理来电 持久化（同步读写，经 SharedPreferences） =====

  static Future<void> persistPendingCall(String opening) async {
    try {
      final agentId = StorageService.instance.getString(kLastAgentIdKey) ?? '';
      final agentName =
          StorageService.instance.getString(kLastAgentNameKey) ?? '小乐';
      final call = PendingProactiveCall(
        opening: opening,
        agentId: agentId,
        agentName: agentName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await StorageService.instance.setString(
          kPendingCallKey, jsonEncode(call.toJson()));
      _logger.info('后台巡检命中，已持久化待处理来电（agentName=$agentName）');
    } catch (e) {
      _logger.warning('持久化待处理来电失败（忽略）: $e');
    }
  }

  /// 同步读取（通知点击 / 启动检查路径使用，避免在 isolate 边界 await）。
  static PendingProactiveCall? readPendingCallSync() {
    try {
      final raw = StorageService.instance.getString(kPendingCallKey);
      if (raw == null || raw.isEmpty) return null;
      return PendingProactiveCall.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearPendingCall() async {
    try {
      await StorageService.instance.remove(kPendingCallKey);
    } catch (e) {
      _logger.warning('清除待处理来电失败（忽略）: $e');
    }
  }

  // ===== 前台活跃 agent 记录（供后台回填） =====

  static Future<void> rememberForegroundAgent(
      String agentId, String agentName) async {
    try {
      await StorageService.instance.setString(kLastAgentIdKey, agentId);
      await StorageService.instance.setString(kLastAgentNameKey, agentName);
    } catch (e) {
      // 非关键，忽略
    }
  }

  // ===== 通知 =====

  /// 初始化通知插件 + 高优先渠道（前后台 isolate 各调用一次，幂等）。
  static Future<void> initNotifications() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
        onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
      );
    } catch (e) {
      _logger.warning('通知初始化失败（忽略）: $e');
    }
  }

  /// 发出高优先来电通知。点击默认拉起 App（singleTop 复用主 Activity）；
  /// App 在前台时由 [_onNotificationTapped] 直接进入来电页。
  static Future<void> showProactiveCallNotification(String opening) async {
    try {
      await initNotifications();
      const android = AndroidNotificationDetails(
        kNotifChannelId,
        '小乐来电',
        channelDescription: 'AI 主动来电提醒（高优先级）',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      );
      await FlutterLocalNotificationsPlugin().show(
        0,
        '小乐想和你通话',
        opening.isNotEmpty ? opening : '点开听听它想说什么',
        const NotificationDetails(android: android),
      );
      _logger.info('已发出高优先来电通知');
    } catch (e) {
      _logger.warning('发出来电通知失败（忽略）: $e');
    }
  }

  /// 通知被禁标记读取（开发者中心展示用）。
  static bool isNotificationDenied() =>
      StorageService.instance.getBool(kNotifDeniedKey) ?? false;

  // ===== WorkManager 注册/取消（与总开关联动） =====

  /// 初始化 WorkManager（传入后台入口）。务必在 registerPeriodicTask 之前调用。
  static Future<void> ensureWorkmanagerInitialized() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      _logger.info('WorkManager 已初始化');
    } catch (e) {
      _logger.warning('WorkManager 初始化失败（忽略）: $e');
    }
  }

  /// 与总开关联动：开启 → 注册周期任务；关闭 → 取消（保证关闭=零唤醒）。
  /// [requestPermission]：是否在注册时申请通知权限（默认 true）。
  /// 启动期调用建议传 false，避免在用户尚未开启开关时弹出权限申请。
  static Future<void> syncWithSwitch({bool requestPermission = true}) async {
    try {
      await ensureWorkmanagerInitialized();
      if (!AppFeats.proactive) {
        await cancelTask();
        return;
      }
      if (requestPermission) {
        await _ensureNotificationPermission();
      }
      await registerTask();
    } catch (e, st) {
      _logger.severe('后台任务注册/取消失败（忽略）: $e\n$st');
    }
  }

  /// 注册周期任务。WorkManager 最小周期 15 分钟：若用户设定间隔 < 15，则按 15 执行。
  static Future<void> registerTask() async {
    final interval = ProactivePollService.instance.intervalMinutes < 15
        ? 15
        : ProactivePollService.instance.intervalMinutes;
    await Workmanager().registerPeriodicTask(
      kWorkManagerTaskName,
      kWorkManagerTaskName,
      frequency: Duration(minutes: interval),
      // v6.8.1：workmanager 锁 0.8.0（0.9.x 的 apple 子包与平台接口不匹配、Dart 编译失败；
      // 0.10.x 需 Flutter>=3.38）。0.8.0 用 ExistingWorkPolicy；
      // 选 replace 而非 keep —— 用户在 App 内改巡检间隔时需要按新频率重建任务。
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    _logger.info(
        '后台周期任务已注册，执行间隔=$interval 分钟（WorkManager 最小 15 分钟）');
  }

  static Future<void> cancelTask() async {
    await Workmanager().cancelByUniqueName(kWorkManagerTaskName);
    _logger.info('后台周期任务已取消（关闭=零唤醒、零流量）');
  }

  /// Android 13+ 运行时申请通知权限；被拒则置标记（开发者中心提示），不崩溃。
  static Future<void> _ensureNotificationPermission() async {
    try {
      if (!Platform.isAndroid) return;
      final status = await Permission.notification.status;
      if (status.isGranted) {
        await StorageService.instance.setBool(kNotifDeniedKey, false);
        return;
      }
      if (status.isPermanentlyDenied) {
        await StorageService.instance.setBool(kNotifDeniedKey, true);
        _logger.warning('通知权限被永久拒绝，来电无法提醒（已降级）');
        return;
      }
      final r = await Permission.notification.request();
      await StorageService.instance.setBool(kNotifDeniedKey, !r.isGranted);
      if (!r.isGranted) {
        _logger.warning('通知权限被拒，来电无法提醒（已优雅降级）');
      }
    } catch (e) {
      _logger.warning('通知权限申请异常（忽略，不阻断）: $e');
    }
  }

  // ===== 前台启动 / 回到前台：自动进入来电页 =====

  /// App 启动或回到前台时调用：若有待处理来电，清除并进入来电页。
  /// 由 [appRootNavigatorKey] 拿到根导航栈，无需 context。
  static void maybeShowPendingCallOnForeground() {
    try {
      final call = readPendingCallSync();
      if (call == null) return;
      unawaited(clearPendingCall());
      final nav = appRootNavigatorKey.currentState;
      if (nav == null) return;
      // 延迟一帧，确保路由已就绪
      Future.microtask(() {
        final n = appRootNavigatorKey.currentState;
        if (n == null) return;
        n.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallPage(
              opening: call.opening,
              agentId: call.agentId,
              agentName: call.agentName,
            ),
          ),
        );
      });
    } catch (e) {
      _logger.warning('读取待处理来电失败（忽略）: $e');
    }
  }
}

// ===== 后台 isolate 相关（顶层函数，供 WorkManager / 通知插件回调） =====

/// 按顺序最小初始化（任何一步失败都 catch 住安全退出，绝不崩）。
Future<void> _initMinimal() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await AppFeats.load();
  await ProactiveScriptStore.init();
}

/// WorkManager 后台 isolate 入口（@pragma 保证 tree-shake 后保留）。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task != kWorkManagerTaskName) return true;

      await _initMinimal();

      // 总开关守卫：关闭 → 直接返回，零流量、零网络请求
      if (!AppFeats.proactive) {
        _logger.info('主动来电总开关关闭，后台巡检零流量直接返回');
        return true;
      }

      // 前后台互斥：前台近期有心跳 → 前台正在巡检，本轮跳过
      final now = DateTime.now().millisecondsSinceEpoch;
      final hb = StorageService.instance.getInt(kFgHeartbeatKey);
      if (ProactiveBackground.isForegroundActiveRecent(
          hb, now, kFgMutexThresholdMs)) {
        _logger.info('前台近期有心跳，后台跳过本轮（前后台互斥）');
        return true;
      }

      // 命中触发时：持久化为"待处理来电"（后台 isolate 无 UI，不能直接弹来电页）
      ProactivePollService.instance.onTriggered = (opening) async {
        await ProactiveBackground.persistPendingCall(opening);
      };

      // 只跑一轮：绝不调用 start()（那是常驻 Timer）
      final triggered =
          await ProactivePollService.instance.runGuardedRoundForBackground();

      if (triggered) {
        final call = ProactiveBackground.readPendingCallSync();
        await ProactiveBackground.showProactiveCallNotification(
            call?.opening ?? '');
      } else {
        _logger.info('后台巡检本轮未触发');
      }
    } catch (e, st) {
      _logger.severe('后台巡检异常（已吞掉，不影响 App）: $e\n$st');
    }
    // 必须返回 true，否则 WorkManager 会重试
    return true;
  });
}

/// 通知点击回调（必须顶层函数，供插件在其他 isolate 调用）。
@pragma('vm:entry-point')
void _onNotificationTapped(NotificationResponse response) {
  final call = ProactiveBackground.readPendingCallSync();
  if (call == null) return;
  final nav = appRootNavigatorKey.currentState;
  if (nav == null) return;
  unawaited(ProactiveBackground.clearPendingCall());
  nav.push(
    MaterialPageRoute(
      builder: (_) => IncomingCallPage(
        opening: call.opening,
        agentId: call.agentId,
        agentName: call.agentName,
      ),
    ),
  );
}
