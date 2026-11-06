import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:opus_dart/opus_dart.dart';
import 'app/themes/app_theme.dart';
import 'app/routes/app_pages.dart';
import 'core/storage/storage_service.dart';
import 'core/providers/theme_provider.dart';
import 'package:logging/logging.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'core/utils/log_buffer.dart';
import 'core/utils/native_log.dart';
import 'core/utils/audio_util.dart';
import 'core/proactive/proactive_background.dart';
import 'core/service/keep_alive_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地存储
  await StorageService.instance.init();

  // v4.3.3：恢复日志分类开关（默认开 vision/ws/mcp/audio）
  await LogBuffer.loadCategories();

  // v4.4.0：恢复 AEC 通话通路偏好（默认开）
  AudioUtil.loadAecPref();

  // 配置 Logger - 添加这部分代码
  Logger.root.level = Level.ALL; // 设置日志级别
  Logger.root.onRecord.listen((record) {
    // v4.3.2：写入内存环形缓冲——开发者中心「📋 运行日志查看」的数据源。
    // 这里是全项目 package:logging 日志的唯一汇聚点，必须在最前面，
    // 否则 chat_page / cloud_sync 的 logger.info/severe 抓不进缓冲。
    LogBuffer.add(record);
    // release 验收日志：四类关键链路额外走原生 Log.i("XiaoLe")，见 core/utils/native_log.dart
    if (NativeLog.isRequired(record.message) || record.level >= Level.WARNING) {
      NativeLog.write('${record.level.name} ${record.loggerName}: ${record.message}');
    }
    // 使用 debugPrint 替代 print，避免警告
    debugPrint(
      '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}',
    );
  });

  // 79 轮 P0：注册原生 KeepAliveService 的 30s 唤醒回调（补 Dart tick 的兜底）
  KeepAliveService.init();

  // 初始化 Hive（日程映射存储）
  await Hive.initFlutter();

  initOpus(await opus_flutter.load());
  debugPrint('Opus初始化成功: ${getOpusVersion()}');

  // v6.8.0：AI 主动来电「后台化」——与总开关联动注册/取消 WorkManager 周期任务。
  // 启动期不申请通知权限（用户在开发者中心开启开关时才会申请）。
  await ProactiveBackground.syncWithSwitch(requestPermission: false);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动即检查"待处理来电"（后台命中触发、App 被通知拉起）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProactiveBackground.maybeShowPendingCallOnForeground();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时检查"待处理来电"（后台命中触发、用户点通知回前台）
    if (state == AppLifecycleState.resumed) {
      ProactiveBackground.maybeShowPendingCallOnForeground();
      // 回前台立刻收后台保活服务，不残留通知
      KeepAliveCoordinator.instance.onForegroundChanged(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 只在"将进入后台"瞬间起服务（Android 12+ 限制，起不来会打 start_denied）
      KeepAliveCoordinator.instance.onForegroundChanged(false);
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: '小乐',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: AppPages.router,
    );
  }
}
