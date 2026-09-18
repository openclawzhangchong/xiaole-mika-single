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
    // 侧边图标统一约束：40x36 视觉盒，让图标中心与输入框单行中心对齐
    // （解决"高低不齐"：此前 IconButton 默认 48x48，底部对齐时图标中心偏高）
    const sideConstraints = BoxConstraints(minWidth: 40, minHeight: 36);
    const sidePadding = EdgeInsets.zero;

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
          // 多行输入时底部对齐、输入框向上撑开（微信行为）；单行时各组件
          // 因高度统一（36）视觉上即居中
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // v3.1.0：📷 视觉识物（拍照问 AI；未获取 vision 接口时回调内自行提示）
            if (widget.onTakePhoto != null) ...[
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: widget.onTakePhoto,
                tooltip: '拍照识物',
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                padding: sidePadding,
                constraints: sideConstraints,
              ),
              const SizedBox(width: 4),
            ],

            // 语音按钮（切换到按住说话）
            IconButton(
              icon: const Icon(Icons.mic_none_outlined),
              onPressed: widget.onStartVoice,
              tooltip: '按住说话',
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
              padding: sidePadding,
              constraints: sideConstraints,
            ),

            const SizedBox(width: 10),

            // 输入框（微信：白底圆角矩形 5px）
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 36, maxHeight: 120),
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
                    hintText: '输入消息',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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

            const SizedBox(width: 10),

            // 右侧互斥切换（微信原版行为，v6.11.2）：
            // 有文字 → 只显示绿色发送胶囊（电话按钮隐藏，解决拥挤）；
            // 清空   → 恢复电话按钮
            if (_hasText)
              GestureDetector(
                onTap: widget.onSendText,
                child: Container(
                  // 高度 36 与输入框单行高度一致，底部对齐即居中
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
              )
            else
              IconButton(
                icon: const Icon(Icons.call_outlined),
                onPressed: widget.onStartCall,
                tooltip: '语音通话',
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                padding: sidePadding,
                constraints: sideConstraints,
              ),
          ],
        ),
      ),
    );
  }
}
