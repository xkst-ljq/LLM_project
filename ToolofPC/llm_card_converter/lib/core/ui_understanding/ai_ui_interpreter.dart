import 'dart:convert';

import '../api_service.dart';
import '../json_ai_client.dart';
import '../conversion_models.dart';
import '../ui_translate_trace.dart';
import 'ui_design_plan.dart';
import 'ui_engine_knowledge_service.dart';
import 'ui_plan_validator.dart';
import 'ui_source_pack.dart';
import 'ui_source_pack_builder.dart';

/// AI UI 理解阶段：读整张卡的证据包，输出 UiDesignPlan。
///
/// **单轮全量注入**：一次请求把「引擎知识库 + 完整证据包」发给模型，
/// 让它输出完整 UiDesignPlan（必要时用 assemblies 表达多个生命周期）。
///
/// 这是刻意为之的“最稳路径”——先把一次性注入跑通、让 AI 能回复，
/// 之后再做上下文裁剪 / 分阶段，而不是在还没跑通时叠加复杂度。
class AiUiInterpreter {
  const AiUiInterpreter._();

  static Future<AiUiInterpretation> understand({
    required Map<String, dynamic> sourceJson,
    required CardConversionResult baseResult,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final sourcePack = UiSourcePackBuilder.build(sourceJson);
    final characterName = baseResult.characterName;
    final knowledge = UiEngineKnowledgeService.compactPromptSlim();

    onLog?.call('  UI 理解：一次性注入知识库 + 完整证据包，请求模型输出 UiDesignPlan…');

    final step = traceBuilder?.beginStep(
      stage: 'single',
      targetMode: '',
      label: 'UI 理解（单轮全量）',
    );

    final messages = _buildMessages(
      sourcePack: sourcePack,
      knowledge: knowledge,
      characterName: characterName,
    );
    onLog?.call('  UI 理解 prompt 总大小：${_promptSizeLabel(_messageChars(messages))}');

    var result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 理解',
      messages: messages,
      temperature: 0.12,
      maxTokens: 16000,
      onLog: onLog,
      trace: step,
    );
    step?.complete(parsedOk: true, parsedJson: result.json);

    var plans = UiDesignPlan.listFromJson(result.json);
    var validation = _validatePlans(plans, sourcePack);
    var transcript = result.transcript;

    // 语义校验失败时，再给模型一次“只修 JSON”的机会。
    if (!validation.ok) {
      onLog?.call('  UI 方案校验失败：${validation.errors.length} 个错误，准备请求模型修复…');
      final repairStep = traceBuilder?.beginStep(
        stage: 'repair',
        targetMode: '',
        label: 'UI 方案修复',
      );
      final repairPrompt = ChatMessage(
        role: 'user',
        content: '上面的 UiDesignPlan 没通过校验：\n'
            '${validation.errors.map((e) => '- $e').join('\n')}\n\n'
            '请只输出修正后的 JSON 对象。确保满足所有 schema 要求。',
      );
      final repairResult = await JsonAiClient.completeObjectWithTranscript(
        taskName: 'UI 理解方案修复',
        messages: [...transcript, repairPrompt],
        temperature: 0.0,
        maxTokens: 16000,
        onLog: onLog,
        trace: repairStep,
      );
      repairStep?.complete(parsedOk: true, parsedJson: repairResult.json);
      plans = UiDesignPlan.listFromJson(repairResult.json);
      validation = _validatePlans(plans, sourcePack);
      transcript = repairResult.transcript;
    }

    if (!validation.ok) {
      onLog?.call('  AI 修复后仍未通过校验，但为了保证 AI 的自主性，我们将保留其原始意图，仅由编译器尝试容错。');
    }

    return AiUiInterpretation(
      plans: plans,
      validationWarnings: validation.warnings,
      sourcePack: sourcePack,
      conversationContext: transcript,
    );
  }

  static int _messageChars(List<ChatMessage> messages) => messages.fold<int>(
        0,
        (sum, message) => sum + message.content.runes.length,
      );

  static String _promptSizeLabel(int chars) {
    final low = (chars / 3).ceil();
    final high = chars;
    return '$chars 字符（粗略 $low~$high tokens）';
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
你是 SillyTavern 角色卡 UI 转译架构师。你的任务是阅读原卡证据，智能地将其转译为 LLM Project UIEngine 的高层 UiDesignPlan。

【核心使命：多 UI 协同与模式精准判断】
1. **多 UI 决策（至关重要）**：一张卡往往需要多个 UI 配合。
   - **必须包含 opening**：只要原卡有开场白分支、身份选择、属性分配，就必须生成一个 `uiMode=opening` 的方案。
   - **常驻 UI 判断**：
     - 如果原卡状态栏是“侧边挂件/常驻条”，使用 `uiMode=extra_companion`。这是最推荐的模式。
     - 如果原卡是“全屏 RPG 场景/控制台”，使用 `uiMode=scene`。
   - **多 UI 同时输出**：原卡既有开场选择又有常驻状态时，你**必须**在 top-level 输出 `assemblies: [opening方案, extra_companion方案]`。
2. **彻底打破系统套路**：严禁无脑套用“属性、档案、选项”三页模式。
3. **视觉风格与角色共生**：UI 的配色必须反映角色的灵魂。暗黑系用深色底+血红/幽紫；明快系用浅色底+天蓝/嫩绿。
4. **空间利用最大化**：优先使用 `columns: 2` 排列数值字段。长文本用 `span: 2`。

【执行指令】
- 你的输出必须是合法的 UiDesignPlan JSON。
- 绝不解释，绝不输出思考过程，绝不使用 markdown。
- 对于无法还原的插件功能，记录在 unsupported 中。
''',
      ),
      ChatMessage(
        role: 'user',
        content: '【UIEngine 知识库】\n$knowledge',
      ),
      ChatMessage(
        role: 'user',
        content: '【待分析角色卡：$characterName】\n${sourcePack.toPromptTextSlim()}',
      ),
      const ChatMessage(
        role: 'user',
        content: '请基于以上证据输出 UiDesignPlan JSON。再次强调：只能输出 JSON 对象。',
      ),
    ];
  }

  static UiPlanValidationResult _validatePlans(
    List<UiDesignPlan> plans,
    UiSourcePack sourcePack,
  ) {
    if (plans.isEmpty) {
      return const UiPlanValidationResult(
        ok: false,
        errors: ['AI 没有输出任何 UI 方案。'],
      );
    }
    final errors = <String>[];
    final warnings = <String>[];
    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final result = UiPlanValidator.validate(plan, sourcePack);
      errors.addAll(result.errors.map((e) => '[${plan.uiMode}#$i] $e'));
      warnings.addAll(result.warnings.map((e) => '[${plan.uiMode}#$i] $e'));
    }
    return UiPlanValidationResult(
      ok: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}

class AiUiInterpretation {
  final List<UiDesignPlan> plans;
  UiDesignPlan get plan => plans.first;
  final List<String> validationWarnings;
  final UiSourcePack sourcePack;

  /// 隐藏上下文：从“开始理解 UI”的 prompt 到最终结构化输出。
  final List<ChatMessage> conversationContext;

  const AiUiInterpretation({
    required this.plans,
    required this.validationWarnings,
    required this.sourcePack,
    required this.conversationContext,
  });
}
