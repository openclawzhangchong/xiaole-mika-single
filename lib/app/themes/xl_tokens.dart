import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 小乐 · 微信风格 IM 设计令牌（唯一来源：_design/xiaole-mika-ui/tokens.json）
/// ------------------------------------------------------------
/// 只允许从这里取颜色 / 字号 / 圆角 / 间距 / 动效。
/// 业务 widget 里不要再写裸色值与魔法数字。
abstract final class XlColor {
  // bg
  static const canvas = Color(0xFFEDEDED);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFF7F7F7);
  static const pressed = Color(0xFFE9E9E9);
  static const mask = Color(0x73000000);
  static const overlay = Color(0xC7141414); // rgba(20,20,20,.78)

  // text
  static const text1 = Color(0xFF191919);
  static const text2 = Color(0xFF6E6E6E);
  static const text3 = Color(0xFF767676);
  static const text4 = Color(0xFFABABAB);
  static const placeholder = Color(0xFFB2B2B2);
  static const systemText = Color(0xFF5F5F5F); // §15 I2（旧 #ABABAB 废止）
  static const sectionLabel = Color(0xFF666666); // §15 I3/I4
  static const onDark = Color(0xFFE6E6E6);
  static const onDarkSecondary = Color(0xFF9A9A9A);

  // bubble
  static const bubbleSelfBg = Color(0xFF95EC69);
  static const bubbleSelfText = Color(0xFF191919);
  static const bubbleOtherBg = Color(0xFFFFFFFF);
  static const bubbleOtherText = Color(0xFF191919);

  // brand
  static const brand = Color(0xFF07C160); // 仅状态点 / 开关 / 进度 / 波形
  // preview-01 实测：默认智能体头像 = 深底 + 绿色波形
  static const brandAvatarBg = Color(0xFF1E1E1E);
  static const brandBarOuter = Color(0xFFD5D5D5);
  static const brandBarInner = Color(0xFFE8E8E8);
  static const badgeRed = Color(0xFFD93636); // 未读红点（preview-01 实测，深浅一致）
  static const brandDeep = Color(0xFF0B7F40); // 实心按钮 / Tab 选中 / 白字
  static const mint = Color(0xFF8CF0AE); // 录音浮层 / 通话波形（ui.css）
  static const brandSoft = Color(0xFFEAF8EF);
  static const tabActive = Color(0xFF0B7F40); // §15 I7（实拍为准）
  static const switchTrackOn = Color(0xFF07C160);
  static const switchTrackOff = Color(0xFFE5E5E5);
  static const link = Color(0xFF576B95);

  // danger
  static const danger = Color(0xFFFA5151);
  static const dangerText = Color(0xFFC43434); // §15 I1（取消胶囊 5.40:1）
  static const dangerBadge = Color(0xFFD93636);
  static const dangerSoft = Color(0xFFFDEDED);
  static const warning = Color(0xFFFFC300);

  // task
  static const taskQueuedDot = Color(0xFFA0A6AD);
  static const taskQueuedText = Color(0xFF6E6E6E);
  static const taskQueuedBg = Color(0xFFF1F2F4);
  static const taskQueuedIconBg = Color(0xFFF1F2F4);
  static const taskQueuedIcon = Color(0xFF6E6E6E);
  static const taskRunningText = Color(0xFF0B7F40);
  static const taskDoneText = Color(0xFF4A5A4F);
  static const taskDoneBg = Color(0xFFF2F4F3);
  static const taskProgressTrack = Color(0xFFEFEFEF);
  static const taskProgressFill = Color(0xFF07C160);

  // hairline
  static const hairline = Color(0x14000000); // 8% 黑
  static const hairlineStrong = Color(0x1A000000); // 10% 黑
  static const border = Color(0xFFE5E5E5);

  // call
  static const callBgTop = Color(0xFF3C3C3C);
  static const callBgMid = Color(0xFF2B2B2B);
  static const callBgBottom = Color(0xFF1B1B1B);
  static const callControl = Color(0x1FFFFFFF); // 12% 白（DESIGN §8.7）
  static const callControlIcon = Color(0xFFFFFFFF);
  static const callControlMuted = Color(0xFF555555);
  static const callRing = Color(0x33FFFFFF);
  static const callHintBg = Color(0x14FFFFFF);
  static const callTranscriptBg = Color(0x0FFFFFFF); // 6% 白
  static const callTextSoft = Color(0x9EFFFFFF); // 62% 白
  static const callTextDim = Color(0xB3FFFFFF); // 70% 白
}

