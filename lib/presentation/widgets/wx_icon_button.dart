// 微信风按钮（替代 ElevatedButton / TextButton）
// 微信规格：
//  - 高 40
//  - filled=true → 底色 primary（danger 时用 error）、白字、圆角 4
//  - filled=false → 透明底 + 1px 同色边框 + 同色文字
//  - 文字 AppTextStyles.body(17)；水平内边距 20；按下态用 primaryPressed

import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';
import '../../app/themes/app_text_styles.dart';
import '../../app/themes/app_dimens.dart';

class WxIconButton extends StatelessWidget {
  const WxIconButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = true,
    this.icon,
    this.fullWidth = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;
  final bool fullWidth;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final mainColor = danger ? AppColors.error : AppColors.primary;

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: filled ? Colors.white : mainColor),
          const SizedBox(width: AppDimens.gapXs),
        ],
        Text(label),
      ],
    );

    if (filled) {
      return SizedBox(
        height: AppDimens.inputBarHeight - AppDimens.gapMd, // 40
        width: fullWidth ? double.infinity : null,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: mainColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: mainColor.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.gapXl),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            ),
            textStyle: AppTextStyles.body.copyWith(color: Colors.white),
            overlayColor: AppColors.primaryPressed,
          ),
          child: child,
        ),
      );
    }

    return SizedBox(
      height: AppDimens.inputBarHeight - AppDimens.gapMd, // 40
      width: fullWidth ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: mainColor,
          side: BorderSide(color: mainColor),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.gapXl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          textStyle: AppTextStyles.body.copyWith(color: mainColor),
          overlayColor: AppColors.primaryPressed.withValues(alpha: 0.12),
        ),
        child: child,
      ),
    );
  }
}
