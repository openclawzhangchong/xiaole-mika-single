import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../app/themes/xl_tokens.dart';
import '../../services/app_feats.dart';
import '../../widgets/profile_header.dart';
import '../../widgets/wx_cell.dart';
import '../dev_center_page.dart';
import 'settings_detail_page.dart';

/// 「我」页（会话列表第 4 个 Tab）
/// 资料头 + 设置入口 + 开发者入口；设置项本身在 [SettingsDetailPage]（DESIGN screen 08）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = XlPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('我')),
      body: ListView(
        children: [
          const ProfileHeader(),
          _Group(
            children: [
              WxCell(
                title: '设置',
                showArrow: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsDetailPage(),
                    ),
                  );
                },
              ),
              WxCell(
                title: '关于',
                trailingText: AppConfig.appVersion,
                showArrow: true,
                showDivider: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsDetailPage(scrollToAbout: true),
                    ),
                  );
                },
              ),
            ],
          ),
          _Group(
            children: [
              WxCell(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              'Xiaole · ${AppConfig.appVersion}',
              textAlign: TextAlign.center,
              style: XlType.meta.copyWith(color: p.sectionLabel),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(XlDims.rL),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}
