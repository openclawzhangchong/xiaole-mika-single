import 'package:flutter/material.dart';
import '../../../app/themes/app_colors.dart';
import '../conversation/conversation_page.dart';
import '../settings/settings_page.dart';
import '../mika/mika_task_page.dart';

/// 主页面 - 包含底部导航栏（微信风格）
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const ConversationPage(),
    // 合并包新增：进程内 Mika 执行（不再经 adb forward / PC 网关）
    const MikaTaskPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部细分割线（微信底部栏样式）
          Container(
            height: 0.5,
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
          NavigationBar(
            height: 56,
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: '对话',
              ),
              NavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                selectedIcon: Icon(Icons.bolt),
                label: '执行',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
