import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Semantic design tokens shared by the app shell and experience surfaces.
///
/// Keep these values semantic rather than naming them after a hue. A role or
/// a future experience mode may provide its own accent, but ordinary widgets
/// should continue to ask for `surface`, `textPrimary`, `outline`, etc.
@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceGlass,
    required this.surfaceInteractive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.outline,
    required this.divider,
    required this.accent,
    required this.accentSoft,
    required this.accentStrong,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.focusRing,
    required this.scrim,
    required this.shadow,
    required this.imageOutline,
    required this.space1,
    required this.space2,
    required this.space3,
    required this.space4,
    required this.space5,
    required this.space6,
    required this.space7,
    required this.space8,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusPanel,
    required this.radiusPill,
    required this.elevationLow,
    required this.elevationHigh,
    required this.blurSmall,
    required this.blurLarge,
  });

  /// Warm light canvas used by the Day theme.
  const AppThemeTokens.day()
      : this(
          canvas: const Color(0xFFF4F2EE),
          surface: const Color(0xFFFFFFFF),
          surfaceElevated: const Color(0xFFFBFAF7),
          surfaceGlass: const Color(0xB8FFFFFF),
          surfaceInteractive: const Color(0xFFF0F1FA),
          textPrimary: const Color(0xFF17191D),
          textSecondary: const Color(0xFF6F747C),
          textMuted: const Color(0xFF999EA6),
          outline: const Color(0xFFD9D9D5),
          divider: const Color(0xFFE7E5E1),
          accent: const Color(0xFF5867D8),
          accentSoft: const Color(0xFFE8EAFF),
          accentStrong: const Color(0xFF3F4DB8),
          onAccent: const Color(0xFFFFFFFF),
          success: const Color(0xFF2E8B62),
          warning: const Color(0xFFB8751A),
          danger: const Color(0xFFC54848),
          info: const Color(0xFF3976B8),
          focusRing: const Color(0xFF5867D8),
          scrim: const Color(0x6B000000),
          shadow: const Color(0x24000000),
          imageOutline: const Color(0x1A000000),
          space1: 4,
          space2: 8,
          space3: 12,
          space4: 16,
          space5: 20,
          space6: 24,
          space7: 32,
          space8: 40,
          radiusSmall: 8,
          radiusMedium: 12,
          radiusLarge: 16,
          radiusPanel: 20,
          radiusPill: 999,
          elevationLow: 2,
          elevationHigh: 8,
          blurSmall: 10,
          blurLarge: 16,
        );

  /// Deep blue-black canvas used by the Night theme.
  const AppThemeTokens.night()
      : this(
          canvas: const Color(0xFF0B0E13),
          surface: const Color(0xFF131820),
          surfaceElevated: const Color(0xFF1B212B),
          surfaceGlass: const Color(0xB8131820),
          surfaceInteractive: const Color(0xFF202735),
          textPrimary: const Color(0xFFF2F4F8),
          textSecondary: const Color(0xFFA5ACB8),
          textMuted: const Color(0xFF747D8C),
          outline: const Color(0xFF303846),
          divider: const Color(0xFF242B35),
          accent: const Color(0xFF9EA9FF),
          accentSoft: const Color(0xFF282E50),
          accentStrong: const Color(0xFFC2C9FF),
          onAccent: const Color(0xFF10131A),
          success: const Color(0xFF70C79D),
          warning: const Color(0xFFF0B35A),
          danger: const Color(0xFFFF817E),
          info: const Color(0xFF80B8F0),
          focusRing: const Color(0xFFB9C0FF),
          scrim: const Color(0x85000000),
          shadow: const Color(0x66000000),
          imageOutline: const Color(0x33FFFFFF),
          space1: 4,
          space2: 8,
          space3: 12,
          space4: 16,
          space5: 20,
          space6: 24,
          space7: 32,
          space8: 40,
          radiusSmall: 8,
          radiusMedium: 12,
          radiusLarge: 16,
          radiusPanel: 20,
          radiusPill: 999,
          elevationLow: 2,
          elevationHigh: 8,
          blurSmall: 10,
          blurLarge: 16,
        );

  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceGlass;
  final Color surfaceInteractive;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color outline;
  final Color divider;

  final Color accent;
  final Color accentSoft;
  final Color accentStrong;
  final Color onAccent;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color focusRing;
  final Color scrim;
  final Color shadow;
  final Color imageOutline;

  final double space1;
  final double space2;
  final double space3;
  final double space4;
  final double space5;
  final double space6;
  final double space7;
  final double space8;

  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusPanel;
  final double radiusPill;

  final double elevationLow;
  final double elevationHigh;
  final double blurSmall;
  final double blurLarge;

  static AppThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<AppThemeTokens>() ??
        const AppThemeTokens.day();
  }

  @override
  AppThemeTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceGlass,
    Color? surfaceInteractive,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? outline,
    Color? divider,
    Color? accent,
    Color? accentSoft,
    Color? accentStrong,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? focusRing,
    Color? scrim,
    Color? shadow,
    Color? imageOutline,
    double? space1,
    double? space2,
    double? space3,
    double? space4,
    double? space5,
    double? space6,
    double? space7,
    double? space8,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusPanel,
    double? radiusPill,
    double? elevationLow,
    double? elevationHigh,
    double? blurSmall,
    double? blurLarge,
  }) {
    return AppThemeTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceInteractive: surfaceInteractive ?? this.surfaceInteractive,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      outline: outline ?? this.outline,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentStrong: accentStrong ?? this.accentStrong,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      imageOutline: imageOutline ?? this.imageOutline,
      space1: space1 ?? this.space1,
      space2: space2 ?? this.space2,
      space3: space3 ?? this.space3,
      space4: space4 ?? this.space4,
      space5: space5 ?? this.space5,
      space6: space6 ?? this.space6,
      space7: space7 ?? this.space7,
      space8: space8 ?? this.space8,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusPanel: radiusPanel ?? this.radiusPanel,
      radiusPill: radiusPill ?? this.radiusPill,
      elevationLow: elevationLow ?? this.elevationLow,
      elevationHigh: elevationHigh ?? this.elevationHigh,
      blurSmall: blurSmall ?? this.blurSmall,
      blurLarge: blurLarge ?? this.blurLarge,
    );
  }

  @override
  AppThemeTokens lerp(
    covariant AppThemeTokens? other,
    double t,
  ) {
    if (other == null) return this;

    Color color(Color a, Color b) => Color.lerp(a, b, t)!;
    double value(double a, double b) => a + (b - a) * t;

    return AppThemeTokens(
      canvas: color(canvas, other.canvas),
      surface: color(surface, other.surface),
      surfaceElevated: color(surfaceElevated, other.surfaceElevated),
      surfaceGlass: color(surfaceGlass, other.surfaceGlass),
      surfaceInteractive: color(surfaceInteractive, other.surfaceInteractive),
      textPrimary: color(textPrimary, other.textPrimary),
      textSecondary: color(textSecondary, other.textSecondary),
      textMuted: color(textMuted, other.textMuted),
      outline: color(outline, other.outline),
      divider: color(divider, other.divider),
      accent: color(accent, other.accent),
      accentSoft: color(accentSoft, other.accentSoft),
      accentStrong: color(accentStrong, other.accentStrong),
      onAccent: color(onAccent, other.onAccent),
      success: color(success, other.success),
      warning: color(warning, other.warning),
      danger: color(danger, other.danger),
      info: color(info, other.info),
      focusRing: color(focusRing, other.focusRing),
      scrim: color(scrim, other.scrim),
      shadow: color(shadow, other.shadow),
      imageOutline: color(imageOutline, other.imageOutline),
      space1: value(space1, other.space1),
      space2: value(space2, other.space2),
      space3: value(space3, other.space3),
      space4: value(space4, other.space4),
      space5: value(space5, other.space5),
      space6: value(space6, other.space6),
      space7: value(space7, other.space7),
      space8: value(space8, other.space8),
      radiusSmall: value(radiusSmall, other.radiusSmall),
      radiusMedium: value(radiusMedium, other.radiusMedium),
      radiusLarge: value(radiusLarge, other.radiusLarge),
      radiusPanel: value(radiusPanel, other.radiusPanel),
      radiusPill: value(radiusPill, other.radiusPill),
      elevationLow: value(elevationLow, other.elevationLow),
      elevationHigh: value(elevationHigh, other.elevationHigh),
      blurSmall: value(blurSmall, other.blurSmall),
      blurLarge: value(blurLarge, other.blurLarge),
    );
  }
}

extension AppThemeTokensContext on BuildContext {
  AppThemeTokens get appThemeTokens => AppThemeTokens.of(this);
}
