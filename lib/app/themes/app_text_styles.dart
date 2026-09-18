import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 微信风字号阶梯（v6.10.0 重写）
/// ------------------------------------------------------------
/// ⚠️ 设计要点：本文件**不含任何 color**。
///
/// 旧版把 `color: AppColors.textPrimary` 写死在每个样式里 —— 深色模式下不可用，
/// 于是全项目零引用、沦为死代码（实测：lib/ 与 test/ 均 0 引用）。
///
/// 新版只定义「字号 + 字重 + 行高」，颜色由调用方按 light/dark 取值，
/// 直接调用 [primaryText] / [secondaryText] / [tertiaryText] / [divider] / [surface]。
///
/// 阶梯只有 5 档：**11 / 12 / 14 / 17 / 20**（对齐微信）。
/// 全项目硬编码字号一律收敛到本阶梯，见 PLAN_v6.10.0。
class AppTextStyles {
  AppTextStyles._();

  // ========== 阶梯定义（无颜色） ==========

  /// 20px w400 — 页面级大字（空态标题 / 金额等）
  static const TextStyle title20 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 17px w500 — 导航栏标题
  static const TextStyle navTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// 17px w400 — 正文 / 消息气泡 / 单元格标题（微信主字号）
  static const TextStyle body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 17px w600 — 强调（会话名 / 主标题）
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 14px w400 — 次要文字 / 副标题 / 分组标题
  static const TextStyle subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 14px w500 — 次要强调
  static const TextStyle subtitleStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// 12px w400 — 辅助说明 / 会话时间
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// 11px w400 — 极小辅助（底部标签 / 时间戳）
  static const TextStyle captionSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  // ========== 颜色辅助（按 light/dark 自动取值） ==========

  /// 主文字色（浅色 #181818 / 深色 #E5E5E5）
  static Color primaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.textPrimaryDark
          : AppColors.textPrimary;

  /// 次要文字色
  static Color secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.textSecondaryDark
          : AppColors.textSecondary;

  /// 三级文字色
  static Color tertiaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.textTertiaryDark
          : AppColors.textTertiary;

  /// 分割线色（微信 0.5px 细线）
  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.dividerDark
          : AppColors.divider;

  /// 卡片 / 页面底色
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.surfaceDark
          : AppColors.surface;

  /// 页面底色（微信聊天灰）
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.background;
}
