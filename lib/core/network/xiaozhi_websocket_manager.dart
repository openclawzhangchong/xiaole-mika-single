import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:logging/logging.dart';
// 尝试导入io.dart,但在web平台会抛出异常
import 'package:web_socket_channel/io.dart'
    if (dart.library.html) 'package:web_socket_channel/html.dart';

/// 小智WebSocket事件类型
enum XiaozhiEventType { connected, disconnected, message, error, binaryMessage }

/// v6.11.9：保活方案收敛为二值。
/// 真机实验（6.11.8+60，2026-11-04 18:20–18:24）结论：
/// - hello/abort 与对照组同量级（65–68s 被 1005 回收）→ 无效，已剔除；
/// - detect 是唯一撑过 3 分钟的候选（240s+ 无 1005），但每个 tick 都会触发
///   服务端一轮 stt→llm→tts（实测 8 tick = 8 次 TTS 播放）→ **默认关闭**，
///   只在需要极端保活且能接受"自言自语"噪音时由开发者显式开启。
enum WsProbeMode {
  /// 关（生产默认：仍保留 WS pingInterval + 无感重连兜底）
  off,

  /// 定时发 listen{state:"detect"}（唯一有效保活，但有 TTS 副作用）
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

  // v3.0.0 重连策略（对齐网页版实测经验，见 xiaoleweb.md §2.6）：
  // 指数退避 1s→2s→4s…封顶 30s，最多 12 次；1005=服务器静默回收(正常)静默重连；
  // 432x=身份校验失败(重连无效)停止并明确提示；用户主动断开(_manualClosed)永不重连。
  static const int RECONNECT_BASE_MS = 1000;
  static const int RECONNECT_MAX_MS = 30000;
  static const int RECONNECT_MAX_TRIES = 12;

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
  bool _manualClosed = false;

  /// v4.3.3：最近一次收到服务器消息的时间（供上层判断连接是否已僵死）
  DateTime? _lastRecvAt;

  // ===== v6.11.8：心跳实验（默认关闭）=====
  final WsProbeMode _probeMode;
  final Duration _probeInterval;
  Timer? _probeTimer;
  int _probeSeq = 0;
  int _probeRecv = 0;
  DateTime? _probeStartAt;

  // ===== v6.11.9：会话感知（保活只在"空闲"时发）=====
  /// 是否有进行中的会话（用户上行 / listen start / 未完成回复 / TTS 播放）
  bool _conversationActive = false;
  DateTime? _conversationEndAt;
  DateTime? _lastActivityAt;

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

