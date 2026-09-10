import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';
import '../services/app_feats.dart';
import '../../core/utils/log_buffer.dart';
import 'log_category_page.dart';

/// 开发者中心（v3.3.0，对齐网页版模式，xiaoleweb.md 第十一章）
/// ------------------------------------------------------------
/// 入口：「我」→ 开发者选项 → 未授权先弹密码门（本机记住授权，页面内可清除）。
/// Cell 列表：左标题+副标题说明、右开关；顶部「N 项开启」；底部全部关闭/清除授权。
class DevCenterPage extends StatefulWidget {
  const DevCenterPage({super.key});

  @override
  State<DevCenterPage> createState() => _DevCenterPageState();
}

class _DevCenterPageState extends State<DevCenterPage> {
  @override
  void initState() {
    super.initState();
    AppFeats.load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('开发者中心')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // N 项开启
          Center(
            child: Text(
              '${AppFeats.onCount} 项开启',
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _section(isDark, '能力开关', [
            _switchTile(
              isDark,
              '🧰 MCP 设备工具',
              '向 AI 注册设备工具：音量/主题/拍照/定时器/日程——AI 可真实操控',
              'mcptools',
            ),
            _switchTile(
              isDark,
              '📡 MQTT 常驻在线',
              '长连接保后台在线 + 接收远程配置；下次连接生效（限流风险默认关）',
              'mqtt',
            ),
            _switchTile(
              isDark,
              '📷 视觉识物',
              '聊天栏相机按钮：拍照问 AI 这是什么',
              'vision',
            ),
            _switchTile(
              isDark,
              '🎤 抢话打断',
              '通话中 AI 说话时你开口立即打断（误触发可关）',
              'bargein',
            ),
            _switchTile(
              isDark,
              '🧪 MCP 调试',
              '开启=字幕保留 % 工具名原文；关闭=自动过滤',
              'mcpDebug',
            ),
            _switchTile(
              isDark,
              '😄 表情动画',
              'AI 对话时的全屏表情动画（v4.3.0 起默认关，可在此开启）',
              'emotion',
            ),
          ]),
          _section(isDark, '诊断', [
            ListTile(
              leading:
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF576B95)),
              title: const Text('📋 运行日志查看'),
              subtitle: const Text('复制最近 200 条运行日志，供 AI 排查故障'),
              onTap: _copyLogs,
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: Color(0xFF576B95)),
              title: const Text('🗂 日志分类'),
              subtitle: Text(
                  '按功能开关日志记录（已开 ${LogBuffer.enabledCount}/${LogBuffer.categories.length}）'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogCategoryPage()),
                );
                if (mounted) setState(() {});
              },
            ),
          ]),
          _section(isDark, '安全', [
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF576B95)),
              title: const Text('🔒 清除授权'),
              subtitle: const Text('下次进开发者中心需重新输密码'),
              onTap: () {
                AppFeats.setDevAuthed(false);
                ToastUtil.show('已清除授权');
                Navigator.of(context).pop();
              },
            ),
          ]),
          _section(isDark, '危险操作', [
            ListTile(
              leading: const Icon(Icons.close, color: Color(0xFFE64340)),
              title: const Text('全部关闭'),
              subtitle: const Text('关闭所有开发者功能（等效普通用户模式）'),
              onTap: () {
                AppFeats.allOff();
                setState(() {});
                ToastUtil.show('已全部关闭');
              },
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// v4.3.2：复制最近 200 条运行日志到剪贴板（供用户粘贴给 AI 排查故障）
  Future<void> _copyLogs() async {
    try {
      final text = LogBuffer.recentText(200);
      if (text.isEmpty) {
        ToastUtil.show('暂无日志，请先复现操作再回来复制');
        return;
      }
      final count = '\n'.allMatches(text).length + 1;
      await Clipboard.setData(ClipboardData(text: text));
      ToastUtil.show('已复制 $count 条日志');
    } catch (e) {
      ToastUtil.show('复制失败：$e');
    }
  }

  Widget _section(bool isDark, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(bool isDark, String title, String subtitle, String key) {
    return SwitchListTile(
      value: AppFeats.get(key),
      onChanged: (v) {
        AppFeats.set(key, v);
        setState(() {});
        ToastUtil.show(v ? '$title 已开启' : '$title 已关闭');
      },
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 开发者中心密码门（未授权时弹出；与网页版同密码，错误抖动）
Future<void> showDevGateIfNeeded(BuildContext context) async {
  if (AppFeats.devAuthed) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevCenterPage()),
    );
    return;
  }
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('开发者模式'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            hintText: '请输入密码', border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.of(ctx).pop(v == AppFeats.devPassword),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text == AppFeats.devPassword),
            child: const Text('确定')),
      ],
    ),
  );
  if (ok == true) {
    AppFeats.setDevAuthed(true);
    ToastUtil.show('授权成功');
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DevCenterPage()),
      );
    }
  } else if (ok == false) {
    ToastUtil.show('密码错误');
  }
}
