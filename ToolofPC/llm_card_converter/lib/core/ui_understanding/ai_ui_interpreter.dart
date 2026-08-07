import '../api_service.dart';
import '../json_ai_client.dart';
import '../conversion_models.dart';
import '../ui_engine_api/ui_engine_api_dictionary.dart';
import 'ui_design_plan.dart';
import 'ui_engine_knowledge_service.dart';
import 'ui_plan_validator.dart';
import 'ui_scout_plan.dart';
import 'ui_source_pack.dart';
import 'ui_source_pack_builder.dart';

/// AI UI 理解阶段：读整张卡的证据包，输出 UiDesignPlan。
///
/// 采用两阶段渐进披露（Progressive Disclosure），控制单次请求的上下文量：
///
/// 1. **Scout**：只发「能力索引 + 证据指纹摘要」（token 开销远小于完整
///    证据包），让 AI 先判断有没有 UI、用哪种模式、需要哪些组件、要看
///    哪些证据的细节，输出轻量 `UiScoutPlan`。
/// 2. **Detailer**：程序按 Scout 的点名，只把「被选组件的 API 详情 +
///    被点名的证据切片」拼进第二轮，让 AI 输出完整 `UiDesignPlan`。
///
/// 这样首轮请求大幅缩短（解决“给定文本过多导致模型返回空”），
/// 第二轮也只带真正需要的细节。全程向后兼容：任一阶段失败可回落
/// 单轮全量（旧行为）。
class AiUiInterpreter {
  const AiUiInterpreter._();

  static Future<AiUiInterpretation> understand({
    required Map<String, dynamic> sourceJson,
    required CardConversionResult baseResult,
    void Function(String line)? onLog,
  }) async {
    final sourcePack = UiSourcePackBuilder.build(sourceJson);
    final characterName = baseResult.characterName;

    // ── 阶段 1：Scout —— 轻量选型 ──
    final scoutPlan = await _runScout(
      sourcePack: sourcePack,
      characterName: characterName,
      onLog: onLog,
    );

    if (!scoutPlan.hasUi) {
      return AiUiInterpretation(
        plans: [
          UiDesignPlan(
            hasUi: false,
            confidence: scoutPlan.confidence,
            uiMode: scoutPlan.uiMode,
            uiName: scoutPlan.uiName,
            evidenceSummary: scoutPlan.evidenceSummary,
            sourceRefs: const [],
            visualStyle: const UiPlanStyle(
              styleName: 'dark terminal',
              pcbColor: '#15161A',
              panelColor: '#1E2027',
              titleColor: '#FFFFFF',
              labelColor: '#AAB0BC',
              valueColor: '#E8EDF5',
              accentColor: '#4FA3D1',
              buttonBgColor: '#2A3340',
              barFillColor: '#4FA3D1',
              barTrackColor: '#2A2D36',
              borderRadius: 14.0,
              glow: false,
            ),
            layout: const UiPlanLayout(
              kind: 'single_panel',
              navigation: 'tabs_and_swipe',
              pages: [],
            ),
            fields: const [],
            inputs: const [],
            actions: const [],
            unsupported: const [],
            notes: scoutPlan.notes,
          ),
        ],
        validationWarnings: const [],
        sourcePack: sourcePack,
        conversationContext: const [],
      );
    }

    // ── 阶段 2：Detailer —— 按选型拼细节，输出完整 plan ──
    var result = await _runDetailer(
      sourcePack: sourcePack,
      scoutPlan: scoutPlan,
      characterName: characterName,
      onLog: onLog,
    );

    var plans = UiDesignPlan.listFromJson(result.json);
    var validation = _validatePlans(plans, sourcePack);
    var transcript = result.transcript;

    // 语义校验失败时，再给模型一次“只修 JSON”的机会。
    if (!validation.ok) {
      onLog?.call('  UI 方案校验失败：${validation.errors.length} 个错误，准备请求模型修复…');
      final repairPrompt = ChatMessage(
        role: 'user',
        content: '上面的 UiDesignPlan 没通过校验：\n'
            '${validation.errors.map((e) => '- $e').join('\n')}\n\n'
            '请只输出修正后的 JSON 对象。不要新增原卡没有证据的 UI 字段；'
            '如果证据不足，应改为 hasUi=false。',
      );
      final repairMessages = [...transcript, repairPrompt];
      onLog?.call('  UI 修复 prompt 大小：${_promptSizeLabel(_messageChars(repairMessages))}');
      result = await JsonAiClient.completeObjectWithTranscript(
        taskName: 'UI 理解方案修复',
        messages: repairMessages,
        temperature: 0.0,
        maxTokens: 6000,
        repairAttempts: 1,
      );
      plans = UiDesignPlan.listFromJson(result.json);
      validation = _validatePlans(plans, sourcePack);
      transcript = result.transcript;
    }

    if (!validation.ok) {
      throw FormatException('AI UI 方案未通过校验：${validation.errors.join('；')}');
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
    // 真实 token 数由模型 tokenizer 决定，这里只给一个保守范围，
    // 用于判断“是不是超长上下文导致首 token 慢/空返回”。
    final low = (chars / 3).ceil();
    final high = chars;
    return '$chars 字符（粗略 $low~$high tokens）';
  }

  /// 阶段 1：Scout。输出轻量选型计划。
  static Future<UiScoutPlan> _runScout({
    required UiSourcePack sourcePack,
    required String characterName,
    void Function(String line)? onLog,
  }) async {
    onLog?.call('  UI 侦察（阶段 1）：扫描证据指纹…');
    final scoutPrompt = _buildScoutPrompt(
      sourcePack: sourcePack,
      characterName: characterName,
    );
    onLog?.call('  UI 侦察 prompt 大小：${_promptSizeLabel(_messageChars(scoutPrompt))}');
    var received = 0;
    final result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 侦察',
      messages: scoutPrompt,
      temperature: 0.15,
      maxTokens: 1500,
      repairAttempts: 1,
      onDelta: (delta) {
        received += delta.length;
        // 实时进度点：每 ~200 字符输出一个，证明生成在进行、未被超时。
        if (received % 200 < delta.length) {
          onLog?.call('  侦察中…（已接收 $received 字符）');
        }
      },
    );
    onLog?.call('  侦察完成，已接收 $received 字符');
    final json = result.json;
    if (json.containsKey('hasUi') == false) {
      // 兼容 AI 直接输出完整 plan 的旧行为：hasUi 缺失但有关键字段。
      if (json.containsKey('fields') ||
          json.containsKey('actions') ||
          json.containsKey('inputs')) {
        return UiScoutPlan(
          hasUi: true,
          confidence: 0.6,
          uiMode: json['uiMode']?.toString() ?? 'extra_companion',
          uiName: json['uiName']?.toString() ?? 'AI 转译 UI',
          components: const [],
          regexIndices: const [],
          pluginIndices: const [],
          htmlIndices: const [],
          worldBookIndices: const [],
          includeFullBranches: true,
          evidenceSummary: json['evidenceSummary']?.toString() ?? '',
          notes: const [],
        );
      }
      return const UiScoutPlan(
        hasUi: false,
        confidence: 0.3,
        uiMode: 'extra_companion',
        uiName: '无 UI',
        components: [],
        regexIndices: [],
        pluginIndices: [],
        htmlIndices: [],
        worldBookIndices: [],
        evidenceSummary: 'AI 未输出选型字段',
        notes: [],
      );
    }
    return UiScoutPlan.fromJson(json);
  }

