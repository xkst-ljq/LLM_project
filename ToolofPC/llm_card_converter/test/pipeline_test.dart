import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/conversion_models.dart';
import 'package:llm_card_converter/core/greeting_sanitizer.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';
import 'package:llm_card_converter/core/ui_engine_api/ui_engine_api_dictionary.dart';
import 'package:llm_card_converter/core/ui_understanding/ai_ui_interpreter.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_design_plan.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_engine_knowledge_service.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_plan_validator.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_scout_result.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_source_pack.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_source_pack_builder.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_visual_profile_service.dart';
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
    (double, double, List<Map>) compilePlan(Map<String, dynamic> planJson) {
      final plan = UiDesignPlan.fromJson(planJson);
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pcbW = (asm['pcbWidth'] as num).toDouble();
      final pcbH = (asm['pcbHeight'] as num).toDouble();
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      return (pcbW, pcbH, pages);
    }

    /// 统计可见元素中超出 PCB 边界的数量。
    int overflowCount(List<Map> pages, double pcbW, double pcbH) {
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
    List<double> blankRatios(List<Map> pages, double pcbH) {
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
      final (pcbW, pcbH, pages) = compilePlan({
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
      expect(overflowCount(pages, pcbW, pcbH), 0,
          reason: '两列属性网格不应有任何元素溢出 PCB');
      final blanks = blankRatios(pages, pcbH);
      for (final blank in blanks) {
        expect(blank, lessThan(25),
            reason: '页面底部空白应小于 25%（此前可达 60%+）');
      }
    });

    test('companion panel compacts instead of leaving huge blank', () {
      final (pcbW, pcbH, pages) = compilePlan({
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
      expect(overflowCount(pages, pcbW, pcbH), 0);
      for (final blank in blankRatios(pages, pcbH)) {
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

  group('AI UI plan visual fields', () {
    Map<String, dynamic> basePlan(Map<String, dynamic> visualStyle) => {
          'hasUi': true,
          'confidence': 0.9,
          'uiMode': 'scene',
          'uiName': '视觉测试面板',
          'visualStyle': visualStyle,
          'layout': {
            'kind': 'scene_dashboard',
            'pages': [
              {'title': '正文', 'role': 'story', 'type': 'base'},
              {'title': '属性', 'role': 'stats', 'type': 'base'},
            ],
          },
          'fields': [
            {
              'name': '生命',
              'sourceKey': 'HP',
              'type': 'number',
              'display': 'progress',
              'initialValue': '84',
              'min': 0,
              'max': 100,
              'page': '属性',
              'sourceRef': 'HP',
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
        };

    /// 编译 plan，返回 (底板 module, 底板 element id, 全部 elements)。
    (Map, String, List<Map>) compileWithBackdrop(Map<String, dynamic> planJson) {
      final plan = UiDesignPlan.fromJson(planJson);
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      final elements = <Map>[];
      for (final p in pages) {
        elements.addAll((p['elements'] as List).cast<Map>());
      }
      final backdrop = elements.firstWhere((e) => e['name'] == '底板');
      return (backdrop['module'] as Map, backdrop['id'] as String, elements);
    }

    test('gradient surfaceMaterial maps backdrop to material index 2', () {
      final (module, _, elements) = compileWithBackdrop(basePlan({
        'pcbColor': '#111318',
        'panelColor': '#1E232B',
        'gradientTo': '#4FA3D1',
        'surfaceMaterial': 'gradient',
      }));
      expect(module['material'], 2, reason: 'surfaceMaterial=gradient → 枚举 2');
      // 按钮底等小件保持 solid（material=1），保证可读性。
      final buttonBacks = elements.where((e) =>
          (e['name'] as String).startsWith('按钮底_') ||
          (e['name'] as String).startsWith('标签底_'));
      for (final b in buttonBacks) {
        expect((b['module'] as Map)['material'], 1,
            reason: '按钮/tab 底应保持 solid');
      }
    });

    test('outline surfaceMaterial maps backdrop to material index 3', () {
      final (module, _, _) = compileWithBackdrop(basePlan({
        'pcbColor': '#F5F0E6',
        'panelColor': '#FFFFFF',
        'strokeColor': '#8B6F47',
        'surfaceMaterial': 'outline',
      }));
      expect(module['material'], 3, reason: 'surfaceMaterial=outline → 枚举 3');
    });

    test('glow intensity emits static glow and glowPulse linker', () {
      final (module, backdropId, elements) = compileWithBackdrop(basePlan({
        'pcbColor': '#111318',
        'panelColor': '#1E232B',
        'glowColor': '#00FF88',
        'glowIntensity': 0.8,
      }));
      final props = module['properties'] as Map;
      // 动态脉冲动画配置。
      final anim = props['__anim'];
      expect(anim, isNotNull, reason: 'glowIntensity>0 应写 __anim');
      expect((anim as Map)['type'], 'glow_pulse');
      expect(anim['color'], 0xFF00FF88);
      // 触发 linker：event_to_animation，sourcePort 显式 tap，target 是底板。
      final glowLinker = elements.where((e) {
        if ((e['module'] as Map)['type'] != 'linker') return false;
        final props2 = ((e['module'] as Map)['properties'] as Map)['linker'] as Map;
        return props2['scheme'] == 'event_to_animation';
      }).toList();
      expect(glowLinker, isNotEmpty, reason: '应有 event_to_animation linker');
      final lk = ((glowLinker.first['module'] as Map)['properties'] as Map)['linker'] as Map;
      expect(lk['sourcePort'], 'tap');
      expect(lk['targetModuleId'], backdropId);
      // 静态发光只对 solid 材质生效；这里材质是 solid（未声明 gradient），
      // glowIntensity>0 所以写 __staticGlow。
      expect(props['__staticGlow'], isNotNull);
    });

    test('bubbles follow theme and invert text color on dark theme', () {
      final visualStyle = {
        'pcbColor': '#111318',
        'panelColor': '#1E232B',
        'userBubbleColor': '#1A1A2E',
        'assistantBubbleColor': '#2E2E3E',
      };
      final (_, _, elements) = compileWithBackdrop(basePlan(visualStyle));
      final flowEl = elements.firstWhere(
          (e) => (e['module'] as Map)['type'] == 'message_flow');
      final props = (flowEl['module'] as Map)['properties'] as Map;
      expect(props['userBubbleColor'], 0xFF1A1A2E);
      expect(props['assistantBubbleColor'], 0xFF2E2E3E);
      // 深色气泡 → 文字色取浅色（避免深底深字）。
      expect(props['bubbleTextColor'], 0xFFF4F6FA);
    });

    test('legacy plan without visual fields keeps defaults', () {
      final (module, _, elements) = compileWithBackdrop(basePlan({
        'pcbColor': '#111318',
        'panelColor': '#1E232B',
      }));
      expect(module['material'], 1, reason: '未声明材质 → solid');
      final props = module['properties'] as Map;
      expect(props.containsKey('__anim'), isFalse);
      expect(props.containsKey('__staticGlow'), isFalse);
      expect(
        elements.where((e) {
          final m = e['module'] as Map;
          if (m['type'] != 'linker') return false;
          final lk = (m['properties'] as Map)['linker'] as Map;
          return lk['scheme'] == 'event_to_animation';
        }),
        isEmpty,
        reason: '无发光 → 不生成 event_to_animation linker',
      );
    });
  });

  group('UI visual profile scan', () {
    test('rule scan detects gradient, stroke, glow and palette', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': 'VisualCard',
          'first_mes': '你好',
          'extensions': {
            'regex_scripts': [
              {
                'scriptName': '状态栏',
                'findRegex': '<生命>(.*?)</生命>',
                'replaceString': r'''
<div style="background:#1A1A2E; border:1px solid #00FF88; box-shadow:0 0 12px #00FF88;">
  <div style="width: $1; background:linear-gradient(to right, #16213E, #0F3460);"></div>
</div>''',
              },
            ],
          },
        },
      });
      final profile = UiVisualProfileService.scan(pack);
      expect(profile.isEmpty, isFalse);
      expect(profile.hasGradient, isTrue);
      expect(profile.hasStroke, isTrue);
      expect(profile.hasGlow, isTrue);
      expect(profile.materialHint, 'gradient');
      expect(profile.primaryColor, isNotNull);
      expect(profile.toPromptSlim(), contains('visualStyle'));
    });

    test('empty source yields none profile', () {
      final pack = UiSourcePackBuilder.build({
        'data': {'name': 'Plain', 'first_mes': '……你来了。'},
      });
      final profile = UiVisualProfileService.scan(pack);
      expect(profile.isEmpty, isTrue);
      expect(profile.toPromptSlim(), '');
    });
  });

  group('AI layout - columns up to 6', () {
    (double, double, List<Map>) compilePlan(Map<String, dynamic> planJson) {
      final plan = UiDesignPlan.fromJson(planJson);
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pcbW = (asm['pcbWidth'] as num).toDouble();
      final pcbH = (asm['pcbHeight'] as num).toDouble();
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      return (pcbW, pcbH, pages);
    }

    int overflowCount(List<Map> pages, double pcbW, double pcbH) {
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

    test('respects AI columns up to 6 without overflow', () {
      final (pcbW, pcbH, pages) = compilePlan({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '六列面板',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            {
              'title': '属性',
              'role': 'stats',
              'type': 'base',
              'columns': 6,
              'density': 'compact',
            },
          ],
        },
        'fields': [
          for (var i = 1; i <= 12; i++)
            {
              'name': '属性$i',
              'sourceKey': 'STAT$i',
              'group': '密集属性',
              'type': 'number',
              'display': 'text',
              'initialValue': '${50 + i}',
              'page': '属性',
              'span': 1,
              'sourceRef': 'STAT$i',
            },
        ],
        'actions': [
          {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
        ],
      });
      expect(pcbW, 360);
      expect(overflowCount(pages, pcbW, pcbH), 0,
          reason: '6 列网格不应有元素溢出 PCB');
    });

    test('field-level layout grid drives compact grid rendering', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '字段级布局',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            {'title': '面板', 'role': 'stats', 'type': 'base', 'columns': 1},
          ],
        },
        'fields': [
          for (var i = 1; i <= 6; i++)
            {
              'name': '徽章$i',
              'sourceKey': 'BADGE$i',
              'group': '徽章组',
              'type': 'text',
              'display': 'text',
              'layout': 'badge',
              'initialValue': '值$i',
              'page': '面板',
              'sourceRef': 'BADGE$i',
            },
        ],
        'actions': [
          {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
        ],
      });
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      // badge layout → 渲染出「格底」紧凑网格。
      final hasBadgeCells = pages.any((p) => (p['elements'] as List).cast<Map>()
          .any((e) => (e['name'] as String).contains('格底')));
      expect(hasBadgeCells, isTrue,
          reason: '字段级 layout=badge 应驱动紧凑网格渲染');
    });

    test('density affects attribute grid cell height', () {
      double cellHeightFor(Map<String, dynamic> planJson) {
        final plan = UiDesignPlan.fromJson(planJson);
        final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
        final asm = jsonDecode(built.assemblies.first) as Map;
        final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
        final cells = pages
            .expand((p) => (p['elements'] as List).cast<Map>())
            .where((e) => (e['name'] as String).contains('格底'))
            .toList();
        return cells.isEmpty
            ? 0
            : ((cells.first['size'] as Map)['height'] as num).toDouble();
      }

      Map<String, dynamic> planWith(String density) => {
            'hasUi': true,
            'confidence': 0.9,
            'uiMode': 'scene',
            'uiName': '密度$density',
            'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
            'layout': {
              'kind': 'scene_dashboard',
              'pages': [
                {'title': '正文', 'role': 'story', 'type': 'base'},
                {
                  'title': '属性',
                  'role': 'stats',
                  'type': 'base',
                  'columns': 2,
                  'density': density,
                },
              ],
            },
            'fields': [
              for (var i = 1; i <= 6; i++)
                {
                  'name': '属性$i',
                  'sourceKey': 'STAT$i',
                  'group': '核心属性',
                  'type': 'number',
                  'display': 'text',
                  'initialValue': '${50 + i}',
                  'page': '属性',
                  'sourceRef': 'STAT$i',
                },
            ],
            'actions': [
              {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
            ],
          };
      final compact = cellHeightFor(planWith('compact'));
      final spacious = cellHeightFor(planWith('spacious'));
      expect(compact, greaterThan(0));
      expect(spacious, greaterThan(0));
      expect(spacious, greaterThan(compact),
          reason: 'spacious 属性格应高于 compact（density 生效）');
    });
  });

  group('AI multi-page - more pages and overlays', () {
    test('more than 5 pages compile without truncation', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '多页面板',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            for (var i = 1; i <= 7; i++)
              {
                'title': '页$i',
                'role': 'stats',
                'type': 'base',
                'columns': 2,
              },
          ],
        },
        'fields': [
          for (var i = 1; i <= 7; i++)
            {
              'name': '数据$i',
              'sourceKey': 'D$i',
              'group': '组$i',
              'type': 'number',
              'display': 'text',
              'initialValue': '$i',
              'page': '页$i',
              'sourceRef': 'D$i',
            },
        ],
        'actions': [
          {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
        ],
      });
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      expect(pages.length, 8, reason: '主支路 1 页 + 7 页 = 8 页，不应被 take(5) 截断');
    });

    test('overlay entries beyond 4 compile', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '多叠加页',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            for (var i = 1; i <= 6; i++)
              {
                'title': '详情$i',
                'role': 'stats',
                'type': 'overlay',
                'parentPage': '正文',
              },
          ],
        },
        'fields': [
          for (var i = 1; i <= 6; i++)
            {
              'name': '详情字段$i',
              'sourceKey': 'OV$i',
              'group': '详情',
              'type': 'text',
              'display': 'text',
              'initialValue': '内容$i',
              'page': '详情$i',
              'sourceRef': 'OV$i',
            },
        ],
        'actions': [
          {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
        ],
      });
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final pages = (jsonDecode(asm['pages'] as String) as List).cast<Map>();
      final storyPage = pages.cast<Map>().firstWhere((p) => p['name'] == '正文');
      final entryCount = (storyPage['elements'] as List).cast<Map>()
          .where((e) => (e['name'] as String).startsWith('叠加入口底_'))
          .length;
      expect(entryCount, 6, reason: '6 个 overlay 应有 6 个入口按钮');
    });
  });

  group('AI branchPlans - opening differentiation', () {
    Map<String, dynamic> branchPlan() => {
          'hasUi': true,
          'confidence': 0.9,
          'uiMode': 'opening',
          'uiName': '开场选择',
          'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
          'layout': {
            'kind': 'opening_choices',
            'pages': [
              {'title': '开场', 'role': 'form', 'type': 'base'},
            ],
          },
          'actions': [
            {
              'label': '新人入狱',
              'sendText': '选择开场1：新人入狱',
              'branchIndex': 0,
              'page': '开场',
              'sourceRef': 'x',
            },
          ],
          'branchPlans': {
            '1': {
              'fields': [
                {
                  'name': '狱警编号',
                  'sourceKey': 'GuardID',
                  'group': '身份',
                  'type': 'text',
                  'display': 'text',
                  'initialValue': 'G-1024',
                  'page': '开场',
                  'sourceRef': 'x',
                },
              ],
            },
          },
        };

    test('branchPlans emit branchVariants in assembly', () {
      final plan = UiDesignPlan.fromJson(branchPlan());
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final asm = jsonDecode(built.assemblies.first) as Map;
      final variants = asm['branchVariants'];
      expect(variants, isNotNull, reason: '有 branchPlans 应生成 branchVariants');
      expect((variants as Map).containsKey('0'), isFalse,
          reason: '分支 0 是主支路，不写变体');
      expect(variants.containsKey('1'), isTrue);
      final branchPages = jsonDecode(variants['1'] as String) as List;
      expect(branchPages, isNotEmpty);
      // 变体含主支路没有的「狱警编号」字段。
      final branchFieldNames = branchPages
          .expand((p) => (p['elements'] as List).cast<Map>())
          .map((e) => e['name'] as String)
          .toList();
      expect(branchFieldNames, contains('狱警编号'));
    });

    test('branch variant merges statusFields', () {
      final plan = UiDesignPlan.fromJson(branchPlan());
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final ids = built.statusFields.map((f) => f['id']).toSet();
      expect(ids, contains('sf_GuardID'),
          reason: '分支特有字段应并入顶层 status_bar_fields');
    });

    test('branch variant inherits mode from main plan', () {
      final plan = UiDesignPlan.fromJson(branchPlan());
      expect(plan.branchPlans[1]!.uiMode, 'opening',
          reason: '变体未写 uiMode 应继承主支路');
    });

    test('validator rejects nested or mismatched-mode branchPlans', () {
      final json = branchPlan();
      final branchPlans = Map<String, dynamic>.from(json['branchPlans'] as Map);
      branchPlans['1'] = <String, dynamic>{'uiMode': 'scene'};
      json['branchPlans'] = branchPlans;
      final plan = UiDesignPlan.fromJson(json);
      final pack = UiSourcePackBuilder.build({'data': {'name': 'X'}});
      final result = UiPlanValidator.validate(plan, pack);
      expect(result.ok, isFalse, reason: '变体 uiMode 与主支路不一致应报错');
    });
  });

  group('AI data completeness - notes on truncation', () {
    test('dedupe truncation reports notes', () {
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'confidence': 0.9,
        'uiMode': 'scene',
        'uiName': '超多字段',
        'visualStyle': {'pcbColor': '#111318', 'panelColor': '#1E232B'},
        'layout': {
          'kind': 'scene_dashboard',
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            {'title': '面板', 'role': 'stats', 'type': 'base', 'columns': 2},
          ],
        },
        'fields': [
          for (var i = 1; i <= 40; i++)
            {
              'name': '字段$i',
              'sourceKey': 'F$i',
              'group': '海量组',
              'type': 'text',
              'display': 'text',
              'initialValue': '值$i',
              'page': '面板',
              'sourceRef': 'F$i',
            },
        ],
        'actions': [
          {'label': '行动', 'sendText': '行动', 'page': '正文', 'sourceRef': 'x'},
        ],
      });
      final built = UiAssemblyBuilder.buildFromPlan(plan, cardName: '测试卡');
      final joined = built.notes.join('\n');
      expect(joined, contains('省略'), reason: '字段截断应有 notes 说明');
    });

    test('slim prompt reports omitted evidence', () {
      final entries = [
        for (var i = 1; i <= 25; i++)
          {
            'comment': '条目$i',
            'content': '{quest:任务$i|type:生活|desc:描述$i|diff:D级|client:委托人|reward:10银|location:森林|time:无|equip:无|risk:低|note:说明}',
          },
      ];
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': 'QuestCard',
          'first_mes': '你好',
          'character_book': {'entries': entries},
        },
      });
      final slim = pack.toPromptTextSlim();
      expect(slim, contains('omitted'), reason: '超过展示上限应提示省略');
    });
  });

  group('AI mode decision - density & multi-greeting', () {
    test('multi-greeting without buttons still requires opening', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '多开场卡',
          'first_mes': '开场A',
          'alternate_greetings': ['开场B', '开场C'],
          'description': '一个角色',
        },
      });
      expect(pack.needsOpeningBranchChoice, isTrue,
          reason: '多开场白本身即构成 opening 需求，不依赖 send() 按钮');
      final suggestion = pack.modeSuggestion();
      expect(suggestion, contains('[opening]'));
      expect(suggestion, contains('分支差异化'));
    });

    test('high density card suggests scene', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '高密度卡',
          'description': '角色',
          'first_mes':
              '<生命>84</生命><精神>70</精神><体力>60</体力><饱腹>50</饱腹>'
              '<势力>1</势力><关系>2</关系><声望>3</声望><点数>4</点数>'
              '<物品>刀</物品><位置>监狱</位置><正文>你醒来了</正文>',
          'extensions': {
            'regex_scripts': [
              {
                'scriptName': '状态栏',
                'findRegex': '<生命>(.*?)</生命>.*?<正文>(.*?)</正文>',
                'replaceString':
                    '<div style="width:100%;overflow:auto;color:#fff;'
                    '${List.filled(60, 'background-color:#111;').join()}'
                    '">正文容器</div>',
              },
            ],
          },
        },
      });
      final density = pack.densityAssessment();
      expect(density.isHigh, isTrue,
          reason: '≥8 状态字段 + 正文包裹应判为高密度');
      expect(pack.modeSuggestion(), contains('[scene]'));
    });

    test('focused single-purpose card suggests companion not scene', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '专项卡',
          'description': '角色',
          'first_mes': '<生命>84</生命>正文',
        },
      });
      expect(pack.densityAssessment().isHigh, isFalse);
      expect(pack.modeSuggestion(), contains('[extra_companion]'));
      expect(pack.modeSuggestion(), isNot(contains('[scene]')));
    });

    test('slim prompt includes density assessment', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '高密度卡',
          'description': '角色',
          'first_mes':
              '<生命>84</生命><精神>70</精神><体力>60</体力><饱腹>50</饱腹>'
              '<势力>1</势力><关系>2</关系><声望>3</声望><点数>4</点数>'
              '<物品>刀</物品><位置>监狱</位置><正文>正文</正文>',
        },
      });
      final slim = pack.toPromptTextSlim();
      expect(slim, contains('UI density assessment'));
      expect(slim, contains('信息密度'));
    });
  });

  group('AI validateAssemblies - multi-greeting & density rules', () {
    Map<String, dynamic> greetingPackJson({bool withStatus = false}) => {
          'data': {
            'name': '多开场卡',
            'description': '角色',
            'first_mes': withStatus
                ? '<生命>84</生命><精神>70</精神><体力>60</体力><饱腹>50</饱腹>'
                    '<势力>1</势力><关系>2</关系><声望>3</声望><点数>4</点数>'
                    '<物品>刀</物品><位置>监狱</位置><正文>A</正文>'
                : '开场A',
            'alternate_greetings': ['开场B'],
          },
        };

    test('missing opening errors when multiple greetings', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'extra_companion',
        'uiName': '伴生栏',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([plan], pack);
      expect(result.ok, isFalse,
          reason: '多开场白必须包含 opening assembly');
      expect(result.errors.join(), contains('uiMode=opening'));
    });

    test('opening without branchIndex errors', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'opening',
        'uiName': '开场选择',
        'layout': {'pages': [{'title': '开场', 'role': 'form'}]},
        'actions': [
          {'label': '继续', 'sendText': '继续', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([plan], pack);
      expect(result.ok, isFalse,
          reason: '多开场白 opening 必须用 branchIndex 对应每个方向');
      expect(result.errors.join(), contains('branchIndex'));
    });

    test('opening with branchInitialValues passes', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'opening',
        'uiName': '开场选择',
        'layout': {'pages': [{'title': '开场', 'role': 'form'}]},
        'actions': [
          {'label': '方向A', 'branchIndex': 0, 'sourceRef': 'x'},
          {'label': '方向B', 'branchIndex': 1, 'sourceRef': 'x'},
        ],
        'fields': [
          {
            'name': '生命',
            'type': 'number',
            'initialValue': '84',
            'branchInitialValues': {'0': '84', '1': '70'},
            'sourceRef': 'x',
          },
        ],
      });
      final result = UiPlanValidator.validateAssemblies([plan], pack);
      expect(result.ok, isTrue, reason: 'branchIndex 全覆盖 + branchInitialValues 应通过');
    });

    test('status differs across branches but no differentiation errors', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '差异化卡',
          'description': '角色',
          'first_mes': '{PlayerStatus|HP:100/100|MP:50/50}正文A',
          'alternate_greetings': ['{PlayerStatus|HP:80/100|MP:30/50}正文B'],
        },
      });
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'opening',
        'uiName': '开场选择',
        'layout': {'pages': [{'title': '开场', 'role': 'form'}]},
        'actions': [
          {'label': '方向A', 'branchIndex': 0, 'sourceRef': 'x'},
          {'label': '方向B', 'branchIndex': 1, 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([plan], pack);
      expect(result.ok, isFalse,
          reason: '分支 HP/MP 初值不同，必须用 branchInitialValues 差异化');
      expect(result.errors.join(), contains('branchInitialValues'));
    });

    test('high density companion-only warns about scene', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson(withStatus: true));
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'extra_companion',
        'uiName': '伴生栏',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([plan], pack);
      expect(result.ok, isFalse, reason: '多开场白缺 opening 仍是 error');
      expect(result.warnings.join(), contains('extra_companion'),
          reason: '高密度只用伴生栏应有 scene 建议警告');
    });

    test('duplicate uiMode errors (two companions)', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      UiDesignPlan companion() => UiDesignPlan.fromJson({
            'hasUi': true,
            'uiMode': 'extra_companion',
            'uiName': '伴生栏',
            'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
            'fields': [
              {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
            ],
          });
      final result = UiPlanValidator.validateAssemblies([companion(), companion()], pack);
      expect(result.ok, isFalse,
          reason: '同一 uiMode 重复出现应报错（防止编译出两份重复 UI）');
      expect(result.errors.join(), contains('重复'));
    });

    test('scene plus extra_companion errors as mutually exclusive', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      final scene = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'scene',
        'uiName': '终端',
        'layout': {
          'pages': [
            {'title': '正文', 'role': 'story', 'type': 'base'},
            {'title': '状态', 'role': 'stats', 'type': 'overlay', 'parentPage': '正文'},
          ],
        },
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      final companion = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'extra_companion',
        'uiName': '伴生栏',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '精神', 'type': 'number', 'initialValue': '70', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([scene, companion], pack);
      expect(result.ok, isFalse,
          reason: 'scene 与 extra_companion 互斥，不应并存');
      expect(result.errors.join(), contains('互斥'));
    });

    test('invalid uiMode is preserved for validator to reject', () {
      final pack = UiSourcePackBuilder.build(greetingPackJson());
      final plan = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'not_a_real_mode',
        'uiName': '幻觉 UI',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      expect(plan.uiMode, 'not_a_real_mode',
          reason: '未知 uiMode 不应被静默归一成 extra_companion');
      final result = UiPlanValidator.validate(plan, pack);
      expect(result.ok, isFalse, reason: '非法 uiMode 应被 validator 拦截');
      expect(result.errors.join(), contains('非法 uiMode'));
    });
  });

  group('UI engine knowledge - decision guidance', () {
    test('slim knowledge mandates opening for multi-greeting', () {
      final slim = UiEngineKnowledgeService.compactPromptSlim();
      expect(slim, contains('多开场白'), reason: '应明确多开场白规则');
      expect(slim, contains('必须'), reason: '应使用强约束措辞');
      expect(slim, contains('信息密度'));
      expect(slim, contains('extra_companion / extra_sticky'));
    });

    test('full knowledge covers density and branch differentiation', () {
      final full = UiEngineKnowledgeService.compactPrompt();
      expect(full, contains('Mode selection by information density'));
      expect(full, contains('Opening branch differentiation (mandatory)'));
      expect(full, contains('Multiple greetings always require opening'));
    });
  });

  group('UiScoutResult - staged pipeline step 0', () {
    test('parses assemblies and neededDetail indices', () {
      final scout = UiScoutResult.fromJson({
        'hasUi': true,
        'evidenceSummary': '多开场白 + 状态栏',
        'sourceRefs': ['data.extensions.regex_scripts[0]'],
        'assemblies': [
          {
            'uiMode': 'opening',
            'uiName': '开场登记',
            'reasons': ['多开场白 → 必须 opening'],
            'evidenceSummary': '让玩家选择开场方向',
            'sourceRefs': ['data.alternate_greetings[0]'],
            'neededDetail': {'regex': [1, 2], 'worldbook': [0], 'includeFullBranches': true},
          },
          {
            'uiMode': 'scene',
            'uiName': '运行终端',
            'evidenceSummary': '正文被 UI 包裹',
            'neededDetail': {'regex': [0], 'plugin': [0, 1]},
          },
        ],
      });
      expect(scout.hasUi, isTrue);
      expect(scout.assemblies, hasLength(2));
      final opening = scout.assemblies.first;
      expect(opening.uiMode, 'opening');
      expect(opening.neededDetail.regexIndices, {1, 2});
      expect(opening.neededDetail.worldBookIndices, {0});
      expect(opening.neededDetail.includeFullBranches, isTrue);
      expect(opening.neededDetail.pluginIndices, isEmpty);
      final scene = scout.assemblies[1];
      expect(scene.uiMode, 'scene');
      expect(scene.neededDetail.regexIndices, {0});
      expect(scene.neededDetail.pluginIndices, {0, 1});
      expect(scene.neededDetail.includeFullBranches, isFalse);
    });

    test('normalizes alias uiModes and drops invalid entries', () {
      final scout = UiScoutResult.fromJson({
        'hasUi': true,
        'evidenceSummary': 'x',
        'assemblies': [
          {'uiMode': 'status', 'neededDetail': {}},
          {'uiMode': 'companion', 'neededDetail': {}},
          {'uiMode': 'sticky', 'neededDetail': {}},
          {'uiMode': 'not_a_mode', 'neededDetail': {}},
        ],
      });
      expect(scout.assemblies, hasLength(3));
      expect(scout.assemblies.map((a) => a.uiMode).toList(),
          ['extra_companion', 'extra_companion', 'extra_sticky']);
    });

    test('empty assemblies means no valid selection', () {
      final scout = UiScoutResult.fromJson({'hasUi': true, 'evidenceSummary': 'x'});
      expect(scout.hasUi, isTrue);
      expect(scout.assemblies, isEmpty);
    });
  });

  group('Scout detail slicing - detailPromptFor honors neededDetail', () {
    UiSourcePack pack() => UiSourcePackBuilder.build({
          'data': {
            'name': '切片卡',
            'description': '角色',
            'first_mes': 'A',
            'alternate_greetings': ['B', 'C'],
            'extensions': {
              'regex_scripts': [
                {'scriptName': 'R0', 'findRegex': 'x', 'replaceString': 'x0'},
                {'scriptName': 'R1', 'findRegex': 'y', 'replaceString': 'y1'},
              ],
            },
          },
        });

    test('only requested indices are included', () {
      final prompt = pack().detailPromptFor(regexIndices: {1});
      expect(prompt, contains('regex[1]'));
      expect(prompt, isNot(contains('regex[0]')));
    });

    test('includeFullBranches exposes full branch text, otherwise summary only', () {
      final full = pack().detailPromptFor(includeFullBranches: true);
      expect(full, contains('## first_mes'));
      expect(full, contains('[0]'));
      final summaryOnly = pack().detailPromptFor(includeFullBranches: false);
      expect(summaryOnly, isNot(contains('## first_mes')));
      expect(summaryOnly, contains('Opening greeting branches'));
    });
  });

  group('Staged pipeline - merged plans still validate as assemblies', () {
    test('opening + companion plans pass validateAssemblies for multi-greeting', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '多开场卡',
          'description': '角色',
          'first_mes': '开场A',
          'alternate_greetings': ['开场B'],
        },
      });
      final opening = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'opening',
        'uiName': '开场选择',
        'layout': {'pages': [{'title': '开场', 'role': 'form'}]},
        'actions': [
          {'label': '方向A', 'branchIndex': 0, 'sourceRef': 'x'},
          {'label': '方向B', 'branchIndex': 1, 'sourceRef': 'x'},
        ],
      });
      final companion = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'extra_companion',
        'uiName': '伴生栏',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([opening, companion], pack);
      expect(result.ok, isTrue, reason: 'opening 覆盖全分支 + companion 应通过组合校验');
    });

    test('merged plans missing opening still fail', () {
      final pack = UiSourcePackBuilder.build({
        'data': {
          'name': '多开场卡',
          'description': '角色',
          'first_mes': '开场A',
          'alternate_greetings': ['开场B'],
        },
      });
      final companion = UiDesignPlan.fromJson({
        'hasUi': true,
        'uiMode': 'extra_companion',
        'uiName': '伴生栏',
        'layout': {'pages': [{'title': '面板', 'role': 'stats'}]},
        'fields': [
          {'name': '生命', 'type': 'number', 'initialValue': '84', 'sourceRef': 'x'},
        ],
      });
      final result = UiPlanValidator.validateAssemblies([companion], pack);
      expect(result.ok, isFalse, reason: '多开场白缺 opening 仍是跨套校验错误');
    });
  });

  group('Repair coverage - designed UI never dropped by repair', () {
    UiDesignPlan openingPlan() => UiDesignPlan.fromJson({
          'hasUi': true,
          'uiMode': 'opening',
          'uiName': '冒险者注册',
          'layout': {'pages': [{'title': '注册', 'role': 'form'}]},
          'actions': [
            {'label': '方向A', 'branchIndex': 0, 'sourceRef': 'x'},
            {'label': '方向B', 'branchIndex': 1, 'sourceRef': 'x'},
          ],
        });

    UiDesignPlan scenePlan() => UiDesignPlan.fromJson({
          'hasUi': true,
          'uiMode': 'scene',
          'uiName': '异世界公会终端',
          'layout': {
            'pages': [
              {'title': '公会大厅', 'role': 'story', 'type': 'base'},
              {'title': '任务板', 'role': 'tasks', 'type': 'overlay', 'parentPage': '公会大厅'},
            ],
          },
          'fields': [
            {
              'name': '生命',
              'sourceKey': 'HP',
              'group': '核心状态',
              'type': 'number',
              'display': 'progress',
              'overflow': 'text',
              'initialValue': '84',
              'page': '公会大厅',
              'sourceRef': 'data.first_mes <生命>84%</生命>',
            },
          ],
        });

    test('opening dropped by repair round is restored from original', () {
      final originals = [openingPlan(), scenePlan()];
      // 修复模型只回吐 scene —— 模拟"opening 已设计但被修复轮丢掉"。
      final repaired = [scenePlan()];
      final logs = <String>[];
      final restored =
          AiUiInterpreter.restoreDroppedModes(repaired, originals, logs.add);
      final modes = restored.map((p) => p.uiMode).toSet();
      expect(modes, {'opening', 'scene'},
          reason: '被修复轮漏掉的 opening 必须用原方案补回');
      expect(restored.firstWhere((p) => p.uiMode == 'opening').uiName, '冒险者注册');
      expect(logs.join(), contains('uiMode=opening'));
    });

    test('repair that keeps all modes stays untouched', () {
      final originals = [openingPlan(), scenePlan()];
      final repaired = List<UiDesignPlan>.of(originals);
      final restored =
          AiUiInterpreter.restoreDroppedModes(repaired, originals, (_) {});
      expect(restored.length, 2);
      expect(restored.map((p) => p.uiMode).toSet(), {'opening', 'scene'});
    });

    test('structural repair replaces same-mode plan instead of appending', () {
      // 复现「为什么 4 份 UI」：2 套 plan（opening, scene）结构校验都失败，
      // 逐套修复后如果原方案 + 修复版同存，就会变成 4 个 plan。
      final originals = [openingPlan(), scenePlan()];
      var merged = <UiDesignPlan>[];
      for (final plan in originals) {
        if (!merged.any((p) => p.uiMode == plan.uiMode)) merged.add(plan);
      }
      // 模拟 opening 修复成功、scene 修复成功：各自产出修复版 plan。
      final fixedOpening = openingPlan(); // 修复版（这里用同结构代替）
      final fixedScene = scenePlan();
      merged = AiUiInterpreter.mergeFixedPlans(merged, fixedOpening);
      merged = AiUiInterpreter.mergeFixedPlans(merged, fixedScene);
      expect(merged.length, 2,
          reason: '修复结果必须顶替同 uiMode 的原 plan，不能 append 出重复');
      expect(merged.map((p) => p.uiMode).toSet(), {'opening', 'scene'});
    });

    test('2 designed plans still compile to exactly 2 assemblies', () {
      // 端到端：opening + scene 两套 plan 经编译管线应只产出 2 份 assembly，
      // 而不是 4 份。
      final built = UiAssemblyBuilder.buildFromPlans(
        [openingPlan(), scenePlan()],
        cardName: '异世界公会',
      );
      expect(built.assemblies, hasLength(2),
          reason: '每套 UiDesignPlan 只编译一份 assembly，不得因修复/合并而翻倍');
    });
  });

  group('GreetingSanitizer - dedup', () {
    test('strips PlayerStatus macro', () {
      final result = GreetingSanitizer.sanitize(
        '{PlayerStatus|HP:84/100|MP:50/100}\n正文',
      );
      expect(result.trim(), '正文');
    });

    test('strips known XML tags by tag name', () {
      final result = GreetingSanitizer.sanitize(
        '<生命>84%</生命>正文',
        knownTagNames: {'生命'},
      );
      expect(result.trim(), '正文');
    });

    test('keeps unknown tags', () {
      final result = GreetingSanitizer.sanitize(
        '<随机>123</随机>正文',
        knownTagNames: {'生命'},
      );
      expect(result, contains('<随机>123</随机>'));
    });
  });
}
