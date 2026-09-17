import 'dart:math';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:logging/logging.dart';

/// 来电回铃音（核心层）
///
/// 用已有的 [flutter_pcm_sound] 合成 450Hz 正弦、响 1s / 静 2s 循环的断续回铃音
/// （真实电话回铃音规格），16kHz 单声道 16bit。零新增依赖、零音频资产。
///
/// 注意：回铃音仅用于来电页（来电时用户不在语音通话中），与主会话音频互斥；
/// [stop] 幂等且不抛异常。
class ProactiveRingtone {
  static final Logger _logger = Logger('ProactiveRingtone');

  static const int _sampleRate = 16000;
  static const int _toneSeconds = 1;
  static const int _silenceSeconds = 2;
  static const double _frequency = 450.0;
  static const double _amplitude = 0.25 * 32767.0;

  static bool _playing = false;
  static PcmArrayInt16? _loop;

  static bool get playing => _playing;

  /// 开始播放回铃音（幂等）。
  static Future<void> start() async {
    if (_playing) return;
    try {
      await FlutterPcmSound.setup(
        sampleRate: _sampleRate,
        channelCount: 1,
      );
      // 低缓冲阈值，使 feed 回调能及时补充数据，形成连续循环
      await FlutterPcmSound.setFeedThreshold(_sampleRate ~/ 10);
      _loop ??= _buildLoop();
      FlutterPcmSound.setFeedCallback(_onFeed);
      FlutterPcmSound.start();
      _playing = true;
      _logger.info('回铃音开始播放');
    } catch (e) {
      _logger.warning('回铃音启动失败（忽略）: $e');
    }
  }

  /// feed 回调：每当缓冲不足时由插件触发，补充一段循环缓冲。
  static void _onFeed(int remaining) {
    try {
      if (_loop != null) {
        FlutterPcmSound.feed(_loop!);
      }
    } catch (e) {
      _logger.warning('回铃音 feed 失败（忽略）: $e');
    }
  }

  /// 停止播放（幂等，不抛异常）。
  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await FlutterPcmSound.release();
      _logger.info('回铃音停止');
    } catch (e) {
      _logger.warning('回铃音停止失败（忽略）: $e');
    }
  }

  /// 合成一个循环缓冲：响 1s + 静 2s = 3s，450Hz 正弦。
  static PcmArrayInt16 _buildLoop() {
    const int totalSamples = _sampleRate * (_toneSeconds + _silenceSeconds);
    const int toneSamples = _sampleRate * _toneSeconds; // 1 秒
    final List<int> samples = List<int>.filled(totalSamples, 0);
    for (int i = 0; i < toneSamples; i++) {
      final double v = _amplitude * sin(2 * pi * _frequency * i / _sampleRate);
      samples[i] = v.round().clamp(-32768, 32767);
    }
    return PcmArrayInt16.fromList(samples);
  }
}
