import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_text_styles.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_dimens.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import '../services/app_feats.dart';
import '../../core/utils/log_buffer.dart';
import '../../core/utils/audio_util.dart';
import '../../core/storage/storage_service.dart';
import '../../app/config/app_config.dart';
import '../widgets/device_edit_dialog.dart';
import '../widgets/wx_cell.dart';
import '../widgets/wx_dialog.dart';
import '../widgets/wx_action_sheet.dart';
import 'log_category_page.dart';
import 'external_mcp_page.dart';
import 'proactive_script_page.dart';
import 'proactive_log_page.dart';
import '../../core/proactive/proactive_poll_service.dart';
import '../../core/proactive/proactive_script_store.dart';
import '../../core/proactive/proactive_background.dart';
import 'background_guide_page.dart';

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
          // v6.7.0：设备身份组（自「我」页迁入）
          _section(isDark, '设备身份', [
            _deviceMacTile(),
            _deviceClientIdTile(),
            _deviceModelTile(),
          ]),
          // v6.7.0：原「能力开关」拆分——AI 能力
          _section(isDark, 'AI 能力', [
            _switchTile(
              'MCP 设备工具',
              '向 AI 注册设备工具：26 项（音量/闹钟/日程/拨号/短信/导航/截屏…）——AI 可真实操控',
              'mcptools',
              icon: Icons.build_outlined,
              iconColor: AppColors.info,
              trailingText: '26 项',
            ),
            // v6.1.2：点开查看已注册给 AI 的**全部 26 项**工具（分组 + 用途说明）
            WxCell(
              leading: _iconTile(Icons.list_alt, AppColors.info),
              title: '查看已注册的工具清单',
              subtitle: '26 项能力分组明细（AI 能做什么，一目了然）',
              showArrow: true,
              onTap: () => _showMcpToolsDialog(isDark),
            ),
            // v6.4.0：外部 MCP 服务器管理（可增删改多条，工具带前缀桥接给 AI）
            WxCell(
              leading: _iconTile(Icons.hub, AppColors.primary),
              title: '外部 MCP',
              subtitle: '接入外部 MCP 服务器（biji 笔记 / 高德地图…），可逐台逐工具开关',
              showArrow: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ExternalMcpPage(),
                  ),
                );
              },
            ),
            _switchTile(
              '视觉识物',
              '聊天栏相机按钮：拍照问 AI 这是什么',
              'vision',
              icon: Icons.photo_camera_outlined,
              iconColor: AppColors.cloudBlue,
            ),
            _switchTile(
              '表情动画',
              'AI 对话时的全屏表情动画（v4.3.0 起默认关，可在此开启）',
              'emotion',
              icon: Icons.emoji_emotions_outlined,
              iconColor: AppColors.emojiPink,
              showDivider: false,
            ),
          ]),
          // v6.5.0：AI 主动来电（方案 D —— 口令存本地，设备 MCP 工具取回）
          // v6.8.0：后台化（WorkManager 周期唤醒 + 高优先通知）
          _section(isDark, 'AI 主动联系', [
            // 总开关：核心层不自查开关，必须由这里直接启停巡检服务（关闭=零流量）
            WxCell(
              leading: _iconTile(Icons.phone_in_talk_outlined, AppColors.alertAmber),
              title: 'AI 主动联系',
              subtitle: '前台定时巡检 + 退到后台/锁屏后由系统周期唤醒'
                  '（WorkManager，最小 15 分钟），命中即高优先通知来电',
              trailing: Switch(
                value: AppFeats.get('proactive'),
                activeColor: AppColors.primary,
                onChanged: (v) => _toggleProactive(v),
              ),
              onTap: () => _toggleProactive(!AppFeats.get('proactive')),
            ),
            // v6.8.0：通知被拒提示（优雅降级，不崩溃）
            if (AppFeats.get('proactive') &&
                ProactiveBackground.isNotificationDenied())
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
                child: Text(
                  '通知权限被禁用，主动来电将无法提醒。请在系统设置中允许小乐发送通知。',
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            // v6.8.0：后台保活引导入口
            WxCell(
              leading: _iconTile(Icons.battery_charging_full, AppColors.info),
              title: '后台保活引导',
              subtitle: '电池优化白名单 / 自启动 / 后台运行限制（提升锁屏存活率）',
              showArrow: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BackgroundGuidePage(),
                  ),
                );
              },
            ),
            WxCell(
              leading: _iconTile(Icons.schedule, AppColors.info),
              title: '巡检间隔',
              subtitle: '每 ${ProactivePollService.instance.intervalMinutes} '
                  '分钟一次（后台最小 15 分钟）',
              trailingText:
                  '每 ${ProactivePollService.instance.intervalMinutes} 分钟',
              showArrow: true,
              onTap: _pickProactiveInterval,
            ),
            WxCell(
              leading: _iconTile(Icons.nights_stay, AppColors.info),
              title: '允许来电时段',
              subtitle: _proactiveWindowLabel(),
              showArrow: true,
              onTap: _pickProactiveWindow,
            ),
            WxCell(
              leading: _iconTile(Icons.notes, AppColors.info),
              title: '巡检口令管理',
              subtitle: '多条轮换使用（可增删改查 / 恢复默认 / ≤16 字）',
              showArrow: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProactiveScriptPage(),
                  ),
                );
              },
            ),
            // v6.8.3（A 项）：电话日志入口（诊断用，旁路记录层，不改动巡检行为）
            WxCell(
              leading: _iconTile(Icons.call, AppColors.info),
              title: '电话日志',
              subtitle: '每轮巡检的完整过程（含跳过原因/口令/开场白），最近 50 轮，可一键复制',
              trailingText: '最近 50 轮',
              showArrow: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProactiveLogPage()),
                );
              },
              showDivider: false,
            ),
          ]),
          // v6.7.0：原「能力开关」拆分——连接与音频（尾音保护自「诊断」迁入）
          _section(isDark, '连接与音频', [
            _switchTile(
              'MQTT 常驻在线',
              '长连接保后台在线 + 接收远程配置；下次连接生效（限流风险默认关）',
              'mqtt',
              icon: Icons.router,
              iconColor: AppColors.info,
            ),
            // v4.4.0：原「🎤 抢话打断」开关已移除——其用未消回声的振幅判断会误触发，
            // 导致 AI 自问自答（方案根因③）。此处改为 AEC 通话通路开关。
            _aecTile(),
            _tailGuardTile(),
          ]),
          // v6.7.0：原「能力开关」拆分——调试（+ 音频能力检测自「我」页迁入）
          _section(isDark, '调试', [
            _switchTile(
              'MCP 调试',
              '开启=字幕保留 % 工具名原文；关闭=自动过滤',
              'mcpDebug',
              icon: Icons.bug_report,
              iconColor: AppColors.info,
            ),
            // v6.4.4：开发者/普通用户身份分流开关——控制聊天页服务端 alert 的展现方式
            _switchTile(
              '显示服务端原始提示',
              '开启=开发者模式，聊天页直接显示服务器原文（如 alert 报错）；'
                  '关闭=普通用户模式，改用友好弹窗',
              'rawServerAlert',
              icon: Icons.warning_amber,
              iconColor: AppColors.info,
            ),
            // v6.11.8：WS 心跳实验（默认关；仅用于定位云端"业务空闲"回收，生产不启用）
            WxCell(
              leading: _iconTile(Icons.favorite_border, AppColors.info),
              title: 'WS 心跳实验',
              subtitle: '逐个验证哪条消息能续命云端 1005 回收（默认关，间隔 '
                  '${AppFeats.wsProbeIntervalSec}s）。切换后聊天页立即重建连接，'
                  '日志按 [PROBE] 过滤',
              trailingText: AppFeats.wsProbeLabel,
              showArrow: true,
              onTap: _pickWsProbe,
            ),
            // v6.7.0：音频能力检测（自「我」页迁入，只读展示）
            _audioCapabilitiesTile(),
            WxCell(
              leading: _iconTile(Icons.terminal, AppColors.info),
              title: '运行日志查看',
              subtitle: '复制最近 200 条运行日志，供 AI 排查故障',
              onTap: _copyLogs,
            ),
            WxCell(
              leading: _iconTile(Icons.folder_open, AppColors.info),
              title: '日志分类',
              subtitle: '按功能开关日志记录'
                  '（已开 ${LogBuffer.enabledCount}/${LogBuffer.categories.length}）',
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogCategoryPage()),
                );
                if (mounted) setState(() {});
              },
              showDivider: false,
            ),
          ]),
          // v6.7.0：原「安全」+「危险操作」合并为「管理」
          _section(isDark, '管理', [
            WxCell(
              leading: _iconTile(Icons.lock_open, AppColors.error),
              title: '清除授权',
              subtitle: '下次进开发者中心需重新输密码',
              onTap: () {
                AppFeats.setDevAuthed(false);
                ToastUtil.show('已清除授权');
                Navigator.of(context).pop();
              },
            ),
            WxCell(
              leading: _iconTile(Icons.power_settings_new, AppColors.error),
              title: '全部关闭',
              subtitle: '关闭所有开发者功能（等效普通用户模式）',
              onTap: () {
                AppFeats.allOff();
                // v6.8.0：总开关被关闭 → 取消后台周期任务（保证关闭=零唤醒）
                unawaited(ProactiveBackground.syncWithSwitch());
                setState(() {});
                ToastUtil.show('已全部关闭');
              },
              showDivider: false,
            ),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppFeats.onCount} 项开启\n小乐 AI 智能体聊天 · Version ${AppConfig.appVersion}',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption
                  .copyWith(color: AppTextStyles.tertiaryText(context)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// v6.5.0：AI 主动联系总开关——与总开关联动启停巡检服务 + 后台周期任务。
  Future<void> _toggleProactive(bool v) async {
    AppFeats.set('proactive', v);
    if (v) {
      await ProactivePollService.instance.start();
    } else {
      await ProactivePollService.instance.stop();
    }
    // v6.8.0：与总开关联动注册/取消后台周期任务（含通知权限申请）
    await ProactiveBackground.syncWithSwitch();
    if (!mounted) return;
    setState(() {});
    ToastUtil.show(v ? 'AI 主动联系 已开启' : 'AI 主动联系 已关闭');
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
    return WxCell(
      leading: _iconTile(Icons.confirmation_num_outlined, AppColors.info),
      title: '虚拟MAC地址',
      subtitleWidget: FutureBuilder<String>(
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
    return WxCell(
      leading: _iconTile(Icons.badge_outlined, AppColors.info),
      title: '虚拟Client ID',
      subtitleWidget: FutureBuilder<String>(
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
    return WxCell(
      leading: _iconTile(Icons.phone_android_outlined, AppColors.primary),
      title: '设备型号',
      subtitleWidget: FutureBuilder<String>(
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
      showDivider: false,
    );
  }

  /// v6.7.0：音频能力检测（自「我」页原样迁入，只读展示）
  Widget _audioCapabilitiesTile() {
    return FutureBuilder<Map<String, bool>>(
      future: AudioUtil.checkAudioCapabilities(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const WxCell(
            leading: Icon(Icons.graphic_eq),
            title: '音频能力检测',
            subtitle: '检测中...',
          );
        }

        final capabilities = snapshot.data ?? {};
        final aecSupported = capabilities['aecSupported'] ?? false;
        final noiseSuppress = capabilities['noiseSuppressSupported'] ?? false;
        final autoGain = capabilities['autoGainSupported'] ?? false;

        return Column(
          children: [
            WxCell(
              leading: Icon(
                aecSupported ? Icons.check_circle : Icons.cancel,
                color: aecSupported ? AppColors.primary : AppColors.error,
              ),
              title: 'AEC 回声消除',
              subtitle: aecSupported ? '支持' : '不支持',
            ),
            WxCell(
              leading: Icon(
                noiseSuppress ? Icons.check_circle : Icons.cancel,
                color: noiseSuppress ? AppColors.primary : AppColors.error,
              ),
              title: '噪声抑制',
              subtitle: noiseSuppress ? '支持' : '不支持',
            ),
            WxCell(
              leading: Icon(
                autoGain ? Icons.check_circle : Icons.cancel,
                color: autoGain ? AppColors.primary : AppColors.error,
              ),
              title: '自动增益控制',
              subtitle: autoGain ? '支持' : '不支持',
              showDivider: false,
            ),
          ],
        );
      },
    );
  }

  /// v4.4.0：AEC 通话通路开关
  /// **独立于 `AppFeats`**——`AppFeats.allOff()`（"全部关闭"＝普通用户模式）会关掉所有开关，
  /// 而 AEC 属基础收音质量而非"开发者增强功能"，不应被"全部关闭"取消，故用独立存储键。
  Widget _aecTile() {
    return WxCell(
      leading: _iconTile(Icons.headset, AppColors.primary),
      title: '通话降噪通路（AEC）',
      subtitle: '开启＝走通话音频通路以启用硬件回声消除，'
          '可消除 AI 尾音被误识别；少数机型音色略闷。下次录音/通话生效',
      trailing: Switch(
        value: AudioUtil.useAecSource,
        activeColor: AppColors.primary,
        onChanged: (v) {
          AudioUtil.setAecSource(v);
          setState(() {});
          ToastUtil.show(v
              ? '通话降噪通路已开启（下次录音生效）'
              : '通话降噪通路已关闭，恢复原录音源（下次录音生效）');
        },
      ),
      onTap: () {
        final v = !AudioUtil.useAecSource;
        AudioUtil.setAecSource(v);
        setState(() {});
        ToastUtil.show(v
            ? '通话降噪通路已开启（下次录音生效）'
            : '通话降噪通路已关闭，恢复原录音源（下次录音生效）');
      },
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
    return WxCell(
      leading: _iconTile(Icons.timer_outlined, AppColors.info),
      title: '尾音保护',
      subtitle: 'AI 说完后等待 $ms 毫秒再恢复采集（减少误识别；调大更保险）',
      onTap: () => _pickTailGuard(ms),
      showDivider: false,
    );
  }

  Future<void> _pickTailGuard(int current) async {
    double value = current.toDouble();
    final ok = await showWxDialog(
      context,
      title: '尾音保护时长',
      confirmText: '保存',
      contentWidget: StatefulBuilder(
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
              activeColor: AppColors.primary,
              onChanged: (v) => setS(() => value = v),
            ),
            const Text(
              'AI 说完后等多久再开始听你说话：调大可减少误识别，调小更灵敏',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
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

  // ===== v6.11.8：WS 心跳实验候选选择 =====

  Future<void> _pickWsProbe() async {
    const modes = <String>['off', 'hello', 'detect', 'abort', 'ping'];
    const labels = <String>[
      '关闭（生产默认）',
      '① 定时重发 hello（含 device-id/版本）',
      '② 定时 listen{state:"detect"}',
      '③ 定时 abort{reason:"heartbeat"}',
      '④ 仅保留 WS ping（对照组）',
    ];
    final idx = await showWxActionSheet(
      context,
      items: [
        for (final l in labels) WxActionSheetItem(label: l),
      ],
    );
    if (idx == null) return;
    AppFeats.setWsProbe(modes[idx]);
    if (mounted) setState(() {});
    ToastUtil.show('心跳实验：${AppFeats.wsProbeLabel}');
  }

  Future<void> _pickProactiveInterval() async {
    const opts = <int>[15, 30, 60, 120, 240];
    final idx = await showWxActionSheet(
      context,
      items: [
        for (final m in opts) WxActionSheetItem(label: '每 $m 分钟'),
      ],
    );
    if (idx == null) return;
    final picked = opts[idx];
    await ProactivePollService.instance.setIntervalMinutes(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickProactiveWindow() async {
    final w = ProactiveScriptStore.window;
    var allDay = w.allDay;
    var start = w.startMin;
    var end = w.endMin;
    final ok = await showWxDialog(
      context,
      title: '允许来电时段',
      confirmText: '保存',
      contentWidget: StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WxCell(
                title: '全天允许',
                trailing: Switch(
                  value: allDay,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setSheet(() => allDay = v),
                ),
                onTap: () => setSheet(() => allDay = !allDay),
              ),
              if (!allDay) ...[
              WxCell(
                title: '开始时间',
                trailingText: _fmtMinOfDay(start),
                onTap: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime:
                        TimeOfDay(hour: start ~/ 60, minute: start % 60),
                  );
                  if (t != null) setSheet(() => start = t.hour * 60 + t.minute);
                },
              ),
              WxCell(
                title: '结束时间',
                trailingText: _fmtMinOfDay(end),
                onTap: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                  );
                  if (t != null) setSheet(() => end = t.hour * 60 + t.minute);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('支持跨午夜（如 22:00–08:00）',
                    style: AppTextStyles.caption.copyWith(
                        color: AppTextStyles.secondaryText(context))),
              ),
            ],
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
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: AppTextStyles.secondaryText(context),
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, String key,
      {bool showDivider = true,
      IconData? icon,
      Color? iconColor,
      String? trailingText}) {
    return WxCell(
      leading: icon != null && iconColor != null
          ? _iconTile(icon, iconColor)
          : null,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(right: AppDimens.gapSm),
              child: Text(
                trailingText,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppTextStyles.secondaryText(context),
                ),
              ),
            ),
          Switch(
            value: AppFeats.get(key),
            activeColor: AppColors.primary,
            onChanged: (v) {
              AppFeats.set(key, v);
              setState(() {});
              ToastUtil.show(v ? '$title 已开启' : '$title 已关闭');
            },
          ),
        ],
      ),
      onTap: () {
        final v = !AppFeats.get(key);
        AppFeats.set(key, v);
        setState(() {});
        ToastUtil.show(v ? '$title 已开启' : '$title 已关闭');
      },
      showDivider: showDivider,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
                '共 ${_totalCount()} 项能力，逐项开关；关闭后 AI 将看不到该工具',
                style: AppTextStyles.caption.copyWith(color: sub)),
          ),
          if (!masterOn)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              ),
              child: Text(
                '总开关「MCP 设备工具」已关闭，下面各项暂不可操作。'
                '请先返回上一页开启总闸。',
                style: AppTextStyles.caption.copyWith(color: AppColors.info),
              ),
            ),
          for (final g in groups)
            _section(g.key, g.value, prim, sub, masterOn),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              '注意：闹钟 / 日程 / 短信 / 拨号 / 分享会打开系统界面，'
              '需要你确认后才真正生效（安卓的安全设计）。',
              style: AppTextStyles.captionSmall.copyWith(color: sub, height: 1.4),
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
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(title,
                style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold, color: prim)),
          ),
          Material(
            color: widget.isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.zero,
            child: Column(
              children: [
                for (var i = 0; i < tools.length; i++)
                  WxCell(
                    title: tools[i][1],
                    subtitleWidget: Text(tools[i][0],
                        style: AppTextStyles.captionSmall.copyWith(color: sub)),
                    trailing: Switch(
                      // 总闸关 → 置灰不可操作（逐项设置保留，不清除）
                      value: AppFeats.mcpToolEnabled(tools[i][0]),
                      activeColor: AppColors.primary,
                      onChanged: masterOn
                          ? (v) {
                              AppFeats.setMcpToolEnabled(tools[i][0], v);
                              setState(() {});
                            }
                          : null,
                    ),
                    onTap: masterOn
                        ? () {
                            final v = !AppFeats.mcpToolEnabled(tools[i][0]);
                            AppFeats.setMcpToolEnabled(tools[i][0], v);
                            setState(() {});
                          }
                        : null,
                    showDivider: i == tools.length - 1,
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
  final ok = await showWxDialog(
    context,
    title: '开发者模式',
    confirmText: '确定',
    contentWidget: TextField(
      controller: controller,
      obscureText: true,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
          hintText: '请输入密码', border: OutlineInputBorder()),
    ),
  );
  if (ok == true) {
    if (controller.text == AppFeats.devPassword) {
      AppFeats.setDevAuthed(true);
      ToastUtil.show('授权成功');
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DevCenterPage()),
        );
      }
    } else {
      ToastUtil.show('密码错误');
    }
  }
  controller.dispose();
}
