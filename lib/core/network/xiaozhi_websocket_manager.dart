import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:logging/logging.dart';
// 尝试导入io.dart,但在web平台会抛出异常
import 'package:web_socket_channel/io.dart'
    if (dart.library.html) 'package:web_socket_channel/html.dart';

import '../service/keep_alive_service.dart';

/// 小智WebSocket事件类型
enum XiaozhiEventType { connected, disconnected, message, error, binaryMessage }

/// v6.11.9：保活方案收敛为二值。
/// 真机实验（6.11.8+60，2026-11-04 18:20–18:24）结论：
/// - hello/abort 与对照组同量级（65–68s 被 1005 回收）→ 无效，已剔除；
/// - detect 能撑过 3 分钟，但每个 tick 都会触发服务端一轮 stt→llm→tts
///   （实测 8 tick = 8 次 TTS 播放）→ 仅作诊断，默认隐藏；
/// - **v6.11.11 定案：`listen{state:"stop"}` 每 45s 一次作为生产默认保活**
///   （8 tick / 6 分钟零副作用、零重连，实测数据见 docs/ws-idle-reclaim-evidence.md）。
enum WsProbeMode {
  /// 关闭：不发任何保活消息（仍保留 WS ping + 无感重连兜底）
  off,

  /// **v6.11.11 生产默认**：每 45s 发 `listen{state:"stop"}`。
  /// 2026-11-04 真机实测：6 分钟 8 tick，零 stt / 零 tts / 零 llm /
  /// 零下行音频 / 零 AudioTrack start，且零重连（1005 回收被完全跨过）。
  auto,

  /// 诊断用（默认不在开发者中心展示）：
  /// `listen{state:"detect"}` 同样能保活，但每个 tick 会触发一轮 TTS 外放
  /// （实测 8 tick = 8 轮），属"保活反而制造噪音"，绝不能作为生产默认。
  detect,
}

/// 小智WebSocket事件
class XiaozhiEvent {
  final XiaozhiEventType type;
  final dynamic data;

  XiaozhiEvent({required this.type, this.data});
}

/// 小智WebSocket监听器接口
typedef XiaozhiWebSocketListener = void Function(XiaozhiEvent event);

/// 小智WebSocket管理器
class XiaozhiWebSocketManager {
  final Logger logger = Logger('XiaozhiWebSocketManager');

  // 81 重连策略：固定阶梯退避 2s→5s→15s→30s→60s 封顶。
  // 前台最多 12 次；后台（息屏/切后台）最多 3 次即停手，等亮屏后由 onReturnToForeground 秒回。
  // 1005=服务器静默回收(正常)静默重连；432x=身份校验失败(重连无效)停止；
  // 用户主动断开(_manualClosed)永不重连。
  static const List<int> RECONNECT_DELAYS_MS = <int>[
    2000,
    5000,
    15000,
    30000,
    60000,
  ];
  static const int RECONNECT_MAX_TRIES = 12;

  /// 81：后台连续失败上限。ColorOS 息屏下宁可断开，也不许 1005/1006 风暴。
  static const int RECONNECT_BG_MAX_TRIES = 3;

  /// v6.11.6：WS 保活间隔。云端会把空闲长连接约 60s 回收（真机日志实证：
  /// 16:07:53.809 连上 → 16:08:54.071 code=1006，时长 60.26s），
  /// 25s 发一次 ping 可稳定保活。
  static const Duration PING_INTERVAL = Duration(seconds: 25);

  /// v6.11.6：看门狗检查间隔（Dart 定时器，不依赖 didChangeAppLifecycleState）
  static const Duration WATCHDOG_INTERVAL = Duration(seconds: 20);

  /// v6.11.9：detect 保活默认间隔。实测 30s 可保活；45s 仍留出 15–25s 余量，
  /// 同时把"误触发 TTS"的频率降到最低（每 45s 最多一次）。
  static const Duration PROBE_DETECT_INTERVAL = Duration(seconds: 45);

  /// v6.11.9：对话结束后延迟恢复保活，避开尾音保护 / 迟到音频帧阶段。
  static const Duration PROBE_RESUME_DELAY = Duration(seconds: 5);

  /// v6.11.9：会话标记的兜底超时——若上层漏发"对话结束"，超过该时长无任何
  /// 收发活动即自动解除标记，避免保活被永久暂停（最坏退化为 3 分钟一次）。
  static const Duration CONVERSATION_STALE = Duration(seconds: 60);

  WebSocketChannel? _channel;
  String? _serverUrl;
  String? _deviceId;
  String? _clientId; // v1.1.6: 真实 ClientID（激活注册用的 UUID），可选
  String? _token;
  bool _enableToken;

  final List<XiaozhiWebSocketListener> _listeners = [];
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  StreamSubscription? _streamSubscription;
  int _reconnectAttempts = 0;

  // ===== v6.11.17：握手闸门（P0-2 根因修复）=====
  // socket 打开 != 连接可用。只有收到服务器 hello ACK 才算握手完成；
  // 在此之前对外 isConnected=false，页面不会再"成功即断"。
  bool _handshakeDone = false;
  bool _pendingIsReconnect = false;
  Timer? _helloTimer;
  Timer? _handshakeTimer;

  /// hello ACK 等待上限。超时即判定本次建连失败，主动关闭走重连。
  static const Duration HANDSHAKE_TIMEOUT = Duration(seconds: 8);

  // ===== v6.11.10：重连频率统计（回答"1 小时 50 次重连是否过频"）=====
  int _reconnectTotal = 0;        // 累计发起的重连次数
  int _reconnectSuccess = 0;      // 累计成功次数
  DateTime? _lastReconnectAt;     // 上次发起重连的时刻
  DateTime? _lastDisconnectAt;    // 上次断开的时刻（用于算间隔）
  final List<int> _reconnectGapsSec = <int>[]; // 相邻两次重连的间隔（秒）
  final List<int> _closeCodes = <int>[];       // 最近收到的关闭码（含 null 记为 -1）
  bool _manualClosed = false;

