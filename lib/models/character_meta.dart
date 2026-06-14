import 'dart:convert';

/// 角色扩展元信息。
///
/// 这是「补齐我们现在没有、酒馆有」的信息载体。统一存放在
/// characters 表的 meta_json 列里（一个 JSON 字符串），好处：
///   - 数据库只迁移一次，后续新增字段不用再动表；
///   - 备份 / 导入导出只多带一个字段；
///   - 功能可以渐进启用（数据先存好，UI / Prompt 注入按批次开放）。
///
/// 当前承载（来自第三方角色卡迁移）：
///   - tags                       角色标签
///   - creator / creatorNotes     作者 / 作者备注
///   - characterVersion           角色版本
///   - sourceFormat               来源格式（如 SillyTavern V2）
///   - postHistoryInstructions    历史之后注入指令（我们暂无注入位，先保留）
///   - mesExample                 对话示例（暂以条目承载，这里也保留原文）
class CharacterMeta {
  List<String> tags;
  String creator;
  String creatorNotes;
  String characterVersion;
  String sourceFormat;
  String postHistoryInstructions;
  String mesExample;

  CharacterMeta({
    List<String>? tags,
    this.creator = '',
    this.creatorNotes = '',
    this.characterVersion = '',
    this.sourceFormat = '',
    this.postHistoryInstructions = '',
    this.mesExample = '',
  }) : tags = tags ?? <String>[];

  bool get isEmpty =>
      tags.isEmpty &&
      creator.trim().isEmpty &&
      creatorNotes.trim().isEmpty &&
      characterVersion.trim().isEmpty &&
      sourceFormat.trim().isEmpty &&
      postHistoryInstructions.trim().isEmpty &&
      mesExample.trim().isEmpty;

  factory CharacterMeta.fromJson(Map<String, dynamic> json) {
    List<String> readTags(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return <String>[];
    }

    return CharacterMeta(
      tags: readTags(json['tags']),
      creator: json['creator']?.toString() ?? '',
      creatorNotes: json['creator_notes']?.toString() ?? '',
      characterVersion: json['character_version']?.toString() ?? '',
      sourceFormat: json['source_format']?.toString() ?? '',
      postHistoryInstructions:
          json['post_history_instructions']?.toString() ?? '',
      mesExample: json['mes_example']?.toString() ?? '',
    );
  }

  /// 从 meta_json 字符串解析（容错：空 / 损坏都回退为空 meta）。
  factory CharacterMeta.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return CharacterMeta();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CharacterMeta.fromJson(decoded);
      }
      if (decoded is Map) {
        return CharacterMeta.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return CharacterMeta();
  }

  Map<String, dynamic> toJson() {
    return {
      'tags': tags,
      'creator': creator,
      'creator_notes': creatorNotes,
      'character_version': characterVersion,
      'source_format': sourceFormat,
      'post_history_instructions': postHistoryInstructions,
      'mes_example': mesExample,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  CharacterMeta copy() => CharacterMeta.fromJson(toJson());
}
