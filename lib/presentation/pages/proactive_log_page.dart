import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';
import 'package:xiaozhi_client_flutter/core/proactive/proactive_round_log.dart';

/// v6.8.3：AI 主动联系 · 电话日志（诊断用）
/// ------------------------------------------------------------
/// 开发者中心「📞 电话日志」入口页。结构化展示最近 [ProactiveRoundLog.maxRounds]
/// 轮巡检的完整过程（含被守卫跳过的轮次及其具体原因），支持「一键复制全部」纯文本
/// 直接贴给 AI 诊断。
///
/// 数据来自 [ProactiveRoundLog]（旁路记录层，不改动任何巡检行为）。
/// UI 语言保持与「巡检口令」页一致（AppBar + ListView + 卡片）。
class ProactiveLogPage extends StatefulWidget {
  const ProactiveLogPage({super.key});

  @override
  State<ProactiveLogPage> createState() => _ProactiveLogPageState();
}

class _ProactiveLogPageState extends State<ProactiveLogPage> {
  List<ProactiveRoundLogEntry> _list = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // 持久化历史是异步加载的（App 重启后日志仍在）——必须等它读完再渲染，
    // 否则首帧会是"空列表"且不会自动刷新。
    await ProactiveRoundLog.load();
    if (!mounted) return;
    // entries 按时间正序；展示时最新一条置顶
    setState(() {
      _list = ProactiveRoundLog.entries.reversed.toList();
    });
  }

  Future<void> _copyAll() async {
    try {
      final text = ProactiveRoundLog.toPlainText();
      if (text == '（暂无巡检记录）') {
        ToastUtil.show('暂无巡检记录，请先复现一轮巡检');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ToastUtil.show('已复制 ${ProactiveRoundLog.length} 轮日志');
    } catch (e) {
      if (!mounted) return;
      ToastUtil.show('复制失败：$e');
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空电话日志'),
        content: const Text('将删除全部巡检记录（含已跳过轮次），此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ProactiveRoundLog.clear();
    unawaited(_load());
    if (!mounted) return;
    ToastUtil.show('已清空');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('电话日志'),
        actions: [
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: _list.isEmpty ? null : _clear,
          ),
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy),
            onPressed: _copyAll,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '每轮 AI 主动联系巡检的完整过程（含被守卫跳过的轮次）。'
              '保留最近 ${ProactiveRoundLog.maxRounds} 轮，App 重启后仍在。'
              '点右上角「复制全部」可整段贴给 AI 诊断。',
              style: TextStyle(fontSize: 12, color: sub),
            ),
          ),
          const Divider(height: 1),
          if (_list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('还没有巡检记录，开启「AI 主动联系」后跑一轮即可看到'),
              ),
            ),
          ..._list.map((e) => _buildCard(e, prim, sub)),
        ],
      ),
    );
  }

  Widget _buildCard(ProactiveRoundLogEntry e, Color prim, Color sub) {
    final isSkip = e.decision == 'skip';
    final label = isSkip ? '跳过' : _decisionLabel(e);
    // 跳过用深琥珀（AppColors.warning 的黄色在浅色底上做文字对比度不足，读不清）
    final accent = isSkip
        ? const Color(0xFFB25E00)
        : (e.triggerCalled ? AppColors.primary : AppColors.info);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.surfaceDark
          : AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _fmt(e.time),
                  style: TextStyle(fontSize: 12, color: sub),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isSkip) ...[
              _row('跳过原因', e.skipReason ?? '未知', prim, sub),
              if (e.source != null) _row('来源', e.source!, prim, sub),
            ] else ...[
              _row('结束原因', e.endReason ?? '—', prim, sub),
              if (e.commands.isEmpty)
                _row('口令', '—', prim, sub)
              else
                for (var k = 0; k < e.commands.length; k++)
                  _row(
                    k == 0 ? '口令' : '口令${k + 1}(重发)',
                    e.commands[k],
                    prim,
                    sub,
                  ),
              _row('get_script 调用', e.getScriptCalled ? '是' : '否', prim, sub),
              _row('trigger_call', e.triggerCalled ? '是' : '否', prim, sub),
              _row('skip', e.skipCalled ? '是' : '否', prim, sub),
              _row('开场白', e.opening ?? '—', prim, sub),
              _row('本轮耗时', '${e.durationMs} ms', prim, sub),
              _row('close code', e.closeCode ?? '—', prim, sub),
              _row('服务器 alert', e.alert ?? '—', prim, sub),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, Color prim, Color sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: TextStyle(fontSize: 13, color: sub)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(fontSize: 13, color: prim),
            ),
          ),
        ],
      ),
    );
  }

  /// 判定标签（与 `ProactiveRoundLog._decisionLabel` 保持同一口径）
  String _decisionLabel(ProactiveRoundLogEntry e) {
    if (e.triggerCalled) return '触发来电';
    if (e.skipCalled) return '静默';
    if (e.endReason == 'timeout') return '超时';
    if (e.endReason == 'stop') return '被停止';
    return '巡检轮';
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
