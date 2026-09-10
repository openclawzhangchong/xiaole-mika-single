import 'package:flutter/material.dart';

/// 应用颜色常量（微信风格 · 对齐原型 v6 色板）
class AppColors {
  AppColors._();

  // 主色调（微信绿）
  static const Color primary = Color(0xFF07C160);
  static const Color primaryVariant = Color(0xFF06AD56);
  static const Color primaryPressed = Color(0xFF06AD56);
  static const Color primaryLight = Color(0xFF95EC69);
  static const Color secondary = Color(0xFF07C160);
  static const Color secondaryVariant = Color(0xFF06AD56);

  // 背景色
  static const Color background = Color(0xFFEDEDED);
  static const Color backgroundDark = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color backgroundSecondary = Color(0xFFF7F7F7);
  static const Color backgroundSecondaryDark = Color(0xFF1A1A1A);

  // 消息气泡
  static const Color userMessageBg = Color(0xFF95EC69);
  static const Color aiMessageBg = Color(0xFFFFFFFF);
  static const Color userMessageBgDark = Color(0xFF2B5E3F);
  static const Color aiMessageBgDark = Color(0xFF2C2C2C);

  // 文本颜色
  static const Color textPrimary = Color(0xFF181818);
  static const Color textPrimaryDark = Color(0xFFE5E5E5);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textSecondaryDark = Color(0xFF8E8E8E);
  static const Color textTertiary = Color(0xFFB2B2B2);
  static const Color textTertiaryDark = Color(0xFF555555);

  // 功能色
  static const Color success = Color(0xFF07C160);
  static const Color error = Color(0xFFFA5151);
  static const Color warning = Color(0xFFFFC300);
  static const Color info = Color(0xFF576B95);
  static const Color infoDark = Color(0xFF6B7FA8);

  // 分割线与边框
  static const Color divider = Color(0xFFF0F0F0);
  static const Color dividerDark = Color(0xFF1E1E1E);
  static const Color border = Color(0xFFE5E5E5);
  static const Color borderDark = Color(0xFF2A2A2A);

  // 输入框
  static const Color inputBackground = Color(0xFFFFFFFF);
  static const Color inputBackgroundDark = Color(0xFF2A2A2A);
  static const Color inputBorder = Color(0xFFE5E5E5);
  static const Color inputBorderDark = Color(0xFF333333);

  // 搜索框底色
  static const Color searchBackground = Color(0xFFE0E0E0);
  static const Color searchBackgroundDark = Color(0xFF2A2A2A);

  // 底部导航栏
  static const Color navBarBackground = Color(0xFFF7F7F7);
  static const Color navBarBackgroundDark = Color(0xFF161616);
  static const Color navBarUnselected = Color(0xFF7A7A7A);
  static const Color navBarUnselectedDark = Color(0xFF6A6A6A);

  // 未读徽标
  static const Color badge = Color(0xFFFA5151);
  static const Color badgeText = Color(0xFFFFFFFF);

  // 列表按压态
  static const Color listPressed = Color(0xFFE6E6E6);
  static const Color listPressedDark = Color(0xFF2A2A2A);

  // 状态点
  static const Color statusOnline = Color(0xFF07C160);
  static const Color statusBusy = Color(0xFFFA5151);
  static const Color statusOffline = Color(0xFFB2B2B2);
  static const Color statusOfflineDark = Color(0xFF555555);

  // 语音波形 / 系统提示 / 正在输入
  static const Color voiceWave = Color(0xFF07C160);
  static const Color systemText = Color(0xFFB2B2B2);
  static const Color systemTextDark = Color(0xFF6A6A6A);
  static const Color typingDot = Color(0xFFB2B2B2);
  static const Color typingDotDark = Color(0xFF6A6A6A);

  // 头像占位
  static const Color avatarGray = Color(0xFFC7C7CC);

  // 用户头像渐变（原型 user-text-avatar）
  static const Color userAvatarStart = Color(0xFF576B95);
  static const Color userAvatarEnd = Color(0xFF3A5075);

  // 语音通话页背景
  static const Color callBgTop = Color(0xFF3A3A3A);
  static const Color callBgMid = Color(0xFF2B2B2B);
  static const Color callBgBottom = Color(0xFF1A1A1A);
}

/// 尺寸与圆角常量
class AppDimens {
  AppDimens._();

  static const double radiusS = 4;
  static const double radiusM = 8;
  static const double radiusL = 12;
  static const double radiusXl = 20;

  static const double navBarHeight = 48;
  static const double tabBarHeight = 56;
  static const double inputBarHeight = 52;

  static const double avatarList = 48;
  static const double avatarMessage = 40;
  static const double avatarProfile = 64;

  static const double pagePadding = 12;
}
