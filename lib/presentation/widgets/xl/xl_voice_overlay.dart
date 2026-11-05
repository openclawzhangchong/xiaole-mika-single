import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';

/// 竖条波形（preview-03 浮层 11 根、3pt 柱 / 3pt 隙；通话页仍 30 根）
/// 采样 20Hz、上升 90ms / 下降 220ms、静音保留 0.12 基线。
class XlVoiceWave extends StatefulWidget {
  const XlVoiceWave({
    super.key,
    required this.amplitudeStream,
    this.active = true,
    this.width = 53,
    this.height = 34,
    this.maxBarHeight = 18,
    this.color = Colors.white,
    this.highlightColor,
    this.highlightBars = 0,
    this.barCount = 11,
    this.barWidth = 3,
    this.barGap = 2,
    this.profile,
  });

  final Stream<double> amplitudeStream;
  final bool active;
  final double width;
  final double height;
  final double maxBarHeight;
  final Color color;
  final Color? highlightColor;
  final int highlightBars; // 中间高亮根数（通话页用 9，浮层用 3）
  final int barCount;
  final double barWidth;
  final double barGap;

  /// 逐根起伏包络（0–1）。null = 用原正弦包络（通话页）。
  final List<double>? profile;

  @override
  State<XlVoiceWave> createState() => _XlVoiceWaveState();
}

