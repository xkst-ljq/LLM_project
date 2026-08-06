import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/conversion_models.dart';
import 'package:llm_card_converter/core/ui_assembly_builder.dart';
import 'package:llm_card_converter/core/ui_engine_api/ui_engine_api_dictionary.dart';
import 'package:llm_card_converter/core/ui_understanding/ui_design_plan.dart';
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
