import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/themes/xl_tokens.dart';
import '../../../../data/models/message_model.dart';
import '../../../pages/task/xl_task_detail_page.dart';
import '../../../widgets/agent_avatar.dart';
import '../../../widgets/xl/xl_step_timeline.dart';
import '../../../widgets/xl/xl_task_card.dart';

/// 聊天消息气泡（DESIGN §6 / §8.1）
/// 16pt 页边 / 头像 36-5 / 气泡 8pt / 尾 6×10 顶部 12 /
/// 正文 16-24 / 最大宽 min(245, 屏宽 66%) / 气泡间距 14。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.agentId,
    this.agentName,
  });

  final MessageModel message;
  final String? agentId;
  final String? agentName;

  bool get isUser => message.sender == MessageSender.user;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final meta = message.metadata;
    final isTaskCard = meta != null && meta['card'] == 'task';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XlDims.pagePadding,
        vertical: XlDims.bubbleGap / 2,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 10),
          ],
          if (isTaskCard)
            XlTaskCard(
              model: _taskCardModel(meta['data']),
              width: math.min(
                XlDims.taskCardWidth,
                MediaQuery.of(context).size.width -
                    XlDims.pagePadding * 2 -
                    XlDims.chatAvatar -
                    10,
              ),
              onTap: () => _openTaskDetail(context, meta['data']),
              onAbort: () => _taskActionHint(context, '中止'),
              onCancel: () => _taskActionHint(context, '取消'),
              onRetry: () => _taskActionHint(context, '重试'),
            )
          else
            Flexible(child: _buildMessageContent(context, p)),
          if (isUser) ...[
            const SizedBox(width: 10),
            _buildAvatar(),
          ],
        ],
      ),
    );
  }

  /// 头像 36 / 圆角 5
  Widget _buildAvatar() {
    if (isUser) {
      return const UserAvatar(
        name: '我',
        size: XlDims.chatAvatar,
        radius: XlDims.avatarChat,
      );
    }
    return AgentAvatar(
      agentId: agentId,
      name: agentName,
      size: XlDims.chatAvatar,
      radius: XlDims.avatarChat,
    );
  }

  Widget _buildMessageContent(BuildContext context, XlPalette p) {
    final bg = isUser ? p.bubbleSelfBg : p.bubbleOtherBg;
    final fg = isUser ? p.bubbleSelfText : p.bubbleOtherText;
    final radius = BorderRadius.circular(XlDims.rBubble);

    final maxWidth = math.min(
      XlDims.bubbleMaxWidth,
      MediaQuery.of(context).size.width * 0.66,
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: XlDims.bubblePadX,
        vertical: XlDims.bubblePadY,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: _buildContentByType(fg, context),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        bubble,
        Positioned(
          top: XlDims.bubbleTailTop,
          left: isUser ? null : -XlDims.bubbleTailW + 1,
          right: isUser ? -XlDims.bubbleTailW + 1 : null,
          child: CustomPaint(
            size: const Size(XlDims.bubbleTailW, XlDims.bubbleTailH),
            painter: _BubbleTailPainter(color: bg, isUser: isUser),
          ),
        ),
      ],
    );
  }

  Widget _buildContentByType(Color fg, BuildContext context) {
    final meta = message.metadata;
    if (meta != null && meta['card'] == 'device_status') {
      return _buildDeviceStatusCard(meta['data'], context);
    }

    switch (message.type) {
      case MessageType.text:
        return SelectableText(
          message.content,
          style: XlType.body.copyWith(color: fg),
        );

      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(XlDims.rS),
          child: CachedNetworkImage(
            imageUrl: message.content,
            width: 200,
            placeholder: (context, url) => const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        );

      case MessageType.audio:
        final secs = meta?['duration'];
        return SizedBox(
          height: XlDims.voiceBubbleHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StaticWave(color: fg.withOpacity(0.7)),
              const SizedBox(width: XlDims.s),
              Text(
                secs == null ? '语音' : '$secs″',
                style: XlType.meta.copyWith(color: fg),
              ),
            ],
          ),
        );

      case MessageType.system:
        return Text(
          message.content,
          style: XlType.meta.copyWith(color: XlPalette.of(context).systemText),
        );
    }
  }

  /// 设备状态卡（原 card=device_status，配色改为令牌）
  Widget _buildDeviceStatusCard(dynamic raw, BuildContext context) {
    final data = raw is Map ? raw : <String, dynamic>{};
    final p = XlPalette.of(context);
    final battery = data['battery'] is Map ? data['battery'] as Map : const {};
    final level = (battery['level'] as num?)?.toInt() ?? 100;
    final charging = battery['charging'] == true;
    final volume = (data['volume'] as num?)?.toInt() ?? 0;
    final theme = (data['theme'] as String?) == 'dark' ? '深色' : '浅色';
    final online = data['network'] == 'online';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '设备状态',
            style: XlType.cardTitle.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: XlDims.s),
          _statusRow(Icons.volume_up_rounded, '音量', '$volume%', p),
          _statusRow(
            charging ? Icons.battery_charging_full : Icons.battery_std,
            '电量',
            charging ? '$level%（充电中）' : '$level%',
            p,
            valueColor: charging
                ? p.brand
                : (level < 20 ? p.danger : p.textPrimary),
          ),
          _statusRow(Icons.palette_outlined, '主题', theme, p),
          _statusRow(
            online ? Icons.wifi : Icons.wifi_off,
            '网络',
            online ? '在线' : '离线',
            p,
            valueColor: online ? p.brand : p.danger,
          ),
        ],
      ),
    );
  }

  Widget _statusRow(
    IconData icon,
    String label,
    String value,
    XlPalette p, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: valueColor ?? p.textPrimary),
          const SizedBox(width: XlDims.s),
          Text(label, style: XlType.meta.copyWith(color: p.textSecondary)),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: XlType.meta.fontSize,
              fontWeight: FontWeight.w600,
              height: XlType.meta.height,
              color: valueColor ?? p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  XlTaskCardModel _taskCardModel(dynamic raw) {
    final data = raw is Map ? raw : <String, dynamic>{};
    final status = _parseStatus(data['status']);
    final elapsedMs = (data['elapsedMs'] as num?)?.toInt() ?? 0;
    final progress = (data['progress'] as num?)?.toDouble();
    return XlTaskCardModel(
      title: (data['title'] ?? '任务').toString(),
      status: status,
      stepIndex: (data['stepIndex'] as num?)?.toInt() ?? 0,
      stepTotal: (data['stepTotal'] as num?)?.toInt() ?? 0,
      elapsed: Duration(milliseconds: elapsedMs),
      progress: progress,
      failReason: data['failReason']?.toString(),
      canAbort: status == XlTaskStatus.running,
      canCancel: status == XlTaskStatus.queued,
      canRetry: status == XlTaskStatus.failed,
      icon: _taskIcon(data['icon']),
      timeLabel: message.timestamp == null
          ? null
          : _formatTime(message.timestamp!),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  XlTaskStatus _parseStatus(dynamic raw) {
    final name = raw?.toString();
    for (final s in XlTaskStatus.values) {
      if (s.name == name) return s;
    }
    return XlTaskStatus.running;
  }

  IconData _taskIcon(dynamic raw) {
    switch (raw?.toString()) {
      case 'screen':
        return Icons.smartphone_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'clean':
        return Icons.cleaning_services_rounded;
      case 'list':
        return Icons.checklist_rounded;
      default:
        return Icons.checklist_rounded;
    }
  }

  void _openTaskDetail(BuildContext context, dynamic raw) {
    final data = raw is Map ? raw : <String, dynamic>{};
    final status = _parseStatus(data['status']);
    final elapsedMs = (data['elapsedMs'] as num?)?.toInt() ?? 0;
    final steps = _parseSteps(data['steps'], status, data);
    final results = data['results'] is List
        ? (data['results'] as List).map((e) => e.toString()).toList()
        : <String>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => XlTaskDetailPage(
          data: XlTaskDetailData(
            title: (data['title'] ?? '任务').toString(),
            status: status,
            elapsed: Duration(milliseconds: elapsedMs),
            stepIndex: (data['stepIndex'] as num?)?.toInt() ?? 0,
            stepTotal: (data['stepTotal'] as num?)?.toInt() ?? 0,
            startedAt: (data['startedAt'] ?? '今天').toString(),
            device: (data['device'] ?? '当前手机').toString(),
            trigger: (data['trigger'] ?? '对话内指令').toString(),
            steps: steps,
            results: results,
            icon: _taskIcon(data['icon']),
          ),
        ),
      ),
    );
  }

  List<XlTaskStep> _parseSteps(
    dynamic raw,
    XlTaskStatus status,
    Map<dynamic, dynamic> data,
  ) {
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) {
        final m = e is Map ? e : <dynamic, dynamic>{};
        final stateName = m['state']?.toString();
        final state = switch (stateName) {
          'done' => XlStepState.done,
          'running' => XlStepState.running,
          'failed' => XlStepState.failed,
          _ => XlStepState.pending,
        };
        return XlTaskStep(
          title: (m['title'] ?? '').toString(),
          meta: m['meta']?.toString(),
          state: state,
        );
      }).toList();
    }
    final state = switch (status) {
      XlTaskStatus.done => XlStepState.done,
      XlTaskStatus.running => XlStepState.running,
      XlTaskStatus.failed => XlStepState.failed,
      _ => XlStepState.pending,
    };
    return <XlTaskStep>[
      XlTaskStep(
        title: (data['title'] ?? '执行任务').toString(),
        meta: status == XlTaskStatus.queued ? '等待执行' : null,
        state: state,
      ),
    ];
  }

  void _taskActionHint(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action任务请在任务中心操作')),
    );
  }
}

/// 气泡小尖角（6×10，与气泡同色，顶部 12 对齐首行）
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.isUser});

  final Color color;
  final bool isUser;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isUser) {
      path
        ..moveTo(0, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height / 2);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height / 2);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) =>
      old.color != color || old.isUser != isUser;
}

/// 历史语音消息的静态 11 根波形（§15 I5）
class _StaticWave extends StatelessWidget {
  const _StaticWave({required this.color});

  final Color color;

  static const List<double> _heights = <double>[
    6, 10, 16, 12, 18, 18, 14, 18, 10, 12, 6,
  ];

  @override
  Widget build(BuildContext context) {
    final bars = XlMotion.waveBarCount;
    return SizedBox(
      width: bars * XlDims.waveBarW + (bars - 1) * XlDims.waveBarGap,
      height: XlDims.waveBarMaxH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_heights.length, (i) {
          return Padding(
            padding: EdgeInsets.only(
              right: i == _heights.length - 1 ? 0 : XlDims.waveBarGap,
            ),
            child: Container(
              width: XlDims.waveBarW,
              height: _heights[i],
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(XlDims.waveBarW / 2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
