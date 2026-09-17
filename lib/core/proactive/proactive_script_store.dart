import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';

/// 单条「巡检口令」（轮换短口令，≤16 字）
class ProactiveScript {
  final String id;
  final String text;
  final bool enabled;

  const ProactiveScript({
    required this.id,
    required this.text,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'enabled': enabled,
      };

  factory ProactiveScript.fromJson(Map<String, dynamic> j) => ProactiveScript(
        id: j['id'] as String,
        text: j['text'] as String,
        enabled: (j['enabled'] as bool?) ?? true,
      );

  ProactiveScript copyWith({String? id, String? text, bool? enabled}) =>
      ProactiveScript(
        id: id ?? this.id,
        text: text ?? this.text,
        enabled: enabled ?? this.enabled,
      );
}

/// 允许来电时段（按当日分钟数判断）
class ProactiveWindow {
  final bool allDay;
  final int startMin; // 当日分钟数，如 22:00 = 1320
  final int endMin;

  const ProactiveWindow({
    this.allDay = true,
    this.startMin = 0,
    this.endMin = 0,
  });

  Map<String, dynamic> toJson() => {
        'allDay': allDay,
        'startMin': startMin,
        'endMin': endMin,
      };

  factory ProactiveWindow.fromJson(Map<String, dynamic> j) => ProactiveWindow(
        allDay: (j['allDay'] as bool?) ?? true,
        startMin: (j['startMin'] as int?) ?? 0,
        endMin: (j['endMin'] as int?) ?? 0,
      );

  /// 判断 [nowMin] 是否在允许来电时段内。
  /// - allDay：恒为 true
  /// - start > end：跨午夜窗口（如 22:00–08:00）
  /// - start < end：普通窗口（左闭右开）
  /// - start == end：空窗口，返回 false
  bool contains(int nowMin) {
    if (allDay) return true;
    if (startMin < endMin) {
      return nowMin >= startMin && nowMin < endMin;
    } else if (startMin > endMin) {
      return nowMin >= startMin || nowMin < endMin;
    }
    return false;
  }
}

/// 巡检口令存储（多条 CRUD + 轮换游标 + 允许来电时段 + 内置默认 + 恢复默认）
///
/// 持久化基于 [StorageService]（SharedPreferences + JSON）。
/// 钥匙：`xw_proactive_scripts` / `xw_proactive_active` / `xw_proactive_window`。
class ProactiveScriptStore {
  static const String _kScripts = 'xw_proactive_scripts';
  static const String _kActive = 'xw_proactive_active';
  static const String _kWindow = 'xw_proactive_window';

  /// 内置默认口令（≤16 字，逐字使用）
  static const List<String> _builtIn = <String>[
    '读巡检口令执行',
    '取巡检口令并按它执行',
    '拉一下巡检口令',
    '读巡检口令开始巡检',
  ];

  static List<ProactiveScript> _scripts = <ProactiveScript>[];
  static String? _activeId;
  static ProactiveWindow _window = const ProactiveWindow();

  /// 轮换游标（内存态，restoreDefaults 时归零）
  static int _rotationCounter = 0;

  ProactiveScriptStore._();

  /// 初始化：加载已持久化数据；若无数据则恢复默认。
  static Future<void> init() async {
    await StorageService.instance.init();
    await _load();
  }

  static Future<void> _load() async {
    final raw = StorageService.instance.getString(_kScripts);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _scripts = list.map((j) => ProactiveScript.fromJson(j)).toList();
      } catch (e) {
        _scripts = <ProactiveScript>[];
      }
    }
    if (_scripts.isEmpty) {
      await restoreDefaults();
      return;
    }
    _activeId = StorageService.instance.getString(_kActive);
    final wRaw = StorageService.instance.getString(_kWindow);
    if (wRaw != null && wRaw.isNotEmpty) {
      try {
        _window = ProactiveWindow.fromJson(jsonDecode(wRaw) as Map<String, dynamic>);
      } catch (e) {
        // 解析失败保持默认
      }
    }
  }

  /// 当前全部口令（返回副本，避免外部直接修改内部状态）
  static List<ProactiveScript> get scripts =>
      List<ProactiveScript>.from(_scripts);

  /// 当前"选中"的那条（activeId 命中 / 否则第一条启用 / 否则第一条）
  static ProactiveScript? get active {
    if (_scripts.isEmpty) return null;
    if (_activeId != null) {
      for (final s in _scripts) {
        if (s.id == _activeId) return s;
      }
    }
    for (final s in _scripts) {
      if (s.enabled) return s;
    }
    return _scripts.first;
  }

  static Future<void> setActive(String id) async {
    _activeId = id;
    await _persistActive();
  }

  static Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _scripts.add(ProactiveScript(
      id: const Uuid().v4(),
      text: t,
      enabled: true,
    ));
    await _persistScripts();
  }

  static Future<void> update(String id, {String? text, bool? enabled}) async {
    final idx = _scripts.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _scripts[idx] = _scripts[idx].copyWith(text: text, enabled: enabled);
    await _persistScripts();
  }

  /// 移除口令；若删的是 active，自动切到第一条启用的（无启用则第一条）。
  static Future<void> remove(String id) async {
    final wasActive = _activeId == id;
    _scripts.removeWhere((s) => s.id == id);
    if (wasActive) {
      _activeId = _firstEnabledId() ?? _firstScriptId();
    }
    await _persistScripts();
    await _persistActive();
  }

  static Future<void> restoreDefaults() async {
    _scripts = _builtIn
        .map((t) => ProactiveScript(id: const Uuid().v4(), text: t, enabled: true))
        .toList();
    _activeId = _scripts.first.id;
    _rotationCounter = 0;
    await _persistScripts();
    await _persistActive();
  }

  /// ★轮换游标：返回"下一个启用口令"，循环；无启用则返回内置第 1 条。
  static String nextRotatingText() {
    final enabled =
        _scripts.where((s) => s.enabled).toList(growable: false);
    if (enabled.isEmpty) return _builtIn.first;
    final s = enabled[_rotationCounter % enabled.length];
    _rotationCounter++;
    return s.text;
  }

  static ProactiveWindow get window => _window;

  static Future<void> setWindow(ProactiveWindow w) async {
    _window = w;
    await _persistWindow();
  }

  // ---------- 内部辅助 ----------

  static String? _firstEnabledId() {
    for (final s in _scripts) {
      if (s.enabled) return s.id;
    }
    return null;
  }

  static String? _firstScriptId() {
    return _scripts.isEmpty ? null : _scripts.first.id;
  }

  static Future<void> _persistScripts() async {
    await StorageService.instance.setString(
      _kScripts,
      jsonEncode(_scripts.map((s) => s.toJson()).toList()),
    );
  }

  static Future<void> _persistActive() async {
    if (_activeId != null) {
      await StorageService.instance.setString(_kActive, _activeId!);
    }
  }

  static Future<void> _persistWindow() async {
    await StorageService.instance.setString(_kWindow, jsonEncode(_window.toJson()));
  }
}
