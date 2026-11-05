import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/themes/xl_tokens.dart';
import '../../../../core/utils/audio_util.dart';
import '../../../widgets/xl/xl_voice_overlay.dart';

/// 供 ChatPage「更多」菜单调用持续监听（保留原功能，不丢入口）
class VoiceRecordController {
  /// 录音浮层状态：由聊天页 `Stack` 内的兄弟节点监听并渲染。
  final ValueNotifier<XlVoiceOverlayState> overlayState =
      ValueNotifier<XlVoiceOverlayState>(XlVoiceOverlayState.hidden);

  VoidCallback? _toggle;
  bool Function()? _active;

  void dispose() => overlayState.dispose();

  void attach({
    required VoidCallback toggle,
    required bool Function() active,
  }) {
    _toggle = toggle;
    _active = active;
  }

  void detach() {
    _toggle = null;
    _active = null;
  }

  bool get isContinuousListening => _active?.call() ?? false;

  void toggleContinuousListen() => _toggle?.call();
}

/// 按住说话按钮
/// ------------------------------------------------------------
/// §15 I10：系统 `onLongPressStart` 固定 500ms，无法做 120ms；
/// 改用 `RawGestureDetector + LongPressGestureRecognizer(duration: 120ms)`。
/// 上滑取消用 `details.offsetFromOrigin.dy`（相对按下点），80/72pt 迟滞。
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.onRecordStart,
    required this.onRecordEnd,
    required this.onRecordCancel,
    required this.onAudioSend,
    this.onRecordTooShort,
    this.onContinuousListenStart,
    this.onContinuousListenStop,
    this.controller,
  });

  final VoidCallback onRecordStart;
  final VoidCallback onRecordEnd;
  final VoidCallback onRecordCancel;
  /// <800ms 误触：不发音频、不产生气泡，只提示；用于通知聊天页收束本轮 listen
  final VoidCallback? onRecordTooShort;
  final ValueChanged<Uint8List> onAudioSend;
  final VoidCallback? onContinuousListenStart;
  final VoidCallback? onContinuousListenStop;
  final VoiceRecordController? controller;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  final Logger _log = Logger('VoiceRecord');
  bool _isRecording = false;
  bool _willCancel = false;
  bool _pressEnded = false;
  bool _closing = false;
  bool _isContinuousListening = false;

  DateTime? _startAt;
  Timer? _ticker;
  StreamSubscription<Uint8List>? _audioSub;

  final ValueNotifier<XlVoiceOverlayState> _localOverlayState =
      ValueNotifier<XlVoiceOverlayState>(XlVoiceOverlayState.hidden);

  ValueNotifier<XlVoiceOverlayState> get _overlayState =>
      widget.controller?.overlayState ?? _localOverlayState;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(
      toggle: _toggleContinuousListen,
      active: () => _isContinuousListening,
    );
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _ticker?.cancel();
    _audioSub?.cancel();
    _localOverlayState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final cancel = _isRecording && _willCancel;
    final pressed = _isRecording && !_willCancel;

    final bg = cancel
        ? p.dangerSoft
        : (pressed ? p.pressed : p.surface);
    final fg = cancel ? p.dangerText : p.textPrimary;
    final label = _isContinuousListening
        ? '正在聆听…'
        : (_isRecording
            ? (cancel ? '松开 取消' : '松开 发送')
            : '按住 说话');

    final button = AnimatedContainer(
      duration: XlMotion.instant,
      curve: XlMotion.standard,
      height: XlDims.voiceButtonHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(XlDims.rField),
      ),
      child: Text(
        label,
        style: XlType.body.copyWith(
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );

    return Semantics(
      label: '按住说话，上滑取消',
      button: true,
      onLongPress: _isContinuousListening ? null : _startFromSemantics,
      child: _isContinuousListening
          ? button
          : RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 120),
                    debugOwner: this,
                  ),
                  (instance) {
                    instance
                      ..onLongPressStart = _onStart
                      ..onLongPressMoveUpdate = _onMove
                      ..onLongPressEnd = _onEnd
                      ..onLongPressCancel = _onGestureCancel;
                  },
                ),
              },
              child: button,
            ),
    );
  }

  void _startFromSemantics() {
    _pressEnded = false;
    _onStart(null);
  }

  Future<void> _onStart(LongPressStartDetails? details) async {
    if (_isRecording || _closing) return;
    _pressEnded = false;
    if (!await _ensureMic()) return;
    if (_pressEnded) return;
    await _startRecording();
  }

  void _onMove(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    final dy = details.offsetFromOrigin.dy;
    if (!_willCancel && dy < -XlMotion.cancelThreshold) {
      setState(() => _willCancel = true);
      _overlayState.value = _overlayState.value.copyWith(willCancel: true);
      HapticFeedback.lightImpact();
    } else if (_willCancel &&
        dy > -(XlMotion.cancelThreshold - XlMotion.cancelHysteresis)) {
      setState(() => _willCancel = false);
      _overlayState.value = _overlayState.value.copyWith(willCancel: false);
    }
  }

  void _onEnd(LongPressEndDetails details) {
    _pressEnded = true;
    if (!_isRecording) return;
    final elapsed = _startAt == null
        ? Duration.zero
        : DateTime.now().difference(_startAt!);
    final tooShort = elapsed < const Duration(milliseconds: 800);
    if (tooShort) {
      // v6.11.18：误触拦截但不静默——先停上行，浮层给明确提示，再自动收回到待说话态
      _finish(send: false, tooShortElapsed: elapsed);
      return;
    }
    _finish(send: !_willCancel);
  }

  void _onGestureCancel() {
    _pressEnded = true;
    if (!_isRecording) return;
    _finish(send: false, silent: true);
  }

  Future<void> _finish({
    required bool send,
    bool silent = false,
    Duration? tooShortElapsed,
  }) async {
    if (!_isRecording || _closing) return;
    _closing = true;
    _ticker?.cancel();
    _ticker = null;

    // v6.11.18：<800ms 误触——先停上行（保证无音频发出），浮层提示 700ms，
    // 再收起并回到待说话态；不调 onRecordEnd（无气泡），也不弹"已取消录音"混淆视听
    if (tooShortElapsed != null) {
      await _stopAudio();
      _log.info('[RECORD] too-short elapsed=${tooShortElapsed.inMilliseconds}ms 已提示未发送');
      _overlayState.value = _overlayState.value.copyWith(
        visible: true,
        willCancel: false,
        elapsed: tooShortElapsed,
        hintOverride: '说话时间太短，请按住再说',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      _overlayState.value = _overlayState.value.copyWith(visible: false);
      await Future<void>.delayed(XlMotion.fast);
      if (mounted) {
        setState(() {
          _isRecording = false;
          _willCancel = false;
        });
      }
      _closing = false;
      // 通知聊天页收束本轮 listen start（不发音频、不产生气泡）
      widget.onRecordTooShort?.call();
      return;
    }

    // 浮层 150ms 淡出（取消），发送 90ms 收起
    _overlayState.value = _overlayState.value.copyWith(visible: false);
    await Future<void>.delayed(
      send ? const Duration(milliseconds: 90) : XlMotion.fast,
    );

    await _stopAudio();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _willCancel = false;
      });
    }
    _closing = false;

    if (send) {
      HapticFeedback.lightImpact();
      widget.onRecordEnd();
    } else if (!silent) {
      HapticFeedback.lightImpact();
      widget.onRecordCancel();
    }
  }

  Future<void> _startRecording() async {
    try {
      HapticFeedback.mediumImpact();
      widget.onRecordStart.call();

      _audioSub = AudioUtil.audioStream.listen(
        (audio) {
          if (_isRecording) widget.onAudioSend(audio);
        },
        onError: (Object e) {
          _fail('录音失败，请稍后再试');
        },
      );
      await AudioUtil.startRecording();

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _willCancel = false;
        _startAt = DateTime.now();
      });
      _overlayState.value = const XlVoiceOverlayState(
        visible: true,
        willCancel: false,
        elapsed: Duration.zero,
        showLimitHint: false,
        hintOverride: null,
      );
      _ticker = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _tick(),
      );
    } catch (e) {
      _fail('麦克风被占用，请稍后再试');
    }
  }

  void _tick() {
    final start = _startAt;
    if (start == null || !_isRecording) return;
    final elapsed = DateTime.now().difference(start);
    if (elapsed >= const Duration(seconds: 60)) {
      // 60s 自动发送
      _finish(send: !_willCancel);
      return;
    }
    _overlayState.value = _overlayState.value.copyWith(
      elapsed: elapsed,
      showLimitHint: elapsed >= const Duration(seconds: 45),
    );
  }

  Future<void> _stopAudio() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await AudioUtil.stopRecording();
    } catch (_) {}
  }

  Future<void> _fail(String message) async {
    _ticker?.cancel();
    _ticker = null;
    await _stopAudio();
    if (!mounted) return;
    _overlayState.value = XlVoiceOverlayState.hidden;
    setState(() {
      _isRecording = false;
      _willCancel = false;
    });
    _showError(message);
  }

  Future<bool> _ensureMic() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _showMicGuide();
      return false;
    }
    final result = await Permission.microphone.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied) {
      _showMicGuide();
    } else {
      _showError('麦克风权限被拒绝，按住说话无法录音');
    }
    return false;
  }

  /// 持续监听（原功能，入口移至「更多」菜单）
  Future<void> _toggleContinuousListen() async {
    if (_isContinuousListening) {
      await _stopContinuousListening();
    } else {
      await _startContinuousListening();
    }
  }

  Future<void> _startContinuousListening() async {
    if (!await _ensureMic()) return;
    try {
      setState(() => _isContinuousListening = true);
      HapticFeedback.mediumImpact();
      widget.onContinuousListenStart?.call();
      _audioSub = AudioUtil.audioStream.listen(
        (audio) {
          if (_isContinuousListening) widget.onAudioSend(audio);
        },
        onError: (_) => _stopContinuousListening(),
      );
      await AudioUtil.startRecording(enableAEC: true);
    } catch (e) {
      setState(() => _isContinuousListening = false);
      _showError('启动持续监听失败: $e');
    }
  }

  Future<void> _stopContinuousListening() async {
    if (!_isContinuousListening) return;
    HapticFeedback.lightImpact();
    await _stopAudio();
    widget.onContinuousListenStop?.call();
    if (mounted) setState(() => _isContinuousListening = false);
  }

  void _showMicGuide() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('麦克风权限没开，点这里去开启'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '去开启', onPressed: openAppSettings),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: XlPalette.of(context).danger,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

