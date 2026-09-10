import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/config/app_config.dart';
import '../../data/models/agent_model.dart';
import '../../data/models/message_model.dart';
import 'chat_history_store.dart';

/// v4.3.0：本地聊天记录导出（方案模块三，完全对齐网页版 v1.3.1 规格）。
/// ------------------------------------------------------------------
/// - 范围：全部智能体 / 单选智能体；格式：TXT（默认易读）/ JSON（默认，对齐网页版）；
/// - 起止日期过滤：留空不过滤；启用后无完整时间戳的历史消息排除（网页版同规则）；
/// - TXT 带 BOM（\uFEFF）保证记事本中文不乱码，CRLF 换行；
/// - 交付：写入临时目录 → 调用方交给 share_plus 系统分享面板。
class ChatExportService {
  ChatExportService._();

  /// 单条导出消息（role/text/time/ts，字段名对齐网页版 JSON 结构）
  /// MessageModel.timestamp 为非空 DateTime（所有本地消息必有时间戳），
  /// 网页版「无时间戳排除」规则在 App 侧天然不适用。
  static Map<String, dynamic> _msgToMap(MessageModel m) {
    final ts = m.timestamp;
    final time = '${ts.month}-${ts.day} ${_hhmm(ts)}';
    final text = m.type == MessageType.image
        ? '[图片]'
        : m.type == MessageType.audio
            ? '[语音]'
            : m.content;
    return {
      'role': _roleOf(m),
      'text': text,
      'time': time,
      'ts': ts.millisecondsSinceEpoch,
    };
  }

  static String _roleOf(MessageModel m) {
    switch (m.sender) {
      case MessageSender.user:
        return 'user';
      case MessageSender.ai:
        return 'ai';
      case MessageSender.system:
        return 'system';
    }
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 读取本地全部智能体 + 会话（与 cloud_sync_page._readLocal 同模式）
  static Future<(List<AgentModel>, Map<String, List<MessageModel>>)>
      readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final agents = <AgentModel>[];
    final raw = prefs.getString(AppConfig.keyAgentList);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          try {
            agents.add(AgentModel.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      } catch (_) {}
    }
    final sessions = <String, List<MessageModel>>{};
    for (final a in agents) {
      final msgs = await ChatHistoryStore.loadAll(a.id);
      if (msgs.isNotEmpty) sessions[a.id] = msgs;
    }
    return (agents, sessions);
  }

  /// 全量统计（导出页打开时显示「N 个智能体 · M 条消息」）
  static Future<({int agentCount, int msgCount})> stats() async {
    final (agents, sessions) = await readLocal();
    var n = 0;
    for (final a in agents) {
      n += sessions[a.id]?.length ?? 0;
    }
    return (agentCount: agents.length, msgCount: n);
  }

  /// 收集范围内消息（scopeId='all' 或具体 agentId；from/to 传 null 表示不过滤。
  /// App 侧所有消息必有非空时间戳，日期过滤直接按 ts 比较）
  static Future<List<({String id, String name, List<Map<String, dynamic>> messages})>>
      collectAsync({
    required String scopeId,
    DateTime? from,
    DateTime? to,
  }) async {
    final (agents, sessions) = await readLocal();
    final fromTs = from?.millisecondsSinceEpoch;
    final toTs = to?.millisecondsSinceEpoch;
    final out =
        <({String id, String name, List<Map<String, dynamic>> messages})>[];
    for (final a in agents) {
      if (scopeId != 'all' && a.id != scopeId) continue;
      final msgs = <Map<String, dynamic>>[];
      for (final m in sessions[a.id] ?? const <MessageModel>[]) {
        final ts = m.timestamp.millisecondsSinceEpoch;
        if (fromTs != null && ts < fromTs) continue;
        if (toTs != null && ts > toTs) continue;
        msgs.add(_msgToMap(m));
      }
      out.add((id: a.id, name: a.name, messages: msgs));
    }
    return out;
  }

  static String _scopeName(String scopeId, List<AgentModel> agents) {
    if (scopeId == 'all') return '全部智能体';
    for (final a in agents) {
      if (a.id == scopeId) return a.name;
    }
    return '智能体';
  }

  /// 导出主流程：收集 → 生成内容 → 写临时文件，返回文件供系统分享。
  /// 返回 null 表示所选范围内没有聊天记录。
  static Future<File?> exportToFile({
    required String scopeId,
    required String fmt, // 'json' | 'txt'
    DateTime? from,
    DateTime? to,
  }) async {
    final (agents, _) = await readLocal();
    final data = await collectAsync(scopeId: scopeId, from: from, to: to);
    final total = data.fold<int>(0, (s, a) => s + a.messages.length);
    if (total == 0) return null;

    final scopeName = _scopeName(scopeId, agents);
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    String content;
    if (fmt == 'json') {
      final payload = {
        'app': 'xiaole-app',
        'version': AppConfig.appVersion,
        'exportedAt': now.toIso8601String(),
        'range': {
          'scope': scopeName,
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
        },
        'totalMessages': total,
        'agents': data
            .map((a) => {'id': a.id, 'name': a.name, 'messages': a.messages})
            .toList(),
      };
      content = const JsonEncoder.withIndent('  ').convert(payload);
    } else {
      // TXT 模板复刻网页版 v1.3.1（BOM 由调用方写入文件时追加）
      final fromV = from != null
          ? '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}'
          : '';
      final toV = to != null
          ? '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}'
          : '';
      final lines = <String>[
        '小乐App · 聊天记录导出',
        '导出时间：${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${_hhmm(now)}',
        '范围：$scopeName${(fromV.isNotEmpty || toV.isNotEmpty) ? '（${fromV.isEmpty ? '不限' : fromV} ~ ${toV.isEmpty ? '不限' : toV}）' : ''}',
        '=' * 40,
      ];
      for (final a in data) {
        lines.add('');
        lines.add('【${a.name}】（${a.messages.length} 条）');
        for (final m in a.messages) {
          final role = m['role'] as String;
          final who = role == 'user'
              ? '我'
              : role == 'system'
                  ? '系统'
                  : a.name;
          lines.add('[${m['time'] ?? '时间未知'}] $who：${m['text']}');
        }
        lines.add('-' * 40);
      }
      content = lines.join('\r\n');
    }

    final safeName =
        'xiaole聊天_${scopeName}_$stamp.$fmt'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$safeName');
    // BOM 仅 TXT 需要（JSON 读取方不依赖 BOM）
    await file.writeAsString(
        fmt == 'txt' ? '\ufeff$content' : content,
        encoding: utf8);
    return file;
  }
}
