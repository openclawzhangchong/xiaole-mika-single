import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../data/models/message_model.dart';
import '../../../../app/themes/app_colors.dart';
import '../../../widgets/agent_avatar.dart';

/// 聊天消息气泡组件（微信风格 v7）
///
/// 对齐原型 v7：圆角方形头像、气泡宽度按屏宽 68% 自适应、
/// 时间戳移至列表层居中分隔条（本组件不再渲染时间）。
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final int? avatarStyleIndex;

  const MessageBubble({
    super.key,
    required this.message,
    this.avatarStyleIndex,
  });

  bool get isUser => message.sender == MessageSender.user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: _buildMessageContent(context),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            _buildAvatar(),
          ],
        ],
      ),
    );
  }

  /// 头像（微信风格：圆角方形 40）
  Widget _buildAvatar() {
    if (isUser) {
      return const UserAvatar(name: '我', size: 40);
    }
    return AgentAvatar(
      styleIndex: avatarStyleIndex ?? 0,
      size: 40,
    );
  }

  /// 消息内容（微信气泡：绿色/白色，靠头像侧小圆角 + 小尖角）
  Widget _buildMessageContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = isUser
        ? (isDark ? AppColors.userMessageBgDark : AppColors.userMessageBg)
        : (isDark ? AppColors.aiMessageBgDark : AppColors.aiMessageBg);

    // 微信气泡圆角：靠头像一侧的上方圆角更小（对齐原型 v7 的 12px 圆角体系）
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
            topRight: Radius.circular(2),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
            topLeft: Radius.circular(2),
          );

    // 用户气泡文字：浅色模式黑字，深色模式白字（保证对比度）
    final bubbleTextColor = isUser && isDark
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.68,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: borderRadius,
      ),
      child: _buildContentByType(bubbleTextColor, context),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        bubble,
        // 靠头像侧的小尖角（对齐原型 v7 的 ::before 三角）
        Positioned(
          top: 10,
          left: isUser ? null : -5,
          right: isUser ? -5 : null,
          child: CustomPaint(
            size: const Size(6, 10),
            painter: _BubbleTailPainter(
              color: bubbleColor,
              isUser: isUser,
            ),
          ),
        ),
      ],
    );
  }

  /// 根据消息类型构建内容
  Widget _buildContentByType(Color bubbleTextColor, BuildContext context) {
    // v4.2.0：结构化卡片（申请书 7 号——设备状态卡片，AI 查状态时本地渲染）
    final meta = message.metadata;
    if (meta != null && meta['card'] == 'device_status') {
      return _buildDeviceStatusCard(meta['data'], context);
    }
    switch (message.type) {
      case MessageType.text:
        return SelectableText(
          message.content,
          style: TextStyle(fontSize: 16, color: bubbleTextColor, height: 1.5),
        );

      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline,
                size: 24, color: bubbleTextColor),
            const SizedBox(width: 8),
            Flexible(
              child: SelectableText(
                message.content,
                style: TextStyle(
                    fontSize: 16, color: bubbleTextColor, height: 1.5),
              ),
            ),
          ],
        );

      case MessageType.system:
        // 系统消息由 MessageList 层居中渲染，此处兜底（不应到达）
        return Text(
          message.content,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.systemText,
          ),
        );
    }
  }
  /// v4.2.0 设备状态卡片（申请书 7 号）——音量/电量/主题/网络结构化展示
  Widget _buildDeviceStatusCard(dynamic raw, BuildContext context) {
    final data = raw is Map ? raw : <String, dynamic>{};
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subColor = AppColors.textSecondary;

    final battery = data['battery'] is Map ? data['battery'] as Map : const {};
    final level = (battery['level'] as num?)?.toInt() ?? 100;
    final charging = battery['charging'] == true;
    final volume = (data['volume'] as num?)?.toInt() ?? 0;
    final theme = (data['theme'] as String?) == 'dark' ? '深色' : '浅色';
    final online = data['network'] == 'online';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📊 设备状态',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 8),
          _statusRow(Icons.volume_up, '音量', '$volume%', textColor, subColor),
          _statusRow(
            charging ? Icons.battery_charging_full : Icons.battery_std,
            '电量',
            charging ? '$level%（充电中）' : '$level%',
            charging
                ? AppColors.success
                : (level < 20 ? AppColors.error : textColor),
            subColor,
          ),
          _statusRow(Icons.palette_outlined, '主题', theme, textColor, subColor),
          _statusRow(
            online ? Icons.wifi : Icons.wifi_off,
            '网络',
            online ? '在线' : '离线',
            online ? AppColors.success : AppColors.error,
            subColor,
          ),
        ],
      ),
    );
  }

  Widget _statusRow(IconData icon, String label, String value,
      Color valueColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: valueColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(width: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }
}

/// 气泡小尖角（与气泡同色，靠头像侧）
class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isUser;

  const _BubbleTailPainter({required this.color, required this.isUser});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isUser) {
      // 用户（右）：平边在左（贴气泡右缘），尖端向右
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height / 2);
    } else {
      // AI（左）：平边在右（贴气泡左缘），尖端向左
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height / 2);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter old) =>
      old.color != color || old.isUser != isUser;
}