abstract final class XlColorDark {
  static const canvas = Color(0xFF111111);
  static const nav = Color(0xFF1A1A1A); // preview-09 实测：导航/状态栏比画布浅一档
  static const surface = Color(0xFF1C1C1E);
  static const subtle = Color(0xFF242426);
  static const pressed = Color(0xFF2E2E30);
  static const mask = Color(0x99000000);
  static const overlay = Color(0xD1181818); // rgba(24,24,24,.82)

  static const text1 = Color(0xFFE6E6E6);
  static const text2 = Color(0xFF9A9A9A);
  static const text3 = Color(0xFF8A8A8A);
  static const text4 = Color(0xFF6E6E6E);
  static const placeholder = Color(0xFF7A7A7A);
  static const systemText = Color(0xFF9A9A9A);
  static const sectionLabel = Color(0xFF9A9A9A);

  static const bubbleSelfBg = Color(0xFF3A7A4F);
  static const bubbleSelfText = Color(0xFFFFFFFF);
  static const bubbleOtherBg = Color(0xFF2C2C2E);
  static const bubbleOtherText = Color(0xFFFFFFFF);

  static const brandDeep = Color(0xFF12A55C);
  static const brandSoft = Color(0xFF163A24);
  static const tabActive = Color(0xFF12A55C);
  static const switchTrackOn = Color(0xFF07C160);
  static const switchTrackOff = Color(0xFF3A3A3C); // §15 I9 不写死浅色值
  static const link = Color(0xFF8FA6CE);

  static const danger = Color(0xFFFF5A5A);
  static const dangerText = Color(0xFFFF7A7A);
  static const dangerBadge = Color(0xFFD93636);
  static const dangerSoft = Color(0x24FF5A5A);

  static const taskQueuedDot = Color(0xFF8A8A8A);
  static const taskQueuedText = Color(0xFF9A9A9A);
  static const taskQueuedBg = Color(0xFF242426);
  static const taskRunningText = Color(0xFF5BD98F);
  static const taskDoneText = Color(0xFFA8BCAE);
  static const taskProgressTrack = Color(0xFF2E2E30);

  static const hairline = Color(0x17FFFFFF); // 9% 白
  static const hairlineStrong = Color(0x24FFFFFF); // 14% 白
  static const border = Color(0xFF2E2E30);
}

/// 任务卡状态色（Light/Dark 仅换色，不改布局）
class XlTaskColors {
  const XlTaskColors({
    required this.dot,
    required this.text,
    required this.bg,
    required this.iconBg,
    required this.icon,
  });

  final Color dot;
  final Color text;
  final Color bg;
  final Color iconBg;
  final Color icon;
}

