/// v6.8.3（A 项）：MCP 电话日志 —— 巡检轮**旁路记录层**。
///
/// 定位：**只读旁路，零行为变更**。巡检链路本身（三守卫 / 22s 超时 / 12s 重发 /
/// 4 个 MCP 工具 / 时序）一个字都不改；本文件只负责把"每一轮到底发生了什么"
/// 结构化留存，供开发者中心「📞 电话日志」页查看与**一键复制**给 AI 诊断。
///
/// 设计要点：
/// - **跳过轮也留痕**，且写明**具体原因**（时段外 / 冷却中 / 语音通话中 /
///   上一轮未结束 / 服务未初始化 / WS 地址为空）——只记"跳过"是没用的；
/// - **最近 [ProactiveRoundLog.maxRounds] 轮环形缓冲**（超出丢最旧，不无限增长）；
/// - **持久化**（SharedPreferences，键 [ProactiveRoundLog.keyStorage]）——
///   App 重启后日志仍在；存储不可用时**优雅降级为纯内存**，绝不抛异常；
/// - logger 名以 `Proactive` 开头 ⇒ 运行日志自动归入 `LogBuffer` 的 `proactive`
///   分类（页面是"结构化视图"，日志照写，两边打通）。
///
/// ⚠️ **写入顺序铁律**：`recordXxx` 是同步 API，但持久化必须**等历史加载完**
/// 再写盘，否则 App 启动后的第一次记录会用"只有一条"的数组覆盖掉旧历史。
/// 故 `_persistAfterLoad` 先 `await load()` 再落盘。
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import '../storage/storage_service.dart';

/// 单条巡检记录（不可变；`decision` 区分"跳过轮"与"真正跑过的巡检轮"）。
class ProactiveRoundLogEntry {
  /// 记录时间
  final DateTime time;

  /// `'skip'` = 未建立会话即跳过；`'inspect'` = 真正跑过一轮巡检
  final String decision;

  /// 跳过原因（`decision == 'skip'` 时非空，措辞见 [ProactiveRoundLog.recordSkip]）
  final String? skipReason;

  /// 跳过来源：`tick`(前台周期) / `bg`(后台单轮) / `busy` / `inspect`(进轮后校验失败)
  final String? source;

  /// 本轮实际发出的口令（[0] 为 detect 口令，[1] 为 12s 未响应时的轮换重发）
  final List<String> commands;

  /// 是否被 AI 调用过 `self.proactive.get_script`
  final bool getScriptCalled;

  /// 是否收到 `self.proactive.trigger_call`
  final bool triggerCalled;

  /// 是否收到 `self.proactive.skip`
  final bool skipCalled;

  /// 开场白原文（`trigger_call` 的 message）
  final String? opening;

  /// 本轮耗时（毫秒）
  final int durationMs;

  /// 巡检会话 close code（断开事件采集；拿不到为 null）
  final String? closeCode;

  /// 服务器 `alert` 原文（若有）
  final String? alert;

  /// 结束原因：`trigger` / `skip` / `timeout` / `finally` / `stop`
  final String? endReason;