  /// 阶段 2：Detailer。按 Scout 选型拼「组件 API + 证据切片」，输出完整 plan。
  static Future<JsonAiResult> _runDetailer({
    required UiSourcePack sourcePack,
    required UiScoutPlan scoutPlan,
    required String characterName,
    void Function(String line)? onLog,
  }) async {
    onLog?.call('  精修检索（阶段 2）：拼装组件 API + 证据切片…');
    // 组件 API 详情：只给 Scout 点名的组件。
    final componentDetails = UiEngineApiDictionary.detailForComponents(
      scoutPlan.components,
    );
    // 证据切片：只给 Scout 点名的正则 / 插件 / HTML / 世界书。
    final detailEvidence = sourcePack.detailPromptFor(
      regexIndices: scoutPlan.regexIndices.toSet(),
      pluginIndices: scoutPlan.pluginIndices.toSet(),
      htmlIndices: scoutPlan.htmlIndices.toSet(),
      worldBookIndices: scoutPlan.worldBookIndices.toSet(),
      includeFullBranches: scoutPlan.includeFullBranches,
    );
    final messages = _buildDetailerMessages(
      sourcePack: sourcePack,
      characterName: characterName,
      scoutPlan: scoutPlan,
      componentDetails: componentDetails,
      detailEvidence: detailEvidence,
    );
    onLog?.call('  精修组件 API 大小：${componentDetails.runes.length} 字符；证据切片大小：${detailEvidence.runes.length} 字符');
    onLog?.call('  UI 精修 prompt 总大小：${_promptSizeLabel(_messageChars(messages))}');
    if (scoutPlan.regexIndices.isNotEmpty || scoutPlan.worldBookIndices.isNotEmpty) {
      onLog?.call('  精修证据索引：regex=${scoutPlan.regexIndices.join(',')} worldbook=${scoutPlan.worldBookIndices.join(',')} branches=${scoutPlan.includeFullBranches ? 'full' : 'summary'}');
    }
    var received = 0;
    final result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 理解',
      messages: messages,
      temperature: 0.12,
      maxTokens: 6000,
      // 阶段 2 上下文大（组件 API + 证据切片），模型首 token 前的
      // 处理时间长；流式靠 chunk 规避生成中超时，但首 token 等待
      // 仍受 timeout 限制，放宽到 480s。
      timeout: const Duration(seconds: 480),
      repairAttempts: 1,
      onDelta: (delta) {
        received += delta.length;
        if (received % 400 < delta.length) {
          onLog?.call('  生成中…（已接收 $received 字符）');
        }
      },
    );
    onLog?.call('  生成完成，已接收 $received 字符');
    return result;
  }

  /// Scout 阶段的 prompt：能力索引 + 证据指纹，不含完整证据正文。
  static List<ChatMessage> _buildScoutPrompt({
    required UiSourcePack sourcePack,
    required String characterName,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译侦察员。你的任务是用最小代价判断原卡是否包含
可转译 UI，并列出需要进一步查看的证据。只输出一个 JSON 对象，不要 markdown。

输出结构（所有字段都给出）：
{
  "hasUi": true/false,
  "confidence": 0.0~1.0,
  "uiMode": "opening|scene|extra_sticky|extra_companion",
  "uiName": "简短 UI 名",
  "components": ["surface","text","progress", ...],  // 计划使用的引擎组件
  "regexIndices": [0,1],           // 需要看完整内容的 regex 证据下标
  "pluginIndices": [],
  "htmlIndices": [],
  "worldBookIndices": [],
  "includeFullBranches": true/false, // 需要完整开场白文本以提取字段/动作时 true
  "evidenceSummary": "为什么有/没有 UI",
  "notes": []
}

规则：
1. 原卡没有明确 UI 证据时 hasUi=false。
2. components 只列可能用到的；不确定就少列，detail 阶段会补。
3. 证据包里有多个 regex 时，用 indices 点名要看哪几个，避免全量塞入。
4. 只有需要精确提取字段名 / 动作文本时才 includeFullBranches=true。
''',
      ),
      ChatMessage(
        role: 'user',
        content: '【能力索引】\n${UiEngineApiDictionary.compactIndexMarkdown()}',
      ),
      ChatMessage(
        role: 'user',
        content: '【证据指纹】\n${sourcePack.summaryPrompt()}',
      ),
      const ChatMessage(
        role: 'user',
        content: '请基于以上证据指纹输出侦察 JSON。',
      ),
    ];
  }

  /// Detailer 阶段的 prompt：组件 API 详情 + 按需证据切片。
  static List<ChatMessage> _buildDetailerMessages({
    required UiSourcePack sourcePack,
    required String characterName,
    required UiScoutPlan scoutPlan,
    required String componentDetails,
    required String detailEvidence,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译架构师。你已确认原卡包含可转译 UI，
现在基于提供的组件 API 详情与证据切片，输出高层 UiDesignPlan（必要时用
assemblies 输出多份方案），交给 Dart 编译器生成 UIEngine JSON。

硬性规则：
1. 只输出一个 JSON 对象，不要 markdown，不要解释。
2. 不要输出内部 assembly JSON。
3. 每个字段/动作都应有 sourceRef。没有证据不要生成。
4. 如果 UI 依赖外部 JS 运行时，写入 unsupported，除非证据中也有静态可还原内容。
5. 优先忠实迁移原 UI 语义，再做移动端适配。不要为了好看新增原卡没有的属性。
6. 使用提供的 columns/density/fill/span 布局意图字段控制空间分配。
''',
      ),
      ChatMessage(
        role: 'user',
        content: '【选型结果】\n'
            'uiMode: ${scoutPlan.uiMode}\n'
            'uiName: ${scoutPlan.uiName}\n'
            '计划组件: ${scoutPlan.components.join(', ')}\n'
            '侦察摘要: ${scoutPlan.evidenceSummary}\n'
            '侦察备注: ${scoutPlan.notes.join('; ')}',
      ),
      ChatMessage(
        role: 'user',
        content: '【组件 API 详情】\n$componentDetails',
      ),
      ChatMessage(
        role: 'user',
        content: '【精选证据】\n$detailEvidence',
      ),
      ChatMessage(
        role: 'user',
        content: '请输出 UiDesignPlan JSON。UiDesignPlan schema 见下方：\n'
            '${UiEngineKnowledgeService.compactPrompt()}',
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
  /// 工作区里的对话按钮会把它作为上下文继续与同一个转译 AI 对话。
  final List<ChatMessage> conversationContext;

  const AiUiInterpretation({
    required this.plans,
    required this.validationWarnings,
    required this.sourcePack,
    required this.conversationContext,
  });
}