/// 语义色扩展：业务层不写 `isDark ? A : B`
@immutable
class XlPalette extends ThemeExtension<XlPalette> {
  const XlPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.subtle,
    required this.pressed,
    required this.overlay,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.placeholder,
    required this.systemText,
    required this.sectionLabel,
    required this.bubbleSelfBg,
    required this.bubbleSelfText,
    required this.bubbleOtherBg,
    required this.bubbleOtherText,
    required this.brand,
    required this.brandDeep,
    required this.brandSoft,
    required this.tabActive,
    required this.switchTrackOff,
    required this.link,
    required this.danger,
    required this.dangerText,
    required this.dangerBadge,
    required this.dangerSoft,
    required this.hairline,
    required this.hairlineStrong,
    required this.border,
    required this.taskQueued,
    required this.taskRunning,
    required this.taskDone,
    required this.taskFailed,
    required this.progressTrack,
    required this.progressFill,
    required this.cardShadow,
  });

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color subtle;
  final Color pressed;
  final Color overlay;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textQuaternary;
  final Color placeholder;
  final Color systemText;
  final Color sectionLabel;
  final Color bubbleSelfBg;
  final Color bubbleSelfText;
  final Color bubbleOtherBg;
  final Color bubbleOtherText;
  final Color brand;
  final Color brandDeep;
  final Color brandSoft;
  final Color tabActive;
  final Color switchTrackOff;
  final Color link;
  final Color danger;
  final Color dangerText;
  final Color dangerBadge;
  final Color dangerSoft;
  final Color hairline;
  final Color hairlineStrong;
  final Color border;
  final XlTaskColors taskQueued;
  final XlTaskColors taskRunning;
  final XlTaskColors taskDone;
  final XlTaskColors taskFailed;
  final Color progressTrack;
  final Color progressFill;
  final Color cardShadow;

  static const light = XlPalette(
    isDark: false,
    canvas: XlColor.canvas,
    surface: XlColor.surface,
    subtle: XlColor.subtle,
    pressed: XlColor.pressed,
    overlay: XlColor.overlay,
    textPrimary: XlColor.text1,
    textSecondary: XlColor.text2,
    textTertiary: XlColor.text3,
    textQuaternary: XlColor.text4,
    placeholder: XlColor.placeholder,
    systemText: XlColor.systemText,
    sectionLabel: XlColor.sectionLabel,
    bubbleSelfBg: XlColor.bubbleSelfBg,
    bubbleSelfText: XlColor.bubbleSelfText,
    bubbleOtherBg: XlColor.bubbleOtherBg,
    bubbleOtherText: XlColor.bubbleOtherText,
    brand: XlColor.brand,
    brandDeep: XlColor.brandDeep,
    brandSoft: XlColor.brandSoft,
    tabActive: XlColor.tabActive,
    switchTrackOff: XlColor.switchTrackOff,
    link: XlColor.link,
    danger: XlColor.danger,
    dangerText: XlColor.dangerText,
    dangerBadge: XlColor.dangerBadge,
    dangerSoft: XlColor.dangerSoft,
    hairline: XlColor.hairline,
    hairlineStrong: XlColor.hairlineStrong,
    border: XlColor.border,
    taskQueued: XlTaskColors(
      dot: XlColor.taskQueuedDot,
      text: XlColor.taskQueuedText,
      bg: XlColor.taskQueuedBg,
      iconBg: XlColor.taskQueuedIconBg,
      icon: XlColor.taskQueuedIcon,
    ),
    taskRunning: XlTaskColors(
      dot: XlColor.brand,
      text: XlColor.taskRunningText,
      bg: XlColor.brandSoft,
      iconBg: XlColor.brandSoft,
      icon: XlColor.brandDeep,
    ),
    taskDone: XlTaskColors(
      dot: XlColor.brandDeep,
      text: XlColor.taskDoneText,
      bg: XlColor.taskDoneBg,
      iconBg: XlColor.brandSoft,
      icon: XlColor.brandDeep,
    ),
    taskFailed: XlTaskColors(
      dot: XlColor.danger,
      text: XlColor.dangerText,
      bg: XlColor.dangerSoft,
      iconBg: XlColor.dangerSoft,
      icon: XlColor.dangerText,
    ),
    progressTrack: XlColor.taskProgressTrack,
    progressFill: XlColor.taskProgressFill,
    cardShadow: Color(0x0F000000), // 0 1 2 6%
  );

  static const dark = XlPalette(
    isDark: true,
    canvas: XlColorDark.canvas,
    surface: XlColorDark.surface,
    subtle: XlColorDark.subtle,
    pressed: XlColorDark.pressed,
    overlay: XlColorDark.overlay,
    textPrimary: XlColorDark.text1,
    textSecondary: XlColorDark.text2,
    textTertiary: XlColorDark.text3,
    textQuaternary: XlColorDark.text4,
    placeholder: XlColorDark.placeholder,
    systemText: XlColorDark.systemText,
    sectionLabel: XlColorDark.sectionLabel,
    bubbleSelfBg: XlColorDark.bubbleSelfBg,
    bubbleSelfText: XlColorDark.bubbleSelfText,
    bubbleOtherBg: XlColorDark.bubbleOtherBg,
    bubbleOtherText: XlColorDark.bubbleOtherText,
    brand: XlColor.brand,
    brandDeep: XlColorDark.brandDeep,
    brandSoft: XlColorDark.brandSoft,
    tabActive: XlColorDark.tabActive,
    switchTrackOff: XlColorDark.switchTrackOff,
    link: XlColorDark.link,
    danger: XlColorDark.danger,
    dangerText: XlColorDark.dangerText,
    dangerBadge: XlColorDark.dangerBadge,
    dangerSoft: XlColorDark.dangerSoft,
    hairline: XlColorDark.hairline,
    hairlineStrong: XlColorDark.hairlineStrong,
    border: XlColorDark.border,
    taskQueued: XlTaskColors(
      dot: XlColorDark.taskQueuedDot,
      text: XlColorDark.taskQueuedText,
      bg: XlColorDark.taskQueuedBg,
      iconBg: XlColorDark.taskQueuedBg,
      icon: XlColorDark.taskQueuedText,
    ),
    taskRunning: XlTaskColors(
      dot: XlColor.brand,
      text: XlColorDark.taskRunningText,
      bg: Color(0x2407C160), // rgba(7,193,96,.14)
      iconBg: Color(0x2407C160),
      icon: XlColorDark.taskRunningText,
    ),
    taskDone: XlTaskColors(
      dot: Color(0xFF5BD98F),
      text: XlColorDark.taskDoneText,
      bg: XlColorDark.subtle,
      iconBg: XlColorDark.brandSoft,
      icon: Color(0xFF5BD98F),
    ),
    taskFailed: XlTaskColors(
      dot: XlColorDark.danger,
      text: XlColorDark.dangerText,
      bg: Color(0x24FF5A5A), // rgba(255,90,90,.14)
      iconBg: Color(0x24FF5A5A),
      icon: XlColorDark.dangerText,
    ),
    progressTrack: XlColorDark.taskProgressTrack,
    progressFill: XlColor.brand,
    cardShadow: Color(0x00000000), // 深色去掉投影
  );

  /// 亮/暗解析；缺省回退浅色（避免 ThemeExtension 未注册时崩溃）
  static XlPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<XlPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  XlPalette copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? subtle,
    Color? pressed,
    Color? overlay,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textQuaternary,
    Color? placeholder,
    Color? systemText,
    Color? sectionLabel,
    Color? bubbleSelfBg,
    Color? bubbleSelfText,
    Color? bubbleOtherBg,
    Color? bubbleOtherText,
    Color? brand,
    Color? brandDeep,
    Color? brandSoft,
    Color? tabActive,
    Color? switchTrackOff,
    Color? link,
    Color? danger,
    Color? dangerText,
    Color? dangerBadge,
    Color? dangerSoft,
    Color? hairline,
    Color? hairlineStrong,
    Color? border,
    XlTaskColors? taskQueued,
    XlTaskColors? taskRunning,
    XlTaskColors? taskDone,
    XlTaskColors? taskFailed,
    Color? progressTrack,
    Color? progressFill,
    Color? cardShadow,
  }) {
    return XlPalette(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      subtle: subtle ?? this.subtle,
      pressed: pressed ?? this.pressed,
      overlay: overlay ?? this.overlay,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textQuaternary: textQuaternary ?? this.textQuaternary,
      placeholder: placeholder ?? this.placeholder,
      systemText: systemText ?? this.systemText,
      sectionLabel: sectionLabel ?? this.sectionLabel,
      bubbleSelfBg: bubbleSelfBg ?? this.bubbleSelfBg,
      bubbleSelfText: bubbleSelfText ?? this.bubbleSelfText,
      bubbleOtherBg: bubbleOtherBg ?? this.bubbleOtherBg,
      bubbleOtherText: bubbleOtherText ?? this.bubbleOtherText,
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      brandSoft: brandSoft ?? this.brandSoft,
      tabActive: tabActive ?? this.tabActive,
      switchTrackOff: switchTrackOff ?? this.switchTrackOff,
      link: link ?? this.link,
      danger: danger ?? this.danger,
      dangerText: dangerText ?? this.dangerText,
      dangerBadge: dangerBadge ?? this.dangerBadge,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      border: border ?? this.border,
      taskQueued: taskQueued ?? this.taskQueued,
      taskRunning: taskRunning ?? this.taskRunning,
      taskDone: taskDone ?? this.taskDone,
      taskFailed: taskFailed ?? this.taskFailed,
      progressTrack: progressTrack ?? this.progressTrack,
      progressFill: progressFill ?? this.progressFill,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  XlPalette lerp(ThemeExtension<XlPalette>? other, double t) {
    if (other is! XlPalette) return this;
    return XlPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      pressed: Color.lerp(pressed, other.pressed, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textQuaternary: Color.lerp(textQuaternary, other.textQuaternary, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      systemText: Color.lerp(systemText, other.systemText, t)!,
      sectionLabel: Color.lerp(sectionLabel, other.sectionLabel, t)!,
      bubbleSelfBg: Color.lerp(bubbleSelfBg, other.bubbleSelfBg, t)!,
      bubbleSelfText: Color.lerp(bubbleSelfText, other.bubbleSelfText, t)!,
      bubbleOtherBg: Color.lerp(bubbleOtherBg, other.bubbleOtherBg, t)!,
      bubbleOtherText: Color.lerp(bubbleOtherText, other.bubbleOtherText, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      tabActive: Color.lerp(tabActive, other.tabActive, t)!,
      switchTrackOff: Color.lerp(switchTrackOff, other.switchTrackOff, t)!,
      link: Color.lerp(link, other.link, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      dangerBadge: Color.lerp(dangerBadge, other.dangerBadge, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      taskQueued: taskQueued,
      taskRunning: taskRunning,
      taskDone: taskDone,
      taskFailed: taskFailed,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      progressFill: Color.lerp(progressFill, other.progressFill, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

/// 字号阶梯（tokens.typography.scale）
abstract final class XlType {
  static const navTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 22 / 17,
    letterSpacing: 0.2,
  );

  static const listTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 22 / 17,
  );

  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );

  static const cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 20 / 15,
  );

  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 22 / 16,
  );

  static const sendButton = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 20 / 15,
  );

  static const summary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 19 / 14,
  );

  static const meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 16 / 11,
  );

  static const tabLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 14 / 10,
  );

  static const callName = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 30 / 22,
  );

  static const callTimer = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 20 / 15,
    letterSpacing: 0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 时间跳秒不抖动
  static const callStatus = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
  );

  /// 通话转写条正文（DESIGN §8.7 13/19）
  static const callCaption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 19 / 13,
  );
}

