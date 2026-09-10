import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/message_model.dart';

/// 聊天记录本地存储（v1.1.6，纯表现层，零红线）
///
/// - 每个智能体独立一份（键 `chat_history_<agentId>`，JSON 数组）；
/// - 进入对话时加载最近 [loadLimit] 条；
/// - 收发消息后整表落库，最多保留 [maxKeep] 条防膨胀；
/// - 卸载重装/清数据会清空（本地存储，属预期）。
class ChatHistoryStore {
  ChatHistoryStore._();

  static const String keyPrefix = 'chat_history_';
  static const String _prefix = keyPrefix;
  static const int maxKeep = 1000;
  static const int loadLimit = 200;

  /// 读取某智能体的全部聊天历史（不裁剪，按时间正序）——v4.1.0 一键云端上传用
  static Future<List<MessageModel>> loadAll(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$agentId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return []; // 数据损坏时静默丢弃，不影响聊天
    }
  }

  /// 读取某智能体的聊天历史（最近 [loadLimit] 条，按时间正序）
  static Future<List<MessageModel>> load(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$agentId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => MessageModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return list.length > loadLimit
          ? list.sublist(list.length - loadLimit)
          : list;
    } catch (_) {
      return []; // 数据损坏时静默丢弃，不影响聊天
    }
  }

  /// 保存某智能体的聊天记录（整表覆盖写，超出上限丢最旧的）
  static Future<void> save(String agentId, List<MessageModel> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = messages.length > maxKeep
          ? messages.sublist(messages.length - maxKeep)
          : messages;
      final json = jsonEncode(trimmed.map((m) => m.toJson()).toList());
      await prefs.setString('$_prefix$agentId', json);
    } catch (_) {
      // 存储失败不影响聊天主流程
    }
  }
}
