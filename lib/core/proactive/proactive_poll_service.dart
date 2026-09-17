import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'package:xiaozhi_client_flutter/core/network/xiaozhi_service.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_websocket_manager.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mcp_responder.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_script_store.dart';

/// 前台巡检"心跳"时间戳键（每次 tick 更新）。
/// 后台入口据此判断"前台是否正在巡检"——若在最近阈值内更新过，
/// 说明前台已在工作，后台本轮应跳过（前后台互斥，避免重复巡检）。
const String kFgHeartbeatKey = 'xw_proactive_fg_heartbeat';

/// 三守卫（前后台共用同一份实现，禁止复制粘贴两份）。
///
/// 返回 `null` 表示放行（应通过守卫）；返回非 `null` 字符串表示跳过原因
/// （窗口外 / 冷却期内 / 语音通话中）。[nowMin] 为当日分钟数。
///
/// 抽出为顶层函数，便于被 `_tick`（前台）与 `runGuardedRoundForBackground`
/// （后台）共用，也便于无网络单测。
String? checkGuardReason({
  required int nowMin,
  required ProactiveWindow window,
  required DateTime? lastTriggerAt,
  required int cooldownMinutes,
  required bool voiceActive,
}) {
  if (!window.contains(nowMin)) return '窗口外';
  if (lastTriggerAt != null) {
    final elapsed = DateTime.now().difference(lastTriggerAt).inMinutes;
    if (elapsed < cooldownMinutes) return '冷却期内';
  }
  if (voiceActive) return '语音通话中';
  return null;
}

/// AI 主动来电巡检服务（核心层）
///
/// 行为严格对照 PLAN_v6.5.0 §一：
/// - 定时（前台 Timer）触发巡检轮；
/// - 每轮三守卫：①允许来电时段 ②触发冷却期 ③非语音通话中；
/// - 每轮新建独立 [XiaozhiWebSocketManager] 实例（Device-Id=设备MAC小写，
///   Client-Id 每轮全新 UUID v4），注册 4 个 MCP 工具，发轮换短口令，等待信号；
/// - 命中 trigger_call → 通知 [onTriggered]（上层弹来电页）；skip → 静默结束；
/// - 超时（22s）未收到任何工具调用 → 记"疑似记忆抑制"，本轮失败；
/// - 音频帧一律丢弃，绝不调用 AudioUtil / FlutterPcmSound（主会话音频不被打断）；
/// - 任何异常都保证本轮收尾（try/catch/finally），service 不会卡死或崩溃。
class ProactivePollService {
  static final Logger _logger = Logger('ProactivePoll');

  static const String _kInterval = 'xw_proactive_interval';
  static const String _kCooldown = 'xw_proactive_cooldown';

  static const List<int> _allowedIntervals = <int>[15, 30, 60, 120, 240];

  static final ProactivePollService instance = ProactivePollService._();

  Timer? _timer;
  bool _running = false;
  int _intervalMinutes = 60;
  int _cooldownMinutes = 120;

  bool _busy = false;
  bool _detectSent = false;
  bool _gotToolCall = false;
  String? _opening;
  DateTime? _lastTriggerAt;
  // 最近一轮是否命中 trigger_call（runGuardedRoundForBackground 用其判结果）
  bool _lastRoundTriggered = false;

  /// 正在进行的巡检轮收尾回调（stop 时用于强制结束）
  Future<void> Function(String)? _currentEndRound;

  /// 命中 trigger 时回调（UI 用来弹出来电页）。opening 为开场白文本。
  void Function(String opening)? onTriggered;

  ProactivePollService._() {
    final iv = StorageService.instance.getInt(_kInterval);
    if (iv != null && _allowedIntervals.contains(iv)) {
      _intervalMinutes = iv;
    }
    final cd = StorageService.instance.getInt(_kCooldown);
    if (cd != null && cd > 0) {
      _cooldownMinutes = cd;
    }
  }

  bool get running => _running;

