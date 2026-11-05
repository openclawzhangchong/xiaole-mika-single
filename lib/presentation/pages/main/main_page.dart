import 'package:flutter/material.dart';

import '../../widgets/xl/xl_tab_bar.dart';
import '../conversation/conversation_page.dart';
import '../device/device_page.dart';
import '../mika/mika_task_page.dart';
import '../settings/settings_page.dart';

/// 主页面 - 底部 4 Tab（DESIGN §8.6：消息 / 任务 / 设备 / 我的）
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  static const List<XlTabItem> _tabs = <XlTabItem>[
    XlTabItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: '消息',
    ),
    XlTabItem(
      icon: Icons.checklist_outlined,
      activeIcon: Icons.checklist_rounded,
      label: '任务',
    ),
    XlTabItem(
      icon: Icons.smartphone_outlined,
      activeIcon: Icons.smartphone_rounded,
      label: '设备',
    ),
    XlTabItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: '我的',
    ),
  ];

  final List<Widget> _pages = const [
    ConversationPage(),
    // 合并包：进程内 Mika 执行（不再经 adb forward / PC 网关）
    MikaTaskPage(),
    DevicePage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: XlTabBar(
        items: _tabs,
        index: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
