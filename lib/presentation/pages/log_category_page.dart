import 'package:flutter/material.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';

import '../../core/utils/log_buffer.dart';

/// 日志分类开关（v4.3.3 新增）
/// ------------------------------------------------------------
/// 入口：开发者中心 →「诊断」→「🗂 日志分类」。
/// 关闭的分类**不再写入运行日志缓冲**（省内存、降噪音）；排查某一功能时只开它即可。
/// 默认只开识图链路三件套：vision（照片）/ ws（连接）/ mcp（消息）。
class LogCategoryPage extends StatefulWidget {
  const LogCategoryPage({super.key});

  @override
  State<LogCategoryPage> createState() => _LogCategoryPageState();
}

class _LogCategoryPageState extends State<LogCategoryPage> {
  void _setAll(bool v) {
    LogBuffer.setAll(v);
    setState(() {});
    ToastUtil.show(v ? '已全部开启' : '已全部关闭');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Scaffold(
      appBar: AppBar(title: const Text('日志分类')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '关闭的分类不再记录到运行日志（省内存、降噪音）。\n'
              '排查某一功能时，只开它对应的分类即可。\n'
              '默认开启：识图（照片）+ 连接（WS）+ MCP 消息。',
              style: TextStyle(fontSize: 13, height: 1.5, color: sub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '已开启 ${LogBuffer.enabledCount}/${LogBuffer.categories.length}'
              ' · 当前缓冲 ${LogBuffer.length} 条',
              style: TextStyle(fontSize: 12, color: sub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: isDark ? AppColors.surfaceDark : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  for (final c in LogBuffer.categories)
                    SwitchListTile(
                      value: LogBuffer.isEnabled(c),
                      onChanged: (v) {
                        LogBuffer.setCategory(c, v);
                        setState(() {});
                      },
                      title: Text(
                        LogBuffer.categoryLabels[c] ?? c,
                        style: TextStyle(fontSize: 16, color: prim),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setAll(true),
                    child: const Text('全部开启'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setAll(false),
                    child: const Text('全部关闭'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
