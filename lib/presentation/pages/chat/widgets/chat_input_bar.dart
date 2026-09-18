import 'package:flutter/material.dart';
import '../../../../app/themes/app_colors.dart';
import '../../../../app/themes/app_text_styles.dart';

/// 聊天输入栏组件（微信风格，对齐原型 v6）
class ChatInputBar extends StatefulWidget {
  final TextEditingController textController;
  final VoidCallback onSendText;
  final VoidCallback onStartVoice;
  final VoidCallback onStartCall;
  final VoidCallback? onTakePhoto; // v3.1.0：视觉识物（拍照问 AI）

  const ChatInputBar({
    super.key,
    required this.textController,
    required this.onSendText,
    required this.onStartVoice,
    required this.onStartCall,
    this.onTakePhoto,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // 同步初始文字状态（防御：controller 带文字进入时发送胶囊立即可见）
    _hasText = widget.textController.text.trim().isNotEmpty;
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // v3.1.0：📷 视觉识物（拍照问 AI；未获取 vision 接口时回调内自行提示）
            if (widget.onTakePhoto != null)
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: widget.onTakePhoto,
                tooltip: '拍照识物',
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),

            // 语音按钮（切换到按住说话）
            IconButton(
              icon: const Icon(Icons.mic_none_outlined),
              onPressed: widget.onStartVoice,
              tooltip: '按住说话',
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),

            // 输入框（微信：白底圆角矩形）
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.inputBackgroundDark
                      : AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: TextField(
                  controller: widget.textController,
                  style: AppTextStyles.body.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '发消息给小乐',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (_hasText) {
                      widget.onSendText();
                    }
                  },
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 发送按钮（微信原版：绿色文字胶囊，输入框有文字时才出现）
            if (_hasText) ...[
              GestureDetector(
                onTap: widget.onSendText,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '发送',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],

            // 📞 电话按钮（对齐原型：输入栏右侧）
            IconButton(
              icon: const Icon(Icons.call_outlined),
              onPressed: widget.onStartCall,
              tooltip: '语音通话',
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
