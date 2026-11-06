import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../app/themes/xl_tokens.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/service/keep_alive_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/utils/audio_util.dart';
import '../../widgets/wx_action_sheet.dart';
import '../../widgets/wx_cell.dart';
import '../background_guide_page.dart';
import '../cloud_sync_page.dart';
import '../export_chat_page.dart';
import '../privacy_policy_page.dart';
import '../user_agreement_page.dart';

/// 设置页（DESIGN screen 08）
/// 导航 44 / 分组标题 13-666 / 行 50 / 开关轨道用令牌 / 页脚隐私事实 12-666
class SettingsDetailPage extends ConsumerStatefulWidget {
  const SettingsDetailPage({
    super.key,
    this.scrollToAbout = false,
  });

  final bool scrollToAbout;

  @override
  ConsumerState<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends ConsumerState<SettingsDetailPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToAbout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final themeName =
        ref.read(themeModeProvider.notifier).getThemeModeName();

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionLabel('账号'),
          _Group(
            children: [
              WxCell(
                title: '账号与安全',
                trailingText: '本机账号',
              ),
              WxCell(
                title: '一键云端',
                trailingText: '三端互通',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSyncPage()),
                  );
                },
              ),
              WxCell(
                title: '导出聊天记录',
                trailingText: 'TXT / JSON',
                showArrow: true,
                showDivider: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExportChatPage()),
                  );
                },
              ),
            ],
          ),

          const _SectionLabel('语音与对话'),
          _Group(
            children: [
              _AutoPlaySwitch(),
              WxCell(
                title: '唤醒词「小乐」',
                trailingText: '内置',
              ),
              WxCell(
                title: '说话音量',
                subtitleWidget: _VolumeSlider(),
                showDivider: false,
              ),
            ],
          ),

          const _SectionLabel('权限与信任'),
          _Group(
            children: [
              WxCell(
                title: '屏幕读取',
                trailingText: '仅任务期间',
              ),
              WxCell(
                title: '操作记录保留',
                trailingText: '仅本机',
              ),
              _KeepAliveSwitch(),
              _BatteryExemptCell(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '屏幕读取仅在任务执行期间开启，任务结束立即停止。',
              style: XlType.meta.copyWith(color: p.sectionLabel),
            ),
          ),

          const _SectionLabel('通用'),
          _Group(
            children: [
              WxCell(
                title: '深色模式',
                trailingText: themeName,
                showArrow: true,
                showDivider: false,
                onTap: () => _showThemeDialog(context, ref),
              ),
            ],
          ),

          const _SectionLabel('关于'),
          _Group(
            children: [
              WxCell(
                title: '隐私政策',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyPage(),
                    ),
                  );
                },
              ),
              WxCell(
                title: '用户协议',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UserAgreementPage(),
                    ),
                  );
                },
              ),
              WxCell(
                title: '版本',
                trailingText: AppConfig.appVersion,
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showThemeDialog(BuildContext context, WidgetRef ref) async {
    final themeModeNotifier = ref.read(themeModeProvider.notifier);
    final current = ref.read(themeModeProvider);

    final index = await showWxActionSheet(
      context,
      items: [
        WxActionSheetItem(label: '浅色', selected: current == ThemeMode.light),
        WxActionSheetItem(label: '深色', selected: current == ThemeMode.dark),
        WxActionSheetItem(
          label: '跟随系统',
          selected: current == ThemeMode.system,
        ),
      ],
    );
    if (!context.mounted || index == null) return;
    final modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    themeModeNotifier.setThemeMode(modes[index]);
  }
}

/// 语音回复自动播放：轨道/滑块均取令牌；关闭即 TTS 音量 0（真实生效）
class _AutoPlaySwitch extends StatefulWidget {
  @override
  State<_AutoPlaySwitch> createState() => _AutoPlaySwitchState();
}

class _AutoPlaySwitchState extends State<_AutoPlaySwitch> {
  int _restoreVolume = 70;

  bool get _on => AudioUtil.ttsVolumePercent > 0;

