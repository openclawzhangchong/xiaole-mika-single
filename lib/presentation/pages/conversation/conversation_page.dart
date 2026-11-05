import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/themes/xl_tokens.dart';
import '../../../core/providers/agent_provider.dart';
import '../../../data/models/agent_model.dart';
import '../../widgets/agent_avatar.dart';
import '../../services/unread_store.dart';
import '../../widgets/wx_action_sheet.dart';
import '../../widgets/wx_dialog.dart';
import '../../widgets/wx_empty.dart';

/// 会话列表（DESIGN §7 screen 01）
/// 导航「消息」/ 搜索 36 / 行高 64 / 头像 48-6 / 分割线缩进 76 / 脚注 12-666
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentListAsync = ref.watch(agentListProvider);
    final p = XlPalette.of(context);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 24),
            onPressed: () => context.push(AppRoutes.agentConfig),
            tooltip: '添加智能体',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: agentListAsync.when(
        data: (agents) {
          final visible = _query.isEmpty
              ? agents
              : agents
                  .where((a) =>
                      a.name.toLowerCase().contains(_query) ||
                      a.description.toLowerCase().contains(_query))
                  .toList();

          return Column(
            children: [
              _SearchField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              Expanded(
                child: visible.isEmpty
                    ? WxEmpty(
                        icon: Icons.chat_bubble_outline,
                        title: _query.isEmpty ? '暂无会话' : '没有匹配的会话',
                        description: _query.isEmpty
                            ? '点击右上角 "+" 添加智能体'
                            : '换个关键词试试',
                        actionLabel: _query.isEmpty ? '添加智能体' : null,
                        onAction: _query.isEmpty
                            ? () => context.push(AppRoutes.agentConfig)
                            : null,
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: visible.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: XlDims.listDividerInset,
                          color: p.hairline,
                        ),
                        itemBuilder: (context, index) {
                          final agent = visible[index];
                          return _ConversationRow(
                            agent: agent,
                            onTap: () => context.push(
                              '${AppRoutes.chat}?agentId=${agent.id}&agentName=${agent.name}',
                            ),
                            onLongPress: () =>
                                _showRowActions(context, ref, agent),
                          );
                        },
                      ),
              ),
              Container(
                color: p.canvas,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  '长按会话可编辑或删除',
                  textAlign: TextAlign.center,
                  style: XlType.meta.copyWith(color: p.sectionLabel),
                ),
              ),
            ],
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(p.brandDeep),
          ),
        ),
        error: (error, stack) => WxEmpty(
          icon: Icons.error_outline,
          title: '加载失败',
          description: '$error',
          actionLabel: '重试',
          onAction: () => ref.read(agentListProvider.notifier).loadAgents(),
        ),
      ),
    );
  }

  /// 长按会话行：微信式操作菜单（编辑/删除）
  Future<void> _showRowActions(
    BuildContext context,
    WidgetRef ref,
    AgentModel agent,
  ) async {
    final index = await showWxActionSheet(
      context,
      items: const [
        WxActionSheetItem(label: '编辑智能体'),
        WxActionSheetItem(label: '删除智能体', danger: true),
      ],
    );
    if (!context.mounted) return;
    if (index == 0) {
      context.push('${AppRoutes.agentConfig}?agentId=${agent.id}');
    } else if (index == 1) {
      await _showDeleteDialog(context, ref, agent.id, agent.name);
    }
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String agentId,
    String agentName,
  ) async {
    final ok = await showWxDialog(
      context,
      title: '删除智能体',
      content: '确定要删除 "$agentName" 吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok == true) {
      await ref.read(agentListProvider.notifier).deleteAgent(agentId);
    }
  }
}

/// 会话行（tokens.rowHeights.conversation = 64）
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.agent,
    required this.onTap,
    required this.onLongPress,
  });

  final AgentModel agent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final updatedAt = agent.updatedAt;
    final timeStr = updatedAt != null ? DateFormat('HH:mm').format(updatedAt) : '';

    return Material(
      color: p.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        highlightColor: p.pressed,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: XlDims.conversationRow,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: XlDims.listPadding,
            ),
            child: Row(
              children: [
                AgentAvatar(
                  agentId: agent.id,
                  name: agent.name,
                  size: XlDims.listAvatar,
                  radius: XlDims.avatarList,
                ),
                const SizedBox(width: XlDims.l),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: XlType.listTitle.copyWith(
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        agent.description.isNotEmpty
                            ? agent.description
                            : '点击开始对话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: XlType.summary.copyWith(
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: XlDims.s),
                ValueListenableBuilder<int>(
                  valueListenable: UnreadStore.revision,
                  builder: (context, _, __) {
                    final unread = UnreadStore.of(agent.id);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: XlType.meta.copyWith(color: p.textQuaternary),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(height: 4),
                          _UnreadBadge(count: unread, color: XlColor.badgeRed),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 未读红点（preview-01 实测：18pt 圆、#D93636 底、白字 11/600）
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: XlDims.badgeSize,
      height: XlDims.badgeSize,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(XlDims.badgeSize / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 搜索框：36 白底 4pt，1px #E5E5E5 描边，占位 14 #B2B2B2
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(XlDims.rField),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final empty = value.text.isEmpty;
            return Row(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (empty)
                        IgnorePointer(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 16,
                                color: p.textQuaternary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '搜索',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 19 / 14,
                                  color: p.placeholder,
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: controller,
                        onChanged: onChanged,
                        style: TextStyle(
                          fontSize: 14,
                          height: 19 / 14,
                          color: p.textPrimary,
                        ),
                        cursorColor: p.brandDeep,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: '',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 9),
                          filled: false,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!empty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.cancel,
                        size: 16,
                        color: p.textQuaternary,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
