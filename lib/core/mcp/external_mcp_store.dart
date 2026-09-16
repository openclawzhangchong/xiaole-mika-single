import 'dart:convert';

import '../storage/storage_service.dart';

/// v6.4.0：单条外部 MCP 服务器配置
class ExternalMcpServer {
  /// 唯一标识（本地生成）
  final String id;

  /// 展示名（如 "biji-notes"）
  final String name;

  /// 工具名前缀：暴露给 AI 的工具名为 `{prefix}.{原始工具名}`
  /// 例如 prefix=notes → `notes.search_notes`
  final String prefix;

  /// streamable HTTP 端点（JSON-RPC 走 POST）
  final String url;

  /// 附加请求头（如 biji 的 Authorization: Bearer ...）
  final Map<String, String> headers;

  /// 整台服务器是否启用
  final bool enabled;

  /// 逐工具关闭名单（存**原始**工具名，如 add_note）
  final List<String> disabledTools;

  const ExternalMcpServer({
    required this.id,
    required this.name,
    required this.prefix,
    required this.url,
    this.headers = const <String, String>{},
    this.enabled = true,
    this.disabledTools = const <String>[],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prefix': prefix,
        'url': url,
        'headers': headers,
        'enabled': enabled,
        'disabledTools': disabledTools,
      };

  factory ExternalMcpServer.fromJson(Map<String, dynamic> j) => ExternalMcpServer(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        prefix: (j['prefix'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        headers: j['headers'] is Map
            ? Map<String, String>.from(
                (j['headers'] as Map).map(
                    (k, v) => MapEntry(k.toString(), v.toString())))
            : const <String, String>{},
        enabled: j['enabled'] != false,
        disabledTools: j['disabledTools'] is List
            ? (j['disabledTools'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
            : const <String>[],
      );

  ExternalMcpServer copyWith({
    String? id,
    String? name,
    String? prefix,
    String? url,
    Map<String, String>? headers,
    bool? enabled,
    List<String>? disabledTools,
  }) =>
      ExternalMcpServer(
        id: id ?? this.id,
        name: name ?? this.name,
        prefix: prefix ?? this.prefix,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        enabled: enabled ?? this.enabled,
        disabledTools: disabledTools ?? this.disabledTools,
      );

  /// 由名称推导默认前缀：取首段并只保留 [a-z0-9_]
  /// 例：biji-notes → biji；amap-maps-streamableHTTP → amap
  static String derivePrefix(String name) {
    final first = name.split(RegExp(r'[-_\s]')).firstWhere(
          (s) => s.isNotEmpty,
          orElse: () => name,
        );
    final cleaned = first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return cleaned.isEmpty ? 'mcp' : cleaned;
  }
}

/// 配置持久化（JSON 字符串存 SharedPreferences）
class ExternalMcpStore {
  ExternalMcpStore._();

  static const String _key = 'xw_external_mcp_servers';

  static List<ExternalMcpServer> load() {
    final raw = StorageService.instance.getString(_key);
    if (raw == null || raw.isEmpty) return const <ExternalMcpServer>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => ExternalMcpServer.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.url.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 数据损坏时当作空列表，避免启动崩溃
    }
    return const <ExternalMcpServer>[];
  }

  static Future<void> save(List<ExternalMcpServer> list) =>
      StorageService.instance.setString(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
}