/// 间距 / 圆角 / 尺寸
abstract final class XlDims {
  // spacing
  static const unit = 4.0;
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const pagePadding = 16.0;
  static const listPadding = 12.0;
  static const cardGap = 12.0;
  static const bubbleGap = 14.0;

  // row heights
  static const navHeight = 44.0;
  static const conversationRow = 64.0;
  static const settingsRow = 50.0;
  static const tabBarHeight = 49.0;
  static const inputBarHeight = 50.0;
  static const taskFooter = 36.0;

  // radius
  static const rXs = 2.0;
  static const rS = 4.0;
  static const rM = 6.0;
  static const rL = 8.0;
  static const rXl = 12.0;
  static const avatarChat = 5.0;
  static const avatarList = 6.0;
  static const avatarCall = 24.0;
  static const rBubble = 8.0;
  static const rCard = 8.0;
  static const rField = 4.0;
  static const rButton = 6.0;
  static const rPill = 999.0;

  // conversation list
  static const listAvatar = 48.0;
  // 品牌头像内 5 根竖条：preview-01 实测 4pt 宽 / 2.5pt 间距（48pt 基准）
  static const brandBarW = 4.0;
  static const brandBarGap = 2.5;
  static const listDividerInset = 76.0;
  static const badgeSize = 18.0;

