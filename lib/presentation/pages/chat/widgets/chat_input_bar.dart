import 'package:flutter/material.dart';

import '../../../../app/themes/xl_tokens.dart';

/// 聊天输入栏（DESIGN §8.3）
/// 高 50 + 安全区 / #F7F7F7 / 顶部 1px 分隔；
/// 左语音 32 · 输入框 36 白底 4pt · 内嵌表情 · 右发送 56×32 或「更多 +」32
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.textController,
    required this.onSendText,
    required this.onStartVoice,
    required this.onMore,
    this.autoFocus = false,
  });

  final TextEditingController textController;
  final VoidCallback onSendText;
  final VoidCallback onStartVoice;
  final VoidCallback onMore;
  final bool autoFocus;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const List<String> _emojis = <String>[
    '🙂', '😄', '😂', '🥰', '😎', '🤔', '😴', '😭',
    '👍', '👏', '🙏', '💪', '🎉', '❤️', '🔥', '✨',
    '🌿', '☀️', '🌙', '📱', '✅', '⚡', '🎵', '🍀',
  ];

  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.textController.text.trim().isNotEmpty;
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.subtle,
        border: Border(top: BorderSide(color: p.hairline, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BarIcon(
                icon: Icons.mic_none_rounded,
                color: p.textPrimary,
                tooltip: '按住说话',
                onTap: widget.onStartVoice,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: XlDims.composerField,
                    maxHeight: 120,
                  ),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(XlDims.rField),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.textController,
                          focusNode: _focusNode,
                          autofocus: widget.autoFocus,
                          style: XlType.body.copyWith(color: p.textPrimary),
                          cursorColor: p.brandDeep,
                          cursorWidth: 2,
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (_hasText) widget.onSendText();
                          },
                          decoration: InputDecoration(
                            hintText: '输入消息',
                            hintStyle:
                                XlType.body.copyWith(color: p.placeholder),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            // 6+24+6 = 36，加 14 内边距 = 50，加安全区 = 84（DESIGN §8.3）
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              6,
                              4,
                              6,
                            ),
                            filled: false,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 4, bottom: 2),
                        child: _EmojiButton(
                          color: p.textSecondary,
                          onTap: _showEmojiSheet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: XlMotion.fast,
                switchInCurve: XlMotion.standard,
                switchOutCurve: XlMotion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: _hasText
                    ? _SendButton(
                        key: const ValueKey<String>('send'),
                        palette: p,
                        onTap: widget.onSendText,
                      )
                    : _BarIcon(
                        key: const ValueKey<String>('more'),
                        icon: Icons.add_circle_outline_rounded,
                        color: p.textPrimary,
                        tooltip: '更多',
                        onTap: widget.onMore,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEmojiSheet() async {
    final p = XlPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.canvas,
      builder: (ctx) => SafeArea(
        top: false,
        child: SizedBox(
          height: 260,
          child: GridView.count(
            crossAxisCount: 8,
            padding: const EdgeInsets.all(12),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: _emojis
                .map(
                  (e) => InkWell(
                    onTap: () {
                      _insertEmoji(e);
                      Navigator.of(ctx).pop();
                    },
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    _focusNode.requestFocus();
  }

  void _insertEmoji(String emoji) {
    final value = widget.textController.value;
    final selection = value.selection;
    final offset = selection.isValid ? selection.start : value.text.length;
    final newText = value.text.replaceRange(offset, offset, emoji);
    widget.textController.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + emoji.length),
      composing: TextRange.empty,
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.palette, required this.onTap});

  final XlPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: XlDims.sendW,
        height: XlDims.sendH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.brandDeep,
          borderRadius: BorderRadius.circular(XlDims.rField),
        ),
        child: Text(
          '发送',
          style: XlType.sendButton.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: XlDims.composerIcon,
          height: XlDims.composerIcon,
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 32,
        child: Icon(Icons.emoji_emotions_outlined, size: 20, color: color),
      ),
    );
  }
}
