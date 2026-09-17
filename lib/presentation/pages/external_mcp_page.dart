import 'package:flutter/material.dart';

import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';

import '../../core/mcp/external_mcp_client.dart';
import '../../core/mcp/external_mcp_manager.dart';
import '../../core/mcp/external_mcp_store.dart';

/// v6.4.0：外部 MCP 服务器管理页
/// ------------------------------------------------------------------
/// - 列表展示已配置服务器（名称/地址/连接状态与工具数）
/// - 整台启用开关；点进可**逐工具开关**
/// - 支持「粘贴 JSON 导入」（`{"mcpServers":{...}}`）与「手动添加」
/// - 支持编辑、删除（二次确认）、手动刷新探测
///
/// 安全约定：会写/删数据的工具在 UI 上标注；其中 `merge_notes`（合并会删数据）
/// 在首次探测成功后**默认关闭**。
class ExternalMcpPage extends StatefulWidget {
  const ExternalMcpPage({super.key});

  @override
  State<ExternalMcpPage> createState() => _ExternalMcpPageState();
}

/// 会写入或删除数据的工具（UI 上标注）
const Set<String> kWriteTools = <String>{
  'add_note',
  'save_kb_doc',
  'merge_notes',
};

/// 默认关闭的破坏性工具
const String kDefaultDisabledTool = 'merge_notes';

class _ExternalMcpPageState extends State<ExternalMcpPage> {
  bool _loading = true;
  bool _refreshing = false;
  final _pasteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await ExternalMcpManager.instance.init();
    await _refresh();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ExternalMcpManager.instance.refreshAll();
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  Future<void> _persist() => ExternalMcpManager.instance.save();

  /// 探测成功后把破坏性工具（merge_notes）默认关闭。
  /// 逻辑统一放在 manager，供新增、导入、预置三条路径共用。
  Future<void> _applyDefaultDisabled() =>
      ExternalMcpManager.instance.applyDefaultDisabled();

  /// v6.4.1：重新载入缺失的预置（笔记 + 高德），按 id 去重
  Future<void> _restoreBuiltins() async {
    final n = await ExternalMcpManager.instance.restoreBuiltins();
    if (!mounted) return;
    setState(() {});
    ToastUtil.show(n == 0 ? '预置已全部存在' : '已恢复 $n 台预置');
  }

