import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Pursee violets: the tile of the logo, a deep aubergine for the big
/// cards and buttons, and light violets for progress and selection, on a
/// soft white. Money has three fixed colours everywhere: income green,
/// expense red, transfers grey.
class K {
  static const deep = Color(0xFF1E1240);
  static const blue = Color(0xFF6D4AE8);   // the brand violet (kept as `blue` so shared widgets read the same)
  static const sky = Color(0xFF9B7BFF);
  static const glow = Color(0xFFC4B2FF);
  static const ice = Color(0xFFEFEAFF);
  static const paper = Color(0xFFF8F7FC);
  static const frame = Color(0xFFECE9F6);
  static const ink = Color(0xFF17122B);
  static const ink2 = Color(0xFF3B3557);
  static const muted = Color(0xFF6B6585);
  static const border = Color(0xFFE6E2F0);
  static const border2 = Color(0xFFD2CCE3);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF3F0FA);
  static const brand100 = Color(0xFFEEE8FE);
  static const brand200 = Color(0xFFD9CDFC);
  static const brand300 = Color(0xFFB39DF8);
  static const brand500 = Color(0xFF6D4AE8);
  static const brand600 = Color(0xFF5634C7);
  static const heroText = Color(0xFFE2D9FF);
  static const bad = Color(0xFFB42318);
  static const badBg = Color(0xFFFDECEA);
  static const warn = Color(0xFF8A5D0B);
  static const warnBg = Color(0xFFFBF1DC);

  // Money
  static const income = Color(0xFF138A5E);
  static const incomeBg = Color(0xFFE3F5EC);
  static const expense = Color(0xFFD63A4B);
  static const expenseBg = Color(0xFFFCE8EA);
  static const transfer = Color(0xFF6B6585);

  /// The colours of the pie and the category pills, in order.
  static const chart = [
    Color(0xFF6D4AE8), Color(0xFFF2994A), Color(0xFF2BB673), Color(0xFFEB5757), Color(0xFF2D9CDB),
    Color(0xFFF2C94C), Color(0xFF9B51E0), Color(0xFF27AE9F), Color(0xFFE85A9B), Color(0xFF8D6E63),
    Color(0xFF56CCF2), Color(0xFFBB6BD9), Color(0xFF6FCF97), Color(0xFFB0A8C9),
  ];

  static const rSm = 12.0;
  static const rMd = 16.0;
  static const r = 18.0;
  static const rLg = 24.0;

  static const shadow = [
    BoxShadow(color: Color(0x0A1E1240), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A1E1240), blurRadius: 24, spreadRadius: -18, offset: Offset(0, 10)),
  ];
}

/// Spacing: one scale for paddings and gaps.
class Sp {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const page = 16.0;
}

/// Text: Manrope for reading, Bricolage Grotesque for titles and big
/// numbers. Small and calm, like Kuree. No letter spacing anywhere.
class T {
  static const _m = 'Manrope';
  static const _b = 'Bricolage';

  /// Category emojis: phones and the web use their own emoji font anyway;
  /// naming this one lets the screen pictures draw emojis too.
  static const emojiFallback = ['Noto Color Emoji'];

  static const display = TextStyle(fontFamily: _b, fontFamilyFallback: emojiFallback, fontSize: 28, fontWeight: FontWeight.w600, height: 1.14, letterSpacing: 0, color: K.ink);
  static const h1 = TextStyle(fontFamily: _b, fontFamilyFallback: emojiFallback, fontSize: 23, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0, color: K.ink);
  static const h2 = TextStyle(fontFamily: _b, fontFamilyFallback: emojiFallback, fontSize: 19, fontWeight: FontWeight.w600, height: 1.24, letterSpacing: 0, color: K.ink);
  static const h3 = TextStyle(fontFamily: _b, fontFamilyFallback: emojiFallback, fontSize: 16, fontWeight: FontWeight.w600, height: 1.28, letterSpacing: 0, color: K.ink);
  static const amount = TextStyle(fontFamily: _b, fontFamilyFallback: emojiFallback, fontSize: 32, fontWeight: FontWeight.w600, height: 1.0, letterSpacing: 0,
      color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]);
  static const body = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.45, letterSpacing: 0, color: K.ink);
  static const bodyStrong = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35, letterSpacing: 0, color: K.ink);
  static const small = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0, color: K.muted);
  static const tiny = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0, color: K.muted);
  static const label = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0, color: K.ink2);
  static const button = TextStyle(fontFamily: _m, fontFamilyFallback: emojiFallback, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0);
  static const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
}

