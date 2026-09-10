import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/agent_model.dart';
import '../../../core/providers/agent_provider.dart';
import '../../../core/utils/toast_util.dart';
import '../../../core/utils/xiaozhi_device_info_util.dart';
import '../../../app/config/app_config.dart';
import '../../../app/themes/app_colors.dart';
import '../../widgets/agent_avatar.dart';
import '../../widgets/activation_dialog.dart';
import '../../services/agent_identity_store.dart';

/// 智能体配置页面（对齐原型 v6 的添加智能体弹窗）
class AgentConfigPage extends ConsumerStatefulWidget {
  final String? agentId;

  const AgentConfigPage({super.key, this.agentId});

  @override
  ConsumerState<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(
    text: '小乐${DateTime.now().millisecondsSinceEpoch}',
  );
  final _urlController = TextEditingController(
    text: 'wss://api.tenclass.net/xiaozhi/v1/',
  );
  final _tokenController = TextEditingController(text: 'to-test');
  final _descriptionController = TextEditingController();
  final _otaController = TextEditingController(
    text: 'https://api.tenclass.net/xiaozhi/ota/',
  );
  // 设备身份（全局，写入 SharedPreferences，连接时读取生效）
  final _macController = TextEditingController();
  final _clientIdController = TextEditingController();
  // v4.3.0：型号统一 m5stack-core-s3（弃用 xiaole-voice-v1 / 手机型号，方案模块一）
  final _modelController =
      TextEditingController(text: kUnifiedDeviceModel);
  bool _isLoading = false;
  bool _advancedExpanded = false;
  int _previewStyleIndex = 0;

  bool get isEdit => widget.agentId != null;

  @override
  void initState() {
    super.initState();
    _previewStyleIndex = Random().nextInt(kAgentAvatarStyles.length);
    _loadDeviceFields();
    if (isEdit) {
      _loadAgent();
    }
  }

  /// 加载设备身份当前值（全局）
  Future<void> _loadDeviceFields() async {
    final mac = await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress();
    final cid = await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();
    // v4.3.0：读到旧值（手机型号 fallback / xiaole-voice-v1）→ 矫正显示并写回覆盖值
    var model = await XiaozhiDeviceInfoUtil.instance.getDeviceModel();
    if (model != kUnifiedDeviceModel) {
      model = kUnifiedDeviceModel;
      await XiaozhiDeviceInfoUtil.instance.setDeviceModel(kUnifiedDeviceModel);
    }
    if (!mounted) return;
    setState(() {
      _macController.text = mac;
      _clientIdController.text = cid;
      _modelController.text = model;
    });
  }

