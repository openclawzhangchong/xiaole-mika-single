import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// v6.4.0：外部 MCP 服务器客户端（streamable HTTP + JSON-RPC 2.0）
/// ------------------------------------------------------------------
/// ⚠️ 以下均为 2026-09-16 对两个真实端点的**实测结论**，改动前请先看清：
///
/// 1. **biji-notes 有双重 UA 校验**：Cloudflare + 源站都会挡非浏览器 UA。
///    - `Mozilla/5.0 (...)` → 200
///    - Dart 默认 `Dart/3.x`、`okhttp`、`curl` → **401**（源站伪装成"凭证格式不正确"）
///    - 空 UA → **403** CF Error 1010
///    ⇒ 所有请求强制带浏览器式 User-Agent（kMcpBrowserUserAgent）。
/// 2. **amap 的 Accept 必须同时含 `application/json` 与 `text/event-stream`**，否则 **406**。
/// 3. **两服务器均无状态**：响应头无 `Mcp-Session-Id`，也不要求
///    `notifications/initialized`（按规范仍发一次，无害）。
/// 4. **响应三态**：
///    - 顶层 `error`        → 协议错误，取 `error.message`
///    - `result.isError=true` → 业务错误，取 `result.content[0].text`
///    - 正常                → 取 `result.content[0].text`
///    amap 的 text 是 **JSON 字符串**、biji 是 **纯文本** —— 一律原样透传，不二次解析。
/// 5. **鉴权失败形态不同**：
///    - biji → HTTP **401** + `{ok:false,error:{...}}`
///    - amap → HTTP **200**(!) + 裸错误 `{"status":"0","info":"INVALID_USER_KEY"}`
///    ⇒ **绝不能只看 HTTP 状态码**，必须解析 body。
const String kMcpBrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// 外部 MCP 服务器的单个工具
class ExternalMcpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const ExternalMcpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory ExternalMcpTool.fromJson(Map<String, dynamic> j) => ExternalMcpTool(
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        inputSchema: j['inputSchema'] is Map
            ? Map<String, dynamic>.from(j['inputSchema'] as Map)
            : <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{},
              },
      );
}

/// 探测（initialize + tools/list）结果
class McpProbeResult {
  final bool ok;
  final String serverName;
  final List<ExternalMcpTool> tools;
  final String? error;

  const McpProbeResult({
    required this.ok,
    this.serverName = '',
    this.tools = const <ExternalMcpTool>[],
    this.error,
  });

  int get toolCount => tools.length;
}

class ExternalMcpClient {
  final String url;
  final Map<String, String> extraHeaders;
  final Duration timeout;

