import 'package:flutter/material.dart';

/// 应用颜色常量（微信风格 · 唯一来源 `xl_tokens.dart` / tokens.json）
class AppColors {
  AppColors._();

  // 主色调（微信绿）
  static const Color primary = Color(0xFF07C160);
  static const Color primaryVariant = Color(0xFF06AD56);
  static const Color primaryPressed = Color(0xFF06AD56);
  static const Color primaryLight = Color(0xFF95EC69);
  static const Color secondary = Color(0xFF07C160);
  static const Color secondaryVariant = Color(0xFF06AD56);

  /// 深绿：实心按钮 / Tab 选中（白字 5.12:1）
  static const Color brandDeep = Color(0xFF0B7F40);
  static const Color brandSoft = Color(0xFFEAF8EF);

  // 背景色
  static const Color background = Color(0xFFEDEDED);
  static const Color backgroundDark = Color(0xFF111111);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color backgroundSecondary = Color(0xFFF7F7F7);
  static const Color backgroundSecondaryDark = Color(0xFF242426);

  // 消息气泡
  static const Color userMessageBg = Color(0xFF95EC69);
  static const Color aiMessageBg = Color(0xFFFFFFFF);
  static const Color userMessageBgDark = Color(0xFF3A7A4F);
  static const Color aiMessageBgDark = Color(0xFF2C2C2E);

  // 文本颜色
  static const Color textPrimary = Color(0xFF191919);
  static const Color textPrimaryDark = Color(0xFFE6E6E6);
  static const Color textSecondary = Color(0xFF6E6E6E);
  static const Color textSecondaryDark = Color(0xFF9A9A9A);
  static const Color textTertiary = Color(0xFF767676);
  static const Color textTertiaryDark = Color(0xFF8A8A8A);

  // 功能色
  static const Color success = Color(0xFF07C160);
  static const Color error = Color(0xFFFA5151);
  static const Color errorText = Color(0xFFC43434);
  static const Color warning = Color(0xFFFFC300);
  static const Color info = Color(0xFF576B95);
  static const Color infoDark = Color(0xFF8FA6CE);

  /// 云端相关图标蓝（一键云端 / 云端身份）—— v6.10.0 从硬编码提取为 token
  static const Color cloudBlue = Color(0xFF0ABFF4);

  /// 表情动画图标粉（开发者中心「表情动画」开关行色块）
  static const Color emojiPink = Color(0xFFFF6B9D);

  /// 主动联系图标琥珀（开发者中心「AI 主动联系」总开关行色块）
  static const Color alertAmber = Color(0xFFFA9D3B);

  // 分割线与边框
  static const Color divider = Color(0x14000000);
  static const Color dividerDark = Color(0x17FFFFFF);
  static const Color border = Color(0xFFE5E5E5);
  static const Color borderDark = Color(0xFF2E2E30);

  // 输入框
  static const Color inputBackground = Color(0xFFFFFFFF);
  static const Color inputBackgroundDark = Color(0xFF242426);
  static const Color inputBorder = Color(0xFFE5E5E5);
  static const Color inputBorderDark = Color(0xFF2E2E30);

  // 搜索框底色
  static const Color searchBackground = Color(0xFFFFFFFF);
  static const Color searchBackgroundDark = Color(0xFF1C1C1E);

  // 底部导航栏
  static const Color navBarBackground = Color(0xFFF7F7F7);
  static const Color navBarBackgroundDark = Color(0xFF242426);
  static const Color navBarUnselected = Color(0xFF7A7A7A);
  static const Color navBarUnselectedDark = Color(0xFF8A8A8A);

  // 未读徽标
  static const Color badge = Color(0xFFD93636);
  static const Color badgeText = Color(0xFFFFFFFF);

  // 列表按压态
  static const Color listPressed = Color(0xFFE9E9E9);
  static const Color listPressedDark = Color(0xFF2E2E30);

  // 状态点
  static const Color statusOnline = Color(0xFF07C160);
  static const Color statusBusy = Color(0xFFFA5151);
  static const Color statusOffline = Color(0xFFA0A6AD);
  static const Color statusOfflineDark = Color(0xFF8A8A8A);

  // 语音波形 / 系统提示 / 正在输入
  static const Color voiceWave = Color(0xFF07C160);
  static const Color systemText = Color(0xFF5F5F5F); // §15 I2
  static const Color systemTextDark = Color(0xFF9A9A9A);
  static const Color typingDot = Color(0xFFABABAB);
  static const Color typingDotDark = Color(0xFF6E6E6E);

  // 头像占位
  static const Color avatarGray = Color(0xFFC7C7CC);

  // 用户头像渐变（原型 user-text-avatar）
  static const Color userAvatarStart = Color(0xFF576B95);
  static const Color userAvatarEnd = Color(0xFF3A5075);

  // 语音通话页背景
  static const Color callBgTop = Color(0xFF3C3C3C);
  static const Color callBgMid = Color(0xFF2B2B2B);
  static const Color callBgBottom = Color(0xFF1B1B1B);
}

// v6.10.0：原 `AppDimens` 类已迁出到 `app_dimens.dart` 并补齐 token。
// 迁出原因：① 原类全项目零引用（死代码）；② 若与 app_dimens.dart 的新类同时被 import
// 会触发类名冲突。此处删除零引用类，无回归风险。
