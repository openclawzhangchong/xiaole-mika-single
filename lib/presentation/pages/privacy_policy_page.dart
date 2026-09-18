import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';

/// 隐私政策 · 权限引导页（v6.7.0 新增；v6.11.4 按微信四层规范重排）
/// ------------------------------------------------------------
/// 定位：引导用户放心授予全部权限（每条：用途 + 不授权的影响），
/// 并给出保活设置指引（电池优化/自启动/后台运行）。
/// 微信四层规范（对齐 v6.11.0 开发者中心）：①灰页面底 ②白色通栏直角容器
/// （显式撑满宽，根治 v6.11.3 前卡片随内容收缩的 bug）③行间 0.5px 分割线
/// ④28px 彩色圆角图标色块（替代 emoji）。无外链、深浅色自适应。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策 · 权限引导')),
      // 底部安全区交给 SafeArea，防手势条遮挡
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 10),
            _section(isDark, '为什么建议全部授权', [
              _p(sub, '为了让小乐 App 的每一项功能都能完整使用，'
                  '我们真诚建议您授予以下全部权限。'
                  '放心授权后，App 会越来越好用、越来越稳定。'),
            ]),
            _section(isDark, '权限清单', [
              _perm(isDark, Icons.mic, AppColors.primary,
                  '麦克风', '与小乐语音对话的核心通道', '只能打字交流，无法语音通话'),
              _perm(isDark, Icons.photo_camera, AppColors.cloudBlue,
                  '相机', '拍照识物', '无法拍照让小乐识别'),
              _perm(isDark, Icons.notifications, AppColors.alertAmber,
                  '通知', '接收 AI 回复与主动来电提醒', '收不到提醒、可能错过主动来电'),
              _perm(isDark, Icons.event, AppColors.info,
                  '日历', '写入日程提醒', '日程功能不可用'),
              _perm(isDark, Icons.location_on, AppColors.error,
                  '位置', '导航与位置相关能力', '无法使用导航/定位功能'),
              _perm(isDark, Icons.call, AppColors.info,
                  '电话', '打开拨号盘并填号（由你拨出）', '无法使用"帮我打电话"'),
              _perm(isDark, Icons.sms, AppColors.emojiPink,
                  '短信', '预填短信内容（由你发送）', '无法使用"帮我发短信"'),
              _perm(isDark, Icons.photo_library, AppColors.primary,
                  '存储/相册', '导出聊天记录、选择图片识图', '无法导出与选图',
                  isLast: true),
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
              _point(isDark, AppColors.primary,
                  '权限仅用于实现对应功能，不会在后台滥用'),
              _point(isDark, AppColors.primary,
                  '涉及电话、短信等敏感系统操作，均需你手动确认后才真正生效'),
              _point(isDark, AppColors.primary,
                  '你的聊天记录保存在本机，云端同步仅在你主动开启后进行'),
              _point(isDark, AppColors.primary,
                  '随时可在系统设置中收回任何权限，App 会优雅降级为不依赖该权限的模式',
                  isLast: true),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ===== 28px 彩色圆角图标色块（微信规格，对齐 dev_center _iconTile） =====
  Widget _permIcon(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }

  /// 权限条目：左 28px 色块 + 右侧（名称 17/w500 + 两行说明 12 次色，顶对齐）；
  /// 条目间 0.5px 分割线（缩进对齐文字区），末行无线。
  Widget _perm(bool isDark, IconData icon, Color color, String name,
      String why, String impact, {bool isLast = false}) {
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // 条目上下 12：统一高度节奏（拒绝任务里会导致错位的"垂直居中"方案，
          // 两行说明的条目应顶对齐——微信单元格行为）
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _permIcon(icon, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTextStyles.bodyStrong.copyWith(color: prim)),
                    const SizedBox(height: 3),
                    Text('为什么需要：$why',
                        style: AppTextStyles.caption
                            .copyWith(height: 1.4, color: sub)),
                    Text('不授权会怎样：$impact',
                        style: AppTextStyles.caption
                            .copyWith(height: 1.4, color: sub)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            margin: const EdgeInsets.only(left: 56), // 16 + 28 + 12 对齐文字区
            height: 0.5,
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
      ],
    );
  }

  /// 承诺条目（✅ 图标 + 文字，顶对齐）
  Widget _point(bool isDark, Color color, String text, {bool isLast = false}) {
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: AppTextStyles.subtitle
                        .copyWith(height: 1.5, color: sub)),
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            margin: const EdgeInsets.only(left: 42), // 16 + 16 + 10
            height: 0.5,
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
      ],
    );
  }

  /// 正文段落（组内）
  Widget _p(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(
        text,
        style: AppTextStyles.subtitle.copyWith(height: 1.5, color: color),
      ),
    );
  }

  /// 微信分组：灰底上灰色标题 + 白色通栏直角容器。
  /// SizedBox(width: double.infinity) 显式撑满 —— 根治"卡片随内容收缩"的
  /// 宽度 bug（Column 传松约束，Material 会收缩到最宽一行；截图确证）。
  Widget _section(bool isDark, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
