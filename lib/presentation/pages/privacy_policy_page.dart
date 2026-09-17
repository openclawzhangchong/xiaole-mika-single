import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';

/// 隐私政策 · 权限引导页（v6.7.0 新增）
/// ------------------------------------------------------------
/// 定位：引导用户放心授予全部权限（每条：用途 + 不授权的影响），
/// 并给出保活设置指引（电池优化/自启动/后台运行）。
/// 无外链、深浅色自适应。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final accent = const Color(0xFF07C160);

    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策 · 权限引导')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _section(isDark, '为什么建议全部授权', [
            _p(sub, '为了让小乐 App 的每一项功能都能完整使用，'
                '我们真诚建议您授予以下全部权限。'
                '放心授权后，App 会越来越好用、越来越稳定。'),
          ]),
          _section(isDark, '权限清单', [
            _perm(isDark, '🎤 麦克风', '与小智语音对话的核心通道', '只能打字交流，无法语音通话'),
            _perm(isDark, '📷 相机', '拍照识物', '无法拍照让小智识别'),
            _perm(isDark, '🔔 通知', '接收 AI 回复与主动来电提醒', '收不到提醒、可能错过主动来电'),
            _perm(isDark, '📅 日历', '写入日程提醒', '日程功能不可用'),
            _perm(isDark, '📍 位置', '导航与位置相关能力', '无法使用导航/定位功能'),
            _perm(isDark, '📞 电话', '打开拨号盘并填号（由你拨出）', '无法使用"帮我打电话"'),
            _perm(isDark, '💬 短信', '预填短信内容（由你发送）', '无法使用"帮我发短信"'),
            _perm(isDark, '🖼 存储/相册', '导出聊天记录、选择图片识图', '无法导出与选图'),
          ]),
          _section(isDark, '让 App 常驻不杀（重要）', [
            _p(sub, '请按以下步骤设置，避免小乐被系统后台杀掉，'
                '保证语音通话不断线、AI 主动来电不漏接：'),
            _p(prim, '1. 系统设置 → 应用 → 小乐 → 电池 → 选择「不限制/允许后台运行」；'),
            _p(prim, '2. 在电池优化列表中将小乐设为「不优化/白名单」；'),
            _p(prim, '3. 若有「自启动」开关，请开启；'),
            _p(prim, '4. 最近任务里不要上滑清理小乐。'),
            _p(sub, '（不同品牌手机路径略有差异，关键词：电池优化、自启动、后台运行。）'),
          ]),
          _section(isDark, '我们的承诺', [
            _point(accent, '权限仅用于实现对应功能，不会在后台滥用'),
            _point(accent, '涉及电话、短信等敏感系统操作，均需你手动确认后才真正生效'),
            _point(accent, '你的聊天记录保存在本机，云端同步仅在你主动开启后进行'),
            _point(accent, '随时可在系统设置中收回任何权限，App 会优雅降级为不依赖该权限的模式'),
          ]),
        ],
      ),
    );
  }

  Widget _perm(bool isDark, String name, String why, String impact) {
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: prim)),
          const SizedBox(height: 2),
          Text('为什么需要：$why', style: TextStyle(fontSize: 13, height: 1.4, color: sub)),
          Text('不授权会怎样：$impact', style: TextStyle(fontSize: 13, height: 1.4, color: sub)),
        ],
      ),
    );
  }

  Widget _point(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Icon(Icons.check_circle, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(bool isDark, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _p(Color color, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: bold ? 15 : 13.5,
          fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
          height: 1.5,
          color: color,
        ),
      ),
    );
  }
}
