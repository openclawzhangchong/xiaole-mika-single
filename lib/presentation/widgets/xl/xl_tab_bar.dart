import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';

/// 底部 Tab（DESIGN §8.6 / tokens.rowHeights.tabBar）
/// 高 49 + 安全区；选中色 #0B7F40，图标 26 / 标签 10。
class XlTabItem {
  const XlTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class XlTabBar extends StatelessWidget {
  const XlTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<XlTabItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.subtle,
        border: Border(top: BorderSide(color: p.hairline, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: XlDims.tabBarHeight,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == index;
              final item = items[i];
              final color = selected ? p.tabActive : p.textSecondary;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  label: item.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 26,
                          color: color,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          maxLines: 1,
                          style: XlType.tabLabel.copyWith(color: color),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
