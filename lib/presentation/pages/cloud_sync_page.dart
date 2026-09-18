import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/config/app_config.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';
import '../../core/providers/agent_provider.dart';
import '../../data/models/agent_model.dart';
import '../../data/models/message_model.dart';
import '../services/chat_history_store.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/wx_dialog.dart';
import '../widgets/wx_icon_button.dart';

/// 一键云端（v4.1.0，对齐网页版批次C 交互）
///
/// 未绑定：手机号 + 用户名 → 绑定建档；
/// 已绑定：上传（⬆ 全部智能体聊天+配置）/ 恢复（⬇ 覆盖本机，需确认）/ 解除绑定。
/// 手机号是云端唯一身份；绑定后用户名锁定（重绑须同名）。
/// v6.4.2：由 StatefulWidget 改为 ConsumerStatefulWidget —— 恢复完成后需要拿到 `ref`
/// 去刷新 `agentListProvider`（见 `_pull()` 内 `loadAgents()` 调用）。
class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({super.key});

  @override
  ConsumerState<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends ConsumerState<CloudSyncPage> {
  final CloudSyncService _svc = CloudSyncService();
  final TextEditingController _phoneCtl = TextEditingController();
  final TextEditingController _nameCtl = TextEditingController();
  // v4.3.2：云同步链路日志（自动进 LogBuffer）
  final Logger _log = Logger('CloudSyncPage');

  CloudSyncState? _state;
  bool _busy = false; // 操作进行中（防重复提交）
  double _progress = 0;
  String _statusText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final st = await CloudSyncService.loadState();
    if (!mounted) return;
    setState(() {
      _state = st;
      if (st == null) {
        final prefsFuture = SharedPreferences.getInstance();
        prefsFuture.then((prefs) {
          if (!mounted) return;
          _nameCtl.text = prefs.getString('profile_name') ?? '';
        });
      }
    });
  }

  void _setBusy(bool busy, {String status = '', double progress = 0}) {
    if (!mounted) return;
    setState(() {
      _busy = busy;
      _statusText = status;
      _progress = progress;
      if (busy) _errorText = null;
    });
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorText = msg;
    });
  }

  // ---------------- 读取本地数据（上传用） ----------------

  Future<(List<AgentModel>, Map<String, List<MessageModel>>)> _readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final agents = <AgentModel>[];
    final raw = prefs.getString(AppConfig.keyAgentList);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          try {
            agents.add(AgentModel.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      } catch (_) {}
    }
    final sessions = <String, List<MessageModel>>{};
    for (final a in agents) {
      final msgs = await ChatHistoryStore.loadAll(a.id);
      if (msgs.isNotEmpty) sessions[a.id] = msgs;
    }
    return (agents, sessions);
  }

  // ---------------- 三个动作 ----------------

  Future<void> _bind() async {
    final phone = _phoneCtl.text.trim();
    final name = _nameCtl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _fail('请输入正确的 11 位手机号（1 开头）');
      return;
    }
    if (name.isEmpty || name.length > 24) {
      _fail('用户名需 1-24 个字符');
      return;
    }
    _setBusy(true, status: '与云端核验身份中…', progress: 0.4);
    _log.info('UI 触发绑定：userName=$name');
    try {
      final r = await _svc.bind(phone, name, profile: {'userName': name});
      if (r['ok'] != true) {
        _fail('绑定失败：${r['error'] ?? '未知错误'}');
        return;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _statusText = '绑定成功！用户名已锁定';
        _busy = false;
        _progress = 1;
      });
    } catch (e, st) {
      // v4.3.2：任何异常都必须复位 _busy，否则按钮永久转圈（真机卡死次因）
      _log.severe('绑定异常: $e\n${_shortStack(st)}');
      _fail(_netError(e, '绑定'));
    }
  }

  /// v4.3.2：网络类异常统一文案（绑定/上传/恢复三个动作共用）
  String _netError(Object e, String action) {
    if (e is TimeoutException) return '$action超时，请检查网络后重试';
    if (e is SocketException || e is HandshakeException) {
      return '网络连接失败，请检查网络后重试';
    }
    return '$action失败：$e';
  }

  /// 堆栈只取前 6 行，避免刷爆日志缓冲
  static String _shortStack(StackTrace st) =>
      st.toString().split('\n').take(6).join(' | ');

  Future<void> _push() async {
    final st = _state;
    if (st == null) return;
    _setBusy(true, status: '读取本地聊天记录…', progress: 0.1);
    try {
      final (agents, sessions) = await _readLocal();
      if (sessions.isEmpty) {
        _fail('还没有聊天记录可上传');
        return;
      }
      final packed = sessions.values.fold<int>(0, (s, l) => s + l.length);
      _log.info('读取本地完成：${agents.length} 个智能体，'
          '${sessions.length} 个会话共 $packed 条消息');
      _setBusy(true,
          status: '打包完成：${agents.length} 个智能体 · $packed 条消息，上传中…',
          progress: 0.5);
      final prefs = await SharedPreferences.getInstance();
      final nickname = prefs.getString('profile_name') ?? '小乐';
      final sw = Stopwatch()..start();
      final r = await _svc.pushAll(
        state: st,
        nickname: nickname,
        agents: agents,
        sessions: sessions,
      );
      sw.stop();
      _log.info('pushAll 返回（耗时 ${sw.elapsedMilliseconds}ms）：$r');
      if (r['ok'] != true) {
        _fail('上传失败：${r['error'] ?? '未知错误'}');
        return;
      }
      await _load();
      if (!mounted) return;
      setState(() {
        _statusText =
            '上传完成！${r['messages']} 条消息 · ${r['blocks']} 个数据块已存入云端';
        _busy = false;
        _progress = 1;
      });
    } catch (e, st) {
      // v4.3.2：修复真机「打包完成后永久卡住」——异常必须复位 _busy
      _log.severe('上传异常: $e\n${_shortStack(st)}');
      _fail(_netError(e, '上传'));
    }
  }

  Future<void> _pull() async {
    final st = _state;
    if (st == null) return;
    _setBusy(true, status: '从云端读取…', progress: 0.2);
    try {
      final r = await _svc.pullAll(st);
      if (r['ok'] != true) {
        _fail('读取失败：${r['error'] ?? '未知错误'}');
        return;
      }
      final cAgent = (r['agents'] as List).length;
      final cMsg = (r['messages'] as num?)?.toInt() ?? 0;
      _log.info('pullAll 返回：$cAgent 个智能体 / $cMsg 条消息');
      if (cAgent == 0 && cMsg == 0) {
        _fail('云端还没有数据，请先在任意一端上传');
        return;
      }
      _setBusy(true, status: '云端读取完成，等待确认…', progress: 0.6);
      if (!mounted) return;
      final ok = await showWxDialog(
        context,
        title: '确认恢复？',
        content: '云端有 $cAgent 个智能体 · $cMsg 条消息。\n\n'
            '恢复将【覆盖】本机的智能体配置与全部聊天记录，确定恢复吗？',
        confirmText: '覆盖恢复',
        danger: true,
      );
      if (ok != true) {
        _setBusy(false);
        return;
      }
      await CloudSyncService.applyPullResult(result: r);
      // v6.4.2：applyPullResult 只写盘、不通知内存状态，导致恢复后列表不刷新
      // （要再新增一个智能体才"顺带"显示）。此处补一次与 addAgent 完全等价的刷新动作。
      await ref.read(agentListProvider.notifier).loadAgents();
      await _load();
      if (!mounted) return;
      setState(() {
        _statusText = '恢复完成！$cAgent 个智能体 · $cMsg 条消息已回到本机';
        _busy = false;
        _progress = 1;
      });
    } catch (e, st) {
      // v4.3.2：异常必须复位 _busy，否则「从云端读取…」永久转圈
      _log.severe('恢复异常: $e\n${_shortStack(st)}');
      _fail(_netError(e, '恢复'));
    }
  }

  /// v6.2.0：**清空该账号在云端的全部数据**（智能体配置 + 全部聊天记录）。
  ///
  /// 危险操作：先弹二次确认（明确列出删除范围与"不可恢复"），
  /// 再调用云端 `POST /clear`（服务端仍会做手机号+用户名双因子核验）。
  /// 本机数据不受影响。
  Future<void> _clearCloud() async {
    final st = await CloudSyncService.loadState();
    if (st == null) return;
    if (!mounted) return;

    final ok = await showWxDialog(
      context,
      title: '⚠️ 清空云端数据',
      content: '将删除账号「${st.maskedPhone}」在云端的全部数据：\n\n'
          '· 所有智能体配置（含 MAC / 设备 ID）\n'
          '· 全部聊天记录\n\n'
          '此操作不可恢复（你本机上的数据不受影响）。',
      confirmText: '确认清空',
      danger: true,
    );
    if (ok != true || !mounted) return;

    _setBusy(true, status: '正在清空云端数据…', progress: 0.5);
    try {
      final r = await _svc.clearAll(st);
      if (!mounted) return;
      if (r['ok'] == true) {
        setState(() {
          _statusText = '云端数据已清空'
              '（智能体 ${r['deletedAgents'] ?? 0} · 会话块 ${r['deletedBlocks'] ?? 0}）';
          _busy = false;
          _progress = 1;
        });
      } else {
        _fail('清空失败：${r['error'] ?? '未知错误'}');
      }
    } catch (e, st2) {
      // 异常必须复位 _busy，避免界面永久转圈（v4.3.2 教训）
      _log.severe('清空云端异常: $e\n${_shortStack(st2)}');
      _fail(_netError(e, '清空云端'));
    }
  }

  Future<void> _unbind() async {
    final ok = await showWxDialog(
      context,
      title: '解除绑定',
      content: '仅解除本机与云端的关联（云端数据不受影响）。\n'
          '之后可用同一手机号+用户名重新绑定。',
      confirmText: '解除',
    );
    if (ok == true) {
      await CloudSyncService.clearState();
      await _load();
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('一键云端'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: _busy ? _buildProgress() : _buildBody(),
    );
  }

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gapXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
            const SizedBox(height: AppDimens.gapXl),
            Text(_statusText, textAlign: TextAlign.center),
            const SizedBox(height: AppDimens.gapLg),
            LinearProgressIndicator(value: _progress),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final st = _state;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputFill =
        isDark ? AppColors.inputBackgroundDark : AppColors.inputBackground;
    final inputBorder =
        isDark ? AppColors.inputBorderDark : AppColors.inputBorder;

    InputDecoration wxInput(String labelText, {String? hintText}) =>
        InputDecoration(
          labelText: labelText,
          hintText: hintText,
          counterText: '',
          filled: true,
          fillColor: inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            borderSide: BorderSide(color: inputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            borderSide: BorderSide(color: inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      children: [
        Container(
          padding: const EdgeInsets.all(AppDimens.pagePadding),
          decoration: BoxDecoration(
            color: AppTextStyles.surface(context),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cloud_outlined, color: AppColors.cloudBlue),
                SizedBox(width: AppDimens.gapSm),
                Text('云端身份',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: AppDimens.gapSm),
              Text(
                st == null
                    ? '手机号是您在云端的唯一身份。绑定后可随时把聊天记录与智能体配置备份到云端，换设备也能一键恢复。'
                    : '已绑定：${st.userName} · ${st.maskedPhone}',
                style: AppTextStyles.caption.copyWith(
                  color: AppTextStyles.secondaryText(context),
                ),
              ),
              if (st != null) ...[
                const SizedBox(height: AppDimens.gapXs),
                Text(
                  '绑定于 ${_fmt(st.boundAt)} · ${st.lastSync > 0 ? '上次同步 ${_fmt(st.lastSync)}' : '尚未同步过'}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppTextStyles.tertiaryText(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.gapLg),
        if (st == null)
          _buildUnbound(wxInput)
        else
          _buildBound(),
        if (_errorText != null) ...[
          const SizedBox(height: AppDimens.gapMd),
          Text(_errorText!,
              style: AppTextStyles.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }

  Widget _buildUnbound(InputDecoration Function(String, {String? hintText}) wxInput) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      decoration: BoxDecoration(
        color: AppTextStyles.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Column(
        children: [
          TextField(
            controller: _phoneCtl,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: wxInput('手机号（云端唯一身份）',
                hintText: '11 位手机号'),
          ),
          const SizedBox(height: AppDimens.gapMd),
          TextField(
            controller: _nameCtl,
            maxLength: 24,
            decoration: wxInput('用户名（绑定后锁定，重绑须同名）'),
          ),
          const SizedBox(height: AppDimens.gapLg),
          WxIconButton(
            label: '绑定云端',
            icon: Icons.lock_outline,
            filled: true,
            fullWidth: true,
            onPressed: _bind,
          ),
        ],
      ),
    );
  }

  Widget _buildBound() {
    return Container(
      padding: const EdgeInsets.all(AppDimens.pagePadding),
      decoration: BoxDecoration(
        color: AppTextStyles.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Column(
        children: [
          WxIconButton(
            label: '⬆ 上传聊天记录到云端',
            icon: Icons.upload,
            filled: true,
            fullWidth: true,
            onPressed: _push,
          ),
          const SizedBox(height: 10),
          WxIconButton(
            label: '⬇ 从云端恢复到本机',
            icon: Icons.download,
            filled: false,
            fullWidth: true,
            onPressed: _pull,
          ),
          const SizedBox(height: 10),
          // v6.2.0：清空云端数据（危险操作 → 二次确认）
          WxIconButton(
            label: '🗑 清空云端数据',
            icon: Icons.delete_forever_outlined,
            filled: false,
            fullWidth: true,
            danger: true,
            onPressed: _clearCloud,
          ),
          const SizedBox(height: 10),
          WxIconButton(
            label: '解除本机绑定',
            icon: Icons.link_off,
            filled: false,
            fullWidth: true,
            onPressed: _unbind,
          ),
          const SizedBox(height: AppDimens.gapXs),
          Text(
            '云端每个智能体保留最近 500 条 · 三端（网页/桌面/App）同号即互通',
            style: AppTextStyles.caption.copyWith(
              color: AppTextStyles.tertiaryText(context),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
