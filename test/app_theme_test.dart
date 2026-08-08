import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_project/shared/theme/app_theme.dart';
import 'package:llm_project/shared/theme/app_theme_tokens.dart';

void main() {
  group('AppTheme', () {
    test('provides stable Day and Night base themes', () {
      expect(AppTheme.day.brightness, Brightness.light);
      expect(AppTheme.night.brightness, Brightness.dark);
      expect(AppTheme.day.scaffoldBackgroundColor, const Color(0xFFF4F2EE));
      expect(AppTheme.night.scaffoldBackgroundColor, const Color(0xFF0B0E13));
    });

    test('exposes semantic tokens through ThemeExtension', () {
      final dayTokens = AppTheme.day.extension<AppThemeTokens>();
      final nightTokens = AppTheme.night.extension<AppThemeTokens>();

      expect(dayTokens, isNotNull);
      expect(nightTokens, isNotNull);
      expect(dayTokens!.radiusMedium, 12);
      expect(nightTokens!.radiusMedium, 12);
      expect(dayTokens.space4, 16);
      expect(nightTokens.space4, 16);
    });
  });
}
