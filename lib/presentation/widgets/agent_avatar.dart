import 'dart:io';

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../presentation/services/agent_avatar_store.dart';

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
/// 扩展（C 项：头像升级）：
/// - [agentId] 非空 → 走新的「文字 / 图片」头像（读本地配置：有图片用图片，否则文字 + 色板）；
/// - [agentId] 为空且 [configOverride] 为空 → 完全沿用旧的渐变 + 符号渲染
///   （这样 `profile_header.dart` 一行不改、视觉不变）。
/// - [configOverride] 提供时（配置页预览）直接用该配置渲染，不读存储。
/// - [name] 文字头像取字来源，默认 '小乐'。
/// - [styleIndex] 旧渐变 + 符号的兜底索引（默认 0），仅在无 agentId 时生效。
class AgentAvatar extends StatelessWidget {
  final int? styleIndex;
  final String? agentId;
  final String? name;
  final AgentAvatarConfig? configOverride;
  final double size;
  final double? radius;
  final bool showOnlineDot;
  final bool online;

  const AgentAvatar({
    super.key,
    this.styleIndex = 0,
    this.agentId,
    this.name,
    this.configOverride,
    this.size = 48,
    this.radius,
    this.showOnlineDot = false,
    this.online = false,
  });

  @override
  Widget build(BuildContext context) {
    if (agentId == null && configOverride == null) {
      return _buildLegacy(context);
    }
    // 新头像：监听 revision 实现跨页刷新；首帧同步读缓存（已是稳定文字头像，不闪烁）。
    return ValueListenableBuilder<int>(
      valueListenable: AgentAvatarStore.revision,
      builder: (context, _, __) {
        final cfg = configOverride ?? AgentAvatarStore.read(agentId!);
        return _buildBody(context, cfg);
      },
    );
  }

  /// 旧渐变 + 符号渲染（profile_header 等无 agentId 场景）。保持不变。
  Widget _buildLegacy(BuildContext context) {
    final idx = (styleIndex ?? 0) % kAgentAvatarStyles.length;
    final style = kAgentAvatarStyles[idx];
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

  Widget _buildBody(BuildContext context, AgentAvatarConfig cfg) {
    final displayName =
        (name != null && name!.trim().isNotEmpty) ? name! : '小乐';
    final double r = radius ?? size / 5;

    final Widget avatar;
    if (cfg.imagePath != null) {
      final file = File(cfg.imagePath!);
      if (file.existsSync()) {
        avatar = ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _textInner(displayName, cfg, r),
          ),
        );
      } else {
        // 文件不存在（典型：重装 App 后路径失效）→ 优雅回落文字头像
        avatar = _textInner(displayName, cfg, r);
      }
    } else {
      avatar = _textInner(displayName, cfg, r);
    }

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

  Widget _textInner(String displayName, AgentAvatarConfig cfg, double r) {
    final palette =
        kAgentAvatarPalette[cfg.paletteIndex % kAgentAvatarPalette.length];
    final ch = AgentAvatarStore.pickDisplayChar(
      displayName,
      cfg.mode,
      cfg.customChar,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.bg,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: palette.fg,
        ),
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
