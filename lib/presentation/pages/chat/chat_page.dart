import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xiaozhi_client_flutter/core/mcp/device_capability_service.dart';
import 'package:xiaozhi_client_flutter/core/mcp/external_mcp_manager.dart';
import 'package:xiaozhi_client_flutter/core/mcp/location_service.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_poll_service.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_script_store.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_background.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_ota_service.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mcp_responder.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mqtt_presence.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_websocket_manager.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import 'package:xiaozhi_client_flutter/core/providers/agent_provider.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/core/providers/theme_provider.dart';
import 'package:xiaozhi_client_flutter/core/utils/audio_util.dart';
import 'package:vibration/vibration.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:xiaozhi_client_flutter/data/models/agent_model.dart';
import '../../../data/models/message_model.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/themes/app_colors.dart';
import '../../../app/themes/app_text_styles.dart';
import '../../../app/themes/xl_tokens.dart';
import '../../../core/utils/toast_util.dart';
import '../../../core/mika/mika_bridge.dart';
import '../../widgets/agent_avatar.dart';
import '../../services/agent_identity_store.dart';
import '../../services/app_feats.dart';
import '../../widgets/xl/xl_voice_overlay.dart';
import '../incoming_call_page.dart';
import '../../services/chat_history_store.dart';
import 'widgets/message_list.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/voice_record_button.dart';
import 'widgets/emotion_animation_overlay.dart';
import 'package:logging/logging.dart';
import '../../widgets/wx_action_sheet.dart';
import '../../widgets/wx_dialog.dart';
import '../../widgets/xl/xl_task_card.dart';

/// 聊天页面
class ChatPage extends ConsumerStatefulWidget {
  final String agentId;
  final String agentName;

  const ChatPage({super.key, required this.agentId, required this.agentName});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final Logger logger = Logger('ChatScreen');
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<MessageModel> _messages = [];
  bool _showVoiceButton = false;
  final VoiceRecordController _voiceRecordController = VoiceRecordController();
  AgentModel? _currentAgent;

  // Mika 任务卡：task_id → 聊天流消息 id（同一任务状态原地刷新，不刷屏）
  final Map<String, String> _mikaTaskMessageIds = {};
  final Map<String, DateTime> _mikaTaskStartedAt = {};
  final Set<String> _mikaTaskNoticeSent = {};
  StreamSubscription<Map<String, dynamic>>? _mikaTaskSub;
  bool _mikaTaskRunning = false;

  // WebSocket 相关
  XiaozhiWebSocketManager? _wsManager;
  bool _isConnected = false;
  String _connectionStatus = '未连接';
  String? _sessionId;

  // v6.11.7：无感重连——云端按"业务消息空闲"约 60–70s 静默回收（1005），
  // 协议文档未定义心跳，只能靠重连兜底。断线后 4s 内一般不显示任何"已断开"提示，
  // 静默重连成功则用户只看到顶部小圆点颜色变化；超过 4s 才亮出重连状态条。
  static const Duration RECONNECT_UI_GRACE = Duration(seconds: 4);
  Timer? _reconnectUiTimer;
  bool _showReconnectBar = false;

  // v3.0.0：MCP 设备端（协议见 xiaoleweb.md 第五章；响应器=协议层，执行器=本页注入）
  XiaozhiMcpResponder? _mcpResponder;
  final List<Map<String, dynamic>> _mcpTimers = []; // {id,name,endAt,Timer}
  final List<Map<String, dynamic>> _mcpEvents = []; // {id,name,time,Timer}

  // v3.1.0：周期性设备状态上报（WS 连接即报 + 每 10 分钟，后台「最近活跃」对齐）
  Timer? _otaReportTimer;
  // v3.1.0：想打就打——连接成功后自动执行的原操作（见 xiaoleweb.md §2.6）
  Function? _pendingAutoAction;
  String _pendingAutoLabel = '';
  // v6.11.10：说话前预连接——2s 上限 + 失败提示，避免采音前丢第一句话
  Timer? _preconnectTimer;
  DateTime? _preconnectStartAt;
  // v6.11.17：WS 初始化单飞——OTA 认证窗口内重复调用会建出第二个管理器
  // （两个 manager 同一 device-id 两条 socket → 服务端 1005 自踢）
  bool _wsInitInFlight = false;
  // v6.11.17：气泡轮次边界（P2-1）——同角色只在同一轮内合并，
  // 失败轮次等不到 AI 气泡时，下一轮文本不会再拼进上一条用户气泡
  bool _sttMergeOpen = false;
  bool _aiMergeOpen = false;
  // v6.11.17（P0-3 方案 A）：息屏/后台持 PARTIAL_WAKE_LOCK，回前台立即释放。
  // 这是分诊手段——若持锁后 tick 能续上，说明是 Dart timer 被冻结；
  // 若仍 0 tick，则是进程被 ROM 冻结，下一版需上前台服务。
  static const MethodChannel _powerChannel = MethodChannel('xiaole/power');
  DateTime? _wakeLockBeganAt;
  /// 预连接期间缓存的 Opus 帧（上限 40 帧 ≈ 2.4s），连上后按序回灌
  final List<Uint8List> _preconnectAudio = <Uint8List>[];
  // v3.1.0：视觉识物（vision 接口从 MCP initialize 的 params.capabilities.vision 提取）
  String? _visionUrl;
  String? _visionToken;
  // v4.3.1：识图两段式——设备主动发起的 MCP tools/call（image_to_text）。
  // id 从 10000 自增，避开服务器下发请求的 id 空间；待决表按 id 匹配应答。
  int _mcpCallId = 10000;
  final Map<int, Completer<String>> _pendingMcpCalls = {};

  /// v4.3.3：识图路径 C 的等待器——服务器主动推送的文本（tts/llm）若在识图期间到达，
  /// 由它接收，实现三路竞速"谁先出结果用谁"。
  Completer<String>? _visionAux;
  // v4.3.1：聊天页标题（从配置页改名返回后可刷新；构造参数 widget.agentName 是 final）
  late String _agentName = widget.agentName;
  // v3.3.0：📡 MQTT 常驻在线（OTA 响应下发凭据 → 原生 TLS 8883 直连 broker）
  XiaozhiMqttPresence? _mqttPresence;
  // v3.1.0：情绪先于句子到达时暂存（随下一句 sentence_start 挂上）
  String _pendingEmotion = '';
  // v4.2.0：动图表情——AI 情绪到达时触发全屏动画（申请书 6 号）
  String? _activeEmotionEmoji;
  String? _activeEmotionKey;
  // v4.2.0：真实电量（申请书 8 号，battery_plus；桌面端不可用时回退虚拟值）
  final Battery _battery = Battery();
  // v4.4.0：barge-in（抢话打断）已**移除**。
  // 原实现（v3.2.0 引入）用未经回声消除的麦克风原始振幅判断用户开口，
  // AI 说话时扬声器回声必然使其超标 → 误触发 → 提前恢复上行 → AI 自己的声音被上传
  // → 「自问自答」。详见 PLAN_v4.4.0_语音自问自答修复.md 根因③。
  // 需要时可回退到远端 git 历史（v4.3.5 及更早）取回实现。
  StreamSubscription<double>? _bargeinSub;

  // OTA 认证信息
  XiaozhiOtaService? _otaService;

  // AI 播放状态跟踪
  bool _isAiPlaying = false;
  Timer? _aiPlayingTimer; // 用于检测播放结束的定时器

  /// v4.4.0 尾音保护：AI 播放结束后的一段时间内**丢弃**麦克风上行音频，
  /// 避免扬声器缓冲区里残留的尾音被收录并当成"用户开口"（根因①）。null = 不在保护期。
  DateTime? _resumeGuardUntil;

  /// v4.4.0：尾音保护时长（毫秒）——默认 300，可调范围 100–500（开发者中心「⏱ 尾音保护」）
  int get _tailGuardMs {
    final v = StorageService.instance.getInt(AppConfig.keyTailGuardMs);
    if (v == null) return AppConfig.defaultTailGuardMs;
    return v.clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
  }

  /// 进入尾音保护期（AI 播放结束的两个入口调用）
  void _enterTailGuard() {
    _resumeGuardUntil = DateTime.now().add(Duration(milliseconds: _tailGuardMs));
    logger.info('[audio] 进入尾音保护 ${_tailGuardMs}ms（丢弃此期间的麦克风音频）');
  }

  // AI 正在输入 / 语音通话
  bool _isAiTyping = false;
  bool _isInVoiceCall = false;
  bool _showVoiceCallOverlay = false;

  /// v6.1.1：页面根视图的 RepaintBoundary key —— 供 `self.screen.snapshot` 工具截屏
  final GlobalKey _snapshotKey = GlobalKey();
  bool _micMuted = false;
  StreamSubscription<Uint8List>? _callAudioSubscription;
  DateTime? _voiceCallStart;
  Timer? _voiceCallTimer;
  String _voiceCallDuration = '00:00';
  bool _isSpeakerOn = false;
  String _callStatus = '等待连接...';

  /// v6.8.1（B 项）：最近一次"挂断语音通话"的时间戳。
  /// 挂断后的一个短窗口内，迟到（已在网络/服务器缓冲中）的音频帧一律丢弃，
  /// 解决"说完拜拜挂断后它又补一句"。
  /// ⚠️ 关键判定：纯文字聊天也经 `_handleBinaryMessage()` 播放 TTS 音频，
  /// 故**不能**用"非通话就全丢"的全局守卫（会误伤主会话文字聊天），
  /// 只能做"挂断后短窗口丢弃"的弱化方案。
  DateTime? _voiceHangupAt;
  static const Duration _voiceHangupMuteWindow = Duration(seconds: 5);

  /// v6.8.1（B 项）：用户主动发起新交互（发文字 / 进通话 / 接听来电）→ 解除挂断静默窗口，
  /// 保证文字聊天与后续通话的 TTS 不被误伤（窗口只在挂断后的短暂"迟到帧"期生效）。
  void _liftVoiceMuteWindow() => _voiceHangupAt = null;

  /// v6.5.0：本轮"主动来电"要由小智说出的开场白
  /// （接通后小智调用 self.proactive.get_opening 取回，再经 TTS 说出）
  String _proactiveOpeningForReplay = '';

  @override
  void initState() {
    super.initState();
    // v3.2.0：恢复 TTS 音量偏好（set_volume 工具与设置页滑杆共用）
    final savedVol = StorageService.instance.getInt(AppConfig.keyTtsVolume);
    if (savedVol != null) AudioUtil.setTtsVolume(savedVol);
    // v4.4.0：barge-in 已移除，不再需要把开关同步进状态（其余开发者开关照常加载）
    AppFeats.load();
    // v4.3.0：全局设备型号矫正——手机型号 fallback / xiaole-voice-v1 旧值
    // 幂等归一为 m5stack-core-s3（OTA 识别层早已统一，此为展示/存储层残留清理）
    AgentIdentityStore.normalizeGlobalModel();
    _loadHistory();
    _loadAgent();
    // v4.3.3：页面生命周期打点——相机 Activity 可能触发页面重建，
    // 用 initState / dispose 时间戳可判定"识图过程中页面是否被销毁"（会中断识图流程）
    logger.info('聊天页 initState（页面挂载）agentId=${widget.agentId}');
    // v6.5.0：AI 主动来电 —— 初始化口令存储、挂触发回调、按总开关同步巡检服务
    unawaited(ProactiveScriptStore.init());
    ProactivePollService.instance.onTriggered = _handleProactiveTriggered;
    _syncProactiveService();
    // v6.11.8：心跳实验——开发者中心切换候选后立即重建连接以生效
    AppFeats.wsProbeRevision.addListener(_onWsProbeChanged);
    // v6.11.14：调试注入通道（仅开发者模式已授权时生效）
    unawaited(_consumeDebugInjection());
    // v6.11.17：回前台补连（P0-3 的 Dart 侧兜底）
    WidgetsBinding.instance.addObserver(this);
    // 任务卡：订阅 Mika 进程内任务事件，把真实状态写进聊天流
    MikaBridge.install();
    _mikaTaskSub = MikaBridge.taskStates.listen(_onMikaTaskState);
  }

