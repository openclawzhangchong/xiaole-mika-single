import 'dart:convert';

import '../network/xiaozhi_mcp_responder.dart' show XiaozhiMcpTool;
import 'external_mcp_client.dart';
import 'external_mcp_store.dart';

/// v6.4.0：外部 MCP 管理器（单例）
/// ------------------------------------------------------------------
/// 职责：
/// - 持有配置列表（ExternalMcpStore 持久化）
/// - refreshAll()：对每台启用中的服务器做 initialize + tools/list，缓存工具与状态
/// - mergedTools()：把外部工具**加前缀**映射成设备工具名，供 tools/list 一并下发给 AI
/// - dispatch()：AI 调用带前缀的外部工具时，转发到对应服务器
class ExternalMcpManager {
  ExternalMcpManager._();

  static final ExternalMcpManager instance = ExternalMcpManager._();

  final List<ExternalMcpServer> servers = <ExternalMcpServer>[];

  /// serverId → 最近一次探测结果
  final Map<String, McpProbeResult> _probe = <String, McpProbeResult>{};

  bool _inited = false;

  /// 客户端工厂。生产环境保持 null（按各自 url/headers 构造真实客户端）；
  /// 单测注入此工厂即可在不发真实网络请求的前提下验证合并与转发逻辑。
  ExternalMcpClient Function(ExternalMcpServer s)? clientFactory;

  ExternalMcpClient _clientFor(ExternalMcpServer s) =>
      clientFactory?.call(s) ??
      ExternalMcpClient(url: s.url, headers: s.headers);

  Future<void> init() async {
    if (_inited) return;
    servers
      ..clear()
      ..addAll(ExternalMcpStore.load());
    _inited = true;
  }

  Future<void> save() => ExternalMcpStore.save(servers);

  McpProbeResult? statusOf(String serverId) => _probe[serverId];

  ExternalMcpServer? byId(String id) => servers.cast<ExternalMcpServer?>().firstWhere(
        (s) => s?.id == id,
        orElse: () => null,
      );

  /// 并发探测所有启用中的服务器
  Future<void> refreshAll() async {
    if (!_inited) await init();
    await Future.wait(servers.where((s) => s.enabled).map((s) async {
      _probe[s.id] = await _clientFor(s).probe();
    }));
  }

  /// 合并后的工具清单（已加前缀、已剔除逐项关闭的工具）
  List<XiaozhiMcpTool> mergedTools() {
    final out = <XiaozhiMcpTool>[];
    for (final s in servers) {
      if (!s.enabled) continue;
      final pr = _probe[s.id];
      if (pr == null || !pr.ok) continue;
      for (final t in pr.tools) {
        if (s.disabledTools.contains(t.name)) continue;
        final exposed = s.prefix.isEmpty ? t.name : '${s.prefix}.${t.name}';
        out.add(XiaozhiMcpTool(
          name: exposed,
          description: t.description,
          inputSchema: t.inputSchema,
        ));
      }
    }
    return out;
  }

  /// 该工具名是否属于某个外部服务器（按前缀判定）
  bool isExternal(String name) => _serverOfTool(name) != null;

  ExternalMcpServer? _serverOfTool(String name) {
    for (final s in servers) {
      if (!s.enabled || s.prefix.isEmpty) continue;
      if (name.startsWith('${s.prefix}.')) return s;
    }
    return null;
  }

  /// 转发调用。返回结构与设备工具一致：{'success':bool, 'text'/ 'message'}
  Future<Map<String, dynamic>> dispatch(
      String name, Map<String, dynamic> args) async {
    final s = _serverOfTool(name);
    if (s == null) {
      return {'success': false, 'message': '未找到该外部工具'};
    }
    final raw = name.substring('${s.prefix}.'.length);
    if (s.disabledTools.contains(raw)) {
      return {'success': false, 'message': '该外部工具已被关闭'};
    }
    final text = await _clientFor(s).callTool(raw, args);
    final ok = !text.startsWith('调用失败');
    return ok
        ? {'success': true, 'text': text}
        : {'success': false, 'message': text};
  }

  /// 解析用户粘贴的 `{"mcpServers":{...}}` 片段
  /// 返回解析出的配置列表；失败抛出带原因的 FormatException
  static List<ExternalMcpServer> parseMcpServersJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('内容为空');
    }
    final decoded = jsonDecode(trimmed);
    Map<String, dynamic>? root;
    if (decoded is Map && decoded['mcpServers'] is Map) {
      root = Map<String, dynamic>.from(decoded['mcpServers'] as Map);
    } else if (decoded is Map) {
      // 也允许直接贴 {"name":{"url":...}} 形式
      root = Map<String, dynamic>.from(decoded);
    } else {
      throw const FormatException('不是合法的 JSON 对象');
    }

    final out = <ExternalMcpServer>[];
    root.forEach((key, value) {
      if (value is! Map) return;
      final e = Map<String, dynamic>.from(value);
      final url = (e['url'] ?? '').toString();
      if (url.isEmpty) return;
      // type 只做参考（本实现统一走 streamable HTTP POST）
      out.add(ExternalMcpServer(
        id: 'mcp_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
        name: key,
        prefix: ExternalMcpServer.derivePrefix(key),
        url: url,
        headers: e['headers'] is Map
            ? Map<String, String>.from((e['headers'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString())))
            : const <String, String>{},
      ));
    });
    if (out.isEmpty) {
      throw const FormatException('未解析到任何带 url 的服务器');
    }
    return out;
  }
}