  // ===== v6.11.24（81）：前后台策略 =====
  // 81 产品定义：息屏/后台不再要求 tick、不再要求 45s 心跳。
  // 后台只做"断开等亮屏"——不跑业务保活探针、不跑看门狗、重连最多 3 次即停。
  bool _appForeground = true;
  bool get appForeground => _appForeground;

  /// v4.3.3：最近一次收到服务器消息的时间（供上层判断连接是否已僵死）
  DateTime? _lastRecvAt;

  // ===== v6.11.8：心跳实验（v6.11.11 起 auto 为生产默认）=====
  final WsProbeMode _probeMode;
  final Duration _probeInterval;
  Timer? _probeTimer;
  int _probeSeq = 0; // tick 累计次数（79 轮起跨重连单调递增，供"连续增长"取证）
  int _probeSent = 0; // 本段实际发出的保活消息数
  int _probeRecv = 0;
  int _segTicks = 0; // 本段 tick 次数（用于"跳过"统计）
  DateTime? _probeStartAt;
  DateTime? _lastUplinkAt; // 上次保活上行的时刻（用于日志"距上次上行"）
  DateTime? _lastTickAt; // 上一次 tick 时刻（原生唤醒据此判"是否停摆"）

  /// 日志前缀：生产保活用 [KEEPALIVE]，诊断 detect 用 [PROBE]
  String get _tag => _probeMode == WsProbeMode.auto ? 'KEEPALIVE' : 'PROBE';

  // ===== v6.11.9：会话感知（保活只在"空闲"时发）=====
  /// 是否有进行中的会话（用户上行 / listen start / 未完成回复 / TTS 播放）
  bool _conversationActive = false;
  DateTime? _conversationEndAt;
  DateTime? _lastActivityAt;

  /// v6.11.13：会话标记的独立过期定时器。
  /// 旧实现只在 tick 时刻检查 60s 空闲，最坏要等下一个 tick（+45s），
  /// 慢于云端 60–70s 回收线，导致云端先断开（1005 → 重连）。
  Timer? _conversationStaleTimer;

  // ===== v6.11.9：下行帧构成统计（证伪/证实"detect 是否制造噪音"）=====
  int _probeDownText = 0;
  int _probeDownBinary = 0;
  final Map<String, int> _probeTypes = {};

  /// 最近一次收到服务器消息的时间（null = 本次连接内尚未收到任何消息）
  DateTime? get lastReceivedAt => _lastRecvAt;

  /// 距最近一次收到服务器消息的秒数（从未收到返回 null）
  int? get silentSeconds {
    final t = _lastRecvAt;
    if (t == null) return null;
    return DateTime.now().difference(t).inSeconds;
  }

  /// 距最近一次保活上行的秒数（从未上行返回 null）。
  /// 79 轮：回前台判僵死必须同时看上行——保活发 `listen:stop` 服务端不回包，
  /// 只凭下行静默会把健康连接误杀（78 真机每次回前台都误判"连接僵死"并重建）。
  int? get uplinkSilentSeconds {
    final t = _lastUplinkAt;
    if (t == null) return null;
    return DateTime.now().difference(t).inSeconds;
  }

  /// 最近一次服务端关闭码（null = 本段还没断过），回前台日志用它区分"真断"与"误杀"
  int? get lastCloseCode => _closeCodes.isEmpty ? null : _closeCodes.last;

  /// 构造函数
  /// [clientId] 真实设备 ClientID（UUID）。官方协议中 client-id 头应传该值；
  /// 不传时保持旧行为（client-id = deviceId），完全向后兼容。
  XiaozhiWebSocketManager({
    required String deviceId,
    bool enableToken = false,
    String? wsProtocol,
    String? clientId,
    WsProbeMode probeMode = WsProbeMode.off,
    Duration probeInterval = PROBE_DETECT_INTERVAL,
  }) : _deviceId = deviceId,
       _clientId = clientId,
       _enableToken = enableToken,
       _probeMode = probeMode,
       _probeInterval = probeInterval;

  /// 添加事件监听器
  void addListener(XiaozhiWebSocketListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiWebSocketListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiEvent event) {
    for (var listener in _listeners) {
      listener(event);
    }
  }

