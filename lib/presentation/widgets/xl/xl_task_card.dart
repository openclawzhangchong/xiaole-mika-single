import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';

/// 任务卡状态机（DESIGN §8.2 / §8.8，5 态）
enum XlTaskStatus { queued, running, done, failed, cancelled }

/// 任务卡数据（不持久化，由业务层注入真实进度；`progress == null` 不画假进度）
class XlTaskCardModel {
  const XlTaskCardModel({
    required this.title,
    required this.status,
    this.icon = Icons.checklist_rounded,
    this.stepIndex = 0,
    this.stepTotal = 0,
    this.elapsed = Duration.zero,
    this.progress,
    this.failReason,
    this.canAbort = false,
    this.canRetry = false,
    this.canCancel = false,
    this.timeLabel,
  });

  final String title;
  final XlTaskStatus status;
  final IconData icon;
  final int stepIndex; // 1-based
  final int stepTotal;
  final Duration elapsed;
  final double? progress; // 0–1，null = 不显示
  final String? failReason;
  final bool canAbort;
  final bool canRetry;
  final bool canCancel;
  final String? timeLabel; // 完成态 meta 尾部时间，如 21:06
}

/// 268pt 任务卡：头部 22 / meta / 进度 / footer 36
class XlTaskCard extends StatelessWidget {
  const XlTaskCard({
    super.key,
    required this.model,
    this.onTap,
    this.onAbort,
    this.onCancel,
    this.onRetry,
    this.width = XlDims.taskCardWidth,
  });