  const ProactiveRoundLogEntry({
    required this.time,
    required this.decision,
    this.skipReason,
    this.source,
    this.commands = const <String>[],
    this.getScriptCalled = false,
    this.triggerCalled = false,
    this.skipCalled = false,
    this.opening,
    this.durationMs = 0,
    this.closeCode,
    this.alert,
    this.endReason,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': time.toIso8601String(),
        'd': decision,
        if (skipReason != null) 'sr': skipReason,
        if (source != null) 'sc': source,
        if (commands.isNotEmpty) 'cm': commands,
        'gs': getScriptCalled,
        'tc': triggerCalled,
        'sk': skipCalled,
        if (opening != null) 'op': opening,
        'ms': durationMs,
        if (closeCode != null) 'cc': closeCode,
        if (alert != null) 'al': alert,
        if (endReason != null) 'er': endReason,
      };

  static ProactiveRoundLogEntry fromJson(Map<String, dynamic> json) {
    return ProactiveRoundLogEntry(
      time: DateTime.tryParse(json['t'] as String? ?? '') ?? DateTime.now(),
      decision: (json['d'] as String?) ?? 'inspect',
      skipReason: json['sr'] as String?,
      source: json['sc'] as String?,
      commands: (json['cm'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[],
      getScriptCalled: json['gs'] == true,
      triggerCalled: json['tc'] == true,
      skipCalled: json['sk'] == true,
      opening: json['op'] as String?,
      durationMs: (json['ms'] as num?)?.toInt() ?? 0,
      closeCode: json['cc'] as String?,
      alert: json['al'] as String?,
      endReason: json['er'] as String?,
    );
  }
}

/// 一轮巡检的**可变累加器**：由 `ProactivePollService` 在轮内逐点填写，
/// 轮末交给 [ProactiveRoundLog.recordInspection] 落盘。
///
/// 之所以不直接写库：轮内是异步流程，需要先攒齐（口令/工具调用/close code/alert）
/// 再一次性生成不可变记录，避免半成品出现在页面上。
class ProactiveRoundRecorder {
  ProactiveRoundRecorder({DateTime? startedAt})
      : _startedAt = startedAt ?? DateTime.now();

  final DateTime _startedAt;

  final List<String> _commands = <String>[];
  bool _getScriptCalled = false;
  bool _triggerCalled = false;
  bool _skipCalled = false;
  String? _opening;
  String? _closeCode;
  String? _alert;

  /// 本轮实际发出的口令（按发送顺序，最多 2 条）
  List<String> get commands => List<String>.unmodifiable(_commands);

  void addCommand(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    if (_commands.length >= 2) return; // 一轮最多发出 2 条（detect + 一次重发）
    _commands.add(t);
  }

  void markGetScript() => _getScriptCalled = true;

  void markTrigger(String message) {
    _triggerCalled = true;
    _opening = message;
  }

  void markSkip() => _skipCalled = true;

  void setCloseCode(String code) {
    final c = code.trim();
    if (c.isEmpty) return;
    _closeCode = c;
  }

  void setAlert(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _alert = t;
  }

  int get elapsedMs => DateTime.now().difference(_startedAt).inMilliseconds;

  ProactiveRoundLogEntry build({required String endReason}) {
    return ProactiveRoundLogEntry(
      time: _startedAt,
      decision: 'inspect',
      commands: List<String>.from(_commands),
      getScriptCalled: _getScriptCalled,
      triggerCalled: _triggerCalled,
      skipCalled: _skipCalled,
      opening: _opening,
      durationMs: elapsedMs,
      closeCode: _closeCode,
      alert: _alert,
      endReason: endReason,
    );
  }
}

/// 巡检轮记录仓库（环形缓冲 + 持久化 + 一键复制的纯文本渲染）。
class ProactiveRoundLog {
  ProactiveRoundLog._();

  static final Logger _logger = Logger('ProactiveRoundLog');

  /// 保留轮数上限
  static const int maxRounds = 50;

  /// 持久化键
  static const String keyStorage = 'xw_proactive_round_log';

  /// 无记录时 [toPlainText] 的返回值（页面据此提示"暂无记录"）
  static const String emptyText = '（暂无巡检记录）';

  /// 内存缓冲（**时间正序**，末尾最新）
  static final List<ProactiveRoundLogEntry> _entries = <ProactiveRoundLogEntry>[];

  static bool _loaded = false;
  static Future<void>? _loading;

  /// 清空代号：`clear()` 后置位，使"正在飞行中"的加载结果作废（否则清空后旧历史会被插回来）
  static int _generation = 0;

  /// 全部记录（**时间正序**；页面自行 `reversed` 展示最新在前）
  static List<ProactiveRoundLogEntry> get entries =>
      List<ProactiveRoundLogEntry>.unmodifiable(_entries);

  /// 当前条数
  static int get length => _entries.length;

  /// 从持久化存储加载历史（幂等；可安全并发调用）。任何异常都不外抛。
  static Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadFromStorage();
  }

  /// 记录一轮「跳过」（未建立巡检会话）。**唯一的跳过写入口**。
  ///
  /// [skipReason] 必须是**具体**原因，不要只写"跳过"。
  /// [source] 取值：`tick`(前台周期) / `bg`(后台单轮) / `busy` / `inspect`。
  static void recordSkip({required String skipReason, String? source}) {
    _append(
      ProactiveRoundLogEntry(
        time: DateTime.now(),
        decision: 'skip',
        skipReason: skipReason,
        source: source,
      ),
    );
    _logger.info('巡检轮记录（跳过）：$skipReason${source == null ? '' : ' [$source]'}');
  }

  /// 记录一轮**真正跑过的巡检**（由 [ProactiveRoundRecorder] 攒齐后调用）。
  static void recordInspection({
    required ProactiveRoundRecorder rec,
    required String endReason,
  }) {
    final entry = rec.build(endReason: endReason);
    _append(entry);
    _logger.info(
      '第 ${entry.time.toIso8601String()} 轮 | 结束=${entry.endReason} | '
      '口令=${entry.commands.join(' / ')} | get_script=${entry.getScriptCalled ? 1 : 0} '
      'trigger=${entry.triggerCalled ? 1 : 0} skip=${entry.skipCalled ? 1 : 0} | '
      '耗时=${entry.durationMs}ms | closeCode=${entry.closeCode ?? '—'} | '
      'alert=${entry.alert ?? '—'}',
    );
  }

  /// 清空全部记录（**内存部分同步生效**——页面点"清空"必须立刻看到列表空掉；
  /// 持久化删除异步进行，失败不影响内存已清空的事实）。
  static void clear() {
    _generation++;
    _loaded = true; // 阻止后续惰性加载把旧历史读回来
    _entries.clear();
    unawaited(_removeStorage());
  }

  static Future<void> _removeStorage() async {
    try {
      await StorageService.instance.remove(keyStorage);
    } catch (e) {
      _logger.warning('电话日志清空失败（忽略）: $e');
    }
  }

  /// 一键复制用的纯文本（含全部字段，可直接整段贴给 AI 诊断）。
  /// 无记录时返回 [emptyText]。
  static String toPlainText() {
    if (_entries.isEmpty) return emptyText;
    final b = StringBuffer()
      ..writeln('小乐 · MCP 电话日志（共 ${_entries.length} 轮，最多保留 $maxRounds 轮）')
      ..writeln('导出时间：${_fmt(DateTime.now())}')
      ..writeln('');
    final newestFirst = _entries.reversed.toList(growable: false);
    for (var i = 0; i < newestFirst.length; i++) {
      final e = newestFirst[i];
      b.writeln('────────── 第 ${newestFirst.length - i} 条（最新在前）──────────');
      b.writeln('时间：${_fmt(e.time)}');
      if (e.decision == 'skip') {
        b.writeln('判定：跳过');
        b.writeln('跳过原因：${e.skipReason ?? '未知'}');
        if (e.source != null) b.writeln('来源：${e.source}');
      } else {
        b.writeln('判定：${_decisionLabel(e)}');
        b.writeln('结束原因：${e.endReason ?? '—'}');
        if (e.commands.isEmpty) {
          b.writeln('口令：—');
        } else {
          for (var k = 0; k < e.commands.length; k++) {
            b.writeln(k == 0 ? '口令：${e.commands[k]}' : '口令${k + 1}(重发)：${e.commands[k]}');
          }
        }
        b.writeln('get_script 调用：${e.getScriptCalled ? '是' : '否'}');
        b.writeln('trigger_call：${e.triggerCalled ? '是' : '否'}');
        b.writeln('skip：${e.skipCalled ? '是' : '否'}');
        b.writeln('开场白：${_or(e.opening)}');
        b.writeln('本轮耗时：${e.durationMs} ms');
        b.writeln('close code：${_or(e.closeCode)}');
        b.writeln('服务器 alert：${_or(e.alert)}');
      }
      b.writeln('');
    }
    return b.toString().trimRight();
  }

  // ---------- 内部 ----------

  static void _append(ProactiveRoundLogEntry entry) {
    _ensureLoaded();
    _entries.add(entry);
    while (_entries.length > maxRounds) {
      _entries.removeAt(0);
    }
    unawaited(_persistAfterLoad());
  }

  /// 惰性加载：同步 API 首次被调用时触发一次后台加载（不阻塞巡检）。
  static void _ensureLoaded() {
    if (_loaded) return;
    unawaited(load());
  }

  static Future<void> _loadFromStorage() async {
    // 先置 _loaded，避免加载期间的记录触发二次加载
    _loaded = true;
    final gen = _generation;
    try {
      final raw = StorageService.instance.getString(keyStorage);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final history = <ProactiveRoundLogEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          history.add(
              ProactiveRoundLogEntry.fromJson(item.cast<String, dynamic>()));
        } catch (_) {
          // 单条坏数据跳过，不影响其余
        }
      }
      // 加载期间用户点过"清空" → 本次结果作废，别把旧历史插回来
      if (gen != _generation) return;
      // ⚠️ 插到**前面**：加载期间可能已有新记录写进 _entries，历史必须排在它们之前
      _entries.insertAll(0, history);
      while (_entries.length > maxRounds) {
        _entries.removeAt(0);
      }
    } catch (e) {
      _logger.warning('电话日志读取失败（降级为空）: $e');
    }
  }

  /// ⚠️ 关键：**等历史加载完再落盘**，否则启动后首次记录会覆盖掉旧历史。
  static Future<void> _persistAfterLoad() async {
    try {
      await load();
      await StorageService.instance.setString(
        keyStorage,
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      _logger.warning('电话日志持久化失败（忽略）: $e');
    }
  }

  /// 判定标签（页面与复制文本共用，避免两处措辞漂移）
  static String _decisionLabel(ProactiveRoundLogEntry e) {
    if (e.triggerCalled) return '触发来电';
    if (e.skipCalled) return '静默';
    if (e.endReason == 'timeout') return '超时';
    if (e.endReason == 'stop') return '被停止';
    return '巡检轮';
  }

  static String _or(String? v) =>
      (v == null || v.trim().isEmpty) ? '—' : v.trim();

  static String _fmt(DateTime t) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
