import 'dart:math';

import 'package:flutter/material.dart';

/// 全屏动图表情（v4.2.0 申请书 6 号：AI 表情从静态 emoji 升级为动图动画）
///
/// 对齐真机 otto-emoji-gif 表现：AI 说话时屏幕上「活」起来的表情动画。
/// 纯 Flutter 内建动画（零新依赖、零外部资源）：
/// - happy    😊 上下蹦跳 + 缩放脉冲
/// - laughing 😆 大幅快弹 + 左右摇摆
/// - cool     😎 滑入 + 摇滚摆
/// - sad      😢 下落 + 渐隐
/// - angry    😠 抖动 + 红色光晕
/// 播放约 1.8s 后自动缩小消失（onDone 回调移除）。
class EmotionAnimationOverlay extends StatefulWidget {
  final String emoji;
  final String emotion; // happy/laughing/cool/sad/angry
  final VoidCallback onDone;

  const EmotionAnimationOverlay({
    super.key,
    required this.emoji,
    required this.emotion,
    required this.onDone,
  });

  @override
  State<EmotionAnimationOverlay> createState() =>
      _EmotionAnimationOverlayState();
}

class _EmotionAnimationOverlayState extends State<EmotionAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _dx;
  late final Animation<double> _dy;
  late final Animation<double> _rot;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));

    // 总体生命周期：快速进场 → 停留 → 尾段缩小消失
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 72),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 16),
    ]).animate(_ctl);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 1.15)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 62),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.4)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 18),
    ]).animate(_ctl);

    switch (widget.emotion) {
      case 'laughing': // 大幅快弹 + 摇摆
        _dy = TweenSequence<double>([
          for (int i = 0; i < 4; i++) ...[
            TweenSequenceItem(tween: Tween(begin: 0.0, end: -34.0), weight: 9),
            TweenSequenceItem(tween: Tween(begin: -34.0, end: 0.0), weight: 9),
          ],
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 64),
        ]).animate(_ctl);
        _dx = TweenSequence<double>([
          for (int i = 0; i < 3; i++) ...[
            TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 12),
            TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 12),
          ],
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 52),
        ]).animate(_ctl);
        _rot = ConstantTween(0.0).animate(_ctl);
        break;
      case 'cool': // 从左滑入 + 摇滚摆
        _dx = TweenSequence<double>([
          TweenSequenceItem(
              tween: Tween(begin: -120.0, end: 0.0)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
              weight: 25),
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 55),
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 60.0), weight: 20),
        ]).animate(_ctl);
        _dy = ConstantTween(0.0).animate(_ctl);
        _rot = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: -0.35, end: 0.0), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.12), weight: 15),
          TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 15),
          TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.0), weight: 15),
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
        ]).animate(_ctl);
        break;
      case 'sad': // 从上方落下 + 轻微左右漂
        _dy = TweenSequence<double>([
          TweenSequenceItem(
              tween: Tween(begin: -90.0, end: 0.0)
                  .chain(CurveTween(curve: Curves.easeIn)),
              weight: 30),
          TweenSequenceItem(
              tween: Tween(begin: 0.0, end: -8.0), weight: 8), // 小回弹
          TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0), weight: 8),
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 54),
        ]).animate(_ctl);
        _dx = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 6.0), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0), weight: 25),
          TweenSequenceItem(tween: Tween(begin: -6.0, end: 0.0), weight: 25),
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 25),
        ]).animate(_ctl);
        _rot = ConstantTween(0.0).animate(_ctl);
        break;
      case 'angry': // 急促抖动
        _dx = TweenSequence<double>([
          for (int i = 0; i < 6; i++) ...[
            TweenSequenceItem(tween: Tween(begin: -7.0, end: 7.0), weight: 5),
            TweenSequenceItem(tween: Tween(begin: 7.0, end: -7.0), weight: 5),
          ],
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
        ]).animate(_ctl);
        _dy = ConstantTween(0.0).animate(_ctl);
        _rot = ConstantTween(0.0).animate(_ctl);
        break;
      default: // happy：上下蹦跳
        _dy = TweenSequence<double>([
          for (int i = 0; i < 3; i++) ...[
            TweenSequenceItem(
                tween: Tween(begin: 0.0, end: -30.0)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 10),
            TweenSequenceItem(
                tween: Tween(begin: -30.0, end: 0.0)
                    .chain(CurveTween(curve: Curves.easeIn)),
                weight: 10),
          ],
          TweenSequenceItem(tween: ConstantTween(0.0), weight: 60),
        ]).animate(_ctl);
        _dx = ConstantTween(0.0).animate(_ctl);
        _rot = ConstantTween(0.0).animate(_ctl);
    }

    _ctl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // angry 附加红色光晕
    final isAngry = widget.emotion == 'angry';
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true, // 动画不挡操作
        child: Center(
          child: AnimatedBuilder(
            animation: _ctl,
            builder: (context, child) => Opacity(
              opacity: _fade.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(_dx.value, _dy.value),
                child: Transform.rotate(
                  angle: _rot.value,
                  child: Transform.scale(
                    scale: max(0.1, _scale.value),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isAngry
                            ? [
                                BoxShadow(
                                  color: Colors.red.withOpacity(
                                      (0.35 * _fade.value).clamp(0.0, 1.0)),
                                  blurRadius: 40,
                                  spreadRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        widget.emoji,
                        style: const TextStyle(fontSize: 110),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