      // 连接成功后发送Hello消息
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.connected, data: null),
      );

      // 在发送认证信息之后发送Hello消息
      Timer(Duration(milliseconds: 200), () {
        _sendHelloMessage();
      });

      logger.info('已连接到 $uri');
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

    // 取消重连
    _reconnectTimer?.cancel();
    _isReconnecting = false;

    // v6.11.6：主动断开时停掉看门狗，避免它把用户手动断开又连回去
    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    // v6.11.8：主动断开同时停掉心跳探针
    _stopProbe('App 主动断开');

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

  /// 发送Hello消息
  void _sendHelloMessage() {
    sendMessage(jsonEncode(_helloPayload()));
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
    if (_probeMode != WsProbeMode.off) {
      logger.info('[PROBE] 进入会话，保活暂停（$why）');
    }
  }

  /// v6.11.9：上层标记"会话结束"（TTS stop/end、挂断、音频播放结束）。
  /// 5s 后恢复保活，留给尾音保护与迟到音频帧。
  void markConversationIdle(String why) {
    if (!_conversationActive) return;
    _conversationActive = false;
    _conversationEndAt = DateTime.now();
    if (_probeMode != WsProbeMode.off) {
      logger.info('[PROBE] 会话结束，${PROBE_RESUME_DELAY.inSeconds}s 后恢复保活（$why）');
    }
  }

  /// 是否处于会话中（供调试页展示）
  bool get conversationActive => _conversationActive;

  /// 连接建立后按配置启动探针。
  /// 日志前缀 `[PROBE]` 便于 `adb logcat | findstr PROBE` 单线取证。
  void _startProbe() {
    _stopProbe('新连接');
    _probeSeq = 0;
    _probeRecv = 0;
    _probeDownText = 0;
    _probeDownBinary = 0;
    _probeTypes.clear();
    _probeStartAt = DateTime.now();
    // 新连接 = 新 session，旧会话标记作废
    _conversationActive = false;
    _conversationEndAt = null;

    final mode = _probeMode;
    if (mode == WsProbeMode.off) {
      logger.info('[PROBE] 关闭（不发保活消息；仅 WS ping=${PING_INTERVAL.inSeconds}s + 无感重连）');
      return;
    }
    final iv = _probeInterval.inSeconds;
    logger.info('[PROBE] 启动 mode=${mode.name} interval=${iv}s '
        '条件=已连接且无会话中；对话结束 ${PROBE_RESUME_DELAY.inSeconds}s 后恢复');
    _probeTimer = Timer.periodic(_probeInterval, (_) {
      if (_manualClosed || !isConnected) return;
      final now = DateTime.now();
      // v6.11.9 兜底：上层漏发"会话结束"时，无活动超过 60s 自动恢复
      if (_conversationActive) {
        final last = _lastActivityAt;
        if (last == null || now.difference(last) >= CONVERSATION_STALE) {
          _conversationActive = false;
          _conversationEndAt = now;
          logger.warning('[PROBE] 会话标记超时（${last == null ? '无活动记录' : '${now.difference(last).inSeconds}s 无活动'}），自动恢复保活');
        } else {
          logger.info('[PROBE] skip（会话进行中）t=${_probeElapsedSec}s');
          return;
        }
      }
      final end = _conversationEndAt;
      if (end != null && now.difference(end) < PROBE_RESUME_DELAY) {
        logger.info('[PROBE] skip（会话刚结束 ${now.difference(end).inSeconds}s < ${PROBE_RESUME_DELAY.inSeconds}s）');
        return;
      }
      _probeSeq++;
      logger.info('[PROBE] tick mode=${mode.name} seq=$_probeSeq '
          'interval=${iv}s t=${_probeElapsedSec}s recv=$_probeRecv');
      sendMessage(_probePayload());
    });
  }

  /// detect 保活载荷（v6.11.9 仅保留这一种）
  String _probePayload() => jsonEncode({"type": "listen", "state": "detect"});

  void _stopProbe(String why) {
    if (_probeTimer != null || _probeStartAt != null) {
      final types = _probeTypes.entries
          .map((e) => '${e.key}=${e.value}')
          .join(',');
      logger.info('[PROBE] 停止（$why）mode=${_probeMode.name} '
          '存活=${_probeElapsedSec}s 发送=$_probeSeq 收到帧=$_probeRecv '
          '文本=$_probeDownText 音频=$_probeDownBinary'
          '${types.isEmpty ? '' : ' types={$types}'}');
    }
    _probeTimer?.cancel();
    _probeTimer = null;
    _probeStartAt = null;
    _probeDownText = 0;
    _probeDownBinary = 0;
    _probeTypes.clear();
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

  /// 发送文本消息
  void sendMessage(String message) {
    if (_channel != null && isConnected) {
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

  /// 发送二进制数据
  void sendBinaryMessage(List<int> data) {
    if (_channel != null && isConnected) {
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
    // v6.11.8/6.11.9：心跳实验记录点——服务器是否回过帧、回的是什么
    if (_probeMode != WsProbeMode.off) {
      _probeRecv++;
      if (message is String) {
        _probeDownText++;
        final t = _typeOf(message);
        _probeTypes[t] = (_probeTypes[t] ?? 0) + 1;
        if (_probeRecv == 1) {
          logger.info('[PROBE] 本连接首个服务器帧 t=${_probeElapsedSec}s type=$t');
        }
        logger.info('[PROBE] 下行#${_probeRecv} 文本 type=$t preview=${_previewOf(message)}');
      } else if (message is List<int>) {
        _probeDownBinary++;
        _probeTypes['binary'] = (_probeTypes['binary'] ?? 0) + 1;
        if (_probeRecv == 1) {
          logger.info('[PROBE] 本连接首个服务器帧 t=${_probeElapsedSec}s type=binary');
        }
        // 音频帧量大：只对前 3 帧打首 32 字节指纹，其余只记长度，避免日志刷屏
        if (_probeDownBinary <= 3) {
          logger.info('[PROBE] 下行#${_probeRecv} 二进制 len=${message.length} '
              'head32=${_hexHead(message, 32)}');
        } else {
          logger.info('[PROBE] 下行#${_probeRecv} 二进制 len=${message.length}');
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
    // v1.1.6: 采集服务器关闭码/原因，便于真机诊断（如 1006=异常断开）
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;
    // v6.11.8：先结算本次探针（候选名 / 存活秒数 / 发送数 / 收到帧 / close code）
    _stopProbe('服务器断开 code=${code ?? '-'}');
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
      logger.warning('1006=握手/协议被拒（检查 device-id/client-id 头）');
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
    final delay = _reconnectAttempts <= 1
        ? RECONNECT_BASE_MS
        : (RECONNECT_BASE_MS * (1 << (_reconnectAttempts - 1)))
            .clamp(RECONNECT_BASE_MS, RECONNECT_MAX_MS);
    logger.info('网络中断，${delay / 1000}s 后第 $_reconnectAttempts 次自动重连…');
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _isReconnecting = false;
      if (!_manualClosed && _serverUrl != null && _token != null) {
        connect(_serverUrl!, _token!, isReconnect: true);
      }
    });
  }

  /// v6.11.6：看门狗。每到 WATCHDOG_INTERVAL 检查一次，专门处理"进程被系统冻结
  /// 后 Dart 定时器停摆、回前台时订阅还在但连接早已丢失"这类"断了再也不回来"：
  /// 连接不存在就立即补连。僵死 socket 由 pingInterval 的 pong 超时自动触发
  /// _onDisconnected，这里不再重复判定（云端空闲时不下发消息，用消息静默判僵死会误杀）。
  void _startWatchdog() {
    _watchdogTimer?.cancel();
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

  /// 判断是否已连接
  bool get isConnected {
    return _channel != null && _streamSubscription != null;
  }
}
