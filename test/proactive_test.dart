import 'package:flutter_test/flutter_test.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_script_store.dart';

void main() {
  group('ProactiveWindow.contains', () {
    test('allDay 始终包含任意时刻', () {
      const w = ProactiveWindow(allDay: true);
      expect(w.contains(0), isTrue);
      expect(w.contains(1320), isTrue);
      expect(w.contains(1439), isTrue);
    });

    test('普通窗口：左闭右开', () {
      // 01:00 - 02:00
      const w = ProactiveWindow(allDay: false, startMin: 60, endMin: 120);
      expect(w.contains(60), isTrue); // 左闭
      expect(w.contains(119), isTrue);
      expect(w.contains(120), isFalse); // 右开
      expect(w.contains(59), isFalse);
      expect(w.contains(600), isFalse);
    });

    test('跨午夜窗口', () {
      // 22:00 - 08:00（start > end 视为跨午夜）
      const w = ProactiveWindow(allDay: false, startMin: 1320, endMin: 480);
      expect(w.contains(1320), isTrue); // 左闭
      expect(w.contains(1439), isTrue);
      expect(w.contains(0), isTrue);
      expect(w.contains(479), isTrue);
      expect(w.contains(480), isFalse); // 右开
      expect(w.contains(600), isFalse); // 白天不在窗口内
    });

    test('start == end 视为空窗口', () {
      const w = ProactiveWindow(allDay: false, startMin: 100, endMin: 100);
      expect(w.contains(100), isFalse);
    });
  });

  group('ProactiveScriptStore 轮换游标', () {
    test('restoreDefaults 后按序返回 4 条启用口令并循环', () async {
      await ProactiveScriptStore.restoreDefaults();
      final first = ProactiveScriptStore.nextRotatingText();
      final second = ProactiveScriptStore.nextRotatingText();
      final third = ProactiveScriptStore.nextRotatingText();
      final fourth = ProactiveScriptStore.nextRotatingText();
      final fifth = ProactiveScriptStore.nextRotatingText();

      expect(first, '读巡检口令执行');
      expect(second, '取巡检口令并按它执行');
      expect(third, '拉一下巡检口令');
      expect(fourth, '读巡检口令开始巡检');
      // 第 5 次回到第 1 条（循环）
      expect(fifth, first);
    });

    test('禁用部分口令后只轮换启用的', () async {
      await ProactiveScriptStore.restoreDefaults();
      final scripts = ProactiveScriptStore.scripts;
      // 禁用第 2、4 条（保留第 1、3 条启用）
      await ProactiveScriptStore.update(scripts[1].id, enabled: false);
      await ProactiveScriptStore.update(scripts[3].id, enabled: false);

      final a = ProactiveScriptStore.nextRotatingText();
      final b = ProactiveScriptStore.nextRotatingText();
      final c = ProactiveScriptStore.nextRotatingText();

      expect(a, '读巡检口令执行');
      expect(b, '拉一下巡检口令');
      expect(c, '读巡检口令执行'); // 循环回到第一条启用
    });

    test('全部禁用时返回内置第 1 条', () async {
      await ProactiveScriptStore.restoreDefaults();
      for (final s in ProactiveScriptStore.scripts) {
        await ProactiveScriptStore.update(s.id, enabled: false);
      }
      expect(ProactiveScriptStore.nextRotatingText(), '读巡检口令执行');
    });

    test('restoreDefaults 内置 4 条且首条为 active', () async {
      await ProactiveScriptStore.restoreDefaults();
      expect(ProactiveScriptStore.scripts.length, 4);
      expect(ProactiveScriptStore.active?.text, '读巡检口令执行');
    });
  });

  group('ProactiveScript 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const s = ProactiveScript(id: 'abc', text: '读巡检口令执行', enabled: false);
      final j = s.toJson();
      final s2 = ProactiveScript.fromJson(j);
      expect(s2.id, s.id);
      expect(s2.text, s.text);
      expect(s2.enabled, s.enabled);
    });

    test('copyWith 仅改指字段', () {
      const s = ProactiveScript(id: 'abc', text: '原文本');
      final s2 = s.copyWith(enabled: false);
      expect(s2.id, 'abc');
      expect(s2.text, '原文本');
      expect(s2.enabled, isFalse);
    });
  });
}