  Future<void> _showAddSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste_go),
              title: const Text('粘贴 JSON 导入'),
              subtitle: const Text('支持 {"mcpServers":{...}} 片段'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('手动填写'),
              subtitle: const Text('名称 / 前缀 / 地址 / 请求头'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'paste') await _showPasteDialog();
    if (choice == 'manual') await _showEditDialog(null);
  }

  Future<void> _showPasteDialog() async {
    _pasteCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴 MCP 配置'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _pasteCtrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '{\n  "mcpServers": {\n    "biji-notes": {\n'
                  '      "type": "streamable_http",\n      "url": "https://...",\n'
                  '      "headers": {"Authorization": "Bearer ..."}\n    }\n  }\n}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final parsed = ExternalMcpManager.parseMcpServersJson(_pasteCtrl.text);
      ExternalMcpManager.instance.servers.addAll(parsed);
      await _persist();
      await _refresh();
      await _applyDefaultDisabled();
      if (!mounted) return;
      setState(() {});
      ToastUtil.show('已导入 ${parsed.length} 台');
    } catch (e) {
      if (!mounted) return;
      ToastUtil.show('导入失败：$e');
    }
  }

  Future<void> _showEditDialog(ExternalMcpServer? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final prefixCtrl = TextEditingController(text: existing?.prefix ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final headersCtrl = TextEditingController(
      text: (existing?.headers ?? const <String, String>{})
          .entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名称')),
              TextField(
                controller: prefixCtrl,
                decoration: const InputDecoration(
                    labelText: '工具名前缀', hintText: '如 notes / amap'),
              ),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                    labelText: '地址 URL', hintText: 'https://...'),
              ),
              TextField(
                controller: headersCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '请求头（每行一条 Key: Value）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved != true) return;

    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      ToastUtil.show('地址不能为空');
      return;
    }
    final headers = <String, String>{};
    for (final line in headersCtrl.text.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (k.isNotEmpty) headers[k] = v;
    }
    final name = nameCtrl.text.trim().isEmpty
        ? (Uri.tryParse(url)?.host ?? 'mcp')
        : nameCtrl.text.trim();
    final prefix = prefixCtrl.text.trim().isEmpty
        ? ExternalMcpServer.derivePrefix(name)
        : prefixCtrl.text.trim();

    final list = ExternalMcpManager.instance.servers;
    if (existing == null) {
      final s = ExternalMcpServer(
        id: 'mcp_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        prefix: prefix,
        url: url,
        headers: headers,
      );
      list.add(s);
      await _persist();
      await _refresh();
      await _applyDefaultDisabled();
    } else {
      final idx = list.indexWhere((e) => e.id == existing.id);
      if (idx >= 0) {
        list[idx] = existing.copyWith(
            name: name, prefix: prefix, url: url, headers: headers);
      }
      await _persist();
      await _refresh();
    }
    if (!mounted) return;
    setState(() {});
    ToastUtil.show(existing == null ? '已添加' : '已保存');
  }

  Future<void> _confirmDelete(ExternalMcpServer s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除「${s.name}」？该配置仅保存在本机。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    ExternalMcpManager.instance.servers.removeWhere((e) => e.id == s.id);
    await _persist();
    if (!mounted) return;
    setState(() {});
    ToastUtil.show('已删除');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final servers = ExternalMcpManager.instance.servers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('外部 MCP'),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet),
          // v6.4.1：预置被删掉后可在此重新载入（笔记 + 高德）
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'restore') _restoreBuiltins();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'restore', child: Text('恢复预置（笔记/高德）')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : servers.isEmpty
              ? _buildEmpty(isDark)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: servers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _buildTile(servers[i], isDark),
                ),
    );
  }

  Widget _buildEmpty(bool isDark) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_outlined,
                  size: 56,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text('还没有外部 MCP 服务器'),
              const SizedBox(height: 6),
              Text(
                '点右上角 + 添加，或直接粘贴配置 JSON',
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_for_offline),
                label: const Text('载入预置（笔记 + 高德）'),
                onPressed: _restoreBuiltins,
              ),
            ],
          ),
        ),
      );

  Widget _buildTile(ExternalMcpServer s, bool isDark) {
    final pr = ExternalMcpManager.instance.statusOf(s.id);
    final online = s.enabled && pr != null && pr.ok;
    // v6.9.0：列表上直接显示「已启用几个 / 共几个」，不必点进去才知道能逐工具管理
    final enabledToolCount = pr == null
        ? 0
        : pr.tools.where((t) => !s.disabledTools.contains(t.name)).length;
    final statusText = !s.enabled
        ? '已停用'
        : (pr == null
            ? '未探测'
            : pr.ok
                ? '在线 · 已启用 $enabledToolCount/${pr.tools.length} 个工具'
                : '连接失败：${pr.error ?? '未知'}');
    final statusColor = online ? AppColors.statusOnline : AppColors.textSecondary;

    return ListTile(
      leading: Icon(Icons.hub,
          color: online
              ? AppColors.primary
              : (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary)),
      title: Text('${s.name}  ·  ${s.prefix}.*'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: s.enabled,
            activeColor: AppColors.primary,
            onChanged: (v) async {
              final idx = ExternalMcpManager.instance.servers
                  .indexWhere((e) => e.id == s.id);
              if (idx >= 0) {
                ExternalMcpManager.instance.servers[idx] =
                    s.copyWith(enabled: v);
              }
              await _persist();
              await _refresh();
              if (!mounted) return;
              setState(() {});
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _showEditDialog(s);
              if (v == 'delete') _confirmDelete(s);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _ExternalMcpToolsPage(server: s)),
        );
      },
    );
  }
}

/// 单台服务器的**逐工具开关**页
class _ExternalMcpToolsPage extends StatefulWidget {
  final ExternalMcpServer server;
  const _ExternalMcpToolsPage({required this.server});

