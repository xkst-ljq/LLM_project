import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/ai_ui_designer.dart';
import 'package:llm_card_converter/core/regex_ui_extractor.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';

/// 模拟一张开场白用 <字段>值</字段> 格式的卡。
Map<String, dynamic> _xmlTagCard() => {
      'data': {
        'name': '测试角色',
        'first_mes': '<正文>欢迎来到黑曜石特区。</正文>'
            '<生命>84%</生命>'
            '<精神>72%</精神>'
            '<称号>囚犯</称号>',
        'alternate_greetings': [
          '<正文>这是开局A。</正文><生命>60%</生命><精神>90%</精神><称号>狱警</称号>',
        ],
        'extensions': {
          'regex_scripts': [
            {
              'scriptName': '状态栏',
              'findRegex': '<生命>(.*?)</生命>|<精神>(.*?)</精神>|<称号>(.*?)</称号>',
              'replaceString': '<div>状态栏</div>',
            },
          ],
        },
      },
    };

void main() {
  group('开场白数据读取', () {
    test('extractBarFieldValues 只提取 {Xxx|key:value} 格式', () {
      final v = RegexUiExtractor.extractBarFieldValues(
          '<生命>84%</生命><称号>囚犯</称号>');
      expect(v, isEmpty, reason: 'XML 标签格式不应被 extractBarFieldValues 提取');
    });

    test('branchPresets 提取 <字段>值</字段> 格式', () {
      final ex = RegexUiExtractor.extract(_xmlTagCard());
      expect(ex.branchPresets, isNotEmpty, reason: 'branchPresets 应提取 XML 标签格式');
      // 分支 0 = first_mes
      expect(ex.branchPresets[0]?['生命'], '84%');
      expect(ex.branchPresets[0]?['称号'], '囚犯');
      // 分支 1 = alternate_greetings[0]
      expect(ex.branchPresets[1]?['生命'], '60%');
    });

    test('buildSceneFromIntent 用 branchPresets 兜底填充初始值', () {
      final ex = RegexUiExtractor.extract(_xmlTagCard());

      // 构造一个 AI 意图：一个面板，字段没给 initialValue
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: [
          ScenePage(id: 'p1', name: '主场景'),
        ],
        activePage: 'p1',
        panels: [
          UiPanel(
            kind: 'status_bar',
            title: '状态',
            page: 'p1',
            fields: [
              UiFieldIntent(name: '生命', type: 'number', display: 'progress', x: 14, y: 30, width: 100, height: 14),
              UiFieldIntent(name: '称号', type: 'text', display: 'text', x: 14, y: 60, width: 100, height: 22),
            ],
          ),
        ],
        reasoning: const [],
      );

      // 模拟 pipeline 里合并 branchPresets 到 initialValues
      // （分支 0 = first_mes 优先，其它分支兜底）
      final initValues = <String, String>{};
      for (final entry in ex.branchPresets.entries) {
        if (entry.key == 0) continue;
        initValues.addAll(entry.value);
      }
      final firstMesPresets = ex.branchPresets[0];
      if (firstMesPresets != null) {
        initValues.addAll(firstMesPresets);
      }

      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent,
        cardName: '测试角色',
        initialValues: initValues,
      );

      // 验证 statusFields 里有初始值
      final lifeField = built.statusFields.firstWhere((f) => f['name'] == '生命');
      expect(lifeField['initial_value'], '84%',
          reason: '生命字段应读取到开场白里的 84%');

      final titleField = built.statusFields.firstWhere((f) => f['name'] == '称号');
      expect(titleField['initial_value'], '囚犯',
          reason: '称号字段应读取到开场白里的 囚犯');
    });
  });
}
