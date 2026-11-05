import 'package:flutter/foundation.dart';

/// 会话列表未读红点（preview-01）。
///
/// 78 轮只做视觉落地与最小语义：任务在后台完成/失败时 +1，进入会话清零。
/// 纯内存态，进程重启归零 —— 不引入新的持久化面，也不碰 AgentModel。
class UnreadStore {
  UnreadStore._();

  static final Map<String, int> _counts = <String, int>{};

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static int of(String agentId) => _counts[agentId] ?? 0;

  static void bump(String agentId) {
    _counts[agentId] = of(agentId) + 1;
    revision.value++;
  }

  static void clear(String agentId) {
    if (_counts.remove(agentId) == null) return;
    revision.value++;
  }
}
