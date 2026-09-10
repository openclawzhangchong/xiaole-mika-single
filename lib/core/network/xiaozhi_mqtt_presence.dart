import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart'; // v10.x：MqttServerClient 在独立库文件

/// 小智 MQTT 常驻在线（v3.3.0，对齐真机 240s 心跳，见 xiaoleweb.md 第六章）
/// ------------------------------------------------------------------
/// 真机后台常显在线靠 MQTT 长连接（OTA 响应下发凭据 → TLS 8883 → keepalive 240s）。
/// App 原生可直连 TCP/TLS，**无需网页版的 worker TCP 桥**。
/// 用途：①xiaozhi.me 后台显示「在线」；②接收后台远程配置/MCP 下发
///（订阅 devices/p2p/<mac>，消息经 onMessage 回调转交 MCP 响应器）。
///
/// ⚠️ 实测坑（xiaoleweb.md §6.2）：EMQX 对同一 clientId 高频重连有限流惩罚窗
///（connack timeout/连上即断）。本类保持长连接、断线交给 mqtt_client 内建
/// 自动重连（自带退避），外部禁止高频 start/stop。
class XiaozhiMqttPresence {
  final Logger logger = Logger('XiaozhiMqttPresence');

  final String endpoint; // OTA 响应 mqtt.endpoint（如 api.tenclass.net）
  final String clientId; // mqtt.client_id（GID_test@@@mac@@@cid 格式，勿自行构造）
  final String username;
  final String password;
  final String mac; // 设备 MAC（订阅 devices/p2p/<mac 冒号换下划线>）
  final void Function(Map<String, dynamic> msg)? onMessage;

  MqttServerClient? _client;
  bool _userStopped = false;

  XiaozhiMqttPresence({
    required this.endpoint,
    required this.clientId,
    required this.username,
    required this.password,
    required this.mac,
    this.onMessage,
  });

  /// 建立连接并订阅设备下行主题。返回是否成功（失败可重试，但勿高频）。
  Future<bool> start() async {
    if (_client != null) return true;
    _userStopped = false;

    // endpoint 可能带协议前缀/路径，剥出纯 host
    final host = endpoint
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/.*$'), '')
        .trim();
    if (host.isEmpty) {
      logger.warning('MQTT endpoint 为空，无法连接');
      return false;
    }

    final client = MqttServerClient.withPort(host, clientId, 8883)
      ..secure = true // TLS 8883（真机同款）
      ..keepAlivePeriod = 240 // 真机同款心跳
      ..connectTimeoutPeriod = 20000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    client.onConnected = () =>
        logger.info('📡 MQTT 常驻连接建立（后台应显示在线）');
    client.onAutoReconnect = () => logger.warning('MQTT 断线，自动重连中…');
    client.onAutoReconnected = () => logger.info('MQTT 自动重连成功');
    final connMess = MqttConnectMessage()
      ..authenticateAs(username, password)
      ..startClean()
      ..keepAliveFor(240);
    client.connectionMessage = connMess;
    _client = client;

    try {
      final status = await client.connect(username, password);
      if (status == null ||
          status.state != MqttConnectionState.connected) {
        logger.severe('MQTT 连接失败: ${status?.state}');
        _client = null;
        return false;
      }
      final topic = 'devices/p2p/${mac.replaceAll(':', '_')}';
      client.subscribe(topic, MqttQos.atLeastOnce);
      logger.info('📡 已订阅 $topic');
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        for (final m in c) {
          final publish = m.payload as MqttPublishMessage;
          final text = MqttPublishPayload.bytesToStringAsString(
              publish.payload.message);
          logger.info(
              'MQTT ← ${text.length > 150 ? text.substring(0, 150) : text}');
          try {
            final msg = jsonDecode(text);
            if (msg is Map) {
              onMessage?.call(Map<String, dynamic>.from(msg));
            }
          } catch (_) {}
        }
      });
      return true;
    } catch (e) {
      logger.severe('MQTT 连接异常: $e');
      _client = null;
      return false;
    }
  }

  void stop() {
    _userStopped = true;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    logger.info('MQTT 常驻连接已关闭');
  }

  bool get isStoppedByUser => _userStopped;
}
