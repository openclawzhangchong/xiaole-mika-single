import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/themes/xl_tokens.dart';
import '../../widgets/xl/xl_step_timeline.dart';
import '../../widgets/xl/xl_task_card.dart';

/// 任务详情数据（由任务卡 / 消息 metadata 注入，页面不编造业务数据）
class XlTaskDetailData {
  const XlTaskDetailData({
    required this.title,
    required this.status,
    this.icon = Icons.checklist_rounded,
    this.elapsed = Duration.zero,
    this.stepIndex = 0,
    this.stepTotal = 0,
    this.startedAt = '今天',
    this.device = '当前手机',
    this.trigger = '对话内指令',
    this.steps = const <XlTaskStep>[],
    this.results = const <String>[],
  });

  final String title;
  final XlTaskStatus status;
  final IconData icon;
  final Duration elapsed;
  final int stepIndex;
  final int stepTotal;
  final String startedAt;
  final String device;
  final String trigger;
  final List<XlTaskStep> steps;
  final List<String> results;
}

/// 任务详情（DESIGN §9）：导航 44 / hero 卡 / 步骤时间线 11pt / 结果 / 隐私事实 / 再次执行 44
class XlTaskDetailPage extends StatelessWidget {
  const XlTaskDetailPage({
    super.key,
    required this.data,
    this.onReRun,
    this.onMore,
  });

  final XlTaskDetailData data;
  final VoidCallback? onReRun;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('任务详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '返回',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 24),
            onPressed: onMore ??
                () {
                  // 无销毁 / 编辑类不可逆动作，不弹空菜单
                },
            tooltip: '更多',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            XlDims.pagePadding,
            XlDims.m,
            XlDims.pagePadding,
            XlDims.xxl,
          ),
          children: [
            _HeroCard(data: data),
            const SizedBox(height: XlDims.xxl),
            _SectionLabel('执行步骤'),
            const SizedBox(height: XlDims.s),
            _SurfaceCard(
              child: XlTaskStepTimeline(steps: data.steps),
            ),
            if (data.results.isNotEmpty) ...[
              const SizedBox(height: XlDims.xxl),
              _SectionLabel('结果'),
              const SizedBox(height: XlDims.s),
              _SurfaceCard(child: _ResultList(results: data.results)),
            ],
            const SizedBox(height: XlDims.xxl),
            _PrivacyNote(status: data.status),
            const SizedBox(height: XlDims.xxl),
            SizedBox(
              height: XlDims.primaryButtonH,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onReRun ?? () => _notifyManual(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.brandDeep,
                  disabledBackgroundColor: p.brandDeep.withOpacity(0.4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(XlDims.rButton),
                  ),
                  textStyle: XlType.button,
                ),
                child: const Text('再次执行'),
              ),
            ),
            const SizedBox(height: XlDims.s),
            TextButton(
              onPressed: () => _copyResult(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(120, 44),
                foregroundColor: p.link,
              ),
              child: const Text('复制结果'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyResult(BuildContext context) async {
    final text = data.results.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('结果已复制')),
    );
  }

  void _notifyManual(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请在对话中重新发起任务')),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.data});

  final XlTaskDetailData data;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final c = _statusColors(p, data.status);
    final secs = (data.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final statusText = switch (data.status) {
      XlTaskStatus.queued => '排队中',
      XlTaskStatus.running =>
        data.stepTotal > 0 ? '执行中 · 第 ${data.stepIndex}/${data.stepTotal} 步' : '执行中',
      XlTaskStatus.done => '已完成 · 用时 $secs 秒',
      XlTaskStatus.failed => '失败 · 用时 $secs 秒',
      XlTaskStatus.cancelled => '已中止',
    };

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(XlDims.rCard),
        border: p.isDark ? Border.all(color: p.hairline, width: 0.5) : null,
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
      padding: const EdgeInsets.all(XlDims.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: XlDims.detailIcon,
                height: XlDims.detailIcon,
                decoration: BoxDecoration(
                  color: c.iconBg,
                  borderRadius:
                      BorderRadius.circular(XlDims.detailIconRadius),
                ),
                alignment: Alignment.center,
                child: Icon(data.icon, size: 22, color: c.icon),
              ),
              const SizedBox(width: XlDims.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: XlType.navTitle.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    XlTaskDetailStatus(
                      status: data.status,
                      text: statusText,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: XlDims.l),
          Divider(height: 0.5, color: p.hairline),
          const SizedBox(height: XlDims.l),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _MetaCell(label: '发起时间', value: data.startedAt),
                ),
                VerticalDivider(width: 1, color: p.hairline),
                Expanded(
                  child: _MetaCell(label: '执行设备', value: data.device),
                ),
                VerticalDivider(width: 1, color: p.hairline),
                Expanded(
                  child: _MetaCell(label: '触发方式', value: data.trigger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  XlTaskColors _statusColors(XlPalette p, XlTaskStatus status) {
    switch (status) {
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
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: XlType.meta.copyWith(color: p.sectionLabel)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: XlType.meta.fontSize,
            fontWeight: FontWeight.w500,
            height: XlType.meta.height,
            color: p.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(XlDims.l),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(XlDims.rCard),
        border: p.isDark ? Border.all(color: p.hairline, width: 0.5) : null,
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: XlDims.sectionLabelSize,
        fontWeight: FontWeight.w500,
        height: 18 / XlDims.sectionLabelSize,
        color: p.sectionLabel,
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.results});

  final List<String> results;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Column(
      children: List.generate(results.length, (i) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: i == results.length - 1 ? 0 : XlDims.m,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: p.brandSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: XlType.caption.copyWith(color: p.brandDeep),
                ),
              ),
              const SizedBox(width: XlDims.s),
              Expanded(
                child: Text(
                  results[i],
                  style: XlType.body.copyWith(color: p.textPrimary),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.status});

  final XlTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final ended = status == XlTaskStatus.done ||
        status == XlTaskStatus.failed ||
        status == XlTaskStatus.cancelled;
    return Container(
      padding: const EdgeInsets.all(XlDims.m),
      decoration: BoxDecoration(
        color: p.brandSoft,
        borderRadius: BorderRadius.circular(XlDims.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: p.brandDeep),
          const SizedBox(width: XlDims.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ended ? '任务已结束，小乐已停止读取屏幕' : '任务执行中，小乐正在读取屏幕',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 17 / 12,
                    color: p.brandDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '屏幕读取仅在任务期间开启，任务结束立即停止。',
                  style: XlType.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
