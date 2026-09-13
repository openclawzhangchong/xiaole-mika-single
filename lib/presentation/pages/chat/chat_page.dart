import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xiaozhi_client_flutter/core/mcp/device_capability_service.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_ota_service.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mcp_responder.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mqtt_presence.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_websocket_manager.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import 'package:xiaozhi_client_flutter/core/providers/agent_provider.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/core/providers/theme_provider.dart';
import 'package:xiaozhi_client_flutter/core/utils/audio_util.dart';
import 'package:vibration/vibration.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:xiaozhi_client_flutter/data/models/agent_model.dart';
import '../../../data/models/message_model.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/themes/app_colors.dart';
import '../../../core/utils/toast_util.dart';
import '../../widgets/agent_avatar.dart';
import '../../services/agent_identity_store.dart';
import '../../services/app_feats.dart';
import '../../services/chat_history_store.dart';
import 'widgets/message_list.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/voice_record_button.dart';
import 'widgets/emotion_animation_overlay.dart';
import 'package:logging/logging.dart';

/// 聊天页面
class ChatPage extends ConsumerStatefulWidget {
  final String agentId;
  final String agentName;

  const ChatPage({super.key, required this.agentId, required this.agentName});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final Logger logger = Logger('ChatScreen');
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<MessageModel> _messages = [];
  bool _showVoiceButton = false;
  AgentModel? _currentAgent;

  // WebSocket 相关
  XiaozhiWebSocketManager? _wsManager;
  bool _isConnected = false;
  String _connectionStatus = '未连接';
  String? _sessionId;

  // v3.0.0：MCP 设备端（协议见 xiaoleweb.md 第五章；响应器=协议层，执行器=本页注入）
  XiaozhiMcpResponder? _mcpResponder;
  final List<Map<String, dynamic>> _mcpTimers = []; // {id,name,endAt,Timer}
  final List<Map<String, dynamic>> _mcpEvents = []; // {id,name,time,Timer}

  // v3.1.0：周期性设备状态上报（WS 连接即报 + 每 10 分钟，后台「最近活跃」对齐）
  Timer? _otaReportTimer;
  // v3.1.0：想打就打——连接成功后自动执行的原操作（见 xiaoleweb.md §2.6）
  Function? _pendingAutoAction;
  String _pendingAutoLabel = '';
  // v3.1.0：视觉识物（vision 接口从 MCP initialize 的 params.capabilities.vision 提取）
  String? _visionUrl;
  String? _visionToken;
  // v4.3.1：识图两段式——设备主动发起的 MCP tools/call（image_to_text）。
  // id 从 10000 自增，避开服务器下发请求的 id 空间；待决表按 id 匹配应答。
  int _mcpCallId = 10000;
  final Map<int, Completer<String>> _pendingMcpCalls = {};

  /// v4.3.3：识图路径 C 的等待器——服务器主动推送的文本（tts/llm）若在识图期间到达，
  /// 由它接收，实现三路竞速"谁先出结果用谁"。
  Completer<String>? _visionAux;
  // v4.3.1：聊天页标题（从配置页改名返回后可刷新；构造参数 widget.agentName 是 final）
  late String _agentName = widget.agentName;
  // v3.3.0：📡 MQTT 常驻在线（OTA 响应下发凭据 → 原生 TLS 8883 直连 broker）
  XiaozhiMqttPresence? _mqttPresence;
  // v3.1.0：情绪先于句子到达时暂存（随下一句 sentence_start 挂上）
  String _pendingEmotion = '';
  // v4.2.0：动图表情——AI 情绪到达时触发全屏动画（申请书 6 号）
  String? _activeEmotionEmoji;
  String? _activeEmotionKey;
  // v4.2.0：真实电量（申请书 8 号，battery_plus；桌面端不可用时回退虚拟值）
  final Battery _battery = Battery();
  // v4.4.0：barge-in（抢话打断）已**移除**。
  // 原实现（v3.2.0 引入）用未经回声消除的麦克风原始振幅判断用户开口，
  // AI 说话时扬声器回声必然使其超标 → 误触发 → 提前恢复上行 → AI 自己的声音被上传
  // → 「自问自答」。详见 PLAN_v4.4.0_语音自问自答修复.md 根因③。
  // 需要时可回退到远端 git 历史（v4.3.5 及更早）取回实现。
  StreamSubscription<double>? _bargeinSub;

  // OTA 认证信息
  XiaozhiOtaService? _otaService;

  // AI 播放状态跟踪
  bool _isAiPlaying = false;
  Timer? _aiPlayingTimer; // 用于检测播放结束的定时器

  /// v4.4.0 尾音保护：AI 播放结束后的一段时间内**丢弃**麦克风上行音频，
  /// 避免扬声器缓冲区里残留的尾音被收录并当成"用户开口"（根因①）。null = 不在保护期。
  DateTime? _resumeGuardUntil;

  /// v4.4.0：尾音保护时长（毫秒）——默认 300，可调范围 100–500（开发者中心「⏱ 尾音保护」）
  int get _tailGuardMs {
    final v = StorageService.instance.getInt(AppConfig.keyTailGuardMs);
    if (v == null) return AppConfig.defaultTailGuardMs;
    return v.clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
  }

  /// 进入尾音保护期（AI 播放结束的两个入口调用）
  void _enterTailGuard() {
    _resumeGuardUntil = DateTime.now().add(Duration(milliseconds: _tailGuardMs));
    logger.info('[audio] 进入尾音保护 ${_tailGuardMs}ms（丢弃此期间的麦克风音频）');
  }

  // AI 正在输入 / 语音通话
  bool _isAiTyping = false;
  bool _isInVoiceCall = false;
  bool _showVoiceCallOverlay = false;

  /// v6.1.1：页面根视图的 RepaintBoundary key —— 供 `self.screen.snapshot` 工具截屏
  final GlobalKey _snapshotKey = GlobalKey();
  bool _micMuted = false;
  StreamSubscription<Uint8List>? _callAudioSubscription;
  DateTime? _voiceCallStart;
  Timer? _voiceCallTimer;
  String _voiceCallDuration = '00:00';
  bool _isSpeakerOn = false;
  String _callStatus = '等待连接...';

  @override
  void initState() {
    super.initState();
    // v3.2.0：恢复 TTS 音量偏好（set_volume 工具与设置页滑杆共用）
    final savedVol = StorageService.instance.getInt(AppConfig.keyTtsVolume);
    if (savedVol != null) AudioUtil.setTtsVolume(savedVol);
    // v4.4.0：barge-in 已移除，不再需要把开关同步进状态（其余开发者开关照常加载）
    AppFeats.load();
    // v4.3.0：全局设备型号矫正——手机型号 fallback / xiaole-voice-v1 旧值
    // 幂等归一为 m5stack-core-s3（OTA 识别层早已统一，此为展示/存储层残留清理）
    AgentIdentityStore.normalizeGlobalModel();
    _loadHistory();
    _loadAgent();
    // v4.3.3：页面生命周期打点——相机 Activity 可能触发页面重建，
    // 用 initState / dispose 时间戳可判定"识图过程中页面是否被销毁"（会中断识图流程）
    logger.info('聊天页 initState（页面挂载）agentId=${widget.agentId}');
  }

