import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';

void main() {
  group('buildOpeningFromGreetings - 选择开场白 opening 页', () {
    test('只有 1 条开场白时不生成选择页', () {
      final built = UiAssemblyBuilder.buildOpeningFromGreetings([
        {'content': '唯一开场白'},
      ]);
      expect(built, isNull, reason: '单一开场白无需选择，不生成 opening');
    });

    test('2 条开场白生成 opening 页，每个开场白一个按钮，不发送给 AI', () {
      final built = UiAssemblyBuilder.buildOpeningFromGreetings([
        {'content': '开局A：晨光中的冒险者公会……'},
        {'content': '开局B：深夜的酒馆……'},
      ], cardName: '异世界公会');

      expect(built, isNotNull);
      expect(built!.assemblies.length, 1);

      final assembly =
          Map<String, dynamic>.from(jsonDecode(built.assemblies.first) as Map);
      expect(assembly['mode'], 'opening');

      final pages = (jsonDecode(assembly['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final elements =
          (pages.first['elements'] as List).cast<Map<String, dynamic>>();

      // 每个开场白一个 button：sendsMessage 缺省（不发送）、keyAction:true、targetBranchIndex 对应该开场白下标
      final buttons = elements
          .map((e) => Map<String, dynamic>.from(e['module'] as Map))
          .where((m) => m['type'] == 'button')
          .toList();
      expect(buttons.length, 2);

      final props0 = Map<String, dynamic>.from(buttons[0]['properties'] as Map);
      expect(props0.containsKey('sendsMessage'), isFalse,
          reason: '选开场白不应发送任何文本给 AI');
      expect(props0['keyAction'], isTrue);
      expect(props0['targetBranchIndex'], 0);

      final props1 = Map<String, dynamic>.from(buttons[1]['properties'] as Map);
      expect(props1.containsKey('sendsMessage'), isFalse);
      expect(props1['keyAction'], isTrue);
      expect(props1['targetBranchIndex'], 1);
    });

    test('按钮文案取自开场白内容摘要（非数据标题）', () {
      final built = UiAssemblyBuilder.buildOpeningFromGreetings([
        {'content': '开局A：晨光中的冒险者公会'},
        {'content': '开局B：深夜的酒馆'},
      ]);
      final assembly =
          Map<String, dynamic>.from(jsonDecode(built!.assemblies.first) as Map);
      final pages = (jsonDecode(assembly['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final elements =
          (pages.first['elements'] as List).cast<Map<String, dynamic>>();
      final texts = elements
          .map((e) => Map<String, dynamic>.from(e['module'] as Map))
          .where((m) => m['type'] == 'text')
          .map((m) =>
              Map<String, dynamic>.from(m['properties'] as Map)['text'])
          .whereType<String>()
          .toList();
      expect(texts.any((t) => t.contains('开局A')), isTrue,
          reason: '按钮文案应取开场白真实内容摘要');
    });
  });
}
