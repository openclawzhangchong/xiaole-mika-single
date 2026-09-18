import 'package:flutter/material.dart';

import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_text_styles.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_dimens.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';

import '../../core/proactive/proactive_script_store.dart';
import '../widgets/wx_cell.dart';
import '../widgets/wx_cell_group.dart';
import '../widgets/wx_dialog.dart';
import '../widgets/wx_empty.dart';

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

  InputDecoration _wxInput(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: '例：读巡检口令执行',
      helperText: '≤16 字（该通道硬上限）',
      filled: true,
      fillColor: isDark ? AppColors.inputBackgroundDark : AppColors.inputBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        borderSide: BorderSide(
          color: isDark ? AppColors.inputBorderDark : AppColors.inputBorder,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        borderSide: BorderSide(
          color: isDark ? AppColors.inputBorderDark : AppColors.inputBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  Future<void> _addOrEdit({ProactiveScript? existing}) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    final saved = await showWxDialog(
      context,
      title: existing == null ? '新增巡检口令' : '编辑巡检口令',
      confirmText: '保存',
      contentWidget: TextField(
        controller: ctrl,
        maxLength: maxChars,
        autofocus: true,
        decoration: _wxInput(context),
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
    final ok = await showWxDialog(
      context,
      title: '删除确认',
      content: '确定删除「${s.text}」？',
      confirmText: '删除',
    );
    if (ok != true) return;
    await ProactiveScriptStore.remove(s.id);
    await _refresh();
    if (mounted) ToastUtil.show('已删除');
  }

  Future<void> _restoreDefaults() async {
    final ok = await showWxDialog(
      context,
      title: '恢复默认口令',
      content: '将恢复 4 条内置口令，并把第 1 条设为当前。你自定义的口令会被覆盖。',
      confirmText: '恢复',
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
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapLg,
              AppDimens.pagePadding,
              AppDimens.gapSm,
            ),
            child: Text(
              '多条轮换使用（每轮自动换一条），提高"不被记忆固化"的成功率。'
              '单条 ≤$maxChars 字——巡检口令经 listen/detect 通道发出，该通道有硬性长度上限。',
              style: AppTextStyles.caption.copyWith(
                color: AppTextStyles.secondaryText(context),
              ),
            ),
          ),
          const Divider(height: AppDimens.hairline),
          if (scripts.isEmpty)
            WxEmpty(
              icon: Icons.inbox_outlined,
              title: '还没有口令',
              description: '点右上角 + 新增',
              actionLabel: '新增',
              onAction: () => _addOrEdit(),
            )
          else
            WxCellGroup(
              children: scripts.asMap().entries.map((e) {
                final index = e.key;
                final s = e.value;
                final isActive = s.id == activeId;
                final isLast = index == scripts.length - 1;
                return WxCell(
                  leading: Icon(
                    isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isActive
                        ? AppColors.primary
                        : AppTextStyles.secondaryText(context),
                  ),
                  title: s.text,
                  subtitle: isActive ? '当前使用' : '点击设为当前',
                  showDivider: !isLast,
                  onTap: () async {
                    await ProactiveScriptStore.setActive(s.id);
                    await _refresh();
                  },
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
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
