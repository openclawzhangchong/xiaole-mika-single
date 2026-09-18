import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_text_styles.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';

/// v6.8.0：主动来电「后台化」引导页
/// ------------------------------------------------------------------
/// 三步引导用户做保活设置，提升锁屏/退后台后巡检存活率：
/// ① 电池优化白名单 ② 自启动 ③ 后台运行限制。
///
/// 每步一行说明 + 一个"去设置"按钮，用项目已有的 [AndroidIntent] 打开系统页。
/// ⚠️ 仅当**能查询到**电池优化状态时才展示"已设置/未设置"；本项目不引入额外插件，
/// 无法可靠查询各厂商 ROM 的上述状态，故**不展示伪造状态**，只提供入口。
class BackgroundGuidePage extends StatelessWidget {
  const BackgroundGuidePage({super.key});

  static const String _packageName = 'com.zcstudy.xiaole';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('后台保活引导')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF576B95).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '开启「AI 主动联系」后，小乐会在你退出 App / 锁屏时后台巡检并来电。'
              '不同手机厂商会限制后台活动，请按下面三步放行，来电才能更可靠地送达。',
              style: AppTextStyles.caption.copyWith(height: 1.5),
            ),
          ),
          _StepCard(
            index: 1,
            title: '电池优化白名单',
            desc: '把小乐加入「不受电池优化限制」列表，避免被系统休眠。',
            onTap: _openBatterySettings,
          ),
          _StepCard(
            index: 2,
            title: '允许自启动',
            desc: '允许小乐自启动，系统在需要时能重新拉起它完成巡检。',
            onTap: _openAppDetails,
          ),
          _StepCard(
            index: 3,
            title: '后台运行限制',
            desc: '关闭对小乐的「后台运行限制 / 省电限制」，让它退到后台也能工作。',
            onTap: _openAppDetails,
          ),
          const SizedBox(height: 12),
          Text(
            '提示：不同厂商（小米 / 华为 / OPPO / vivo 等）设置路径与名称不同，'
            '若上述按钮未跳到对应位置，可在系统「设置 → 应用管理 → 小乐」中手动查找上述三项。',
            style: AppTextStyles.caption.copyWith(color: sub, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// ① 电池优化设置页（列出所有可豁免电池优化的应用，找到小乐并设为"不限制"）。
  Future<void> _openBatterySettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      // 个别 ROM 无此页，回退到应用详情页
      await _openAppDetails();
      ToastUtil.show('未找到电池优化页，已打开应用设置，请手动查找');
    }
  }

  /// ②/③ 应用详情设置页（自启动 / 后台运行限制多数厂商都在此处或其子菜单）。
  Future<void> _openAppDetails() async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$_packageName',
      );
      await intent.launch();
    } catch (e) {
      ToastUtil.show('无法打开系统设置：$e');
    }
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final String title;
  final String desc;
  final Future<void> Function() onTap;

  const _StepCard({
    required this.index,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.subtitleStrong.copyWith(color: prim)),
                const SizedBox(height: 2),
                Text(desc,
                    style: AppTextStyles.caption.copyWith(color: sub, height: 1.4)),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text('去设置'),
          ),
        ],
      ),
    );
  }
}