  void _toggle(bool value) {
    if (value) {
      final volume = _restoreVolume <= 0 ? 70 : _restoreVolume;
      AudioUtil.setTtsVolume(volume);
      StorageService.instance.setInt(AppConfig.keyTtsVolume, volume);
    } else {
      final current = AudioUtil.ttsVolumePercent;
      if (current > 0) _restoreVolume = current;
      AudioUtil.setTtsVolume(0);
      StorageService.instance.setInt(AppConfig.keyTtsVolume, 0);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WxCell(
      title: '语音回复自动播放',
      trailing: Semantics(
        label: '语音回复自动播放',
        child: Switch(
          value: _on,
          onChanged: _toggle,
        ),
      ),
    );
  }
}

/// 后台保持连接（方案 B）：打开时先要通知权限，被拒则开关回弹并提示，
/// 绝不出现"开关开着但服务没起"的状态；关掉立即停服务、撤通知。
class _KeepAliveSwitch extends StatefulWidget {
  @override
  State<_KeepAliveSwitch> createState() => _KeepAliveSwitchState();
}

class _KeepAliveSwitchState extends State<_KeepAliveSwitch> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final coordinator = KeepAliveCoordinator.instance;
    if (value) {
      // 先在前台把通知权限走完，再引导白名单（避免系统设置页抢焦点）
      final ok = await coordinator.enableWithPermission();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得通知权限，后台保持连接未开启')),
        );
      } else if (ok && mounted) {
        // 80 轮：ColorOS 会在息屏约 30s 后冻结进程，引导加入电池优化白名单
        final exempt = await KeepAliveService.batteryExempt();
        if (!exempt && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('允许小乐后台运行'),
              content: const Text(
                '小乐还不在电池优化白名单。ColorOS 会在息屏约 30 秒后冻结进程并断开连接，'
                '后台心跳会完全停止。请允许小乐忽略电池优化。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('稍后'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去允许'),
                ),
              ],
            ),
          );
          if (go == true) {
            await KeepAliveService.requestBatteryExempt();
          }
        }
      }
    } else {
      await coordinator.setEnabled(false);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return WxCell(
      title: '后台保持连接',
      subtitle: '锁屏后系统可能限制后台连接，亮屏会自动恢复；此开关管后台通知与快速恢复',
      trailing: Semantics(
        label: '后台保持连接',
        child: Switch(
          value: KeepAliveCoordinator.instance.enabled,
          onChanged: _busy ? null : _toggle,
        ),
      ),
    );
  }
}

/// 80 轮：电池优化白名单状态 + 系统授权入口（ColorOS 冻结进程的唯一可靠解法）
class _BatteryExemptCell extends StatefulWidget {
  const _BatteryExemptCell();

  @override
  State<_BatteryExemptCell> createState() => _BatteryExemptCellState();
}

class _BatteryExemptCellState extends State<_BatteryExemptCell>
    with WidgetsBindingObserver {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final v = await KeepAliveService.batteryExempt();
    if (mounted) setState(() => _exempt = v);
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackgroundGuidePage()),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = _exempt == null ? '检测中' : (_exempt! ? '已允许' : '未允许');
    return WxCell(
      title: '电池优化白名单',
      subtitle: 'ColorOS 会在息屏后冻结后台连接，需允许小乐后台运行',
      trailingText: text,
      showArrow: true,
      showDivider: false,
      onTap: _open,
    );
  }
}

class _VolumeSlider extends StatefulWidget {
  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    final vol = AudioUtil.ttsVolumePercent;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: p.brand,
        inactiveTrackColor: p.border,
        thumbColor: p.brand,
        overlayColor: p.brand.withOpacity(0.12),
      ),
      child: Slider(
        value: vol.toDouble(),
        min: 0,
        max: 100,
        divisions: 20,
        label: '$vol%',
        onChanged: (v) {
          final percent = v.round();
          AudioUtil.setTtsVolume(percent);
          StorageService.instance.setInt(AppConfig.keyTtsVolume, percent);
          setState(() {});
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 18 / 13,
          color: p.sectionLabel,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Material(
      color: p.surface,
      child: Column(children: children),
    );
  }
}
