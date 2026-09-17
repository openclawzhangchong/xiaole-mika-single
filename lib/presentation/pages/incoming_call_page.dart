import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../app/themes/app_colors.dart';
import '../../core/proactive/proactive_ringtone.dart';
import '../widgets/agent_avatar.dart';

/// v6.5.0：AI 主动来电 —— 全屏来电页
/// ------------------------------------------------------------------
/// 由 `ProactivePollService.onTriggered` 触发（小智调用了 self.proactive.trigger_call）。
/// 行为：
/// - 进入即播放 450Hz 断续回铃音 + 震动（周期震动，非持续）；
/// - 30 秒环形倒计时，归零自动挂断（视为拒绝）；
/// - 接听 → `Navigator.pop(context, opening)`（把开场白交回调用方去回放）；
/// - 拒绝 / 超时 → `Navigator.pop(context, null)`。
/// 资源释放（回铃音/震动/计时器）集中在 `dispose()`，幂等且不抛异常。
class IncomingCallPage extends StatefulWidget {
  final String opening;
  final String agentId;
  final String agentName;

  const IncomingCallPage({
    super.key,
    required this.opening,
    this.agentId = '',
    this.agentName = '小乐',
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  static const int _timeoutSeconds = 30;

  int _remaining = _timeoutSeconds;
  Timer? _timer;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    // 回铃音 + 首次震动（失败一律吞掉，绝不能因音频/震动异常卡住来电页）
    unawaited(ProactiveRingtone.start().catchError((_) {}));
    _vibrateOnce();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      // 每 3 秒震一次，模拟来电节奏
      if (_remaining > 0 && _remaining % 3 == 0) _vibrateOnce();
      if (_remaining <= 0) _hangUp();
    });
  }

  void _vibrateOnce() {
    try {
      Vibration.vibrate(pattern: const [0, 400, 200, 400]).catchError((_) {});
    } catch (_) {}
  }

  /// 释放全部资源（幂等）
  void _release() {
    _timer?.cancel();
    _timer = null;
    unawaited(ProactiveRingtone.stop().catchError((_) {}));
    try {
      Vibration.cancel().catchError((_) {});
    } catch (_) {}
  }

  void _hangUp() {
    if (!mounted) return;
    _release();
    Navigator.of(context).pop(null);
  }

  void _answer() {
    if (_answered) return;
    _answered = true;
    _release();
    Navigator.of(context).pop(widget.opening);
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 来电页不允许用返回键悄悄跳过；走"拒绝"语义
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.callBgTop,
                AppColors.callBgMid,
                AppColors.callBgBottom,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                AgentAvatar(
                  agentId: widget.agentId.isEmpty ? null : widget.agentId,
                  name: widget.agentName,
                  size: 120,
                  showOnlineDot: false,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.agentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '小乐想和你说说',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _remaining / _timeoutSeconds,
                        strokeWidth: 3,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                      Text(
                        '$_remaining',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFE24B4A),
                        label: '拒绝',
                        onTap: _hangUp,
                      ),
                      _RoundButton(
                        icon: Icons.call,
                        color: AppColors.primary,
                        label: '接听',
                        onTap: _answer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