class _XlVoiceWaveState extends State<XlVoiceWave> {
  StreamSubscription<double>? _sub;
  late List<double> _levels = List<double>.filled(widget.barCount, 0.12);
  late List<bool> _rising = List<bool>.filled(widget.barCount, false);

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(XlVoiceWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.amplitudeStream != widget.amplitudeStream) {
      _bind();
    }
    if (oldWidget.barCount != widget.barCount) {
      _levels = List<double>.filled(widget.barCount, 0.12);
      _rising = List<bool>.filled(widget.barCount, false);
    }
  }

  void _bind() {
    _sub?.cancel();
    if (!widget.active) return;
    _sub = widget.amplitudeStream.listen((rms) {
      if (!mounted) return;
      final count = widget.barCount;
      final base = (0.45 + 0.55 * rms).clamp(0.12, 1.0).toDouble();
      final next = List<double>.generate(count, (i) {
        final shape = widget.profile != null
            ? widget.profile![i % widget.profile!.length]
            : 0.55 + 0.45 * math.sin((i / (count - 1)) * math.pi);
        return (base * shape).clamp(0.12, 1.0).toDouble();
      });
      final rising = List<bool>.generate(
        count,
        (i) => next[i] >= _levels[i],
      );
      setState(() {
        _levels = next;
        _rising = rising;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.barCount;
    final barsWidth =
        count * widget.barWidth + (count - 1) * widget.barGap;
    final actualWidth = widget.width < barsWidth ? barsWidth : widget.width;
    final centerStart = (count - widget.highlightBars) ~/ 2;
    final centerEnd = centerStart + widget.highlightBars;

    return SizedBox(
      width: actualWidth,
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(count, (i) {
          final highlight = widget.highlightBars > 0 &&
              i >= centerStart &&
              i < centerEnd;
          final barColor =
              highlight ? (widget.highlightColor ?? widget.color) : widget.color;
          final h = widget.active
              ? (widget.maxBarHeight * _levels[i])
                  .clamp(2.0, widget.maxBarHeight)
                  .toDouble()
              : widget.maxBarHeight * 0.12;
          return Padding(
            padding: EdgeInsets.only(
              right: i == count - 1 ? 0 : widget.barGap,
            ),
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: widget.active
                    ? (_rising[i]
                        ? XlMotion.waveAttackMs
                        : XlMotion.waveDecayMs)
                    : XlMotion.fast.inMilliseconds,
              ),
              curve: Curves.easeOut,
              width: widget.barWidth,
              height: h,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 录音浮层（两态高度统一 107pt，§15 I11；只换色与内容，不换布局）
class XlVoiceRecordOverlay extends StatelessWidget {
  const XlVoiceRecordOverlay({
    super.key,
    required this.amplitudeStream,
    required this.elapsed,
    required this.willCancel,
    this.showLimitHint = false,
    this.hintOverride,
  });

  final Stream<double> amplitudeStream;
  final Duration elapsed;
  final bool willCancel;
  final bool showLimitHint;

  /// v6.11.18：<800ms 误触等场景的临时提示，优先于默认提示文案
  final String? hintOverride;

  String get _duration {
    final m = elapsed.inMinutes;
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final hint = hintOverride ??
        (willCancel
            ? '松开手指，取消发送'
            : (showLimitHint ? '松开发送，最长 60 秒' : '手指上滑，取消发送'));

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(XlDims.voiceOverlayRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: XlDims.overlayBlur,
            sigmaY: XlDims.overlayBlur,
          ),
          child: Container(
        width: XlDims.voiceOverlayW,
        height: XlDims.voiceOverlayH,
        padding: const EdgeInsets.symmetric(
          horizontal: XlDims.voiceOverlayPad,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: p.overlay,
          borderRadius: BorderRadius.circular(XlDims.voiceOverlayRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              offset: Offset(0, 8),
              blurRadius: XlDims.overlayShadowBlur,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: XlDims.voiceWaveSlot,
              child: Center(
                child: AnimatedSwitcher(
                  duration: XlMotion.fast,
                  child: willCancel
                      ? _CancelMark(key: const ValueKey<String>('cancel'))
                      : XlVoiceWave(
                          key: const ValueKey<String>('wave'),
                          amplitudeStream: amplitudeStream,
                          width: 63, // 11 根 × 3pt + 10 × 3pt 隙（preview-03 实测 126px@2x）
                          height: XlDims.voiceWaveSlot,
                          maxBarHeight: XlDims.voiceWaveBarMaxH,
                          color: XlColor.mint,
                          highlightColor: XlColor.mint,
                          highlightBars: 3,
                          barCount: XlDims.voiceWaveBarCount,
                          barWidth: XlDims.voiceWaveBarW,
                          barGap: XlDims.voiceWaveGap,
                          profile: XlDims.voiceWaveProfile,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _duration,
              style: XlType.callTimer.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: XlMotion.fast,
              child: willCancel
                  ? Container(
                      key: const ValueKey<String>('cancel_hint'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.dangerText,
                        borderRadius: BorderRadius.circular(XlDims.rS),
                      ),
                      child: Text(
                        hint,
                        style: XlType.caption.copyWith(color: Colors.white),
                      ),
                    )
                  : Text(
                      hint,
                      key: const ValueKey<String>('normal_hint'),
                      style: XlType.caption.copyWith(
                        color: Colors.white.withOpacity(0.72),
                      ),
                    ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

class _CancelMark extends StatelessWidget {
  const _CancelMark({super.key});

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Container(
      width: XlDims.cancelIcon,
      height: XlDims.cancelIcon,
      decoration: BoxDecoration(
        color: p.danger.withOpacity(0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.close_rounded, size: 18, color: XlColor.cancelMark),
    );
  }
}

/// 录音浮层状态。
///
/// 浮层不再挂独立 `OverlayEntry`：`BackdropFilter` 只能采样同一合成层里
/// 已经绘制的内容，挂在应用级 Overlay 上时底下路由是另一个图层，
/// 模糊因此完全不生效（真机实测卡面灰度均匀、边缘单像素硬过渡）。
/// 改由聊天页 `Stack` 内的兄弟节点渲染，位于消息列表之上、输入栏之上。
class XlVoiceOverlayState {
  const XlVoiceOverlayState({
    this.visible = false,
    this.willCancel = false,
    this.elapsed = Duration.zero,
    this.showLimitHint = false,
    this.hintOverride,
  });

  static const XlVoiceOverlayState hidden = XlVoiceOverlayState();

  final bool visible;
  final bool willCancel;
  final Duration elapsed;
  final bool showLimitHint;
  final String? hintOverride;

  XlVoiceOverlayState copyWith({
    bool? visible,
    bool? willCancel,
    Duration? elapsed,
    bool? showLimitHint,
    String? hintOverride,
  }) {
    return XlVoiceOverlayState(
      visible: visible ?? this.visible,
      willCancel: willCancel ?? this.willCancel,
      elapsed: elapsed ?? this.elapsed,
      showLimitHint: showLimitHint ?? this.showLimitHint,
      hintOverride: hintOverride ?? this.hintOverride,
    );
  }
}
