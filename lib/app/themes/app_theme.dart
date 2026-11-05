import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'xl_tokens.dart';

/// 应用主题（微信风 · 用于 tokens.json 的 ThemeData 映射）
/// ------------------------------------------------------------
/// Material 3 关闭：避免自带抬升与胶囊圆角污染 IM 观感。
/// 深色只换色不改布局；所有语义色通过 [XlPalette] 扩展下发。
class AppTheme {
  AppTheme._();

  static ThemeData lightTheme() => _build(Brightness.light);

  static ThemeData darkTheme() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? XlPalette.dark : XlPalette.light;
    final baseText = (dark
            ? Typography.material2021(platform: TargetPlatform.android).white
            : Typography.material2021(platform: TargetPlatform.android).black)
        .apply(
      fontFamilyFallback: xlFontFallback,
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    final textTheme = baseText.copyWith(
      titleLarge: XlType.navTitle.copyWith(color: p.textPrimary),
      titleMedium: XlType.listTitle.copyWith(color: p.textPrimary),
      titleSmall: XlType.cardTitle.copyWith(color: p.textPrimary),
      bodyLarge: XlType.body.copyWith(color: p.textPrimary),
      bodyMedium: XlType.summary.copyWith(color: p.textPrimary),
      bodySmall: XlType.meta.copyWith(color: p.textSecondary),
      labelLarge: XlType.button.copyWith(color: p.textPrimary),
      labelMedium: XlType.caption.copyWith(color: p.textSecondary),
      labelSmall: XlType.tabLabel.copyWith(color: p.textSecondary),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: XlColor.brandDeep,
      brightness: brightness,
    ).copyWith(
      primary: p.brandDeep,
      onPrimary: Colors.white,
      secondary: p.brandDeep,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: p.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: brightness,
      colorScheme: scheme,
      fontFamilyFallback: xlFontFallback,
      scaffoldBackgroundColor: p.canvas,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerColor: p.hairline,
      canvasColor: p.canvas,
      cardColor: p.surface,
      disabledColor: p.textQuaternary,
      extensions: <ThemeExtension<dynamic>>[p],

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: XlDims.navHeight,
        // preview-09 实测深色导航 #1A1A1A（比画布 #111111 浅一档）
        backgroundColor: dark ? XlColorDark.nav : p.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        iconTheme: IconThemeData(color: p.textPrimary, size: 24),
        titleTextStyle: XlType.navTitle.copyWith(
          color: p.textPrimary,
          fontFamilyFallback: xlFontFallback,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(XlDims.rCard),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(XlDims.rField),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(XlDims.rField),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(XlDims.rField),
          borderSide: BorderSide(color: p.hairlineStrong, width: 1),
        ),
        hintStyle: XlType.body.copyWith(color: p.placeholder),
        labelStyle: XlType.body.copyWith(color: p.textSecondary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: p.brandDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.brandDeep.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(XlDims.rButton),
          ),
          textStyle: XlType.button,
        ),
      ),

      // 链接蓝承载"非主路径"动作（查看详情 / 复制结果）
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.link,
          textStyle: XlType.summary,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: p.brandDeep,
        foregroundColor: Colors.white,
      ),

      // 开关：轨道色跟随主题（§15 I9：深色 #3A3A3C 不写死）
      switchTheme: SwitchThemeData(
        thumbColor: const MaterialStatePropertyAll<Color>(Colors.white),
        trackColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return (dark ? XlColorDark.switchTrackOn : XlColor.switchTrackOn);
          }
          return p.switchTrackOff;
        }),
        trackOutlineColor:
            const MaterialStatePropertyAll<Color>(Colors.transparent),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(XlDims.rXl),
        ),
        titleTextStyle: XlType.navTitle.copyWith(color: p.textPrimary),
        contentTextStyle: XlType.body.copyWith(color: p.textPrimary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.canvas,
        modalBackgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(XlDims.rXl)),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: p.hairline,
        thickness: 0.5,
        space: 0.5,
      ),

      iconTheme: IconThemeData(color: p.textPrimary, size: 24),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.brandDeep,
        selectionColor: p.brandDeep.withOpacity(0.24),
        selectionHandleColor: p.brandDeep,
      ),

      // iOS 横推（不用缩放/淡入）
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF191919).withOpacity(0.86),
          borderRadius: BorderRadius.circular(XlDims.rM),
        ),
        textStyle: XlType.meta.copyWith(color: Colors.white),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? XlColorDark.subtle : Color(0xFF191919),
        contentTextStyle: XlType.summary.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(XlDims.rL),
        ),
      ),
    );
  }
}