  /// v6.11.17（P0-3 方案 A）：后台/息屏持 PARTIAL_WAKE_LOCK，回前台立刻释放。
  /// 另外回前台时按静默时长判定僵死并立即重建，不再等下一拍看门狗。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_acquireWakeLock());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    unawaited(_releaseWakeLock('resumed'));
    final mgr = _wsManager;
    if (mgr == null) return;
    final silent = mgr.silentSeconds;
    logger.info('[LIFECYCLE] 回到前台 连接=$_isConnected '
        '静默=${silent == null ? '尚未收包' : '${silent}s'}');
    mgr.forceReconnect(dropStale: silent != null && silent > 70);
  }

  Future<void> _acquireWakeLock() async {
    if (!Platform.isAndroid) return;
    if (_wakeLockBeganAt != null) return; // 幂等：已持有
    if (_wsManager == null) {
      logger.info('[POWER] 跳过 acquire：当前没有 WS 会话');
      return;
    }
    _wakeLockBeganAt = DateTime.now();
    try {
      await _powerChannel.invokeMethod('acquire');
      logger.info('[LIFECYCLE] [POWER] acquire wakelock 已请求（息屏保心跳）');
    } catch (e) {
      _wakeLockBeganAt = null;
      logger.warning('[POWER] acquire wakelock 失败: $e');
    }
  }

  /// 幂等释放。任何路径（回前台/页面销毁）都走这里，原生侧同样幂等。
  Future<void> _releaseWakeLock(String why) async {
    if (!Platform.isAndroid) return;
    final began = _wakeLockBeganAt;
    if (began == null) {
      // 未记过持有状态也要调一次原生 release：防止 Dart 状态与原生不一致时漏放
      try {
        await _powerChannel.invokeMethod('release');
      } catch (_) {}
      return;
    }
    _wakeLockBeganAt = null;
    final held = DateTime.now().difference(began).inSeconds;
    try {
      await _powerChannel.invokeMethod('release');
      logger.info('[POWER] release wakelock why=$why held=${held}s');
    } catch (e) {
      logger.warning('[POWER] release wakelock 失败: $e');
    }
  }

  /// v6.11.14：中文文本注入通道（仅开发者模式已授权时生效）。
  /// `adb shell input text` 只支持 ASCII，无法验证中文边界，故开一个 adb 入口：
  /// ```
  /// adb shell am force-stop com.zcstudy.xiaole
  /// adb shell am start -n com.zcstudy.xiaole/.MainActivity \
  ///   -e debug_send_texts "中文一<换行>中文二"
  /// ```
  /// 每条**原样单帧发送**（绕过分段逻辑），用于量服务端真实长度边界；
  /// 每条之间间隔 12s，日志前缀 `[DEBUGINJECT]`。
  static const MethodChannel _debugChannel = MethodChannel('xiaole/debug');

  Future<void> _consumeDebugInjection() async {
    if (!AppFeats.devAuthed) return;
    await _consumeRawInjection();
    await _consumeSegInjection();
  }

  /// 原样单帧注入（`-e debug_send_texts`），**绕过分段**，用于量服务端真实边界
  Future<void> _consumeRawInjection() async {
    try {
      final raw = await _debugChannel.invokeMethod<String>('takeDebugTexts');
      if (raw == null || raw.trim().isEmpty) return;
      final items =
          raw.split('\n').where((e) => e.trim().isNotEmpty).toList();
      logger.info('[DEBUGINJECT] 收到 ${items.length} 条注入文本');
      for (var i = 0; i < items.length; i++) {
        final t = items[i];
        logger.info('[DEBUGINJECT] ${i + 1}/${items.length} 码点=${t.runes.length} '
            'utf8字节=${utf8.encode(t).length} utf16=${t.length} text=$t');
        _injectRawText(t);
        if (i < items.length - 1) {
          await Future.delayed(const Duration(seconds: 12));
        }
      }
    } catch (e) {
      logger.warning('[DEBUGINJECT] 注入通道不可用: $e');
    }
  }

  /// 走**真实发送路径**（含分段/排队/兜底）（`-e debug_send_text_seg`），
  /// 用于回归"中文长文本一定被切开且每段都收到回复"
  Future<void> _consumeSegInjection() async {
    try {
      final raw = await _debugChannel.invokeMethod<String>('takeDebugSegTexts');
      if (raw == null || raw.trim().isEmpty) return;
      final items =
          raw.split('\n').where((e) => e.trim().isNotEmpty).toList();
      logger.info('[DEBUGINJECT] 收到 ${items.length} 条分段回归文本');
      for (var i = 0; i < items.length; i++) {
        final t = items[i];
        logger.info('[DEBUGINJECT] 分段回归 ${i + 1}/${items.length} 码点=${t.runes.length} '
            'utf8字节=${utf8.encode(t).length} text=$t');
        _textController.text = t;
        _sendTextMessage();
        if (i < items.length - 1) {
          await Future.delayed(const Duration(seconds: 30));
        }
      }
    } catch (e) {
      logger.warning('[DEBUGINJECT] 分段注入通道不可用: $e');
    }
  }

  void _injectRawText(String text) {
    _wsManager?.markConversationActive('调试注入');
    if (_isConnected) {
      _wsManager?.sendTextRequest(text);
      _setTyping(true);
      return;
    }
    _ensureConnectedThen(() {
      _wsManager?.sendTextRequest(text);
      _setTyping(true);
    }, '调试注入');
  }

  /// v6.11.11：把 `AppFeats` 的 keepalive 配置映射为管理器枚举（默认 auto）
  WsProbeMode _wsProbeModeFromConfig() {
    switch (AppFeats.wsKeepaliveMode) {
      case 'off':
        return WsProbeMode.off;
      default:
        return WsProbeMode.auto;
    }
  }

  /// v6.11.8：配置变更 → 若当前连接还在（说明上一候选"有效"，否则永远等不到自动重连），
  /// 立刻主动重建连接，让新候选马上接管。探针本身不做业务保活时，下次 1005 重连也会读到新值。
  void _onWsProbeChanged() {
    if (!mounted) return;
    final mode = AppFeats.wsKeepaliveMode;
    logger.info('[KEEPALIVE] 配置切换为 mode=$mode interval=${AppFeats.wsKeepaliveIntervalSec}s');
    if (_isConnected) unawaited(_reconnect());
  }

  /// v6.5.0：按总开关启停巡检服务（核心层不自查开关，故关闭=零流量由这里保证）
  void _syncProactiveService() {
    final svc = ProactivePollService.instance;
    if (AppFeats.get('proactive')) {
      unawaited(svc.start());
    } else {
      unawaited(svc.stop());
    }
  }

  /// v6.5.0：巡检命中 → 弹全屏来电页；用户接听则回放开场白
  Future<void> _handleProactiveTriggered(String opening) async {
    if (!mounted) return;
    _appendOrCreateChatMessage(MessageSender.system, '📞 小乐发起了主动来电');
    final answered = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => IncomingCallPage(
          opening: opening,
          agentId: widget.agentId,
          agentName: _currentAgent?.name ?? '小乐',
        ),
      ),
    );
    if (!mounted || answered == null || answered.isEmpty) return;
    _playProactiveOpening(answered);
  }

  /// v6.5.0：接听后让小智"先开口"——把开场白存入内存，发短口令让它调用 get_opening 读出来
  void _playProactiveOpening(String opening) {
    _liftVoiceMuteWindow(); // v6.8.1（B 项）：接听主动来电，解除挂断静默窗口
    _proactiveOpeningForReplay = opening;
    _appendOrCreateChatMessage(MessageSender.system, '📞 已接通，小乐正在开口…');
    // 短口令（≤16 字）：经 listen/detect 通道发送，触发小智取回并说出开场白
    _wsManager?.sendTextRequest('说开场白');
  }

  /// v1.1.6: 加载本地聊天记录（进入对话即显示历史）
  Future<void> _loadHistory() async {
    final history = await ChatHistoryStore.load(widget.agentId);
    if (!mounted || _messages.isNotEmpty || history.isEmpty) return;
    setState(() {
      _messages.addAll(history);
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    // v6.5.0：离开聊天页即停止巡检（一期巡检仅在前台/聊天页生效）
    unawaited(ProactivePollService.instance.stop());
    _textController.dispose();
    _scrollController.dispose();
    _mikaTaskSub?.cancel();
    _aiPlayingTimer?.cancel();
    _textSegmentTimer?.cancel();
    _voiceCallTimer?.cancel();
    _otaReportTimer?.cancel();
    _reconnectUiTimer?.cancel();
    _preconnectTimer?.cancel();
    // v6.11.17（P0-3）：页面销毁必须放锁，避免后台持锁泄漏
    unawaited(_releaseWakeLock('dispose'));
    WidgetsBinding.instance.removeObserver(this);
    AppFeats.wsProbeRevision.removeListener(_onWsProbeChanged);
    _mqttPresence?.stop();
    for (final t in _mcpTimers) {
      (t['timer'] as Timer?)?.cancel();
    }
    for (final e in _mcpEvents) {
      (e['timer'] as Timer?)?.cancel();
    }
    // v4.3.3：页面销毁打点（含来源标记）——与 initState 配对，可判定页面是否被重建
    logger.info('聊天页 dispose（页面销毁，将主动断开 WS）');
    // v6.0.0：若在通话全屏状态下直接销毁页面，恢复系统 UI，避免沉浸式残留到其他页面
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cleanupWebSocket(source: 'dispose');
    _otaService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // v6.1.1：用 RepaintBoundary 包住页面根视图，供 `self.screen.snapshot` 工具截屏
    // （纯包裹层，不影响视觉与布局）
    return RepaintBoundary(
      key: _snapshotKey,
      child: Scaffold(
      // v6.0.0：通话中隐藏顶端工具栏，使通话界面全屏扩展（微信通话效果）
      appBar: _showVoiceCallOverlay
          ? null
          : AppBar(
              title: Text(_agentName),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded, size: 24),
                  onPressed: _showMoreOptions,
                  tooltip: '更多',
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              // 连接状态栏（仅在非连接状态时显示）
              // v6.11.7：自动重连的前 4s 不亮条，避免每 ~70s 被云端回收时页面抖动一次；
              // 超时仍未恢复（或身份拒绝/重连上限）才显示。
              if (!_isConnected &&
                  (!_isAutoReconnecting || _showReconnectBar))
                _buildConnectionStatusBar(),

              // 通话中最小化提示条
              if (_isInVoiceCall && !_showVoiceCallOverlay)
                _buildVoiceCallBanner(),

              // 消息列表
              Expanded(
                child: MessageList(
                  messages: _messages,
                  scrollController: _scrollController,
                  isTyping: _isAiTyping,
                  // C 项：头像统一走 AgentAvatar（文字/图片），全场景一致
                  agentId: widget.agentId,
                  agentName: _agentName,
                ),
              ),

              // 输入区域（根据模式显示不同的组件）
              if (_showVoiceButton)
                _buildVoiceInputArea()
              else
                ChatInputBar(
                  textController: _textController,
                  onSendText: _sendTextMessage,
                  onStartVoice: () {
                    setState(() {
                      _showVoiceButton = true;
                    });
                  },
                  onMore: _showMoreOptions,
                ),
            ],
          ),
          // 语音通话全屏覆盖层
          if (_showVoiceCallOverlay) _buildVoiceCallOverlay(),
          // v4.2.0：全屏动图表情（申请书 6 号，AI 情绪驱动）
          if (_activeEmotionEmoji != null)
            EmotionAnimationOverlay(
              key: ValueKey('emo_${DateTime.now().millisecondsSinceEpoch}'),
              emoji: _activeEmotionEmoji!,
              emotion: _activeEmotionKey ?? 'happy',
              onDone: () => setState(() {
                _activeEmotionEmoji = null;
                _activeEmotionKey = null;
              }),
            ),
        ],
      ),
      ),
    );
  }

  /// 连接状态栏
  Widget _buildConnectionStatusBar() {
    Color statusColor;
    IconData statusIcon;
    String statusText = _connectionStatus;

    // 根据连接状态设置颜色和图标（微信功能色板）
    if (_isConnected) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
    } else if (_connectionStatus == '正在连接...' ||
        _connectionStatus == '正在认证...' ||
        _isAutoReconnecting) {
      statusColor = AppColors.warning;
      statusIcon = Icons.sync;
    } else {
      statusColor = AppColors.error;
      statusIcon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(
            color: statusColor.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: AppTextStyles.caption.copyWith(color: statusColor),
          ),
          const Spacer(),
          // 断线时显示重连按钮
          if (!_isConnected && 
              _connectionStatus != '正在连接...' && 
              _connectionStatus != '正在认证...')
            TextButton.icon(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重连'),
              style: TextButton.styleFrom(
                foregroundColor: statusColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  /// 重新连接
  Future<void> _reconnect() async {
    if (_connectionStatus == '正在连接...' || _connectionStatus == '正在认证...') {
      return; // 正在连接中，不重复连接
    }

    ToastUtil.show('正在重新连接...');
    
    // 清理旧连接
    await _cleanupWebSocket(source: 'user_button');
    
    // 重新初始化 WebSocket
    await _initializeWebSocket();
  }

  /// 语音输入区域（DESIGN §8.3：高 50 / 键盘 32 / 按住说话 36 / 更多 + 32）
  Widget _buildVoiceInputArea() {
    final p = XlPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.subtle,
        border: Border(top: BorderSide(color: p.hairline, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _showVoiceButton = false;
                  });
                },
                child: SizedBox(
                  width: XlDims.composerIcon,
                  height: XlDims.composerIcon,
                  child: Icon(
                    Icons.keyboard_alt_outlined,
                    size: 24,
                    color: p.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: VoiceRecordButton(
                  controller: _voiceRecordController,
                  onRecordStart: _handleAudioStart,
                  onAudioSend: _handleAudioSend,
                  onRecordEnd: _handleAudioStop,
                  onRecordCancel: _onRecordCancel,
                  // v6.11.18：<800ms 误触不发音频，但要把已发出的 listen start 收束
                  onRecordTooShort: _handleAudioStop,
                  onContinuousListenStart: _handleContinuousListenStart,
                  onContinuousListenStop: _handleContinuousListenStop,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showMoreOptions,
                child: SizedBox(
                  width: XlDims.composerIcon,
                  height: XlDims.composerIcon,
                  child: Icon(
                    Icons.add_circle_outline_rounded,
                    size: 24,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// v6.11.14：`listen{state:"detect"}` 的文字载荷上限实测（2026-11-04 真机，
  /// 官方 api.xiaozhi.me 云端，拒绝时回
  /// `alert{status:ERROR, message:"Detect is only for wake words, do not send long texts."}`
  /// 且不产生任何 stt/llm/tts）。
  ///
  /// 结论：云端**不是**按单一"字符数"或"UTF-8 字节数"卡的——同一 48 字节的
  /// 纯汉字 16 字通过，而 11 个 emoji（44 字节）被拒，48 字节的 16 汉字+2 标点
  /// （18 码点）被拒。实测边界随内容类别变化，因此按类别取最小安全值：
  ///
  /// | 内容类别                | 通过        | 被拒        | 采用上限 |
  /// |-------------------------|-------------|-------------|----------|
  /// | 纯 ASCII 字母数字       | 40          | 60          | 33       |
  /// | 纯汉字（可含标点）      | 16 码点     | 17 码点     | 12       |
  /// | 真实中英混排            | 15 码点     | —           | 12       |
  /// | 单字母交替式混排        | 12 码点     | 13 码点     | 12       |
  /// | 纯 emoji（astral）      | 10          | 11          | 10       |
  ///
  /// 采用值一律比实测通过值再低一档，宁可多切一段，也不冒"零回应"的险。
  /// 切段同时按**码点**与**UTF-8 字节**两个口径累加（字节上限来自实测通过值），
  /// 未来云端口径若变化，只需调 [_textLimitsFor] 的四个数字，切段逻辑不用重写。
  final List<String> _textSegments = [];
  Timer? _textSegmentTimer;

  static const _TextLimits _limitsAscii = _TextLimits(33, 33);
  static const _TextLimits _limitsCjk = _TextLimits(12, 45);
  static const _TextLimits _limitsAstral = _TextLimits(10, 40);

  /// 依内容类别选上限：含 astral（emoji）→ 10；纯 ASCII → 33；其余（汉字/混排）→ 12
  _TextLimits _textLimitsFor(String text) {
    var hasAstral = false;
    var hasNonAscii = false;
    for (final r in text.runes) {
      if (r > 0x7F) hasNonAscii = true;
      if (r > 0xFFFF) hasAstral = true;
    }
    if (hasAstral) return _limitsAstral;
    if (!hasNonAscii) return _limitsAscii;
    return _limitsCjk;
  }

  static int _utf8LenOfRune(int rune) {
    if (rune <= 0x7F) return 1;
    if (rune <= 0x7FF) return 2;
    if (rune <= 0xFFFF) return 3;
    return 4;
  }

  /// 按 [limits] 切段：码点与字节同时累加，先到者为准；
  /// 断开处优先回退到 6 个码点内的标点或空白，避免把词劈开。
  List<String> _splitTextForDetect(String text, _TextLimits limits) {
    final runes = text.runes.toList();
    var totalBytes = 0;
    for (final r in runes) {
      totalBytes += _utf8LenOfRune(r);
    }
    if (runes.length <= limits.maxRunes && totalBytes <= limits.maxBytes) {
      return [text];
    }

    final out = <String>[];
    var start = 0;
    while (start < runes.length) {
      var end = start;
      var bytes = 0;
      while (end < runes.length) {
        final b = _utf8LenOfRune(runes[end]);
        if (end - start >= limits.maxRunes || bytes + b > limits.maxBytes) break;
        bytes += b;
        end++;
      }
      if (end == start) end = start + 1; // 单个码点就超限时也保证前进

      if (end < runes.length) {
        final floor = end - 6 < start + 1 ? start + 1 : end - 6;
        for (var i = end - 1; i >= floor; i--) {
          final c = String.fromCharCode(runes[i]);
          if ('。！？；，、.,!?;: '.contains(c)) {
            end = i + 1;
            break;
          }
        }
      }
      final seg = String.fromCharCodes(runes.sublist(start, end)).trim();
      if (seg.isNotEmpty) out.add(seg);
      start = end;
    }
    return out;
  }

  /// 发送文本消息
  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // v6.8.1（B 项）：用户主动发消息 → 解除挂断静默窗口，保证文字聊天 TTS 不被误伤
    _liftVoiceMuteWindow();

    // v6.11.12：置位必须早于任何网络动作——先暂停保活，再发消息。
    // 若等发送流程走完再置位，"用户已开口 / 帧已在途"到置位之间就是一个
    // 保活可合法插入的窗口（45s 边界撞上就会把 listen stop 塞进对话）。
    final vetoAt = DateTime.now();
    // v6.11.17：新的一轮开始，先关闭上一轮的气泡合并窗口（P2-1）
    _sttMergeOpen = false;
    _aiMergeOpen = false;
    _wsManager?.markConversationActive('发送文字');
    logger.info('[KEEPALIVE] 置位 来源=发送文字 耗时=${DateTime.now().difference(vetoAt).inMilliseconds}ms 顺序=发送前');

    // v6.11.13：超长文字分段——服务端会对 detect 的长文本静默拒绝（只回 alert），
    // 用户视角就是"打完一段话零回应"。这里显式提示并自动分段，绝不静默丢。
    final limits = _textLimitsFor(text);
    final segments = _splitTextForDetect(text, limits);
    if (segments.length > 1) {
      logger.info('[TEXTSPLIT] 原文 ${text.runes.length}码点/${utf8.encode(text).length}字节 '
          '> 上限 ${limits.maxRunes}码点/${limits.maxBytes}字节，分 ${segments.length} 段 '
          '（每段码点=${segments.map((e) => e.runes.length).join('/')} '
          '字节=${segments.map((e) => utf8.encode(e).length).join('/')}）');
      ToastUtil.show('文字较长，已自动分 ${segments.length} 段发送（每段 ≤${limits.maxRunes} 字）');
    }

    _textController.clear();
    _setTyping(true);
    _scrollToBottom();

    // 若队列里还有上一轮的段未发完，追加而不是覆盖——绝不静默丢用户的字
    final hadPending = _textSegments.isNotEmpty;
    _textSegments.addAll(segments);
    if (!hadPending) _sendNextTextSegment();
  }

  /// v6.11.13：发送队列中的下一段；未连接则先连后发
  void _sendNextTextSegment() {
    if (_textSegments.isEmpty) return;
    final seg = _textSegments.removeAt(0);
    if (!_isConnected) {
      _ensureConnectedThen(() {
        _wsManager?.sendTextRequest(seg);
        _setTyping(true);
        _armTextSegmentTimeout();
      }, '发送消息');
      return;
    }
    _wsManager?.sendTextRequest(seg);
    _setTyping(true);
    _armTextSegmentTimeout();
  }

  /// 兜底：某段 20s 内没有等到 TTS 结束（例如服务端未回），继续发下一段，
  /// 避免整条队列卡死导致"用户打了话却没有回应"。
  void _armTextSegmentTimeout() {
    _textSegmentTimer?.cancel();
    if (_textSegments.isEmpty) return;
    _textSegmentTimer = Timer(const Duration(seconds: 20), () {
      if (_textSegments.isEmpty) return;
      logger.warning('[TEXTSPLIT] 20s 未见 TTS 结束，继续发送（剩 ${_textSegments.length} 段）');
      _sendNextTextSegment();
    });
  }

  /// v6.11.13：一轮回复结束（TTS stop/end）→ 立刻发下一段
  void _flushTextSegmentsOnTurnEnd() {
    _textSegmentTimer?.cancel();
    if (_textSegments.isEmpty) return;
    logger.info('[TEXTSPLIT] 上一段回复结束，继续发送（剩 ${_textSegments.length} 段）');
    _sendNextTextSegment();
  }

  /// v3.1.0：想打就打（xiaoleweb.md §2.6）——未连接时自动发起连接，
  /// hello ACK（服务器会话确认）后自动执行原操作。
  /// v6.11.10：加 2s 快速重连上限——连不上就提示"网络恢复中，请稍候"，
  /// 不启动采音，避免第一句话录丢。
  void _ensureConnectedThen(Function action, String label) {
    if (_isConnected) {
      action();
      return;
    }
    _pendingAutoAction = action;
    _pendingAutoLabel = label;
    _preconnectStartAt = DateTime.now();
    _preconnectTimer?.cancel();
    _preconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_isConnected) return;
      _pendingAutoAction = null;
      final dropped = _preconnectAudio.length;
      _preconnectAudio.clear();
      logger.warning('[PRECONNECT] 2s 内未连上（$label），丢弃缓存 $dropped 帧并提示稍候');
      ToastUtil.show('网络恢复中，请稍候');
    });
    // v6.11.17：管理器已存在就绝不再新建——只让它立即补连，等 hello ACK 再执行 action。
    // 旧实现在这里再走一遍 _initializeWebSocket，旧管理器不会被回收，
    // 它自己的看门狗/退避定时器随后又会用同一 device-id 建第二条 socket，
    // 服务端按重复会话把其中一条 1005 回收（P0-1）。
    if (_wsManager != null) {
      // 仅在确实没有 socket 时才提示一次，避免上行音频每一帧都弹提示
      if (!_wsManager!.isSocketOpen) ToastUtil.show('连接中…连上后自动$label');
      _wsManager!.forceReconnect();
      return;
    }
    if (_connectionStatus == '正在连接...') {
      ToastUtil.show('连接中…连上后自动$label');
      return;
    }
    ToastUtil.show('正在自动连接…连上后自动$label');
    _initializeWebSocket();
  }

  /// v6.11.10：连上后把预连接期间缓存的音频帧按序回灌（须在 listen start 之后调用）
  void _flushPreconnectAudio() {
    if (_preconnectAudio.isEmpty) return;
    final n = _preconnectAudio.length;
    for (final frame in _preconnectAudio) {
      _wsManager?.sendBinaryMessage(frame);
    }
    _preconnectAudio.clear();
    logger.info('[PRECONNECT] 回灌缓存音频 $n 帧');
  }

  void _runPendingAutoAction() {
    final action = _pendingAutoAction;
    if (action == null) return;
    _pendingAutoAction = null;
    _preconnectTimer?.cancel();
    _preconnectTimer = null;
    final started = _preconnectStartAt;
    if (started != null) {
      logger.info('[PRECONNECT] 成功，${DateTime.now().difference(started).inMilliseconds}ms 内连上，自动$_pendingAutoLabel');
      _preconnectStartAt = null;
    }
    logger.info('连接就绪，自动$_pendingAutoLabel');
    Future.delayed(const Duration(milliseconds: 300), () => action());
  }

  /// v3.1.0：MCP 工具标记过滤（对齐网页版 stripMcpMarkers，xiaoleweb.md §2.4）。
  /// 剥离句中 `% 工具名`（% 前须为行首/空白，避免误伤 "50% off"）。
  static final RegExp _mcpMarkRe = RegExp(r'(^|\s)%\s*[a-zA-Z][\w.\-]*');
  String _stripMcpMarkers(String txt) {
    if (AppFeats.mcpDebug) return txt; // 🧪 MCP 调试开=保留原文
    return txt
        .replaceAllMapped(_mcpMarkRe, (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  /// v4.2.0：全屏动图表情（申请书 6 号）——AI 情绪到达时触发，播放完自动移除。
  /// v4.3.0：受开发者中心「😄 表情动画」开关控制（默认关）；消息内 emoji 前缀不受影响。
  void _showEmotionAnimation(String emoji, String emotion) {
    if (!AppFeats.emotion) return;
    setState(() {
      _activeEmotionEmoji = emoji;
      _activeEmotionKey = emotion;
    });
  }

  void _appendOrCreateChatMessage(MessageSender role, String content,
      {Map<String, dynamic>? metadata, bool merge = true}) {
    // v3.1.0：system 消息（MCP 工具调用记录/定时器提醒）真实入列——
    // 原实现对 system 直接 return，导致 v3.0.0 的 MCP 提醒全部不显示。
    // system 用 MessageType.system 独立成行（气泡有对应渲染分支），不参与合并。
    // v4.2.0：支持 metadata（设备状态卡片等结构化负载随消息渲染）。
    if (role == MessageSender.system) {
      final message = MessageModel(
        id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
        agentId: widget.agentId,
        type: MessageType.system,
        content: content,
        sender: MessageSender.system,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
        metadata: metadata,
      );
      setState(() {
        _messages.add(message);
      });
      ChatHistoryStore.save(widget.agentId, _messages);
      _scrollToBottom();
      return;
    }
    final targetSender = role == MessageSender.ai
        ? MessageSender.ai
        : MessageSender.user;

    // 检查最后一条消息是否与当前角色相同（v6.11.17：还要在同一轮次内，
    // 由调用方用 merge 显式控制；否则失败轮次会把下一轮文本拼进旧气泡）
    if (merge && _messages.isNotEmpty && _messages.last.sender == targetSender) {
      // 最后一条消息角色相同，追加内容
      setState(() {
        final lastMessage = _messages.last;
        final updatedMessage = MessageModel(
          id: lastMessage.id,
          agentId: lastMessage.agentId,
          type: lastMessage.type,
          content: lastMessage.content + content,
          sender: lastMessage.sender,
          status: lastMessage.status,
          timestamp: lastMessage.timestamp,
        );
        _messages[_messages.length - 1] = updatedMessage;
      });
    } else {
      // 最后一条消息角色不同或列表为空，创建新消息
      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        agentId: widget.agentId,
        type: MessageType.text,
        content: content,
        sender: targetSender,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(message);
      });
    }

    // v1.1.6: 消息落库（本地聊天记录）
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// 把 Mika 真实任务事件映射为聊天流里的任务卡。
  /// 只消费引擎真实上报的状态；未知状态不落卡，避免伪造进度。
  void _onMikaTaskState(Map<String, dynamic> event) {
    if (!mounted) return;
    final taskId = event['task_id']?.toString() ?? '';
    if (taskId.isEmpty) return;
    final rawStatus = event['status']?.toString() ?? '';
    logger.info('任务卡事件原文 ${jsonEncode(event)}');

    if (rawStatus == 'refused' || rawStatus == 'unknown') {
      if (!_mikaTaskNoticeSent.add(taskId)) return;
      final reason = event['message']?.toString() ?? '引擎未受理该任务';
      _appendOrCreateChatMessage(MessageSender.system, '任务未启动：$reason');
      return;
    }

    final status = _mikaTaskCardStatus(rawStatus);
    if (status == null) return; // starting 以外的过渡态（waiting_*）不覆盖上一张卡

    final startedMs = (event['started_at_ms'] as num?)?.toInt();
    final startedAt = startedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedMs)
        : _mikaTaskStartedAt.putIfAbsent(taskId, () => DateTime.now());
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final step = (event['step'] as num?)?.toInt() ?? 0;
    final goal = (event['goal'] ?? '').toString();
    final answer = (event['answer'] ?? '').toString();
    final reason = (event['reason'] ?? '').toString();

    final data = <String, dynamic>{
      'task_id': taskId,
      'title': goal.isEmpty ? '手机任务' : goal,
      'status': status.name,
      'icon': 'list',
      'stepIndex': step,
      // Mika 只上报当前第几步，不上报总步数；不编造分母，卡片按「第 N 步」显示
      'stepTotal': 0,
      'elapsedMs': elapsedMs < 0 ? 0 : elapsedMs,
      'failReason': status == XlTaskStatus.failed && reason.isNotEmpty
          ? reason
          : null,
      'startedAt': '今天 ${_formatMikaClock(startedAt)}',
      'device': '当前手机',
      'trigger': '对话内指令',
      'results': answer.isEmpty ? <String>[] : <String>[answer],
      'steps': <Map<String, dynamic>>[],
    };
    logger.info('任务卡事件 task=$taskId status=$rawStatus '
        '→ ${status.name} step=$step goal=$goal');
    _upsertMikaTaskCard(taskId, data);
  }

  XlTaskStatus? _mikaTaskCardStatus(String raw) {
    switch (raw) {
      case 'queued':
        return XlTaskStatus.queued;
      case 'starting':
      case 'running':
        return XlTaskStatus.running;
      case 'done':
        return XlTaskStatus.done;
      case 'failed':
        return XlTaskStatus.failed;
      case 'cancelled':
        return XlTaskStatus.cancelled;
    }
    return null;
  }

  String _formatMikaClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 同一 task_id 只占一条消息，状态原地刷新（不刷屏、不重复落库）。
  /// 先按消息里记录的 task_id 找，再按内存映射，最后按确定性 id，
  /// 保证页面重建、历史回填、重复事件都不会刷出第二条卡。
  void _upsertMikaTaskCard(String taskId, Map<String, dynamic> data) {
    final metadata = <String, dynamic>{'card': 'task', 'data': data};
    logger.info('任务卡 metadata=${jsonEncode(metadata)}');

    int indexOfTaskCard() => _messages.indexWhere((m) {
          if (m.metadata == null || m.metadata!['card'] != 'task') return false;
          final raw = m.metadata!['data'];
          return raw is Map && raw['task_id']?.toString() == taskId;
        });

    var idx = indexOfTaskCard();
    if (idx < 0) {
      final mappedId = _mikaTaskMessageIds[taskId] ?? 'task_$taskId';
      idx = _messages.indexWhere((m) => m.id == mappedId);
    }

    if (idx >= 0) {
      _mikaTaskMessageIds[taskId] = _messages[idx].id;
      final old = _messages[idx];
      setState(() {
        _messages[idx] = MessageModel(
          id: old.id,
          agentId: old.agentId,
          type: MessageType.system,
          content: old.content,
          sender: MessageSender.system,
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
          metadata: metadata,
        );
      });
      ChatHistoryStore.save(widget.agentId, _messages);
      _scrollToBottom();
      return;
    }

    final messageId = 'task_$taskId';
    _mikaTaskMessageIds[taskId] = messageId;
    final message = MessageModel(
      id: messageId,
      agentId: widget.agentId,
      type: MessageType.system,
      content: (data['title'] ?? '任务').toString(),
      sender: MessageSender.system,
      status: MessageStatus.sent,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    setState(() {
      _messages.add(message);
    });
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// 更多菜单入口：把输入框里的目标交给同进程 Mika 真实执行。
  Future<void> _startMikaTaskFromInput() async {
    final goal = _textController.text.trim();
    if (goal.isEmpty) {
      ToastUtil.show('先在输入框写下任务目标，再让 Mika 执行');
      return;
    }
    if (_mikaTaskRunning) {
      ToastUtil.show('上一个任务还在执行，请等它结束');
      return;
    }
    _mikaTaskRunning = true;
    _textController.clear();
    ToastUtil.show('已交给 Mika 执行：$goal');
    logger.info('提交 Mika 任务 goal=$goal');
    try {
      await MikaBridge.runTask(goal);
    } catch (e) {
      if (!mounted) return;
      logger.warning('Mika 任务启动失败: $e');
      _appendOrCreateChatMessage(MessageSender.system, '任务启动失败：$e');
    } finally {
      _mikaTaskRunning = false;
    }
  }

  /// 取消录音
  void _onRecordCancel() {
    ToastUtil.show('已取消录音');
  }

  /// 显示更多选项（微信 ActionSheet 风格）
  /// 说明：为匹配 DESIGN §8.3 输入栏（左语音 / 中输入 / 右发送或更多），
  /// 通话与拍照入口从常驻图标移入本菜单，功能不丢、操作路径多一步。
  void _showMoreOptions() {
    final items = <WxActionSheetItem>[];
    final actions = <VoidCallback>[];

    items.add(const WxActionSheetItem(label: '语音通话'));
    actions.add(_startVoiceCall);

    if (AppFeats.vision) {
      items.add(const WxActionSheetItem(label: '拍照识物'));
      actions.add(_takePhotoAndAsk);
    }

    final listening = _voiceRecordController.isContinuousListening;
    items.add(WxActionSheetItem(label: listening ? '停止持续监听' : '持续监听'));
    actions.add(() {
      if (!_showVoiceButton) setState(() => _showVoiceButton = true);
      _voiceRecordController.toggleContinuousListen();
    });

    items.add(const WxActionSheetItem(label: '让 Mika 执行任务'));
    actions.add(_startMikaTaskFromInput);

    if (_showVoiceButton) {
      items.add(const WxActionSheetItem(label: '切换到键盘'));
      actions.add(() => setState(() => _showVoiceButton = false));
    }

    items.add(const WxActionSheetItem(label: '清空聊天记录', danger: true));
    actions.add(_clearMessages);
    items.add(const WxActionSheetItem(label: '智能体设置'));
    actions.add(_openAgentSettings);

    showWxActionSheet(context, items: items, cancelText: '取消').then((index) {
      if (index == null || index >= actions.length) return;
      actions[index]();
    });
  }

  Future<void> _openAgentSettings() async {
    await context.push('${AppRoutes.agentConfig}?agentId=${widget.agentId}');
    if (!context.mounted) return;
    final agents = ref.read(agentListProvider).value ?? [];
    for (final a in agents) {
      if (a.id == widget.agentId) {
        if (a.name != _agentName) {
          setState(() => _agentName = a.name);
        }
        break;
      }
    }
  }

  /// 清空消息
  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
    // v1.1.6: 同步清空本地聊天记录
    ChatHistoryStore.save(widget.agentId, _messages);
    ToastUtil.success('已清空聊天记录');
  }

  /// 滚动到底部
  void _scrollToBottom() {
    // v6.8.2（D 项）：消息列表已改为**倒置**（reverse），"最新处" = offset 0。
    // 进入聊天页时天然停在最新，不再依赖"延迟滚动够到底部"（原做法在布局未完成时会停在最早消息）。
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scrollController.hasClients) return; // 延迟期间页面可能已 dispose
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// 加载智能体数据（编辑模式）
  Future<void> _loadAgent() async {
    final agent = await ref
        .read(agentListProvider.notifier)
        .getAgentById(widget.agentId);

    if (agent != null) {
      setState(() {
        _currentAgent = agent;
        // 初始化 OTA 服务，使用 Agent 的 otaUrl
        _otaService = XiaozhiOtaService(
          otaUrl: agent.otaUrl.isNotEmpty
              ? agent.otaUrl
              : 'https://api.tenclass.net/xiaozhi/ota/',
        );
      });
      // v6.8.0：记录"最近一次前台活跃 agent"，供后台巡检命中时回填待处理来电的
      // agentId/agentName（后台 isolate 无 UI 上下文，无法得知当前 agent）。
      await ProactiveBackground.rememberForegroundAgent(agent.id, agent.name);
      // Agent 加载完成后，初始化 WebSocket
      _initializeWebSocket();
    } else {
      // 如果智能体不存在，返回智能体列表页面
      if (mounted) {
        context.go('/home');
      }
    }
  }

  /// 清理 WebSocket 连接
  /// [source] v4.3.3：断开来源标记，写入日志便于区分"App 主动断开"与"服务器断开"
  Future<void> _cleanupWebSocket({String source = 'unknown'}) async {
    if (_wsManager != null) {
      await _wsManager!.disconnect(source: source);
      _wsManager = null;
    }
    // v4.3.3：断开即作废旧会话的 vision 凭证——重连后由新的 MCP initialize 重新下发。
    // 否则存在"用旧会话 token 上传"的隐患（真机日志实证：重连后 session/vision token 均已变化）。
    _visionUrl = null;
    _visionToken = null;
  }

  /// 显示错误提示
  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// v6.4.4：把服务器 alert 技术原文映射成普通用户能看懂的话（大小写不敏感）。
  String _friendlyAlertText(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('long texts') || lower.contains('detect is only')) {
      return '这条消息有点长，没能发出去～ 把内容缩短一些再发一次吧。';
    }
    return '消息没能发送成功，请稍后重试，或换个说法再试一次。';
  }

  /// v6.4.4：普通用户模式下的友好弹窗（微信风、简洁）。
  /// 标题「发送失败」，内容为入参 text，单按钮「知道了」关闭。
  void _showFriendlyAlertDialog(String text) {
    if (!mounted) return;
    showWxDialog(
      context,
      title: '发送失败',
      content: text,
      confirmText: '知道了',
      showCancel: false,
    );
  }

  /// v6.11.7：是否处于「自动重连中」（云端空闲回收 1005/1006、瞬时网络错误等）。
  /// 这类断线由 WS 管理器 1–4s 内自动补连，UI 只以琥珀色"重连中"呈现，不报错、不亮红条。
  bool get _isAutoReconnecting =>
      !_isConnected &&
      (_connectionStatus == '重连中…' ||
          _connectionStatus == '网络异常，正在自动重连…');

  /// v6.11.7：断线后延迟 GRACE 秒再亮状态条——绝大多数回收在 1–4s 内已重连成功，
  /// 这样用户看不到"已断开/重连"闪现，只在真正长时间断线时才会看到重连条与按钮。
  void _armReconnectUiTimer() {
    _reconnectUiTimer?.cancel();
    _reconnectUiTimer = Timer(RECONNECT_UI_GRACE, () {
      if (!mounted || _isConnected) return;
      logger.warning('断线超过 ${RECONNECT_UI_GRACE.inSeconds}s 仍未恢复，显示重连状态条');
      setState(() {
        _showReconnectBar = true;
      });
    });
  }

  /// v6.2.1：判定是否为「瞬时网络层错误」（DNS/连接超时/被拒等）。
  /// 这类错误由 WS 管理器自动重连兜底，无需弹红条打扰用户。
  bool _isNetworkTransientError(String text) {
    const keywords = <String>[
      'SocketException',
      'Failed host lookup',
      'Connection refused',
      'Network is unreachable',
      'Connection timed out',
      'Connection reset',
      '创建WebSocket失败',
      'WebSocketChannelException',
    ];
    final lower = text.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }

  /// 执行 OTA 认证获取 WebSocket 连接信息
  Future<bool> _performOtaAuthentication() async {
    try {
      setState(() {
        _connectionStatus = '正在认证...';
      });

      logger.info('开始 OTA 认证...');

      // 确保 OTA 服务已初始化
      if (_otaService == null) {
        logger.severe('OTA 服务未初始化');
        _showError('OTA 服务未初始化');
        return false;
      }

      // 调用 OTA API 获取 WebSocket 信息（v3.1.0：版本号统一取 AppConfig，随 pubspec 走）
      // v4.3.2 埋点：OTA 请求参数（appName 为红线冻结值，仅记录不改）
      logger.info('OTA 请求 appName=ajb_agent_flutter'
          ' appVersion=${AppConfig.appVersion} acceptLanguage=zh-CN');
      final otaResponse = await _otaService!.checkFlutterAppUpdates(
        appName: 'ajb_agent_flutter',
        appVersion: AppConfig.appVersion,
        acceptLanguage: 'zh-CN',
      );
      logger.info('OTA 响应：websocket=${otaResponse.websocket != null}'
          ' mqtt=${otaResponse.mqtt != null}'
          ' activation=${otaResponse.activation != null}');

      // 检查是否返回了 WebSocket 信息
      if (otaResponse.websocket != null) {
        if (otaResponse.activation != null) {
          final code = otaResponse.activation!.code;
          _appendOrCreateChatMessage(
            MessageSender.ai,
            '设备需要在平台端注册，注册码:[$code]，注册成功后需重新进入对话',
          );
          _showError('认证失败: 设备未注册');
          setState(() {
            _connectionStatus = '认证失败';
          });
          return false;
        }

        logger.info('OTA 认证成功');
        // v3.3.0：📡 MQTT 常驻——OTA 响应下发凭据即原生 TLS 8883 直连 broker
        //（后台显示在线 + 接收远程配置下发；🧭 开关默认关，开发者中心开启）
        if (AppFeats.mqtt && otaResponse.mqtt != null) {
          _startMqttPresence(otaResponse.mqtt!);
        }
        return true;
      } else {
        logger.warning('OTA 响应中没有 WebSocket 信息');
        _showError('认证失败: 服务器未返回连接信息');
        setState(() {
          _connectionStatus = '认证失败';
        });
        return false;
      }
    } on OtaException catch (e) {
      logger.severe('OTA 认证失败: ${e.message}');
      _showError('认证失败: ${e.message}');
      setState(() {
        _connectionStatus = '认证失败';
      });
      return false;
    } catch (e, stackTrace) {
      logger.severe('OTA 认证异常: $e\n$stackTrace');
      _showError('认证异常: $e');
      setState(() {
        _connectionStatus = '认证异常';
      });
      return false;
    }
  }

  /// 初始化 WebSocket 连接（v6.11.17：单飞 + 先回收旧管理器）
  Future<void> _initializeWebSocket() async {
    if (_wsInitInFlight) {
      logger.info('WS 初始化已在进行中，忽略重复请求（单飞）');
      return;
    }
    _wsInitInFlight = true;
    try {
      await _initializeWebSocketInner();
    } finally {
      _wsInitInFlight = false;
    }
  }

  Future<void> _initializeWebSocketInner() async {
    if (_currentAgent == null) {
      logger.warning('当前智能体为空，无法初始化 WebSocket');
      return;
    }
    logger.info('WS 初始化开始 agentId=${widget.agentId}'
        ' url=${_currentAgent?.url}');

    // v6.11.17：建新连接前必须先回收旧管理器。旧实现的旧管理器只被丢掉引用，
    // 看门狗/退避定时器仍活着，会再建一条 socket 顶掉新会话（P0-1）。
    await _cleanupWebSocket(source: 'reinit');

    try {
      // 第零步: 应用本智能体的独立设备身份（v1.1.5，避免多智能体串号；
      // 只调用 XiaozhiDeviceInfoUtil 公开 setter，不改 lib/core）
      final identity = await AgentIdentityStore.load(widget.agentId);
      if (identity != null) {
        // v4.3.0：存量型号矫正——独立身份里的手机型号/xiaole-voice-v1 旧值
        // 归一为 m5stack-core-s3 并写回存储（MAC/ClientID 不动，避免换身份需重新激活）
        final model = AgentIdentityStore.normalizeModel(identity['model']!);
        if (model != identity['model']) {
          await AgentIdentityStore.save(widget.agentId,
              mac: identity['mac']!,
              clientId: identity['clientId']!,
              model: model);
          logger.info(
              '已矫正智能体独立身份型号: ${identity['model']} -> $model');
        }
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceMacAddress(identity['mac']!);
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceClientId(identity['clientId']!);
        await XiaozhiDeviceInfoUtil.instance.setDeviceModel(model);
        logger.info('已应用智能体独立身份: ${identity['mac']}');
      } else {
        // v1.1.6: 旧智能体首次进入时，把当前全局身份快照绑定为它的专属身份，
        // 防止全局被其他智能体覆盖后拿错身份连接
        final mac = await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress();
        final cid = await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();
        // v4.3.0：快照绑定的型号同样归一（normalizeGlobalModel 已矫正全局，此处兜底）
        final model = AgentIdentityStore.normalizeModel(
            await XiaozhiDeviceInfoUtil.instance.getDeviceModel());
        await AgentIdentityStore.save(widget.agentId,
            mac: mac, clientId: cid, model: model);
        logger.info('已快照绑定旧智能体身份: $mac');
      }

      // 第一步: 执行 OTA 认证
      final authSuccess = await _performOtaAuthentication();
      if (!authSuccess) {
        logger.warning('OTA 认证失败,取消 WebSocket 连接');
        return;
      }

      // 第二步: 获取设备ID 与 ClientID（v1.1.6: 握手需上报真实 ClientID）
      final deviceId = await XiaozhiDeviceInfoUtil.instance
          .getDeviceMacAddress();
      final clientId = await XiaozhiDeviceInfoUtil.instance
          .getDeviceClientId();

      print(_currentAgent);
      // 第三步: 创建 WebSocket 管理器
      _wsManager = XiaozhiWebSocketManager(
        deviceId: deviceId,
        clientId: clientId,
        enableToken: false,
        // v6.11.8：心跳实验配置（默认 off；开发者中心可切候选，切换即重建连接）
        probeMode: _wsProbeModeFromConfig(),
        probeInterval: Duration(seconds: AppFeats.wsKeepaliveIntervalSec),
      );

      // 第四步: 添加事件监听器
      _wsManager!.addListener(_handleWebSocketEvent);

      // 第四步半 (v3.0.0)：MCP 设备端——应答服务器 initialize/tools/list/tools/call，
      // 注册 9 项工具让 AI 真实操控设备（协议对齐真机 mcp_server.cc，见 xiaoleweb.md 第五章）
      // v6.4.0：先预拉取外部 MCP 工具（不等待），让服务器下发 tools/list 时就能看到它们。
      // 失败不影响设备本地工具，异常全部由 ExternalMcpManager 内部消化。
      unawaited(ExternalMcpManager.instance.refreshAll());
      _setupMcpResponder();

      // 第五步: 使用Agent配置 wsUrl 和 wsToken 连接服务器
      await _connectToWebSocket(_currentAgent?.url ?? '', 'test-token');
    } catch (e) {
      logger.severe('初始化 WebSocket 失败: $e');
      _showError('连接初始化失败: $e');
    }
  }

  /// 使用指定的 URL 和 Token 连接 WebSocket
  Future<void> _connectToWebSocket(String url, String token) async {
    if (_wsManager == null) return;

    setState(() {
      _connectionStatus = '正在连接...';
    });

    try {
      logger.info('WS 连接开始 url=$url');
      await _wsManager!.connect(url, token);
      logger.info('WS 连接请求已发送（等待服务器 hello 握手）');
    } catch (e) {
      logger.severe('WebSocket 连接失败: $e');
      setState(() {
        _connectionStatus = '连接失败';
      });
      _showError('连接失败: $e');
    }
  }

  /// v3.0.0：创建 MCP 响应器并注册 P0 九项工具（执行器全部为本页真实实现）
  void _setupMcpResponder() {
    if (_wsManager == null) return;
    final responder = XiaozhiMcpResponder(
      send: (text) => _wsManager!.sendMessage(text),
      serverName: 'xiaole-app',
      serverVersion: '3.0.0',
      // v6.3.0：注入逐项开关过滤器（null=全部启用，保持既有行为不变）
      isToolEnabled: AppFeats.mcpToolEnabled,
      // v6.4.0：外部 MCP 工具合并下发 + 调用转发
      extraToolsProvider: ExternalMcpManager.instance.mergedTools,
      externalCaller: (name, args) async {
        final mgr = ExternalMcpManager.instance;
        // 返回 null = 该名字不是外部工具，响应器按"未知工具"处理
        if (!mgr.isExternal(name)) return null;
        return await mgr.dispatch(name, args);
      },
    );

    void register(XiaozhiMcpTool tool,
        Future<Map<String, dynamic>> Function(Map<String, dynamic>) exec) {
      responder.registerTool(tool, exec);
    }

    // v6.1.0：设备能力服务（音量/闹钟/日历/系统 intent/TTS/剪贴板/亮度…）
    final caps = DeviceCapabilityService.instance;

    // 1. 设备状态（音量/主题/网络；v4.2.0 真实电量[申请书8号] + 结构化状态卡片[申请书7号]）
    register(XiaozhiMcpStandardTools.status, (_) async {
      final mode = ref.read(themeModeProvider);
      // 真实电量：Android/iOS 读系统电池；桌面端不可用时回退「已接通电源」虚拟值
      int level = 100;
      bool charging = true;
      try {
        level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        charging = state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {
        // 平台不支持（Windows/桌面）保持虚拟值
      }
      // v6.1.0：volume 改读**真实系统媒体音量**
      // （原先上报的是软件增益值，与用户实际听感不符 —— 这就是"显示 100% 实际只有一半"的由来）
      final sysVolume = await caps.getVolume();
      final status = {
        'volume': sysVolume ?? AudioUtil.ttsVolumePercent,
        'theme': mode == ThemeMode.dark ? 'dark' : 'light',
        'battery': {'level': level, 'charging': charging},
        'network': _isConnected ? 'online' : 'offline',
        'active_timers': _mcpTimers.length,
        'scheduled_events': _mcpEvents.length,
      };
      // v4.2.0：设备状态卡片——AI 查状态时本地同步渲染结构化卡片（申请书 7 号）
      _appendOrCreateChatMessage(
        MessageSender.system,
        '📊 设备状态',
        metadata: {'card': 'device_status', 'data': status},
      );
      return status;
    });

    // 2. 音量（v6.1.0：改为控制**系统媒体音量** —— 原先只改软件增益，
    //    受系统音量上限约束，导致"AI 说调到 100% 但实际只有一半响度"）
    register(XiaozhiMcpStandardTools.setVolume, (args) async {
      final v = (args['volume'] as num?)?.toInt() ?? -1;
      if (v < 0 || v > 100) {
        return {'success': false, 'message': 'volume must be 0-100'};
      }
      final r = await caps.setVolume(v);
      // 软件增益同步跟随：万一某些机型系统音量接口不可用，App 内增益仍能兜底
      AudioUtil.setTtsVolume(v);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '🔊 AI 已把系统音量调到 $v%');
      }
      return r;
    });

    // 3. 主题（真实切换深浅色）
    register(XiaozhiMcpStandardTools.setTheme, (args) async {
      final theme = args['theme'] as String?;
      if (theme != 'light' && theme != 'dark') {
        return {'success': false, 'message': 'theme must be light or dark'};
      }
      final notifier = ref.read(themeModeProvider.notifier);
      final before = ref.read(themeModeProvider) == ThemeMode.dark;
      if ((theme == 'dark') != before) {
        theme == 'dark'
            ? await notifier.setDarkMode()
            : await notifier.setLightMode();
      }
      _appendOrCreateChatMessage(
          MessageSender.system, '🎨 AI 已切换${theme == 'dark' ? '深色' : '浅色'}模式');
      return {
        'success': true,
        'theme': ref.read(themeModeProvider) == ThemeMode.dark ? 'dark' : 'light'
      };
    });

    // 4-6. 定时器（创建/列表/停止；到点 = 系统消息 + 震动 + Toast）
    register(XiaozhiMcpStandardTools.timerCreate, (args) async {
      final secs = (args['seconds'] as num?)?.toInt() ?? 0;
      if (secs <= 0) {
        return {'success': false, 'message': 'invalid seconds'};
      }
      final name = (args['event_name'] as String?) ??
          (secs >= 60 ? '倒计时 ${secs ~/ 60} 分钟' : '倒计时 $secs 秒');
      final id = DateTime.now().millisecondsSinceEpoch;
      final timer = Timer(Duration(seconds: secs), () {
        _mcpTimers.removeWhere((t) => t['id'] == id);
        _mcpFireReminder('⏰ $name · 时间到！');
      });
      _mcpTimers.add({'id': id, 'name': name, 'endAt': DateTime.now().add(Duration(seconds: secs)), 'timer': timer});
      _appendOrCreateChatMessage(
          MessageSender.system, '⏳ 已创建倒计时「$name」（$secs 秒）');
      return {'success': true, 'id': id, 'name': name, 'seconds': secs};
    });
    register(XiaozhiMcpStandardTools.timerList, (_) async {
      final now = DateTime.now();
      return {
        'tasks': _mcpTimers
            .map((t) => {
                  'id': t['id'],
                  'name': t['name'],
                  'remaining_seconds':
                      (t['endAt'] as DateTime).difference(now).inSeconds,
                })
            .toList()
      };
    });
    register(XiaozhiMcpStandardTools.timerStop, (args) async {
      final id = (args['id'] as num?)?.toInt();
      final hit = _mcpTimers.where((t) => t['id'] == id).toList();
      if (id == null || hit.isEmpty) {
        return {'success': false, 'message': 'timer not found'};
      }
      (hit.first['timer'] as Timer?)?.cancel();
      _mcpTimers.removeWhere((t) => t['id'] == id);
      _appendOrCreateChatMessage(
          MessageSender.system, '⏳ 倒计时「${hit.first['name']}」已停止');
      return {'success': true};
    });

    // 7-9. 日程（v6.1.0：create 改为写**系统日历** —— 原先用内存 Timer，App 退出/重启即失效，
    //      这就是"日程设了没用"的根因）
    register(XiaozhiMcpStandardTools.scheduleCreate, (args) async {
      final timeStr = args['time'] as String?;
      final name = (args['event_name'] as String?) ?? '日程';
      // 协议格式 YYYY-MM-DD HH:MM → DateTime.tryParse 可解析（空格分隔兼容）
      final tm = timeStr == null ? null : DateTime.tryParse(timeStr);
      if (tm == null) {
        return {'success': false, 'message': 'invalid time, use YYYY-MM-DD HH:MM'};
      }
      final r = await caps.createCalendarEvent(title: name, start: tm);
      if (r['success'] == true) {
        // 仅在 App 内留一条记录，便于 schedule.get_events 查询
        // （真正的提醒由系统日历 App 负责；此处不再创建内存 Timer）
        _mcpEvents.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'name': name,
          'time': timeStr,
          'timer': null,
        });
        _appendOrCreateChatMessage(
            MessageSender.system, '📅 已请求写入系统日历「$name」（$timeStr）——请在日历界面点「保存」');
      }
      return r;
    });
    register(XiaozhiMcpStandardTools.scheduleList, (_) async {
      return {
        'events':
            _mcpEvents.map((e) => {'id': e['id'], 'name': e['name'], 'time': e['time']}).toList()
      };
    });
    register(XiaozhiMcpStandardTools.scheduleDelete, (args) async {
      final id = (args['id'] as num?)?.toInt();
      final hit = _mcpEvents.where((e) => e['id'] == id).toList();
      if (id == null || hit.isEmpty) {
        return {'success': false, 'message': 'event not found'};
      }
      (hit.first['timer'] as Timer?)?.cancel();
      _mcpEvents.removeWhere((e) => e['id'] == id);
      return {'success': true};
    });

    // 10. AI 主动拍照识图（v3.2.0）：拉起相机 → 上传识图 → 描述回传 AI
    register(XiaozhiMcpStandardTools.takePhoto, (args) async {
      final q = (args['question'] as String?) ?? '这张图里有什么？';
      if (_visionUrl == null || _visionUrl!.isEmpty) {
        return {'success': false, 'message': 'camera/vision not ready'};
      }
      _appendOrCreateChatMessage(MessageSender.system, '📷 AI 请求拍照：$q');
      try {
        final xfile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1280,
          imageQuality: 85,
        );
        if (xfile == null) {
          return {'success': false, 'message': 'user cancelled camera'};
        }
        final up = await _uploadVision(xfile.path, q);
        // v4.3.5【方案一修正】：官方固件 Esp32Camera::Explain() 的全部实现就是
        //   `std::string result = http->ReadAll(); return result;`
        // —— 把 HTTP 响应体**原样**作为 MCP 工具结果返回，由**服务端 LLM** 依据其中的
        //    uuid/message（"Please call the tool image_to_text…"）自行完成描述获取。
        //    官方仓库全文件 `image_to_text` 出现 0 次 ⇒ **设备端不存在"第二段调用"**。
        //    旧实现错在此处也去发 tools/call（方向反了：tools/call 是服务器→设备），必然超时。
        // 现按官方做法回传响应体原文：旧协议下它本身就是描述；新协议下它是给 LLM 的提示。
        final desc = up['raw'] ?? up['message'] ?? up['value'] ?? '';
        logger.info('MCP take_photo 回传响应体原文 ${desc.length} 字符，交由服务端 LLM 处理'
            '（kind=${up['kind']}）');
        // 仅旧协议（响应体即描述）才回填 AI 气泡；新协议下这段是**给 LLM 的提示**，
        // 不能显示给用户（否则又变成"把 JSON 摆给用户看"），真正的描述由服务端 LLM 回复。
        if (up['kind'] == 'text') {
          _appendOrCreateChatMessage(MessageSender.ai, desc);
        }
        return {'success': true, 'question': q, 'description': desc};
      } catch (e) {
        return {'success': false, 'message': '$e'};
      }
    });

    // 11. AI 屏显图片（v3.2.0）：图片 URL 进 AI 消息（气泡用 CachedNetworkImage 渲染）
    register(XiaozhiMcpStandardTools.previewImage, (args) async {
      final url = args['url'] as String?;
      if (url == null || url.isEmpty) {
        return {'success': false, 'message': 'invalid url'};
      }
      final message = MessageModel(
        id: 'img_${DateTime.now().millisecondsSinceEpoch}',
        agentId: widget.agentId,
        type: MessageType.image,
        content: url,
        sender: MessageSender.ai,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(message);
      });
      ChatHistoryStore.save(widget.agentId, _messages);
      _scrollToBottom();
      return {'success': true};
    });

    // ==================== v6.1.0 新增 15 项能力 ====================
    // 方案：PLAN_v6.1.0_MCP设备工具能力扩展.md ｜ 能力实现：DeviceCapabilityService

    // ---------- 🅑 补齐官方标准（官方 mcp_server.cc 有、我们原先缺失）----------

    // 12. 屏幕亮度（应用级：不需要 WRITE_SETTINGS 特殊权限）
    register(XiaozhiMcpStandardTools.setBrightness, (args) async {
      final b = (args['brightness'] as num?)?.toInt() ?? -1;
      if (b < 1 || b > 100) {
        return {'success': false, 'message': 'brightness must be 1-100'};
      }
      final r = await caps.setBrightness(b);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '☀️ AI 已把屏幕亮度调到 $b%');
      }
      return r;
    });

    // 13. 屏幕信息（逻辑像素 + 物理像素，供 AI 适配布局）
    register(XiaozhiMcpStandardTools.getScreenInfo, (_) async {
      final size = MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return {
        'success': true,
        'width': size.width.round(),
        'height': size.height.round(),
        'device_pixel_ratio': dpr,
        'physical_width': (size.width * dpr).round(),
        'physical_height': (size.height * dpr).round(),
      };
    });

    // 14. 系统与设备信息
    register(XiaozhiMcpStandardTools.getSystemInfo, (_) async {
      final out = <String, dynamic>{
        'success': true,
        'app_version': AppConfig.appVersion,
        'platform': Platform.operatingSystem,
      };
      try {
        if (Platform.isAndroid) {
          final a = await DeviceInfoPlugin().androidInfo;
          out.addAll({
            'brand': a.brand,
            'model': a.model,
            'android_version': a.version.release,
            'sdk_int': a.version.sdkInt,
          });
        }
      } catch (e) {
        out['note'] = '部分设备信息不可用：$e';
      }
      return out;
    });

    // 15. 截屏（App 内截屏：走 RenderRepaintBoundary，**不需要 MediaProjection、无系统权限**）
    register(XiaozhiMcpStandardTools.snapshot, (_) async {
      try {
        final ro = _snapshotKey.currentContext?.findRenderObject();
        if (ro is! RenderRepaintBoundary) {
          return {'success': false, 'message': '当前界面不支持截屏'};
        }
        final img = await ro.toImage(pixelRatio: 1.5);
        try {
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) return {'success': false, 'message': '截屏编码失败'};
          final f = File('${Directory.systemTemp.path}/xl_snapshot_'
              '${DateTime.now().millisecondsSinceEpoch}.png');
          await f.writeAsBytes(bytes.buffer.asUint8List());
          return {'success': true, 'path': f.path, 'bytes': bytes.lengthInBytes};
        } finally {
          // v6.1.2：释放 ui.Image 占用的原生/GPU 内存
          // （独立验证发现：不 dispose 会导致**每次截屏泄漏一张图**）
          img.dispose();
        }
      } catch (e) {
        return {'success': false, 'message': '截屏失败：$e'};
      }
    });

    // 16. 重启会话（App 无真重启能力 → 映射为「重新连接 + 清空当前会话」）
    register(XiaozhiMcpStandardTools.reboot, (_) async {
      _appendOrCreateChatMessage(
          MessageSender.system, '🔄 AI 请求重启会话，正在重新连接…');
      try {
        _ensureConnectedThen(() {}, '重启会话');
        return {
          'success': true,
          'message': '已触发重新连接并重置当前会话状态（不会重启手机）',
        };
      } catch (e) {
        return {'success': false, 'message': '重连失败：$e'};
      }
    });

    // ---------- 🅒 Android 系统能力（全部免危险权限）----------

    // 17. 拨号（ACTION_DIAL：只打开拨号盘预填，不直接拨出）
    register(XiaozhiMcpStandardTools.dial, (args) async {
      final r = await caps.dial(args['number'] as String? ?? '');
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '📞 已打开拨号盘：${r['number']}');
      }
      return r;
    });

    // 18. 短信（ACTION_SENDTO：预填号码与内容，用户点发送）
    register(XiaozhiMcpStandardTools.sendSms, (args) async {
      final r = await caps.sendSms(
        number: args['number'] as String? ?? '',
        body: args['body'] as String? ?? '',
      );
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '💬 已打开短信界面（发给 ${r['number']}）');
      }
      return r;
    });

    // 19. 地图导航
    register(XiaozhiMcpStandardTools.navigate, (args) async {
      final r = await caps.navigate(args['destination'] as String? ?? '');
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '🗺 已打开地图导航：${r['destination']}');
      }
      return r;
    });

    // 20. 打开系统设置页
    register(XiaozhiMcpStandardTools.openSettings,
        (args) async => caps.openSettings(args['page'] as String? ?? ''));

    // 21. 打开网页
    register(XiaozhiMcpStandardTools.openUrl,
        (args) async => caps.openUrl(args['url'] as String? ?? ''));

    // ---------- 🅐 系统闹钟 / 轻提示 / 分享 ----------

    // 22. 系统闹钟（**真·系统时钟闹钟**：App 关闭、手机重启后依然会响）
    register(XiaozhiMcpStandardTools.setAlarm, (args) async {
      final h = (args['hour'] as num?)?.toInt() ?? -1;
      final m = (args['minute'] as num?)?.toInt() ?? -1;
      if (h < 0 || m < 0) {
        return {'success': false, 'message': 'hour/minute are required'};
      }
      List<int>? days;
      final raw = args['weekdays'];
      if (raw is List) {
        days = raw.whereType<num>().map((e) => e.toInt()).toList();
      }
      final r = await caps.setAlarm(
          hour: h, minute: m, label: args['label'] as String?, weekdays: days);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(MessageSender.system,
            '⏰ 已请求系统闹钟 ${r['time']}（请在时钟界面点「保存」）');
      }
      return r;
    });

    // 23. 轻提示（AI 主动弹，不打断对话）
    register(XiaozhiMcpStandardTools.showToast, (args) async {
      final t = args['text'] as String? ?? '';
      if (t.trim().isEmpty) return {'success': false, 'message': 'text required'};
      caps.showToast(t);
      return {'success': true};
    });

    // 24. 分享文本到笔记/备忘录/微信等
    register(XiaozhiMcpStandardTools.shareText, (args) async {
      return caps.shareText(
        args['text'] as String? ?? '',
        subject: args['subject'] as String?,
      );
    });

    // ---------- 🅓 剪贴板 ----------

    // 25. 读剪贴板
    register(XiaozhiMcpStandardTools.clipboardGet, (_) async {
      final t = await caps.getClipboard();
      return {'success': t != null, 'text': t ?? ''};
    });

    // 26. 写剪贴板
    register(XiaozhiMcpStandardTools.clipboardSet, (args) async {
      return caps.setClipboard(args['text'] as String? ?? '');
    });

    // 27. 定位能力（v6.3.0）：返回 GCJ-02 坐标；权限/服务/超时全部内部消化，绝不阻塞 UI
    register(XiaozhiMcpStandardTools.locationGetCurrent, (_) async {
      final loc = await LocationService.instance.getCurrent();
      if (loc['success'] == true) {
        _appendOrCreateChatMessage(MessageSender.system,
            '📍 AI 已获取当前位置（精度 ${loc['accuracy']} 米）');
      } else {
        _appendOrCreateChatMessage(MessageSender.system,
            '📍 获取位置失败：${loc['message']}');
      }
      return loc;
    });

    // 28. v6.5.0：AI 主动来电 —— 开场白回放（接通后小智调它取回要说的那句话）
    register(
      const XiaozhiMcpTool(
        name: 'self.proactive.get_opening',
        description: '取回本轮主动来电要说的开场白。收到「说开场白」时调用它，'
            '然后用口语把返回内容原样说给用户听。',
        inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
      ),
      (_) async {
        final text = _proactiveOpeningForReplay;
        return {
          'success': true,
          'text': text.isEmpty ? '（当前没有待说的开场白）' : '请用口语把下面这句说给用户听：$text',
        };
      },
    );

    _mcpResponder = responder;
    logger.info('MCP 设备端就绪：注册 ${responder.toolCount} 项工具');
  }

  /// MCP 提醒触发（定时器/日程共用）：聊天系统消息 + 震动 + Toast
  void _mcpFireReminder(String text) {
    _appendOrCreateChatMessage(MessageSender.system, text);
    ToastUtil.show(text);
    Vibration.vibrate(pattern: [0, 300, 150, 300]).catchError((_) {});
    logger.info('MCP 提醒: $text');
  }

  /// v3.1.0：周期性设备状态上报（WS 连接即报 + 每 10 分钟，见 xiaoleweb.md §2.3）
  void _startOtaReporting() {
    _stopOtaReporting();
    _otaService?.reportStatus(
        appName: 'ajb_agent_flutter', appVersion: AppConfig.appVersion);
    _otaReportTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _otaService?.reportStatus(
          appName: 'ajb_agent_flutter', appVersion: AppConfig.appVersion);
    });
  }

  void _stopOtaReporting() {
    _otaReportTimer?.cancel();
    _otaReportTimer = null;
  }

  /// v3.3.0：启动 MQTT 常驻在线（凭据来自 OTA 响应；订阅设备下行主题，
  /// 后台下发的 MCP/远程配置转现有响应器——远程主题/音色自定义随之解锁）
  Future<void> _startMqttPresence(MqttInfo mqtt) async {
    if (_mqttPresence != null) return;
    final mac = (await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress())
        .toLowerCase(); // 铁律：MAC 全小写
    final presence = XiaozhiMqttPresence(
      endpoint: mqtt.endpoint,
      clientId: mqtt.clientId,
      username: mqtt.username,
      password: mqtt.password,
      mac: mac,
      onMessage: (msg) {
        final type = msg['type'] as String?;
        if (type == 'mcp' && _mcpResponder != null && AppFeats.mcptools) {
          final payload = msg['payload'];
          if (payload is Map) {
            _mcpResponder!
                .handlePayload(Map<String, dynamic>.from(payload));
          }
        } else if (type == 'goodbye') {
          logger.info('MQTT 下发 goodbye（正常保活交互）');
        }
      },
    );
    presence.start();
    _mqttPresence = presence;
    logger.info('📡 MQTT 常驻启动（endpoint=${mqtt.endpoint}）');
  }

  /// 识图两段式第二步：拿到 `uuid` 后向服务器索要图片描述。
  ///
  /// ⚠️ 现状（v4.3.4 定格，2026-09-11 真机结论）：**此步骤在官方服务器上无可用协议，功能暂缓**。
  /// 调用链路（A/C 两路）与日志埋点全部保留，等日后拿到官方教程或服务器修复后再继续开发。
  ///
  /// 【已确认的事实】（完整证据见仓库根 `故障报告_识图image_to_text无响应_2026-09-11.md`）
  ///   1. 上传链路完全正常：POST `capabilities.vision.url` → HTTP 200 + `{success, uuid, message}`；
  ///   2. 服务器返回的 message（"Please call the tool `image_to_text` ... then reply to the user"）
  ///      措辞是**给 LLM 的指令**（只有 LLM 才能 "reply to the user"），设备无法执行；
  ///   3. 设备发 `tools/call image_to_text{uuid}`（路径 A）→ 服务器 **30 秒零响应**（无 result 也 error）；
  ///   4. 设备把 message 当文本请求发（原路径 B，`listen/detect`）→ 服务器**明确拒绝**：
  ///      `{"type":"alert","status":"ERROR","message":"Detect is only for wake words, do not send long texts."}`
  ///      （官方服务器对 detect 只接受唤醒词短语，长文本一律拒绝——第三方开发者亦有公开记录）
  ///      → **v4.3.4 已移除路径 B**（无效，且每次都会触发服务器 ERROR）；
  ///   5. 全网检索无该协议的正确实现（第三方客户端只能用第三方视觉 API 绕过，或改打自建服务器）；
  ///   6. 服务器对**非法**请求会明确报错，却对路径 A **完全静默** → A 不是服务器认识的用法。
  ///
  /// 【判定】疑似**服务端该功能未完成**：把"给 LLM 的 tool-call 提示"当作 HTTP 响应体返回了，
  /// 真正的描述生成从未发生。客户端无法通过公开协议完成，故暂缓。
  ///
  /// 【日后如何继续】
  ///   - 拿到官方教程/抓包对比：按新协议改写下方发送体即可（埋点已齐备，日志分类默认开
  ///     `vision`/`ws`/`mcp`，一次复现就能看清全部往返）；
  ///   - 服务器修复：本方法**无需改动**，路径 A 的应答会经 `_pendingMcpCalls` 自动命中；
  ///   - 改用自建 xiaozhi-esp32-server：其识图链路完整，本方法同样可直接复用。
  ///
  /// 保留两路（谁先出结果用谁）：
  ///   [A] 发 tools/call image_to_text{uuid} → 由 _pendingMcpCalls 捕获 mcp 应答
  ///   [C] 纯等待服务器主动推送（tts/llm 文本）→ 由 _visionAux 捕获
  Future<String> _callImageToText(String uuid) async {
    // v4.3.2：切到相机 Activity 期间 WS 很可能已被系统回收/服务端断开，
    // 此处先重新校验连接状态，断了就先重连再发，避免"连接已死却按在线发"。
    if (_wsManager == null || !_isConnected) {
      logger.warning('image_to_text 前置检查未通过：'
          'wsManager=${_wsManager != null} isConnected=$_isConnected，先尝试重连');
      final ok = await _ensureConnectedForVision();
      if (!ok) throw '连接已断开且自动重连失败，请稍后重试';
    }
    final id = ++_mcpCallId;
    final c = Completer<String>();
    _pendingMcpCalls[id] = c;
    _visionAux = Completer<String>();

    // ---------- 路径 A：tools/call image_to_text ----------
    final reqA = jsonEncode({
      'type': 'mcp',
      'payload': {
        'jsonrpc': '2.0',
        'id': id,
        'method': 'tools/call',
        'params': {
          'name': 'image_to_text',
          'arguments': {'uuid': uuid},
        },
      },
    });
    _wsManager!.sendMessage(reqA);
    logger.info('[A] 识图：已发起 tools/call image_to_text id=$id uuid=$uuid');

    // 注：v4.3.4 已移除原「路径 B」（把服务器 message 当 listen/detect 文本请求发送）——
    // 真机证实官方服务器一律拒绝长文本（alert: "Detect is only for wake words..."），
    // 且每次都会触发服务器 ERROR 报警，故不再发送。详见方法头注释。

    // ---------- 路径 C：纯等待服务器主动推送 ----------
    logger.info('[C] 识图：开始监听服务器主动推送（tts/llm 文本）');

    try {
      // 三路竞速：A/B → mcp 应答（c）；C → 服务器主动推送（_visionAux）
      final text = await Future.any<String>([
        c.future,
        _visionAux!.future,
      ]).timeout(const Duration(seconds: 30));
      logger.info('识图结果到达（${text.length} 字符）');
      return text;
    } on TimeoutException {
      final silent = _wsManager?.silentSeconds;
      logger.warning('识图三路均无结果（30s）id=$id uuid=$uuid'
          ' isConnected=$_isConnected silentSeconds=$silent');
      throw '图片已上传成功，但服务器未返回识别结果（可能服务端未就绪）。已记录日志，请复制日志反馈';
    } finally {
      _pendingMcpCalls.remove(id);
      _visionAux = null;
    }
  }

  /// v4.3.2：识图前的按需重连（复用「想打就打」的待办执行链路）。
  /// 返回 true = 已连接可继续；false = 20s 内没连上。
  /// v4.3.3：[force]=true 时**无视 isConnected 标志**，先断开旧连接再重建——
  /// 相机是独立 Activity，期间连接可能已被回收而标志位仍是陈旧的 true，
  /// 这时只有"重建"才可信（见 v4.3.2 真机日志：isConnected=true 却收不到应答）。
  Future<bool> _ensureConnectedForVision({bool force = false}) async {
    if (!force && _wsManager != null && _isConnected) return true;
    if (force) {
      await _cleanupWebSocket(source: 'vision_refresh');
    }
    final c = Completer<bool>();
    _ensureConnectedThen(() {
      if (!c.isCompleted) c.complete(true);
    }, '识图');
    try {
      return await c.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
    } finally {
      if (!c.isCompleted) c.complete(false);
    }
  }

  /// v3.1.0：视觉识物（拍照问 AI，见 xiaoleweb.md §7）
  /// 链路：image_picker 拍照 → multipart POST vision 接口（headers 带
  /// Device-Id/Client-Id/Authorization；上游为 http://，Manifest 已开 cleartext）
  /// → v4.3.1 两段式：旧协议{text}直显 / 新协议{uuid}发 image_to_text 拿描述。
  Future<void> _takePhotoAndAsk() async {
    // v4.3.2 埋点：点击即记录全部前置状态，一眼看出卡在哪道闸
    logger.info('📷 点击拍照识物：visionUrl=${_visionUrl == null ? "null" : "已获取"}'
        ' isConnected=$_isConnected'
        ' featVision=${AppFeats.vision} featMcptools=${AppFeats.mcptools}');
    if (_visionUrl == null || _visionUrl!.isEmpty) {
      logger.warning('识图中止：visionUrl 为空（未拿到服务器 MCP initialize 的'
          ' capabilities.vision，或 🧰 MCP 开关关闭导致 initialize 未处理）');
      ToastUtil.show('尚未获取视觉接口——先连接一次即可');
      return;
    }
    if (!_isConnected) {
      _ensureConnectedThen(_doTakePhotoAndAsk, '识图');
      return;
    }
    await _doTakePhotoAndAsk();
  }

  Future<void> _doTakePhotoAndAsk() async {
    if (_visionUrl == null || _visionUrl!.isEmpty) {
      logger.warning('识图中止（doTake）：visionUrl 为空');
      ToastUtil.show('尚未获取视觉接口——先连接一次即可');
      return;
    }
    try {
      final picker = ImagePicker();
      logger.info('识图：拉起系统相机');
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (xfile == null) {
        // v4.3.2：此前这里静默 return（用户以为"没反应"），补埋点便于区分
        logger.warning('识图中止：相机未返回图片（用户取消 / 权限被拒 / 相机异常）');
        return;
      }
      logger.info('识图：相机返回图片 path=${xfile.path}');

      // v4.3.3：相机是独立 Activity，拍照期间 App 进后台，连接很可能已被回收，
      // 而 _isConnected 会停留在陈旧值（v4.3.2 真机日志实证：isConnected=true 却收不到应答）。
      // 因此这里用"静默时长"（距上次收到服务器消息的秒数）判断连接是否可信，
      // 不可信则**强制重建**，并等新的 initialize 重新下发 vision url/token 后再上传。
      final silent = _wsManager?.silentSeconds;
      final needReconnect = _wsManager == null ||
          !_isConnected ||
          silent == null ||
          silent > 25;
      logger.info('识图：拍照返回连接体检 isConnected=$_isConnected'
          ' silentSeconds=$silent 需重建=$needReconnect');
      if (needReconnect) {
        final ok = await _ensureConnectedForVision(force: true);
        if (!ok) throw '连接已断开且自动重连失败，请稍后重试';
        // 等新的 MCP initialize 把 vision url/token 重新下发（最多 5 秒）
        for (var i = 0; i < 50 && (_visionUrl == null || _visionUrl!.isEmpty); i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        logger.info('识图：重连后 visionUrl=${_visionUrl == null ? "null（未下发）" : "已就绪"}'
            ' tokenLen=${(_visionToken ?? '').length}');
      }

      // v4.3.2：占位气泡带固定 id，成功/失败/超时都要落到终态（更新或替换），
      // 杜绝"📷 拍照识物中…"之后没有后话。
      final placeholderId = 'vision_${DateTime.now().millisecondsSinceEpoch}';
      _appendSystemMessage('📷 拍照识物中…', id: placeholderId);
      try {
        final up = await _uploadVision(xfile.path, '这张图里有什么？');
        final desc = up['kind'] == 'uuid'
            ? await _callImageToText(up['value']!)
            : (up['value'] ?? '识图结果为空');
        _finishVisionBubble(placeholderId, MessageSender.ai, desc);
        logger.info('视觉识物成功（${desc.length} 字符）');
      } catch (e, st) {
        logger.severe('视觉识物失败: $e\n${_shortStack(st)}');
        _finishVisionBubble(placeholderId, MessageSender.system, '⚠️ $e');
      }
    } catch (e, st) {
      // v4.3.1：任何失败只显示友好中文，绝不把原始 JSON/响应体抛给用户
      logger.severe('拍照阶段异常: $e\n${_shortStack(st)}');
      _appendOrCreateChatMessage(MessageSender.system, '⚠️ $e');
    }
  }

  /// v4.3.2：追加一条带指定 id 的 system 消息（识物占位气泡用）
  void _appendSystemMessage(String content, {required String id}) {
    final message = MessageModel(
      id: id,
      agentId: widget.agentId,
      type: MessageType.system,
      content: content,
      sender: MessageSender.system,
      status: MessageStatus.sent,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(message);
    });
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// v4.3.2：把识物占位气泡替换为终态内容（成功=AI 描述，失败=⚠️ 中文提示）。
  /// 占位气泡若已不存在（页面重建等），则退化为追加一条新消息，保证一定有终态。
  void _finishVisionBubble(
      String placeholderId, MessageSender sender, String content) {
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m.id == placeholderId);
    setState(() {
      if (idx >= 0) {
        final old = _messages[idx];
        _messages[idx] = MessageModel(
          id: old.id,
          agentId: old.agentId,
          type: sender == MessageSender.system
              ? MessageType.system
              : MessageType.text,
          content: content,
          sender: sender,
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
        );
      } else {
        _messages.add(MessageModel(
          id: 'vision_${DateTime.now().millisecondsSinceEpoch}',
          agentId: widget.agentId,
          type: sender == MessageSender.system
              ? MessageType.system
              : MessageType.text,
          content: content,
          sender: sender,
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
        ));
      }
    });
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// v4.3.2：日志正文/响应体截断（超出标注被截字符数，避免刷爆缓冲）
  static String _clip(String s, [int max = 500]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...[+${s.length - max} chars]';
  }

  /// v4.3.2：堆栈只取前 6 行进日志
  static String _shortStack(StackTrace st) =>
      st.toString().split('\n').take(6).join(' | ');

  /// v3.2.0：识图上传共享逻辑（手动 📷 与 MCP take_photo 共用）。
  /// v4.3.1：返回结构化结果——
  ///   {'kind':'text','value':描述}  旧协议（服务器同步返回描述，直显）
  ///   {'kind':'uuid','value':uuid}  新协议两段式（调用方再发 image_to_text）
  ///   {'kind':'raw','value':原文}   未知形态兜底
  /// 失败抛异常（HTTP 只报状态码，响应体进日志不进 UI）。
  Future<Map<String, String>> _uploadVision(String filePath, String question) async {
    final mac =
        (await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress())
            .toLowerCase(); // 铁律：MAC 全小写
    final clientId = await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();

    final req = http.MultipartRequest('POST', Uri.parse(_visionUrl!))
      ..fields['question'] = question
      ..files.add(await http.MultipartFile.fromPath('file', filePath,
          filename: 'camera.jpg'));
    req.headers['Device-Id'] = mac;
    if (clientId.isNotEmpty) {
      req.headers['Client-Id'] = clientId;
    }
    if ((_visionToken ?? '').isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${_visionToken}';
    }

    final sw = Stopwatch()..start();
    logger.info('识图上传开始 url=$_visionUrl question=$question file=$filePath'
        ' deviceId=$mac clientId=$clientId');
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    sw.stop();
    logger.info('识图上传完成 HTTP ${streamed.statusCode}'
        ' 耗时 ${sw.elapsedMilliseconds}ms 响应体=${_clip(body)}');
    if (streamed.statusCode != 200) {
      logger.severe('识图上传 HTTP ${streamed.statusCode}: $body');
      throw '识图上传失败（HTTP ${streamed.statusCode}），请稍后重试';
    }
    String kind = 'raw', value = body, serverMsg = '';
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        // v4.3.3：提取服务器返回的 message（新协议里它是"如何取到描述"的提示文本）
        if (j['message'] is String) serverMsg = (j['message'] as String).trim();
        if (j['text'] is String && (j['text'] as String).isNotEmpty) {
          kind = 'text'; // 旧协议：{"success":true,"text":"<描述>"}
          value = j['text'] as String;
        } else if (j['uuid'] is String && (j['uuid'] as String).isNotEmpty) {
          kind = 'uuid'; // 新协议两段式：{"success":true,"uuid":"..."}
          value = j['uuid'] as String;
        }
      }
    } catch (e) {
      // v4.3.2：此处原本静默吞掉解析异常 → 退化成 kind='raw'，
      // 会把响应体原文（JSON）直接显示给用户。补日志以便定位。
      logger.warning('识图上传响应不是合法 JSON，按原文兜底：${_clip(body)}');
    }
    logger.info('识图上传解析结果 kind=$kind valueLen=${value.length}'
        ' serverMessage=${serverMsg.isEmpty ? "(无)" : serverMsg}');
    // v4.3.5：额外回传响应体原文（raw）。官方固件 Esp32Camera::Explain() 的做法就是把它**原样**
    // 作为工具结果返回给服务端 LLM（见 视觉方案修复.md 第一节），故 MCP 场景需要用到它。
    return {'kind': kind, 'value': value, 'message': serverMsg, 'raw': body};
  }

  /// 处理 WebSocket 事件
  void _handleWebSocketEvent(XiaozhiEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case XiaozhiEventType.connected:
        _reconnectUiTimer?.cancel();
        _reconnectUiTimer = null;
        setState(() {
          _isConnected = true;
          _connectionStatus = '已连接';
          _showReconnectBar = false;
        });
        logger.info('WebSocket 已连接');
        // v3.1.0：连接即开始周期性设备状态上报（后台「最近活跃」对齐）
        _startOtaReporting();
        //_addConnectionStatusMessage('已连接到服务器');
        break;

      case XiaozhiEventType.disconnected:
        // v6.11.17：断线即本轮失败终结，关闭气泡合并窗口（P2-1）
        _sttMergeOpen = false;
        _aiMergeOpen = false;
        final codeInfo = event.data?.toString() ?? '';
        // 432x = 身份校验失败：重连无效，必须让用户看到真实原因与手动入口
        final fatalIdentity = codeInfo.startsWith('432');
        setState(() {
          _isConnected = false;
          _showReconnectBar = false;
          if (fatalIdentity) {
            // v1.1.6: 显示服务器关闭码，便于真机诊断失联原因
            _connectionStatus =
                codeInfo.isEmpty ? '已断开' : '已断开 ($codeInfo)';
          } else {
            // v6.11.7：1005/1006 多为云端按业务空闲回收，管理器 1–4s 内自动补连。
            // 不再显示"已断开"，只显示与"已连接"等宽的"重连中…"（顶部不跳字、不弹条）。
            _connectionStatus = '重连中…';
          }
        });
        // v4.3.2 埋点：断开原因（close code）进日志
        logger.warning('WebSocket 已断开 closeCode=${event.data} fatalIdentity=$fatalIdentity');
        // v3.1.0：断线停止周期上报（重连成功后自动恢复）
        _stopOtaReporting();
        if (!fatalIdentity) _armReconnectUiTimer();
        //_addConnectionStatusMessage('与服务器断开连接');
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        _handleBinaryMessage(event.data as List<int>);
        break;

      case XiaozhiEventType.error:
        final errText = event.data?.toString() ?? '';
        logger.severe('WebSocket 错误: $errText');
        // v6.2.1：瞬时网络错误（DNS 解析失败 / 连接超时 / 连接被拒等）由 WS 管理器
        // 自动重连兜底，不再弹红条打扰；仅刷新顶部状态栏 + 记日志。
        // 需用户处理的错误（身份拒绝 432x、重连超限、认证失败等）仍弹红条。
        if (_isNetworkTransientError(errText)) {
          if (mounted) {
            setState(() {
              _connectionStatus = '网络异常，正在自动重连…';
            });
          }
        } else {
          _showError('连接错误: $errText');
          // v6.11.7：重连上限/身份拒绝等"自愈不了"的错误，停止"重连中"假象，
          // 交还状态条与手动「重连」按钮，避免用户一直等一个不会来的恢复。
          if (!_isConnected) {
            setState(() {
              _connectionStatus = '连接已断开';
              _showReconnectBar = true;
            });
          }
        }
        break;
    }
  }

  /// 处理二进制消息（音频数据）
  void _handleBinaryMessage(List<int> data) {
    // v6.8.1（B 项）：挂断后静默窗口——丢弃挂断后短窗口内到达的迟到音频帧。
    // 文字聊天也经此路径播放 TTS，故不能"非通话就全丢"，只做挂断后短窗口丢弃。
    if (_voiceHangupAt != null &&
        DateTime.now().difference(_voiceHangupAt!) < _voiceHangupMuteWindow) {
      return;
    }

    //logger.info('收到音频数据: ${data.length} 字节');

    // 标记 AI 开始播放
    if (!_isAiPlaying) {
      _wsManager?.markConversationActive('下行音频'); // v6.11.9：AI 正在播放 → 保活暂停
      setState(() {
        _isAiPlaying = true;
      });
      logger.info('AI 开始播放音频，暂停发送麦克风数据');
    }

    // 收到音频即代表 AI 已响应，隐藏输入指示器
    _setTyping(false);
    
    // 重置定时器，如果一段时间没有收到新的音频数据，则认为播放结束
    _aiPlayingTimer?.cancel();
    _aiPlayingTimer = Timer(const Duration(milliseconds: 500), () {
      // 500ms 没有收到新的音频数据，认为播放结束
      if (_isAiPlaying) {
        setState(() {
          _isAiPlaying = false;
        });
        // v4.4.0：进入尾音保护（根因①——此时扬声器可能还在播最后几个字）
        _enterTailGuard();
        // v6.11.9：音频播放结束 → 5s 后恢复保活
        _wsManager?.markConversationIdle('音频播放结束');
        logger.info('AI 播放结束（500ms 无新音频），进入尾音保护');
      }
    });
    
    // 播放音频
    AudioUtil.playOpusData(Uint8List.fromList(data));
  }

  /// 处理文本消息
  void _handleTextMessage(String message) {
    try {
      // 解析 JSON 消息
      final jsonData = Map<String, dynamic>.from(
        const JsonDecoder().convert(message),
      );

      final type = jsonData['type'] as String?;

      switch (type) {
        case 'tts':
          // 处理 TTS 消息
          final state = jsonData['state'] as String?;
          final text = jsonData['text'] as String?;
          // v6.11.9：tts start/sentence_start 都算会话进行中
          if (state == 'start' || state == 'sentence_start') {
            _wsManager?.markConversationActive('TTS $state');
          }

          if (state == 'sentence_start' && text != null && text.isNotEmpty) {
            // AI 开始说新的一句话，追加到当前消息
            _setTyping(false);
            // v3.1.0：MCP 工具标记过滤 + 待挂情绪 emoji（对齐网页版，xiaoleweb.md §2.4）
            final filtered = _stripMcpMarkers(text);
            if (filtered.isEmpty) {
              logger.info('句子仅含 MCP 标记，气泡不渲染: $text');
            } else if (_visionAux != null && !_visionAux!.isCompleted) {
              // v4.3.3 路径 C：识图等待中——服务器主动推送的文本即认作识图结果，
              // 交给竞速逻辑处理（终态气泡会展示它，故此处不重复追加气泡）
              logger.info('[C] 识图：服务器主动推送文本作为识图结果 ${_clip(filtered)}');
              _visionAux!.complete(filtered);
            } else {
              final decorated =
                  _pendingEmotion.isEmpty ? filtered : '${_pendingEmotion} $filtered';
              _pendingEmotion = '';
              // v6.11.17：同一轮回复的句子才合并；新一轮回复另起气泡
              _appendOrCreateChatMessage(MessageSender.ai, decorated,
                  merge: _aiMergeOpen);
              _aiMergeOpen = true;
            }
          } else if (state == 'end' || state == 'stop') {
            // v6.11.17：本轮终结——气泡合并窗口关闭（P2-1）
            _sttMergeOpen = false;
            _aiMergeOpen = false;
            // v6.11.9：TTS 结束 → 5s 后恢复保活
            _wsManager?.markConversationIdle('TTS $state');
            // v6.11.13：本轮结束 → 若还有超长文字的分段待发，立即续发下一段
            _flushTextSegmentsOnTurnEnd();
            // AI 说完了，标记播放结束
            // v3.0.0：双兼容——网页版实测服务器发的是 'stop'（部分上游发 'end'），
            // 只认其一会导致 _isAiPlaying 不复位 → 麦克风停发 → 「第二句听不见」
            _aiPlayingTimer?.cancel();
            if (_isAiPlaying) {
              setState(() {
                _isAiPlaying = false;
              });
              // v4.4.0：进入尾音保护（同上）
              _enterTailGuard();
              logger.info('TTS 结束($state)，AI 播放完成，进入尾音保护');
            }
          }
          break;

        case 'stt':
          // v6.11.9：服务端已开始识别/会话已开 → 保活暂停
          _wsManager?.markConversationActive('stt');
          // 处理语音识别结果 - 实时追加到最后一条用户消息
          final text = jsonData['text'] as String?;
          if (text != null && text.isNotEmpty) {
            logger.info('语音识别: $text');
            // v6.11.17：同一轮次的 stt 片段才合并；新轮次（发送前已关闭窗口）
            // 一律新建气泡，避免"现在几点了现在几点了hello"（P2-1）
            _appendOrCreateChatMessage(MessageSender.user, text,
                merge: _sttMergeOpen);
            _sttMergeOpen = true;
            _scrollToBottom();
          }
          break;

        case 'hello':
          // 🔥 服务器 hello 响应，提取 session_id
          final sessionId = jsonData['session_id'] as String?;
          if (sessionId != null && sessionId.isNotEmpty) {
            _sessionId = sessionId;
            logger.info('收到服务器 hello 响应，会话ID: $_sessionId');
          } else {
            logger.info('收到服务器 hello 响应（无 session_id）');
          }
          // v3.1.0：hello ACK → 执行「想打就打」的待办动作
          _runPendingAutoAction();
          break;

        case 'llm':
          // v6.11.9：AI 正在生成回复（未完成回复）→ 保活暂停
          _wsManager?.markConversationActive('llm');
          // v3.1.0：AI 情绪 → emoji 前缀（对齐网页版映射，xiaoleweb.md §2.4）
          // v4.2.0：同时触发全屏动图表情（申请书 6 号）
          final emotion = jsonData['emotion'] as String?;
          final em = {
            'happy': '😊',
            'laughing': '😆',
            'cool': '😎',
            'sad': '😢',
            'angry': '😠',
          }[emotion];
          if (em != null) {
            _showEmotionAnimation(em, emotion!);
            final last = _messages.isNotEmpty ? _messages.last : null;
            if (last != null &&
                last.sender == MessageSender.ai &&
                !last.content.startsWith(RegExp(r'[😊😆😎😢😠]'))) {
              setState(() {
                _messages[_messages.length - 1] = MessageModel(
                  id: last.id,
                  agentId: last.agentId,
                  type: last.type,
                  content: '$em ${last.content}',
                  sender: last.sender,
                  status: last.status,
                  timestamp: last.timestamp,
                );
              });
              ChatHistoryStore.save(widget.agentId, _messages);
            } else if (last == null || last.sender != MessageSender.ai) {
              // 情绪先于句子到达：暂存，随下一句 sentence_start 挂上
              _pendingEmotion = em;
            }
          }
          break;

        case 'mcp':
          // v3.0.0：MCP 设备端——响应服务器 initialize/tools/list/tools/call
          //（协议与工具效果见 xiaoleweb.md 第五章；hello 已声明 features.mcp）
          // v4.3.1：识图两段式——本设备主动发起的 tools/call 应答（带 id+result/error）
          // 必须最先拦截且不受 🧰 开关控制（识图与 mcptools 开关无关）。
          final mcpPayload = jsonData['payload'];
          // v4.3.2 埋点：mcp 帧全量摘要（含非应答帧），用于判断服务器到底回了什么
          logger.info('收到 mcp 帧：${_clip(jsonEncode(mcpPayload ?? {}))}');
          if (mcpPayload is Map) {
            final payloadMap = Map<String, dynamic>.from(mcpPayload);
            final rid = payloadMap['id'];
            final isCallAnswer = rid != null &&
                (payloadMap['result'] != null || payloadMap['error'] != null);
            if (isCallAnswer) {
              // v4.3.2 埋点：应答 id 与待决表比对，定位"超时/无反应"到底卡在哪
              logger.info('mcp 应答帧 id=$rid(${rid.runtimeType})'
                  ' 待决表=${_pendingMcpCalls.keys.toList()}');
              final pending = rid is int
                  ? _pendingMcpCalls.remove(rid)
                  : (rid is String
                      ? _pendingMcpCalls.remove(int.tryParse(rid))
                      : null);
              if (pending != null && !pending.isCompleted) {
                final result = payloadMap['result'];
                if (result is Map) {
                  String text = '';
                  final content = result['content'];
                  if (content is List && content.isNotEmpty) {
                    final first = content.first;
                    if (first is Map && first['text'] is String) {
                      text = first['text'] as String;
                    }
                  }
                  logger.info('mcp 应答 id=$rid 解析出描述 ${text.length} 字符');
                  pending.complete(
                      text.isEmpty ? '（服务器未返回图片描述）' : text);
                } else {
                  final err = payloadMap['error'];
                  final errMsg = err is Map
                      ? ((err['message'] as String?) ?? '未知错误')
                      : '未知错误';
                  logger.warning('mcp 应答 id=$rid 返回错误：$errMsg');
                  pending.completeError('识图失败：$errMsg');
                }
              } else {
                logger.warning('mcp 应答 id=$rid 未匹配任何待决调用'
                    '（待决表=${_pendingMcpCalls.keys.toList()}）');
              }
              break;
            }
            // v3.3.0：🧰 开关关 = 不应答服务器 MCP 请求（回到静默行为）
            if (!AppFeats.mcptools) {
              logger.info('MCP 请求被 🧰 开关忽略（开发者中心可开启）');
              break;
            }
            if (_mcpResponder != null) {
              // v3.1.0：从服务器 initialize 的 params.capabilities.vision 提取视觉识物接口
              if (payloadMap['method'] == 'initialize') {
                final params =
                    (payloadMap['params'] as Map?)?.cast<String, dynamic>() ?? {};
                final caps =
                    (params['capabilities'] as Map?)?.cast<String, dynamic>() ?? {};
                final vision = (caps['vision'] as Map?)?.cast<String, dynamic>();
                if (vision != null && vision['url'] != null) {
                  _visionUrl = vision['url'] as String?;
                  _visionToken = (vision['token'] as String?) ?? '';
                  logger.info('已获取视觉识物接口: $_visionUrl');
                } else {
                  // v4.3.2 埋点：服务器 initialize 没带 vision → 识物必然不可用
                  logger.warning(
                      '收到 MCP initialize，但 capabilities.vision 为空'
                      '（caps=${caps.keys.toList()}）——视觉识物不可用');
                }
              }
              _mcpResponder!.handlePayload(payloadMap);
            } else {
              logger.warning(
                  '收到 MCP 请求但响应器未就绪，已忽略（本条 AI 无法操控设备）');
            }
          }
          break;

        case 'alert':
          // v6.4.3：服务器的 alert 此前**完全没有被处理**（落到 default 只记一行日志），
          // 导致「超长文本被 detect 通道拒绝」这类关键提示在 UI 上完全不可见——
          // 用户以为消息发出去了，实际被服务器丢弃。此处显式呈现，让问题可感知。
          // v6.4.4：按身份分流——开发者看原文（排查用），普通用户看友好提示。
          final alertStatus = (jsonData['status'] ?? '').toString();
          final alertText = (jsonData['message'] ?? '').toString();
          logger.warning('服务端 alert：status=$alertStatus message=$alertText');
          if (alertText.isEmpty) break;
          if (AppFeats.get('rawServerAlert')) {
            // 开发者模式：原文可见（保持 v6.4.3 行为）
            _appendOrCreateChatMessage(
                MessageSender.system, '⚠️ 服务端提示：$alertText');
            if (alertStatus.toUpperCase() == 'ERROR') {
              _showError(alertText);
            }
          } else {
            // 普通用户模式：不暴露技术细节，改成能看懂的说明 + 弹窗
            final friendly = _friendlyAlertText(alertText);
            _appendOrCreateChatMessage(MessageSender.system, friendly);
            _showFriendlyAlertDialog(friendly);
          }
          break;

        default:
          logger.warning('未知消息类型: $type , 内容: $message');
      }
    } catch (e) {
      logger.severe('解析消息失败: $e');
    }
  }

  /// 处理音频数据发送（发送二进制音频数据）
  void _handleAudioSend(Uint8List audioData) {
    // 如果 AI 正在播放，则不发送音频数据（但录音继续）
    if (_isAiPlaying) {
      // logger.info('AI 正在播放，跳过发送音频数据'); // 注释掉，避免日志过多
      return;
    }

    // v4.4.0 尾音保护：AI 刚说完时，扬声器缓冲区里可能还在播最后几个字，
    // 此时上行的音频实为 AI 自己的尾音 → 会被服务器 ASR 当成"用户开口"导致自问自答。
    // 故保护期内丢弃音频，等扬声器余音衰减完毕。
    final guard = _resumeGuardUntil;
    if (guard != null) {
      if (DateTime.now().isBefore(guard)) return;
      _resumeGuardUntil = null;
      logger.info('[audio] 尾音保护结束，恢复上行麦克风数据');
    }

    // 通过 WebSocket 发送音频数据
    if (_wsManager != null && _isConnected) {
      try {
        _wsManager!.markConversationActive('上行麦克风音频'); // v6.11.9：用户正在说话
        _wsManager!.sendBinaryMessage(audioData);
        // logger.info('已发送音频数据: ${audioData.length} 字节'); // 注释掉，避免日志过多
      } catch (e) {
        logger.severe('发送音频失败: $e');
        _showError('发送音频失败: $e');
      }
    } else {
      // v6.11.10：说话前预连接——断线瞬间按下麦克风时，先把音频帧缓存（上限 40 帧≈2.4s），
      // 连上并发出 listen start 后回灌，避免"第一句话录丢"。
      if (!_isInVoiceCall && _preconnectAudio.length < 40) {
        _preconnectAudio.add(audioData);
        if (_preconnectAudio.length == 1) {
          logger.info('[PRECONNECT] 断线中开始缓存上行音频');
        }
      }
      // v3.1.0：想打就打——触发自动连接（连上后继续说话即正常上行）。
      // 通话中由 WS 管理器自身重连兜底，不走全链路重建（避免双连接）。
      if (!_isInVoiceCall && _connectionStatus != '正在连接...') {
        _ensureConnectedThen(() {}, '发送语音');
      }
    }
  }

  /// 处理音频停止（发送 listen stop 消息）
  void _handleAudioStop() {
    // v3.0.0：防 mode 交叉（xiaoleweb.md §2.4 铁律）——realtime 通话进行中
    // 不允许按键说话链路（auto）插入 start/stop，否则服务器 VAD 语义错乱
    if (_isInVoiceCall) {
      logger.info('通话进行中，忽略按键说话的 listen stop（防 mode 交叉）');
      return;
    }
    if (_wsManager == null || !_isConnected) {
      _preconnectAudio.clear(); // v6.11.10：松手即丢缓存，避免残留帧串到下一次说话
      return;
    }

    try {
      // 🔥 发送 listen stop 消息（按照协议）
      final listenStopMessage = {
        "session_id": _sessionId ?? "", // 使用从 hello 消息中获取的 session_id
        "type": "listen",
        "mode": "auto",
        "state": "stop",
      };

      _wsManager!.sendMessage(jsonEncode(listenStopMessage));
      logger.info('已发送 listen stop 消息: ${jsonEncode(listenStopMessage)}');
      // v6.11.12 核查结论：松手**不**解除会话标记——ASR/LLM 仍在服务端排队，
      // 若此处 markIdle，5s 后保活可能在"等待识别"窗口插入 stop，反而打断本轮。
      // 解除一律由 TTS stop/end 触发；纯静音无回复时由 60s 无活动兜底自动解除。
    } catch (e) {
      logger.severe('发送 listen stop 消息失败: $e');
    }
  }

  /// 处理音频开始（发送 listen start 消息）
  void _handleAudioStart() {
    // v3.0.0：防 mode 交叉（同 _handleAudioStop 注释）
    if (_isInVoiceCall) {
      logger.info('通话进行中，忽略按键说话的 listen start（防 mode 交叉）');
      return;
    }
    // v6.11.17：新的一轮说话开始，关闭上一轮气泡合并窗口（P2-1）
    _sttMergeOpen = false;
    _aiMergeOpen = false;
    // v6.11.12：**必须在 listen start 上行之前置位**。
    // 旧版靠 _handleAudioSend 的首帧音频才置位，"麦克风已开、置位未到"的
    // 几十~几百 ms 窗口里若撞上 45s 保活 tick，会把 listen stop 插到 start 之前/之后，
    // 服务端可能提前收束本轮识别（表现为"说话被打断"）。置位提前，宁可多停一档。
    _wsManager?.markConversationActive('开始说话');
    if (_wsManager == null || !_isConnected) {
      // v3.1.0：想打就打——未连接时自动连接；
      // v6.11.10：连上后自动重放本次 listen start，并回灌缓存音频，避免第一句话丢失
      _ensureConnectedThen(_handleAudioStart, '开始说话');
      return;
    }

    try {
      // 🔥 发送 listen start 消息（按照协议）
      final listenStartMessage = {
        "session_id": _sessionId ?? "", // 使用从 hello 消息中获取的 session_id
        "type": "listen",
        "state": "start",
        "mode": "auto", // 自动模式：自动识别说话
      };

      _wsManager!.sendMessage(jsonEncode(listenStartMessage));
      logger.info('已发送 listen start 消息: ${jsonEncode(listenStartMessage)}');
      _flushPreconnectAudio(); // v6.11.10：回灌预连接期间缓存的音频帧
    } catch (e) {
      logger.severe('发送 listen start 消息失败: $e');
      _showError('启动录音失败: $e');
    }
  }

  /// 处理持续监听开始（发送 realtime 模式的 listen start 消息）
  void _handleContinuousListenStart() {
    if (_wsManager == null || !_isConnected) {
      _showError('未连接到服务器');
      return;
    }

    try {
      // 🔥 发送 realtime 模式的 listen start 消息
      final listenStartMessage = {
        "session_id": _sessionId ?? "",
        "type": "listen",
        "state": "start",
        "mode": "realtime", // 实时模式：持续监听
      };

      _wsManager!.sendMessage(jsonEncode(listenStartMessage));
      logger.info('已发送持续监听 start 消息: ${jsonEncode(listenStartMessage)}');
      ToastUtil.show('开始持续监听');
    } catch (e) {
      logger.severe('发送持续监听 start 消息失败: $e');
      _showError('启动持续监听失败: $e');
    }
  }

  /// 处理持续监听停止（发送 realtime 模式的 listen stop 消息）
  void _handleContinuousListenStop() {
    if (_wsManager == null || !_isConnected) {
      return;
    }

    try {
      // 🔥 发送 realtime 模式的 listen stop 消息
      final listenStopMessage = {
        "session_id": _sessionId ?? "",
        "type": "listen",
        "state": "stop",
        "mode": "realtime", // 实时模式：持续监听
      };

      _wsManager!.sendMessage(jsonEncode(listenStopMessage));
      logger.info('已发送持续监听 stop 消息: ${jsonEncode(listenStopMessage)}');
      ToastUtil.show('停止持续监听');
    } catch (e) {
      logger.severe('发送持续监听 stop 消息失败: $e');
    }
  }

  /// 显示/隐藏 AI 输入指示器（仅触发实际变化时刷新）
  void _setTyping(bool typing) {
    if (_isAiTyping != typing && mounted) {
      setState(() => _isAiTyping = typing);
    }
  }

  /// 开始语音通话（复用现有连续监听 + 音频链路，不改通信层）
  void _startVoiceCall() {
    if (_isInVoiceCall) return;
    _liftVoiceMuteWindow(); // v6.8.1（B 项）：新通话开启，解除挂断静默窗口
    if (!_isConnected) {
      // v3.1.0：想打就打——未连接时自动连接，hello ACK 后自动进通话
      _ensureConnectedThen(_startVoiceCall, '进入通话');
      return;
    }
    // v6.0.0：进入通话 → 系统沉浸式（隐藏状态栏/导航栏），配合隐藏 AppBar 实现全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isInVoiceCall = true;
      _showVoiceCallOverlay = true;
      _micMuted = false;
      _isSpeakerOn = false;
      _callStatus = '等待连接...';
      _voiceCallStart = DateTime.now();
      _voiceCallDuration = '00:00';
    });
    _voiceCallTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateVoiceCallDuration(),
    );
    // 与持续监听同链路：先启动麦克风采集，再订阅音频流转发，最后发送 realtime listen
    if (!AudioUtil.isRecording) {
      AudioUtil.startRecording(enableAEC: true);
    }
    // 关键修复：订阅麦克风音频流并逐帧转发到 WebSocket（v1.1.2 漏了这步导致服务器收不到声音）
    _callAudioSubscription = AudioUtil.audioStream.listen(
      (audioData) {
        if (!_micMuted) _handleAudioSend(audioData); // 静音时不发送
      },
      onError: (e) {
        logger.severe('通话音频流错误: $e');
      },
    );
    // v4.4.0：barge-in 已移除，不再订阅麦克风能量流
    _bargeinSub?.cancel();
    _bargeinSub = null;
    _handleContinuousListenStart();
    if (mounted) setState(() => _callStatus = '正在听你说');
  }

  void _updateVoiceCallDuration() {
    if (_voiceCallStart == null) return;
    final elapsed = DateTime.now().difference(_voiceCallStart!);
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted) setState(() => _voiceCallDuration = '$m:$s');
  }

  /// 结束语音通话
  void _endVoiceCall() {
    // v6.0.0：退出通话 → 恢复系统 UI（与进入时的沉浸式配对）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _voiceCallTimer?.cancel();
    _voiceCallTimer = null;
    // v4.4.0：barge-in 已移除（保留订阅清理以防残留）
    _bargeinSub?.cancel();
    _bargeinSub = null;
    // 取消音频流订阅（与持续监听同链路，只调用不改 lib/core）
    _callAudioSubscription?.cancel();
    _callAudioSubscription = null;
    // 停止麦克风采集（与持续监听同链路，只调用不改 lib/core）
    if (AudioUtil.isRecording) {
      AudioUtil.stopRecording();
    }
    // v6.8.1（B 项）：挂断即静音——立即释放音频播放引擎，
    // 避免已进入播放缓冲的 PCM 继续外放（根因①）。
    AudioUtil.stopPlaying();
    // v6.8.1（B 项）：挂断即通知——无条件向服务器发 abort 停止合成。
    // 旧逻辑被 _isAiPlaying 门控，挂断瞬间该标志常已为 false，导致指令发不出，
    // 服务器后续仍推 TTS ⇒ 挂断后"补一句"（根因②）。改为只要连着就发。
    if (_wsManager != null && _isConnected) {
      _wsManager!.sendMessage(jsonEncode({'type': 'abort'}));
      logger.info('已发送 abort（挂断即通知服务器停止 TTS 合成）');
      _isAiPlaying = false;
      _aiPlayingTimer?.cancel();
    }
    // v6.8.1（B 项）：记录挂断时刻，开启"迟到音频帧丢弃"静默窗口（根因④）。
    _voiceHangupAt = DateTime.now();
    // v6.11.9：挂断 = 会话结束 → 5s 后恢复保活
    _wsManager?.markConversationIdle('挂断');
    _handleContinuousListenStop(); // 复用现有停止逻辑
    if (mounted) {
      setState(() {
        _isInVoiceCall = false;
        _showVoiceCallOverlay = false;
        _micMuted = false;
        _isSpeakerOn = false;
        _callStatus = '等待连接...';
        _voiceCallDuration = '00:00';
        _voiceCallStart = null;
      });
    }
  }

  void _toggleMic() {
    if (mounted) setState(() => _micMuted = !_micMuted);
    // 静音 = 停止麦克风采集；取消静音 = 重新采集
    if (_micMuted) {
      if (AudioUtil.isRecording) AudioUtil.stopRecording();
    } else {
      if (!AudioUtil.isRecording) AudioUtil.startRecording(enableAEC: true);
    }
  }

  void _toggleSpeaker() {
    // 注意：当前 AudioUtil 未暴露扬声道路由 API，此处仅切换 UI 状态（占位）。
    // 真正的听筒/扬声器切换需改动 lib/core（红线），本轮不做。
    if (mounted) setState(() => _isSpeakerOn = !_isSpeakerOn);
    ToastUtil.show(_isSpeakerOn ? '已切换至扬声器' : '已切换至听筒');
  }

  /// 通话中顶部小条（最小化后点击可恢复）
  /// v6.0.0：收起通话全屏层 —— 同时恢复系统 UI，避免沉浸式状态残留
  void _collapseVoiceCallOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _showVoiceCallOverlay = false);
  }

  /// v6.0.0：展开 / 重新展开通话全屏层 —— 每次都必须重入系统沉浸式
  /// （收起时已恢复 edgeToEdge，若展开时只 setState 而不重设沉浸式，会丢失全屏效果）
  void _expandVoiceCallOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _showVoiceCallOverlay = true);
  }

  Widget _buildVoiceCallBanner() {
    final p = XlPalette.of(context);
    return Material(
      color: p.brandDeep,
      child: InkWell(
        onTap: _expandVoiceCallOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.call, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text('通话中', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Text(
                _voiceCallDuration,
                style: XlType.meta.copyWith(color: Colors.white),
              ),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  /// 语音通话全屏覆盖层（DESIGN §10）
  /// 径向渐变 / 头像 96-24 / 脉冲圈 128·152 / 波形 30 根 / 控制 64·72·64
  Widget _buildVoiceCallOverlay() {
    return Material(
      color: Colors.black,
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.24),
            radius: 1.2,
            colors: [
              XlColor.callBgTop,
              XlColor.callBgMid,
              XlColor.callBgBottom,
            ],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: XlDims.navHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _collapseVoiceCallOverlay,
                        tooltip: '收起',
                      ),
                    ),
                    Text(
                      '语音通话',
                      style: XlType.navTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(
                          Icons.more_horiz,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () => ToastUtil.show('更多选项'),
                        tooltip: '更多',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: XlDims.callTopTitleGap),
              Text(
                'AI 语音 · 任务可随时打断',
                style: XlType.meta.copyWith(color: XlColor.callTextDim),
              ),
              const Spacer(flex: 2),
              Stack(
                alignment: Alignment.center,
                children: [
                  const _CallPulseRings(),
                  AgentAvatar(
                    agentId: widget.agentId,
                    name: _agentName,
                    size: XlDims.callAvatar,
                    radius: XlDims.avatarCall,
                    showOnlineDot: false,
                  ),
                ],
              ),
              const SizedBox(height: XlDims.xl),
              Text(
                _agentName,
                style: XlType.callName.copyWith(color: Colors.white),
              ),
              const SizedBox(height: XlDims.s),
              Text(
                _callStatus,
                style: XlType.callStatus.copyWith(
                  color: XlColor.callTextDim,
                ),
              ),
              const SizedBox(height: XlDims.xs),
              Text(
                _voiceCallDuration,
                style: XlType.callTimer.copyWith(color: Colors.white),
              ),
              const SizedBox(height: XlDims.xl),
              XlVoiceWave(
                amplitudeStream: AudioUtil.amplitudeStream,
                active: _isConnected && !_micMuted,
                width: XlDims.callWaveW,
                height: XlDims.callWaveH,
                maxBarHeight: XlDims.callWaveMaxH,
                barCount: XlMotion.callWaveBarCount,
                color: Colors.white.withOpacity(0.72),
                highlightColor: XlColor.brand,
                highlightBars: XlDims.callHighlightBars,
              ),
              const SizedBox(height: XlDims.l),
              // 转写条：6pt 绿点 + 13/19 正文（DESIGN §8.7）
              Container(
                width: XlDims.callHintW,
                padding: const EdgeInsets.symmetric(
                  horizontal: XlDims.voiceOverlayPad,
                  vertical: XlDims.callTranscriptPadV,
                ),
                decoration: BoxDecoration(
                  color: XlColor.callTranscriptBg,
                  borderRadius: BorderRadius.circular(XlDims.rL),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: XlDims.callTranscriptDot,
                      height: XlDims.callTranscriptDot,
                      decoration: const BoxDecoration(
                        color: XlColor.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: XlDims.s),
                    Flexible(
                      child: Text(
                        '语音通话中，请直接说话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: XlType.callCaption.copyWith(
                          color: XlColor.callTextSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: XlDims.callHintBottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _voiceCallCircleButton(
                          icon: _micMuted ? Icons.mic_off : Icons.mic,
                          label: _micMuted ? '已静音' : '静音',
                          circleColor: _micMuted
                              ? XlColor.callControlMuted
                              : XlColor.callControl,
                          iconColor: _micMuted
                              ? Colors.white
                              : XlColor.callControlIcon,
                          onTap: _toggleMic,
                        ),
                        const SizedBox(width: XlDims.callControlsGap),
                        _voiceCallCircleButton(
                          icon: Icons.call_end,
                          label: '挂断',
                          size: XlDims.callHangup,
                          circleColor: XlColor.danger,
                          iconColor: Colors.white,
                          onTap: _endVoiceCall,
                        ),
                        const SizedBox(width: XlDims.callControlsGap),
                        _voiceCallCircleButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                          label: _isSpeakerOn ? '免提' : '听筒',
                          circleColor: _isSpeakerOn
                              ? XlColor.brand
                              : XlColor.callControl,
                          iconColor: _isSpeakerOn
                              ? Colors.white
                              : XlColor.callControlIcon,
                          onTap: _toggleSpeaker,
                        ),
                      ],
                    ),
                    const SizedBox(height: XlDims.callHintGap),
                    Text(
                      '随时说话即可打断小乐',
                      style: XlType.caption.copyWith(
                        color: XlColor.callTextDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceCallCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = XlDims.callControl,
    Color circleColor = XlColor.callControl,
    Color iconColor = XlColor.callControlIcon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size >= 72 ? 30 : 26),
          ),
        ),
        const SizedBox(height: XlDims.s),
        Text(
          label,
          style: XlType.caption.copyWith(color: XlColor.callTextDim),
        ),
      ],
    );
  }
}

