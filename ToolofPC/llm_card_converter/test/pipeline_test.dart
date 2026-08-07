import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/conversion_models.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';
import 'package:llm_card_converter/core/ui_engine_api/ui_engine_api_dictionary.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_design_plan.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_source_pack_builder.dart';
import 'package:llm_card_converter/pipeline/pipeline.dart';

Map<String, dynamic> _ariaV2() => {
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': {
        'name': 'Aria',
        'description': 'Aria 是王立学院的学生，性格冷淡。',
        'personality': '冷淡',
        'first_mes': '……你来了。',
      },
    };

void main() {
  group('ConversionPipeline - stage1 (rule)', () {
    test('runs offline and produces a card', () {
      final pipeline = ConversionPipeline(); // 不注入 AI
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );

      final result = pipeline.runRuleStage(item);
      expect(result.success, isTrue);
      expect(item.stageStatus[PipelineStage.rule], StageStatus.done);
      expect(item.current, isNotNull);
      expect(item.current!.characterName, 'Aria');
    });

    test('extracts source json from tp_raw for later stages', () {
      final pipeline = ConversionPipeline();
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      pipeline.runRuleStage(item);
      expect(item.sourceJson, isNotNull);
      // 源 JSON 应能取回 name
      final data = (item.sourceJson!['data'] ?? item.sourceJson!) as Map;
      expect(data['name'], 'Aria');
    });
  });

  group('ConversionPipeline - AI stages gating', () {
    test('aiClassify throws when not configured', () async {
      final pipeline = ConversionPipeline();
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      pipeline.runRuleStage(item);
      expect(
        () => pipeline.runAiClassifyStage(item),
        throwsStateError,
      );
    });

    test('aiClassify runs with injected fn and updates current', () async {
      // 注入一个假的 AI：把角色名改成 Aria(AI) 以验证链路
      final pipeline = ConversionPipeline(
        aiClassify: (ruleResult, sourceJson) async {
          final data = Map<String, dynamic>.from(ruleResult.characterData!);
          data['name'] = 'Aria(AI)';
          return CardConversionResult(
            sourceName: ruleResult.sourceName,
            format: ruleResult.format,
            success: true,
            characterData: data,
            worldBooks: ruleResult.worldBooks,
            imageBytes: ruleResult.imageBytes,
          );
        },
      );
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      pipeline.runRuleStage(item);
      final out = await pipeline.runAiClassifyStage(item);
      expect(out.success, isTrue);
      expect(out.characterName, 'Aria(AI)');
      // current 应优先返回更后阶段（AI）的结果
      expect(item.current!.characterName, 'Aria(AI)');
    });
  });

  group('ConversionPipeline - refine stage', () {
    test('produces issue list via injected fn', () async {
      final pipeline = ConversionPipeline(
        aiRefine: (current, sourceJson) async {
          return [
            RefineIssue(
              type: RefineIssueType.missing,
              fields: const ['background.origin'],
              text: '她害怕雷声',
              suggestion: '原文提到但未转入，建议补到背景。',
              confidence: 0.8,
            ),
          ];
        },
      );
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      pipeline.runRuleStage(item);
      final issues = await pipeline.runRefineStage(item);
      expect(issues.length, 1);
      expect(issues.first.type, RefineIssueType.missing);
      expect(item.stageStatus[PipelineStage.refine], StageStatus.done);
    });
  });

  group('ConversionPipeline - runAll skips missing AI stages', () {
    test('rule done, ai stages skipped when not configured', () async {
      final pipeline = ConversionPipeline();
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      await pipeline.runAll(item);
      expect(item.stageStatus[PipelineStage.rule], StageStatus.done);
      expect(item.stageStatus[PipelineStage.aiClassify], StageStatus.skipped);
      expect(item.stageStatus[PipelineStage.refine], StageStatus.skipped);
    });
  });

  group('UIEngine API dictionary', () {
    test('exposes component and mode details for translator lookup', () {
      expect(UiEngineApiDictionary.lookup('components.text.properties.overflow'), isNotNull);
      expect(UiEngineApiDictionary.lookup('components.message_flow.properties.historyLimit'), isNotNull);
      expect(UiEngineApiDictionary.lookup('modes.scene.keyActionMeaning'), contains('聊天设置'));
      expect(UiEngineApiDictionary.component('base_box'), isNotNull);
      expect(UiEngineApiDictionary.compactIndexMarkdown(), contains('components.text'));
    });
  });

  group('UI source pack', () {
    test('filters quest schema templates from initial quest summaries', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': 'QuestCard',
          'first_mes': '{quest:采集安神草|type:生活类|desc:采集二十株|diff:E级|client:赫尔曼|reward:20银币|location:森林|time:无|equip:无|risk:史莱姆|note:蓝紫色小花}',
          'character_book': {
            'entries': [
              {
                'comment': '任务界面',
                'content': '{quest:任务名称|type:任务类型|desc:任务描述|diff:难度等级|client:委托人姓名|reward:任务报酬|location:任务地点|time:时间限制|equip:推荐装备|risk:潜在风险|note:特别说明}',
              },
            ],
          },
        },
      });

      expect(pack.questSummaries.map((q) => q.name), contains('采集安神草'));
      expect(pack.questSummaries.map((q) => q.name), isNot(contains('任务名称')));
    });
  });

  group('AI UI plan compiler', () {
    test('compiles UiDesignPlan into assembly JSON and status fields', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'extra_companion',
        'uiName': '状态面板',
        'evidenceSummary': '测试证据',
        'sourceRefs': ['data.first_mes'],
        'visualStyle': {
          'pcbColor': '#111318',
          'panelColor': '#1E232B',
          'titleColor': '#FFFFFF',
          'labelColor': '#AAB0BC',
          'valueColor': '#E8EDF5',
          'accentColor': '#4FA3D1',
          'buttonBgColor': '#2A3340',
          'barFillColor': '#4FA3D1',
          'barTrackColor': '#2A2D36',
          'borderRadius': 14,
          'glow': false,
        },
        'layout': {
          'kind': 'tabbed_companion_panel',
          'pages': [
            {'title': '属性', 'role': 'stats'},
            {'title': '选项', 'role': 'actions'},
          ],
        },
        'fields': [
          {
            'name': '生命',
            'type': 'number',
            'display': 'progress',
            'initialValue': '84',
            'min': 0,
            'max': 100,
            'owner': 'player',
            'page': '属性',
            'sourceRef': 'data.first_mes:<生命>84%</生命>',
          },
        ],
        'actions': [
          {
            'label': '继续',
            'sendText': '继续',
            'branchIndex': 0,
            'page': '选项',
            'sourceRef': 'data.first_mes onclick send',
          },
        ],
        'unsupported': [],
        'notes': [],
      });

      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      expect(built.isEmpty, isFalse);
      expect(built.statusFields, hasLength(1));
      expect(built.statusFields.first['name'], '生命');

      final assembly = jsonDecode(built.assemblies.first) as Map;
      expect(assembly['mode'], 'extra_companion');
      expect(assembly['elements'], '[]');
      final pages = jsonDecode(assembly['pages'] as String) as List;
      expect(pages, hasLength(2));
    });

    test('compiles scene story page with message_flow and overlay details', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '公会大厅',
        'visualStyle': {'pcbColor': '#2C1A0E', 'panelColor': '#F7E9D7'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '公会大厅', 'role': 'story', 'type': 'base'},
            {'title': '任务板', 'role': 'tasks', 'type': 'overlay', 'parentPage': '公会大厅'},
          ],
        },
        'fields': [
          {
            'name': '任务板',
            'sourceKey': 'TaskBoard',
            'group': '任务板',
            'type': 'text',
            'display': 'text',
            'overflow': 'scroll',
            'initialValue': '任务一\n任务二',
            'page': '任务板',
            'sourceRef': 'data.first_mes quest',
          },
        ],
        'actions': [
          {
            'label': '选择采集安神草的任务。',
            'sendText': '选择采集安神草的任务。',
            'page': '公会大厅',
            'sourceRef': 'data.first_mes DQ_ChoiceBox',
          },
        ],
      });

      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '异世界公会');
      final assembly = jsonDecode(built.assemblies.first) as Map;
      expect((assembly['pcbHeight'] as num).toDouble(), greaterThanOrEqualTo(760));
      final pages = jsonDecode(assembly['pages'] as String) as List;
      expect(pages.any((p) => (p as Map)['type'] == 'overlay'), isTrue);
      final base = pages.cast<Map>().firstWhere((p) => p['name'] == '公会大厅');
      final baseElements = base['elements'] as List;
      final messageFlow = baseElements.cast<Map>().firstWhere(
        (e) => (e['module'] as Map)['type'] == 'message_flow',
      );
      expect(
        ((messageFlow['size'] as Map)['height'] as num).toDouble(),
        greaterThan(320),
      );
      expect(
        baseElements.any((e) {
          final module = ((e as Map)['module'] as Map);
          final props = module['properties'];
          if (module['type'] != 'page_router' || props is! Map) return false;
          final route = props['route'];
          return route is Map && route['action'] == 'open_overlay';
        }),
        isTrue,
      );
    });

    test('supports multi-assembly plans such as opening plus scene', () {
      final plans = UiDesignPlan.listFromJson({
        'hasUi': true,
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'assemblies': [
          {
            'uiMode': 'opening',
            'uiName': '开场选择',
            'actions': [
              {
                'label': '新人入狱',
                'sendText': '选择开场1：新人入狱',
                'branchIndex': 0,
                'sourceRef': 'data.first_mes onclick',
              },
            ],
          },
          {
            'uiMode': 'scene',
            'uiName': '监控终端',
            'fields': [
              {
                'name': '生命值 (HP)',
                'sourceKey': 'HP',
                'type': 'number',
                'display': 'progress',
                'initialValue': '100',
                'min': 0,
                'max': 100,
                'sourceRef': 'data.first_mes HP',
              },
            ],
          },
        ],
      });

      final built = UiAssemblyBuilder.buildFromPlans(plans, cardName: '测试卡');
      expect(built.assemblies, hasLength(2));
      final modes = built.assemblies
          .map((e) => (jsonDecode(e) as Map)['mode'])
          .toList();
      expect(modes, containsAll(['opening', 'scene']));
      expect(built.statusFields, hasLength(1));
    });
  });

  group('Layout regression - no overflow / no big blank', () {
    /// 编译 plan 并返回 (pcbW, pcbH, pages)。
    (double, double, List<Map>) _compile(Map<String, dynamic> planJson) {
      final plan = UiDesignPlan.fromJson(planJson);
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pcbW = (asm['pcbWidth'] as num).toDouble();
      final pcbH = (asm['pcbHeight'] as num).toDouble();
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      return (pcbW, pcbH, pages);
    }

    /// 统计可见元素中超出 PCB 边界的数量。
    int _overflowCount(List<Map> pages, double pcbW, double pcbH) {
      var n = 0;
      for (final page in pages) {
        for (final e in (page['elements'] as List).cast<Map>()) {
          final module = e['module'] as Map;
          final type = module['type']?.toString() ?? '';
          if (const {'linker', 'page_router', 'math_node', 'timer'}
              .contains(type)) {
            continue;
          }
          if (e['name'] == '底板') continue;
          final off = e['offset'] as Map;
          final sz = e['size'] as Map;
          final x = (off['x'] as num).toDouble();
          final y = (off['y'] as num).toDouble();
          final w = (sz['width'] as num).toDouble();
          final h = (sz['height'] as num).toDouble();
          if (x < 0 || y < 0) continue;
          if (x + w > pcbW + 0.5 || y + h > pcbH + 0.5) n++;
        }
      }
      return n;
    }

    /// 每页底部空白占比（百分比）。
    List<double> _blankRatios(List<Map> pages, double pcbH) {
      final out = <double>[];
      for (final page in pages) {
        double maxBottom = 0;
        for (final e in (page['elements'] as List).cast<Map>()) {
          final module = e['module'] as Map;
          final type = module['type']?.toString() ?? '';
          if (const {'linker', 'page_router', 'math_node', 'timer'}
              .contains(type)) {
            continue;
          }
          if (e['name'] == '底板') continue;
          final off = e['offset'] as Map;
          final sz = e['size'] as Map;
          final y = (off['y'] as num).toDouble();
          final h = (sz['height'] as num).toDouble();
          if (y >= 0 && y + h > maxBottom) maxBottom = y + h;
        }
        out.add(((pcbH - maxBottom) / pcbH * 100).clamp(0, 100).toDouble());
      }
      return out;
    }

    test('two-column attribute grid does not overflow and fills page', () {
      final (pcbW, pcbH, pages) = _compile({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '测试面板',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base', 'columns': 1},
            {
              'title': '属性',
              'role': 'stats',
              'type': 'base',
              'columns': 2,
              'density': 'compact',
            },
          ],
        },
        'fields': [
          for (var i = 1; i <= 10; i++)
            {
              'name': '属性$i',
              'sourceKey': 'STAT$i',
              'group': '核心属性',
              'type': 'number',
              'display': 'progress',
              'initialValue': '${50 + i}',
              'min': 0,
              'max': 100,
              'owner': 'player',
              'page': '属性',
              'span': 1,
              'sourceRef': 'data STAT$i',
            },
          {
            'name': '物品栏',
            'sourceKey': 'ITEMS',
            'group': '核心属性',
            'type': 'text',
            'display': 'text',
            'overflow': 'scroll',
            'initialValue': '铁剑、药水、护符、地图碎片、金币若干',
            'page': '属性',
            'span': 2,
            'sourceRef': 'data ITEMS',
          },
        ],
        'actions': [
          {
            'label': '行动',
            'sendText': '行动',
            'page': '正文',
            'sourceRef': 'x',
          },
        ],
        'unsupported': [],
        'notes': [],
      });
      expect(pcbW, 360);
      expect(_overflowCount(pages, pcbW, pcbH), 0,
          reason: '两列属性网格不应有任何元素溢出 PCB');
      final blanks = _blankRatios(pages, pcbH);
      for (final blank in blanks) {
        expect(blank, lessThan(25),
            reason: '页面底部空白应小于 25%（此前可达 60%+）');
      }
    });

    test('companion panel compacts instead of leaving huge blank', () {
      final (pcbW, pcbH, pages) = _compile({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'extra_companion',
        'uiName': '冒险者状态面板',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'tabbed_companion_panel',
          'navigation': 'tabs',
          'pages': [
            {'title': '状态', 'role': 'stats', 'columns': 1},
            {'title': '选项', 'role': 'actions', 'columns': 1},
          ],
        },
        'fields': [
          {
            'name': '生命值',
            'sourceKey': 'HP',
            'group': '核心状态',
            'type': 'number',
            'display': 'progress',
            'initialValue': '84',
            'min': 0,
            'max': 100,
            'owner': 'char',
            'page': '状态',
            'sourceRef': 'HP',
          },
          {
            'name': '法力',
            'sourceKey': 'MP',
            'group': '核心状态',
            'type': 'number',
            'display': 'progress',
            'initialValue': '42',
            'min': 0,
            'max': 100,
            'owner': 'char',
            'page': '状态',
            'sourceRef': 'MP',
          },
          {
            'name': '经验',
            'sourceKey': 'XP',
            'group': '核心状态',
            'type': 'number',
            'display': 'progress',
            'initialValue': '30',
            'min': 0,
            'max': 100,
            'owner': 'player',
            'page': '状态',
            'sourceRef': 'XP',
          },
          {
            'name': '金币',
            'sourceKey': 'GOLD',
            'group': '资产',
            'type': 'number',
            'display': 'text',
            'initialValue': '520',
            'page': '状态',
            'sourceRef': 'GOLD',
          },
          {
            'name': '地点',
            'sourceKey': 'LOC',
            'group': '资产',
            'type': 'text',
            'display': 'text',
            'initialValue': '黑曜石港',
            'page': '状态',
            'sourceRef': 'LOC',
          },
        ],
        'actions': [
          {
            'label': '接取任务',
            'sendText': '接取任务',
            'page': '选项',
            'sourceRef': 'a1',
          },
          {
            'label': '前往市场',
            'sendText': '前往市场',
            'page': '选项',
            'sourceRef': 'a2',
          },
          {
            'label': '查看委托板',
            'sendText': '查看委托板',
            'page': '选项',
            'sourceRef': 'a3',
          },
          {
            'label': '休息一晚',
            'sendText': '休息一晚',
            'page': '选项',
            'sourceRef': 'a4',
          },
        ],
        'unsupported': [],
        'notes': [],
      });
      expect(pcbW, 212);
      // 内容驱动高度：不再为矮页拔高 PCB，整体应明显低于旧版 490。
      expect(pcbH, lessThan(400),
          reason: '伴生面板高度应由内容决定，不应被拔高到接近 490');
      expect(_overflowCount(pages, pcbW, pcbH), 0);
      for (final blank in _blankRatios(pages, pcbH)) {
        expect(blank, lessThan(25));
      }
    });
  });

  group('CardWorkItem - manual override', () {
    test('overrideStageOutput marks editedByUser', () {
      final pipeline = ConversionPipeline();
      final item = pipeline.createItem(
        'aria.json',
        utf8.encode(jsonEncode(_ariaV2())),
      );
      final r = pipeline.runRuleStage(item);
      final edited = CardConversionResult(
        sourceName: r.sourceName,
        format: r.format,
        success: true,
        characterData: Map<String, dynamic>.from(r.characterData!)
          ..['name'] = '手改名',
      );
      item.overrideStageOutput(PipelineStage.rule, edited);
      expect(item.stageStatus[PipelineStage.rule], StageStatus.editedByUser);
      expect(item.current!.characterName, '手改名');
    });
  });
}
