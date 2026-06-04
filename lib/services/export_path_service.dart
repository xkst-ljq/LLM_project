import 'package:shared_preferences/shared_preferences.dart';

enum ExportTargetType {
  backup,
  characterCard,
  backgroundCard,
  worldBook,
  knowledgeBase,
  jailbreak,
}

class ExportPathService {
  static String _keyOf(ExportTargetType type) => 'export_path_${type.name}';

  static String labelOf(ExportTargetType type) {
    switch (type) {
      case ExportTargetType.backup:
        return '完整备份';
      case ExportTargetType.characterCard:
        return '角色卡';
      case ExportTargetType.backgroundCard:
        return '背景卡';
      case ExportTargetType.worldBook:
        return '世界书';
      case ExportTargetType.knowledgeBase:
        return '知识库';
      case ExportTargetType.jailbreak:
        return '破限库';
    }
  }

  static Future<String?> getPath(ExportTargetType type) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyOf(type));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> setPath(ExportTargetType type, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOf(type), path);
  }

  static Future<void> clearPath(ExportTargetType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOf(type));
  }

  static Future<Map<ExportTargetType, String?>> getAllPaths() async {
    final result = <ExportTargetType, String?>{};
    for (final type in ExportTargetType.values) {
      result[type] = await getPath(type);
    }
    return result;
  }
}
