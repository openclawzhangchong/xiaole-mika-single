import 'package:go_router/go_router.dart';
import '../../presentation/pages/main/main_page.dart';
import '../../presentation/pages/conversation/conversation_page.dart';
import '../../presentation/pages/chat/chat_page.dart';
import '../../presentation/pages/agent_config/agent_config_page.dart';
import '../../presentation/pages/settings/settings_page.dart';
import '../../presentation/pages/incoming_call_page.dart';
import '../../presentation/pages/proactive_script_page.dart';
import 'app_routes.dart';

/// 应用路由配置
class AppPages {
  AppPages._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.main,
    routes: [
      // 主页面（包含底部导航）
      GoRoute(
        path: AppRoutes.main,
        builder: (context, state) => const MainPage(),
      ),

      // 聊天详情页
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) {
          final agentId = state.uri.queryParameters['agentId'] ?? '';
          final agentName = state.uri.queryParameters['agentName'] ?? '';
          return ChatPage(
            agentId: agentId,
            agentName: agentName,
          );
        },
      ),

      // 智能体配置页
      GoRoute(
        path: AppRoutes.agentConfig,
        builder: (context, state) {
          final agentId = state.uri.queryParameters['agentId'];
          return AgentConfigPage(agentId: agentId);
        },
      ),

      // v6.5.0：AI 主动来电 —— 全屏来电页（接听/拒绝/30s 倒计时）
      GoRoute(
        path: AppRoutes.incomingCall,
        builder: (context, state) {
          final opening = state.uri.queryParameters['opening'] ?? '';
          final agentId = state.uri.queryParameters['agentId'] ?? '';
          final agentName = state.uri.queryParameters['agentName'] ?? '';
          return IncomingCallPage(
            opening: opening,
            agentId: agentId,
            agentName: agentName,
          );
        },
      ),

      // v6.5.0：AI 主动来电 —— 巡检口令管理页
      GoRoute(
        path: AppRoutes.proactiveScript,
        builder: (context, state) => const ProactiveScriptPage(),
      ),
    ],
  );
}
