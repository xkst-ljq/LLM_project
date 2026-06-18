import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/conversion_models.dart';
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
