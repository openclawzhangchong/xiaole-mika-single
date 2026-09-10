import 'package:flutter/foundation.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';

/// 开发者功能开关体系（v3.3.0，对齐网页版开发者中心模式，xiaoleweb.md 第十一章）
/// ------------------------------------------------------------------
/// 设计原则（照搬网页版）：每个高风险功能独立开关、可灰度、出问题关掉即回旧行为，
/// 永不回滚整版。开关即时读取（每次用前 get），无状态缓存导致的过期问题。
class AppFeats {
  AppFeats._();

  /// 开发者中心密码（与网页版一致）
  static const String devPassword = 'zc19901111';
  static const String _devAuthedKey = 'xw_dev_authed';

  /// 开关清单与默认值：
  /// - mcptools（🧰 MCP 设备工具）：v3.0 起默认开（用户批准）
  /// - vision（📷 视觉识物）：v3.1 起默认开
  /// - bargein（🎤 抢话打断）：v3.2 起默认开
  /// - mqtt（📡 MQTT 常驻在线）：v3.3 新增，**默认关**（EMQX 限流待真机观察，灰度）
  /// - mcpDebug（🧪 MCP 调试）：默认关（开=字幕保留 % 工具名原文）
  /// - emotion（😄 表情动画）：v4.3.0 新增，**默认关**（用户拍板：全屏动画移入
  ///   开发者中心，普通用户默认不见；消息内 emoji 前缀不受此开关影响）
  static const List<String> keys = [
    'mcptools',
    'mqtt',
    'vision',
    'bargein',
    'mcpDebug',
    'emotion'
  ];
  static const Map<String, bool> defaults = {
    'mcptools': true,
    'mqtt': false,
    'vision': true,
    'bargein': true,
    'mcpDebug': false,
    'emotion': false,
  };

  static final Map<String, bool> _cache = Map.from(defaults);

  /// 是否已通过密码授权（本机记住；开发者中心内可清除重新上锁）
  static bool get devAuthed =>
      StorageService.instance.getBool(_devAuthedKey) ?? false;

  static void setDevAuthed(bool v) =>
      StorageService.instance.setBool(_devAuthedKey, v);

  static bool get(String key) => _cache[key] ?? false;

  /// 「N 项开启」通知（设置页入口实时刷新用）
  static final ValueNotifier<int> onCountNotifier = ValueNotifier<int>(0);

  static void _notify() => onCountNotifier.value = onCount;

  static void set(String key, bool v) {
    _cache[key] = v;
    StorageService.instance.setBool('xw_feat_$key', v);
    _notify();
  }

  /// 启动时从存储恢复（chat_page initState 调用一次）
  static Future<void> load() async {
    for (final k in keys) {
      final v = StorageService.instance.getBool('xw_feat_$k');
      if (v != null) _cache[k] = v;
    }
    _notify();
  }

  static int get onCount => keys.where(get).length;

  static void allOff() {
    for (final k in keys) {
      set(k, false);
    }
  }

  // ---------- 语义化快捷读取（避免散落魔法字符串） ----------
  static bool get mcptools => get('mcptools');
  static bool get mqtt => get('mqtt');
  static bool get vision => get('vision');
  static bool get bargein => get('bargein');
  static bool get mcpDebug => get('mcpDebug');
  static bool get emotion => get('emotion');
}
