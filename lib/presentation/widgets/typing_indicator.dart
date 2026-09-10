import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';

/// AI 正在输入指示器（对齐原型 v6 的三点弹跳）
class TypingIndicator extends StatefulWidget {
  final double dotSize;
  final EdgeInsetsGeometry padding;

  const TypingIndicator({
    super.key,
    this.dotSize = 7,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotColor = isDark ? AppColors.typingDotDark : AppColors.typingDot;
    final bubbleColor =
        isDark ? AppColors.aiMessageBgDark : AppColors.aiMessageBg;

    return Padding(
      padding: widget.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.avatarGray,
            child: const Icon(Icons.smart_toy, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
                topLeft: Radius.circular(2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final local =
                        (_controller.value - i * (0.2 / 1.4)) % 1.0;
                    final c = _curve(local);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: _dot(c, dotColor),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double c, Color color) {
    return Opacity(
      opacity: 0.4 + 0.6 * c,
      child: Transform.translate(
        offset: Offset(0, -6 * c),
        child: Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }

  /// 单点弹跳曲线：0→1(上)→0(下)→0（对齐原型 typingBounce）
  double _curve(double t) {
    if (t < 0) t += 1;
    if (t < 0.3) return t / 0.3;
    if (t < 0.6) return 1 - (t - 0.3) / 0.3;
    return 0.0;
  }
}
