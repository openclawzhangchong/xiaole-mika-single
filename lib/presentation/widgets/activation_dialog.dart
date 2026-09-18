import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_ota_service.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';
import 'wx_icon_button.dart';

/// 设备激活轮询弹窗（对齐原型 v6 的 activationModal）
///
/// 仅调用现有 XiaozhiOtaService.checkFlutterAppUpdates（只读，不改 lib/core）：
/// 1. 提交后立即请求 OTA，若已返回 websocket 信息则直接成功；
/// 2. 否则展示服务器下发的验证码，并在后台每 3 秒轮询一次；
/// 3. 5 分钟倒计时内一旦返回 websocket 信息即判定激活成功，展示 WS 配置。
/// 任何网络/解析异常均被捕获并以错误态呈现，不会崩溃主流程。
class ActivationDialog extends StatefulWidget {
  final String otaUrl;
  final String appVersion;

  const ActivationDialog({
    super.key,
    required this.otaUrl,
    required this.appVersion,
  });

  @override
  State<ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends State<ActivationDialog> {
  static const int _maxSeconds = 300;

  String _status = 'loading'; // loading | code | success | error
  String _code = '';
  String _errorMsg = '';
  int _remaining = _maxSeconds;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  late final XiaozhiOtaService _otaService;

  @override
  void initState() {
    super.initState();
    _otaService = XiaozhiOtaService(otaUrl: widget.otaUrl);
    _start();
  }

  Future<void> _start() async {
    if (widget.otaUrl.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _errorMsg = '请先填写 OTA 地址';
      });
      return;
    }
    try {
      final resp = await _otaService.checkFlutterAppUpdates(
        appName: 'ajb_agent_flutter',
        appVersion: widget.appVersion,
      );
      if (!mounted) return;
      if (resp.websocket != null) {
        _stopTimers();
        setState(() {
          _status = 'success';
        });
        return;
      }
      if (resp.activation != null) {
        setState(() {
          _status = 'code';
          _code = resp.activation!.code;
        });
        _startPolling();
        _startCountdown();
        return;
      }
      setState(() {
        _status = 'error';
        _errorMsg = '服务器未返回激活信息，请检查 OTA 地址';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _errorMsg = '激活请求失败：$e';
      });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final resp = await _otaService.checkFlutterAppUpdates(
          appName: 'ajb_agent_flutter',
          appVersion: widget.appVersion,
        );
        if (!mounted) return;
        if (resp.websocket != null) {
          _stopTimers();
          setState(() {
            _status = 'success';
          });
        }
      } catch (_) {
        // 轮询失败静默重试，不中断倒计时
      }
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _stopTimers();
        if (mounted) {
          setState(() {
            _status = 'error';
            _errorMsg = '激活超时（5 分钟），请在 xiaozhi.me 后台完成激活后重试';
          });
        }
      }
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    _otaService.dispose();
    super.dispose();
  }

  String _formatRemaining() {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTextStyles.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      title: Text(
        '设备激活',
        style: AppTextStyles.navTitle.copyWith(
          color: AppTextStyles.primaryText(context),
        ),
      ),
      titlePadding: const EdgeInsets.only(
        top: AppDimens.gapXl,
        bottom: AppDimens.gapSm,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppDimens.pagePadding,
        0,
        AppDimens.pagePadding,
        AppDimens.gapMd,
      ),
      content: SizedBox(
        width: 270,
        child: _buildContent(),
      ),
      actions: [
        WxIconButton(
          label: '关闭',
          filled: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      actionsPadding: const EdgeInsets.only(
        right: AppDimens.gapXs,
        bottom: AppDimens.gapXs,
      ),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'loading':
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在请求激活信息...', textAlign: TextAlign.center),
            SizedBox(height: 24),
          ],
        );
      case 'code':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              '请前往 xiaozhi.me 后台，输入以下验证码激活设备',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Text(
              _code,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '剩余 ${_formatRemaining()}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text('正在自动检测激活状态...',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      case 'success':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('设备激活成功',
                style: AppTextStyles.bodyStrong),
            const SizedBox(height: 8),
            Text('设备已加入智能体列表，可以开始对话了',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
          ],
        );
      case 'error':
      default:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
          ],
        );
    }
  }
}