  /// 加载智能体数据（编辑模式）
  Future<void> _loadAgent() async {
    if (widget.agentId == null) return;

    final agent = await ref
        .read(agentListProvider.notifier)
        .getAgentById(widget.agentId!);

    if (agent != null && mounted) {
      setState(() {
        _nameController.text = agent.name;
        _urlController.text = agent.url;
        _tokenController.text = agent.token;
        _otaController.text = agent.otaUrl;
        _descriptionController.text = agent.description;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _descriptionController.dispose();
    _otaController.dispose();
    _macController.dispose();
    _clientIdController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑智能体' : '添加智能体'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveAndActivate,
              child: const Text('提交激活'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 头像预览 + 随机换头像
            Row(
              children: [
                AgentAvatar(
                  styleIndex: _previewStyleIndex,
                  size: 72,
                  radius: 12,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _previewStyleIndex =
                              (_previewStyleIndex + 1) % kAgentAvatarStyles.length;
                        }),
                        icon: const Text('✨', style: TextStyle(fontSize: 16)),
                        label: const Text('随机换头像'),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '新建后头像按 ID 自动分配',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '给智能体起个名字',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入智能体名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 高级设置（默认折叠）
            InkWell(
              onTap: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Text('高级设置',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Icon(
                      _advancedExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_advancedExpanded) ...[
              _deviceField(
                label: 'MAC 地址',
                controller: _macController,
                hint: 'a4:cf:12:34:56:78（必须小写）',
                onGenerate: () => setState(() {
                  _macController.text = _randomMac();
                }),
              ),
              _deviceField(
                label: 'Client ID',
                controller: _clientIdController,
                hint: 'xxxx-xxxx-xxxx',
                onGenerate: () => setState(() {
                  _clientIdController.text = _randomClientId();
                }),
              ),
              _deviceField(
                label: '设备型号',
                controller: _modelController,
                hint: 'm5stack-core-s3',
                onGenerate: () => setState(() {
                  // v4.3.0：型号统一后固定填入（不再随机）；MAC/ClientID 仍随机生成
                  _modelController.text = kUnifiedDeviceModel;
                }),
              ),
              TextFormField(
                controller: _otaController,
                decoration: const InputDecoration(
                  labelText: 'OTA 地址',
                  hintText: 'https://api.example.com/v1/ota',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'WebSocket 地址',
                  hintText: 'wss://api.example.com',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入 Websocket 地址';
                  }
                  if (!value.startsWith('ws://') &&
                      !value.startsWith('wss://')) {
                    return '请输入有效的 Websocket URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Token',
                  hintText: '输入 API Token',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入 Token';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: '描述（可选）',
                  hintText: '简单描述这个智能体',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              const Text(
                '设备身份字段保存后写入设备身份（全局生效），用于连接校验。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 设备字段：输入框 + 🎲 重新生成
  Widget _deviceField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onGenerate,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: InputDecoration(hintText: hint),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onGenerate,
                child: const Text('🎲 重新生成'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 生成随机虚拟 MAC。
  /// ⚠️ 必须【全小写】：小智服务器 WS 侧按 device-id 查设备区分大小写，
  /// 大写 MAC 会导致 OTA 激活成功、但 WS 连上 30~150ms 被静默踢线（close code=1005）。
  String _randomMac() {
    final r = Random();
    final bytes = List<int>.generate(6, (_) => r.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toLowerCase())
        .join(':');
  }

  String _randomClientId() {
    return const Uuid().v4(); // 形如 1257d6dc-7b0b-4772-aacc-9b27e33778ac（合法 UUID）
  }

  /// 保存智能体 + 写入设备身份，然后弹出激活轮询弹窗
  void _saveAndActivate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // 设备身份写入全局 SharedPreferences（只调用不改 lib/core）
      // ⚠️ MAC 强制小写：服务器 WS 侧按 device-id 查设备区分大小写，大写会被静默踢线（1005）
      final mac = _macController.text.trim().toLowerCase();
      await XiaozhiDeviceInfoUtil.instance.setDeviceMacAddress(mac);
      await XiaozhiDeviceInfoUtil.instance
          .setDeviceClientId(_clientIdController.text.trim());
      await XiaozhiDeviceInfoUtil.instance
          .setDeviceModel(_modelController.text.trim());

      // v1.1.5：同时按 agentId 存一份独立身份，进入对话时切换，避免多智能体串号
      final identityAgentId = widget.agentId ?? const Uuid().v4();
      await AgentIdentityStore.save(
        identityAgentId,
        mac: mac, // 已小写化
        clientId: _clientIdController.text.trim(),
        model: _modelController.text.trim(),
      );

      final agent = AgentModel(
        id: identityAgentId,
        name: _nameController.text.trim(),
        url: _urlController.text.trim(),
        token: _tokenController.text.trim(),
        otaUrl: _otaController.text.trim(),
        description: _descriptionController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (isEdit) {
        await ref.read(agentListProvider.notifier).updateAgent(agent);
      } else {
        await ref.read(agentListProvider.notifier).addAgent(agent);
      }

      if (!mounted) return;

      // 弹出激活轮询弹窗（只读调用 OTA 服务）
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ActivationDialog(
          otaUrl: _otaController.text.trim(),
          appVersion: AppConfig.appVersion,
        ),
      );

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
