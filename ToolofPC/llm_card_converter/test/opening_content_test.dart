import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/regex_ui_extractor.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';

/// 模拟一张带开场白正文 + 可点击选项的卡。
Map<String, dynamic> _cardWithOpening() => {
      'data': {
        'name': '测试角色',
        'first_mes': '<正文>欢迎来到黑曜石特区，请选择你的开局。</正文>'
            '<选项列表>'
            '<div onclick="send(\'选择1：新人入狱\')">[01] 新人入狱</div>'
            '<div onclick="send(\'选择2：狱警入职\')">[02] 狱警入职</div>'
            '</选项列表>',
        'alternate_greetings': [
          '<正文>这是开局A的正文。</正文>',
          '<正文>这是开局B的正文。</正文>',
        ],
      },
    };

/// 从 opening assembly 里取所有 text 元素的文本。
List<String> _openingTexts(BuiltAssembly built) {
  final opening = built.assemblies
      .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
      .firstWhere((a) => a['mode'] == 'opening');
  final pages = (jsonDecode(opening['pages'] as String) as List)
      .cast<Map<String, dynamic>>();
  final elements =
      (pages.first['elements'] as List).cast<Map<String, dynamic>>();
  final texts = <String>[];
  for (final e in elements) {
    final m = Map<String, dynamic>.from(e['module'] as Map);
    if (m['type'] == 'text') {
      final props = Map<String, dynamic>.from(m['properties'] as Map);
      texts.add(props['text']?.toString() ?? '');
    }
  }
  return texts;
}

void main() {
  group('开场白内容写入', () {
    test('opening 页应包含开场白正文（cleanFirstMes）', () {
      final ex = RegexUiExtractor.extract(_cardWithOpening());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试角色');

      // 确认 opening 页生成了
      final hasOpening = built.assemblies.any((s) {
        final a = Map<String, dynamic>.from(jsonDecode(s) as Map);
        return a['mode'] == 'opening';
      });
      expect(hasOpening, isTrue, reason: '有 onclick 选项时应生成 opening 页');

      final texts = _openingTexts(built);
      // 开场白正文应出现在文本里
      expect(
        texts.any((t) => t.contains('欢迎来到黑曜石特区')),
        isTrue,
        reason: '开场白正文应写入 opening 页，实际文本: $texts',
      );
    });

    test('cleanFirstMes 应提取 <正文> 内容', () {
      final ex = RegexUiExtractor.extract(_cardWithOpening());
      expect(ex.cleanFirstMes, contains('欢迎来到黑曜石特区'));
    });
  });
}