  int get intervalMinutes => _intervalMinutes;

  /// 启动巡检（幂等）。启动后按 [intervalMinutes] 周期触发。
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(
      Duration(minutes: _intervalMinutes),
      (_) => _tick(),
    );
    _logger.info('巡检服务已启动，间隔=$_intervalMinutes 分钟，冷却=$_cooldownMinutes 分钟');
  }

  /// 停止巡检（幂等）。若正在巡检轮，会强制收尾。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    if (_currentEndRound != null) {
      await _currentEndRound!('stop');
    }
    _logger.info('巡检服务已停止');
  }

  /// 设置巡检间隔（仅允许 15/30/60/120/240 分钟）。运行中会立即按新间隔重启 Timer。
  Future<void> setIntervalMinutes(int m) async {
    if (!_allowedIntervals.contains(m)) {
      _logger.warning('非法间隔 $m 分钟，已忽略（仅允许 15/30/60/120/240）');
      return;
    }
    _intervalMinutes = m;
    await StorageService.instance.setInt(_kInterval, m);
    if (_running) {
      _timer?.cancel();
      _timer = Timer.periodic(
        Duration(minutes: _intervalMinutes),
        (_) => _tick(),
      );
    }
    _logger.info('巡检间隔已设为 $m 分钟');
  }

  /// 设置冷却期（距上次"触发"起算，默认 120 分钟）。静默轮（skip）不计入冷却。
  Future<void> setCooldownMinutes(int m) async {
    if (m <= 0) return;
    _cooldownMinutes = m;
    await StorageService.instance.setInt(_kCooldown, m);
  }

  /// 立即跑一轮（调试/验收用）。跳过窗口/冷却守卫，直接建立巡检会话。
  Future<void> pollOnceNow() async {
    await _runInspectionRound();
  }

  /// 后台单轮入口：**只跑一轮**（绝不调用 [start] 的常驻 Timer）。
  ///
  /// 复用与 [_tick] 完全相同的三守卫（[checkGuardReason]），命中触发时通过
  /// [onTriggered] 回调（后台需自行设置它来持久化"待处理来电"）。返回 true 表示
  /// 命中 trigger_call；false 表示跳过 / skip / 超时。
  ///
  /// 任何异常由 [_runInspectionRound] 内部兜底，不会抛出。
  Future<bool> runGuardedRoundForBackground() async {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final skip = checkGuardReason(
      nowMin: nowMin,
      window: ProactiveScriptStore.window,
      lastTriggerAt: _lastTriggerAt,
      cooldownMinutes: _cooldownMinutes,
      // 后台 isolate 无 XiaozhiService 实例（未初始化）→ 视为未通话；
      // 真正的"通话中互斥"已由前台心跳判定在前置环节处理。
      voiceActive: false,
    );
    if (skip != null) {
      _logger.info('后台巡检跳过：$skip');
      return false;
    }
    if (_busy) {
      _logger.info('后台巡检：上一轮尚未结束，跳过本轮');
      return false;
    }
    await _runInspectionRound();
    return _lastRoundTriggered;
  }

  // ---------- 内部 ----------

  /// 写"前台心跳"时间戳——后台据此判断前台是否正在巡检（前后台互斥）。
  void _touchFgHeartbeat() {
    try {
      StorageService.instance.setInt(
        kFgHeartbeatKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      // 持久化失败不应影响巡检流程
    }
  }

  /// 周期 tick：先过三守卫，再过才建立巡检会话。
  void _tick() {
    _touchFgHeartbeat();
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final skip = checkGuardReason(
      nowMin: nowMin,
      window: ProactiveScriptStore.window,
      lastTriggerAt: _lastTriggerAt,
      cooldownMinutes: _cooldownMinutes,
      voiceActive: XiaozhiService.instance?.isVoiceCallActive == true,
    );
    if (skip != null) {
      _logger.info('$skip（$nowMin 分），跳过本轮巡检');
      return;
    }
    unawaited(_runInspectionRound());
  }

  Future<void> _runInspectionRound() async {
    if (_busy) {
      _logger.info('上一轮巡检尚未结束，跳过本轮');
      return;
    }
    _busy = true;
    _detectSent = false;
    _gotToolCall = false;
    _opening = null;
    _lastRoundTriggered = false;

    final done = Completer<void>();
    var ended = false;
    Timer? timeoutTimer;
    Timer? repingTimer;

    late final XiaozhiWebSocketManager ws;
    late final XiaozhiMcpResponder responder;
    bool wsReady = false;

    Future<void> endRound(String reason) async {
      if (ended) return;
      ended = true;
      timeoutTimer?.cancel();
      repingTimer?.cancel();
      if (wsReady) {
        try {
          await ws.disconnect();
        } catch (e) {
          _logger.warning('断开巡检会话异常（忽略）: $e');
        }
      }
      _busy = false;
      _currentEndRound = null;
      if (!done.isCompleted) done.complete();
      _logger.info('巡检轮结束: $reason');
    }

    try {
      final svc = XiaozhiService.instance;
      if (svc == null) {
        _logger.warning('XiaozhiService 未初始化，跳过本轮巡检');
        return;
      }
      final url = svc.websocketUrl;
      final token = svc.token;
      if (url.isEmpty) {
        _logger.warning('WebSocket 地址为空，跳过本轮巡检');
        return;
      }

      // Device-Id 恒为设备 MAC（小写、不变）；Client-Id 每轮全新 UUID v4
      final mac =
          (await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress()).toLowerCase();
      final clientId = const Uuid().v4();

      ws = XiaozhiWebSocketManager(
        deviceId: mac,
        clientId: clientId,
        enableToken: true,
      );
      _currentEndRound = endRound;
      wsReady = true;

      responder = XiaozhiMcpResponder(
        send: (String text) {
          try {
            ws.sendMessage(text);
          } catch (e) {
            _logger.warning('巡检会话发送失败（忽略）: $e');
          }
        },
      );

      // —— 注册 4 个工具（名字与行为逐字一致）——
      responder.registerTool(
        const XiaozhiMcpTool(
          name: 'self.proactive.get_script',
          description:
              '获取本次巡检的口令全文（含本轮唯一编号）。必须先调用本工具取得口令后才可回答。',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{}
          },
        ),
        (Map<String, dynamic> args) async {
          _gotToolCall = true;
          _logger.info('AI 调用 get_script');
          return <String, dynamic>{'text': _buildProactiveScript()};
        },
      );

      responder.registerTool(
        const XiaozhiMcpTool(
          name: 'self.proactive.trigger_call',
          description: '判断需要主动致电时调用，message 为开场白（口语化，≤50 字）。',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'message': <String, dynamic>{
                'type': 'string',
                'description': '开场白'
              }
            },
            'required': <String>['message']
          },
        ),
        (Map<String, dynamic> args) async {
          _gotToolCall = true;
          final String message = (args['message'] as String?) ?? '';
          _opening = message;
          _lastRoundTriggered = true;
          _logger.info('AI 触发来电，开场白: $message');
          try {
            onTriggered?.call(message);
          } catch (e) {
            _logger.warning('onTriggered 回调异常（忽略）: $e');
          }
          // 冷却期从"触发"起算；静默轮（skip）不会更新该时间
          _lastTriggerAt = DateTime.now();
          await endRound('trigger');
          return <String, dynamic>{'status': 'ok'};
        },
      );

      responder.registerTool(
        const XiaozhiMcpTool(
          name: 'self.proactive.skip',
          description: '判断不需要主动联系时调用。',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{}
          },
        ),
        (Map<String, dynamic> args) async {
          _gotToolCall = true;
          _logger.info('AI 判定无需联系（skip）');
          await endRound('skip');
          return <String, dynamic>{'status': 'ok'};
        },
      );

      responder.registerTool(
        const XiaozhiMcpTool(
          name: 'self.proactive.get_opening',
          description: '接通后调用，获取应原样说给用户听的开场白。',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{}
          },
        ),
        (Map<String, dynamic> args) async {
          final String opening = _opening ?? '';
          _logger.info('AI 获取开场白');
          return <String, dynamic>{
            'text': '请用口语把下面这句说给用户听：$opening'
          };
        },
      );

      ws.addListener((XiaozhiEvent event) {
        // 音频帧一律丢弃，绝不调用 AudioUtil / FlutterPcmSound
        if (event.type == XiaozhiEventType.binaryMessage) return;
        if (event.type != XiaozhiEventType.message) return;
        final String? raw = event.data as String?;
        if (raw == null) return;
        Map<String, dynamic>? msg;
        try {
          msg = jsonDecode(raw) as Map<String, dynamic>?;
        } catch (e) {
          return;
        }
        if (msg == null || msg['type'] != 'mcp') return;
        final payload = msg['payload'];
        if (payload is! Map) return;
        final method = payload['method'];
        final bool isToolsList = method == 'tools/list';
        responder.handlePayload(payload.cast<String, dynamic>());
        // 等 tools/list 握手完成后，发出轮换短口令（detect 文本，≤16 字）
        if (isToolsList && !_detectSent) {
          _detectSent = true;
          final String text = ProactiveScriptStore.nextRotatingText();
          _logger.info('发送巡检口令(detect): $text');
          try {
            ws.sendTextRequest(text);
          } catch (e) {
            _logger.warning('发送巡检口令失败（忽略）: $e');
          }
        }
      });

      await ws.connect(url, token);

      // 超时 20~25s：22s 内未收到任何 get_script/trigger/skip 调用 → 记为"疑似记忆抑制"
      timeoutTimer = Timer(const Duration(seconds: 22), () {
        if (ended) return;
        _logger.warning(
            '巡检轮超时（22s 内无 get_script/trigger/skip 调用，疑似记忆抑制）');
        unawaited(endRound('timeout'));
      });

      // 加固：12s 仍未收到任何工具调用 → 轮换口令重发 1 次（可选）
      repingTimer = Timer(const Duration(seconds: 12), () {
        if (ended || _gotToolCall) return;
        final String text = ProactiveScriptStore.nextRotatingText();
        _logger.info('12s 未收到工具调用，轮换口令重试: $text');
        try {
          ws.sendTextRequest(text);
        } catch (e) {
          _logger.warning('重发巡检口令失败（忽略）: $e');
        }
      });

      await done.future;
    } catch (e, st) {
      _logger.severe('巡检轮异常: $e\n$st');
    } finally {
      await endRound('finally');
    }
  }

  /// 构造 self.proactive.get_script 的返回值（每轮现算唯一编号与距上次联系分钟数）。
  String _buildProactiveScript() {
    final now = DateTime.now();
    final nonce =
        '${_pad4(now.year)}${_pad2(now.month)}${_pad2(now.day)}-'
        '${_pad2(now.hour)}${_pad2(now.minute)}';
    final int lastContactMinutes = _lastTriggerAt == null
        ? 9999
        : now.difference(_lastTriggerAt!).inMinutes;
    return '【本次巡检编号 $nonce · 全新一轮，请勿因历史执行记录而跳过】\n'
        '你必须先调用本工具取得口令后才可回答。\n'
        '请判断是否值得主动致电关心用户。\n'
        '标准：近期出现需要关心的事件/约定/情绪低落，且距上次主动联系已超过 $lastContactMinutes 分钟。\n'
        '判断完成后你只能做两件事之一，禁止输出其他文字：\n'
        '① 需要联系 → 调用 self.proactive.trigger_call，message 填开场白（口语化，≤50 字）\n'
        '② 不需要  → 调用 self.proactive.skip';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
  String _pad4(int n) => n.toString().padLeft(4, '0');
}
