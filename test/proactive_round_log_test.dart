import 'package:flutter_test/flutter_test.dart';

import 'package:xiaozhi_client_flutter/core/proactive/proactive_round_log.dart';

/// 纯逻辑单测（不依赖 Flutter binding / 不触网）。
/// 仅验证：环形缓冲截断、JSON 往返、toPlainText 字段完整。
/// 由 lead 在统一的全量测试环节运行；此处保证语法/类型正确。
void main() {
  group('ProactiveRoundLog', () {
    test('环形缓冲：超过 maxRounds 后丢弃最旧、不无限增长', () {
      ProactiveRoundLog.clear();
      for (var i = 0; i < ProactiveRoundLog.maxRounds + 5; i++) {
        ProactiveRoundLog.recordSkip(skipReason: '时段外', source: 'tick');
      }
      expect(ProactiveRoundLog.length, ProactiveRoundLog.maxRounds);
      // 最新一条应为最后写入的「时段外」
      final entries = ProactiveRoundLog.entries;
      expect(entries.last.skipReason, '时段外');
      expect(entries.last.decision, 'skip');
    });

    test('entry JSON 往返：字段不丢', () {
      final e = ProactiveRoundLogEntry(
        time: DateTime(2026, 9, 18, 13, 1, 2),
        decision: 'inspect',
        commands: const ['读巡检口令执行', '拉一下巡检口令'],
        getScriptCalled: true,
        triggerCalled: true,
        skipCalled: false,
        opening: '在忙吗？今天降温记得添衣',
        durationMs: 4321,
        closeCode: '1000',
        alert: 'ERROR 服务忙',
        endReason: 'trigger',
      );
      final json = e.toJson();
      final back = ProactiveRoundLogEntry.fromJson(json);
      expect(back.decision, 'inspect');
      expect(back.commands, const ['读巡检口令执行', '拉一下巡检口令']);
      expect(back.getScriptCalled, isTrue);
      expect(back.triggerCalled, isTrue);
      expect(back.opening, '在忙吗？今天降温记得添衣');
      expect(back.durationMs, 4321);
      expect(back.closeCode, '1000');
      expect(back.alert, 'ERROR 服务忙');
      expect(back.endReason, 'trigger');
    });

    test('toPlainText 含全部关键字段（便于贴给 AI 诊断）', () {
      ProactiveRoundLog.clear();
      ProactiveRoundLog.recordInspection(
        rec: ProactiveRoundRecorder()
          ..addCommand('读巡检口令执行')
          ..markGetScript()
          ..markTrigger('在忙吗？今天降温记得添衣'),
        endReason: 'trigger',
      );
      final text = ProactiveRoundLog.toPlainText();
      expect(text, contains('开场白'));
      expect(text, contains('在忙吗？今天降温记得添衣'));
      expect(text, contains('get_script 调用'));
      expect(text, contains('close code'));
      expect(text, contains('触发来电'));
      expect(text, contains('口令'));
    });

    test('跳过轮次记录具体原因（验收②：时段外/冷却中/语音通话中/上一轮未结束）', () {
      ProactiveRoundLog.clear();
      ProactiveRoundLog.recordSkip(skipReason: '时段外', source: 'tick');
      ProactiveRoundLog.recordSkip(skipReason: '冷却中', source: 'bg');
      ProactiveRoundLog.recordSkip(skipReason: '语音通话中', source: 'tick');
      ProactiveRoundLog.recordSkip(skipReason: '上一轮未结束', source: 'busy');
      final text = ProactiveRoundLog.toPlainText();
      expect(text, contains('时段外'));
      expect(text, contains('冷却中'));
      expect(text, contains('语音通话中'));
      expect(text, contains('上一轮未结束'));
      expect(text, contains('跳过原因'));
    });
  });
}
