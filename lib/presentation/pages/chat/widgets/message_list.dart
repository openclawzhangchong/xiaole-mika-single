import 'package:flutter/material.dart';

import '../../../../app/themes/xl_tokens.dart';
import '../../../../data/models/message_model.dart';
import '../../../widgets/typing_indicator.dart';
import 'message_bubble.dart';

/// 消息列表（DESIGN §6 / §8.1）
/// - 时间分隔条 12pt #ABABAB，仅装饰；系统消息 12pt #5F5F5F（§15 I2）
/// - 倒置列表：最新消息贴底，进入即停最新处
class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.isTyping = false,
    this.agentId,
    this.agentName,
  });

  final List<MessageModel> messages;
  final ScrollController scrollController;
  final bool isTyping;
  final String? agentId;
  final String? agentName;

  static int _minuteKey(MessageModel m) =>
      m.timestamp.hour * 60 + m.timestamp.minute;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    if (messages.isEmpty && !isTyping) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: p.textQuaternary,
            ),
            const SizedBox(height: XlDims.l),
            Text(
              '开始对话',
              style: XlType.summary.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      );
    }

    final itemCount = messages.length + (isTyping ? 1 : 0);
    final typingOffset = isTyping ? 1 : 0;

    // 同屏只让"当前正在跑"的那张任务卡脉冲（DESIGN §8.2）
    String? latestRunningTaskId;
    for (final m in messages) {
      final meta = m.metadata;
      final data = meta?['data'];
      if (meta != null &&
          meta['card'] == 'task' &&
          data is Map &&
          data['status']?.toString() == 'running') {
        latestRunningTaskId = m.id;
      }
    }

    if (isTyping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });
    }

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      // 79 轮 P1：默认 true 会给每个气泡套 RepaintBoundary（独立合成层），
      // 录音浮层的 BackdropFilter 就采不到下方内容 → 实拍成"近实心遮挡"。
      addRepaintBoundaries: false,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (isTyping && index == 0) {
          return const TypingIndicator();
        }

        final msgIndex = messages.length - 1 - (index - typingOffset);
        final msg = messages[msgIndex];

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bool showDivider = msgIndex == 0 ||
            _minuteKey(messages[msgIndex - 1]) != _minuteKey(msg);

        final divider = showDivider
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  // preview-09 实测深色时间分隔 #8A8A8A（浅色仍 #6E6E6E）
                  style: XlType.meta.copyWith(
                    color: isDark ? p.textTertiary : p.textQuaternary,
                  ),
                ),
              )
            : null;

        // 82：任务卡是卡片组件，不是系统纯文本。metadata card=task 必须先于
        // MessageType.system 分支判断，否则 chat_page 注入的任务卡会被渲染成
        // 居中四行纯文本（81 mock 验收失败的根因）。
        final isTaskCard = msg.metadata?['card'] == 'task';
        if (msg.type == MessageType.system && !isTaskCard) {
          return Column(
            children: [
              if (divider != null) divider,
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text(
                  msg.content,
                  textAlign: TextAlign.center,
                  style: XlType.meta.copyWith(color: p.systemText),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            if (divider != null) divider,
            MessageBubble(
              message: msg,
              agentId: agentId,
              agentName: agentName,
              animateTaskPulse: msg.id == latestRunningTaskId,
            ),
          ],
        );
      },
    );
  }
}