/// 通话头像外圈脉冲（128 / 152，2400ms，错峰 400ms；reduce motion 时静止）
class _CallPulseRings extends StatefulWidget {
  const _CallPulseRings();

  @override
  State<_CallPulseRings> createState() => _CallPulseRingsState();
}

class _CallPulseRingsState extends State<_CallPulseRings>
    with TickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _b = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _a.stop();
      _b.stop();
      return;
    }
    if (!_a.isAnimating) {
      _a.repeat();
    }
    if (!_b.isAnimating) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_b.isAnimating) _b.repeat();
      });
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return const SizedBox.shrink();
    return SizedBox(
      width: XlDims.callPulseOuter,
      height: XlDims.callPulseOuter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(_a, XlDims.callPulseInner, endScale: 1.18, baseOpacity: 0.28),
          _ring(_b, XlDims.callPulseOuter, endScale: 1.34, baseOpacity: 0.14),
        ],
      ),
    );
  }

  Widget _ring(
    AnimationController controller,
    double size, {
    required double endScale,
    required double baseOpacity,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        return Opacity(
          opacity: (baseOpacity * (1 - t)).clamp(0.0, 1.0).toDouble(),
          child: Container(
            width: size * (1 + (endScale - 1) * t),
            height: size * (1 + (endScale - 1) * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: XlColor.brand, width: 1),
            ),
          ),
        );
      },
    );
  }
}

/// v6.11.14：单个文本分段的双口径上限（码点数 / UTF-8 字节数）
class _TextLimits {
  const _TextLimits(this.maxRunes, this.maxBytes);
  final int maxRunes;
  final int maxBytes;
}
