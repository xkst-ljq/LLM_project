import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prompt_settings.dart';

class PromptSettingsService {
  static const String _globalKey = 'prompt_settings';

  static final ValueNotifier<int> versionNotifier = ValueNotifier<int>(0);

  static String _characterEnabledKey(String characterId) {
    return 'prompt_settings.character.$characterId.enabled';
  }

  static String _characterSettingsKey(String characterId) {
    return 'prompt_settings.character.$characterId.settings';
  }

  static void _notifyChanged() {
    versionNotifier.value++;
  }

  static PromptSettings? _decodeSettings(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PromptSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return PromptSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}

    return null;
  }

  /// 获取主菜单中的“全局默认 Prompt 策略”。
  static Future<PromptSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeSettings(prefs.getString(_globalKey)) ?? PromptSettings();
  }

  /// 保存主菜单中的“全局默认 Prompt 策略”。
  static Future<void> saveSettings(PromptSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalKey, jsonEncode(settings.toJson()));
    _notifyChanged();
  }

  static Future<void> resetGlobalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_globalKey);
    _notifyChanged();
  }

  /// 兼容旧调用名。
  static Future<void> reset() => resetGlobalSettings();

  /// 当前角色是否启用独立 Prompt 策略。
  ///
  /// 注意：没有保存过的角色默认 false，也就是使用全局默认策略。
  static Future<bool> isCharacterSettingsEnabled(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_characterEnabledKey(characterId)) ?? false;
  }

  static Future<void> setCharacterSettingsEnabled(
      String characterId,
      bool enabled,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_characterEnabledKey(characterId), enabled);
    _notifyChanged();
  }

  /// 获取某个角色自己的独立 Prompt 策略。
  ///
  /// 返回 null 表示这个角色还没有保存过独立策略。
  static Future<PromptSettings?> getCharacterSettings(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeSettings(prefs.getString(_characterSettingsKey(characterId)));
  }

  static Future<void> saveCharacterSettings(
      String characterId,
      PromptSettings settings,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _characterSettingsKey(characterId),
      jsonEncode(settings.toJson()),
    );
    _notifyChanged();
  }

  /// ChatPage 应该调用这个方法。
  ///
  /// 规则：
  /// - 没有角色：使用全局策略。
  /// - 角色未开启独立策略：使用全局策略。
  /// - 角色开启独立策略且有独立设置：使用角色设置。
  /// - 角色开启独立策略但还没保存设置：使用全局策略副本。
  static Future<PromptSettings> getEffectiveSettings(String? characterId) async {
    final globalSettings = await getSettings();

    if (characterId == null || characterId.isEmpty) {
      return globalSettings;
    }

    final enabled = await isCharacterSettingsEnabled(characterId);
    if (!enabled) {
      return globalSettings;
    }

    final characterSettings = await getCharacterSettings(characterId);
    return characterSettings ?? globalSettings.copy();
  }

  /// 可选清理：删除某个角色的独立策略状态和内容。
  static Future<void> removeCharacterSettings(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_characterEnabledKey(characterId));
    await prefs.remove(_characterSettingsKey(characterId));
    _notifyChanged();
  }
}
