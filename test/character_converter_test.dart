import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_project/tools/character_converter/conversion_models.dart';
import 'package:llm_project/tools/character_converter/conversion_service.dart';
import 'package:llm_project/tools/character_converter/png_chara_reader.dart';

/// 构造一个最小 PNG，并写入 tEXt 'chara' 文本块（base64(JSON)）。
List<int> _buildPngWithChara(Map<String, dynamic> card) {
  final sig = [137, 80, 78, 71, 13, 10, 26, 10];

  List<int> u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  // CRC32（PNG 多项式 0xEDB88320）
  int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final b in bytes) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  List<int> chunk(String type, List<int> data) {
    final t = ascii.encode(type);
    final body = [...t, ...data];
    return [...u32(data.length), ...body, ...u32(crc32(body))];
  }

  final ihdr = chunk('IHDR', [
    ...u32(1), ...u32(1), // 1x1
    8, 2, 0, 0, 0, // bit depth, color type, etc.
  ]);

  final charaB64 = base64.encode(utf8.encode(jsonEncode(card)));
  final textData = [...ascii.encode('chara'), 0, ...ascii.encode(charaB64)];
  final text = chunk('tEXt', textData);

  // 用 zlib 压缩一个最小 IDAT
  final raw = [0, 255, 0, 0];
  final comp = ZLibEncoder().encode(raw);
  final idat = chunk('IDAT', comp);
  final iend = chunk('IEND', const []);

  return [...sig, ...ihdr, ...text, ...idat, ...iend];
}

Map<String, dynamic> _ariaV2() => {
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': {
        'name': 'Aria',
        'description': 'Aria 是王立学院的学生。',
        'personality': '冷淡、内向、嘴硬心软',
        'scenario': '此时正在废弃车站等你。',
        'first_mes': '……你来了。',
        'mes_example': '<START>\n{{user}}: 你好\n{{char}}: 哼。',
        'system_prompt': 'You are Aria.',
        'post_history_instructions': '保持冷淡语气。',
        'alternate_greetings': ['雨下个不停呢……', '你迟到了。'],
        'creator_notes': '推荐温度 0.9。',
        'tags': ['oc', 'tsundere'],
        'creator': 'someone',
        'character_version': '1.1',
        'character_book': {
          'name': 'Aria Lore',
          'entries': [
            {
              'keys': ['王立学院'],
              'content': '历史悠久的魔法学院。',
              'enabled': true,
              'insertion_order': 10,
              'priority': 100,
            },
            {
              'keys': ['废弃车站'],
              'content': '城郊一座荒废的车站。',
              'constant': true,
            },
          ],
        },
      },
    };

void main() {
  group('PngCharaReader', () {
    test('reads tEXt chara chunk and decodes base64 json', () {
      final png = Uint8List.fromList(_buildPngWithChara(_ariaV2()));
      expect(PngCharaReader.isPng(png), isTrue);
      final json = PngCharaReader.extractCharacterJson(png);
      expect(json, isNotNull);
      expect(json!['spec'], 'chara_card_v2');
      expect((json['data'] as Map)['name'], 'Aria');
    });
  });

  group('CharacterConversionService - V2 JSON', () {
    final result = CharacterConversionService.convertBytes(
      utf8.encode(jsonEncode(_ariaV2())),
      sourceName: 'aria.json',
    );

    test('detects format and succeeds', () {
      expect(result.success, isTrue);
      expect(result.format, ThirdPartyCardFormat.sillyTavernV2);
      expect(result.characterName, 'Aria');
    });

    test('maps core fields into entries', () {
      final entries = (jsonDecode(result.characterData!['entries_json']) as List)
          .cast<Map<String, dynamic>>();
      final byId = {for (final e in entries) e['id']: e};

      // psychology <- personality
      final psych = jsonDecode(byId['psychology']!['content']);
      expect(psych['personality'], '冷淡、内向、嘴硬心软');
      expect(byId['psychology']!['enabled'], isTrue);

      // background <- description
      final bg = jsonDecode(byId['background']!['content']);
      expect(bg['origin'], 'Aria 是王立学院的学生。');

      // scenario / mes_example custom entries
      expect(byId.containsKey('tp_scenario'), isTrue);
      expect(byId.containsKey('tp_mes_example'), isTrue);
      // raw retained
      expect(byId.containsKey('tp_raw'), isTrue);
      expect(byId['tp_raw']!['enabled'], isFalse);
    });

    test('maps greetings (first_mes + alternates)', () {
      final greetings =
          (jsonDecode(result.characterData!['opening_greetings']) as List);
      expect(greetings.length, 3);
      expect(greetings.first['content'], '……你来了。');
    });

    test('maps system_prompt', () {
      expect(result.characterData!['system_prompt'], 'You are Aria.');
    });

    test('populates meta_json (tags / creator / version / source)', () {
      final meta = jsonDecode(result.characterData!['meta_json'])
          as Map<String, dynamic>;
      expect((meta['tags'] as List), containsAll(['oc', 'tsundere']));
      expect(meta['creator'], 'someone');
      expect(meta['character_version'], '1.1');
      expect((meta['source_format'] as String).isNotEmpty, isTrue);
      expect(meta['post_history_instructions'], '保持冷淡语气。');
      expect((meta['mes_example'] as String).isNotEmpty, isTrue);
    });

    test('converts embedded character_book into a world book', () {
      expect(result.worldBooks.length, 1);
      final wb = result.worldBooks.first;
      final wbEntries = (jsonDecode(wb['entries_json']) as List);
      expect(wbEntries.length, 2);
      expect(wbEntries[1]['always_active'], isTrue); // constant -> alwaysActive
      // 角色绑定到该世界书
      expect(result.characterData!['world_book_id'], wb['id']);
    });

    test('flags advanced world book fields as downgraded', () {
      expect(result.partial, isTrue);
      expect(
        result.unsupportedFields.any((f) => f.contains('世界书高级触发规则')),
        isTrue,
      );
    });
  });

  group('CharacterConversionService - V1 JSON', () {
    test('detects tavern v1 and maps', () {
      final v1 = {
        'name': 'Bob',
        'description': '一个普通人。',
        'personality': '友善',
        'first_mes': '你好！',
        'mes_example': '示例',
      };
      final result = CharacterConversionService.convertBytes(
        utf8.encode(jsonEncode(v1)),
        sourceName: 'bob.json',
      );
      expect(result.success, isTrue);
      expect(result.format, ThirdPartyCardFormat.tavernV1);
      expect(result.characterName, 'Bob');
    });
  });

  group('CharacterConversionService - PNG card', () {
    test('reads PNG chara and converts, keeping image bytes', () {
      final png = _buildPngWithChara(_ariaV2());
      final result =
          CharacterConversionService.convertBytes(png, sourceName: 'aria.png');
      expect(result.success, isTrue);
      expect(result.format, ThirdPartyCardFormat.sillyTavernV2);
      expect(result.imageBytes, isNotNull);
      expect(result.characterName, 'Aria');
    });
  });

  group('CharacterConversionService - errors', () {
    test('llmcard (zip) is rejected with helpful message', () {
      final zip = [0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0];
      final result =
          CharacterConversionService.convertBytes(zip, sourceName: 'x.llmcard');
      expect(result.success, isFalse);
      expect(result.format, ThirdPartyCardFormat.llmProjectCard);
    });

    test('unknown content fails gracefully', () {
      final result = CharacterConversionService.convertBytes(
        utf8.encode('hello world not a card'),
        sourceName: 'note.txt',
      );
      expect(result.success, isFalse);
      expect(result.format, ThirdPartyCardFormat.unknown);
    });
  });
}
