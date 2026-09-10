import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/themes/app_colors.dart';
import '../../../core/providers/agent_provider.dart';
import '../../../data/models/agent_model.dart';
import '../../widgets/agent_avatar.dart';

/// 对话页面 - 智能体列表（微信会话列表风格）
class ConversationPage extends ConsumerWidget {
  const ConversationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentListAsync = ref.watch(agentListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('小乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              context.push(AppRoutes.agentConfig);
            },
            tooltip: '添加智能体',
          ),
        ],
      ),
      body: agentListAsync.when(
        data: (agents) {
          if (agents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 72,
                    color: isDark
                        ? AppColors.navBarUnselectedDark
                        : AppColors.navBarUnselected,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无会话',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右上角 "+" 添加智能体',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      context.push(AppRoutes.agentConfig);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加智能体'),
                  ),
                ],
              ),
            );
          }

          // 微信会话列表：白底行 + 左侧头像 + 右侧时间，行间细分割线
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: agents.length,
            separatorBuilder: (context, index) => Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 76,
              color: isDark ? AppColors.dividerDark : AppColors.divider,
            ),
            itemBuilder: (context, index) {
              final agent = agents[index];
              final updatedAt = agent.updatedAt;
              final timeStr = updatedAt != null
                  ? DateFormat('HH:mm').format(updatedAt)
                  : '';
              return Material(
                color: isDark ? AppColors.surfaceDark : AppColors.surface,
                child: InkWell(
                  onTap: () {
                    context.push(
                      '${AppRoutes.chat}?agentId=${agent.id}&agentName=${agent.name}',
                    );
                  },
                  // 微信交互：长按会话行弹出 编辑/删除
                  onLongPress: () =>
                      _showRowActions(context, ref, agent),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 头像（原型 v7：10 套渐变 + 符号，圆角方形 48/6px）
                        AgentAvatar(
                          styleIndex:
                              agent.id.hashCode.abs() % kAgentAvatarStyles.length,
                          size: 48,
                          radius: 6,
                        ),
                        const SizedBox(width: 12),
                        // 标题 + 最后消息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agent.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                agent.description.isNotEmpty
                                    ? agent.description
                                    : '点击开始对话',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 右侧：时间（编辑/删除已改为长按弹出，微信交互）
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 60, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                '加载失败: $error',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(agentListProvider.notifier).loadAgents();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按会话行：微信式操作菜单（编辑/删除）
  void _showRowActions(
    BuildContext context,
    WidgetRef ref,
    AgentModel agent,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑智能体'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('${AppRoutes.agentConfig}?agentId=${agent.id}');
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除智能体',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDeleteDialog(context, ref, agent.id, agent.name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String agentId,
    String agentName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除智能体'),
        content: Text('确定要删除 "$agentName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(agentListProvider.notifier).deleteAgent(agentId);
            },
            child: const Text(
              '删除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
