import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/presentation/services/agent_avatar_store.dart';

/// C 项（头像升级）纯逻辑单测。
///
/// 重点覆盖 v6.8.3 实测踩到的**两个真 bug**：
/// 1. `read()` 曾用"默认值"覆盖了刚同步读进缓存的**已存配置** ⇒ 用户保存的头像永远不生效；
/// 2. `_lazyLoad()` 曾在 build 期间同步 `revision.value++` ⇒
///    `setState() or markNeedsBuild() called during build` 断言。
/// 本文件守住"存 → 清内存 → 再读能拿回已存值"这条关键路径。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Hive.initFlutter 需要 path_provider，测试环境用临时目录顶替
    final tmpDir = Directory.systemTemp.createTempSync('xiaole_avatar_hive');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmpDir.path,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.instance.init();
  });

  setUp(() => AgentAvatarStore.resetForTest());

  group('落地持久化：存 → 清内存 → 再读', () {
    test('read() 能读回已存配置（回归：曾被默认值覆盖）', () async {
      const saved = AgentAvatarConfig(
        mode: 2,
        customChar: '',
        paletteIndex: 5,
        imagePath: null,
      );
      await AgentAvatarStore.save('agent_a', saved);

      // 模拟"下次冷启动"：清掉内存缓存，只剩 SharedPreferences
      AgentAvatarStore.resetForTest();

      final first = AgentAvatarStore.read('agent_a');
      expect(first.mode, 2, reason: '取字模式必须是已存的第 3 字，而不是默认第 1 字');
      expect(first.paletteIndex, 5, reason: '色板必须是已存的 5，而不是默认派生值');
      expect(first.imagePath, isNull);
    });

    test('load() 总是回读存储，不受缓存占位影响', () async {
      const saved = AgentAvatarConfig(mode: -2, paletteIndex: 3);
      await AgentAvatarStore.save('agent_b', saved);
      AgentAvatarStore.resetForTest();

      // 先 read 造成"缓存占位"，再 load 必须仍是已存值
      AgentAvatarStore.read('agent_b');
      final cfg = await AgentAvatarStore.load('agent_b');
      expect(cfg.mode, -2);
      expect(cfg.paletteIndex, 3);
    });

    test('未存过的 agent 回落默认：mode=0 + 由 id 派生色板', () async {
      AgentAvatarStore.resetForTest();
      final cfg = AgentAvatarStore.read('never_saved_agent');
      expect(cfg.mode, 0);
      expect(cfg.customChar, '');
      expect(cfg.imagePath, isNull);
      expect(
        cfg.paletteIndex,
        AgentAvatarStore.defaultConfig('never_saved_agent').paletteIndex,
      );
    });

    test('clear 图片：imagePath 置空后不再有图片（回落文字头像）', () async {
      await AgentAvatarStore.save(
        'agent_c',
        const AgentAvatarConfig(imagePath: '/not/exist/pic.png'),
      );
      AgentAvatarStore.resetForTest();
      expect(AgentAvatarStore.read('agent_c').imagePath, '/not/exist/pic.png');

      await AgentAvatarStore.save(
        'agent_c',
        const AgentAvatarConfig(imagePath: null),
      );
      AgentAvatarStore.resetForTest();
      expect(AgentAvatarStore.read('agent_c').imagePath, isNull);
      // 删除不存在的文件不应抛异常
      await AgentAvatarStore.deleteImage('/not/exist/pic.png');
    });

    test('配置 JSON 往返不丢字段', () {
      const cfg = AgentAvatarConfig(
        mode: -1,
        customChar: '好',
        paletteIndex: 7,
        imagePath: '/x/y.png',
      );
      final back = AgentAvatarConfig.fromString(cfg.toJsonString());
      expect(back.mode, -1);
      expect(back.customChar, '好');
      expect(back.paletteIndex, 7);
      expect(back.imagePath, '/x/y.png');
      // 脏数据不崩
      expect(AgentAvatarConfig.fromString('{oops').mode, 0);
      expect(AgentAvatarConfig.fromString(null).mode, 0);
      expect(AgentAvatarConfig.fromString('').mode, 0);
    });
  });

  group('色板对比度（不做任意取色器）', () {
    test('12 套色板，每套按亮度选安全字色', () {
      expect(kAgentAvatarPalette.length, 12);
      for (final p in kAgentAvatarPalette) {
        expect(p.bg.length, 2, reason: '每套应为渐变（两色）');
        // 字色只有两种安全选择：白字（深底）或深灰字（浅底）
        final isWhite = p.fg.toARGB32() == 0xFFFFFFFF;
        final isDarkGray = p.fg.toARGB32() == 0xFF2C2C2E;
        expect(isWhite || isDarkGray, isTrue,
            reason: '字色必须是安全的白或深灰，避免撞色看不清');
        // 渐变两端亮度接近（同明暗档），避免同一底色上出现"一半看得清一半看不清"
        final l0 = p.bg[0].computeLuminance();
        final l1 = p.bg[1].computeLuminance();
        expect((l0 - l1).abs() < 0.35, isTrue,
            reason: '同套渐变两端明暗差不宜过大');
        // 白字必须配深底，深灰字必须配浅底
        final brightest = l0 > l1 ? l0 : l1;
        if (isWhite) {
          expect(brightest, lessThan(0.45), reason: '白字必须配深底');
        } else {
          expect(brightest, greaterThan(0.55), reason: '深灰字必须配浅底');
        }
      }
    });
  });

  group('文字头像取字', () {
    test('默认第 1 字 / 第 2 / 第 3 / 末字', () {
      const name = '小乐乐AI';
      expect(AgentAvatarStore.pickDisplayChar(name, 0, ''), '小');
      expect(AgentAvatarStore.pickDisplayChar(name, 1, ''), '乐');
      expect(AgentAvatarStore.pickDisplayChar(name, 2, ''), '乐');
      expect(AgentAvatarStore.pickDisplayChar(name, -2, ''), 'I');
    });

    test('取字越界回落第 1 字', () {
      expect(AgentAvatarStore.pickDisplayChar('小乐', 2, ''), '小');
      expect(AgentAvatarStore.pickDisplayChar('小乐', 1, ''), '乐');
    });

    test('自填一字（mode=-1）：取首字；为空回落 乐', () {
      expect(AgentAvatarStore.pickDisplayChar('任意名字', -1, '好'), '好');
      expect(AgentAvatarStore.pickDisplayChar('任意名字', -1, '好字多'), '好');
      expect(AgentAvatarStore.pickDisplayChar('任意名字', -1, '  '), '乐');
    });

    test('用户自填优先于名字；名字为空回落 乐', () {
      expect(AgentAvatarStore.pickDisplayChar('', 0, ''), '乐');
      expect(AgentAvatarStore.pickDisplayChar('   ', 2, ''), '乐');
    });
  });
}
