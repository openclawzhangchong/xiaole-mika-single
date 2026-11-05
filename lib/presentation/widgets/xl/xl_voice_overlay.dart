import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';

/// 11 根竖条波形（tokens.motion.voice.waveBarCount = 11，§15 I5）
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
      final base = (0.35 + 0.65 * rms).clamp(0.12, 1.0).toDouble();
      final next = List<double>.generate(count, (i) {
        final phase = (i / (count - 1)) * math.pi;
        final shape = 0.55 + 0.45 * math.sin(phase);
        return (base * (0.35 + 0.65 * shape)).clamp(0.12, 1.0).toDouble();
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
  });

  final Stream<double> amplitudeStream;
  final Duration elapsed;
  final bool willCancel;
  final bool showLimitHint;

  String get _duration {
    final m = elapsed.inMinutes;
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final hint = willCancel
        ? '松开手指，取消发送'
        : (showLimitHint ? '松开发送，最长 60 秒' : '上滑取消');

    return ExcludeSemantics(
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
                          width: 53,
                          height: XlDims.voiceWaveSlot,
                          maxBarHeight: 18,
                          color: Colors.white,
                          highlightColor: XlColor.brand,
                          highlightBars: 3,
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
                        borderRadius: BorderRadius.circular(XlDims.rPill),
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
      child: Icon(Icons.close_rounded, size: 18, color: p.danger),
    );
  }
}
