import 'dart:convert';
import 'package:llm_project/models/world_book_entry.dart';

class WorldBook {
  final String id;
  String name;
  String description;
  String detailedSetting;   // 保留兼容
  String entriesJson;        // 新增：JSON 序列化的条目列表
  String coverImagePath;
  bool isPreset;

  WorldBook({
    required this.id,
    required this.name,
    this.description = '',
    this.detailedSetting = '',
    this.entriesJson = '[]',  // 默认空数组
    this.coverImagePath = '',
    this.isPreset = false,
  });

  // 条目反序列化辅助
  List<WorldBookEntry> get entries {
    try {
      final list = jsonDecode(entriesJson) as List;
      return list.map((e) => WorldBookEntry.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  factory WorldBook.fromDb(Map<String, dynamic> data) {
    return WorldBook(
      id: data['id'] as String,
      name: data['name'] as String,
      description: data['description'] as String? ?? '',
      detailedSetting: data['detailed_setting'] as String? ?? '',
      entriesJson: data['entries_json'] as String? ?? '[]',
      coverImagePath: data['cover_image_path'] as String? ?? '',
      isPreset: (data['is_preset'] as int?) == 1,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'detailed_setting': detailedSetting,
      'entries_json': entriesJson,
      'cover_image_path': coverImagePath,
      'is_preset': isPreset ? 1 : 0,
    };
  }
}