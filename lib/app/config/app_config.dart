/// 应用配置常量
class AppConfig {
  AppConfig._();

  // 应用信息
  static const String appName = '小乐'; // v4.0.0：品牌统一（默认智能体名前缀等）
  static const String appVersion = '6.10.0'; // v6.10.0：微信风收口与 Design Token 治理 —— ① 补活 AppTextStyles 与 AppDimens（此前全项目零引用、是死代码；AppTextStyles 沦陷根因是把 color 写死导致深色模式不可用，新版不含颜色）；② 新建 6 个微信风组件 WxCell/WxCellGroup/WxDialog/WxActionSheet/WxIconButton/WxEmpty；③ 全项目硬编码字号 124 处收敛到 11/12/14/17/20 五档阶梯（聊天气泡 16→17 对齐微信正文）；④ 会话列表长按菜单由底部白抽屉改为微信屏幕正中央深色 ActionSheet。详见 CHANGELOG.md

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
