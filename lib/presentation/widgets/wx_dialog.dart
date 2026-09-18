// 微信风对话框（替代 Material AlertDialog）
// 微信规格：
//  - 宽 270，圆角 12，底色 AppTextStyles.surface(context)
//  - 标题 AppTextStyles.navTitle + primaryText(context)，居中，上内边距 24
//  - 正文 AppTextStyles.subtitle + secondaryText(context)，居中，水平内边距 16，与标题间距 8，下内边距 24
//  - 按钮区：横向平分（Expanded），上下各一条 0.5px 分割线；按钮文字 AppTextStyles.body(17) 居中
//    取消用 secondaryText(context)，确定用 AppColors.primary；danger=true 时确定用 AppColors.error
//  - showWxDialog 返回 Future<bool?>：确定 → true，取消 → false

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

class WxDialog {
  WxDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String? content,
    Widget? contentWidget,
    String cancelText = '取消',
    String confirmText = '确定',
    bool danger = false,
    bool showCancel = true,
  }) {
    return showWxDialog(
      context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      cancelText: cancelText,
      confirmText: confirmText,
      danger: danger,
      showCancel: showCancel,
    );
  }
}

Future<bool?> showWxDialog(
  BuildContext context, {
  required String title,
  String? content,
  Widget? contentWidget,
  String cancelText = '取消',
  String confirmText = '确定',
  bool danger = false,
  bool showCancel = true,
}) {
  final confirmColor = danger ? AppColors.error : AppColors.primary;

  final buttons = <Widget>[];

  if (showCancel) {
    buttons.add(
      Expanded(
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.cellSingle),
            foregroundColor: AppTextStyles.secondaryText(context),
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelText,
            style: AppTextStyles.body.copyWith(
              color: AppTextStyles.secondaryText(context),
            ),
          ),
        ),
      ),
    );
    buttons.add(
      SizedBox(
        width: AppDimens.hairline,
        height: AppDimens.cellSingle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTextStyles.divider(context),
          ),
        ),
      ),
    );
  }

  buttons.add(
    Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimens.cellSingle),
          foregroundColor: confirmColor,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          confirmText,
          style: AppTextStyles.body.copyWith(color: confirmColor),
        ),
      ),
    ),
  );

  final dialogChild = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          left: AppDimens.pagePadding,
          right: AppDimens.pagePadding,
          top: AppDimens.gapXl,
        ),
        child: Text(
          title,
          style: AppTextStyles.navTitle.copyWith(
            color: AppTextStyles.primaryText(context),
          ),
          textAlign: TextAlign.center,
        ),
      ),
      if (contentWidget != null || content != null)
        Padding(
          padding: const EdgeInsets.only(
            left: AppDimens.pagePadding,
            right: AppDimens.pagePadding,
            top: AppDimens.gapSm,
            bottom: AppDimens.gapXl,
          ),
          child: contentWidget ??
              Text(
                content!,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppTextStyles.secondaryText(context),
                ),
                textAlign: TextAlign.center,
              ),
        ),
      // 按钮区上分割线
      Divider(
        height: AppDimens.hairline,
        thickness: AppDimens.hairline,
        color: AppTextStyles.divider(context),
      ),
      Row(children: buttons),
    ],
  );

  return showDialog<bool?>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppTextStyles.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: SizedBox(
        width: 270,
        child: dialogChild,
      ),
    ),
  );
}
