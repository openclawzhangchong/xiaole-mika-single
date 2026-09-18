import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiaozhi_client_flutter/core/utils/audio_util.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import '../../../app/themes/app_colors.dart';
import '../../../app/themes/app_text_styles.dart';
import '../../../core/providers/theme_provider.dart';
import '../../widgets/wx_action_sheet.dart';
import '../../widgets/wx_cell.dart';
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
              WxCell(
                leading: _iconTile(Icons.cloud_outlined, AppColors.cloudBlue),
                title: '一键云端',
                subtitle: '聊天记录 · 智能体配置 · 三端互通',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSyncPage()),
                  );
                },
              ),
              // v4.3.0：导出本地聊天记录（方案模块三，对齐网页版 v1.3.1）
              WxCell(
                leading: _iconTile(Icons.ios_share, const Color(0xFF07C160)),
                title: '导出聊天记录',
                subtitle: 'TXT / JSON · 起止日期 · 系统分享',
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
          // v6.7.0：原「外观」「语音」合并为「通用」
          _buildSection(
            context,
            title: '通用',
            children: [
              WxCell(
                leading:
                    _iconTile(Icons.palette_outlined, const Color(0xFFFF9500)),
                title: '主题模式',
                subtitle: themeModeNotifier.getThemeModeName(),
                showArrow: true,
                onTap: () {
                  _showThemeDialog(context, ref);
                },
              ),
              // v3.2.0：TTS 播放音量滑杆（与 MCP set_volume 工具联动，同一控制点）
              StatefulBuilder(
                builder: (context, setLocal) {
                  final vol = AudioUtil.ttsVolumePercent;
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return WxCell(
                    leading: _iconTile(Icons.volume_up, const Color(0xFFFF9500)),
                    title: '说话音量',
                    showDivider: false,
                    subtitleWidget: Slider(
                      value: vol.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$vol%',
                      activeColor: AppColors.primary,
                      inactiveColor:
                          isDark ? AppColors.borderDark : AppColors.border,
                      thumbColor: AppColors.primary,
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
              WxCell(
                leading: _iconTile(Icons.info_outline, const Color(0xFF576B95)),
                title: '版本',
                subtitle: AppConfig.appVersion,
              ),
              WxCell(
                leading: _iconTile(Icons.article_outlined, const Color(0xFF576B95)),
                title: '用户协议',
                subtitle: '功能介绍 · 你能获得的能力',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserAgreementPage()),
                  );
                },
              ),
              WxCell(
                leading: _iconTile(Icons.privacy_tip_outlined, AppColors.error),
                title: '隐私政策',
                subtitle: '权限引导 · 让 App 更好用',
                showArrow: true,
                showDivider: false,
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
              WxCell(
                leading:
                    _iconTile(Icons.developer_mode, const Color(0xFF576B95)),
                title: '开发者选项',
                subtitleWidget: ValueListenableBuilder<int>(
                  valueListenable: AppFeats.onCountNotifier,
                  builder: (_, count, __) => Text('功能开关 · $count 项开启'),
                ),
                showArrow: true,
                showDivider: false,
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
              style: AppTextStyles.subtitle.copyWith(
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

  /// 显示主题选择菜单
  Future<void> _showThemeDialog(BuildContext context, WidgetRef ref) async {
    final themeModeNotifier = ref.read(themeModeProvider.notifier);
    final current = ref.read(themeModeProvider);

    final index = await showWxActionSheet(
      context,
      items: [
        WxActionSheetItem(label: '浅色', selected: current == ThemeMode.light),
        WxActionSheetItem(label: '深色', selected: current == ThemeMode.dark),
        WxActionSheetItem(
            label: '跟随系统', selected: current == ThemeMode.system),
      ],
    );
    if (!context.mounted) return;
    if (index == null) return;
    final modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    themeModeNotifier.setThemeMode(modes[index]);
  }
}
