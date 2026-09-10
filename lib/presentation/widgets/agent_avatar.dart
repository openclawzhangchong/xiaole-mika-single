import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';

/// 智能体预设头像（原型 v6 的 10 套渐变 + 符号）
class AgentAvatarStyle {
  final List<Color> colors;
  final String symbol;
  final bool darkText;

  const AgentAvatarStyle({
    required this.colors,
    required this.symbol,
    this.darkText = false,
  });
}

const List<AgentAvatarStyle> kAgentAvatarStyles = [
  AgentAvatarStyle(colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)], symbol: '✨'),
  AgentAvatarStyle(colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)], symbol: '☀'),
  AgentAvatarStyle(colors: [Color(0xFF667EEA), Color(0xFF764BA2)], symbol: '★'),
  AgentAvatarStyle(colors: [Color(0xFFF093FB), Color(0xFFF5576C)], symbol: '♨'),
  AgentAvatarStyle(colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)], symbol: '☎'),
  AgentAvatarStyle(colors: [Color(0xFF43E97B), Color(0xFF38F9D7)], symbol: '◎'),
  AgentAvatarStyle(colors: [Color(0xFFFA709A), Color(0xFFFEE140)], symbol: '♠'),
  AgentAvatarStyle(colors: [Color(0xFF30CFD0), Color(0xFF330867)], symbol: '♥'),
  AgentAvatarStyle(
    colors: [Color(0xFFA8EDEA), Color(0xFFFED6E3)],
    symbol: '☢',
    darkText: true,
  ),
  AgentAvatarStyle(
    colors: [Color(0xFFFF9A9E), Color(0xFFFECFEF)],
    symbol: '☘',
    darkText: true,
  ),
];

/// 智能体头像组件
///
/// [styleIndex] 预设样式索引（0-9），[size] 边长，[radius] 圆角
class AgentAvatar extends StatelessWidget {
  final int styleIndex;
  final double size;
  final double? radius;
  final bool showOnlineDot;
  final bool online;

  const AgentAvatar({
    super.key,
    required this.styleIndex,
    this.size = 48,
    this.radius,
    this.showOnlineDot = false,
    this.online = false,
  });

  @override
  Widget build(BuildContext context) {
    final style =
        kAgentAvatarStyles[styleIndex % kAgentAvatarStyles.length];
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size / 5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        style.symbol,
        style: TextStyle(
          fontSize: size * 0.45,
          color: style.darkText ? const Color(0xFF444444) : Colors.white,
        ),
      ),
    );

    if (!showOnlineDot) return avatar;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.statusOnline,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppColors.surfaceDark : AppColors.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 用户头像（原型：蓝紫渐变 + 名字首字）
class UserAvatar extends StatelessWidget {
  final String name;
  final double size;
  final double? radius;

  const UserAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final firstChar = name.isNotEmpty ? name.characters.first : '我';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size / 5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.userAvatarStart, AppColors.userAvatarEnd],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
