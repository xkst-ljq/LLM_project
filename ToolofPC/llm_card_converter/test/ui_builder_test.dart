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
          '<正文>这是开局A的正文。</正文>\n'
              '<选项>\n'
              '1.🤐【保持沉默】默不作声地按照指示上前。\n'
              '2.🤝【尝试交涉】趁上前扫过登记台。\n'
              '</选项>',
          '<正文>这是开局B的正文。</正文>\n'
              '<选项>\n'
              '1.🌟【职业化应对】握紧装备默默跟上。\n'
              '2.🧭【察言观色】跟随队长前行。\n'
              '</选项>',
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

  group('RegexUiExtractor - 分支动作提取', () {
    test('从各 alternate_greetings 的 <选项> 提取动作列表', () {
      final ex = RegexUiExtractor.extract(_branchCard());

      expect(ex.branchActions.length, 2);
      expect(ex.branchActions[1]!.length, 2);
      expect(ex.branchActions[2]!.length, 2);

      final a0 = ex.branchActions[1]!.first;
      expect(a0.raw, contains('保持沉默'));
      expect(a0.label, '保持沉默');
      expect(a0.sendText, a0.raw);
    });
  });

  group('UiAssemblyBuilder - 分支动作区', () {
    test('动作区生成 status field，branch_initial_values 存各分支动作', () {
      final ex = RegexUiExtractor.extract(_branchCard());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试');

      final actionFields = built.statusFields
          .where((f) => f['id'].toString().startsWith('sf_act_'))
          .toList();
      expect(actionFields.length, 2);

      final f1 = actionFields[0];
      expect(f1['type'], 'text');
      final branchVals = (f1['branch_initial_values'] as Map?);
      expect(branchVals, isNotNull);
      expect(branchVals!['1'].toString(), contains('保持沉默'));
      expect(branchVals['2'].toString(), contains('职业化应对'));
    });

    test('动作生成叠加层 overlay 页，确认按钮 sendsMessage', () {
      final ex = RegexUiExtractor.extract(_branchCard());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试');

      final companion = built.assemblies
          .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
          .firstWhere((a) => a['mode'] == 'extra_companion');
      final pages = (jsonDecode(companion['pages'] as String) as List)
          .cast<Map<String, dynamic>>();

      // 应为：属性页 + 档案页 + 2 个动作叠加层页
      final overlays =
          pages.where((p) => p['type'] == 'overlay').toList();
      expect(overlays.length, 2);

      // 每个叠加层有 parentPageId，且含 sendsMessage 的确认按钮
      for (final ov in overlays) {
        expect(ov['parentPageId'], isNotNull);
        var confirmFound = false;
        for (final e in (ov['elements'] as List).cast<Map<String, dynamic>>()) {
          final m = Map<String, dynamic>.from(e['module'] as Map);
          if (m['type'] == 'button') {
            final props = Map<String, dynamic>.from(m['properties'] as Map);
            if (props['sendsMessage'] == true) confirmFound = true;
          }
        }
        expect(confirmFound, isTrue, reason: '叠加层应有确认发送按钮');
      }
    });

    test('属性页动作按钮不直接发送，而是打开叠加层', () {
      final ex = RegexUiExtractor.extract(_branchCard());
      final built = UiAssemblyBuilder.build(ex, cardName: '测试');

      final companion = built.assemblies
          .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
          .firstWhere((a) => a['mode'] == 'extra_companion');
      final pages = (jsonDecode(companion['pages'] as String) as List)
          .cast<Map<String, dynamic>>();

      // 属性页（第一个 base 页）里的动作按钮（动作_1/动作_2）
      // 不应带 sendsMessage（点击只打开叠加层，不直接发送）
      final basePages = pages.where((p) => p['type'] == 'base').toList();
      final attrPage = basePages.firstWhere((p) => p['name'] == '属性');
      for (final e in (attrPage['elements'] as List).cast<Map<String, dynamic>>()) {
        final m = Map<String, dynamic>.from(e['module'] as Map);
        if (m['type'] == 'button' &&
            (m['name'] ?? '').toString().startsWith('动作_')) {
          final props = Map<String, dynamic>.from(m['properties'] as Map);
          expect(props['sendsMessage'] ?? false, isFalse);
        }
      }
    });
  });
}
