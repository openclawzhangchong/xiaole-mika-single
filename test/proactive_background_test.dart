import 'package:flutter_test/flutter_test.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_poll_service.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_background.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_script_store.dart';

/// 纯逻辑单测（不发网络）：
/// 1) 三守卫 [checkGuardReason] —— 前后台共用同一份实现，禁止复制粘贴两份；
/// 2) 前后台互斥判定 [ProactiveBackground.isForegroundActiveRecent]。
void main() {
  group('checkGuardReason（三守卫，前后台共用）', () {
    // 全天窗口，便于单独验证冷却/语音守卫
    const allDay = ProactiveWindow(allDay: true);
    // 22:00–08:00 跨午夜窗口
    const night = ProactiveWindow(allDay: false, startMin: 1320, endMin: 480);

    test('窗口外 → 返回"窗口外"', () {
      // 13:00（780 分）不在 22:00–08:00 内
      expect(
        checkGuardReason(
          nowMin: 780,
          window: night,
          lastTriggerAt: null,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        '窗口外',
      );
    });

    test('窗口内但冷却期内 → 返回"冷却期内"', () {
      final last = DateTime.now().subtract(const Duration(minutes: 30));
      expect(
        checkGuardReason(
          nowMin: 0,
          window: allDay,
          lastTriggerAt: last,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        '冷却期内',
      );
    });

    test('冷却期刚过（等于阈值）→ 放行（null）', () {
      final last = DateTime.now().subtract(const Duration(minutes: 120));
      expect(
        checkGuardReason(
          nowMin: 0,
          window: allDay,
          lastTriggerAt: last,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        isNull,
      );
    });

    test('无冷却、但语音通话中 → 返回"语音通话中"', () {
      expect(
        checkGuardReason(
          nowMin: 0,
          window: allDay,
          lastTriggerAt: null,
          cooldownMinutes: 120,
          voiceActive: true,
        ),
        '语音通话中',
      );
    });

    test('窗口内 + 冷却已过 + 未通话 → 放行（null）', () {
      final last = DateTime.now().subtract(const Duration(minutes: 999));
      expect(
        checkGuardReason(
          nowMin: 0,
          window: allDay,
          lastTriggerAt: last,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        isNull,
      );
    });

    test('跨午夜窗口内（凌晨 3 点）→ 放行', () {
      expect(
        checkGuardReason(
          nowMin: 180, // 03:00
          window: night,
          lastTriggerAt: null,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        isNull,
      );
    });
  });

  group('isForegroundActiveRecent（前后台互斥判定）', () {
    const threshold = 5 * 60 * 1000; // 5 分钟

    test('心跳为 null → 视为前台从未巡检，返回 false', () {
      expect(
        ProactiveBackground.isForegroundActiveRecent(null, 1000, threshold),
        isFalse,
      );
    });

    test('心跳在阈值内（1 分钟前）→ true', () {
      const now = 10 * 60 * 1000;
      final hb = now - 1 * 60 * 1000;
      expect(
        ProactiveBackground.isForegroundActiveRecent(hb, now, threshold),
        isTrue,
      );
    });

    test('心跳超出阈值（10 分钟前）→ false', () {
      const now = 10 * 60 * 1000;
      final hb = now - 10 * 60 * 1000;
      expect(
        ProactiveBackground.isForegroundActiveRecent(hb, now, threshold),
        isFalse,
      );
    });

    test('心跳恰好在阈值边界（5 分钟前）→ true', () {
      const now = 10 * 60 * 1000;
      final hb = now - threshold;
      expect(
        ProactiveBackground.isForegroundActiveRecent(hb, now, threshold),
        isTrue,
      );
    });

    test('时钟回拨（now < heartbeat）→ false（防御异常值）', () {
      const now = 5 * 60 * 1000;
      const hb = 6 * 60 * 1000;
      expect(
        ProactiveBackground.isForegroundActiveRecent(hb, now, threshold),
        isFalse,
      );
    });

    test('心跳为负值 → false', () {
      expect(
        ProactiveBackground.isForegroundActiveRecent(-1, 1000, threshold),
        isFalse,
      );
    });
  });

  group('守卫复用正确性（runGuardedRoundForBackground 存在且复用 checkGuardReason）', () {
    test('ProactivePollService 暴露带守卫的单轮入口', () {
      // 仅校验方法存在且签名可用（不真正发起网络）
      expect(
        ProactivePollService.instance.runGuardedRoundForBackground,
        isA<Function>(),
      );
    });

    test('ProactiveScriptStore 窗口与守卫逻辑一致（全天窗口通过）', () {
      expect(
        checkGuardReason(
          nowMin: 0,
          window: ProactiveScriptStore.window, // 默认全天后由脚本库提供
          lastTriggerAt: null,
          cooldownMinutes: 120,
          voiceActive: false,
        ),
        isNull,
      );
    });
  });
}
