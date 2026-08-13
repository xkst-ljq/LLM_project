import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

/// Builds the two stable base themes for the app.
///
/// Custom themes and role experience skins should be resolved on top of these
/// values rather than replacing the app's interaction geometry wholesale.
class AppTheme {
  AppTheme._();

  static final ThemeData day = _build(
    const AppThemeTokens.day(),
    Brightness.light,
  );

  static final ThemeData night = _build(
    const AppThemeTokens.night(),
    Brightness.dark,
  );

  static ThemeData _build(
    AppThemeTokens tokens,
    Brightness brightness,
  ) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.accent,
      brightness: brightness,
    ).copyWith(
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      secondary: tokens.accentSoft,
      onSecondary: tokens.textPrimary,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      error: tokens.danger,
      onError: tokens.onAccent,
      outline: tokens.outline,
      shadow: tokens.shadow,
      scrim: tokens.scrim,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    );

    final fieldShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      borderSide: BorderSide(color: tokens.outline),
    );
    final focusedFieldShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
    );

    return base.copyWith(
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      cardColor: tokens.surface,
      dividerColor: tokens.divider,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: tokens.surfaceElevated,
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space4,
          vertical: tokens.space3,
        ),
        border: fieldShape,
        enabledBorder: fieldShape,
        focusedBorder: focusedFieldShape,
        errorBorder: fieldShape.copyWith(
          borderSide: BorderSide(color: tokens.danger),
        ),
        focusedErrorBorder: focusedFieldShape.copyWith(
          borderSide: BorderSide(color: tokens.danger, width: 1.5),
        ),
        hintStyle: TextStyle(color: tokens.textMuted),
        labelStyle: TextStyle(color: tokens.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.onAccent,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.space4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.surfaceElevated,
          foregroundColor: tokens.textPrimary,
          minimumSize: const Size(44, 44),
          elevation: tokens.elevationLow,
          padding: EdgeInsets.symmetric(horizontal: tokens.space4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            side: BorderSide(color: tokens.outline),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accentStrong,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.symmetric(horizontal: tokens.space3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        elevation: tokens.elevationHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // 半透明玻璃气泡：深浅主题都用 surfaceGlass，深色下自动变深。
        backgroundColor: tokens.surfaceGlass.withValues(alpha: 0.92),
        // 胶囊细长：窄边距 + 满圆角，让气泡细长不占空间。
        width: 320,
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        contentTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13,
          height: 1.3,
        ),
        actionTextColor: tokens.accentStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusPill),
          side: BorderSide(color: tokens.outline.withValues(alpha: 0.6)),
        ),
        elevation: tokens.elevationHigh,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        circularTrackColor: tokens.accentSoft,
        linearTrackColor: tokens.divider,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        thickness: 1,
        space: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}