  // chat
  static const chatAvatar = 36.0;
  static const bubbleMaxWidth = 245.0;
  static const bubblePadX = 12.0;
  static const bubblePadY = 9.0;
  static const bubbleTailW = 6.0;
  static const bubbleTailH = 10.0;
  static const bubbleTailTop = 12.0;
  static const voiceBubbleHeight = 40.0;
  static const waveBarW = 3.0;
  static const chatWaveBarW = 2.0; // 聊天气泡波形 2pt（浮层仍 3pt）
  static const waveBarGap = 2.0;
  static const waveBarMaxH = 18.0;
  static const voiceWaveBarMaxH = 34.0; // 录音浮层波形满槽高（ui.css 34 优先）
  static const voiceWaveBarCount = 9; // preview-03 实测 9 根（tokens 原 11 有误，已回写）
  static const voiceWaveBarW = 3.0;
  static const voiceWaveGap = 3.0;
  // preview-03 逐根实测高度 16/24/32/20/26/34/22/13/24pt，归一化到满槽 34
  static const voiceWaveProfile = <double>[
    0.47, 0.71, 0.94, 0.59, 0.76, 1.00, 0.65, 0.38, 0.71,
  ];
  static const waveOpacity = 0.55;
  static const taskCardWidth = 268.0;
  static const taskCardPadding = 12.0;
  static const taskIcon = 22.0;
  static const taskChipHeight = 20.0;
  static const taskMetaIndent = 30.0;
  static const taskProgressHeight = 3.0;

