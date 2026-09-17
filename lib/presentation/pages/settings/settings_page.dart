import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiaozhi_client_flutter/core/utils/audio_util.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import '../../../app/themes/app_colors.dart';
import '../../../core/providers/theme_provider.dart';
import '../../services/app_feats.dart';
import '../../widgets/profile_header.dart';
import '../cloud_sync_page.dart';
import '../dev_center_page.dart';
import '../export_chat_page.dart';
import '../privacy_policy_page.dart';
import '../user_agreement_page.dart';

/// 设置页面（v6.7.0 分层重构：纯普通用户层）
/// ------------------------------------------------------------
/// 结构：资料头 → 账号与云 → 通用（主题+音量）→ 关于（协议/隐私真实页）→ 开发者。
/// 设备身份编辑（MAC/ClientID/型号）与音频能力检测已迁入开发者中心
/// （dev_center_page.dart「设备身份」组与「调试」组）。
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
          // v6.7.0：账号与云提顶（普通用户最高频功能）
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
          // v6.7.0：原「外观」「语音」合并为「通用」
          _buildSection(
            context,
            title: '通用',
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
              // v3.2.0：TTS 播放音量滑杆（与 MCP set_volume 工具联动，同一控制点）
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
          // v6.7.0：关于组——用户协议/隐私政策由 TODO 空壳升级为真实内容页
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
                subtitle: const Text('功能介绍 · 你能获得的能力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserAgreementPage()),
                  );
                },
              ),
              ListTile(
                leading: _iconTile(Icons.privacy_tip_outlined, AppColors.error),
                title: const Text('隐私政策'),
                subtitle: const Text('权限引导 · 让 App 更好用'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                  );
                },
              ),
            ],
          ),
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
