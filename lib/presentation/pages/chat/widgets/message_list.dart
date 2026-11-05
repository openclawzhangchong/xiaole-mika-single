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
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (isTyping && index == 0) {
          return const TypingIndicator();
        }

        final msgIndex = messages.length - 1 - (index - typingOffset);
        final msg = messages[msgIndex];

        final bool showDivider = msgIndex == 0 ||
            _minuteKey(messages[msgIndex - 1]) != _minuteKey(msg);

        final divider = showDivider
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: XlType.meta.copyWith(color: p.textQuaternary),
                ),
              )
            : null;

        if (msg.type == MessageType.system) {
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
            ),
          ],
        );
      },
    );
  }
}