  /// 连接到WebSocket服务器
  /// [isReconnect] 自动重连路径传 true——保留退避计数，仅用户主动连接时清零
  Future<void> connect(String url, String token, {bool isReconnect = false}) async {
    if (url.isEmpty) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: "WebSocket地址不能为空"),
      );
      return;
    }

    // 保存连接参数
    _serverUrl = url;
    _token = token;

    // 如果已连接，先断开
    if (_channel != null) {
      await disconnect();
    }

    // v3.0.0：新连接重置退避与手动关闭标志（必须在内部 disconnect 之后；
    // 重连路径不清零计数，否则退避失效变无限 1s 轰炸）
    _manualClosed = false;
    if (!isReconnect) _reconnectAttempts = 0;

    // v6.11.17：新 socket = 新握手。清掉上一条 socket 遗留的 hello/超时定时器，
    // 保证"一条 socket 只发一次 hello"，也不把旧 socket 的 ACK 算到新连接上。
    _helloTimer?.cancel();
    _helloTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeDone = false;
    _pendingIsReconnect = isReconnect;

    try {
      // 创建WebSocket连接
      Uri uri = Uri.parse(url);

      logger.info('正在连接 $url');
      logger.info('设备ID: $_deviceId');
      logger.info('Token启用: $_enableToken');

      if (_enableToken) {
        logger.info('使用Token: $token');
      }

      // 尝试使用headers (这在非Web平台上有效)
      try {
        // 创建headers
        Map<String, dynamic> headers = {
          'device-id': _deviceId ?? '',
          // v1.1.6: 优先发真实 ClientID（与激活注册一致）；未传则保持旧行为
          'client-id': (_clientId != null && _clientId!.isNotEmpty)
              ? _clientId!
              : (_deviceId ?? ''),
          'protocol-version': '1',
        };

        // 添加Authorization头，参考Java实现
        if (_enableToken && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
          logger.info('添加Authorization头: Bearer $token');
        } else {
          headers['Authorization'] = 'Bearer test-token';
          logger.info('添加默认Authorization头: Bearer test-token');
        }

        // 使用IOWebSocketChannel并传递headers
        // v6.11.6：加 pingInterval 保活，避免空闲约 60s 被云端回收（1006/1005）
        _channel = IOWebSocketChannel.connect(uri,
            headers: headers, pingInterval: PING_INTERVAL);

        logger.info('使用headers方式连接WebSocket成功');
      } catch (e) {
        // 如果不支持IOWebSocketChannel（web平台），则回退到使用基本连接
        logger.warning('不支持使用headers方式，回退到基本连接: $e');

        // 创建基本连接
        _channel = WebSocketChannel.connect(uri);

        // 在连接成功后作为第一条消息发送认证信息
        Timer(Duration(milliseconds: 100), () {
          if (_channel != null && isConnected) {
            // 发送认证信息作为第一条消息
            String authMessage =
                'Authorization: Bearer ${_enableToken && token.isNotEmpty ? token : "test-token"}';
            _channel!.sink.add(authMessage);
            logger.info('发送认证消息: $authMessage');

            // 发送设备ID信息
            String deviceIdMessage = 'Device-ID: $_deviceId';
            _channel!.sink.add(deviceIdMessage);
            logger.info('发送设备ID消息: $deviceIdMessage');
          }
        });
      }

      // 监听WebSocket事件
      _streamSubscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: _onError,
        cancelOnError: false,
      );

      // v6.11.17：这里**不再** dispatch(connected)。socket 打开只代表 TCP/WS 建立，
      // 服务器 hello ACK 才是会话可用（P0-2）。成功事件与 [RECONNECT] 成功日志
      // 统一在 _completeHandshake() 里打。
      //
      // 握手超时闸门：8s 内没有 hello ACK 就主动关闭，交给 onDone 走重连，
      // 避免"socket 还开着、但其实已经废了"的僵尸连接。
      _handshakeTimer = Timer(HANDSHAKE_TIMEOUT, () {
        if (_handshakeDone) return;
        logger.warning('[HANDSHAKE] ${HANDSHAKE_TIMEOUT.inSeconds}s 未收到服务器 hello，'
            '判定建连失败，主动关闭走重连');
        KeepAliveCoordinator.instance.onConnectionChanged(false);
        _channel?.sink.close(status.goingAway);
      });

      // 每条 socket 只发一次 hello（定时器句柄可取消，旧实现是匿名 Timer，
      // 断连后仍会触发，可能把 hello 发到新 socket 上）
      _helloTimer?.cancel();
      _helloTimer = Timer(Duration(milliseconds: 200), () {
        _sendHelloMessage();
      });

      logger.info('socket 已建立 $uri（等待服务器 hello ACK 才算连接成功）');
      // v6.11.6：连接建立即启动看门狗（独立 Dart Timer，不需要生命周期回调）
      _startWatchdog();
      // v6.11.8：按实验配置启动业务保活探针（off/ping 时只打日志，不发业务消息）
      _startProbe();
    } catch (e) {
      logger.severe('连接失败: $e');
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: "创建WebSocket失败: $e"),
      );
    }
  }

  /// 断开WebSocket连接
  /// [source] v4.3.3 新增：断开来源标记（dispose / user_button / reconnect / …），
  /// 仅用于日志区分"App 主动断开"与"服务器断开"，不影响任何行为。
  Future<void> disconnect({String source = 'unknown'}) async {
    // v3.0.0：标记用户主动断开——之后任何 onDone 都不自动重连
    _manualClosed = true;
    // v6.11.21（78 轮）：主动断开同样摘掉保活信号，避免服务常驻
    KeepAliveCoordinator.instance.onConnectionChanged(false);

    // 取消重连
    _reconnectTimer?.cancel();
    _isReconnecting = false;

    // v6.11.6：主动断开时停掉看门狗，避免它把用户手动断开又连回去
    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    // v6.11.8：主动断开同时停掉心跳探针
    _stopProbe('App 主动断开');

    // v6.11.17：握手闸门一起复位，避免旧 socket 的 hello/超时定时器打到新连接上
    _helloTimer?.cancel();
    _helloTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeDone = false;
    _pendingIsReconnect = false;

    // 取消订阅
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    // 关闭连接
    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
      // v4.3.3：标注断开来源。若日志出现本行 = App 主动断开；
      // 服务器断开则走 _onDisconnected（带 code/reason 与 kind=服务器）
      logger.info('连接已断开（App 主动断开 source=$source）');
    }
  }

  /// 发送Hello消息（socket 已关就丢弃，绝不把 hello 发到新旧错位的连接上）
  void _sendHelloMessage() {
    if (!isSocketOpen) {
      logger.warning('hello 未发送：socket 已关闭');
      return;
    }
    sendMessage(jsonEncode(_helloPayload()));
  }

  /// v6.11.17：收到服务器 hello ACK → 本次连接才算"成功"。
  /// 这里才 dispatch(connected)/打 [RECONNECT] 成功，页面 `_isConnected`
  /// 也才会置真，彻底消除"成功 50ms 即断"的误报成功。
  void _completeHandshake() {
    if (_handshakeDone) return;
    _handshakeDone = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final opened = _probeStartAt;
    final costMs = opened == null
        ? '-'
        : '${DateTime.now().difference(opened).inMilliseconds}ms';
    logger.info('[HANDSHAKE] 收到服务器 hello ACK，握手完成（socket→ACK $costMs）');
    // 81：握手成功即健康，退避计数归零，后续再断从 2s 档重新开始
    _reconnectAttempts = 0;
    if (_pendingIsReconnect) {
      _reconnectSuccess++;
      final started = _lastReconnectAt;
      final cost = started == null
          ? '-'
          : '${DateTime.now().difference(started).inSeconds}s';
      logger.info('[RECONNECT] 成功 #$_reconnectSuccess/$_reconnectTotal '
          '用时=$cost（以 hello ACK 为准）');
      _pendingIsReconnect = false;
    }
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.connected, data: null),
    );
    // v6.11.21（78 轮）：真正连接成功的唯一判据也喂给保活协调器。
    // 旧实现只挂在 xiaozhi_service.dart 的 onConnectionChanged，聊天页走的是
    // 本管理器，导致 _connected 恒 false、前台服务从未起过。
    KeepAliveCoordinator.instance.onConnectionChanged(true);
  }

  /// v6.11.8：hello 载荷（正常握手与心跳实验共用，含 device-id/版本/特性/音频参数）
  Map<String, dynamic> _helloPayload() => {
        "type": "hello",
        "version": 1,
        "device_id": _deviceId ?? '',
        "features": {"mcp": true},
        "transport": "websocket",
        "audio_params": {
          "format": "opus",
          "sample_rate": 16000,
          "channels": 1,
          "frame_duration": 60,
        },
      };

  // ===================== v6.11.8/6.11.9：心跳探针 =====================

  int get _probeElapsedSec => _probeStartAt == null
      ? 0
      : DateTime.now().difference(_probeStartAt!).inSeconds;

  /// v6.11.9：上层（聊天页）标记"进入会话"。
  /// 触发点：发送文字 / 上行麦克风音频 / 收到 stt|llm|tts start / 拨通语音通话。
  /// 进入会话后保活立即暂停，绝不在对话中间插 detect。
  void markConversationActive(String why) {
    _conversationActive = true;
    _conversationEndAt = null;
    _lastActivityAt = DateTime.now();
    // v6.11.13：首次进入会话时挂独立过期定时器；后续续约不重建（避免语音路径
    // 每帧 16 次 cancel/new）。到期时再按"最后一次活动的剩余时间"续约。
    _conversationStaleTimer ??=
        Timer(CONVERSATION_STALE, _expireConversationIfStale);
    if (_probeMode != WsProbeMode.off) {
      logger.info('[$_tag] 进入会话，保活暂停（$why）');
    }
  }

  /// v6.11.9：上层标记"会话结束"（TTS stop/end、挂断、音频播放结束）。
  /// 5s 后恢复保活，留给尾音保护与迟到音频帧。
  void markConversationIdle(String why) {
    if (!_conversationActive) return;
    _conversationActive = false;
    _conversationEndAt = DateTime.now();
    _conversationStaleTimer?.cancel();
    _conversationStaleTimer = null;
    if (_probeMode != WsProbeMode.off) {
      logger.info('[$_tag] 会话结束，${PROBE_RESUME_DELAY.inSeconds}s 后恢复保活（$why）');
    }
  }

  /// 是否处于会话中（供调试页展示）
  bool get conversationActive => _conversationActive;

  /// v6.11.13：会话标记的独立过期出口。
  /// 60s 内没有任何收发活动即解除；若期间有活动则按剩余时间续约。
  /// 解除时立刻补发一帧保活，把"最长无上行间隔"重新压回 60s 附近，
  /// 保证解除动作本身早于云端 60–70s 的回收线（不再依赖 tick 的 45s 节拍）。
  void _expireConversationIfStale() {
    if (!_conversationActive) {
      _conversationStaleTimer = null;
      return;
    }
    final last = _lastActivityAt;
    final idle =
        last == null ? CONVERSATION_STALE : DateTime.now().difference(last);
    if (idle < CONVERSATION_STALE) {
      // 仍有活动：按剩余时间续约，保证"最坏 60s"不被活动刷新拖成无限
      _conversationStaleTimer?.cancel();
      _conversationStaleTimer = Timer(
        CONVERSATION_STALE - idle,
        _expireConversationIfStale,
      );
      return;
    }
    _conversationActive = false;
    _conversationEndAt = DateTime.now();
    logger.warning('[$_tag] 会话标记过期（独立定时器：${idle.inSeconds}s 无收发活动），恢复保活');
    if (_probeMode == WsProbeMode.auto && isConnected && !_manualClosed) {
      final now = DateTime.now();
      final gap = _lastUplinkAt == null
          ? '首次'
          : '${now.difference(_lastUplinkAt!).inSeconds}s';
      for (final payload in _probePayloads()) {
        sendMessage(payload);
      }
      _lastUplinkAt = now;
      logger.info('[$_tag] 会话标记过期 → 立即补发保活（距上次上行=$gap）');
    }
  }

  /// 连接建立后按配置启动探针。
  /// 日志前缀 `[KEEPALIVE]` 便于 `adb logcat -s XiaoLe | findstr KEEPALIVE` 单线取证。
  ///
  /// 79 轮 P0：tick 定时器是"心跳是否还在跑"的唯一取证点，
  /// **绝不因为掉线（`_onDisconnected`）而 cancel**；只有主动断开 / 关闭保活才停。
  void _startProbe() {
    // 81：后台/息屏不发业务保活。Dart isolate 被 ColorOS 冻结，45s tick 不可能成立，
    // 强制保活只会变成"每次唤醒都新建连接"的 1005/1006 风暴。
    if (!_appForeground) {
      _stopProbe('后台（81：不启业务保活）');
      logger.info('[KEEPALIVE] 后台不启动保活探针（81 产品定义：锁屏可断、亮屏秒回）');
      return;
    }
    final mode = _probeMode;
    // 结算上一段统计（不断 timer、不清 _probeSeq：tick 号要跨重连单调递增）
    _settleProbe('新连接');
    _probeStartAt = DateTime.now();
    _lastUplinkAt = null;
    // 新连接 = 新 session，旧会话标记作废
    _conversationActive = false;
    _conversationEndAt = null;
    _conversationStaleTimer?.cancel();
    _conversationStaleTimer = null;

    if (mode == WsProbeMode.off) {
      _stopProbe('模式=off');
      logger.info('[KEEPALIVE] 关闭（不发保活消息；仅 WS ping=${PING_INTERVAL.inSeconds}s + 无感重连）');
      return;
    }
    if (_probeTimer != null) {
      logger.info('[$_tag] 连接已重建 mode=${mode.name} interval=${_probeInterval.inSeconds}s '
          '→ tick 续跑（tick#$_probeSeq，不重建定时器）');
      return;
    }
    logger.info('[$_tag] 启动 mode=${mode.name} interval=${_probeInterval.inSeconds}s '
        '条件=已连接且无会话中；对话结束 ${PROBE_RESUME_DELAY.inSeconds}s 后恢复');
    _probeTimer = Timer.periodic(_probeInterval, (_) => _tick('dart'));
  }

  /// 一拍心跳。[source] 只用于日志：`dart` = 配置间隔（默认 45s）定时器，
  /// `native` = 原生 KeepAliveService 每 30s 唤醒补拍。
  void _tick(String source) {
    _probeSeq++;
    _segTicks++;
    _lastTickAt = DateTime.now();
    final from = source == 'native' ? ' 来源=native唤醒' : '';
    if (_manualClosed || !isConnected) {
      logger.info('[$_tag] tick#$_probeSeq t=${_probeElapsedSec}s 发送=否 原因=未连接$from');
      return;
    }
    // v6.11.13：会话过期统一交给独立定时器（_expireConversationIfStale），
    // 这里只做一次兜底调用，避免 tick 与定时器两套判定漂移。
    if (_conversationActive) {
      _expireConversationIfStale();
    }
    if (_conversationActive) {
      logger.info('[$_tag] tick#$_probeSeq t=${_probeElapsedSec}s 发送=否 原因=会话中$from');
      return;
    }
    final now = DateTime.now();
    final end = _conversationEndAt;
    if (end != null && now.difference(end) < PROBE_RESUME_DELAY) {
      logger.info('[$_tag] tick#$_probeSeq t=${_probeElapsedSec}s 发送=否 '
          '原因=会话刚结束 ${now.difference(end).inSeconds}s<${PROBE_RESUME_DELAY.inSeconds}s$from');
      return;
    }
    final gap =
        _lastUplinkAt == null ? '首次' : '${now.difference(_lastUplinkAt!).inSeconds}s';
    for (final payload in _probePayloads()) {
      sendMessage(payload);
    }
    _probeSent++;
    _lastUplinkAt = now;
    logger.info('[$_tag] tick#$_probeSeq t=${_probeElapsedSec}s 发送=是 距上次上行=$gap '
        'payload=${_probeMode == WsProbeMode.auto ? 'listen:stop' : 'listen:detect'} '
        'recv=$_probeRecv$from');
  }

  /// 81：原生闹钟（60s）唤醒后调用。只做状态检查与日志，
  /// **不补拍心跳、不强制重连**——后台/息屏不追求 tick，亮屏由 onReturnToForeground 秒回。
  void onNativeWakeup() {
    // 81：原生闹钟只负责"唤醒进程 + 检查 socket"。绝不 _tick、绝不 forceReconnect——
    // 80 的"每次唤醒都重连"正是 1005/1006 风暴的根源。
    final last = _lastTickAt;
    final sinceTick = last == null
        ? '从未启动'
        : '${DateTime.now().difference(last).inSeconds}s 前';
    logger.info('[$_tag] 原生唤醒：前台=$_appForeground '
        'socket=${isSocketOpen ? '开' : '关'} connected=$isConnected '
        '最近tick=$sinceTick 最近close=${lastCloseCode ?? '-'}'
        '（81：不再唤醒即重连）');
    if (!_appForeground || _manualClosed) return;
    // 前台且 socket 已死：只安排一次退避重连（不跳过退避、不叠二次）
    if (!isSocketOpen) _scheduleReconnect();
  }

  /// 各模式的保活载荷（v6.11.11：生产只剩 auto / off，detect 仅诊断）
  /// auto  : 单条 listen stop（"停止监听"，实测不触发回复，零副作用）
  /// detect: 单条 listen detect（能保活但有 TTS 副作用，默认隐藏）
  List<String> _probePayloads() {
    switch (_probeMode) {
      case WsProbeMode.auto:
        return [jsonEncode({"type": "listen", "state": "stop"})];
      case WsProbeMode.detect:
        return [jsonEncode({"type": "listen", "state": "detect"})];
      case WsProbeMode.off:
        return const [];
    }
  }

  /// 只结算本段统计并打汇总日志，**不取消定时器**。
  /// 81：后台不跑探针；断线结算用于取证，不代表还要补拍心跳。
  void _settleProbe(String why) {
    if (_probeTimer != null || _probeStartAt != null) {
      final types = _probeTypes.entries
          .map((e) => '${e.key}=${e.value}')
          .join(',');
      logger.info('[$_tag] 结算（$why）mode=${_probeMode.name} '
          '存活=${_probeElapsedSec}s tick=$_probeSeq 本段tick=$_segTicks 发送=$_probeSent '
          '跳过=${_segTicks - _probeSent} 收到帧=$_probeRecv '
          '文本=$_probeDownText 音频=$_probeDownBinary'
          '${types.isEmpty ? '' : ' types={$types}'}');
    }
    _probeSent = 0;
    _probeRecv = 0;
    _segTicks = 0;
    _probeDownText = 0;
    _probeDownBinary = 0;
    _probeTypes.clear();
  }

  /// 彻底停表：只有「用户主动断开」「关闭保活」「页面销毁」才走这里。
  void _stopProbe(String why) {
    _settleProbe(why);
    _probeTimer?.cancel();
    _probeTimer = null;
    _conversationStaleTimer?.cancel();
    _conversationStaleTimer = null;
    _probeStartAt = null;
  }

  /// v6.11.9：从下行 JSON 提取 type（失败返回 unknown）
  String _typeOf(String raw) {
    final m = RegExp(r'"type"\s*:\s*"([^"]+)"').firstMatch(raw);
    return m?.group(1) ?? 'unknown';
  }

  /// v6.11.9：脱敏后取首 32 字符（token / session_id 一律打码）
  String _previewOf(String raw) {
    var s = raw
        .replaceAll(RegExp(r'"token"\s*:\s*"[^"]*"'), '"token":"***"')
        .replaceAll(RegExp(r'"session_id"\s*:\s*"[^"]*"'), '"session_id":"***"');
    if (s.length > 32) s = '${s.substring(0, 32)}…';
    return s;
  }

  /// v6.11.9：二进制帧首 N 字节 hex 摘要（音频帧无文本语义，只做指纹）
  String _hexHead(List<int> data, int n) {
    final take = data.length < n ? data.length : n;
    return data
        .sublist(0, take)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 发送文本消息（以 socket 是否存活为准；hello 本身必须在握手前就能发出去）
  void sendMessage(String message) {
    if (isSocketOpen) {
      try {
        _channel!.sink.add(message);
        _lastActivityAt = DateTime.now();
        //打印发送的消息
        logger.info('发送消息: $message');
      } catch (e, st) {
        // v4.3.3 发送自证：sink 写入异常必须暴露。
        // （此前若写入静默失败，会出现"明明发送成功却毫无反应"却查不到原因）
        logger.severe('发送消息异常（消息可能未送达服务器）: $e', e, st);
      }
    } else {
      logger.warning('发送失败，连接未建立');
    }
  }

  /// 发送二进制数据（同上：以 socket 存活为准）
  void sendBinaryMessage(List<int> data) {
    if (isSocketOpen) {
      try {
        _channel!.sink.add(data);
        _lastActivityAt = DateTime.now();
      } catch (e) {
        logger.severe('二进制数据发送失败: $e');
      }
    } else {
      logger.warning('发送失败，连接未建立');
    }
  }

  /// 发送文本请求
  void sendTextRequest(String text) {
    if (!isConnected) {
      logger.warning('发送失败，连接未建立');
      return;
    }

    try {
      // 构造消息格式，与Java实现保持一致
      final jsonMessage = {
        "type": "listen",
        "state": "detect",
        "text": text,
        "source": "text",
      };

      logger.info('发送文本请求: ${jsonEncode(jsonMessage)}');
      sendMessage(jsonEncode(jsonMessage));
    } catch (e) {
      logger.severe('发送文本请求失败: $e');
    }
  }

  /// 处理收到的消息
  void _onMessage(dynamic message) {
    _lastRecvAt = DateTime.now(); // v4.3.3：记录最近收包时间（供静默/僵死判断）
    _lastActivityAt = _lastRecvAt;
    // v6.11.17：服务器 hello ACK 是唯一的"连接成功"判据（P0-2）
    if (!_handshakeDone && message is String && _typeOf(message) == 'hello') {
      _completeHandshake();
    }
    // v6.11.8/6.11.9：心跳实验记录点——服务器是否回过帧、回的是什么
    if (_probeMode != WsProbeMode.off) {
      _probeRecv++;
      if (message is String) {
        _probeDownText++;
        final t = _typeOf(message);
        _probeTypes[t] = (_probeTypes[t] ?? 0) + 1;
        if (_probeRecv == 1) {
          logger.info('[$_tag] 本连接首个服务器帧 t=${_probeElapsedSec}s type=$t');
        }
        logger.info('[$_tag] 下行#${_probeRecv} 文本 type=$t preview=${_previewOf(message)}');
      } else if (message is List<int>) {
        _probeDownBinary++;
        _probeTypes['binary'] = (_probeTypes['binary'] ?? 0) + 1;
        if (_probeRecv == 1) {
          logger.info('[$_tag] 本连接首个服务器帧 t=${_probeElapsedSec}s type=binary');
        }
        // 音频帧量大：只对前 3 帧打首 32 字节指纹，其余只记长度，避免日志刷屏
        if (_probeDownBinary <= 3) {
          logger.info('[$_tag] 下行#${_probeRecv} 二进制 len=${message.length} '
              'head32=${_hexHead(message, 32)}');
        } else {
          logger.info('[$_tag] 下行#${_probeRecv} 二进制 len=${message.length}');
        }
      }
    }
    if (message is String) {
      // 文本消息
      logger.info('收到消息: $message');
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.message, data: message),
      );
    } else if (message is List<int>) {
      // 二进制消息
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.binaryMessage, data: message),
      );
    }
  }

  /// 处理断开连接事件
  void _onDisconnected() {
    // v6.11.17：握手闸门复位（本次连接无论是否曾握手成功，都已结束）
    _handshakeDone = false;
    // v6.11.21（78 轮）：socket 关闭即视为断开，先停保活服务再决定是否重连；
    // 重连成功后 _completeHandshake() 会重新置 true。
    KeepAliveCoordinator.instance.onConnectionChanged(false);
    _pendingIsReconnect = false;
    _helloTimer?.cancel();
    _helloTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    // v1.1.6: 采集服务器关闭码/原因，便于真机诊断（如 1006=异常断开）
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;
    // v6.11.8：先结算本次探针（候选名 / 存活秒数 / 发送数 / 收到帧 / close code）
    // 79 轮 P0：**只结算、不 cancel**——息屏掉线后 tick 必须继续跑，
    // 否则又回到"进程活着但心跳不跑"（78 真机 0 条 tick#2+ 的直接原因）。
    _settleProbe('服务器断开 code=${code ?? '-'}');
    // v6.11.10：记录关闭码与断开时刻，供重连频率评估使用
    _closeCodes.add(code ?? -1);
    if (_closeCodes.length > 20) _closeCodes.removeAt(0);
    _lastDisconnectAt = DateTime.now();
    // v4.3.3：kind=服务器 表示非主动断开（真正的连接丢失）；主动断开见 disconnect() 的 source 日志
    logger.info('连接已断开 code=$code reason=$reason attempts=$_reconnectAttempts '
        'kind=${_manualClosed ? '主动' : '服务器'}');
    String? codeInfo = (code != null || (reason != null && reason.isNotEmpty))
        ? '${code ?? ''} ${reason ?? ''}'.trim()
        : null;

    // v3.0.0：close code 分类（语义见 xiaoleweb.md §2.5）
    if (code == 1005) {
      // 服务器无状态码关闭：多为静默超 60s 被回收（正常保护）或身份大小写不符
      codeInfo = (codeInfo == null || codeInfo.isEmpty) ? '1005' : codeInfo;
      logger.info('1005=服务器回收连接（多为静默超时，属正常），自动重连');
    } else if (code == 1006) {
      // 81 结论：重连与首连共用同一 header 构造路径（device-id/client-id 均来自
      // final 字段），不存在"重连头不一致"；1006 多为 ColorOS 冻结/重复会话所致。
      logger.warning('1006=握手/协议被拒（81 已核对：重连 header 与首连一致，'
          '非头不一致；多为冻结/重复会话）');
    } else if (code == 4326 || code == 4327 || code == 4328) {
      logger.severe('432x=身份校验失败，重连无效。核对 MAC/ClientID 或重新激活');
      _dispatchEvent(
        XiaozhiEvent(
            type: XiaozhiEventType.error,
            data: '身份校验失败($code)：重连无效，请核对 MAC/ClientID 或重新激活'),
      );
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.disconnected, data: codeInfo),
      );
      return; // 🔴 身份拒绝：绝不重连（避免轰炸服务器）
    }

    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.disconnected, data: codeInfo),
    );

    // v3.0.0 指数退避自动重连（v6.11.6 抽成 _scheduleReconnect，看门狗复用同一路径）
    _scheduleReconnect();
  }

  /// v6.11.6：安排下一次重连。纯 Dart Timer 调度，不依赖 didChangeAppLifecycleState，
  /// 进程被冻结/回前台后定时器恢复即继续补连。
  void _scheduleReconnect() {
    if (_manualClosed) {
      logger.info('用户主动断开，不自动重连');
      return;
    }
    if (_serverUrl == null || _token == null) return;
    if (_isReconnecting) return;
    // 81：后台最多 3 次即停手，把"熄屏期间的重连风暴"压到 0。
    if (!_appForeground && _reconnectAttempts >= RECONNECT_BG_MAX_TRIES) {
      logger.info('[RECONNECT] 后台已连续失败 $_reconnectAttempts 次 → 停手，等亮屏恢复（81）');
      return;
    }
    if (_reconnectAttempts >= RECONNECT_MAX_TRIES) {
      logger.severe(
          '自动重连已达上限($RECONNECT_MAX_TRIES 次)，停止。请手动重连');
      _dispatchEvent(
        XiaozhiEvent(
            type: XiaozhiEventType.error,
            data: '自动重连已达上限，请检查网络后手动重连'),
      );
      return;
    }
    _isReconnecting = true;
    _reconnectAttempts++;
    // 81：固定阶梯 2s→5s→15s→30s→60s（超出封顶 60s）
    final idx = (_reconnectAttempts - 1).clamp(0, RECONNECT_DELAYS_MS.length - 1);
    final delay = RECONNECT_DELAYS_MS[idx];
    // v6.11.10：累计重连统计（次数 / 相邻间隔 / 最近关闭码）
    _reconnectTotal++;
    final now = DateTime.now();
    final last = _lastReconnectAt;
    final gap = last == null ? null : now.difference(last).inSeconds;
    if (gap != null) {
      _reconnectGapsSec.add(gap);
      if (_reconnectGapsSec.length > 100) _reconnectGapsSec.removeAt(0);
    }
    _lastReconnectAt = now;
    logger.info('[RECONNECT] 计划 #$_reconnectTotal（连续第$_reconnectAttempts次） '
        'delay=${delay / 1000}s gap=${gap ?? '-'}s '
        'code=${_closeCodes.isEmpty ? '-' : _closeCodes.last} '
        '距断开=${_lastDisconnectAt == null ? '-' : '${now.difference(_lastDisconnectAt!).inSeconds}s'}');
    if (_reconnectTotal % 10 == 0) _logReconnectSummary();
    logger.info('网络中断，${delay / 1000}s 后第 $_reconnectAttempts 次自动重连…');
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _isReconnecting = false;
      if (!_manualClosed && _serverUrl != null && _token != null) {
        connect(_serverUrl!, _token!, isReconnect: true);
      }
    });
  }

  /// v6.11.10：每 10 次重连打一条汇总，供"1 小时约 50 次是否过频"评估。
  /// 采集方式：`adb logcat -s flutter | findstr "[RECONNECT]"`，按小时统计 total/成功/间隔。
  void _logReconnectSummary() {
    final gaps = _reconnectGapsSec;
    final avg = gaps.isEmpty
        ? '-'
        : (gaps.reduce((a, b) => a + b) / gaps.length).toStringAsFixed(1);
    final minGap = gaps.isEmpty ? '-' : gaps.reduce((a, b) => a < b ? a : b);
    final maxGap = gaps.isEmpty ? '-' : gaps.reduce((a, b) => a > b ? a : b);
    final codeDist = <int, int>{};
    for (final c in _closeCodes) {
      codeDist[c] = (codeDist[c] ?? 0) + 1;
    }
    final codes =
        codeDist.entries.map((e) => '${e.key}:${e.value}').join(',');
    logger.info('[RECONNECT] 汇总 累计=$_reconnectTotal 成功=$_reconnectSuccess '
        '失败=${_reconnectTotal - _reconnectSuccess} '
        '间隔(avg/min/max)=$avg/$minGap/$maxGap s '
        '近20次closeCode={${codes.isEmpty ? '-' : codes}}');
  }

  /// v6.11.6：看门狗。每到 WATCHDOG_INTERVAL 检查一次，专门处理"进程被系统冻结
  /// 后 Dart 定时器停摆、回前台时订阅还在但连接早已丢失"这类"断了再也不回来"：
  /// 连接不存在就立即补连。僵死 socket 由 pingInterval 的 pong 超时自动触发
  /// _onDisconnected，这里不再重复判定（云端空闲时不下发消息，用消息静默判僵死会误杀）。
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    // 81：后台不跑看门狗——不能让定时器在冻结边缘反复安排重连
    if (!_appForeground) return;
    _watchdogTimer = Timer.periodic(WATCHDOG_INTERVAL, (_) {
      if (_manualClosed) return;
      if (!isConnected && !_isReconnecting) {
        logger.warning('看门狗：连接不存在，立即补连（已尝试 $_reconnectAttempts 次）');
        if (_reconnectAttempts >= RECONNECT_MAX_TRIES) _reconnectAttempts = 0;
        _scheduleReconnect();
      }
    });
  }

  /// 处理错误事件
  void _onError(error) {
    logger.severe('错误: $error');
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.error, data: error.toString()),
    );
  }

  /// socket 是否处于打开状态（不看握手；仅供发送层与 hello 使用）
  bool get isSocketOpen {
    return _channel != null && _streamSubscription != null;
  }

  /// 判断是否已连接（v6.11.17：必须是"socket 打开 + 收到服务器 hello ACK"）
  bool get isConnected {
    return isSocketOpen && _handshakeDone;
  }

  /// v6.11.17：页面侧"想打就打"不再新建管理器，而是让现有管理器立即补连。
  /// 旧实现会再走一遍 _initializeWebSocket 建出第二个 manager，
  /// 两个 manager 用同一 device-id 建两条 socket，服务端按重复会话 1005 回收其一。
  /// 80 轮：socket 仍打开时一律不重建——回前台只看 socket 实际状态，
  /// 1002/1005 属于服务端先断，由 `_onDisconnected` 的正常重连处理，不再叠二次。
  /// 81：亮屏/用户点击的"立即恢复"入口——清零退避计数，只补连一次。
  void forceReconnect({String reason = '页面请求'}) {
    if (_serverUrl == null || _token == null) return;
    if (isSocketOpen) return; // 已有 socket（含等 hello），由握手闸门决定成败
    if (_manualClosed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _manualClosed = false;
    _reconnectAttempts = 0;
    logger.info('[RECONNECT] $reason：立即补连（跳过退避，1 次）');
    unawaited(connect(_serverUrl!, _token!, isReconnect: true));
  }

  /// 81：前后台切换入口。后台停业务保活/看门狗/待执行重连；
  /// 前台只恢复探针，真正的立即补连交给 [onReturnToForeground]。
  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (!foreground) {
      _stopProbe('进入后台（81：后台不发业务保活）');
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _isReconnecting = false;
      logger.info('[LIFECYCLE] 进入后台：已停保活探针/看门狗/待执行重连 '
          'connected=$isConnected socket=$isSocketOpen attempts=$_reconnectAttempts');
      return;
    }
    logger.info('[LIFECYCLE] 回到前台：恢复保活探针（81：前台才发 45s listen:stop）');
    if (isSocketOpen) _startProbe();
  }

  /// 81：亮屏秒回。取消待执行退避、清零计数：
  /// - socket 还开 → 不重连（避免误杀健康连接）；
  /// - socket 已死 → 立即补连一次，不等退避。
  /// 返回是否真的进入了恢复流程（用户主动断开时为 false，页面不要显示恢复态）。
  bool onReturnToForeground() {
    _appForeground = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
    if (_manualClosed) return false;
    if (isSocketOpen) {
      logger.info('[LIFECYCLE] 回前台 socket 仍打开 → 不重连（连接未死）');
      if (_probeTimer == null) _startProbe();
      _startWatchdog(); // 后台停掉的看门狗同步恢复
      return false;
    }
    logger.info('[LIFECYCLE] 回前台 socket 已死 → 立即补连一次（81 亮屏秒回）');
    forceReconnect(reason: '回前台');
    return true;
  }
}
