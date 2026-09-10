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

  /// 最近一次工具调用记录（供 UI 展示/日志），仅保留最近 20 条
  final List<String> recentCalls = [];

  XiaozhiMcpResponder({
    required this.send,
    this.serverName = 'xiaole-app',
    this.serverVersion = '3.0.0',
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
          _sendResult(id,
              {'tools': _tools.values.map((t) => t.toJson()).toList()});
          break;

        case 'tools/call':
          final name = params['name'] as String?;
          final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final executor = name == null ? null : _executors[name];
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

  /// v3.2.0：全量 11 项（对齐真机 mcp_server.cc）
  static List<XiaozhiMcpTool> fullSet() => [
        ...p0Set(),
        takePhoto,
        previewImage,
      ];
}
