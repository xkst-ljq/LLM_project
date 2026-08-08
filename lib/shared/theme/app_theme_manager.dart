import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// The two stable base modes for the first theme foundation.
///
/// A future automatic/system mode can be added without changing the theme
/// consumers; it only needs to resolve to one of these base modes.
enum AppThemeMode { day, night }

class AppThemeManager extends ChangeNotifier {
  AppThemeManager({AppThemeMode initialMode = AppThemeMode.day})
      : _mode = initialMode;

  static const _preferenceKey = 'app_theme_mode';

  AppThemeMode _mode;

  AppThemeMode get mode => _mode;

  bool get isNight => _mode == AppThemeMode.night;

  ThemeMode get materialThemeMode {
    return isNight ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData get theme {
    return isNight ? AppTheme.night : AppTheme.day;
  }

  /// Restore the user's choice before the first frame is rendered.
  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_preferenceKey);
      if (saved == AppThemeMode.night.name) {
        _mode = AppThemeMode.night;
      } else if (saved == AppThemeMode.day.name) {
        _mode = AppThemeMode.day;
      }
    } catch (_) {
      // A theme preference is optional; keep the safe Day default.
    }
  }

  void setMode(AppThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    unawaited(_persistMode(mode));
  }

  void toggle() {
    setMode(isNight ? AppThemeMode.day : AppThemeMode.night);
  }

  Future<void> _persistMode(AppThemeMode mode) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, mode.name);
    } catch (_) {
      // Theme switching should remain usable if persistence is unavailable.
    }
  }
}
