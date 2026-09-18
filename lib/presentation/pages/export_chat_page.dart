import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';
import '../services/chat_export_service.dart';
import '../widgets/wx_icon_button.dart';

/// v4.3.0：导出本地聊天记录（方案模块三，完全对齐网页版 v1.3.1 规格）。
/// 范围（全部/单选智能体）+ 格式（TXT/JSON）+ 起止日期过滤 + 统计；
/// 生成文件后交系统分享面板（share_plus），可存微信/文件管理器/发电脑。
class ExportChatPage extends StatefulWidget {
  const ExportChatPage({super.key});

  @override
  State<ExportChatPage> createState() => _ExportChatPageState();
}

class _ExportChatPageState extends State<ExportChatPage> {
  String _scope = 'all';
  String _fmt = 'json'; // 默认 JSON（对齐网页版）
  DateTime? _from;
  DateTime? _to;
  bool _busy = false;
  String _statText = '统计中…';
  List<({String id, String name})> _agents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  InputDecoration _wxInput(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: '导出范围',
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

  Future<void> _load() async {
    final (agents, _) = await ChatExportService.readLocal();
    final st = await ChatExportService.stats();
    if (!mounted) return;
    setState(() {
      _agents = agents.map((a) => (id: a.id, name: a.name)).toList();
      _statText = '当前共 ${st.agentCount} 个智能体 · ${st.msgCount} 条消息';
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      helpText: isFrom ? '选择开始日期' : '选择结束日期',
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  String _fmtDate(DateTime? d) => d == null
      ? '不限'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _doExport() async {
    if (_busy) return;
    if (_from != null && _to != null && _from!.isAfter(_to!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始日期不能晚于结束日期')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await ChatExportService.exportToFile(
        scopeId: _scope,
        fmt: _fmt,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选范围内没有聊天记录')),
        );
        return;
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: file.uri.pathSegments.last,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已生成导出文件，请在分享面板选择保存位置')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出聊天记录')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pagePadding),
        children: [
          // 范围
          DropdownButtonFormField<String>(
            value: _scope,
            decoration: _wxInput(context),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('全部智能体（默认）')),
              ..._agents.map(
                (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
              ),
            ],
            onChanged: (v) => setState(() => _scope = v ?? 'all'),
          ),
          const SizedBox(height: AppDimens.gapLg),
          // 格式
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'json', label: Text('JSON'), icon: Icon(Icons.data_object)),
              ButtonSegment(value: 'txt', label: Text('TXT'), icon: Icon(Icons.text_snippet)),
            ],
            selected: {_fmt},
            onSelectionChanged: (s) => setState(() => _fmt = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            _fmt == 'json'
                ? 'JSON：结构化，适合备份/再导入'
                : 'TXT：易读纯文本，适合直接查看/打印',
            style: AppTextStyles.caption.copyWith(
              color: AppTextStyles.secondaryText(context),
            ),
          ),
          const SizedBox(height: AppDimens.gapLg),
          // 起止日期
          Row(
            children: [
              Expanded(
                child: WxIconButton(
                  label: '开始：${_fmtDate(_from)}',
                  icon: Icons.date_range,
                  filled: false,
                  fullWidth: true,
                  onPressed: () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: AppDimens.gapSm),
              Expanded(
                child: WxIconButton(
                  label: '结束：${_fmtDate(_to)}',
                  icon: Icons.date_range,
                  filled: false,
                  fullWidth: true,
                  onPressed: () => _pickDate(isFrom: false),
                ),
              ),
            ],
          ),
          if (_from != null || _to != null)
            Align(
              alignment: Alignment.centerRight,
              child: WxIconButton(
                label: '清除日期过滤',
                filled: false,
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
              ),
            ),
          const SizedBox(height: 8),
          // 统计
          Text(
            _statText,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppTextStyles.secondaryText(context),
            ),
          ),
          const SizedBox(height: AppDimens.gapLg),
          // 导出
          WxIconButton(
            label: _busy ? '正在生成…' : '导出并分享',
            icon: _busy ? Icons.hourglass_empty : Icons.ios_share,
            filled: true,
            fullWidth: true,
            onPressed: _busy ? null : _doExport,
          ),
          const SizedBox(height: AppDimens.gapMd),
          const Text(
            '说明：导出生成文件后弹出系统分享面板，可保存到微信、文件管理器或发送到电脑；'
            'TXT 已带 BOM，记事本打开中文不乱码。本地记录永远全量保留，导出不影响任何数据。',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