ThemeData moneeTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: K.deep,
    onPrimary: Colors.white,
    secondary: K.blue,
    onSecondary: Colors.white,
    tertiary: K.sky,
    onTertiary: Colors.white,
    error: K.bad,
    onError: Colors.white,
    surface: K.paper,
    onSurface: K.ink,
    surfaceContainerHighest: K.surface2,
    outline: K.border2,
    outlineVariant: K.border,
  );
  TextStyle m(double size, FontWeight w, [Color c = K.ink]) => TextStyle(fontFamily: 'Manrope', fontFamilyFallback: T.emojiFallback, fontSize: size, fontWeight: w, letterSpacing: 0, color: c);
  TextStyle b(double size, FontWeight w) => TextStyle(fontFamily: 'Bricolage', fontFamilyFallback: T.emojiFallback, fontSize: size, fontWeight: w, letterSpacing: 0, color: K.ink);
  final text = TextTheme(
    displayLarge: b(40, FontWeight.w600),
    displayMedium: b(34, FontWeight.w600),
    displaySmall: b(28, FontWeight.w600),
    headlineLarge: b(25, FontWeight.w600),
    headlineMedium: b(22, FontWeight.w600),
    headlineSmall: b(19, FontWeight.w600),
    titleLarge: b(17, FontWeight.w600),
    titleMedium: m(15, FontWeight.w600),
    titleSmall: m(13.5, FontWeight.w600),
    bodyLarge: m(15, FontWeight.w500),
    bodyMedium: m(14.5, FontWeight.w500),
    bodySmall: m(12.5, FontWeight.w500, K.muted),
    labelLarge: m(14, FontWeight.w600),
    labelMedium: m(12.5, FontWeight.w600),
    labelSmall: m(11, FontWeight.w600),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: K.paper,
    fontFamily: 'Manrope',
    textTheme: text,
    splashFactory: kIsWeb ? InkRipple.splashFactory : InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: K.paper,
      foregroundColor: K.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark, statusBarBrightness: Brightness.light),
      titleTextStyle: TextStyle(fontFamily: 'Bricolage', fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0, color: K.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: K.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: m(14.5, FontWeight.w500, const Color(0xFF9A93B3)),
      labelStyle: m(13.5, FontWeight.w500, K.muted),
      floatingLabelStyle: m(13.5, FontWeight.w600, K.blue),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: K.border2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: K.border2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: K.blue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: K.bad)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: K.bad, width: 1.6)),
      errorStyle: m(12, FontWeight.w500, K.bad),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: K.blue, selectionColor: K.brand200, selectionHandleColor: K.blue),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: K.deep,
      contentTextStyle: m(14, FontWeight.w500, Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    dividerTheme: const DividerThemeData(color: K.border, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: K.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      constraints: BoxConstraints(maxWidth: 640),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: K.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.rLg)),
      titleTextStyle: b(18, FontWeight.w600),
      contentTextStyle: m(14.5, FontWeight.w500, K.ink2),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: K.blue),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: K.deep, borderRadius: BorderRadius.circular(10)),
      textStyle: m(13, FontWeight.w600, Colors.white),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : K.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? K.blue : K.surface2),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? K.blue : Colors.transparent),
      side: const BorderSide(color: K.border2, width: 1.6),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
