import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import '../services/app_feats.dart';
import '../../core/utils/log_buffer.dart';
import '../../core/utils/audio_util.dart';
import '../../core/storage/storage_service.dart';
import '../../app/config/app_config.dart';
import '../widgets/device_edit_dialog.dart';
import 'log_category_page.dart';
import 'external_mcp_page.dart';
import 'proactive_script_page.dart';
import '../../core/proactive/proactive_poll_service.dart';
import '../../core/proactive/proactive_script_store.dart';

/// 开发者中心（v3.3.0，对齐网页版模式，xiaoleweb.md 第十一章）
/// ------------------------------------------------------------
/// 入口：「我」→ 开发者选项 → 未授权先弹密码门（本机记住授权，页面内可清除）。
///
/// v6.7.0 分层重构后结构（6 组）：
/// ① 设备身份（自「我」页迁入：MAC/ClientID/型号编辑，⚠️ MAC 强制小写）
/// ② AI 能力（原「能力开关」拆分：MCP 总闸/工具清单/外部 MCP/视觉/表情）
/// ③ AI 主动联系（原样）
/// ④ 连接与音频（MQTT/AEC/尾音保护）
/// ⑤ 调试（MCP 调试/原始提示/音频能力检测【自「我」页迁入】/运行日志/日志分类）
/// ⑥ 管理（原「安全」+「危险操作」合并：清除授权/全部关闭）
class DevCenterPage extends StatefulWidget {
  const DevCenterPage({super.key});

  @override
  State<DevCenterPage> createState() => _DevCenterPageState();
}

