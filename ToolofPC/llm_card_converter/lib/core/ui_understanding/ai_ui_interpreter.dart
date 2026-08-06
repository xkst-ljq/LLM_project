import 'dart:convert';

import '../api_service.dart';
import '../json_ai_client.dart';
import '../conversion_models.dart';
import 'ui_design_plan.dart';
import 'ui_engine_knowledge_service.dart';
import 'ui_plan_validator.dart';
import 'ui_source_pack.dart';
import 'ui_source_pack_builder.dart';

/// AI UI 理解阶段：读整张卡的证据包，输出 UiDesignPlan。
class AiUiInterpreter {
  const AiUiInterpreter._();

  static Future<AiUiInterpretation> understand({
    required Map<String, dynamic> sourceJson,
    required CardConversionResult baseResult,
  }) async {
    final sourcePack = UiSourcePackBuilder.build(sourceJson);
    final knowledge = UiEngineKnowledgeService.compactPrompt();
    final messages = _buildMessages(
      sourcePack: sourcePack,
      knowledge: knowledge,
      characterName: baseResult.characterName,
    );

    final rawPlanJson = await JsonAiClient.completeObject(
      taskName: 'UI 理解',
      messages: messages,
      temperature: 0.12,
      repairAttempts: 1,
    );

    var plan = UiDesignPlan.fromJson(rawPlanJson);
    var validation = UiPlanValidator.validate(plan, sourcePack);

    // 语义校验失败时，再给模型一次“只修 JSON”的机会。
    if (!validation.ok) {
      final repairedJson = await JsonAiClient.completeObject(
        taskName: 'UI 理解方案修复',
        messages: [
          ...messages,
          ChatMessage(
            role: 'assistant',
            content: const JsonEncoder.withIndent('  ').convert(rawPlanJson),
          ),
          ChatMessage(
            role: 'user',
            content: '上面的 UiDesignPlan 没通过校验：\n'
                '${validation.errors.map((e) => '- $e').join('\n')}\n\n'
                '请只输出修正后的 JSON 对象。不要新增原卡没有证据的 UI 字段；'
                '如果证据不足，应改为 hasUi=false。',
          ),
        ],
        temperature: 0.0,
        repairAttempts: 1,
      );
      plan = UiDesignPlan.fromJson(repairedJson);
      validation = UiPlanValidator.validate(plan, sourcePack);
    }

    if (!validation.ok) {
      throw FormatException('AI UI 方案未通过校验：${validation.errors.join('；')}');
    }

    return AiUiInterpretation(
      plan: plan,
      validationWarnings: validation.warnings,
      sourcePack: sourcePack,
    );
  }

  static List<ChatMessage> _buildMessages({
    required UiSourcePack sourcePack,
    required String knowledge,
    required String characterName,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译架构师。你的任务不是凭空设计 UI，
而是阅读原卡证据，判断原卡是否确实包含 UI / 状态栏 / 点击选项 / 插件界面，
再输出一份高层 UiDesignPlan，交给 Dart 编译器生成 LLM Project UIEngine JSON。

硬性规则：
1. 只输出一个 JSON 对象，不要 markdown，不要解释。
2. 不要输出内部 assembly JSON。
3. 原卡没有明确 UI 证据时，必须返回 hasUi=false。
4. 每个字段/动作都应有 sourceRef。没有证据不要生成。
5. 如果 UI 依赖外部 JS 运行时，写入 unsupported，除非证据包中也有静态可还原的字段/动作。
6. 优先忠实迁移原 UI 语义，再做移动端适配。不要为了好看新增原卡没有的属性。
''',
      ),
      ChatMessage(
        role: 'user',
        content: '【UIEngine 知识库】\n$knowledge',
      ),
      ChatMessage(
        role: 'user',
        content: '【待分析角色卡：$characterName】\n${sourcePack.toPromptText()}',
      ),
      const ChatMessage(
        role: 'user',
        content: '请基于以上证据输出 UiDesignPlan JSON。再次强调：只能输出 JSON 对象。',
      ),
    ];
  }
}

class AiUiInterpretation {
  final UiDesignPlan plan;
  final List<String> validationWarnings;
  final UiSourcePack sourcePack;

  const AiUiInterpretation({
    required this.plan,
    required this.validationWarnings,
    required this.sourcePack,
  });
}
