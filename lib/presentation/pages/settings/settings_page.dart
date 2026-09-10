import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiaozhi_client_flutter/core/utils/audio_util.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import '../../../app/themes/app_colors.dart';
import '../../../core/providers/theme_provider.dart';
import '../../services/app_feats.dart';
import '../../widgets/profile_header.dart';
import '../cloud_sync_page.dart';
import '../dev_center_page.dart';
import '../export_chat_page.dart';

/// 设置页面
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeNotifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('我')),
      body: ListView(
        children: [
          // 资料头（对齐原型 v6 的 profile-header）
          const ProfileHeader(),
          _buildSection(
            context,
            title: '设备信息',
            children: [
              ListTile(
                leading: _iconTile(Icons.confirmation_num_outlined, const Color(0xFF576B95)),
                title: const Text('虚拟MAC地址'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '编辑',
                  onPressed: () => _editDeviceField(
                    context,
                    title: '编辑虚拟MAC地址',
                    getCurrent: XiaozhiDeviceInfoUtil.instance.getDeviceMacAddress,
                    // ⚠️ MAC 强制小写：服务器 WS 侧按 device-id 查设备区分大小写，
                    // 大写 MAC 会 OTA 激活成功但连上即被静默踢线（close code=1005）
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
                  //点击复制文本
                  final macAddress = await XiaozhiDeviceInfoUtil.instance
                      .getDeviceMacAddress();
                  Clipboard.setData(ClipboardData(text: macAddress));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: _iconTile(Icons.badge_outlined, const Color(0xFF576B95)),
                title: const Text('虚拟Client ID'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '编辑',
                  onPressed: () => _editDeviceField(
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
                  final clientId = await XiaozhiDeviceInfoUtil.instance
                      .getDeviceClientId();
                  Clipboard.setData(ClipboardData(text: clientId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: _iconTile(Icons.phone_android_outlined, AppColors.primary),
                title: const Text('设备型号'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '编辑',
                  onPressed: () => _editDeviceField(
                    context,
                    title: '编辑设备型号',
                    getCurrent: XiaozhiDeviceInfoUtil.instance.getDeviceModel,
                    onSave: XiaozhiDeviceInfoUtil.instance.setDeviceModel,
                  ),
                ),
                subtitle: FutureBuilder<String>(
                  // v4.3.0：单跳只读展示（golden 稳定性：多跳矫正链会让截图在
                    // 「加载中/值」间漂移）。全局矫正入口在聊天页 initState +
                    // 添加/编辑智能体页加载设备字段两处，覆盖日常全部路径。
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
              ),
            ],
          ),
          _buildSection(
            context,
            title: '音频能力',
            children: [
              FutureBuilder<Map<String, bool>>(
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
              ),
            ],
          ),
          _buildSection(
            context,
            title: '外观',
            children: [
              ListTile(
                leading: _iconTile(Icons.palette_outlined, const Color(0xFFFF9500)),
                title: const Text('主题模式'),
                subtitle: Text(themeModeNotifier.getThemeModeName()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showThemeDialog(context, ref);
                },
              ),
            ],
          ),
          // v3.2.0：语音——TTS 播放音量滑杆（与 MCP set_volume 工具联动，同一控制点）
          _buildSection(
            context,
            title: '语音',
            children: [
              StatefulBuilder(
                builder: (context, setLocal) {
                  final vol = AudioUtil.ttsVolumePercent;
                  return ListTile(
                    leading:
                        _iconTile(Icons.volume_up, const Color(0xFFFF9500)),
                    title: const Text('说话音量'),
                    subtitle: Slider(
                      value: vol.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$vol%',
                      onChanged: (v) {
                        final p = v.round();
                        AudioUtil.setTtsVolume(p);
                        StorageService.instance
                            .setInt(AppConfig.keyTtsVolume, p);
                        setLocal(() {});
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          // v4.1.0：一键云端（复用网页版 xiaole-cloud-api + D1，三端互通）
          _buildSection(
            context,
            title: '账号与云',
            children: [
              ListTile(
                leading: _iconTile(Icons.cloud_outlined, const Color(0xFF0ABFF4)),
                title: const Text('一键云端'),
                subtitle: const Text('聊天记录 · 智能体配置 · 三端互通'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSyncPage()),
                  );
                },
              ),
              // v4.3.0：导出本地聊天记录（方案模块三，对齐网页版 v1.3.1）
              ListTile(
                leading: _iconTile(Icons.ios_share, const Color(0xFF07C160)),
                title: const Text('导出聊天记录'),
                subtitle: const Text('TXT / JSON · 起止日期 · 系统分享'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExportChatPage()),
                  );
                },
              ),
            ],
          ),
          // v4.3.0：「语言」「清除缓存」暂隐藏（均为 TODO 空壳，待开发后恢复本区）
          // _buildSection(
          //   context,
          //   title: '通用',
          //   children: [
          //     ListTile(
          //       leading: _iconTile(Icons.language, AppColors.primary),
          //       title: const Text('语言'),
          //       subtitle: const Text('简体中文'),
          //       trailing: const Icon(Icons.chevron_right),
          //       onTap: () {
          //         // TODO: 切换语言
          //       },
          //     ),
          //     ListTile(
          //       leading: _iconTile(Icons.storage, const Color(0xFF8E8E93)),
          //       title: const Text('清除缓存'),
          //       trailing: const Icon(Icons.chevron_right),
          //       onTap: () {
          //         // TODO: 清除缓存
          //       },
          //     ),
          //   ],
          // ),
          // v3.3.0：开发者中心入口（密码门在 showDevGateIfNeeded 内处理）
          _buildSection(
            context,
            title: '开发者',
            children: [
              ListTile(
                leading:
                    _iconTile(Icons.developer_mode, const Color(0xFF576B95)),
                title: const Text('开发者选项'),
                subtitle: ValueListenableBuilder<int>(
                  valueListenable: AppFeats.onCountNotifier,
                  builder: (_, count, __) => Text('功能开关 · $count 项开启'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDevGateIfNeeded(context),
              ),
            ],
          ),
          _buildSection(
            context,
            title: '关于',
            children: [
              ListTile(
                leading: _iconTile(Icons.info_outline, const Color(0xFF576B95)),
                title: const Text('版本'),
                subtitle: Text(AppConfig.appVersion),
              ),
              ListTile(
                leading: _iconTile(Icons.article_outlined, const Color(0xFF576B95)),
                title: const Text('用户协议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: 显示用户协议
                },
              ),
              ListTile(
                leading: _iconTile(Icons.privacy_tip_outlined, AppColors.error),
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: 显示隐私政策
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  /// 分组容器（微信"我"/设置页风格：灰色组标题 + 白色圆角卡片）
  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// 编辑设备身份字段（写入 SharedPreferences，连接时读取生效）
  Future<void> _editDeviceField(
    BuildContext context, {
    required String title,
    required Future<String> Function() getCurrent,
    required Future<void> Function(String) onSave,
  }) async {
    final current = await getCurrent();
    if (!context.mounted) return;
    final controller = TextEditingController(text: current);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入新值'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await onSave(controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已保存，重新进入对话后生效'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  /// 显示主题选择对话框
  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final themeModeNotifier = ref.read(themeModeProvider.notifier);
    final currentThemeMode = ref.read(themeModeProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('浅色'),
              value: ThemeMode.light,
              groupValue: currentThemeMode,
              onChanged: (value) {
                if (value != null) {
                  themeModeNotifier.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色'),
              value: ThemeMode.dark,
              groupValue: currentThemeMode,
              onChanged: (value) {
                if (value != null) {
                  themeModeNotifier.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: currentThemeMode,
              onChanged: (value) {
                if (value != null) {
                  themeModeNotifier.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
