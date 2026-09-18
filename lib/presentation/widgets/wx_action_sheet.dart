// 微信风操作菜单（替代 showModalBottomSheet）
// ⚠️ 重点：微信长按菜单出现在屏幕**正中央**（非底部），故用 showGeneralDialog 居中呈现
// 微信规格：
//  - 遮罩 Colors.black alpha 0.4（Flutter 3.32 必须用 withValues(alpha: 0.4)，withOpacity 已废弃）
//  - 主体容器宽 270、圆角 12、深色 Color(0xFF4C4C4C)
//  - 选项按钮高 56，文字 AppTextStyles.body(17) 白色居中；选项间 0.5px 分割线 Colors.white24；danger 项文字用 AppColors.error
//  - 主体下方间隔 8px 放独立「取消」项：宽 270、圆角 12、白底 AppTextStyles.surface(context)、文字 17 居中 primaryText(context)
//  - 返回 Future<int?>：选中索引；取消返回 null

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

/// 操作菜单项
class WxActionSheetItem {
  const WxActionSheetItem({
    required this.label,
    this.danger = false,
    this.selected = false,
  });

  final String label;
  final bool danger;
  final bool selected;
}

Future<int?> showWxActionSheet(
  BuildContext context, {
  required List<WxActionSheetItem> items,
  String? cancelText = '取消',
}) {
  const sheetWidth = 270.0;

  Widget buildItem(WxActionSheetItem item, VoidCallback onTap) {
    final color = item.danger ? AppColors.error : Colors.white;
    return SizedBox(
      height: AppDimens.cellSingle,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimens.cellSingle),
          foregroundColor: color,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              item.label,
              style: AppTextStyles.body.copyWith(color: color),
            ),
            if (item.selected)
              const Positioned(
                left: 16,
                child: Icon(Icons.check, size: 18, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  final optionWidgets = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) {
      optionWidgets.add(
        const SizedBox(
          height: AppDimens.hairline,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white24),
          ),
        ),
      );
    }
    final index = i;
    optionWidgets.add(buildItem(items[i], () => Navigator.of(context).pop(index)));
  }

  final body = Container(
    width: sheetWidth,
    decoration: BoxDecoration(
      color: const Color(0xFF4C4C4C),
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: optionWidgets,
    ),
  );

  final children = <Widget>[body];

  if (cancelText != null) {
    children.add(
      const SizedBox(height: AppDimens.gapSm),
    );
    children.add(
      Container(
        width: sheetWidth,
        decoration: BoxDecoration(
          color: AppTextStyles.surface(context),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        child: SizedBox(
          height: AppDimens.cellSingle,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(AppDimens.cellSingle),
              foregroundColor: AppTextStyles.primaryText(context),
              shape: const RoundedRectangleBorder(),
            ),
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              cancelText,
              style: AppTextStyles.body.copyWith(
                color: AppTextStyles.primaryText(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  return showGeneralDialog<int?>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
    },
  );
}