  ExternalMcpClient({
    required this.url,
    Map<String, String>? headers,
    this.timeout = const Duration(seconds: 15),
  }) : extraHeaders = headers ?? const <String, String>{};

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'User-Agent': kMcpBrowserUserAgent,
      }..addAll(extraHeaders);

  Future<http.Response> _post(Object body) =>
      http.post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);

  /// 解码响应体：兼容纯 JSON（两服务器实测）与 SSE 分帧（防御）
  dynamic _decode(String body) {
    final t = body.trimLeft();
    if (t.startsWith('event:') || t.startsWith('data:')) {
      final data = t
          .split('\n')
          .where((l) => l.startsWith('data:'))
          .map((l) => l.substring(5).trim())
          .join('\n');
      return jsonDecode(data);
    }
    return jsonDecode(t);
  }

  /// amap 的 key 错误是 HTTP 200 + body 内的裸错误；biji 的 401 body 也是非信封格式。
  /// 返回 null 表示未发现鉴权错误。
  String? _authErrorFromBody(String body) {
    if (body.trimLeft().startsWith('{') == false) return null;
    try {
      final j = _decode(body);
      if (j is! Map) return null;
      final map = Map<String, dynamic>.from(j);
      // amap：{"status":"0","info":"INVALID_USER_KEY","infocode":"10001"}
      if (map['status']?.toString() == '0') {
        return '鉴权失败（${map['info'] ?? '未知'}）：请检查 key/凭证是否正确';
      }
      // biji：{"ok":false,"error":{"code":"unauthorized","message":"..."}}
      if (map['ok'] == false) {
        final e = map['error'];
        final msg = (e is Map ? (e['message'] ?? e['code']) : e)?.toString();
        return '鉴权失败：${msg ?? '未知'}';
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _short(String s) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length <= 160 ? t : '${t.substring(0, 160)}…';
  }

  /// 探测：initialize（拿 serverInfo）+ notifications/initialized + tools/list
  Future<McpProbeResult> probe() async {
    try {
      final init = await _post({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': const <String, dynamic>{},
          'clientInfo': const {'name': 'xiaole-app', 'version': '1.0.0'},
        },
      });
      if (init.statusCode == 401 || init.statusCode == 403) {
        return McpProbeResult(
            ok: false,
            error: '凭证无效或被拒绝（HTTP ${init.statusCode}）：${_short(init.body)}');
      }
      final ae = _authErrorFromBody(init.body);
      if (ae != null) return McpProbeResult(ok: false, error: ae);

      String serverName = '';
      try {
        final j = _decode(init.body);
        if (j is Map) {
          // 注意：Dart 没有 ?[] 空安全下标运算符，须逐层判空
          final res0 = j['result'];
          final si = (res0 is Map) ? res0['serverInfo'] : null;
          if (si is Map) serverName = (si['name'] ?? '').toString();
        }
      } catch (_) {}

      // 无状态服务器不要求该通知，发出无害
      try {
        await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
      } catch (_) {}

      final listResp = await _post({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': const <String, dynamic>{},
      });
      if (listResp.statusCode == 401 || listResp.statusCode == 403) {
        return McpProbeResult(
            ok: false,
            error:
                '凭证无效或被拒绝（HTTP ${listResp.statusCode}）：${_short(listResp.body)}');
      }
      final ae2 = _authErrorFromBody(listResp.body);
      if (ae2 != null) return McpProbeResult(ok: false, error: ae2);

      final j = _decode(listResp.body);
      if (j is Map && j['error'] != null) {
        final e = j['error'];
        final msg = (e is Map ? (e['message'] ?? '') : e).toString();
        return McpProbeResult(ok: false, error: '协议错误：$msg');
      }
      // 同上：Dart 无 ?[] 运算符，逐层判空
      final res = (j is Map) ? j['result'] : null;
      final raw = (res is Map) ? res['tools'] : null;
      if (raw is! List) {
        return McpProbeResult(ok: false, error: '响应中没有 tools 列表');
      }
      final tools = raw
          .whereType<Map>()
          .map((e) => ExternalMcpTool.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.name.isNotEmpty)
          .toList();
      return McpProbeResult(ok: true, serverName: serverName, tools: tools);
    } on TimeoutException {
      return const McpProbeResult(ok: false, error: '连接超时');
    } catch (e) {
      return McpProbeResult(ok: false, error: '连接失败：$e');
    }
  }

  /// 调用工具：返回**文本结果**（失败也返回可读文本，绝不抛异常）
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    try {
      final r = await _post({
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch % 1000000,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      });
      if (r.statusCode == 401 || r.statusCode == 403) {
        return '调用失败：凭证无效或被拒绝（HTTP ${r.statusCode}）';
      }
      final ae = _authErrorFromBody(r.body);
      if (ae != null) return '调用失败：$ae';

      final j = _decode(r.body);
      if (j is Map) {
        if (j['error'] != null) {
          final e = j['error'];
          final msg = (e is Map ? (e['message'] ?? '') : e).toString();
          return '调用失败：$msg';
        }
        final res = j['result'];
        if (res is Map) {
          final content = res['content'];
          if (content is List && content.isNotEmpty) {
            final first = content.first;
            if (first is Map && first['text'] != null) {
              final text = first['text'].toString();
              // 业务错误：isError 为真时原文已含原因
              if (res['isError'] == true) return '调用失败：$text';
              return text;
            }
          }
          return jsonEncode(res);
        }
      }
      return r.body;
    } on TimeoutException {
      return '调用失败：超时';
    } catch (e) {
      return '调用失败：$e';
    }
  }
}
