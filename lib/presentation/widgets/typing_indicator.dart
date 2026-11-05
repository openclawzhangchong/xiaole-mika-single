import 'package:flutter/material.dart';

import '../../app/themes/xl_tokens.dart';

/// AI 正在输入指示器（对齐原型 v6 的三点弹跳；气泡随设计令牌）
class TypingIndicator extends StatefulWidget {
  final double dotSize;
  final EdgeInsetsGeometry padding;

  const TypingIndicator({
    super.key,
    this.dotSize = 7,
    this.padding = const EdgeInsets.symmetric(
      horizontal: XlDims.pagePadding,
      vertical: XlDims.bubbleGap / 2,
    ),
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
    final p = XlPalette.of(context);
    final dotColor = p.textQuaternary;
    final bubbleColor = p.bubbleOtherBg;

    return Padding(
      padding: widget.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: XlDims.chatAvatar,
            height: XlDims.chatAvatar,
            decoration: BoxDecoration(
              color: p.brandSoft,
              borderRadius: BorderRadius.circular(XlDims.avatarChat),
            ),
            child: Icon(Icons.graphic_eq_rounded, size: 22, color: p.brandDeep),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(XlDims.rBubble),
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
