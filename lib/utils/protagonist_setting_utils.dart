import 'dart:convert';
import '../models/character_card.dart';
import '../models/character_entry.dart';

class ProtagonistSettingUtils {
  static const Map<String, String> detailLabels = {
    'race': '种族',
    'gender': '性别',
    'age': '年龄',
    'body': '身体',
    'background': '背景',
  };

  static Map<String, dynamic>? getProtagonistData(CharacterCard card) {
    try {
      final rawList = jsonDecode(
        card.entriesJson.isEmpty ? '[]' : card.entriesJson,
      ) as List;

      for (final raw in rawList) {
        final map = Map<String, dynamic>.from(raw as Map);
        final entry = CharacterEntry.fromJson(map);

        if (entry.id == 'protagonist') {
          if (entry.content.trim().isEmpty) return null;

          final decoded = jsonDecode(entry.content);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}

    return null;
  }

  static String getProtagonistName(CharacterCard card) {
    final data = getProtagonistData(card);
    return data?['name']?.toString().trim() ?? '';
  }

  static Map<String, String> getProtagonistDetailMap(CharacterCard card) {
    final data = getProtagonistData(card);
    final detail = data?['detail'];

    if (detail is! Map) return {};

    final result = <String, String>{};
    for (final key in detailLabels.keys) {
      result[key] = detail[key]?.toString().trim() ?? '';
    }

    return result;
  }

  static String formatDetailTextFromMap(Map<String, String> detail) {
    final lines = <String>[];

    for (final key in detailLabels.keys) {
      final value = detail[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        lines.add('${detailLabels[key]}：$value');
      }
    }

    return lines.join('\n');
  }

  static String formatProtagonistDetail(CharacterCard card) {
    return formatDetailTextFromMap(getProtagonistDetailMap(card));
  }

  static Map<String, String> parseDetailText(String text) {
    final result = <String, String>{
      'race': '',
      'gender': '',
      'age': '',
      'body': '',
      'background': '',
    };

    final reverseLabels = {
      for (final e in detailLabels.entries) e.value: e.key,
    };

    final unknownLines = <String>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final colonIndex = line.contains('：')
          ? line.indexOf('：')
          : line.indexOf(':');

      if (colonIndex > 0) {
        final label = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        final key = reverseLabels[label];

        if (key != null) {
          result[key] = value;
        } else {
          unknownLines.add(line);
        }
      } else {
        unknownLines.add(line);
      }
    }

    // 如果用户写了无法识别的自由文本，先放进背景里，避免丢失
    if (unknownLines.isNotEmpty) {
      final oldBackground = result['background'] ?? '';
      result['background'] = [
        if (oldBackground.isNotEmpty) oldBackground,
        ...unknownLines,
      ].join('\n');
    }

    return result;
  }

  static String updateEntriesJsonWithProtagonist({
    required String entriesJson,
    required String name,
    required Map<String, String> detail,
  }) {
    List<dynamic> list;

    try {
      list = jsonDecode(entriesJson.isEmpty ? '[]' : entriesJson) as List;
    } catch (_) {
      list = [];
    }

    final content = jsonEncode({
      'name': name,
      'detail': {
        'race': detail['race'] ?? '',
        'gender': detail['gender'] ?? '',
        'age': detail['age'] ?? '',
        'body': detail['body'] ?? '',
        'background': detail['background'] ?? '',
      },
    });

    bool found = false;

    final newList = list.map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);

      if (map['id'] == 'protagonist') {
        found = true;
        map['title'] = map['title'] ?? '主角设定';
        map['content'] = content;
        map['enabled'] = true;
        map['is_custom'] = false;
        map['sort_order'] = map['sort_order'] ?? 3;
      }

      return map;
    }).toList();

    if (!found) {
      newList.add({
        'id': 'protagonist',
        'title': '主角设定',
        'content': content,
        'enabled': true,
        'is_custom': false,
        'sort_order': 3,
      });
    }

    return jsonEncode(newList);
  }
}