class _DevCenterPageState extends State<DevCenterPage> {
  @override
  void initState() {
    super.initState();
    AppFeats.load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('开发者中心')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // N 项开启
          Center(
            child: Text(
              '${AppFeats.onCount} 项开启',
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // v6.7.0：设备身份组（自「我」页迁入）
          _section(isDark, '设备身份', [
            _deviceMacTile(),
            _deviceClientIdTile(),
            _deviceModelTile(),
          ]),
          // v6.7.0：原「能力开关」拆分——AI 能力
          _section(isDark, 'AI 能力', [
            _switchTile(
              isDark,
              '🧰 MCP 设备工具',
              '向 AI 注册设备工具：26 项（音量/闹钟/日程/拨号/短信/导航/截屏…）——AI 可真实操控',
              'mcptools',
            ),
            // v6.1.2：点开查看已注册给 AI 的**全部 26 项**工具（分组 + 用途说明）
            ListTile(
              leading: const Icon(Icons.list_alt, color: Color(0xFF576B95)),
              title: const Text('📋 查看已注册的工具清单'),
              subtitle: const Text('26 项能力分组明细（AI 能做什么，一目了然）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showMcpToolsDialog(isDark),
            ),
            // v6.4.0：外部 MCP 服务器管理（可增删改多条，工具带前缀桥接给 AI）
            ListTile(
              leading: const Icon(Icons.hub, color: Color(0xFF576B95)),
              title: const Text('🌐 外部 MCP'),
              subtitle: const Text('接入外部 MCP 服务器（biji 笔记 / 高德地图…），可逐台逐工具开关'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ExternalMcpPage()),
                );
              },
            ),
            _switchTile(
              isDark,
              '📷 视觉识物',
              '聊天栏相机按钮：拍照问 AI 这是什么',
              'vision',
            ),
            _switchTile(
              isDark,
              '😄 表情动画',
              'AI 对话时的全屏表情动画（v4.3.0 起默认关，可在此开启）',
              'emotion',
            ),
          ]),
          // v6.5.0：AI 主动来电（方案 D —— 口令存本地，设备 MCP 工具取回）
          _section(isDark, 'AI 主动联系', [
            // 总开关：核心层不自查开关，必须由这里直接启停巡检服务（关闭=零流量）
            SwitchListTile(
              value: AppFeats.get('proactive'),
              activeColor: AppColors.primary,
              title: const Text('🤖 AI 主动联系'),
              subtitle: const Text(
                  '前台定时巡检：由小乐读本地口令判断是否值得主动来电（仅 App 在前台时生效）'),
              onChanged: (v) async {
                AppFeats.set('proactive', v);
                if (v) {
                  await ProactivePollService.instance.start();
                } else {
                  await ProactivePollService.instance.stop();
                }
                if (!mounted) return;
                setState(() {});
                ToastUtil.show(v ? 'AI 主动联系 已开启' : 'AI 主动联系 已关闭');
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: Color(0xFF576B95)),
              title: const Text('⏱ 巡检间隔'),
              subtitle: Text(
                  '每 ${ProactivePollService.instance.intervalMinutes} 分钟一次'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickProactiveInterval,
            ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined,
                  color: Color(0xFF576B95)),
              title: const Text('🌙 允许来电时段'),
              subtitle: Text(_proactiveWindowLabel()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickProactiveWindow,
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: Color(0xFF576B95)),
              title: const Text('📝 巡检口令管理'),
              subtitle: const Text('多条轮换使用（可增删改查 / 恢复默认 / ≤16 字）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ProactiveScriptPage()),
                );
              },
            ),
          ]),
          // v6.7.0：原「能力开关」拆分——连接与音频（尾音保护自「诊断」迁入）
          _section(isDark, '连接与音频', [
            _switchTile(
              isDark,
              '📡 MQTT 常驻在线',
              '长连接保后台在线 + 接收远程配置；下次连接生效（限流风险默认关）',
              'mqtt',
            ),
            // v4.4.0：原「🎤 抢话打断」开关已移除——其用未消回声的振幅判断会误触发，
            // 导致 AI 自问自答（方案根因③）。此处改为 AEC 通话通路开关。
            _aecTile(isDark),
            _tailGuardTile(),
          ]),
          // v6.7.0：原「能力开关」拆分——调试（+ 音频能力检测自「我」页迁入）
          _section(isDark, '调试', [
            _switchTile(
              isDark,
              '🧪 MCP 调试',
              '开启=字幕保留 % 工具名原文；关闭=自动过滤',
              'mcpDebug',
            ),
            // v6.4.4：开发者/普通用户身份分流开关——控制聊天页服务端 alert 的展现方式
            _switchTile(
              isDark,
              '⚠️ 显示服务端原始提示',
              '开启=开发者模式，聊天页直接显示服务器原文（如 alert 报错）；关闭=普通用户模式，改用友好弹窗',
              'rawServerAlert',
            ),
            // v6.7.0：音频能力检测（自「我」页迁入，只读展示）
            _audioCapabilitiesTile(),
            ListTile(
              leading:
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF576B95)),
              title: const Text('📋 运行日志查看'),
              subtitle: const Text('复制最近 200 条运行日志，供 AI 排查故障'),
              onTap: _copyLogs,
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: Color(0xFF576B95)),
              title: const Text('🗂 日志分类'),
              subtitle: Text(
                  '按功能开关日志记录（已开 ${LogBuffer.enabledCount}/${LogBuffer.categories.length}）'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogCategoryPage()),
                );
                if (mounted) setState(() {});
              },
            ),
          ]),
          // v6.7.0：原「安全」+「危险操作」合并为「管理」
          _section(isDark, '管理', [
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF576B95)),
              title: const Text('🔒 清除授权'),
              subtitle: const Text('下次进开发者中心需重新输密码'),
              onTap: () {
                AppFeats.setDevAuthed(false);
                ToastUtil.show('已清除授权');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Color(0xFFE64340)),
              title: const Text('全部关闭'),
              subtitle: const Text('关闭所有开发者功能（等效普通用户模式）'),
              onTap: () {
                AppFeats.allOff();
                setState(() {});
                ToastUtil.show('已全部关闭');
              },
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ===== v6.7.0：设备身份组（自「我」页原样迁入，行为不变） =====

  /// 微信风图标色块（28px 圆角方块 + 白色图标，对齐原型 v7 settings-icon）
  Widget _iconTile(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }

  /// 虚拟 MAC 地址（编辑 + 点按复制）
  /// ⚠️ MAC 强制小写：服务器 WS 侧按 device-id 查设备区分大小写，
  /// 大写 MAC 会 OTA 激活成功但连上即被静默踢线（close code=1005）
  Widget _deviceMacTile() {
    return ListTile(
      leading: _iconTile(Icons.confirmation_num_outlined, const Color(0xFF576B95)),
      title: const Text('虚拟MAC地址'),
      trailing: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: '编辑',
        onPressed: () => showDeviceEditDialog(
          context,
          title: '编辑虚拟MAC地址',
          getCurrent: XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress,
          onSave: (v) => XiaozhiDeviceInfoUtil.instance
              .setDeviceMacAddress(v.trim().toLowerCase()),
        ),
      ),
      subtitle: FutureBuilder<String>(
        future: XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('加载中...');
          }
          if (snapshot.hasError) {
            return const Text('获取失败');
          }
          return Text(snapshot.data ?? '未知');
        },
      ),
      onTap: () async {
        final macAddress =
            await XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress();
        Clipboard.setData(ClipboardData(text: macAddress));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  /// 虚拟 Client ID（编辑 + 点按复制）
  Widget _deviceClientIdTile() {
    return ListTile(
      leading: _iconTile(Icons.badge_outlined, const Color(0xFF576B95)),
      title: const Text('虚拟Client ID'),
      trailing: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: '编辑',
        onPressed: () => showDeviceEditDialog(
          context,
          title: '编辑虚拟Client ID',
          getCurrent: XiaozhiDeviceInfoUtil.instance.getDeviceClientId,
          onSave: XiaozhiDeviceInfoUtil.instance.setDeviceClientId,
        ),
      ),
      subtitle: FutureBuilder<String>(
        future: XiaozhiDeviceInfoUtil.instance.getDeviceClientId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('加载中...');
          }
          if (snapshot.hasError) {
            return const Text('获取失败');
          }
          return Text(snapshot.data ?? '未知');
        },
      ),
      onTap: () async {
        final clientId =
            await XiaozhiDeviceInfoUtil.instance.getDeviceClientId();
        Clipboard.setData(ClipboardData(text: clientId));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  /// 设备型号（编辑）
  /// v4.3.0：单跳只读展示（golden 稳定性：多跳矫正链会让截图在
  /// 「加载中/值」间漂移）。全局矫正入口在聊天页 initState +
  /// 添加/编辑智能体页加载设备字段两处，覆盖日常全部路径。
  Widget _deviceModelTile() {
    return ListTile(
      leading: _iconTile(Icons.phone_android_outlined, AppColors.primary),
      title: const Text('设备型号'),
      trailing: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: '编辑',
        onPressed: () => showDeviceEditDialog(
          context,
          title: '编辑设备型号',
          getCurrent: XiaozhiDeviceInfoUtil.instance.getDeviceModel,
          onSave: XiaozhiDeviceInfoUtil.instance.setDeviceModel,
        ),
      ),
      subtitle: FutureBuilder<String>(
        future: XiaozhiDeviceInfoUtil.instance.getDeviceModel(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('加载中...');
          }
          if (snapshot.hasError) {
            return const Text('获取失败');
          }
          return Text(snapshot.data ?? '未知');
        },
      ),
    );
  }

  /// v6.7.0：音频能力检测（自「我」页原样迁入，只读展示）
  Widget _audioCapabilitiesTile() {
    return FutureBuilder<Map<String, bool>>(
      future: AudioUtil.checkAudioCapabilities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: Icon(Icons.graphic_eq),
            title: Text('音频能力检测'),
            subtitle: Text('检测中...'),
          );
        }

        final capabilities = snapshot.data ?? {};
        final aecSupported = capabilities['aecSupported'] ?? false;
        final noiseSuppress = capabilities['noiseSuppressSupported'] ?? false;
        final autoGain = capabilities['autoGainSupported'] ?? false;

        return Column(
          children: [
            ListTile(
              leading: Icon(
                aecSupported ? Icons.check_circle : Icons.cancel,
                color: aecSupported ? Colors.green : Colors.red,
              ),
              title: const Text('AEC 回声消除'),
              subtitle: Text(aecSupported ? '支持' : '不支持'),
            ),
            ListTile(
              leading: Icon(
                noiseSuppress ? Icons.check_circle : Icons.cancel,
                color: noiseSuppress ? Colors.green : Colors.red,
              ),
              title: const Text('噪声抑制'),
              subtitle: Text(noiseSuppress ? '支持' : '不支持'),
            ),
            ListTile(
              leading: Icon(
                autoGain ? Icons.check_circle : Icons.cancel,
                color: autoGain ? Colors.green : Colors.red,
              ),
              title: const Text('自动增益控制'),
              subtitle: Text(autoGain ? '支持' : '不支持'),
            ),
          ],
        );
      },
    );
  }

  /// v4.4.0：AEC 通话通路开关
  /// **独立于 `AppFeats`**——`AppFeats.allOff()`（"全部关闭"＝普通用户模式）会关掉所有开关，
  /// 而 AEC 属基础收音质量而非"开发者增强功能"，不应被"全部关闭"取消，故用独立存储键。
  Widget _aecTile(bool isDark) {
    return SwitchListTile(
      value: AudioUtil.useAecSource,
      onChanged: (v) {
        AudioUtil.setAecSource(v);
        setState(() {});
        ToastUtil.show(v
            ? '通话降噪通路已开启（下次录音生效）'
            : '通话降噪通路已关闭，恢复原录音源（下次录音生效）');
      },
      title: Text(
        '🎧 通话降噪通路（AEC）',
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '开启＝走通话音频通路以启用硬件回声消除，可消除 AI 尾音被误识别；少数机型音色略闷。下次录音/通话生效',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  int get _tailGuardMs {
    final v = StorageService.instance.getInt(AppConfig.keyTailGuardMs);
    if (v == null) return AppConfig.defaultTailGuardMs;
    return v.clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
  }

  /// v4.4.0：尾音保护时长（100–500ms，默认 300）
  Widget _tailGuardTile() {
    final ms = _tailGuardMs;
    return ListTile(
      leading: const Icon(Icons.timer_outlined, color: Color(0xFF576B95)),
      title: const Text('⏱ 尾音保护'),
      subtitle: Text('AI 说完后等待 $ms 毫秒再恢复采集（减少误识别；调大更保险）'),
      onTap: () => _pickTailGuard(ms),
    );
  }

  Future<void> _pickTailGuard(int current) async {
    double value = current.toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('尾音保护时长'),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()} 毫秒'),
              Slider(
                value: value,
                min: AppConfig.minTailGuardMs.toDouble(),
                max: AppConfig.maxTailGuardMs.toDouble(),
                divisions: 8, // 100~500，步进 50
                label: '${value.round()}ms',
                onChanged: (v) => setS(() => value = v),
              ),
              const Text(
                'AI 说完后等多久再开始听你说话：调大可减少误识别，调小更灵敏',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final v =
        value.round().clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
    await StorageService.instance.setInt(AppConfig.keyTailGuardMs, v);
    setState(() {});
    ToastUtil.show('尾音保护已设为 ${v}ms');
  }

  /// v4.3.2：复制最近 200 条运行日志到剪贴板（供用户粘贴给 AI 排查故障）
  Future<void> _copyLogs() async {
    try {
      final text = LogBuffer.recentText(200);
      if (text.isEmpty) {
        ToastUtil.show('暂无日志，请先复现操作再回来复制');
        return;
      }
      final count = '\n'.allMatches(text).length + 1;
      await Clipboard.setData(ClipboardData(text: text));
      ToastUtil.show('已复制 $count 条日志');
    } catch (e) {
      ToastUtil.show('复制失败：$e');
    }
  }

  /// v6.1.2：展示已注册给 AI 的**全部 MCP 设备工具**。
  /// v6.3.0：由只读弹窗升级为**可操作详情页**——每项行尾带开关，可逐项开关某个工具
  /// （下行层据此在 tools/list 过滤、tools/call 命中禁用工具回 -32601）。
  /// 总闸 `mcptools` 关闭时，逐项开关置灰并提示「先开总闸」。
  void _showMcpToolsDialog(bool isDark) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _McpToolsDetailPage(isDark: isDark),
      ),
    );
  }

  // ===== v6.5.0：AI 主动来电 —— 巡检间隔 / 允许来电时段 =====

  String _fmtMinOfDay(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String _proactiveWindowLabel() {
    final w = ProactiveScriptStore.window;
    if (w.allDay) return '全天';
    return '${_fmtMinOfDay(w.startMin)}–${_fmtMinOfDay(w.endMin)}';
  }

  Future<void> _pickProactiveInterval() async {
    const opts = <int>[15, 30, 60, 120, 240];
    final cur = ProactivePollService.instance.intervalMinutes;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('巡检间隔', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
            ...opts.map((m) => ListTile(
                  title: Text('每 $m 分钟'),
                  trailing: m == cur ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, m),
                )),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ProactivePollService.instance.setIntervalMinutes(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickProactiveWindow() async {
    final w = ProactiveScriptStore.window;
    var allDay = w.allDay;
    var start = w.startMin;
    var end = w.endMin;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('允许来电时段',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              SwitchListTile(
                title: const Text('全天允许'),
                value: allDay,
                activeColor: AppColors.primary,
                onChanged: (v) => setSheet(() => allDay = v),
              ),
              if (!allDay) ...[
                ListTile(
                  title: const Text('开始时间'),
                  trailing: Text(_fmtMinOfDay(start)),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(
                          hour: start ~/ 60, minute: start % 60),
                    );
                    if (t != null) setSheet(() => start = t.hour * 60 + t.minute);
                  },
                ),
                ListTile(
                  title: const Text('结束时间'),
                  trailing: Text(_fmtMinOfDay(end)),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                    );
                    if (t != null) setSheet(() => end = t.hour * 60 + t.minute);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('支持跨午夜（如 22:00–08:00）',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await ProactiveScriptStore.setWindow(
        ProactiveWindow(allDay: allDay, startMin: start, endMin: end));
    if (mounted) setState(() {});
  }

  Widget _section(bool isDark, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(bool isDark, String title, String subtitle, String key) {
    return SwitchListTile(
      value: AppFeats.get(key),
      onChanged: (v) {
        AppFeats.set(key, v);
        setState(() {});
        ToastUtil.show(v ? '$title 已开启' : '$title 已关闭');
      },
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// v6.3.0：MCP 设备工具详情页（逐项开关）。独立 StatefulWidget，
/// 其自身 setState 即可实时刷新开关，不必依赖开发者中心页 rebuild。
class _McpToolsDetailPage extends StatefulWidget {
  final bool isDark;
  const _McpToolsDetailPage({required this.isDark});

  @override
  State<_McpToolsDetailPage> createState() => _McpToolsDetailPageState();
}

class _McpToolsDetailPageState extends State<_McpToolsDetailPage> {
  // 组名 → [ [工具名, 用途], ... ]
  static const List<MapEntry<String, List<List<String>>>> groups = [
    MapEntry('① 基础能力（11 项）', [
      ['self.get_device_status', '设备状态：音量 / 主题 / 电量 / 网络'],
      ['self.audio_speaker.set_volume', '调节音量（真实系统媒体音量）'],
      ['self.screen.set_theme', '切换深色 / 浅色主题'],
      ['self.timer.create_countdown', '创建倒计时（到点提醒+震动+播报）'],
      ['self.timer.get_tasks', '查看进行中的倒计时'],
      ['self.timer.stop_task', '停止指定倒计时'],
      ['self.schedule.create_event', '创建日程（写入系统日历，App 关了也提醒）'],
      ['self.schedule.get_events', '查看已创建的日程记录'],
      ['self.schedule.delete_event', '删除日程记录'],
      ['self.camera.take_photo', '拍照并识别画面内容'],
      ['self.screen.preview_image', '在聊天里显示一张图片'],
    ]),
    MapEntry('② 官方标准补齐（5 项）', [
      ['self.screen.set_brightness', '调节屏幕亮度（应用级，免权限）'],
      ['self.screen.get_info', '屏幕尺寸 / 像素比信息'],
      ['self.get_system_info', '系统与设备信息：品牌 / 型号 / 安卓版本'],
      ['self.screen.snapshot', '截取当前界面（不用系统录屏权限）'],
      ['self.reboot', '重启会话（重新连接 + 清空当前对话）'],
    ]),
    MapEntry('③ 系统能力·免权限（5 项）', [
      ['self.phone.dial', '打开拨号盘并填入号码（需你点拨出）'],
      ['self.message.send_sms', '发短信：预填号码与内容（需你点发送）'],
      ['self.map.navigate', '打开地图导航到指定地点'],
      ['self.system.open_settings', '打开系统设置页：WiFi / 蓝牙 / 声音等'],
      ['self.system.open_url', '用浏览器打开网页'],
    ]),
    MapEntry('④ 提醒与随身工具（5 项）', [
      ['self.alarm.set_alarm', '设置真实系统闹钟（时钟 App 里可见，关机后仍会响）'],
      ['self.show_toast', '屏幕轻提示（不打断对话）'],
      ['self.share.text', '把文字分享到备忘录 / 微信 / 钉钉等'],
      ['self.clipboard.get', '读取剪贴板内容'],
      ['self.clipboard.set', '把文字写入剪贴板'],
    ]),
    MapEntry('⑤ 定位能力（1 项）', [
      ['self.location.get_current', '获取当前 GPS 坐标（GCJ-02，供高德/导航使用）'],
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final masterOn = AppFeats.mcptools;

    return Scaffold(
      appBar: AppBar(title: const Text('MCP 设备工具')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('共 ${_totalCount()} 项能力，逐项开关；关闭后 AI 将看不到该工具',
                style: TextStyle(fontSize: 12, color: sub)),
          ),
          if (!masterOn)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF576B95).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '🧰 总开关「MCP 设备工具」已关闭，下面各项暂不可操作。'
                '请先返回上一页开启总闸。',
                style: TextStyle(fontSize: 12, color: Color(0xFF576B95)),
              ),
            ),
          for (final g in groups)
            _section(g.key, g.value, prim, sub, masterOn),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              '⚠️ 闹钟 / 日程 / 短信 / 拨号 / 分享会打开系统界面，'
              '需要你确认后才真正生效（安卓的安全设计）。',
              style: TextStyle(fontSize: 11, color: sub, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  int _totalCount() => groups.fold(0, (sum, g) => sum + g.value.length);

  Widget _section(String title, List<List<String>> tools, Color prim, Color sub,
      bool masterOn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: prim)),
          ),
          Material(
            color: widget.isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                for (final t in tools)
                  SwitchListTile(
                    // 总闸关 → 置灰不可操作（逐项设置保留，不清除）
                    onChanged: masterOn
                        ? (v) {
                            AppFeats.setMcpToolEnabled(t[0], v);
                            setState(() {});
                          }
                        : null,
                    value: AppFeats.mcpToolEnabled(t[0]),
                    title: Text(t[1],
                        style: TextStyle(
                            fontSize: 14,
                            color: masterOn ? prim : sub)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(t[0],
                          style: TextStyle(fontSize: 11, color: sub)),
                    ),
                    activeColor: const Color(0xFF07C160),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 开发者中心密码门（未授权时弹出；与网页版同密码，错误抖动）
Future<void> showDevGateIfNeeded(BuildContext context) async {
  if (AppFeats.devAuthed) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevCenterPage()),
    );
    return;
  }
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('开发者模式'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            hintText: '请输入密码', border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.of(ctx).pop(v == AppFeats.devPassword),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text == AppFeats.devPassword),
            child: const Text('确定')),
      ],
    ),
  );
  if (ok == true) {
    AppFeats.setDevAuthed(true);
    ToastUtil.show('授权成功');
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DevCenterPage()),
      );
    }
  } else if (ok == false) {
    ToastUtil.show('密码错误');
  }
}
