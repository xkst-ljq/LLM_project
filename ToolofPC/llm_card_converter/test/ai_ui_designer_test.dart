import 'dart:convert';

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

  group('buildSceneFromIntent - 同页多面板不重叠', () {
    test('两个面板放同一页时纵向接续排布', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'p1', name: '主场景')],
        activePage: 'p1',
        panels: [
          UiPanel(
            kind: 'quest_list',
            page: 'p1',
            title: '任务',
            fields: const [UiFieldIntent(name: 'quest', type: 'text', display: 'text', initialValue: '采集安神草')],
          ),
          UiPanel(
            kind: 'option_bar',
            page: 'p1',
            title: '选择',
            fields: const [UiFieldIntent(name: 'option1_text', type: 'text', display: 'text', initialValue: '采集')],
          ),
        ],
        reasoning: const [],
      );

      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent,
        cardName: '测试角色',
        initialValues: const {'quest': '采集安神草', 'option1_text': '采集'},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(json['pages'] as String) as List).cast<Map<String, dynamic>>();
      final elements = (pages.first['elements'] as List).cast<Map<String, dynamic>>();

      // 找两个面板字段的 y 坐标：同一页应接续排布，不得相同（否则重叠）
      double? yOf(String name) {
        for (final e in elements) {
          final m = Map<String, dynamic>.from(e['module'] as Map);
          final props = Map<String, dynamic>.from(m['properties'] as Map);
          if (props['text'] == name) {
            final off = Map<String, dynamic>.from(e['offset'] as Map);
            return (off['y'] as num).toDouble();
          }
        }
        return null;
      }

      final yQuest = yOf('采集安神草');
      final yOption = yOf('采集');
      expect(yQuest, isNotNull);
      expect(yOption, isNotNull);
      // 第二个面板必须排在第一个面板下面（quest 文本在 option 之上）
      expect(yOption!, greaterThan(yQuest!),
          reason: '同一页两个面板应接续排布，option 面板应在 quest 面板之下');
    });
  });

  group('buildSceneFromIntent - AI 显式布局', () {
    test('AI 给定 x/y/w/h + scroll 时优先采用，滚动框不撑高 PCB', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [
          ScenePage(id: 'lobby', name: '公会大厅', pcbHeight: 800),
        ],
        activePage: 'lobby',
        panels: [
          UiPanel(
            kind: 'quest_list',
            page: 'lobby',
            title: '任务',
            fields: const [
              UiFieldIntent(
                name: 'quest', type: 'text', display: 'text',
                initialValue: '采集安神草',
                x: 14, y: 30, width: 200, height: 26, scroll: true,
              ),
              UiFieldIntent(
                name: 'desc', type: 'text', display: 'text',
                initialValue: '为药剂师采集二十株安神草。',
                x: 14, y: 60, width: 200, height: 60, scroll: true,
              ),
            ],
          ),
        ],
        reasoning: const [],
      );

      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent, cardName: '测试角色', initialValues: const {},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      expect(json['pcbHeight'], 930.0, reason: 'AI 指定页高 800 → pcb 800+130=930');
      final pages = (jsonDecode(json['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final elements = (pages.first['elements'] as List).cast<Map<String, dynamic>>();

      // 找到 desc 文本元素，验证它用了 AI 的 y/height 且是 scroll
      double? findY(String name) {
        for (final e in elements) {
          final m = Map<String, dynamic>.from(e['module'] as Map);
          if (m['name'] == name) {
            final off = Map<String, dynamic>.from(e['offset'] as Map);
            return (off['y'] as num).toDouble();
          }
        }
        return null;
      }
      // desc 用了 AI 的 y=60（而非兜底纵向游标 30+26+6=62 附近）
      expect(findY('desc'), 60.0, reason: 'AI 显式布局应覆盖兜底纵向排布');
    });

    test('AI 未给布局时仍兜底纵向排布（向后兼容）', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'p1', name: '页')],
        activePage: 'p1',
        panels: [
          UiPanel(
            kind: 'status_bar', page: 'p1', title: '状态',
            fields: const [
              UiFieldIntent(name: 'HP', type: 'number', display: 'progress', initialValue: '100'),
              UiFieldIntent(name: '名字', type: 'text', display: 'text', initialValue: '阿明'),
            ],
          ),
        ],
        reasoning: const [],
      );
      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent, cardName: '测试角色', initialValues: const {},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(json['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final elements = (pages.first['elements'] as List).cast<Map<String, dynamic>>();
      // 名字文本应在 HP 之后（兜底纵向），y 大于 250
      double? yOf(String name) {
        for (final e in elements) {
          final m = Map<String, dynamic>.from(e['module'] as Map);
          if (m['name'] == name) {
            final off = Map<String, dynamic>.from(e['offset'] as Map);
            return (off['y'] as num).toDouble();
          }
        }
        return null;
      }
      expect(yOf('名字'), isNotNull);
      expect(yOf('名字')!, greaterThan(250.0));
    });
  });

  group('buildSceneFromIntent - AI 声明外壳组件(chrome)', () {
    test('AI 声明消息流+输入+设置才放，未声明页面不放外壳', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [
          ScenePage(
            id: 'lobby', name: '公会大厅', pcbHeight: 900,
            chrome: SceneChrome(
              messageFlow: MessageFlowIntent(x: 14, y: 30, width: 332, height: 200),
              input: InputBarIntent(x: 14, y: 820, width: 284, height: 40),
              settingsButton: SettingsButtonIntent(x: 306, y: 820, width: 40, height: 40),
            ),
          ),
          ScenePage(id: 'pure', name: '纯内容页', pcbHeight: 600), // 无 chrome
        ],
        activePage: 'lobby',
        panels: const [],
        reasoning: const [],
      );
      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent, cardName: '测试角色', initialValues: const {},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(json['pages'] as String) as List)
          .cast<Map<String, dynamic>>();

      // lobby 页应有消息流、输入框、设置按钮
      Map<String, dynamic> lobbyEl = pages.firstWhere((p) => p['name'] == '公会大厅');
      final lobbyElems = (lobbyEl['elements'] as List).cast<Map<String, dynamic>>();
      final lobbyTypes = lobbyElems
          .map((e) => Map<String, dynamic>.from(e['module'] as Map)['type'])
          .toSet();
      expect(lobbyTypes, contains('message_flow'));
      expect(lobbyTypes, contains('input'));
      expect(lobbyTypes, contains('button')); // 设置

      // 纯内容页不应有消息流/输入框（外壳全由 AI 声明，未声明不放）
      final pureEl = pages.firstWhere((p) => p['name'] == '纯内容页');
      final pureTypes = (pureEl['elements'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e['module'] as Map)['type'])
          .toSet();
      expect(pureTypes, isNot(contains('message_flow')));
      expect(pureTypes, isNot(contains('input')));
    });

    test('整卡未声明设置按钮时首页兜底补一个', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [
          ScenePage(id: 'lobby', name: '公会大厅', pcbHeight: 700),
          ScenePage(id: 'p2', name: '页2', pcbHeight: 700),
        ],
        activePage: 'lobby',
        panels: const [],
        reasoning: const [],
      );
      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent, cardName: '测试角色', initialValues: const {},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(json['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final firstTypes = (pages.first['elements'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e['module'] as Map)['type'])
          .toSet();
      expect(firstTypes, contains('button'), reason: '引擎要求首页兜底设置按钮');
      expect(built.notes.any((n) => n.contains('兜底')), isTrue,
          reason: '应在 notes 说明兜底了设置按钮');
    });
  });

  group('UiVisualTheme - 风格系统', () {
    test('byName 返回对应主题，未知回落 dark', () {
      expect(UiVisualTheme.byName('parchment').pcbColor, 0xFF2A1E14);
      expect(UiVisualTheme.byName('cyber').glow, isTrue);
      expect(UiVisualTheme.byName('light').pcbColor, 0xFFF5F5F7);
      expect(UiVisualTheme.byName('unknown_style').pcbColor, UiVisualTheme.byName('dark').pcbColor);
    });

    test('defaultTheme 与 dark 一致', () {
      expect(UiVisualTheme.defaultTheme().pcbColor, UiVisualTheme.byName('dark').pcbColor);
    });
  });

  group('buildSceneFromIntent - 按钮字段渲染 surface 底板', () {
    test('display:button 的字段生成底板 surface + 点击热区', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [ScenePage(id: 'p1', name: '页')],
        activePage: 'p1',
        panels: const [
          UiPanel(
            kind: 'option_bar', page: 'p1', title: '选项',
            fields: [
              UiFieldIntent(name: 'option1_text', type: 'text', display: 'button', initialValue: '对话', x: 14, y: 30, width: 100, height: 40),
            ],
          ),
        ],
        reasoning: const [],
      );
      final built = UiAssemblyBuilder.buildSceneFromIntent(
        intent, cardName: '测试', initialValues: const {},
      );
      final json = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(json['pages'] as String) as List)
          .cast<Map<String, dynamic>>();
      final elements = (pages.first['elements'] as List).cast<Map<String, dynamic>>();
      final types = elements
          .map((e) => Map<String, dynamic>.from(e['module'] as Map)['type'])
          .toSet();
      // 应有 surface 底板（装饰）和 button 热区
      expect(types, contains('surface'));
      expect(types, contains('button'));
    });
  });

}