  /// v1.1.6: 加载本地聊天记录（进入对话即显示历史）
  Future<void> _loadHistory() async {
    final history = await ChatHistoryStore.load(widget.agentId);
    if (!mounted || _messages.isNotEmpty || history.isEmpty) return;
    setState(() {
      _messages.addAll(history);
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _aiPlayingTimer?.cancel();
    _voiceCallTimer?.cancel();
    _otaReportTimer?.cancel();
    _mqttPresence?.stop();
    for (final t in _mcpTimers) {
      (t['timer'] as Timer?)?.cancel();
    }
    for (final e in _mcpEvents) {
      (e['timer'] as Timer?)?.cancel();
    }
    // v4.3.3：页面销毁打点（含来源标记）——与 initState 配对，可判定页面是否被重建
    logger.info('聊天页 dispose（页面销毁，将主动断开 WS）');
    // v6.0.0：若在通话全屏状态下直接销毁页面，恢复系统 UI，避免沉浸式残留到其他页面
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cleanupWebSocket(source: 'dispose');
    _otaService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // v6.1.1：用 RepaintBoundary 包住页面根视图，供 `self.screen.snapshot` 工具截屏
    // （纯包裹层，不影响视觉与布局）
    return RepaintBoundary(
      key: _snapshotKey,
      child: Scaffold(
      // v6.0.0：通话中隐藏顶端工具栏，使通话界面全屏扩展（微信通话效果）
      appBar: _showVoiceCallOverlay
          ? null
          : AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_agentName),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _isConnected ? '已连接' : '未连接',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: _showMoreOptions,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 连接状态栏（仅在非连接状态时显示）
              if (!_isConnected) _buildConnectionStatusBar(),

              // 通话中最小化提示条
              if (_isInVoiceCall && !_showVoiceCallOverlay)
                _buildVoiceCallBanner(),

              // 消息列表
              Expanded(
                child: MessageList(
                  messages: _messages,
                  scrollController: _scrollController,
                  isTyping: _isAiTyping,
                  avatarStyleIndex:
                      widget.agentId.hashCode.abs() % kAgentAvatarStyles.length,
                ),
              ),

              // 输入区域（根据模式显示不同的组件）
              if (_showVoiceButton)
                _buildVoiceInputArea()
              else
                ChatInputBar(
                  textController: _textController,
                  onSendText: _sendTextMessage,
                  onStartVoice: () {
                    setState(() {
                      _showVoiceButton = true;
                    });
                  },
                  onStartCall: _startVoiceCall,
                  onTakePhoto: AppFeats.vision ? _takePhotoAndAsk : null,
                ),
            ],
          ),
          // 语音通话全屏覆盖层
          if (_showVoiceCallOverlay) _buildVoiceCallOverlay(),
          // v4.2.0：全屏动图表情（申请书 6 号，AI 情绪驱动）
          if (_activeEmotionEmoji != null)
            EmotionAnimationOverlay(
              key: ValueKey('emo_${DateTime.now().millisecondsSinceEpoch}'),
              emoji: _activeEmotionEmoji!,
              emotion: _activeEmotionKey ?? 'happy',
              onDone: () => setState(() {
                _activeEmotionEmoji = null;
                _activeEmotionKey = null;
              }),
            ),
        ],
      ),
      ),
    );
  }

  /// 连接状态栏
  Widget _buildConnectionStatusBar() {
    Color statusColor;
    IconData statusIcon;
    String statusText = _connectionStatus;

    // 根据连接状态设置颜色和图标（微信功能色板）
    if (_isConnected) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
    } else if (_connectionStatus == '正在连接...' || _connectionStatus == '正在认证...') {
      statusColor = AppColors.warning;
      statusIcon = Icons.sync;
    } else {
      statusColor = AppColors.error;
      statusIcon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(
            color: statusColor.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          // 断线时显示重连按钮
          if (!_isConnected && 
              _connectionStatus != '正在连接...' && 
              _connectionStatus != '正在认证...')
            TextButton.icon(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重连'),
              style: TextButton.styleFrom(
                foregroundColor: statusColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  /// 重新连接
  Future<void> _reconnect() async {
    if (_connectionStatus == '正在连接...' || _connectionStatus == '正在认证...') {
      return; // 正在连接中，不重复连接
    }

    ToastUtil.show('正在重新连接...');
    
    // 清理旧连接
    await _cleanupWebSocket(source: 'user_button');
    
    // 重新初始化 WebSocket
    await _initializeWebSocket();
  }

  /// 语音输入区域
  Widget _buildVoiceInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 切换回文本输入按钮
            IconButton(
              icon: const Icon(Icons.keyboard),
              onPressed: () {
                setState(() {
                  _showVoiceButton = false;
                });
              },
              tooltip: '切换到文本输入',
            ),

            // 按住说话按钮
            Expanded(
              child: VoiceRecordButton(
                onRecordStart: _handleAudioStart,
                onAudioSend: _handleAudioSend,
                onRecordEnd: _handleAudioStop,
                onRecordCancel: _onRecordCancel,
                onContinuousListenStart: _handleContinuousListenStart,
                onContinuousListenStop: _handleContinuousListenStop,
              ),
            ),

          ],
        ),
      ),
    );
  }

  /// 发送文本消息
  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // v3.1.0：想打就打（xiaoleweb.md §2.6）——未连接时自动连接，hello ACK 后自动发送
    if (!_isConnected) {
      _ensureConnectedThen(() {
        _wsManager?.sendTextRequest(text);
        _setTyping(true);
      }, '发送消息');
      _textController.clear();
      _setTyping(true);
      _scrollToBottom();
      return;
    }

    // 调用接口发送消息
    _wsManager?.sendTextRequest(text);

    _textController.clear();
    _setTyping(true);
    _scrollToBottom();
  }

  /// v3.1.0：想打就打（xiaoleweb.md §2.6）——未连接时自动发起连接，
  /// hello ACK（服务器会话确认）后自动执行原操作。
  void _ensureConnectedThen(Function action, String label) {
    if (_isConnected) {
      action();
      return;
    }
    _pendingAutoAction = action;
    _pendingAutoLabel = label;
    if (_connectionStatus == '正在连接...') {
      ToastUtil.show('连接中…连上后自动$label');
      return;
    }
    ToastUtil.show('正在自动连接…连上后自动$label');
    _initializeWebSocket();
  }

  void _runPendingAutoAction() {
    final action = _pendingAutoAction;
    if (action == null) return;
    _pendingAutoAction = null;
    logger.info('连接就绪，自动$_pendingAutoLabel');
    Future.delayed(const Duration(milliseconds: 300), () => action());
  }

  /// v3.1.0：MCP 工具标记过滤（对齐网页版 stripMcpMarkers，xiaoleweb.md §2.4）。
  /// 剥离句中 `% 工具名`（% 前须为行首/空白，避免误伤 "50% off"）。
  static final RegExp _mcpMarkRe = RegExp(r'(^|\s)%\s*[a-zA-Z][\w.\-]*');
  String _stripMcpMarkers(String txt) {
    if (AppFeats.mcpDebug) return txt; // 🧪 MCP 调试开=保留原文
    return txt
        .replaceAllMapped(_mcpMarkRe, (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  /// v4.2.0：全屏动图表情（申请书 6 号）——AI 情绪到达时触发，播放完自动移除。
  /// v4.3.0：受开发者中心「😄 表情动画」开关控制（默认关）；消息内 emoji 前缀不受影响。
  void _showEmotionAnimation(String emoji, String emotion) {
    if (!AppFeats.emotion) return;
    setState(() {
      _activeEmotionEmoji = emoji;
      _activeEmotionKey = emotion;
    });
  }

  void _appendOrCreateChatMessage(MessageSender role, String content,
      {Map<String, dynamic>? metadata}) {
    // v3.1.0：system 消息（MCP 工具调用记录/定时器提醒）真实入列——
    // 原实现对 system 直接 return，导致 v3.0.0 的 MCP 提醒全部不显示。
    // system 用 MessageType.system 独立成行（气泡有对应渲染分支），不参与合并。
    // v4.2.0：支持 metadata（设备状态卡片等结构化负载随消息渲染）。
    if (role == MessageSender.system) {
      final message = MessageModel(
        id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
        agentId: widget.agentId,
        type: MessageType.system,
        content: content,
        sender: MessageSender.system,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
        metadata: metadata,
      );
      setState(() {
        _messages.add(message);
      });
      ChatHistoryStore.save(widget.agentId, _messages);
      _scrollToBottom();
      return;
    }
    final targetSender = role == MessageSender.ai
        ? MessageSender.ai
        : MessageSender.user;

    // 检查最后一条消息是否与当前角色相同
    if (_messages.isNotEmpty && _messages.last.sender == targetSender) {
      // 最后一条消息角色相同，追加内容
      setState(() {
        final lastMessage = _messages.last;
        final updatedMessage = MessageModel(
          id: lastMessage.id,
          agentId: lastMessage.agentId,
          type: lastMessage.type,
          content: lastMessage.content + content,
          sender: lastMessage.sender,
          status: lastMessage.status,
          timestamp: lastMessage.timestamp,
        );
        _messages[_messages.length - 1] = updatedMessage;
      });
    } else {
      // 最后一条消息角色不同或列表为空，创建新消息
      final message = MessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        agentId: widget.agentId,
        type: MessageType.text,
        content: content,
        sender: targetSender,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(message);
      });
    }

    // v1.1.6: 消息落库（本地聊天记录）
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// 取消录音
  void _onRecordCancel() {
    ToastUtil.show('已取消录音');
  }

  /// 显示更多选项（微信 ActionSheet 风格）
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 选项组
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: InkWell(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        onTap: () {
                          Navigator.pop(context);
                          _clearMessages();
                        },
                        child: const Center(
                          child: Text(
                            '清空聊天记录',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 0.5, thickness: 0.5),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: InkWell(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                        onTap: () async {
                          Navigator.pop(context);
                          // v4.3.1：接线智能体设置（与会话列表页长按编辑同款）
                          await context.push(
                              '${AppRoutes.agentConfig}?agentId=${widget.agentId}');
                          // 返回后刷新标题（配置页改名经 agentListProvider 已更新）
                          if (!mounted) return;
                          final agents =
                              ref.read(agentListProvider).value ?? [];
                          for (final a in agents) {
                            if (a.id == widget.agentId) {
                              if (a.name != _agentName) {
                                setState(() => _agentName = a.name);
                              }
                              break;
                            }
                          }
                        },
                        child: const Center(
                          child: Text(
                            '智能体设置',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 取消按钮
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context),
                    child: const Center(
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 清空消息
  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
    // v1.1.6: 同步清空本地聊天记录
    ChatHistoryStore.save(widget.agentId, _messages);
    ToastUtil.success('已清空聊天记录');
  }

  /// 滚动到底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// 加载智能体数据（编辑模式）
  Future<void> _loadAgent() async {
    final agent = await ref
        .read(agentListProvider.notifier)
        .getAgentById(widget.agentId);

    if (agent != null) {
      setState(() {
        _currentAgent = agent;
        // 初始化 OTA 服务，使用 Agent 的 otaUrl
        _otaService = XiaozhiOtaService(
          otaUrl: agent.otaUrl.isNotEmpty
              ? agent.otaUrl
              : 'https://api.tenclass.net/xiaozhi/ota/',
        );
      });
      // Agent 加载完成后，初始化 WebSocket
      _initializeWebSocket();
    } else {
      // 如果智能体不存在，返回智能体列表页面
      if (mounted) {
        context.go('/home');
      }
    }
  }

  /// 清理 WebSocket 连接
  /// [source] v4.3.3：断开来源标记，写入日志便于区分"App 主动断开"与"服务器断开"
  Future<void> _cleanupWebSocket({String source = 'unknown'}) async {
    if (_wsManager != null) {
      await _wsManager!.disconnect(source: source);
      _wsManager = null;
    }
    // v4.3.3：断开即作废旧会话的 vision 凭证——重连后由新的 MCP initialize 重新下发。
    // 否则存在"用旧会话 token 上传"的隐患（真机日志实证：重连后 session/vision token 均已变化）。
    _visionUrl = null;
    _visionToken = null;
  }

  /// 显示错误提示
  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 执行 OTA 认证获取 WebSocket 连接信息
  Future<bool> _performOtaAuthentication() async {
    try {
      setState(() {
        _connectionStatus = '正在认证...';
      });

      logger.info('开始 OTA 认证...');

      // 确保 OTA 服务已初始化
      if (_otaService == null) {
        logger.severe('OTA 服务未初始化');
        _showError('OTA 服务未初始化');
        return false;
      }

      // 调用 OTA API 获取 WebSocket 信息（v3.1.0：版本号统一取 AppConfig，随 pubspec 走）
      // v4.3.2 埋点：OTA 请求参数（appName 为红线冻结值，仅记录不改）
      logger.info('OTA 请求 appName=ajb_agent_flutter'
          ' appVersion=${AppConfig.appVersion} acceptLanguage=zh-CN');
      final otaResponse = await _otaService!.checkFlutterAppUpdates(
        appName: 'ajb_agent_flutter',
        appVersion: AppConfig.appVersion,
        acceptLanguage: 'zh-CN',
      );
      logger.info('OTA 响应：websocket=${otaResponse.websocket != null}'
          ' mqtt=${otaResponse.mqtt != null}'
          ' activation=${otaResponse.activation != null}');

      // 检查是否返回了 WebSocket 信息
      if (otaResponse.websocket != null) {
        if (otaResponse.activation != null) {
          final code = otaResponse.activation!.code;
          _appendOrCreateChatMessage(
            MessageSender.ai,
            '设备需要在平台端注册，注册码:[$code]，注册成功后需重新进入对话',
          );
          _showError('认证失败: 设备未注册');
          setState(() {
            _connectionStatus = '认证失败';
          });
          return false;
        }

        logger.info('OTA 认证成功');
        // v3.3.0：📡 MQTT 常驻——OTA 响应下发凭据即原生 TLS 8883 直连 broker
        //（后台显示在线 + 接收远程配置下发；🧭 开关默认关，开发者中心开启）
        if (AppFeats.mqtt && otaResponse.mqtt != null) {
          _startMqttPresence(otaResponse.mqtt!);
        }
        return true;
      } else {
        logger.warning('OTA 响应中没有 WebSocket 信息');
        _showError('认证失败: 服务器未返回连接信息');
        setState(() {
          _connectionStatus = '认证失败';
        });
        return false;
      }
    } on OtaException catch (e) {
      logger.severe('OTA 认证失败: ${e.message}');
      _showError('认证失败: ${e.message}');
      setState(() {
        _connectionStatus = '认证失败';
      });
      return false;
    } catch (e, stackTrace) {
      logger.severe('OTA 认证异常: $e\n$stackTrace');
      _showError('认证异常: $e');
      setState(() {
        _connectionStatus = '认证异常';
      });
      return false;
    }
  }

  /// 初始化 WebSocket 连接
  Future<void> _initializeWebSocket() async {
    if (_currentAgent == null) {
      logger.warning('当前智能体为空，无法初始化 WebSocket');
      return;
    }
    logger.info('WS 初始化开始 agentId=${widget.agentId}'
        ' url=${_currentAgent?.url}');

    try {
      // 第零步: 应用本智能体的独立设备身份（v1.1.5，避免多智能体串号；
      // 只调用 XiaozhiDeviceInfoUtil 公开 setter，不改 lib/core）
      final identity = await AgentIdentityStore.load(widget.agentId);
      if (identity != null) {
        // v4.3.0：存量型号矫正——独立身份里的手机型号/xiaole-voice-v1 旧值
        // 归一为 m5stack-core-s3 并写回存储（MAC/ClientID 不动，避免换身份需重新激活）
        final model = AgentIdentityStore.normalizeModel(identity['model']!);
        if (model != identity['model']) {
          await AgentIdentityStore.save(widget.agentId,
              mac: identity['mac']!,
              clientId: identity['clientId']!,
              model: model);
          logger.info(
              '已矫正智能体独立身份型号: ${identity['model']} -> $model');
        }
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceMacAddress(identity['mac']!);
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceClientId(identity['clientId']!);
        await XiaozhiDeviceInfoUtil.instance.setDeviceModel(model);
        logger.info('已应用智能体独立身份: ${identity['mac']}');
      } else {
        // v1.1.6: 旧智能体首次进入时，把当前全局身份快照绑定为它的专属身份，
        // 防止全局被其他智能体覆盖后拿错身份连接
        final mac = await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress();
        final cid = await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();
        // v4.3.0：快照绑定的型号同样归一（normalizeGlobalModel 已矫正全局，此处兜底）
        final model = AgentIdentityStore.normalizeModel(
            await XiaozhiDeviceInfoUtil.instance.getDeviceModel());
        await AgentIdentityStore.save(widget.agentId,
            mac: mac, clientId: cid, model: model);
        logger.info('已快照绑定旧智能体身份: $mac');
      }

      // 第一步: 执行 OTA 认证
      final authSuccess = await _performOtaAuthentication();
      if (!authSuccess) {
        logger.warning('OTA 认证失败,取消 WebSocket 连接');
        return;
      }

      // 第二步: 获取设备ID 与 ClientID（v1.1.6: 握手需上报真实 ClientID）
      final deviceId = await XiaozhiDeviceInfoUtil.instance
          .getDeviceMacAddress();
      final clientId = await XiaozhiDeviceInfoUtil.instance
          .getDeviceClientId();

      print(_currentAgent);
      // 第三步: 创建 WebSocket 管理器
      _wsManager = XiaozhiWebSocketManager(
        deviceId: deviceId,
        clientId: clientId,
        enableToken: false,
      );

      // 第四步: 添加事件监听器
      _wsManager!.addListener(_handleWebSocketEvent);

      // 第四步半 (v3.0.0)：MCP 设备端——应答服务器 initialize/tools/list/tools/call，
      // 注册 9 项工具让 AI 真实操控设备（协议对齐真机 mcp_server.cc，见 xiaoleweb.md 第五章）
      _setupMcpResponder();

      // 第五步: 使用Agent配置 wsUrl 和 wsToken 连接服务器
      await _connectToWebSocket(_currentAgent?.url ?? '', 'test-token');
    } catch (e) {
      logger.severe('初始化 WebSocket 失败: $e');
      _showError('连接初始化失败: $e');
    }
  }

  /// 使用指定的 URL 和 Token 连接 WebSocket
  Future<void> _connectToWebSocket(String url, String token) async {
    if (_wsManager == null) return;

    setState(() {
      _connectionStatus = '正在连接...';
    });

    try {
      logger.info('WS 连接开始 url=$url');
      await _wsManager!.connect(url, token);
      logger.info('WS 连接请求已发送（等待服务器 hello 握手）');
    } catch (e) {
      logger.severe('WebSocket 连接失败: $e');
      setState(() {
        _connectionStatus = '连接失败';
      });
      _showError('连接失败: $e');
    }
  }

  /// v3.0.0：创建 MCP 响应器并注册 P0 九项工具（执行器全部为本页真实实现）
  void _setupMcpResponder() {
    if (_wsManager == null) return;
    final responder = XiaozhiMcpResponder(
      send: (text) => _wsManager!.sendMessage(text),
      serverName: 'xiaole-app',
      serverVersion: '3.0.0',
    );

    void register(XiaozhiMcpTool tool,
        Future<Map<String, dynamic>> Function(Map<String, dynamic>) exec) {
      responder.registerTool(tool, exec);
    }

    // v6.1.0：设备能力服务（音量/闹钟/日历/系统 intent/TTS/剪贴板/亮度…）
    final caps = DeviceCapabilityService.instance;

    // 1. 设备状态（音量/主题/网络；v4.2.0 真实电量[申请书8号] + 结构化状态卡片[申请书7号]）
    register(XiaozhiMcpStandardTools.status, (_) async {
      final mode = ref.read(themeModeProvider);
      // 真实电量：Android/iOS 读系统电池；桌面端不可用时回退「已接通电源」虚拟值
      int level = 100;
      bool charging = true;
      try {
        level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        charging = state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {
        // 平台不支持（Windows/桌面）保持虚拟值
      }
      // v6.1.0：volume 改读**真实系统媒体音量**
      // （原先上报的是软件增益值，与用户实际听感不符 —— 这就是"显示 100% 实际只有一半"的由来）
      final sysVolume = await caps.getVolume();
      final status = {
        'volume': sysVolume ?? AudioUtil.ttsVolumePercent,
        'theme': mode == ThemeMode.dark ? 'dark' : 'light',
        'battery': {'level': level, 'charging': charging},
        'network': _isConnected ? 'online' : 'offline',
        'active_timers': _mcpTimers.length,
        'scheduled_events': _mcpEvents.length,
      };
      // v4.2.0：设备状态卡片——AI 查状态时本地同步渲染结构化卡片（申请书 7 号）
      _appendOrCreateChatMessage(
        MessageSender.system,
        '📊 设备状态',
        metadata: {'card': 'device_status', 'data': status},
      );
      return status;
    });

    // 2. 音量（v6.1.0：改为控制**系统媒体音量** —— 原先只改软件增益，
    //    受系统音量上限约束，导致"AI 说调到 100% 但实际只有一半响度"）
    register(XiaozhiMcpStandardTools.setVolume, (args) async {
      final v = (args['volume'] as num?)?.toInt() ?? -1;
      if (v < 0 || v > 100) {
        return {'success': false, 'message': 'volume must be 0-100'};
      }
      final r = await caps.setVolume(v);
      // 软件增益同步跟随：万一某些机型系统音量接口不可用，App 内增益仍能兜底
      AudioUtil.setTtsVolume(v);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '🔊 AI 已把系统音量调到 $v%');
      }
      return r;
    });

    // 3. 主题（真实切换深浅色）
    register(XiaozhiMcpStandardTools.setTheme, (args) async {
      final theme = args['theme'] as String?;
      if (theme != 'light' && theme != 'dark') {
        return {'success': false, 'message': 'theme must be light or dark'};
      }
      final notifier = ref.read(themeModeProvider.notifier);
      final before = ref.read(themeModeProvider) == ThemeMode.dark;
      if ((theme == 'dark') != before) {
        theme == 'dark'
            ? await notifier.setDarkMode()
            : await notifier.setLightMode();
      }
      _appendOrCreateChatMessage(
          MessageSender.system, '🎨 AI 已切换${theme == 'dark' ? '深色' : '浅色'}模式');
      return {
        'success': true,
        'theme': ref.read(themeModeProvider) == ThemeMode.dark ? 'dark' : 'light'
      };
    });

    // 4-6. 定时器（创建/列表/停止；到点 = 系统消息 + 震动 + Toast）
    register(XiaozhiMcpStandardTools.timerCreate, (args) async {
      final secs = (args['seconds'] as num?)?.toInt() ?? 0;
      if (secs <= 0) {
        return {'success': false, 'message': 'invalid seconds'};
      }
      final name = (args['event_name'] as String?) ??
          (secs >= 60 ? '倒计时 ${secs ~/ 60} 分钟' : '倒计时 $secs 秒');
      final id = DateTime.now().millisecondsSinceEpoch;
      final timer = Timer(Duration(seconds: secs), () {
        _mcpTimers.removeWhere((t) => t['id'] == id);
        _mcpFireReminder('⏰ $name · 时间到！');
      });
      _mcpTimers.add({'id': id, 'name': name, 'endAt': DateTime.now().add(Duration(seconds: secs)), 'timer': timer});
      _appendOrCreateChatMessage(
          MessageSender.system, '⏳ 已创建倒计时「$name」（$secs 秒）');
      return {'success': true, 'id': id, 'name': name, 'seconds': secs};
    });
    register(XiaozhiMcpStandardTools.timerList, (_) async {
      final now = DateTime.now();
      return {
        'tasks': _mcpTimers
            .map((t) => {
                  'id': t['id'],
                  'name': t['name'],
                  'remaining_seconds':
                      (t['endAt'] as DateTime).difference(now).inSeconds,
                })
            .toList()
      };
    });
    register(XiaozhiMcpStandardTools.timerStop, (args) async {
      final id = (args['id'] as num?)?.toInt();
      final hit = _mcpTimers.where((t) => t['id'] == id).toList();
      if (id == null || hit.isEmpty) {
        return {'success': false, 'message': 'timer not found'};
      }
      (hit.first['timer'] as Timer?)?.cancel();
      _mcpTimers.removeWhere((t) => t['id'] == id);
      _appendOrCreateChatMessage(
          MessageSender.system, '⏳ 倒计时「${hit.first['name']}」已停止');
      return {'success': true};
    });

    // 7-9. 日程（v6.1.0：create 改为写**系统日历** —— 原先用内存 Timer，App 退出/重启即失效，
    //      这就是"日程设了没用"的根因）
    register(XiaozhiMcpStandardTools.scheduleCreate, (args) async {
      final timeStr = args['time'] as String?;
      final name = (args['event_name'] as String?) ?? '日程';
      // 协议格式 YYYY-MM-DD HH:MM → DateTime.tryParse 可解析（空格分隔兼容）
      final tm = timeStr == null ? null : DateTime.tryParse(timeStr);
      if (tm == null) {
        return {'success': false, 'message': 'invalid time, use YYYY-MM-DD HH:MM'};
      }
      final r = await caps.createCalendarEvent(title: name, start: tm);
      if (r['success'] == true) {
        // 仅在 App 内留一条记录，便于 schedule.get_events 查询
        // （真正的提醒由系统日历 App 负责；此处不再创建内存 Timer）
        _mcpEvents.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'name': name,
          'time': timeStr,
          'timer': null,
        });
        _appendOrCreateChatMessage(
            MessageSender.system, '📅 已请求写入系统日历「$name」（$timeStr）——请在日历界面点「保存」');
      }
      return r;
    });
    register(XiaozhiMcpStandardTools.scheduleList, (_) async {
      return {
        'events':
            _mcpEvents.map((e) => {'id': e['id'], 'name': e['name'], 'time': e['time']}).toList()
      };
    });
    register(XiaozhiMcpStandardTools.scheduleDelete, (args) async {
      final id = (args['id'] as num?)?.toInt();
      final hit = _mcpEvents.where((e) => e['id'] == id).toList();
      if (id == null || hit.isEmpty) {
        return {'success': false, 'message': 'event not found'};
      }
      (hit.first['timer'] as Timer?)?.cancel();
      _mcpEvents.removeWhere((e) => e['id'] == id);
      return {'success': true};
    });

    // 10. AI 主动拍照识图（v3.2.0）：拉起相机 → 上传识图 → 描述回传 AI
    register(XiaozhiMcpStandardTools.takePhoto, (args) async {
      final q = (args['question'] as String?) ?? '这张图里有什么？';
      if (_visionUrl == null || _visionUrl!.isEmpty) {
        return {'success': false, 'message': 'camera/vision not ready'};
      }
      _appendOrCreateChatMessage(MessageSender.system, '📷 AI 请求拍照：$q');
      try {
        final xfile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1280,
          imageQuality: 85,
        );
        if (xfile == null) {
          return {'success': false, 'message': 'user cancelled camera'};
        }
        final up = await _uploadVision(xfile.path, q);
        // v4.3.5【方案一修正】：官方固件 Esp32Camera::Explain() 的全部实现就是
        //   `std::string result = http->ReadAll(); return result;`
        // —— 把 HTTP 响应体**原样**作为 MCP 工具结果返回，由**服务端 LLM** 依据其中的
        //    uuid/message（"Please call the tool image_to_text…"）自行完成描述获取。
        //    官方仓库全文件 `image_to_text` 出现 0 次 ⇒ **设备端不存在"第二段调用"**。
        //    旧实现错在此处也去发 tools/call（方向反了：tools/call 是服务器→设备），必然超时。
        // 现按官方做法回传响应体原文：旧协议下它本身就是描述；新协议下它是给 LLM 的提示。
        final desc = up['raw'] ?? up['message'] ?? up['value'] ?? '';
        logger.info('MCP take_photo 回传响应体原文 ${desc.length} 字符，交由服务端 LLM 处理'
            '（kind=${up['kind']}）');
        // 仅旧协议（响应体即描述）才回填 AI 气泡；新协议下这段是**给 LLM 的提示**，
        // 不能显示给用户（否则又变成"把 JSON 摆给用户看"），真正的描述由服务端 LLM 回复。
        if (up['kind'] == 'text') {
          _appendOrCreateChatMessage(MessageSender.ai, desc);
        }
        return {'success': true, 'question': q, 'description': desc};
      } catch (e) {
        return {'success': false, 'message': '$e'};
      }
    });

    // 11. AI 屏显图片（v3.2.0）：图片 URL 进 AI 消息（气泡用 CachedNetworkImage 渲染）
    register(XiaozhiMcpStandardTools.previewImage, (args) async {
      final url = args['url'] as String?;
      if (url == null || url.isEmpty) {
        return {'success': false, 'message': 'invalid url'};
      }
      final message = MessageModel(
        id: 'img_${DateTime.now().millisecondsSinceEpoch}',
        agentId: widget.agentId,
        type: MessageType.image,
        content: url,
        sender: MessageSender.ai,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(message);
      });
      ChatHistoryStore.save(widget.agentId, _messages);
      _scrollToBottom();
      return {'success': true};
    });

    // ==================== v6.1.0 新增 15 项能力 ====================
    // 方案：PLAN_v6.1.0_MCP设备工具能力扩展.md ｜ 能力实现：DeviceCapabilityService

    // ---------- 🅑 补齐官方标准（官方 mcp_server.cc 有、我们原先缺失）----------

    // 12. 屏幕亮度（应用级：不需要 WRITE_SETTINGS 特殊权限）
    register(XiaozhiMcpStandardTools.setBrightness, (args) async {
      final b = (args['brightness'] as num?)?.toInt() ?? -1;
      if (b < 1 || b > 100) {
        return {'success': false, 'message': 'brightness must be 1-100'};
      }
      final r = await caps.setBrightness(b);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '☀️ AI 已把屏幕亮度调到 $b%');
      }
      return r;
    });

    // 13. 屏幕信息（逻辑像素 + 物理像素，供 AI 适配布局）
    register(XiaozhiMcpStandardTools.getScreenInfo, (_) async {
      final size = MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return {
        'success': true,
        'width': size.width.round(),
        'height': size.height.round(),
        'device_pixel_ratio': dpr,
        'physical_width': (size.width * dpr).round(),
        'physical_height': (size.height * dpr).round(),
      };
    });

    // 14. 系统与设备信息
    register(XiaozhiMcpStandardTools.getSystemInfo, (_) async {
      final out = <String, dynamic>{
        'success': true,
        'app_version': AppConfig.appVersion,
        'platform': Platform.operatingSystem,
      };
      try {
        if (Platform.isAndroid) {
          final a = await DeviceInfoPlugin().androidInfo;
          out.addAll({
            'brand': a.brand,
            'model': a.model,
            'android_version': a.version.release,
            'sdk_int': a.version.sdkInt,
          });
        }
      } catch (e) {
        out['note'] = '部分设备信息不可用：$e';
      }
      return out;
    });

    // 15. 截屏（App 内截屏：走 RenderRepaintBoundary，**不需要 MediaProjection、无系统权限**）
    register(XiaozhiMcpStandardTools.snapshot, (_) async {
      try {
        final ro = _snapshotKey.currentContext?.findRenderObject();
        if (ro is! RenderRepaintBoundary) {
          return {'success': false, 'message': '当前界面不支持截屏'};
        }
        final img = await ro.toImage(pixelRatio: 1.5);
        try {
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) return {'success': false, 'message': '截屏编码失败'};
          final f = File('${Directory.systemTemp.path}/xl_snapshot_'
              '${DateTime.now().millisecondsSinceEpoch}.png');
          await f.writeAsBytes(bytes.buffer.asUint8List());
          return {'success': true, 'path': f.path, 'bytes': bytes.lengthInBytes};
        } finally {
          // v6.1.2：释放 ui.Image 占用的原生/GPU 内存
          // （独立验证发现：不 dispose 会导致**每次截屏泄漏一张图**）
          img.dispose();
        }
      } catch (e) {
        return {'success': false, 'message': '截屏失败：$e'};
      }
    });

    // 16. 重启会话（App 无真重启能力 → 映射为「重新连接 + 清空当前会话」）
    register(XiaozhiMcpStandardTools.reboot, (_) async {
      _appendOrCreateChatMessage(
          MessageSender.system, '🔄 AI 请求重启会话，正在重新连接…');
      try {
        _ensureConnectedThen(() {}, '重启会话');
        return {
          'success': true,
          'message': '已触发重新连接并重置当前会话状态（不会重启手机）',
        };
      } catch (e) {
        return {'success': false, 'message': '重连失败：$e'};
      }
    });

    // ---------- 🅒 Android 系统能力（全部免危险权限）----------

    // 17. 拨号（ACTION_DIAL：只打开拨号盘预填，不直接拨出）
    register(XiaozhiMcpStandardTools.dial, (args) async {
      final r = await caps.dial(args['number'] as String? ?? '');
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '📞 已打开拨号盘：${r['number']}');
      }
      return r;
    });

    // 18. 短信（ACTION_SENDTO：预填号码与内容，用户点发送）
    register(XiaozhiMcpStandardTools.sendSms, (args) async {
      final r = await caps.sendSms(
        number: args['number'] as String? ?? '',
        body: args['body'] as String? ?? '',
      );
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '💬 已打开短信界面（发给 ${r['number']}）');
      }
      return r;
    });

    // 19. 地图导航
    register(XiaozhiMcpStandardTools.navigate, (args) async {
      final r = await caps.navigate(args['destination'] as String? ?? '');
      if (r['success'] == true) {
        _appendOrCreateChatMessage(
            MessageSender.system, '🗺 已打开地图导航：${r['destination']}');
      }
      return r;
    });

    // 20. 打开系统设置页
    register(XiaozhiMcpStandardTools.openSettings,
        (args) async => caps.openSettings(args['page'] as String? ?? ''));

    // 21. 打开网页
    register(XiaozhiMcpStandardTools.openUrl,
        (args) async => caps.openUrl(args['url'] as String? ?? ''));

    // ---------- 🅐 系统闹钟 / 轻提示 / 分享 ----------

    // 22. 系统闹钟（**真·系统时钟闹钟**：App 关闭、手机重启后依然会响）
    register(XiaozhiMcpStandardTools.setAlarm, (args) async {
      final h = (args['hour'] as num?)?.toInt() ?? -1;
      final m = (args['minute'] as num?)?.toInt() ?? -1;
      if (h < 0 || m < 0) {
        return {'success': false, 'message': 'hour/minute are required'};
      }
      List<int>? days;
      final raw = args['weekdays'];
      if (raw is List) {
        days = raw.whereType<num>().map((e) => e.toInt()).toList();
      }
      final r = await caps.setAlarm(
          hour: h, minute: m, label: args['label'] as String?, weekdays: days);
      if (r['success'] == true) {
        _appendOrCreateChatMessage(MessageSender.system,
            '⏰ 已请求系统闹钟 ${r['time']}（请在时钟界面点「保存」）');
      }
      return r;
    });

    // 23. 轻提示（AI 主动弹，不打断对话）
    register(XiaozhiMcpStandardTools.showToast, (args) async {
      final t = args['text'] as String? ?? '';
      if (t.trim().isEmpty) return {'success': false, 'message': 'text required'};
      caps.showToast(t);
      return {'success': true};
    });

    // 24. 分享文本到笔记/备忘录/微信等
    register(XiaozhiMcpStandardTools.shareText, (args) async {
      return caps.shareText(
        args['text'] as String? ?? '',
        subject: args['subject'] as String?,
      );
    });

    // ---------- 🅓 剪贴板 ----------

    // 25. 读剪贴板
    register(XiaozhiMcpStandardTools.clipboardGet, (_) async {
      final t = await caps.getClipboard();
      return {'success': t != null, 'text': t ?? ''};
    });

    // 26. 写剪贴板
    register(XiaozhiMcpStandardTools.clipboardSet, (args) async {
      return caps.setClipboard(args['text'] as String? ?? '');
    });

    _mcpResponder = responder;
    logger.info('MCP 设备端就绪：注册 ${responder.toolCount} 项工具');
  }

  /// MCP 提醒触发（定时器/日程共用）：聊天系统消息 + 震动 + Toast
  void _mcpFireReminder(String text) {
    _appendOrCreateChatMessage(MessageSender.system, text);
    ToastUtil.show(text);
    Vibration.vibrate(pattern: [0, 300, 150, 300]).catchError((_) {});
    logger.info('MCP 提醒: $text');
  }

  /// v3.1.0：周期性设备状态上报（WS 连接即报 + 每 10 分钟，见 xiaoleweb.md §2.3）
  void _startOtaReporting() {
    _stopOtaReporting();
    _otaService?.reportStatus(
        appName: 'ajb_agent_flutter', appVersion: AppConfig.appVersion);
    _otaReportTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _otaService?.reportStatus(
          appName: 'ajb_agent_flutter', appVersion: AppConfig.appVersion);
    });
  }

  void _stopOtaReporting() {
    _otaReportTimer?.cancel();
    _otaReportTimer = null;
  }

  /// v3.3.0：启动 MQTT 常驻在线（凭据来自 OTA 响应；订阅设备下行主题，
  /// 后台下发的 MCP/远程配置转现有响应器——远程主题/音色自定义随之解锁）
  Future<void> _startMqttPresence(MqttInfo mqtt) async {
    if (_mqttPresence != null) return;
    final mac = (await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress())
        .toLowerCase(); // 铁律：MAC 全小写
    final presence = XiaozhiMqttPresence(
      endpoint: mqtt.endpoint,
      clientId: mqtt.clientId,
      username: mqtt.username,
      password: mqtt.password,
      mac: mac,
      onMessage: (msg) {
        final type = msg['type'] as String?;
        if (type == 'mcp' && _mcpResponder != null && AppFeats.mcptools) {
          final payload = msg['payload'];
          if (payload is Map) {
            _mcpResponder!
                .handlePayload(Map<String, dynamic>.from(payload));
          }
        } else if (type == 'goodbye') {
          logger.info('MQTT 下发 goodbye（正常保活交互）');
        }
      },
    );
    presence.start();
    _mqttPresence = presence;
    logger.info('📡 MQTT 常驻启动（endpoint=${mqtt.endpoint}）');
  }

  /// 识图两段式第二步：拿到 `uuid` 后向服务器索要图片描述。
  ///
  /// ⚠️ 现状（v4.3.4 定格，2026-09-11 真机结论）：**此步骤在官方服务器上无可用协议，功能暂缓**。
  /// 调用链路（A/C 两路）与日志埋点全部保留，等日后拿到官方教程或服务器修复后再继续开发。
  ///
  /// 【已确认的事实】（完整证据见仓库根 `故障报告_识图image_to_text无响应_2026-09-11.md`）
  ///   1. 上传链路完全正常：POST `capabilities.vision.url` → HTTP 200 + `{success, uuid, message}`；
  ///   2. 服务器返回的 message（"Please call the tool `image_to_text` ... then reply to the user"）
  ///      措辞是**给 LLM 的指令**（只有 LLM 才能 "reply to the user"），设备无法执行；
  ///   3. 设备发 `tools/call image_to_text{uuid}`（路径 A）→ 服务器 **30 秒零响应**（无 result 也 error）；
  ///   4. 设备把 message 当文本请求发（原路径 B，`listen/detect`）→ 服务器**明确拒绝**：
  ///      `{"type":"alert","status":"ERROR","message":"Detect is only for wake words, do not send long texts."}`
  ///      （官方服务器对 detect 只接受唤醒词短语，长文本一律拒绝——第三方开发者亦有公开记录）
  ///      → **v4.3.4 已移除路径 B**（无效，且每次都会触发服务器 ERROR）；
  ///   5. 全网检索无该协议的正确实现（第三方客户端只能用第三方视觉 API 绕过，或改打自建服务器）；
  ///   6. 服务器对**非法**请求会明确报错，却对路径 A **完全静默** → A 不是服务器认识的用法。
  ///
  /// 【判定】疑似**服务端该功能未完成**：把"给 LLM 的 tool-call 提示"当作 HTTP 响应体返回了，
  /// 真正的描述生成从未发生。客户端无法通过公开协议完成，故暂缓。
  ///
  /// 【日后如何继续】
  ///   - 拿到官方教程/抓包对比：按新协议改写下方发送体即可（埋点已齐备，日志分类默认开
  ///     `vision`/`ws`/`mcp`，一次复现就能看清全部往返）；
  ///   - 服务器修复：本方法**无需改动**，路径 A 的应答会经 `_pendingMcpCalls` 自动命中；
  ///   - 改用自建 xiaozhi-esp32-server：其识图链路完整，本方法同样可直接复用。
  ///
  /// 保留两路（谁先出结果用谁）：
  ///   [A] 发 tools/call image_to_text{uuid} → 由 _pendingMcpCalls 捕获 mcp 应答
  ///   [C] 纯等待服务器主动推送（tts/llm 文本）→ 由 _visionAux 捕获
  Future<String> _callImageToText(String uuid) async {
    // v4.3.2：切到相机 Activity 期间 WS 很可能已被系统回收/服务端断开，
    // 此处先重新校验连接状态，断了就先重连再发，避免"连接已死却按在线发"。
    if (_wsManager == null || !_isConnected) {
      logger.warning('image_to_text 前置检查未通过：'
          'wsManager=${_wsManager != null} isConnected=$_isConnected，先尝试重连');
      final ok = await _ensureConnectedForVision();
      if (!ok) throw '连接已断开且自动重连失败，请稍后重试';
    }
    final id = ++_mcpCallId;
    final c = Completer<String>();
    _pendingMcpCalls[id] = c;
    _visionAux = Completer<String>();

    // ---------- 路径 A：tools/call image_to_text ----------
    final reqA = jsonEncode({
      'type': 'mcp',
      'payload': {
        'jsonrpc': '2.0',
        'id': id,
        'method': 'tools/call',
        'params': {
          'name': 'image_to_text',
          'arguments': {'uuid': uuid},
        },
      },
    });
    _wsManager!.sendMessage(reqA);
    logger.info('[A] 识图：已发起 tools/call image_to_text id=$id uuid=$uuid');

    // 注：v4.3.4 已移除原「路径 B」（把服务器 message 当 listen/detect 文本请求发送）——
    // 真机证实官方服务器一律拒绝长文本（alert: "Detect is only for wake words..."），
    // 且每次都会触发服务器 ERROR 报警，故不再发送。详见方法头注释。

    // ---------- 路径 C：纯等待服务器主动推送 ----------
    logger.info('[C] 识图：开始监听服务器主动推送（tts/llm 文本）');

    try {
      // 三路竞速：A/B → mcp 应答（c）；C → 服务器主动推送（_visionAux）
      final text = await Future.any<String>([
        c.future,
        _visionAux!.future,
      ]).timeout(const Duration(seconds: 30));
      logger.info('识图结果到达（${text.length} 字符）');
      return text;
    } on TimeoutException {
      final silent = _wsManager?.silentSeconds;
      logger.warning('识图三路均无结果（30s）id=$id uuid=$uuid'
          ' isConnected=$_isConnected silentSeconds=$silent');
      throw '图片已上传成功，但服务器未返回识别结果（可能服务端未就绪）。已记录日志，请复制日志反馈';
    } finally {
      _pendingMcpCalls.remove(id);
      _visionAux = null;
    }
  }

  /// v4.3.2：识图前的按需重连（复用「想打就打」的待办执行链路）。
  /// 返回 true = 已连接可继续；false = 20s 内没连上。
  /// v4.3.3：[force]=true 时**无视 isConnected 标志**，先断开旧连接再重建——
  /// 相机是独立 Activity，期间连接可能已被回收而标志位仍是陈旧的 true，
  /// 这时只有"重建"才可信（见 v4.3.2 真机日志：isConnected=true 却收不到应答）。
  Future<bool> _ensureConnectedForVision({bool force = false}) async {
    if (!force && _wsManager != null && _isConnected) return true;
    if (force) {
      await _cleanupWebSocket(source: 'vision_refresh');
    }
    final c = Completer<bool>();
    _ensureConnectedThen(() {
      if (!c.isCompleted) c.complete(true);
    }, '识图');
    try {
      return await c.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
    } finally {
      if (!c.isCompleted) c.complete(false);
    }
  }

  /// v3.1.0：视觉识物（拍照问 AI，见 xiaoleweb.md §7）
  /// 链路：image_picker 拍照 → multipart POST vision 接口（headers 带
  /// Device-Id/Client-Id/Authorization；上游为 http://，Manifest 已开 cleartext）
  /// → v4.3.1 两段式：旧协议{text}直显 / 新协议{uuid}发 image_to_text 拿描述。
  Future<void> _takePhotoAndAsk() async {
    // v4.3.2 埋点：点击即记录全部前置状态，一眼看出卡在哪道闸
    logger.info('📷 点击拍照识物：visionUrl=${_visionUrl == null ? "null" : "已获取"}'
        ' isConnected=$_isConnected'
        ' featVision=${AppFeats.vision} featMcptools=${AppFeats.mcptools}');
    if (_visionUrl == null || _visionUrl!.isEmpty) {
      logger.warning('识图中止：visionUrl 为空（未拿到服务器 MCP initialize 的'
          ' capabilities.vision，或 🧰 MCP 开关关闭导致 initialize 未处理）');
      ToastUtil.show('尚未获取视觉接口——先连接一次即可');
      return;
    }
    if (!_isConnected) {
      _ensureConnectedThen(_doTakePhotoAndAsk, '识图');
      return;
    }
    await _doTakePhotoAndAsk();
  }

  Future<void> _doTakePhotoAndAsk() async {
    if (_visionUrl == null || _visionUrl!.isEmpty) {
      logger.warning('识图中止（doTake）：visionUrl 为空');
      ToastUtil.show('尚未获取视觉接口——先连接一次即可');
      return;
    }
    try {
      final picker = ImagePicker();
      logger.info('识图：拉起系统相机');
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (xfile == null) {
        // v4.3.2：此前这里静默 return（用户以为"没反应"），补埋点便于区分
        logger.warning('识图中止：相机未返回图片（用户取消 / 权限被拒 / 相机异常）');
        return;
      }
      logger.info('识图：相机返回图片 path=${xfile.path}');

      // v4.3.3：相机是独立 Activity，拍照期间 App 进后台，连接很可能已被回收，
      // 而 _isConnected 会停留在陈旧值（v4.3.2 真机日志实证：isConnected=true 却收不到应答）。
      // 因此这里用"静默时长"（距上次收到服务器消息的秒数）判断连接是否可信，
      // 不可信则**强制重建**，并等新的 initialize 重新下发 vision url/token 后再上传。
      final silent = _wsManager?.silentSeconds;
      final needReconnect = _wsManager == null ||
          !_isConnected ||
          silent == null ||
          silent > 25;
      logger.info('识图：拍照返回连接体检 isConnected=$_isConnected'
          ' silentSeconds=$silent 需重建=$needReconnect');
      if (needReconnect) {
        final ok = await _ensureConnectedForVision(force: true);
        if (!ok) throw '连接已断开且自动重连失败，请稍后重试';
        // 等新的 MCP initialize 把 vision url/token 重新下发（最多 5 秒）
        for (var i = 0; i < 50 && (_visionUrl == null || _visionUrl!.isEmpty); i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        logger.info('识图：重连后 visionUrl=${_visionUrl == null ? "null（未下发）" : "已就绪"}'
            ' tokenLen=${(_visionToken ?? '').length}');
      }

      // v4.3.2：占位气泡带固定 id，成功/失败/超时都要落到终态（更新或替换），
      // 杜绝"📷 拍照识物中…"之后没有后话。
      final placeholderId = 'vision_${DateTime.now().millisecondsSinceEpoch}';
      _appendSystemMessage('📷 拍照识物中…', id: placeholderId);
      try {
        final up = await _uploadVision(xfile.path, '这张图里有什么？');
        final desc = up['kind'] == 'uuid'
            ? await _callImageToText(up['value']!)
            : (up['value'] ?? '识图结果为空');
        _finishVisionBubble(placeholderId, MessageSender.ai, desc);
        logger.info('视觉识物成功（${desc.length} 字符）');
      } catch (e, st) {
        logger.severe('视觉识物失败: $e\n${_shortStack(st)}');
        _finishVisionBubble(placeholderId, MessageSender.system, '⚠️ $e');
      }
    } catch (e, st) {
      // v4.3.1：任何失败只显示友好中文，绝不把原始 JSON/响应体抛给用户
      logger.severe('拍照阶段异常: $e\n${_shortStack(st)}');
      _appendOrCreateChatMessage(MessageSender.system, '⚠️ $e');
    }
  }

  /// v4.3.2：追加一条带指定 id 的 system 消息（识物占位气泡用）
  void _appendSystemMessage(String content, {required String id}) {
    final message = MessageModel(
      id: id,
      agentId: widget.agentId,
      type: MessageType.system,
      content: content,
      sender: MessageSender.system,
      status: MessageStatus.sent,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(message);
    });
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// v4.3.2：把识物占位气泡替换为终态内容（成功=AI 描述，失败=⚠️ 中文提示）。
  /// 占位气泡若已不存在（页面重建等），则退化为追加一条新消息，保证一定有终态。
  void _finishVisionBubble(
      String placeholderId, MessageSender sender, String content) {
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m.id == placeholderId);
    setState(() {
      if (idx >= 0) {
        final old = _messages[idx];
        _messages[idx] = MessageModel(
          id: old.id,
          agentId: old.agentId,
          type: sender == MessageSender.system
              ? MessageType.system
              : MessageType.text,
          content: content,
          sender: sender,
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
        );
      } else {
        _messages.add(MessageModel(
          id: 'vision_${DateTime.now().millisecondsSinceEpoch}',
          agentId: widget.agentId,
          type: sender == MessageSender.system
              ? MessageType.system
              : MessageType.text,
          content: content,
          sender: sender,
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
        ));
      }
    });
    ChatHistoryStore.save(widget.agentId, _messages);
    _scrollToBottom();
  }

  /// v4.3.2：日志正文/响应体截断（超出标注被截字符数，避免刷爆缓冲）
  static String _clip(String s, [int max = 500]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...[+${s.length - max} chars]';
  }

  /// v4.3.2：堆栈只取前 6 行进日志
  static String _shortStack(StackTrace st) =>
      st.toString().split('\n').take(6).join(' | ');

  /// v3.2.0：识图上传共享逻辑（手动 📷 与 MCP take_photo 共用）。
  /// v4.3.1：返回结构化结果——
  ///   {'kind':'text','value':描述}  旧协议（服务器同步返回描述，直显）
  ///   {'kind':'uuid','value':uuid}  新协议两段式（调用方再发 image_to_text）
  ///   {'kind':'raw','value':原文}   未知形态兜底
  /// 失败抛异常（HTTP 只报状态码，响应体进日志不进 UI）。
  Future<Map<String, String>> _uploadVision(String filePath, String question) async {
    final mac =
        (await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress())
            .toLowerCase(); // 铁律：MAC 全小写
    final clientId = await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();

    final req = http.MultipartRequest('POST', Uri.parse(_visionUrl!))
      ..fields['question'] = question
      ..files.add(await http.MultipartFile.fromPath('file', filePath,
          filename: 'camera.jpg'));
    req.headers['Device-Id'] = mac;
    if (clientId.isNotEmpty) {
      req.headers['Client-Id'] = clientId;
    }
    if ((_visionToken ?? '').isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${_visionToken}';
    }

    final sw = Stopwatch()..start();
    logger.info('识图上传开始 url=$_visionUrl question=$question file=$filePath'
        ' deviceId=$mac clientId=$clientId');
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    sw.stop();
    logger.info('识图上传完成 HTTP ${streamed.statusCode}'
        ' 耗时 ${sw.elapsedMilliseconds}ms 响应体=${_clip(body)}');
    if (streamed.statusCode != 200) {
      logger.severe('识图上传 HTTP ${streamed.statusCode}: $body');
      throw '识图上传失败（HTTP ${streamed.statusCode}），请稍后重试';
    }
    String kind = 'raw', value = body, serverMsg = '';
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        // v4.3.3：提取服务器返回的 message（新协议里它是"如何取到描述"的提示文本）
        if (j['message'] is String) serverMsg = (j['message'] as String).trim();
        if (j['text'] is String && (j['text'] as String).isNotEmpty) {
          kind = 'text'; // 旧协议：{"success":true,"text":"<描述>"}
          value = j['text'] as String;
        } else if (j['uuid'] is String && (j['uuid'] as String).isNotEmpty) {
          kind = 'uuid'; // 新协议两段式：{"success":true,"uuid":"..."}
          value = j['uuid'] as String;
        }
      }
    } catch (e) {
      // v4.3.2：此处原本静默吞掉解析异常 → 退化成 kind='raw'，
      // 会把响应体原文（JSON）直接显示给用户。补日志以便定位。
      logger.warning('识图上传响应不是合法 JSON，按原文兜底：${_clip(body)}');
    }
    logger.info('识图上传解析结果 kind=$kind valueLen=${value.length}'
        ' serverMessage=${serverMsg.isEmpty ? "(无)" : serverMsg}');
    // v4.3.5：额外回传响应体原文（raw）。官方固件 Esp32Camera::Explain() 的做法就是把它**原样**
    // 作为工具结果返回给服务端 LLM（见 视觉方案修复.md 第一节），故 MCP 场景需要用到它。
    return {'kind': kind, 'value': value, 'message': serverMsg, 'raw': body};
  }

  /// 处理 WebSocket 事件
  void _handleWebSocketEvent(XiaozhiEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case XiaozhiEventType.connected:
        setState(() {
          _isConnected = true;
          _connectionStatus = '已连接';
        });
        logger.info('WebSocket 已连接');
        // v3.1.0：连接即开始周期性设备状态上报（后台「最近活跃」对齐）
        _startOtaReporting();
        //_addConnectionStatusMessage('已连接到服务器');
        break;

      case XiaozhiEventType.disconnected:
        setState(() {
          _isConnected = false;
          // v1.1.6: 显示服务器关闭码，便于真机诊断失联原因
          final codeInfo = event.data?.toString();
          _connectionStatus = (codeInfo != null && codeInfo.isNotEmpty)
              ? '已断开 ($codeInfo)'
              : '已断开';
        });
        // v4.3.2 埋点：断开原因（close code）进日志
        logger.warning('WebSocket 已断开 closeCode=${event.data}');
        // v3.1.0：断线停止周期上报（重连成功后自动恢复）
        _stopOtaReporting();
        //_addConnectionStatusMessage('与服务器断开连接');
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        _handleBinaryMessage(event.data as List<int>);
        break;

      case XiaozhiEventType.error:
        logger.severe('WebSocket 错误: ${event.data}');
        _showError('连接错误: ${event.data}');
        break;
    }
  }

  /// 处理二进制消息（音频数据）
  void _handleBinaryMessage(List<int> data) {
    //logger.info('收到音频数据: ${data.length} 字节');
    
    // 标记 AI 开始播放
    if (!_isAiPlaying) {
      setState(() {
        _isAiPlaying = true;
      });
      logger.info('AI 开始播放音频，暂停发送麦克风数据');
    }

    // 收到音频即代表 AI 已响应，隐藏输入指示器
    _setTyping(false);
    
    // 重置定时器，如果一段时间没有收到新的音频数据，则认为播放结束
    _aiPlayingTimer?.cancel();
    _aiPlayingTimer = Timer(const Duration(milliseconds: 500), () {
      // 500ms 没有收到新的音频数据，认为播放结束
      if (_isAiPlaying) {
        setState(() {
          _isAiPlaying = false;
        });
        // v4.4.0：进入尾音保护（根因①——此时扬声器可能还在播最后几个字）
        _enterTailGuard();
        logger.info('AI 播放结束（500ms 无新音频），进入尾音保护');
      }
    });
    
    // 播放音频
    AudioUtil.playOpusData(Uint8List.fromList(data));
  }

  /// 处理文本消息
  void _handleTextMessage(String message) {
    try {
      // 解析 JSON 消息
      final jsonData = Map<String, dynamic>.from(
        const JsonDecoder().convert(message),
      );

      final type = jsonData['type'] as String?;

      switch (type) {
        case 'tts':
          // 处理 TTS 消息
          final state = jsonData['state'] as String?;
          final text = jsonData['text'] as String?;

          if (state == 'sentence_start' && text != null && text.isNotEmpty) {
            // AI 开始说新的一句话，追加到当前消息
            _setTyping(false);
            // v3.1.0：MCP 工具标记过滤 + 待挂情绪 emoji（对齐网页版，xiaoleweb.md §2.4）
            final filtered = _stripMcpMarkers(text);
            if (filtered.isEmpty) {
              logger.info('句子仅含 MCP 标记，气泡不渲染: $text');
            } else if (_visionAux != null && !_visionAux!.isCompleted) {
              // v4.3.3 路径 C：识图等待中——服务器主动推送的文本即认作识图结果，
              // 交给竞速逻辑处理（终态气泡会展示它，故此处不重复追加气泡）
              logger.info('[C] 识图：服务器主动推送文本作为识图结果 ${_clip(filtered)}');
              _visionAux!.complete(filtered);
            } else {
              final decorated =
                  _pendingEmotion.isEmpty ? filtered : '${_pendingEmotion} $filtered';
              _pendingEmotion = '';
              _appendOrCreateChatMessage(MessageSender.ai, decorated);
            }
          } else if (state == 'end' || state == 'stop') {
            // AI 说完了，标记播放结束
            // v3.0.0：双兼容——网页版实测服务器发的是 'stop'（部分上游发 'end'），
            // 只认其一会导致 _isAiPlaying 不复位 → 麦克风停发 → 「第二句听不见」
            _aiPlayingTimer?.cancel();
            if (_isAiPlaying) {
              setState(() {
                _isAiPlaying = false;
              });
              // v4.4.0：进入尾音保护（同上）
              _enterTailGuard();
              logger.info('TTS 结束($state)，AI 播放完成，进入尾音保护');
            }
          }
          break;

        case 'stt':
          // 处理语音识别结果 - 实时追加到最后一条用户消息
          final text = jsonData['text'] as String?;
          if (text != null && text.isNotEmpty) {
            logger.info('语音识别: $text');
            _appendOrCreateChatMessage(MessageSender.user, text);
            _scrollToBottom();
          }
          break;

        case 'hello':
          // 🔥 服务器 hello 响应，提取 session_id
          final sessionId = jsonData['session_id'] as String?;
          if (sessionId != null && sessionId.isNotEmpty) {
            _sessionId = sessionId;
            logger.info('收到服务器 hello 响应，会话ID: $_sessionId');
          } else {
            logger.info('收到服务器 hello 响应（无 session_id）');
          }
          // v3.1.0：hello ACK → 执行「想打就打」的待办动作
          _runPendingAutoAction();
          break;

        case 'llm':
          // v3.1.0：AI 情绪 → emoji 前缀（对齐网页版映射，xiaoleweb.md §2.4）
          // v4.2.0：同时触发全屏动图表情（申请书 6 号）
          final emotion = jsonData['emotion'] as String?;
          final em = {
            'happy': '😊',
            'laughing': '😆',
            'cool': '😎',
            'sad': '😢',
            'angry': '😠',
          }[emotion];
          if (em != null) {
            _showEmotionAnimation(em, emotion!);
            final last = _messages.isNotEmpty ? _messages.last : null;
            if (last != null &&
                last.sender == MessageSender.ai &&
                !last.content.startsWith(RegExp(r'[😊😆😎😢😠]'))) {
              setState(() {
                _messages[_messages.length - 1] = MessageModel(
                  id: last.id,
                  agentId: last.agentId,
                  type: last.type,
                  content: '$em ${last.content}',
                  sender: last.sender,
                  status: last.status,
                  timestamp: last.timestamp,
                );
              });
              ChatHistoryStore.save(widget.agentId, _messages);
            } else if (last == null || last.sender != MessageSender.ai) {
              // 情绪先于句子到达：暂存，随下一句 sentence_start 挂上
              _pendingEmotion = em;
            }
          }
          break;

        case 'mcp':
          // v3.0.0：MCP 设备端——响应服务器 initialize/tools/list/tools/call
          //（协议与工具效果见 xiaoleweb.md 第五章；hello 已声明 features.mcp）
          // v4.3.1：识图两段式——本设备主动发起的 tools/call 应答（带 id+result/error）
          // 必须最先拦截且不受 🧰 开关控制（识图与 mcptools 开关无关）。
          final mcpPayload = jsonData['payload'];
          // v4.3.2 埋点：mcp 帧全量摘要（含非应答帧），用于判断服务器到底回了什么
          logger.info('收到 mcp 帧：${_clip(jsonEncode(mcpPayload ?? {}))}');
          if (mcpPayload is Map) {
            final payloadMap = Map<String, dynamic>.from(mcpPayload);
            final rid = payloadMap['id'];
            final isCallAnswer = rid != null &&
                (payloadMap['result'] != null || payloadMap['error'] != null);
            if (isCallAnswer) {
              // v4.3.2 埋点：应答 id 与待决表比对，定位"超时/无反应"到底卡在哪
              logger.info('mcp 应答帧 id=$rid(${rid.runtimeType})'
                  ' 待决表=${_pendingMcpCalls.keys.toList()}');
              final pending = rid is int
                  ? _pendingMcpCalls.remove(rid)
                  : (rid is String
                      ? _pendingMcpCalls.remove(int.tryParse(rid))
                      : null);
              if (pending != null && !pending.isCompleted) {
                final result = payloadMap['result'];
                if (result is Map) {
                  String text = '';
                  final content = result['content'];
                  if (content is List && content.isNotEmpty) {
                    final first = content.first;
                    if (first is Map && first['text'] is String) {
                      text = first['text'] as String;
                    }
                  }
                  logger.info('mcp 应答 id=$rid 解析出描述 ${text.length} 字符');
                  pending.complete(
                      text.isEmpty ? '（服务器未返回图片描述）' : text);
                } else {
                  final err = payloadMap['error'];
                  final errMsg = err is Map
                      ? ((err['message'] as String?) ?? '未知错误')
                      : '未知错误';
                  logger.warning('mcp 应答 id=$rid 返回错误：$errMsg');
                  pending.completeError('识图失败：$errMsg');
                }
              } else {
                logger.warning('mcp 应答 id=$rid 未匹配任何待决调用'
                    '（待决表=${_pendingMcpCalls.keys.toList()}）');
              }
              break;
            }
            // v3.3.0：🧰 开关关 = 不应答服务器 MCP 请求（回到静默行为）
            if (!AppFeats.mcptools) {
              logger.info('MCP 请求被 🧰 开关忽略（开发者中心可开启）');
              break;
            }
            if (_mcpResponder != null) {
              // v3.1.0：从服务器 initialize 的 params.capabilities.vision 提取视觉识物接口
              if (payloadMap['method'] == 'initialize') {
                final params =
                    (payloadMap['params'] as Map?)?.cast<String, dynamic>() ?? {};
                final caps =
                    (params['capabilities'] as Map?)?.cast<String, dynamic>() ?? {};
                final vision = (caps['vision'] as Map?)?.cast<String, dynamic>();
                if (vision != null && vision['url'] != null) {
                  _visionUrl = vision['url'] as String?;
                  _visionToken = (vision['token'] as String?) ?? '';
                  logger.info('已获取视觉识物接口: $_visionUrl');
                } else {
                  // v4.3.2 埋点：服务器 initialize 没带 vision → 识物必然不可用
                  logger.warning(
                      '收到 MCP initialize，但 capabilities.vision 为空'
                      '（caps=${caps.keys.toList()}）——视觉识物不可用');
                }
              }
              _mcpResponder!.handlePayload(payloadMap);
            } else {
              logger.warning(
                  '收到 MCP 请求但响应器未就绪，已忽略（本条 AI 无法操控设备）');
            }
          }
          break;

        default:
          logger.warning('未知消息类型: $type , 内容: $message');
      }
    } catch (e) {
      logger.severe('解析消息失败: $e');
    }
  }

  /// 处理音频数据发送（发送二进制音频数据）
  void _handleAudioSend(Uint8List audioData) {
    // 如果 AI 正在播放，则不发送音频数据（但录音继续）
    if (_isAiPlaying) {
      // logger.info('AI 正在播放，跳过发送音频数据'); // 注释掉，避免日志过多
      return;
    }

    // v4.4.0 尾音保护：AI 刚说完时，扬声器缓冲区里可能还在播最后几个字，
    // 此时上行的音频实为 AI 自己的尾音 → 会被服务器 ASR 当成"用户开口"导致自问自答。
    // 故保护期内丢弃音频，等扬声器余音衰减完毕。
    final guard = _resumeGuardUntil;
    if (guard != null) {
      if (DateTime.now().isBefore(guard)) return;
      _resumeGuardUntil = null;
      logger.info('[audio] 尾音保护结束，恢复上行麦克风数据');
    }

    // 通过 WebSocket 发送音频数据
    if (_wsManager != null && _isConnected) {
      try {
        _wsManager!.sendBinaryMessage(audioData);
        // logger.info('已发送音频数据: ${audioData.length} 字节'); // 注释掉，避免日志过多
      } catch (e) {
        logger.severe('发送音频失败: $e');
        _showError('发送音频失败: $e');
      }
    } else {
      // v3.1.0：想打就打——触发自动连接（连上后继续说话即正常上行）。
      // 通话中由 WS 管理器自身重连兜底，不走全链路重建（避免双连接）。
      if (!_isInVoiceCall && _connectionStatus != '正在连接...') {
        _ensureConnectedThen(() {}, '发送语音');
      }
    }
  }

  /// 处理音频停止（发送 listen stop 消息）
  void _handleAudioStop() {
    // v3.0.0：防 mode 交叉（xiaoleweb.md §2.4 铁律）——realtime 通话进行中
    // 不允许按键说话链路（auto）插入 start/stop，否则服务器 VAD 语义错乱
    if (_isInVoiceCall) {
      logger.info('通话进行中，忽略按键说话的 listen stop（防 mode 交叉）');
      return;
    }
    if (_wsManager == null || !_isConnected) {
      return;
    }

    try {
      // 🔥 发送 listen stop 消息（按照协议）
      final listenStopMessage = {
        "session_id": _sessionId ?? "", // 使用从 hello 消息中获取的 session_id
        "type": "listen",
        "mode": "auto",
        "state": "stop",
      };

      _wsManager!.sendMessage(jsonEncode(listenStopMessage));
      logger.info('已发送 listen stop 消息: ${jsonEncode(listenStopMessage)}');
    } catch (e) {
      logger.severe('发送 listen stop 消息失败: $e');
    }
  }

  /// 处理音频开始（发送 listen start 消息）
  void _handleAudioStart() {
    // v3.0.0：防 mode 交叉（同 _handleAudioStop 注释）
    if (_isInVoiceCall) {
      logger.info('通话进行中，忽略按键说话的 listen start（防 mode 交叉）');
      return;
    }
    if (_wsManager == null || !_isConnected) {
      // v3.1.0：想打就打——未连接时自动连接（本次 listen start 跳过，连上后重按即可）
      _ensureConnectedThen(() {}, '开始说话');
      return;
    }

    try {
      // 🔥 发送 listen start 消息（按照协议）
      final listenStartMessage = {
        "session_id": _sessionId ?? "", // 使用从 hello 消息中获取的 session_id
        "type": "listen",
        "state": "start",
        "mode": "auto", // 自动模式：自动识别说话
      };

      _wsManager!.sendMessage(jsonEncode(listenStartMessage));
      logger.info('已发送 listen start 消息: ${jsonEncode(listenStartMessage)}');
    } catch (e) {
      logger.severe('发送 listen start 消息失败: $e');
      _showError('启动录音失败: $e');
    }
  }

  /// 处理持续监听开始（发送 realtime 模式的 listen start 消息）
  void _handleContinuousListenStart() {
    if (_wsManager == null || !_isConnected) {
      _showError('未连接到服务器');
      return;
    }

    try {
      // 🔥 发送 realtime 模式的 listen start 消息
      final listenStartMessage = {
        "session_id": _sessionId ?? "",
        "type": "listen",
        "state": "start",
        "mode": "realtime", // 实时模式：持续监听
      };

      _wsManager!.sendMessage(jsonEncode(listenStartMessage));
      logger.info('已发送持续监听 start 消息: ${jsonEncode(listenStartMessage)}');
      ToastUtil.show('开始持续监听');
    } catch (e) {
      logger.severe('发送持续监听 start 消息失败: $e');
      _showError('启动持续监听失败: $e');
    }
  }

  /// 处理持续监听停止（发送 realtime 模式的 listen stop 消息）
  void _handleContinuousListenStop() {
    if (_wsManager == null || !_isConnected) {
      return;
    }

    try {
      // 🔥 发送 realtime 模式的 listen stop 消息
      final listenStopMessage = {
        "session_id": _sessionId ?? "",
        "type": "listen",
        "state": "stop",
        "mode": "realtime", // 实时模式：持续监听
      };

      _wsManager!.sendMessage(jsonEncode(listenStopMessage));
      logger.info('已发送持续监听 stop 消息: ${jsonEncode(listenStopMessage)}');
      ToastUtil.show('停止持续监听');
    } catch (e) {
      logger.severe('发送持续监听 stop 消息失败: $e');
    }
  }

  /// 显示/隐藏 AI 输入指示器（仅触发实际变化时刷新）
  void _setTyping(bool typing) {
    if (_isAiTyping != typing && mounted) {
      setState(() => _isAiTyping = typing);
    }
  }

  /// 开始语音通话（复用现有连续监听 + 音频链路，不改通信层）
  void _startVoiceCall() {
    if (_isInVoiceCall) return;
    if (!_isConnected) {
      // v3.1.0：想打就打——未连接时自动连接，hello ACK 后自动进通话
      _ensureConnectedThen(_startVoiceCall, '进入通话');
      return;
    }
    // v6.0.0：进入通话 → 系统沉浸式（隐藏状态栏/导航栏），配合隐藏 AppBar 实现全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isInVoiceCall = true;
      _showVoiceCallOverlay = true;
      _micMuted = false;
      _isSpeakerOn = false;
      _callStatus = '等待连接...';
      _voiceCallStart = DateTime.now();
      _voiceCallDuration = '00:00';
    });
    _voiceCallTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateVoiceCallDuration(),
    );
    // 与持续监听同链路：先启动麦克风采集，再订阅音频流转发，最后发送 realtime listen
    if (!AudioUtil.isRecording) {
      AudioUtil.startRecording(enableAEC: true);
    }
    // 关键修复：订阅麦克风音频流并逐帧转发到 WebSocket（v1.1.2 漏了这步导致服务器收不到声音）
    _callAudioSubscription = AudioUtil.audioStream.listen(
      (audioData) {
        if (!_micMuted) _handleAudioSend(audioData); // 静音时不发送
      },
      onError: (e) {
        logger.severe('通话音频流错误: $e');
      },
    );
    // v4.4.0：barge-in 已移除，不再订阅麦克风能量流
    _bargeinSub?.cancel();
    _bargeinSub = null;
    _handleContinuousListenStart();
    if (mounted) setState(() => _callStatus = '已连接');
  }

  void _updateVoiceCallDuration() {
    if (_voiceCallStart == null) return;
    final elapsed = DateTime.now().difference(_voiceCallStart!);
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted) setState(() => _voiceCallDuration = '$m:$s');
  }

  /// 结束语音通话
  void _endVoiceCall() {
    // v6.0.0：退出通话 → 恢复系统 UI（与进入时的沉浸式配对）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _voiceCallTimer?.cancel();
    _voiceCallTimer = null;
    // v4.4.0：barge-in 已移除（保留订阅清理以防残留）
    _bargeinSub?.cancel();
    _bargeinSub = null;
    // 取消音频流订阅（与持续监听同链路，只调用不改 lib/core）
    _callAudioSubscription?.cancel();
    _callAudioSubscription = null;
    // 停止麦克风采集（与持续监听同链路，只调用不改 lib/core）
    if (AudioUtil.isRecording) {
      AudioUtil.stopRecording();
    }
    // v3.1.0：挂断时若 AI 还在说话，先发 abort 让服务器立刻停止合成（xiaoleweb.md §4.4）
    if (_isAiPlaying && _wsManager != null && _isConnected) {
      _wsManager!.sendMessage(jsonEncode({'type': 'abort'}));
      logger.info('已发送 abort（AI 说话中挂断，服务器停止 TTS）');
      _isAiPlaying = false;
      _aiPlayingTimer?.cancel();
    }
    _handleContinuousListenStop(); // 复用现有停止逻辑
    if (mounted) {
      setState(() {
        _isInVoiceCall = false;
        _showVoiceCallOverlay = false;
        _micMuted = false;
        _isSpeakerOn = false;
        _callStatus = '等待连接...';
        _voiceCallDuration = '00:00';
        _voiceCallStart = null;
      });
    }
  }

  void _toggleMic() {
    if (mounted) setState(() => _micMuted = !_micMuted);
    // 静音 = 停止麦克风采集；取消静音 = 重新采集
    if (_micMuted) {
      if (AudioUtil.isRecording) AudioUtil.stopRecording();
    } else {
      if (!AudioUtil.isRecording) AudioUtil.startRecording(enableAEC: true);
    }
  }

  void _toggleSpeaker() {
    // 注意：当前 AudioUtil 未暴露扬声道路由 API，此处仅切换 UI 状态（占位）。
    // 真正的听筒/扬声器切换需改动 lib/core（红线），本轮不做。
    if (mounted) setState(() => _isSpeakerOn = !_isSpeakerOn);
    ToastUtil.show(_isSpeakerOn ? '已切换至扬声器' : '已切换至听筒');
  }

  /// 通话中顶部小条（最小化后点击可恢复）
  /// v6.0.0：收起通话全屏层 —— 同时恢复系统 UI，避免沉浸式状态残留
  void _collapseVoiceCallOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _showVoiceCallOverlay = false);
  }

  /// v6.0.0：展开 / 重新展开通话全屏层 —— 每次都必须重入系统沉浸式
  /// （收起时已恢复 edgeToEdge，若展开时只 setState 而不重设沉浸式，会丢失全屏效果）
  void _expandVoiceCallOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _showVoiceCallOverlay = true);
  }

  Widget _buildVoiceCallBanner() {
    return Material(
      color: AppColors.primary,
      child: InkWell(
        onTap: _expandVoiceCallOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.call, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text('通话中', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Text(_voiceCallDuration,
                  style: const TextStyle(color: Colors.white)),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  /// 语音通话全屏覆盖层（对齐原型 v6）
  Widget _buildVoiceCallOverlay() {
    final styleIndex =
        widget.agentId.hashCode.abs() % kAgentAvatarStyles.length;
    return Material(
      color: Colors.black,
      child: Container(
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white),
                      // v6.0.0：收起通话全屏层（同时恢复系统 UI，避免沉浸式残留）
                      onPressed: _collapseVoiceCallOverlay,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () => ToastUtil.show('更多选项'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AgentAvatar(
                styleIndex: styleIndex,
                size: 96,
                radius: 48,
                showOnlineDot: true,
                online: true,
              ),
              const SizedBox(height: 16),
              Text(
                _agentName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _callStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                _voiceCallDuration,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _voiceCallCircleButton(
                      icon: _micMuted ? Icons.mic_off : Icons.mic,
                      label: _micMuted ? '已静音' : '麦克风',
                      circleColor:
                          _micMuted ? const Color(0xFF555555) : Colors.white,
                      iconColor:
                          _micMuted ? Colors.white : const Color(0xFF1A1A1A),
                      onTap: _toggleMic,
                    ),
                    const SizedBox(width: 40),
                    _voiceCallCircleButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      label: _isSpeakerOn ? '扬声器' : '听筒',
                      circleColor:
                          _isSpeakerOn ? AppColors.primary : Colors.white,
                      iconColor: _isSpeakerOn
                          ? Colors.white
                          : const Color(0xFF1A1A1A),
                      onTap: _toggleSpeaker,
                    ),
                    const SizedBox(width: 40),
                    _voiceCallCircleButton(
                      icon: Icons.call_end,
                      label: '挂断',
                      circleColor: AppColors.error,
                      iconColor: Colors.white,
                      onTap: _endVoiceCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceCallCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color circleColor = Colors.white,
    Color iconColor = const Color(0xFF1A1A1A),
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
