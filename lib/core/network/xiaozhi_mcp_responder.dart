import 'dart:async';
import 'dart:convert';

/// 小智 MCP 设备端响应器（v3.0.0，对齐真机 mcp_server.cc 协议）
/// ------------------------------------------------------------------
/// 背景见 xiaoleweb.md 第五章：hello 声明 features.mcp:true 后，服务器会向
/// 本「虚拟设备」依次下发 mcp initialize → tools/list → tools/call。
/// 本类只做协议层：应答格式、工具清单、分发执行；具体工具效果由表现层
/// 通过 registerTool() 注入执行器（音量/主题/定时器/日程等）。
///
/// 应答格式（实测有效）：
///   {type:'mcp', payload:{jsonrpc:'2.0', id, result:{content:[{type:'text', text:'<JSON字符串>'}]}}}
///   错误: payload.error = {code, message}
typedef McpSendFn = void Function(String jsonText);
typedef McpToolExecutor = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> arguments);

/// 单个 MCP 工具定义（name/description/inputSchema 逐字段对齐真机）
class XiaozhiMcpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const XiaozhiMcpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'description': description, 'inputSchema': inputSchema};
}

class XiaozhiMcpResponder {
  final McpSendFn send;
  final String serverName;
  final String serverVersion;

  final Map<String, XiaozhiMcpTool> _tools = {};
  final Map<String, McpToolExecutor> _executors = {};

  /// 开关：关闭时不响应任何 MCP 请求（回到 v1.1.7 前的静默行为）
  bool enabled = true;

  /// v6.3.0：逐项工具开关过滤器。为 null 表示"全部启用"（保持既有行为完全不变）。
  /// 下发 tools/list 时据此过滤，被关工具对 AI 不可见；tools/call 命中被关工具
  /// 回 -32601（与"不存在"一致，避免暴露被关工具）。
  final bool Function(String name)? isToolEnabled;

  /// 最近一次工具调用记录（供 UI 展示/日志），仅保留最近 20 条
  final List<String> recentCalls = [];

  XiaozhiMcpResponder({
    required this.send,
    this.serverName = 'xiaole-app',
    this.serverVersion = '3.0.0',
    this.isToolEnabled,
  });

  void registerTool(XiaozhiMcpTool tool, McpToolExecutor executor) {
    _tools[tool.name] = tool;
    _executors[tool.name] = executor;
  }

  int get toolCount => _tools.length;

