/// 应用路由常量
class AppRoutes {
  AppRoutes._();

  // 主页面路由
  static const String main = '/';
  static const String conversation = '/conversation';
  static const String settings = '/settings';

  // 聊天相关路由
  static const String chat = '/chat';
  static const String agentConfig = '/agent-config';

  // v6.5.0：AI 主动来电
  static const String incomingCall = '/incoming-call';
  static const String proactiveScript = '/proactive-script';

  // 其他路由
  static const String splash = '/splash';
}
