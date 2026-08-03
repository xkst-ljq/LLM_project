import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/regex_ui_extractor.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';

/// 模拟一张「first_mes 是引导页、alternate_greetings 是各开局分支」的卡。
///
/// 结构对应黑曜石·法外特区：引导页里的 `onclick="send('...')"` 选项
/// 各自指向一条备用开场白（分支）。
Map<String, dynamic> _branchCard() => {
      'data': {
        'name': '测试',
        'first_mes': '<正文>请选择你的开局</正文>'
            '<选项列表>'
            '<div onclick="send(\'选择1：开局A\')">[01] 开局A</div>'
            '<div onclick="send(\'选择2：开局B\')">[02] 开局B</div>'
            '</选项列表>',
        'alternate_greetings': [
        ],
      },
    };

/// 从构建产物里取 opening assembly 的所有按钮 properties。
List<Map<String, dynamic>> _openingButtons(BuiltAssembly built) {
  final opening = built.assemblies
      .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
      .firstWhere((a) => a['mode'] == 'opening');
  final pages = (jsonDecode(opening['pages'] as String) as List)
      .cast<Map<String, dynamic>>();
  final elements =
      (pages.first['elements'] as List).cast<Map<String, dynamic>>();
  final buttons = <Map<String, dynamic>>[];
  for (final e in elements) {
    final m = Map<String, dynamic>.from(e['module'] as Map);
    if (m['type'] == 'button') {
      buttons.add(Map<String, dynamic>.from(m['properties'] as Map));
    }
  }
  return buttons;
}

void main() {
  group('UiAssemblyBuilder - opening 分支映射', () {
    test('opening 选项 targetBranchIndex 从 1 起，指向 alternate_greetings', () {
      final ex = RegexUiExtractor.extract(_branchCard());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试');

      final buttons = _openingButtons(built);
      expect(buttons.length, 2);

      // 选项 1 → 分支 1（第一条 alternate_greeting）
      expect(buttons[0]['text'], '选择1：开局A');
      expect(buttons[0]['targetBranchIndex'], 1);
      // 选项 2 → 分支 2（第二条 alternate_greeting）
      expect(buttons[1]['text'], '选择2：开局B');
      expect(buttons[1]['targetBranchIndex'], 2);
    });

    test('opening 选项同时带 sendsMessage + keyAction（点击即发送并切分支）', () {
      final ex = RegexUiExtractor.extract(_branchCard());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试');
      final buttons = _openingButtons(built);

      expect(buttons[0]['sendsMessage'], isTrue);
      expect(buttons[0]['keyAction'], isTrue);
    });
  });
}
