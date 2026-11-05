/// 应用配置常量
class AppConfig {
  AppConfig._();

  // 应用信息
  static const String appName = '小乐'; // v4.0.0：品牌统一（默认智能体名前缀等）
  static const String appVersion = '6.11.18'; // v6.11.18：74 通信修复（P0-1 单连接/P0-2 hello ACK 闸门/P0-3 wakelock/P2-1 气泡边界）+ 73 UI（9 屏/任务卡/录音浮层）；v6.11.17：修 P0-1/P0-2/P2-1。详见 CHANGELOG.md

  /// v4.4.0 尾音保护：AI 播放结束后丢弃麦克风音频的时长（毫秒）
  static const int defaultTailGuardMs = 300;
  static const int minTailGuardMs = 100;
  static const int maxTailGuardMs = 500;

  /// v4.4.0 尾音保护时长的持久化键
  static const String keyTailGuardMs = 'tail_guard_ms';

  // API 配置（默认值，可在设置中修改）
  static const String defaultBaseUrl = 'https://api.example.com';
  static const int connectTimeout = 30000; // 30秒
  static const int receiveTimeout = 30000; // 30秒

  // 本地存储 Key
  static const String keyAgentList = 'agent_list';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyTtsVolume = 'tts_volume'; // v3.2.0：TTS 播放音量 0~100（抢话打断开关 v3.3 起归 AppFeats）

  // 分页配置
  static const int pageSize = 20;

  // 媒体配置
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;
  static const int imageQuality = 85;
  static const int maxAudioDuration = 60; // 秒

  // UI 配置
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const double spacing = 16.0;

  // 音频配置
  static int sampleRate = 16000;
  static int channels = 1;
  static int frameDuration = 60; // milliseconds
}
