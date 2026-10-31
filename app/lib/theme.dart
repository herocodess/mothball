import 'package:flutter/material.dart';

/// Mothball's palette and type: Instrument Sans throughout, set heavier and
/// tighter for the big moments.
class MB {
  static const sans = 'Instrument Sans';

  static const ink = Color(0xFF12161C);
  static const accent = Color(0xFF2BB673);
  static const accentDeep = Color(0xFF1B7F4F);
  static const ground = Color(0xFFF5F4EF);
  static const groundDark = Color(0xFF0E1115);
  static const card = Color(0xFFFFFFFF);
  static const cardDark = Color(0xFF161A20);

  /// Display text for numbers and headlines.
  static TextStyle display(BuildContext context, double size, {Color? color, FontStyle? style}) => TextStyle(
        fontFamily: sans,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.08,
        letterSpacing: -0.035 * size,
        fontStyle: style,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  /// Quiet secondary text colour.
  static Color quiet(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  /// Hairline borders and dividers.
  static Color line(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF262C35) : const Color(0xFFE6E4DC);

  static Color cardColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardDark : card;

  /// The accent that reads well on the current background.
  static Color accentOn(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? accent : accentDeep;
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: MB.accent, brightness: b).copyWith(
    primary: dark ? MB.accent : MB.accentDeep,
    onPrimary: dark ? MB.ink : Colors.white,
    surface: dark ? MB.groundDark : MB.ground,
    onSurface: dark ? const Color(0xFFEDEEEA) : MB.ink,
    onSurfaceVariant: dark ? const Color(0xFF9AA1AB) : const Color(0xFF5E646D),
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
  );
  final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: MB.sans);
  final text = base.textTheme.apply(
    fontFamily: MB.sans,
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  const pad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  const label = TextStyle(fontFamily: MB.sans, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    splashFactory: InkSparkle.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape, padding: pad, textStyle: label, elevation: 0),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: pad,
        textStyle: label,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: dark ? const Color(0xFF2C333D) : const Color(0xFFD9D6CC)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, textStyle: label, foregroundColor: scheme.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? MB.accent : null),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : (dark ? const Color(0xFF39414C) : const Color(0xFFCFCBC0))),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: MB.accent,
      inactiveTrackColor: dark ? const Color(0xFF2A3038) : const Color(0xFFE4E1D7),
      thumbColor: dark ? Colors.white : MB.ink,
      overlayColor: MB.accent.withValues(alpha: 0.12),
      showValueIndicator: ShowValueIndicator.never,
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: const TextStyle(fontFamily: MB.sans, fontSize: 12, color: Colors.white),
      decoration: BoxDecoration(color: MB.ink.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFEDEEEA) : MB.ink,
      contentTextStyle: TextStyle(fontFamily: MB.sans, color: dark ? MB.ink : Colors.white, fontSize: 14),
      shape: shape,
      width: 520,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? MB.cardDark : MB.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(fontFamily: MB.sans, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.6, height: 1.2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