  /// 处理服务器下发的 mcp payload（chat_page 的 case 'mcp' 调用）。
  /// 注意：我们自己发出的应答（result 消息）不带 method，会被静默忽略，
  /// 因此无需额外的回环防护。
  void handlePayload(Map<String, dynamic> payload) {
    if (!enabled) return;
    final method = payload['method'] as String?;
    final id = payload['id'];
    if (method == null || id == null) return;
    final params = (payload['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    unawaited(_dispatch(method, id, params));
  }

  Future<void> _dispatch(
      String method, dynamic id, Map<String, dynamic> params) async {
    try {
      switch (method) {
        case 'initialize':
          _sendResult(id, {
            'protocolVersion':
                (params['protocolVersion'] as String?) ?? '2024-11-05',
            'capabilities': {
              'tools': {'listChanged': false}
            },
            'serverInfo': {'name': serverName, 'version': serverVersion},
          });
          break;

        case 'tools/list':
          _sendResult(id, {
            'tools': _tools.values
                .where((t) => isToolEnabled?.call(t.name) ?? true)
                .map((t) => t.toJson())
                .toList()
          });
          break;

        case 'tools/call':
          final name = params['name'] as String?;
          final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final executor = name == null ? null : _executors[name];
          // v6.3.0：逐项开关 —— 被禁用的工具对 AI 不可见，命中即回 -32601
          // （与"不存在"一致，避免暴露被关工具的存在）
          if (executor != null &&
              name != null &&
              isToolEnabled != null &&
              !isToolEnabled!.call(name)) {
            _sendError(id, -32601, 'unknown tool: $name');
            break;
          }
          if (executor == null) {
            _sendError(id, -32601, 'unknown tool: $name');
            break;
          }
          _logCall('$name ${jsonEncode(args)}');
          final result = await executor(args);
          _sendResult(id, {
            'content': [
              {'type': 'text', 'text': jsonEncode(result)}
            ]
          });
          break;

        default:
          // 未知 method：宽容忽略（对齐真机行为，不回错）
          break;
      }
    } catch (e) {
      _sendError(id, -32603, e.toString().sliceOrFull(0, 200));
    }
  }

  void _logCall(String text) {
    recentCalls.insert(0, text);
    if (recentCalls.length > 20) recentCalls.removeLast();
  }

  void _sendResult(dynamic id, Map<String, dynamic> result) {
    send(jsonEncode({
      'type': 'mcp',
      'payload': {'jsonrpc': '2.0', 'id': id, 'result': result}
    }));
  }

  void _sendError(dynamic id, int code, String message) {
    send(jsonEncode({
      'type': 'mcp',
      'payload': {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message}
      }
    }));
  }
}

extension _Slice on String {
  String sliceOrFull(int start, int end) {
    if (length <= end) return this;
    return substring(start, end);
  }
}

/// P0 内置 9 项工具的标准定义（schema 与真机 mcp_server.cc 对齐，勿随意改动
/// 字段类型/必填项——服务器据此指导 AI 传参）。执行器由表现层注入。
class XiaozhiMcpStandardTools {
  static const status = XiaozhiMcpTool(
    name: 'self.get_device_status',
    description:
        'Provides the real-time information of the device, including the current status of the audio speaker volume, screen theme, battery and network.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const setVolume = XiaozhiMcpTool(
    name: 'self.audio_speaker.set_volume',
    description:
        'Set the volume of the audio speaker. If the current volume is unknown, call self.get_device_status first.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'volume': {'type': 'integer', 'minimum': 0, 'maximum': 100}
      },
      'required': ['volume']
    },
  );

  static const setTheme = XiaozhiMcpTool(
    name: 'self.screen.set_theme',
    description: 'Set the theme of the screen: light or dark.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'theme': {'type': 'string', 'enum': ['light', 'dark']}
      },
      'required': ['theme']
    },
  );

  static const timerCreate = XiaozhiMcpTool(
    name: 'self.timer.create_countdown',
    description:
        'Create a countdown timer in seconds. When it finishes the device will remind the user with voice and notification.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'seconds': {'type': 'integer', 'description': 'Duration in seconds'},
        'event_name': {'type': 'string', 'description': 'Optional name of the countdown'}
      },
      'required': ['seconds']
    },
  );

  static const timerList = XiaozhiMcpTool(
    name: 'self.timer.get_tasks',
    description: 'List all active countdown timers.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const timerStop = XiaozhiMcpTool(
    name: 'self.timer.stop_task',
    description: 'Stop an active countdown timer by id.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'integer'}
      },
      'required': ['id']
    },
  );

  static const scheduleCreate = XiaozhiMcpTool(
    name: 'self.schedule.create_event',
    description:
        'Create a scheduled event reminder at a specific time. Format of time: YYYY-MM-DD HH:MM.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'time': {'type': 'string'},
        'event_name': {'type': 'string'}
      },
      'required': ['time', 'event_name']
    },
  );

  static const scheduleList = XiaozhiMcpTool(
    name: 'self.schedule.get_events',
    description: 'List all scheduled events.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const scheduleDelete = XiaozhiMcpTool(
    name: 'self.schedule.delete_event',
    description: 'Delete a scheduled event by id.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'integer'}
      },
      'required': ['id']
    },
  );

  // v3.2.0：补齐后两项，凑满真机同款 11 项工具
  static const takePhoto = XiaozhiMcpTool(
    name: 'self.camera.take_photo',
    description:
        'Take a photo with the camera and explain it. Use this tool when the user asks you to see or look at something.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'question': {
          'type': 'string',
          'description': 'The question you want to ask about the photo'
        }
      },
      'required': ['question']
    },
  );

  static const previewImage = XiaozhiMcpTool(
    name: 'self.screen.preview_image',
    description:
        'Display an image on the screen for the user (shown as a picture bubble in chat).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'Image URL (https)'}
      },
      'required': ['url']
    },
  );

  // ==================== v6.1.0 新增能力（方案见 PLAN_v6.1.0_MCP设备工具能力扩展.md）====================

  // ---- 🅑 补齐官方标准（官方 mcp_server.cc 有、我们原先缺失）----

  static const setBrightness = XiaozhiMcpTool(
    name: 'self.screen.set_brightness',
    description: 'Set the screen brightness. Range 1-100 (application-level, '
        'no special permission required).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'brightness': {'type': 'integer', 'minimum': 1, 'maximum': 100}
      },
      'required': ['brightness']
    },
  );

  static const getScreenInfo = XiaozhiMcpTool(
    name: 'self.screen.get_info',
    description: 'Get the screen information (width, height, pixel ratio) '
        'in logical pixels, useful for adapting layouts.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const getSystemInfo = XiaozhiMcpTool(
    name: 'self.get_system_info',
    description: 'Get system and device information: app version, platform, '
        'device model, manufacturer, Android version.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const snapshot = XiaozhiMcpTool(
    name: 'self.screen.snapshot',
    description: 'Take a screenshot of the current app screen and save it locally. '
        'Use this when the user asks you to look at the current screen. '
        'The picture bubble will be shown in the chat.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const reboot = XiaozhiMcpTool(
    name: 'self.reboot',
    description: 'Restart the assistant session on the device '
        '(reconnect the websocket and clear the current conversation). '
        'It does NOT reboot the phone.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  // ---- 🅒 Android 系统能力（全部免危险权限）----

  static const dial = XiaozhiMcpTool(
    name: 'self.phone.dial',
    description: 'Open the phone dialer with a number pre-filled. '
        'The user still needs to press the call button. '
        'Use this for requests like "call mom".',
    inputSchema: {
      'type': 'object',
      'properties': {
        'number': {'type': 'string', 'description': 'Phone number to dial'}
      },
      'required': ['number']
    },
  );

  static const sendSms = XiaozhiMcpTool(
    name: 'self.message.send_sms',
    description: 'Open the SMS app with recipient and message pre-filled. '
        'The user still needs to press send.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'number': {'type': 'string', 'description': 'Recipient phone number'},
        'body': {'type': 'string', 'description': 'Message content'}
      },
      'required': ['number', 'body']
    },
  );

  static const navigate = XiaozhiMcpTool(
    name: 'self.map.navigate',
    description: 'Open the map app and navigate to a destination '
        '(place name or address).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'destination': {'type': 'string', 'description': 'Place name or address'}
      },
      'required': ['destination']
    },
  );

  static const openSettings = XiaozhiMcpTool(
    name: 'self.system.open_settings',
    description: 'Open an Android system settings page. '
        'Supported pages: wifi, bluetooth, sound, display, battery, location, '
        'apps, airplane, data, home.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'page': {
          'type': 'string',
          'description': 'Settings page key',
          'enum': [
            'wifi', 'bluetooth', 'sound', 'display', 'battery',
            'location', 'apps', 'airplane', 'data', 'home'
          ]
        }
      },
      'required': ['page']
    },
  );

  static const openUrl = XiaozhiMcpTool(
    name: 'self.system.open_url',
    description: 'Open a web page in the system browser.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'Web URL'}
      },
      'required': ['url']
    },
  );

  // ---- 🅐 闹钟与轻提示 / 分享 ----

  static const setAlarm = XiaozhiMcpTool(
    name: 'self.alarm.set_alarm',
    description: 'Set a REAL system alarm in the phone clock app. '
        'The system clock will open with the alarm pre-filled; '
        'the user must tap save to confirm. '
        'Once saved, the alarm rings even if this app is closed or the phone restarts.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23,
          'description': 'Hour in 24-hour format'},
        'minute': {'type': 'integer', 'minimum': 0, 'maximum': 59},
        'label': {'type': 'string', 'description': 'Alarm label, e.g. "起床"'},
        'weekdays': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
          'description': 'Repeat days (1=Sunday ... 7=Saturday). '
              'Omit or empty for a one-time alarm.'
        }
      },
      'required': ['hour', 'minute']
    },
  );

  static const showToast = XiaozhiMcpTool(
    name: 'self.show_toast',
    description: 'Show a short toast message on the screen. '
        'Use it for lightweight feedback (e.g. "已记下") without interrupting the '
        'conversation. Do not use it for important information.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Text to show, keep it short'}
      },
      'required': ['text']
    },
  );

  static const shareText = XiaozhiMcpTool(
    name: 'self.share.text',
    description: 'Share a text to other apps (notes, memo, WeChat, ...) via the '
        'system share sheet. Use this to save a note or memo for the user; '
        'the user picks the target app and confirms.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Content to share'},
        'subject': {'type': 'string', 'description': 'Optional title'}
      },
      'required': ['text']
    },
  );

  // ---- 🅓 剪贴板 ----

  static const clipboardGet = XiaozhiMcpTool(
    name: 'self.clipboard.get',
    description: 'Read the current clipboard text.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  static const clipboardSet = XiaozhiMcpTool(
    name: 'self.clipboard.set',
    description: 'Write text into the system clipboard.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'}
      },
      'required': ['text']
    },
  );

  // ---- 🅔 定位能力（v6.3.0，方案见 PLAN_v6.3.0）----
  // 坐标统一以 GCJ-02 返回（高德/腾讯/百度地图通用；Android 原生 GPS 是 WGS-84，
  // 由 LocationService 内部完成 WGS-84→GCJ-02 转换，调用方无需关心）。

  static const locationGetCurrent = XiaozhiMcpTool(
    name: 'self.location.get_current',
    description: 'Get the device current location. Returns latitude and longitude '
        'in GCJ-02 coordinate system (used by Amap/Tencent/Baidu maps), plus '
        'horizontal accuracy and the provider. Requires the user to have granted '
        'location permission and enabled location services on the device. '
        'Use this when the user asks "where am I", needs navigation, or asks '
        'for nearby recommendations.',
    inputSchema: {'type': 'object', 'properties': {}},
  );

  /// v6.1.0：本轮新增的 15 项能力
  static List<XiaozhiMcpTool> v61Tools() => [
        // 🅑 官方标准补齐
        setBrightness,
        getScreenInfo,
        getSystemInfo,
        snapshot,
        reboot,
        // 🅒 系统能力
        dial,
        sendSms,
        navigate,
        openSettings,
        openUrl,
        // 🅐 闹钟 / 轻提示 / 分享
        setAlarm,
        showToast,
        shareText,
        // 🅓 剪贴板
        clipboardGet,
        clipboardSet,
      ];

  static List<XiaozhiMcpTool> p0Set() => [
        status,
        setVolume,
        setTheme,
        timerCreate,
        timerList,
        timerStop,
        scheduleCreate,
        scheduleList,
        scheduleDelete,
      ];

  /// v3.2.0：全量 11 项。⚠️ 当时的注释称"对齐真机 mcp_server.cc"**不准确**——
  /// 经 v6.1.0 逐字核对官方源码：官方**没有** timer / schedule / alarm / toast 任何工具，
  /// `self.timer.*` 与 `self.schedule.*` 属**本项目自研扩展**。
  static List<XiaozhiMcpTool> fullSet() => [
        ...p0Set(),
        takePhoto,
        previewImage,
      ];

  /// v6.1.0：注册用的完整工具集 = 原有 11 项 + 本轮新增 15 项 = **26 项**
  static List<XiaozhiMcpTool> allTools() => [
        ...fullSet(),
        ...v61Tools(),
      ];

  /// v6.3.0：26 项 + 定位能力（self.location.get_current）= **27 项**。
  /// 供 AppFeats.load() 一并恢复逐项开关状态。
  static List<XiaozhiMcpTool> allToolsWithLocation() => [
        ...allTools(),
        locationGetCurrent,
      ];
}
