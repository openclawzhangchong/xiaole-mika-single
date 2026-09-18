// 微信风单元格（替代 Material ListTile）
// 微信规格：
//  - 高度：无副标题 56（AppDimens.cellSingle）/ 有副标题 68（AppDimens.cellDouble），可用 minHeight 覆盖
//  - 左内边距 16；leading 与标题间距 12
//  - 标题 AppTextStyles.body + primaryText(context)；副标题 AppTextStyles.subtitle + secondaryText(context)，最多 2 行 ellipsis
//  - 右侧箭头 Icons.arrow_forward_ios size 14 色 avatarGray(#C7C7CC)
//  - 行间 0.5px 细线：height/thickness 0.5，色 AppTextStyles.divider(context)，左缩进 = 16 + leading 宽 + 12（无 leading 时为 16，可用 dividerIndent 覆盖）
//  - 有 onTap/onLongPress 时包 Material(color: transparent) + InkWell，splash/highlight 用 listPressed（深色 listPressedDark）

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

class WxCell extends StatelessWidget {
  const WxCell({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.trailingText,
    this.onTap,
    this.onLongPress,
    this.showArrow = false,
    this.showDivider = true,
    this.dividerIndent,
    this.titleTextStyle,
    this.minHeight,
  });

  final Widget? leading;
  final String? title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showArrow;
  final bool showDivider;
  final double? dividerIndent;
  final TextStyle? titleTextStyle;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null || subtitleWidget != null;
    final effectiveMinHeight = minHeight ?? (hasSubtitle ? AppDimens.cellDouble : AppDimens.cellSingle);

    final arrow = showArrow
        ? Padding(
            padding: const EdgeInsets.only(left: AppDimens.gapSm),
            child: Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.avatarGray,
            ),
          )
        : null;

    final trailingWidget = trailing ??
        (trailingText != null
            ? Text(
                trailingText!,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppTextStyles.secondaryText(context),
                ),
              )
            : null);

    final leadingSlot = leading != null
        ? Padding(
            padding: const EdgeInsets.only(right: AppDimens.gapMd),
            child: leading,
          )
        : null;

    Widget content = Container(
      constraints: BoxConstraints(minHeight: effectiveMinHeight),
      padding: const EdgeInsets.only(
        left: AppDimens.pagePadding,
        right: AppDimens.pagePadding,
      ),
      child: Row(
        children: [
          if (leadingSlot != null) leadingSlot,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: titleTextStyle ??
                        AppTextStyles.body.copyWith(
                          color: AppTextStyles.primaryText(context),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 2),
                  subtitleWidget!,
                ] else if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.subtitle.copyWith(
                      color: AppTextStyles.secondaryText(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: AppDimens.gapSm),
            trailingWidget,
          ],
          if (arrow != null) arrow,
        ],
      ),
    );

    if (onTap != null || onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: Theme.of(context).brightness == Brightness.dark
              ? AppColors.listPressedDark
              : AppColors.listPressed,
          highlightColor: Theme.of(context).brightness == Brightness.dark
              ? AppColors.listPressedDark
              : AppColors.listPressed,
          child: content,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        if (showDivider)
          Divider(
            height: AppDimens.hairline,
            thickness: AppDimens.hairline,
            indent: dividerIndent ??
                (AppDimens.pagePadding +
                    (leading != null ? (AppDimens.iconTile + AppDimens.gapMd) : 0)),
            endIndent: 0,
            color: AppTextStyles.divider(context),
          ),
      ],
    );
  }
}
