import 'package:flutter/material.dart';
import '../../../../data/models/message_model.dart';
import '../../../../app/themes/app_colors.dart';
import '../../../widgets/typing_indicator.dart';
import 'message_bubble.dart';

/// 消息列表组件（微信风格 v7）
///
/// 排版规则（对齐原型 v7，修复错版）：
/// - 时间不再挂在气泡下，改为**居中时间分隔条**，仅在时间（分钟）变化时出现；
/// - 系统消息为**居中灰色小字**，无头像无气泡。
class MessageList extends StatelessWidget {
  final List<MessageModel> messages;
  final ScrollController scrollController;
  final bool isTyping;
  final int? avatarStyleIndex;

  const MessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.isTyping = false,
    this.avatarStyleIndex,
  });

  /// 分钟级时间键（同一分钟内不重复显示时间分隔条）
  static int _minuteKey(MessageModel m) =>
      m.timestamp.hour * 60 + m.timestamp.minute;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isTyping) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: isDark
                  ? AppColors.navBarUnselectedDark
                  : AppColors.navBarUnselected,
            ),
            const SizedBox(height: 16),
            Text(
              '开始对话',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final itemCount = messages.length + (isTyping ? 1 : 0);

    // 输入指示器出现时滚动到底部
    if (isTyping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (isTyping && index == messages.length) {
          return const TypingIndicator();
        }

        final msg = messages[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final systemColor = isDark
            ? AppColors.systemTextDark
            : AppColors.systemText;

        // 时间分隔条：首条或与上一条分钟不同时插入（微信排版）
        final bool showDivider =
            index == 0 || _minuteKey(messages[index - 1]) != _minuteKey(msg);

        final divider = showDivider
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: systemColor),
                ),
              )
            : null;

        // 系统消息：居中灰色小字（无头像无气泡）
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
                  style: TextStyle(fontSize: 12, color: systemColor),
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
              avatarStyleIndex: avatarStyleIndex,
            ),
          ],
        );
      },
    );
  }
}
