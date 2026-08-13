import 'dart:convert';

import '../services/database_service.dart';
import '../utils/id_utils.dart';

/// 世界书导入去重助手。
///
/// 供角色卡（.llmcard / 图片）导入、AI 转译入库等流程复用，保证行为一致：
/// 同内容的世界书只保留一份，重复导入时直接绑定到已有的那一套，
/// 而不是每次新建一份（用户诉求：同一张卡反复导入只保留一套世界书）。
class WorldBookImportHelper {
  /// 世界书内容指纹：只看世界书自身的实际内容。
  ///
  /// 与复合组件的「内容指纹」去重思路一致：同一张角色卡反复导入 → 内容
  /// 相同 → 只保留一份、重复绑定到已有那套；作者改过内容再导出 → 指纹
  /// 变了 → 作为新世界书收录。
  ///
  /// 指纹只取内容字段（名称 + 描述 + 详细设定 + 条目），不含封面、预设、
  /// 时间戳等环境/状态字段，也不含 id（导入会换新 id）。
  static String fingerprint(Map<String, dynamic> wb) {
    String normalize(Object? v) {
      if (v is String) {
        // entries_json 等 JSON 字符串，先解析再规范化（键排序），
        // 保证语义相同但字段顺序不同的条目也能匹配。
        try {
          return jsonEncode(_canonicalize(jsonDecode(v)));
        } catch (_) {
          return v.trim();
        }
      }
      return jsonEncode(_canonicalize(v));
    }

    final canon = <String, String>{
      'name': (wb['name']?.toString() ?? '').trim(),
      'description': (wb['description']?.toString() ?? '').trim(),
      'detailed_setting': (wb['detailed_setting']?.toString() ?? '').trim(),
      'entries_json': normalize(wb['entries_json']),
    };
    return jsonEncode(canon);
  }

  /// 递归规范化 JSON：Map 按键排序、列表保持顺序，方便做内容指纹比对。
  static Object? _canonicalize(Object? v) {
    if (v is Map) {
      final sorted = <String, Object?>{};
      for (final key in v.keys.toList()..sort()) {
        sorted[key.toString()] = _canonicalize(v[key]);
      }
      return sorted;
    }
    if (v is List) {
      return v.map(_canonicalize).toList();
    }
    return v;
  }

  static Future<String> _uniqueName(String baseName) async {
    final all = await DatabaseService.getAllWorldBooks();
    final names = all.map((e) => (e['name'] as String? ?? '').trim()).toSet();

    final normalized = baseName.trim().isEmpty ? '导入世界书' : baseName.trim();
    if (!names.contains(normalized)) return normalized;

    var index = 1;
    while (names.contains('$normalized ($index)')) {
      index++;
    }
    return '$normalized ($index)';
  }

  /// 把一批世界书写入库，返回「旧 id → 本库 id」映射。
  ///
  /// 内容指纹与库里已有世界书相同的直接复用（不重复导入），否则新建。
  /// 会原地修改传入的每个 worldBook 的 id / name / cover_image_path /
  /// is_preset，调用方无需再处理。
  static Future<Map<String, String>> importDeduped(
    List<Map<String, dynamic>> worldBooks,
  ) async {
    final idMap = <String, String>{};

    // 现有世界书的「内容指纹 → id」，用于导入去重。
    final existing = <String, String>{};
    for (final wb in await DatabaseService.getAllWorldBooks()) {
      existing[fingerprint(wb)] = wb['id']?.toString() ?? '';
    }

    for (int i = 0; i < worldBooks.length; i++) {
      final wb = Map<String, dynamic>.from(worldBooks[i]);

      final oldId = wb['id']?.toString() ?? '';
      if (oldId.isEmpty) continue;

      final fp = fingerprint(wb);
      final existingId = existing[fp];
      if (existingId != null && existingId.isNotEmpty) {
        // 内容相同：复用库里的那套，不重复导入。
        idMap[oldId] = existingId;
        continue;
      }

      final newId = IdUtils.timestampId(i);
      wb['id'] = newId;
      wb['name'] = await _uniqueName(wb['name']?.toString() ?? '导入世界书');
      wb['cover_image_path'] = '';
      wb['is_preset'] = 0;

      await DatabaseService.insertWorldBook(wb);

      existing[fp] = newId;
      idMap[oldId] = newId;
    }

    return idMap;
  }
}
