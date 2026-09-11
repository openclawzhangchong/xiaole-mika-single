import 'package:logging/logging.dart';

import '../storage/storage_service.dart';

/// 运行日志环形缓冲（v4.3.2 新增，v4.3.3 增加分类过滤）
///
/// 设计要点：
/// - **纯内存、不落盘**：进程内最多保留 [capacity] 条，超出丢弃最旧的一条；
///   App 退出即清空，不留存用户聊天内容，也不写任何持久化存储。
/// - **主接入点是 `main.dart` 的 `Logger.root.onRecord`**：全项目（chat_page /
///   cloud_sync / …）的 `logger.info/severe/warning` 都流经那里，因此无需在
///   各业务文件里补采集代码，只要照常 `logger.info(...)` 就会自动进缓冲。
/// - 次接入点 [push]：给 `AppLogger` 这类非 package:logging 通道手工写入用。
/// - **v4.3.3 分类过滤**：每条日志按内容/来源归入 [categories] 之一，
///   开发者中心「🗂 日志分类」可独立开关；**关闭的分类不写入缓冲区**（省内存、降噪音）。
///   默认只开 `vision / ws / mcp`（识图排查链路三件套），其余默认关。
///
/// 输出格式（纯文本，一行一条，便于整段粘贴给 AI 阅读）：
/// `2026-09-10 14:03:21.517 I [vision] ChatScreen 已发起 image_to_text 调用 id=10001`
class LogBuffer {
  LogBuffer._();

  /// 缓冲容量（条）
  static const int capacity = 500;

  /// 单条正文最大字符数（超出截断并标注被截掉的字符数）
  static const int maxMessageChars = 500;

  // ================= v4.3.3 日志分类 =================

  /// 全部分类（顺序即开发者中心展示顺序）
  static const List<String> categories = <String>[
    'vision',
    'ws',
    'mcp',
    'cloud',
    'ota',
    'audio',
    'ui',
  ];

  /// 分类中文显示名
  static const Map<String, String> categoryLabels = <String, String>{
    'vision': '📷 识图（照片）',
    'ws': '🔌 连接（WS）',
    'mcp': '🧰 MCP 消息',
    'cloud': '☁️ 云端同步',
    'ota': '🔑 OTA 认证',
    'audio': '🔊 音频',
    'ui': '🖥 界面与其他',
  };

  /// 默认开关：默认只开**识图排查链路 + 音频**（张老师拍板 v4.4.0 增加 audio）
  static const Map<String, bool> defaultCategoryEnabled = <String, bool>{
    'vision': true,
    'ws': true,
    'mcp': true,
    'cloud': false,
    'ota': false,
    'audio': true, // v4.4.0：排查语音「自问自答」需要，默认开
    'ui': false,
  };

  static const String _kPrefix = 'xw_logcat_';

  static final Map<String, bool> _catEnabled =
      Map<String, bool>.from(defaultCategoryEnabled);

  /// 分类是否开启（未开启的分类，其日志不会被写入缓冲）
  static bool isEnabled(String category) => _catEnabled[category] ?? false;

  /// 切换分类开关（即时生效并持久化）
  static void setCategory(String category, bool enabled) {
    _catEnabled[category] = enabled;
    StorageService.instance.setBool('$_kPrefix$category', enabled);
  }

  /// 启动时从存储恢复分类开关（main 里调用一次）
  static Future<void> loadCategories() async {
    for (final c in categories) {
      final v = StorageService.instance.getBool('$_kPrefix$c');
      if (v != null) _catEnabled[c] = v;
    }
  }

  /// 当前开启的分类数量（UI 展示用）
  static int get enabledCount => categories.where(isEnabled).length;

  /// 是否全部开启（UI 展示用）
  static bool get allEnabled => enabledCount == categories.length;

  /// 一键全开 / 全关
  static void setAll(bool enabled) {
    for (final c in categories) {
      setCategory(c, enabled);
    }
  }

  /// 按来源与内容推断分类（vision 优先级最高，避免识别图消息里含 mcp/ws 字样被误归）
  static String inferCategory(String tag, String message) {
    final both = '$tag $message';
    final lower = both.toLowerCase();
    // 1) 识图（照片）——最高优先
    if (both.contains('识图') ||
        both.contains('拍照') ||
        both.contains('📷') ||
        both.contains('📸') ||
        lower.contains('vision') ||
        lower.contains('image_to_text')) {
      return 'vision';
    }
    // 2) MCP 消息
    if (lower.contains('mcp')) return 'mcp';
    // 3) 连接 / WS
    if (lower.contains('websocket') ||
        lower.contains('socket') ||
        lower.contains('closecode') ||
        lower.contains('hello') ||
        both.contains('WS ') ||
        both.contains('连接') ||
        both.contains('断开')) {
      return 'ws';
    }
    // 4) 云端同步
    if (both.contains('云端') ||
        lower.contains('push') ||
        lower.contains('pull') ||
        lower.contains('bind')) {
      return 'cloud';
    }
    // 5) OTA
    if (both.contains('OTA') || both.contains('ota')) return 'ota';
    // 6) 音频
    if (both.contains('音频') ||
        lower.contains('opus') ||
        lower.contains('audio')) {
      return 'audio';
    }
    // 7) 其余
    return 'ui';
  }

  // ================= 缓冲本体 =================

  static final List<String> _lines = <String>[];

  /// 主接入点：写入一条 package:logging 的日志记录。
  static void add(LogRecord record) {
    final body = record.error == null
        ? _stringify(record.message)
        : '${_stringify(record.message)} | err=${record.error}';
    push(_levelChar(record.level), record.loggerName, body, record.time);
  }

  /// 次接入点：写入一条自定义日志（level 取 D/I/W/E/F 之一）。
  /// 关闭分类的日志在此被丢弃（不占缓冲）。
  static void push(String level, String tag, String message, [DateTime? at]) {
    final plain = _stringify(message);
    final category = inferCategory(tag, plain);
    if (!isEnabled(category)) return;
    _lines.add(
      '${_formatTime(at ?? DateTime.now())} $level [$category] $tag '
      '${_truncate(plain)}',
    );
    while (_lines.length > capacity) {
      _lines.removeAt(0);
    }
  }

  /// 最近 [n] 条日志拼成的纯文本（一行一条，按时间正序）。
  static String recentText([int n = 200]) {
    if (_lines.isEmpty) return '';
    final take = n <= 0 || n > _lines.length ? _lines.length : n;
    return _lines.sublist(_lines.length - take).join('\n');
  }

  /// 当前缓冲条数（UI 展示用）
  static int get length => _lines.length;

  /// 清空缓冲
  static void clear() => _lines.clear();

  static String _stringify(dynamic message) => message?.toString() ?? '';

  static String _truncate(String s) {
    if (s.length <= maxMessageChars) return s;
    final cut = s.length - maxMessageChars;
    return '${s.substring(0, maxMessageChars)}...[+$cut chars]';
  }

  /// 级别缩写：D(FINE 及以下) / I / W / E / F(SHOUT)
  static String _levelChar(Level level) {
    if (level >= Level.SHOUT) return 'F';
    if (level >= Level.SEVERE) return 'E';
    if (level >= Level.WARNING) return 'W';
    if (level >= Level.INFO) return 'I';
    return 'D';
  }

  /// 手动格式化时间戳（不引入 intl 依赖）：yyyy-MM-dd HH:mm:ss.SSS
  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
