// 微信风空态 / 错误态统一组件
// 微信规格：
//  - 图标 size 72、色 navBarUnselected（深色 navBarUnselectedDark）
//  - 标题 AppTextStyles.body(17) + secondaryText(context)
//  - 描述 AppTextStyles.subtitle(14) + secondaryText(context)
//  - 间距：图标→标题 16、标题→描述 8、描述→按钮 24
//  - actionLabel 非空时在本文件**内联**一个文字按钮（AppColors.primary、AppTextStyles.body、无边框、onTap 触发 onAction）
//    —— 不 import wx_icon_button，避免循环依赖

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

class WxEmpty extends StatelessWidget {
  const WxEmpty({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconSize = 72,
  });

  final IconData? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.navBarUnselectedDark
        : AppColors.navBarUnselected;

    final children = <Widget>[];

    if (icon != null) {
      children.add(
        Icon(
          icon,
          size: iconSize,
          color: iconColor,
        ),
      );
      children.add(const SizedBox(height: AppDimens.gapLg)); // 16
    }

    children.add(
      Text(
        title,
        style: AppTextStyles.body.copyWith(
          color: AppTextStyles.secondaryText(context),
        ),
        textAlign: TextAlign.center,
      ),
    );

    if (description != null) {
      children.add(const SizedBox(height: AppDimens.gapSm)); // 8
      children.add(
        Text(
          description!,
          style: AppTextStyles.subtitle.copyWith(
            color: AppTextStyles.secondaryText(context),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (actionLabel != null && actionLabel!.isNotEmpty) {
      children.add(const SizedBox(height: AppDimens.gapXl)); // 24
      children.add(
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: onAction,
          child: Text(
            actionLabel!,
            style: AppTextStyles.body.copyWith(color: AppColors.primary),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}
