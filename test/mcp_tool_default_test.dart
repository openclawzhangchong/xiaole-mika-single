import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/presentation/services/app_feats.dart';

/// v6.9.1 回归守护：MCP 工具的**默认启用**判定。
///
/// 背景（真实的回归缺陷）：
/// `AppFeats.mcpToolEnabled()` 同时服务「设备工具」与「外部 MCP 工具」
/// （`chat_page` 只向 responder 注入这一个 `isToolEnabled`）。
/// v6.8.1（E 项）把默认值统一改成了「只放行 5 项设备工具白名单」，
/// 而这些外部工具名是 `notes.*`（biji-notes）/ `amap.*`（高德），**不在白名单**
/// ⇒ 外部工具**全部**被判为禁用 ⇒ `tools/list` 不再下发
/// ⇒ 小智 AI 完全看不到外部 MCP 的工具。
/// 症状：v6.4.4 能用 → v6.8.1 起「识别不到外部 MCP」。
///
/// 本文件锁死两条边界（这次就是缺测试才让它溜过去的）：
/// 1. **非 `self.` 前缀（外部 MCP 工具）默认必须启用**；
/// 2. `self.*` 设备工具仍按 v6.8.1（E 项）白名单——仅 5 项默认开，其余默认关。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 与 agent_avatar_store_test.dart 同款：Hive.initFlutter 需要 path_provider
    final tmpDir = Directory.systemTemp.createTempSync('xiaole_mcptool_hive');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmpDir.path,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.instance.init();
  });

  setUp(() => AppFeats.resetMcpToolCache());

  group('① 外部 MCP 工具：默认必须启用（v6.9.1 回归守护）', () {
    test('内置预置 biji-notes / amap 的工具默认放行', () {
      for (final n in const <String>[
        'notes.search_notes',
        'notes.add_note',
        'notes.list_notes',
        'amap.geocode',
        'amap.map_around_search',
        'amap.route_plan',
      ]) {
        expect(
          AppFeats.mcpToolEnabled(n),
          isTrue,
          reason: '外部 MCP 工具 $n 默认应启用，否则 AI 在 tools/list 里看不到它',
        );
      }
    });

    test('任意非 self. 前缀（含用户自定义前缀）也应默认放行', () {
      for (final n in const <String>['my_mcp.some_tool', 'foo.bar', 'mcp.any']) {
        expect(AppFeats.mcpToolEnabled(n), isTrue,
            reason: '$n 非 self. 前缀（= 外部 MCP），应默认放行');
      }
    });
  });

  group('② 设备工具：仍按 v6.8.1（E 项）白名单', () {
    test('白名单 5 项默认开', () {
      for (final n in const <String>[
        'self.location.get_current',
        'self.alarm.set_alarm',
        'self.map.navigate',
        'self.screen.set_brightness',
        'self.audio_speaker.set_volume',
      ]) {
        expect(AppFeats.mcpToolEnabled(n), isTrue, reason: '$n 属白名单，默认应开');
      }
    });

    test('白名单外的设备工具默认关（E 项本意，未被本次修复破坏）', () {
      for (final n in const <String>[
        'self.screen.snapshot',
        'self.timer.create_countdown',
        'self.get_device_status',
      ]) {
        expect(AppFeats.mcpToolEnabled(n), isFalse,
            reason: '$n 不在白名单，默认应关（v6.8.1 E 项设计意图）');
      }
    });
  });

  group('③ 已存值优先于默认值（不被默认值回滚）', () {
    test('用户手动关闭的外部工具，冷启动后仍是关闭', () async {
      AppFeats.setMcpToolEnabled('notes.add_note', false);
      await Future<void>.delayed(Duration.zero); // 让持久化落盘
      AppFeats.resetMcpToolCache(); // 模拟冷启动清运行时缓存
      expect(
        AppFeats.mcpToolEnabled('notes.add_note'),
        isFalse,
        reason: '已存值不得被「外部工具默认放行」回滚',
      );
    });

    test('用户手动开启的白名单外设备工具，冷启动后仍是开启', () async {
      AppFeats.setMcpToolEnabled('self.screen.snapshot', true);
      await Future<void>.delayed(Duration.zero);
      AppFeats.resetMcpToolCache();
      expect(
        AppFeats.mcpToolEnabled('self.screen.snapshot'),
        isTrue,
        reason: '已存值不得被白名单默认值回滚',
      );
    });
  });
}