  @override
  State<_ExternalMcpToolsPage> createState() => _ExternalMcpToolsPageState();
}

class _ExternalMcpToolsPageState extends State<_ExternalMcpToolsPage> {
  ExternalMcpServer get _current {
    final list = ExternalMcpManager.instance.servers;
    final i = list.indexWhere((e) => e.id == widget.server.id);
    return i >= 0 ? list[i] : widget.server;
  }

  Future<void> _toggle(String rawName, bool enable) async {
    final s = _current;
    final next = List<String>.from(s.disabledTools);
    if (enable) {
      next.remove(rawName);
    } else if (!next.contains(rawName)) {
      next.add(rawName);
    }
    final idx =
        ExternalMcpManager.instance.servers.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      ExternalMcpManager.instance.servers[idx] =
          s.copyWith(disabledTools: next);
    }
    await ExternalMcpManager.instance.save();
    if (!mounted) return;
    setState(() {});
  }

  /// v6.9.0：批量开关。
  /// - 全部关闭（enable=false）→ 把**当前在线的全部工具名**写进 disabledTools
  /// - 全部开启（enable=true） → 清空 disabledTools
  /// 适用场景：一个外部 MCP 有几十上百个工具，只想挑一两个用 ——
  /// 先「全部关闭」再逐个开，比挨个关掉几十个快得多。
  Future<void> _toggleAll(bool enable) async {
    final s = _current;
    final pr = ExternalMcpManager.instance.statusOf(s.id);
    final List<String> next;
    if (enable) {
      next = <String>[];
    } else {
      next = (pr?.tools ?? const <ExternalMcpTool>[])
          .map((t) => t.name)
          .toList();
    }
    final idx =
        ExternalMcpManager.instance.servers.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      ExternalMcpManager.instance.servers[idx] =
          s.copyWith(disabledTools: next);
    }
    await ExternalMcpManager.instance.save();
    if (!mounted) return;
    setState(() {});
    ToastUtil.show(enable ? '已全部开启' : '已全部关闭（可再逐个挑要用的）');
  }

  @override
  Widget build(BuildContext context) {
    final s = _current;
    final pr = ExternalMcpManager.instance.statusOf(s.id);
    final tools = pr?.tools ?? const <ExternalMcpTool>[];
    final enabledCount =
        tools.where((t) => !s.disabledTools.contains(t.name)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${s.name} 的工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await ExternalMcpManager.instance.refreshAll();
              if (!mounted) return;
              setState(() {});
            },
          ),
          // v6.9.0：批量开关（工具多时「先全关再挑」远快于逐个关）
          if (tools.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'off') _toggleAll(false);
                if (v == 'on') _toggleAll(true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'off', child: Text('全部关闭')),
                PopupMenuItem(value: 'on', child: Text('全部开启')),
              ],
            ),
        ],
      ),
      body: tools.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(pr == null
                    ? '尚未探测到工具，点右上角刷新'
                    : '连接失败：${pr.error ?? '未知'}'),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '工具名前缀：${s.prefix}.  （暴露给 AI 的名称如 '
                        '${s.prefix}.${tools.first.name}）',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      // v6.9.0：让「启用多少 / 一共多少」一目了然，并提示可批量
                      Text(
                        '已启用 $enabledCount / 共 ${tools.length} 个'
                        '；关闭的工具不会下发给 AI。工具很多时可先「全部关闭」'
                        '（右上角 ⋮）再挑要用的。',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ...tools.map((t) {
                  final disabled = s.disabledTools.contains(t.name);
                  final isWrite = kWriteTools.contains(t.name);
                  return SwitchListTile(
                    value: !disabled,
                    activeColor: AppColors.primary,
                    title: Text(t.name),
                    subtitle: Text(
                      t.description.isEmpty ? '（无描述）' : t.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: isWrite
                        ? const Icon(Icons.warning_amber_rounded, size: 20)
                        : null,
                    onChanged: s.enabled ? (v) => _toggle(t.name, v) : null,
                  );
                }),
              ],
            ),
    );
  }
}
