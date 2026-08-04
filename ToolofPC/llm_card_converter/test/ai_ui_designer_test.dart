import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/ai_ui_designer.dart';
import 'package:llm_card_converter/core/regex_ui_extractor.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';

void main() {
  group('RegexUiExtractor - 提取初始值', () {
    test('extractBarFieldValues 从 {Xxx|key:value|...} 提取初始值', () {
      final values = RegexUiExtractor.extractBarFieldValues(
          '{PlayerStatus|Name:阿明|HP:100/100|MP:50/100|武器:木剑}');
      expect(values['HP'], '100'); // 去掉 /100 量程尾巴
      expect(values['MP'], '50');
      expect(values['武器'], '木剑');
      expect(values['Name'], '阿明');
    });
  });

  group('UiAssemblyBuilder - buildSceneFromIntent 初始值兜底', () {
    test('AI 未给 initialValue 时，回落到从原卡解析的初始值', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'status', name: '状态')],
        activePage: 'status',
        panels: [
          UiPanel(
            kind: 'status_bar',
            page: 'status',
            title: '状态',
            fields: const [
              UiFieldIntent(
                name: 'HP',
                type: 'number',
                display: 'progress',
                min: 0,
                max: 100,
                initialValue: '', // AI 没给
              ),
              UiFieldIntent(
                name: '武器',
                type: 'text',
                display: 'text',
                initialValue: '', // AI 没给
              ),
            ],
          ),
        ],
      );

      // 从原卡解析的初始值（HP:100/100 → 100，武器:木剑）
      final initialValues = {
        'HP': '100',
        '武器': '木剑',
      };

      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent,
        cardName: '测试角色',
        initialValues: initialValues,
      );

      // 验证 statusFields 里 HP 的初始值是 100（而非空）
      final hpField = built.statusFields.firstWhere((f) => f['name'] == 'HP');
      expect(hpField['initial_value'], '100');

      // 验证武器字段的初始值是 木剑（而非破折号）
      final weaponField =
          built.statusFields.firstWhere((f) => f['name'] == '武器');
      expect(weaponField['initial_value'], '木剑');
    });

    test('AI 给了 initialValue 时优先使用 AI 的值', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'status', name: '状态')],
        activePage: 'status',
        panels: [
          UiPanel(
            kind: 'status_bar',
            page: 'status',
            title: '状态',
            fields: const [
              UiFieldIntent(
                name: 'HP',
                type: 'number',
                display: 'progress',
                min: 0,
                max: 100,
                initialValue: '80', // AI 给了
              ),
            ],
          ),
        ],
      );

      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent,
        cardName: '测试角色',
        initialValues: {'HP': '100'}, // 原卡是 100，但 AI 给了 80
      );

      final hpField = built.statusFields.firstWhere((f) => f['name'] == 'HP');
      expect(hpField['initial_value'], '80');
    });

    test('字段名大小写不敏感匹配（AI 把"hp"改成"HP"）', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'status', name: '状态')],
        activePage: 'status',
        panels: [
          UiPanel(
            kind: 'status_bar',
            page: 'status',
            title: '状态',
            fields: const [
              UiFieldIntent(
                name: 'HP',
                type: 'number',
                display: 'progress',
                min: 0,
                max: 100,
                initialValue: '',
              ),
            ],
          ),
        ],
      );

      // 原卡字段名是小写 hp，AI 意图里是大写 HP
      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent,
        cardName: '测试角色',
        initialValues: {'hp': '100'},
      );

      final hpField = built.statusFields.firstWhere((f) => f['name'] == 'HP');
      expect(hpField['initial_value'], '100');
    });
  });

  group('extractBarFieldValues - 兼容两种块格式 + {{user}} 不截断', () {
    test('{{user}} 占位符不再截断后续字段', () {
      final v = RegexUiExtractor.extractBarFieldValues(
          '{PlayerStatus|Name:{{user}}|Level:1|XP:0/100|HP:100/100|MP:50/100|STR:10|Class:冒险者(E级)}');
      expect(v['Name'], '{{user}}');
      expect(v['Level'], '1');
      expect(v['XP'], '0'); // 去掉 /100 尾巴
      expect(v['HP'], '100');
      expect(v['MP'], '50');
      expect(v['STR'], '10');
      expect(v['Class'], '冒险者(E级)');
    });

    test('块名即首字段的 {key:val|...} 格式（quest 列表）', () {
      final v = RegexUiExtractor.extractBarFieldValues(
          '{quest:采集安神草|type:生活类|desc:为药剂师采集|reward:20银币}');
      expect(v['quest'], '采集安神草');
      expect(v['type'], '生活类');
      expect(v['desc'], '为药剂师采集');
      expect(v['reward'], '20银币');
    });

    test('同名键保留第一次出现的值', () {
      final v = RegexUiExtractor.extractBarFieldValues(
          '{quest:A|reward:10}{quest:B|reward:20}');
      expect(v['quest'], 'A');
      expect(v['reward'], '10');
    });
  });
}
