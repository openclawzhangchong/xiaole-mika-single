import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';
import 'xl_task_card.dart';

enum XlStepState { done, running, pending, failed }

class XlTaskStep {
  const XlTaskStep({
    required this.title,
    this.meta,
    this.state = XlStepState.pending,
  });

  final String title;
  final String? meta;
  final XlStepState state;
}

/// 任务详情步骤时间线（步骤点 11pt，§15 I6；已完成实心对勾 / 当前脉冲 / 未开始描边）
class XlTaskStepTimeline extends StatelessWidget {
  const XlTaskStepTimeline({super.key, required this.steps, this.padding});

  final List<XlTaskStep> steps;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        children: List.generate(steps.length, (i) {
          final step = steps[i];
          final last = i == steps.length - 1;
          final running = step.state == XlStepState.running;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: XlDims.stepDot,
                  child: Column(
                    children: [
                      _StepDot(state: step.state, palette: p),
                      if (!last)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: p.hairline,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: XlDims.stepGapX),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: last ? 0 : XlDims.stepGapY,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontSize: XlType.cardTitle.fontSize,
                            fontWeight: running
                                ? FontWeight.w600
                                : FontWeight.w500,
                            height: XlType.cardTitle.height,
                            color: step.state == XlStepState.pending
                                ? p.textSecondary
                                : p.textPrimary,
                          ),
                        ),
                        if (step.meta != null && step.meta!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            step.meta!,
                            style:
                                XlType.meta.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.state, required this.palette});

  final XlStepState state;
  final XlPalette palette;

  @override
  Widget build(BuildContext context) {
    final size = XlDims.stepDot;
    switch (state) {
      case XlStepState.done:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: palette.brandDeep,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.check_rounded, size: 8, color: palette.surface),
        );
      case XlStepState.running:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.brand, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: palette.brand,
              shape: BoxShape.circle,
            ),
          ),
        );
      case XlStepState.failed:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: palette.danger,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.close_rounded, size: 8, color: Colors.white),
        );
      case XlStepState.pending:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.textQuaternary, width: 1.5),
          ),
        );
    }
  }
}

/// 任务详情头部：状态行（复用 chip 语义色）
class XlTaskDetailStatus extends StatelessWidget {
  const XlTaskDetailStatus({
    super.key,
    required this.status,
    required this.text,
  });

  final XlTaskStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final color = switch (status) {
      XlTaskStatus.queued => p.taskQueued.text,
      XlTaskStatus.running => p.taskRunning.text,
      XlTaskStatus.done => p.brandDeep,
      XlTaskStatus.failed => p.dangerText,
      XlTaskStatus.cancelled => p.textSecondary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 18 / 13,
            color: color,
          ),
        ),
      ],
    );
  }
}