  // composer
  static const composerTotal = 84.0;
  static const composerField = 36.0;
  static const composerIcon = 32.0;
  static const sendW = 56.0;
  static const sendH = 32.0;
  static const voiceButtonHeight = 36.0;

  // voice overlay（§15 I11：两态高度统一 107）
  static const voiceOverlayW = 200.0;
  static const voiceOverlayH = 107.0;
  static const voiceOverlayBottom = 96.0;
  static const voiceOverlayRadius = 8.0;
  static const voiceOverlayPad = 14.0;
  static const cancelIcon = 30.0;
  static const voiceWaveSlot = 34.0;
  static const overlayBlur = 12.0; // 浮层背景模糊（DESIGN §8.4）

  // call
  static const callAvatar = 96.0;
  static const callPulseInner = 128.0;
  static const callPulseOuter = 152.0;
  static const callWaveW = 220.0;
  static const callWaveH = 32.0;
  static const callControl = 64.0;
  static const callHangup = 72.0;
  static const callControlsBottom = 92.0;
  static const callControlsGap = 40.0;
  static const callHintW = 280.0;
  static const callHintH = 40.0;
  static const callWaveMaxH = 20.0;
  static const callHighlightBars = 9;
  static const callTopTitleGap = 8.0;
  static const callHintGap = 12.0;
  static const callHintBottom = 20.0;
  static const callTranscriptPadV = 10.0; // 转写条上下内边距
  static const callTranscriptDot = 6.0; // 转写条状态点

  // task detail
  static const stepDot = 11.0; // §15 I6
  static const detailIcon = 40.0;
  static const detailIconRadius = 8.0;
  static const resultIndex = 18.0;
  static const statusDotSize = 6.0; // 状态 chip 静态点（非脉冲时）
  static const noteIcon = 16.0;
  static const hairlineWidth = 0.5;
  static const stepGapX = 12.0;
  static const stepGapY = 12.0;
  static const sectionLabelSize = 13.0;
  static const primaryButtonH = 44.0;

  // misc
  static const taskCardShadowBlur = 2.0;
  static const overlayShadowBlur = 24.0;
}

/// 动效（tokens.motion）
abstract final class XlMotion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const page = Duration(milliseconds: 320);
  static const modal = Duration(milliseconds: 420);

  static const standard = Cubic(0.2, 0.8, 0.2, 1);
  static const decelerate = Cubic(0.16, 1, 0.3, 1);
  static const pageCurve = Cubic(0.32, 0.72, 0, 1);
  static const spring = Cubic(0.34, 1.56, 0.64, 1);

  static const waveBarCount = 11; // §15 I5（语音气泡 11 根；浮层单独用 9 根）
  static const callWaveBarCount = 30;
  static const waveSampleMs = 50;
  static const waveAttackMs = 90;
  static const waveDecayMs = 220;
  static const cancelThreshold = 80.0;
  static const cancelHysteresis = 8.0;

  static const taskPulseMs = 1600;
  static const taskProgressMs = 400;
  static const taskChipMs = 180;
  static const taskHeightMs = 260;
  static const taskCheckMs = 320;

  static const callPulseMs = 2400;
  static const callPulseStaggerMs = 400;
  static const tooShortMs = 800;
}

/// 字体回退栈（顺序不可改：只写 PingFang 会让 Android 中文变宋体感）
const List<String> xlFontFallback = <String>[
  'PingFang SC',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'Microsoft YaHei',
  'Roboto',
];
