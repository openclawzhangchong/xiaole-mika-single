import 'package:flutter_test/flutter_test.dart';

import 'package:xiaozhi_client_flutter/core/mcp/external_mcp_builtin.dart';
import 'package:xiaozhi_client_flutter/core/mcp/external_mcp_client.dart';
import 'package:xiaozhi_client_flutter/core/mcp/external_mcp_manager.dart';
import 'package:xiaozhi_client_flutter/core/mcp/external_mcp_store.dart';

/// 测试替身：不发真实网络，直接返回预置结果
class _StubClient extends ExternalMcpClient {
  final McpProbeResult probeResult;
  final Map<String, String> callResults;

  _StubClient({
    required super.url,
    required this.probeResult,
    this.callResults = const <String, String>{},
  });

  @override
  Future<McpProbeResult> probe() async => probeResult;

  @override
  Future<String> callTool(String name, Map<String, dynamic> args) async =>
      callResults[name] ?? '调用失败：未预设 $name';
}

ExternalMcpTool _tool(String name, [String desc = '']) =>
    ExternalMcpTool(name: name, description: desc, inputSchema: const {});

ExternalMcpServer _server({
  required String id,
  required String prefix,
  bool enabled = true,
  List<String> disabledTools = const <String>[],
}) =>
    ExternalMcpServer(
      id: id,
      name: id,
      prefix: prefix,
      url: 'https://example.com/mcp',
      enabled: enabled,
      disabledTools: disabledTools,
    );