  final XlTaskCardModel model;
  final VoidCallback? onTap;
  final VoidCallback? onAbort;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final c = _statusColors(p);
    final accent = _accentColor(p);
    final showMeta = _metaText() != null;
    final showProgress =
        model.status == XlTaskStatus.running && model.progress != null;
    final showFooter = onTap != null || _footerActionLabel != null;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            XlDims.taskCardPadding,
            XlDims.taskCardPadding,
            XlDims.taskCardPadding,
            XlDims.taskCardPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 头部 22pt：图标 22×22 / 标题 15-600 / chip 20
              SizedBox(
                height: XlDims.taskIcon,
                child: Row(
                  children: [
                    Container(
                      width: XlDims.taskIcon,
                      height: XlDims.taskIcon,
                      decoration: BoxDecoration(
                        color: c.iconBg,
                        borderRadius: BorderRadius.circular(XlDims.rM),
                      ),
                      alignment: Alignment.center,
                      child: Icon(model.icon, size: 14, color: c.icon),
                    ),
                    const SizedBox(width: XlDims.s),
                    Expanded(
                      child: Text(
                        model.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: XlType.cardTitle.copyWith(color: p.textPrimary),
                      ),
                    ),
                    const SizedBox(width: XlDims.xs),
                    XlTaskStatusChip(
                      status: model.status,
                      colors: c,
                      accent: accent,
                    ),
                  ],
                ),
              ),
              if (showMeta) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: XlDims.taskMetaIndent),
                  child: Text(
                    _metaText()!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: XlType.meta.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
              if (model.status == XlTaskStatus.failed &&
                  (model.failReason?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: XlDims.taskMetaIndent),
                  child: Text(
                    model.failReason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: XlType.meta.copyWith(color: p.dangerText),
                  ),
                ),
              ],
              if (showProgress) ...[
                const SizedBox(height: XlDims.s),
                _XlTaskProgress(
                  value: model.progress!.clamp(0.0, 1.0).toDouble(),
                  track: p.progressTrack,
                  fill: p.progressFill,
                ),
              ],
            ],
          ),
        ),
        if (showFooter)
          Container(
            height: XlDims.taskFooter,
            padding: const EdgeInsets.symmetric(horizontal: XlDims.s),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.hairline, width: 0.5)),
            ),
            child: Row(
              children: [
                _FooterLink(
                  label: '查看详情',
                  color: p.link,
                  showChevron: true,
                  onTap: onTap,
                ),
                const Spacer(),
                if (_footerActionLabel != null)
                  _FooterLink(
                    label: _footerActionLabel!,
                    color: model.status == XlTaskStatus.failed
                        ? p.link
                        : p.dangerText,
                    onTap: _footerAction,
                  ),
              ],
            ),
          ),
      ],
    );

    return Semantics(
      container: true,
      label: _semanticsLabel(),
      button: onTap != null,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(XlDims.rCard),
          border: p.isDark
              ? Border.all(color: p.hairline, width: 0.5)
              : null,
          boxShadow: p.isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(XlDims.rCard),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashFactory: NoSplash.splashFactory,
                highlightColor: p.pressed,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  XlTaskColors _statusColors(XlPalette p) {
    switch (model.status) {
      case XlTaskStatus.queued:
        return p.taskQueued;
      case XlTaskStatus.running:
        return p.taskRunning;
      case XlTaskStatus.done:
        return p.taskDone;
      case XlTaskStatus.failed:
        return p.taskFailed;
      case XlTaskStatus.cancelled:
        return XlTaskColors(
          dot: p.textQuaternary,
          text: p.textSecondary,
          bg: p.subtle,
          iconBg: p.subtle,
          icon: p.textTertiary,
        );
    }
  }

  Color _accentColor(XlPalette p) {
    switch (model.status) {
      case XlTaskStatus.queued:
        return p.taskQueued.dot;
      case XlTaskStatus.running:
        return p.taskRunning.dot;
      case XlTaskStatus.done:
        return p.taskDone.dot;
      case XlTaskStatus.failed:
        return p.taskFailed.dot;
      case XlTaskStatus.cancelled:
        return p.textQuaternary;
    }
  }

  /// §15 B2：排队态不出现任何"预计剩余时间"文案。
  String? _metaText() {
    final secs = (model.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    switch (model.status) {
      case XlTaskStatus.queued:
        return null;
      case XlTaskStatus.running:
        if (model.stepTotal > 0) {
          return '第 ${model.stepIndex} / ${model.stepTotal} 步 · 已用 $secs 秒';
        }
        // 引擎只报当前第几步、不报总步数时，如实显示"第 N 步"，不补假分母
        if (model.stepIndex > 0) {
          return '第 ${model.stepIndex} 步 · 已用 $secs 秒';
        }
        return '已用 $secs 秒';
      case XlTaskStatus.done:
        return model.timeLabel == null
            ? '用时 $secs 秒'
            : '用时 $secs 秒 · ${model.timeLabel}';
      case XlTaskStatus.failed:
        if (model.stepTotal > 0) {
          return '第 ${model.stepIndex} / ${model.stepTotal} 步 · 用时 $secs 秒';
        }
        return '用时 $secs 秒';
      case XlTaskStatus.cancelled:
        return null;
    }
  }

  String? get _footerActionLabel {
    switch (model.status) {
      case XlTaskStatus.queued:
        return model.canCancel ? '取消' : null;
      case XlTaskStatus.running:
        return model.canAbort ? '中止' : null;
      case XlTaskStatus.done:
        return null;
      case XlTaskStatus.failed:
        return model.canRetry ? '重试' : null;
      case XlTaskStatus.cancelled:
        return null;
    }
  }

  VoidCallback? get _footerAction {
    switch (model.status) {
      case XlTaskStatus.queued:
        return onCancel;
      case XlTaskStatus.running:
        return onAbort;
      case XlTaskStatus.failed:
        return onRetry;
      case XlTaskStatus.done:
      case XlTaskStatus.cancelled:
        return null;
    }
  }

  String _semanticsLabel() {
    final status = switch (model.status) {
      XlTaskStatus.queued => '排队中',
      XlTaskStatus.running => '执行中',
      XlTaskStatus.done => '已完成',
      XlTaskStatus.failed => '失败',
      XlTaskStatus.cancelled => '已中止',
    };
    final meta = _metaText();
    return '任务：${model.title}，$status'
        '${meta == null ? '' : '，${meta.replaceAll(' · ', '，')}，'}'
        '双击查看详情';
  }
}

/// 状态 chip：高 20 / 全圆角 / 11pt；状态不只靠颜色（点/勾/叉 + 文案）
class XlTaskStatusChip extends StatelessWidget {
  const XlTaskStatusChip({
    super.key,
    required this.status,
    required this.colors,
    required this.accent,
  });

  final XlTaskStatus status;
  final XlTaskColors colors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      XlTaskStatus.queued => '排队中',
      XlTaskStatus.running => '执行中',
      XlTaskStatus.done => '已完成',
      XlTaskStatus.failed => '失败',
      XlTaskStatus.cancelled => '已中止',
    };

    final mark = switch (status) {
      XlTaskStatus.running => _PulseDot(color: accent),
      XlTaskStatus.queued || XlTaskStatus.cancelled =>
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
      XlTaskStatus.done => Icon(Icons.check_rounded, size: 12, color: accent),
      XlTaskStatus.failed => Icon(Icons.close_rounded, size: 12, color: accent),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: XlMotion.standard,
      height: XlDims.taskChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(XlDims.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: SizedBox(
              key: ValueKey<String>('${status.name}_mark'),
              width: 12,
              height: 12,
              child: Center(child: mark),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: XlType.caption.copyWith(color: colors.text),
          ),
        ],
      ),
    );
  }
}

/// 执行中绿点 + 脉冲光圈（1600ms / linear；一屏只应由业务层保留一个）
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return _dot(6);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return SizedBox(
          width: 12,
          height: 12,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (0.45 * (1 - t)).clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 6 * (1 + 0.9 * t),
                  height: 6 * (1 + 0.9 * t),
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              _dot(6),
            ],
          ),
        );
      },
    );
  }

  Widget _dot(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
}

/// 3pt 真实进度（400ms 填充；无真实值时不传）
class _XlTaskProgress extends StatelessWidget {
  const _XlTaskProgress({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(XlDims.rXs),
      child: SizedBox(
        height: XlDims.taskProgressHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 400),
              curve: XlMotion.standard,
              builder: (context, v, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  child: ColoredBox(color: fill),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// footer 动作：链接色/危险色文字，整块 44×36 命中区
class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.color,
    this.onTap,
    this.showChevron = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: XlType.meta.copyWith(color: color)),
              if (showChevron) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 14, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
