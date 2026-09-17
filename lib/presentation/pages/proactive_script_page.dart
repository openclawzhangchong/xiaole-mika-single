import 'package:flutter/material.dart';

import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';

import '../../core/proactive/proactive_script_store.dart';

/// v6.5.0：巡检口令管理页（方案 D —— 口令存本地，由设备 MCP 工具 self.proactive.get_script 取回）
/// ------------------------------------------------------------------
/// - 多条口令**轮换使用**（每轮自动换一条），对抗服务器"同一指令只执行一次"的长期记忆；
/// - 支持增 / 删 / 改 / 启用停用 / 设为当前 / 恢复默认；
/// - 单条文本**限制 ≤16 字**：因为轮换口令最终经 `listen/detect` 通道发出，该通道硬上限约 16 字。
class ProactiveScriptPage extends StatefulWidget {
  const ProactiveScriptPage({super.key});

  @override
  State<ProactiveScriptPage> createState() => _ProactiveScriptPageState();
}

class _ProactiveScriptPageState extends State<ProactiveScriptPage> {
  static const int maxChars = 16;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await ProactiveScriptStore.init();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await ProactiveScriptStore.init();
    if (mounted) setState(() {});
  }

  Future<void> _addOrEdit({ProactiveScript? existing}) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '新增巡检口令' : '编辑巡检口令'),
        content: TextField(
          controller: ctrl,
          maxLength: maxChars,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例：读巡检口令执行',
            helperText: '≤16 字（该通道硬上限）',
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

    final text = ctrl.text.trim();
    if (text.isEmpty) {
      ToastUtil.show('口令不能为空');
      return;
    }
    if (text.characters.length > maxChars) {
      ToastUtil.show('最多 $maxChars 字，请缩短');
      return;
    }
    if (existing == null) {
      await ProactiveScriptStore.add(text);
    } else {
      await ProactiveScriptStore.update(existing.id, text: text);
    }
    await _refresh();
    if (mounted) ToastUtil.show(existing == null ? '已新增' : '已保存');
  }

  Future<void> _confirmDelete(ProactiveScript s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除「${s.text}」？'),
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
    await ProactiveScriptStore.remove(s.id);
    await _refresh();
    if (mounted) ToastUtil.show('已删除');
  }

  Future<void> _restoreDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认口令'),
        content: const Text('将恢复 4 条内置口令，并把第 1 条设为当前。你自定义的口令会被覆盖。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true) return;
    await ProactiveScriptStore.restoreDefaults();
    await _refresh();
    if (mounted) ToastUtil.show('已恢复默认');
  }

  @override
  Widget build(BuildContext context) {
    final scripts = ProactiveScriptStore.scripts;
    final activeId = ProactiveScriptStore.active?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('巡检口令'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restore),
            onPressed: _restoreDefaults,
          ),
          IconButton(
            tooltip: '新增',
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '多条轮换使用（每轮自动换一条），提高"不被记忆固化"的成功率。'
              '单条 ≤$maxChars 字——巡检口令经 listen/detect 通道发出，该通道有硬性长度上限。',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 1),
          if (scripts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有口令，点右上角 + 新增')),
            ),
          ...scripts.map((s) {
            final isActive = s.id == activeId;
            return ListTile(
              leading: Icon(
                isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              title: Text(s.text),
              subtitle: Text(isActive ? '当前使用' : '点击设为当前',
                  style: const TextStyle(fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: s.enabled,
                    activeColor: AppColors.primary,
                    onChanged: (v) async {
                      await ProactiveScriptStore.update(s.id, enabled: v);
                      await _refresh();
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _addOrEdit(existing: s);
                      if (v == 'delete') _confirmDelete(s);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              onTap: () async {
                await ProactiveScriptStore.setActive(s.id);
                await _refresh();
              },
            );
          }),
        ],
      ),
    );
  }
}