void main() {
  group('ExternalMcpServer.derivePrefix', () {
    test('取首段并清洗', () {
      expect(ExternalMcpServer.derivePrefix('biji-notes'), 'biji');
      expect(ExternalMcpServer.derivePrefix('amap-maps-streamableHTTP'), 'amap');
      expect(ExternalMcpServer.derivePrefix('My_MCP 01'), 'my');
      expect(ExternalMcpServer.derivePrefix('!!!'), 'mcp');
    });
  });

  group('parseMcpServersJson', () {
    test('解析标准 mcpServers 片段（含 headers）', () {
      const json = '''
      {"mcpServers":{"biji-notes":{"type":"streamable_http",
       "url":"https://x.dev/api/mcp/rpc",
       "headers":{"Authorization":"Bearer abc"}}}}
      ''';
      final list = ExternalMcpManager.parseMcpServersJson(json);
      expect(list.length, 1);
      expect(list.first.name, 'biji-notes');
      expect(list.first.url, 'https://x.dev/api/mcp/rpc');
      expect(list.first.headers['Authorization'], 'Bearer abc');
      expect(list.first.prefix, 'biji');
      expect(list.first.enabled, true);
    });

    test('解析 amap 形态（key 拼在 url 上）', () {
      const json = '{"mcpServers":{"amap-maps":{"url":"https://mcp.amap.com/mcp?key=K"}}}';
      final s = ExternalMcpManager.parseMcpServersJson(json).first;
      expect(s.url, contains('key=K'));
      expect(s.prefix, 'amap');
      expect(s.headers, isEmpty);
    });

    test('非法输入抛 FormatException', () {
      expect(() => ExternalMcpManager.parseMcpServersJson(''),
          throwsA(isA<FormatException>()));
      expect(() => ExternalMcpManager.parseMcpServersJson('[1,2,3]'),
          throwsA(isA<FormatException>()));
      expect(() => ExternalMcpManager.parseMcpServersJson('{"a":{}}'),
          throwsA(isA<FormatException>()));
    });
  });

  group('ExternalMcpManager 合并与转发（stub 客户端）', () {
    late _StubClient stub;

    setUp(() async {
      // 先 init 置 _inited=true，之后 refreshAll() 不会再清空我们手动设置的 servers
      await ExternalMcpManager.instance.init();
      stub = _StubClient(
        url: 'https://example.com/mcp',
        probeResult: McpProbeResult(
          ok: true,
          serverName: 'stub',
          tools: <ExternalMcpTool>[
            _tool('search_notes', '搜索笔记'),
            _tool('add_note', '记笔记'),
            _tool('merge_notes', '合并（会删数据）'),
          ],
        ),
        callResults: const <String, String>{
          'search_notes': '找到 3 条笔记…',
          'add_note': '调用失败：缺少参数',
        },
      );
      ExternalMcpManager.instance.clientFactory = (_) => stub;
    });

    tearDown(() {
      ExternalMcpManager.instance.clientFactory = null;
      ExternalMcpManager.instance.servers.clear();
    });

    Future<void> setServers(List<ExternalMcpServer> list) async {
      ExternalMcpManager.instance.servers
        ..clear()
        ..addAll(list);
      await ExternalMcpManager.instance.refreshAll();
    }

    test('工具名加前缀后合并下发', () async {
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      final names =
          ExternalMcpManager.instance.mergedTools().map((t) => t.name).toList();
      expect(names, <String>[
        'notes.search_notes',
        'notes.add_note',
        'notes.merge_notes',
      ]);
    });

    test('逐工具关闭后被剔除', () async {
      await setServers(<ExternalMcpServer>[
        _server(id: 'a', prefix: 'notes', disabledTools: <String>['merge_notes']),
      ]);
      final names =
          ExternalMcpManager.instance.mergedTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notes.merge_notes')));
      expect(names, contains('notes.search_notes'));
    });

    test('整台停用时不下发任何工具', () async {
      await setServers(<ExternalMcpServer>[
        _server(id: 'a', prefix: 'notes', enabled: false),
      ]);
      expect(ExternalMcpManager.instance.mergedTools(), isEmpty);
    });

    test('探测失败的服务器不下发工具', () async {
      stub = _StubClient(
        url: 'https://example.com/mcp',
        probeResult: const McpProbeResult(ok: false, error: '鉴权失败'),
      );
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      expect(ExternalMcpManager.instance.mergedTools(), isEmpty);
      expect(ExternalMcpManager.instance.statusOf('a')?.error, '鉴权失败');
    });

    test('isExternal 按前缀判定', () async {
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      expect(ExternalMcpManager.instance.isExternal('notes.search_notes'), isTrue);
      expect(ExternalMcpManager.instance.isExternal('amap.maps_geo'), isFalse);
      expect(ExternalMcpManager.instance.isExternal('self.audio_speaker.set_volume'),
          isFalse);
    });

    test('dispatch 成功转发并返回文本', () async {
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      final r = await ExternalMcpManager.instance
          .dispatch('notes.search_notes', <String, dynamic>{'query': '笔记'});
      expect(r['success'], true);
      expect(r['text'], '找到 3 条笔记…');
    });

    test('dispatch 业务失败（isError 文案以调用失败开头）转为 success=false', () async {
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      final r = await ExternalMcpManager.instance
          .dispatch('notes.add_note', <String, dynamic>{});
      expect(r['success'], false);
      expect(r['message'], contains('调用失败'));
    });

    test('dispatch 被关闭的工具直接拒绝', () async {
      await setServers(<ExternalMcpServer>[
        _server(id: 'a', prefix: 'notes', disabledTools: <String>['merge_notes']),
      ]);
      final r = await ExternalMcpManager.instance
          .dispatch('notes.merge_notes', <String, dynamic>{});
      expect(r['success'], false);
      expect(r['message'], '该外部工具已被关闭');
    });

    test('dispatch 非外部工具返回失败', () async {
      await setServers(<ExternalMcpServer>[_server(id: 'a', prefix: 'notes')]);
      final r = await ExternalMcpManager.instance
          .dispatch('self.reboot', <String, dynamic>{});
      expect(r['success'], false);
      expect(r['message'], '未找到该外部工具');
    });
  });

  group('内置预置（v6.4.1）', () {
    test('预置两条，前缀固定为 notes / amap', () {
      final p = ExternalMcpBuiltin.presets;
      expect(p.length, 2);
      expect(p.map((e) => e.prefix).toList(), <String>['notes', 'amap']);
      expect(p.first.url, contains('zhangchong-biji-web.pages.dev'));
      expect(p.first.headers['Authorization'], startsWith('Bearer '));
      expect(p.last.url, contains('mcp.amap.com'));
      expect(p.every((e) => e.enabled), true);
    });

    test('restoreBuiltins 会补齐且不重复添加', () async {
      await ExternalMcpManager.instance.init();
      ExternalMcpManager.instance.clientFactory = (_) => _StubClient(
            url: 'https://example.com/mcp',
            probeResult: McpProbeResult(
                ok: true, tools: <ExternalMcpTool>[_tool('search_notes')]),
          );
      ExternalMcpManager.instance.servers.clear();

      expect(await ExternalMcpManager.instance.restoreBuiltins(), 2);
      expect(await ExternalMcpManager.instance.restoreBuiltins(), 0);
      expect(ExternalMcpManager.instance.servers.length, 2);

      ExternalMcpManager.instance.clientFactory = null;
      ExternalMcpManager.instance.servers.clear();
    });
  });
}
