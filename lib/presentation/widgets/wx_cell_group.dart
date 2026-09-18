// 微信风分组（设置页/资料页统一分组容器）
// 微信规格：
//  - 灰分组标题 AppTextStyles.subtitle + secondaryText(context)，上下 padding 8，左对齐
//  - 白卡 AppTextStyles.surface(context)，圆角 8，无阴影（微信不用阴影）
//  - 左右外边距 16

import 'package:flutter/material.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

class WxCellGroup extends StatelessWidget {
  const WxCellGroup({
    super.key,
    this.title,
    required this.children,
    this.margin,
    this.radius = AppDimens.radiusMd,
  });

  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final effectiveMargin = margin ??
        const EdgeInsets.symmetric(
          horizontal: AppDimens.pagePadding,
        );

    final card = Container(
      decoration: BoxDecoration(
        color: AppTextStyles.surface(context),
        borderRadius: BorderRadius.circular(radius),
      ),
      // 微信白卡无阴影
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.pagePadding,
              right: AppDimens.pagePadding,
              top: AppDimens.sectionPaddingV,
              bottom: AppDimens.sectionPaddingV,
            ),
            child: Text(
              title!,
              style: AppTextStyles.subtitle.copyWith(
                color: AppTextStyles.secondaryText(context),
              ),
            ),
          ),
        Container(
          margin: effectiveMargin,
          child: card,
        ),
      ],
    );
  }
}
