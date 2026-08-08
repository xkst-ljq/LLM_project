import '../api_service.dart';
import '../json_ai_client.dart';
import '../conversion_models.dart';
import '../ui_translate_trace.dart';
import 'ui_design_plan.dart';
import 'ui_engine_knowledge_service.dart';
import 'ui_plan_validator.dart';
import 'ui_scout_result.dart';
import 'ui_source_pack.dart';
import 'ui_source_pack_builder.dart';
import 'ui_visual_profile.dart';

/// AI UI 理解阶段：读整张卡的证据，输出 UiDesignPlan。
///
/// **分级转译**（阶段 0 → 1 → 2），避免"单轮全量注入"里多套生命周期挤在
/// 一起导致 AI 漏掉某套 UI、以及大证据包下空回复：
///
/// - 阶段 0 **Scout（判级）**：只注入证据**指纹**（summaryPrompt），让 AI
///   先判断「整卡需要哪几套 UI、每套要看哪些证据的细节」。
/// - 阶段 1 **Detailer（逐套设计）**：对每套 UI 各发一轮独立请求（可并行），
///   只允许输出单套 UiDesignPlan，互相不干扰。
/// - 阶段 2 **Merge（汇总校验）**：合并所有 plan，跑结构 + 跨 assembly
///   组合校验，失败再给一次"只修 JSON"的修复机会。
///
/// 任何一级失败都回落原来的单轮全量逻辑（[_understandSingleShot]），
/// 保证最坏情况不劣于分级之前。
class AiUiInterpreter {
  const AiUiInterpreter._();

  static Future<AiUiInterpretation> understand({
    required Map<String, dynamic> sourceJson,
    required CardConversionResult baseResult,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
    UiVisualProfile? visualProfile,
  }) async {
    final sourcePack = UiSourcePackBuilder.build(sourceJson);
    final characterName = baseResult.characterName;

    // 阶段 0：Scout 判级。失败（异常 / 无 UI / 无有效选型）直接回落单轮。
    UiScoutOutcome? scoutOutcome;
    try {
      scoutOutcome = await _runScout(
        sourcePack: sourcePack,
        characterName: characterName,
        visualProfile: visualProfile,
        onLog: onLog,
        traceBuilder: traceBuilder,
      );
    } catch (e) {
      onLog?.call('  UI 侦察失败（${e.toString().split('\n').first}），回落单轮全量注入…');
    }
    final scout = scoutOutcome?.scout;
    if (scout == null || !scout.hasUi || scout.assemblies.isEmpty) {
      return _understandSingleShot(
        sourcePack: sourcePack,
        characterName: characterName,
        visualProfile: visualProfile,
        onLog: onLog,
        traceBuilder: traceBuilder,
      );
    }
    onLog?.call('  侦察判级：需要 ${scout.assemblies.length} 套 UI（${scout.assemblies.map((a) => a.uiMode).join(', ')}）');

    // 阶段 1：逐套单独设计（并行）。单套失败只丢该套，不影响其他。
    final transcripts = <ChatMessage>[...scoutOutcome!.transcript];
    final plans = <UiDesignPlan>[];
    final failed = <String>[];
    final detailerResults = await Future.wait(scout.assemblies.map((spec) async {
      try {
        return await _runDetailer(
          spec: spec,
          sourcePack: sourcePack,
          characterName: characterName,
          visualProfile: visualProfile,
          onLog: onLog,
          traceBuilder: traceBuilder,
        );
      } catch (e) {
        return UiDetailerOutcome.error(
          mode: spec.uiMode,
          error: e.toString().split('\n').first,
        );
      }
    }));
    for (final outcome in detailerResults) {
      if (outcome.plan != null) {
        plans.add(outcome.plan!);
        transcripts.addAll(outcome.transcript);
      } else if (outcome.error != null) {
        failed.add('${outcome.mode}: ${outcome.error}');
      }
    }
    if (failed.isNotEmpty) {
      onLog?.call('  有 ${failed.length} 套 UI 单独设计失败：${failed.join('；')}');
    }
    if (plans.isEmpty) {
      onLog?.call('  全部 UI 单独设计均失败，回落单轮全量注入…');
      return _understandSingleShot(
        sourcePack: sourcePack,
        characterName: characterName,
        visualProfile: visualProfile,
        onLog: onLog,
        traceBuilder: traceBuilder,
      );
    }

    // 阶段 2：汇总 + 校验 + 修复。
    final repaired = await _validateAndRepair(
      plans: plans,
      sourcePack: sourcePack,
      baseTranscript: transcripts,
      onLog: onLog,
      traceBuilder: traceBuilder,
    );

    if (!repaired.validation.ok) {
      onLog?.call('  AI 修复后仍未通过校验，但为了保证 AI 的自主性，我们将保留其原始意图，仅由编译器尝试容错。');
    }

    return AiUiInterpretation(
      plans: repaired.plans,
      validationWarnings: [
        ...repaired.validation.warnings,
        ...failed.map((e) => 'UI 单独设计失败，已跳过该套：$e'),
      ],
      sourcePack: sourcePack,
      conversationContext: repaired.transcript,
    );
  }

  // ─────────────────── 阶段 0：Scout（判级） ───────────────────

  static Future<UiScoutOutcome> _runScout({
    required UiSourcePack sourcePack,
    required String characterName,
    UiVisualProfile? visualProfile,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final knowledge = UiEngineKnowledgeService.compactPromptSlim();
    final summary = sourcePack.summaryPrompt();

    final step = traceBuilder?.beginStep(
      stage: 'scout',
      targetMode: '',
      label: 'UI 侦察（判级）',
    );

    final messages = [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译侦察员。你的任务只有一个：先看整张卡需要哪几套 UI，再为每套指定要看哪些证据的细节。**不要设计 UI 细节，不要输出 fields/actions/layout。**
1. **多开场白（alternate_greetings 非空，即开场白 ≥ 2 条）→ 必须含 uiMode=opening**，让玩家选择开场方向，不依赖原卡是否写了 onclick/send 按钮。
2. 有 `<生命>` 等 XML 标签 / `{PlayerStatus|...}` / regex 仪表盘 / `<正文>` 包裹 → 持久 UI：
   - 高信息密度/正文被 UI 包裹 → scene（全屏沉浸终端）；
   - 专项且单一（1~2 个字段、单一面板、轻量状态条）→ extra_companion（窄伴生栏）或 extra_sticky（顶层/底部工具条）。
   - **严禁**把低密度"专项单一"卡过度设计成 scene。
3. scene 与 extra_companion 互斥——一张卡不两个常驻生命周期并存。
4. 每套 UI 的 neededDetail 列出它要看哪些证据的细节索引（regex/plugin/html/worldbook），直接取自上面的证据指纹。多开场白时 opening 应 includeFullBranches=true 看完整开场白分支。
5. 证据很少/没有 UI 时 hasUi=false，assemblies 留空。
输出必须是合法的 UiScoutResult JSON。绝不解释，绝不使用 markdown。
''',
      ),
      ChatMessage(role: 'user', content: '【UIEngine 知识库】\n$knowledge'),
      ChatMessage(
        role: 'user',
        content:
            '【待判级角色卡：$characterName】\n$summary\n\n'
            '${_scoutSelectionGuide(sourcePack)}${_visualSection(visualProfile)}',
      ),
      const ChatMessage(
        role: 'user',
        content: '请基于以上证据指纹输出 UiScoutResult JSON：hasUi、evidenceSummary、'
            'sourceRefs、assemblies[]（每套含 uiMode/uiName/reasons/evidenceSummary/sourceRefs/neededDetail）。'
            'neededDetail 里 regex/plugin/html/worldbook 填证据指纹里出现的下标。再次强调：只能输出 JSON 对象，不要输出 UiDesignPlan 细节。',
      ),
    ];
    onLog?.call('  UI 侦察：注入证据指纹 ${_promptSizeLabel(_messageChars(messages))}');

    var result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 侦察',
      messages: messages,
      temperature: 0.12,
      maxTokens: 4000,
      onLog: onLog,
      trace: step,
    );
    step?.complete(parsedOk: true, parsedJson: result.json);

    var scout = UiScoutResult.fromJson(result.json);
    // hasUi=true 但没给出任何有效选型 → 非法，给一次只修 JSON 的机会。
    if (scout.hasUi && scout.assemblies.isEmpty) {
      onLog?.call('  UI 侦察判定有 UI 但未给出选型，请求模型修复…');
      final repairStep = traceBuilder?.beginStep(
        stage: 'repair',
        targetMode: '',
        label: 'UI 侦察修复',
      );
      final repairResult = await JsonAiClient.completeObjectWithTranscript(
        taskName: 'UI 侦察修复',
        messages: [
          ...result.transcript,
          const ChatMessage(
            role: 'user',
            content: '你判定 hasUi=true 但 assemblies 为空。请依据证据指纹补充 UiScoutResult JSON，'
                '列出需要生成的每一套 UI（uiMode 只能是 opening/scene/extra_sticky/extra_companion）及对应的 neededDetail。',
          ),
        ],
        temperature: 0.0,
        maxTokens: 4000,
        onLog: onLog,
        trace: repairStep,
      );
      repairStep?.complete(parsedOk: true, parsedJson: repairResult.json);
      scout = UiScoutResult.fromJson(repairResult.json);
      result = repairResult;
    }

    return UiScoutOutcome(scout: scout, transcript: result.transcript);
  }

  /// 给 Scout 的规则级选型建议（模式判据 + 证据索引 + 规则 modeSuggestion）。
  static String _scoutSelectionGuide(UiSourcePack sourcePack) {
    final b = StringBuffer();
    b.writeln('\n# 证据索引（neededDetail 从这里挑下标）');
    for (var i = 0; i < sourcePack.regexScripts.length; i++) {
      final e = sourcePack.regexScripts[i];
      b.writeln('- regex[$i] ${e.scriptName} enabled=${e.enabled} find=${e.findRegex.runes.length}c replace=${e.replaceString.runes.length}c');
    }
    for (var i = 0; i < sourcePack.pluginScripts.length; i++) {
      b.writeln('- plugin[$i] ${sourcePack.pluginScripts[i].content.runes.length}c');
    }
    for (var i = 0; i < sourcePack.htmlSnippets.length; i++) {
      b.writeln('- html[$i] ${sourcePack.htmlSnippets[i].text.runes.length}c');
    }
    for (var i = 0; i < sourcePack.worldBookEvidence.length; i++) {
      b.writeln('- worldbook[$i] ${sourcePack.worldBookEvidence[i].title} ${sourcePack.worldBookEvidence[i].content.runes.length}c');
    }
    b.writeln('\n# 规则判级参考（你可参考或覆盖）');
    b.writeln('多开场白=${sourcePack.alternateGreetings.isNotEmpty}；'
        '状态/正文包裹=${sourcePack.hasPlayerStatusSchema || sourcePack.hasXmlStatusTags || sourcePack.hasNarrativeUiWrapper}；'
        '信息密度=${sourcePack.densityAssessment().level.name}');
    final suggestion = sourcePack.modeSuggestion();
    if (suggestion.isNotEmpty) {
      b.writeln('规则建议：$suggestion');
    }
    return b.toString();
  }

  // ─────────────────── 阶段 1：Detailer（逐套设计） ───────────────────

  static Future<UiDetailerOutcome> _runDetailer({
    required UiAssemblySpec spec,
    required UiSourcePack sourcePack,
    required String characterName,
    UiVisualProfile? visualProfile,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final knowledge = UiEngineKnowledgeService.compactPromptSlim();
    final detail = sourcePack.detailPromptFor(
      regexIndices: spec.neededDetail.regexIndices,
      pluginIndices: spec.neededDetail.pluginIndices,
      htmlIndices: spec.neededDetail.htmlIndices,
      worldBookIndices: spec.neededDetail.worldBookIndices,
      includeFullBranches: spec.neededDetail.includeFullBranches,
    );

    final step = traceBuilder?.beginStep(
      stage: 'detailer',
      targetMode: spec.uiMode,
      label: 'UI 设计/${spec.uiName}',
    );

    final messages = [
      ChatMessage(
        role: 'system',
        content: '你是 SillyTavern 角色卡 UI 设计师。本回合**只设计一套 UI（uiMode=${spec.uiMode}）**。'
            '**严禁**输出 assemblies 数组，严禁设计其他 UI 生命周期。'
            '输出一个合法 UiDesignPlan JSON 对象（hasUi=true，含该套的 fields/inputs/actions/layout/visualStyle）。',
      ),
      ChatMessage(role: 'user', content: '【UIEngine 知识库】\n$knowledge'),
      ChatMessage(
        role: 'user',
        content:
            '【角色卡：$characterName | 本套 ${spec.uiMode}/${spec.uiName}】\n$detail${_visualSection(visualProfile)}',
      ),
      ChatMessage(
        role: 'user',
        content: '【本套设计约束】\n'
            'uiMode=${spec.uiMode}\n'
            'uiName=${spec.uiName}\n'
            '选型理由：${spec.reasons.isEmpty ? '(无)' : spec.reasons.join('；')}\n'
            '证据依据：${spec.evidenceSummary.isEmpty ? '(无)' : spec.evidenceSummary}\n'
            'sourceRefs：${spec.sourceRefs.isEmpty ? '(无)' : spec.sourceRefs.join(', ')}\n\n'
            '请只输出这一套 UiDesignPlan JSON 对象。再次强调：不能输出 assemblies，不能设计别的 UI。',
      ),
    ];
    onLog?.call('  UI 设计/${spec.uiName}：prompt ${_promptSizeLabel(_messageChars(messages))}');

    var result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 设计/${spec.uiName}',
      messages: messages,
      temperature: 0.12,
      maxTokens: 12000,
      onLog: onLog,
      trace: step,
    );
    step?.complete(parsedOk: true, parsedJson: result.json);

    // 单套 plan：把顶层 hasUi / visualStyle 等兜底补全，避免 detailer 漏字段。
    final json = Map<String, dynamic>.from(result.json);
    json['uiMode'] = spec.uiMode;
    json.putIfAbsent('uiName', () => spec.uiName);
    json.putIfAbsent('hasUi', () => true);
    json.putIfAbsent('evidenceSummary', () => spec.evidenceSummary);
    if (spec.sourceRefs.isNotEmpty) {
      json['sourceRefs'] = spec.sourceRefs;
    }
    final plan = UiDesignPlan.fromJson(json);
    return UiDetailerOutcome.plan(plan: plan, transcript: result.transcript);
  }

  // ─────────────────── 阶段 2：汇总 + 校验 + 修复 ───────────────────

  /// 阶段 2 的校验 + 修复。
  ///
  /// **修复轮绝不能删掉已设计好的 UI**：修复必须保持各套 uiMode 的覆盖
  /// （跨套组合校验要求的 opening/scene/companion 等一个都不能少）。
  ///
  /// - 先做结构校验（[UiPlanValidator.validate]）。单套结构错误 → 把该套
  ///   **单独**交给模型重写，其余 plan 原样保留，绝不牵连；多套都有结构
  ///   错误 → 一次性整体修复。
  /// - 再跑跨套组合校验（[UiPlanValidator.validateAssemblies]）。组合错误
  ///   → 整体修复，但修复后把被漏掉的 uiMode 用已设计的原方案补回。
  /// - 修复后若覆盖的 uiMode 数不增反减 → 丢弃修复结果，退回原方案。
  static Future<UiRepairedResult> _validateAndRepair({
    required List<UiDesignPlan> plans,
    required UiSourcePack sourcePack,
    required List<ChatMessage> baseTranscript,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final allModes = {for (final p in plans) p.uiMode};
    final repaired = await _repairStructural(
      plans: plans,
      sourcePack: sourcePack,
      baseTranscript: baseTranscript,
      onLog: onLog,
      traceBuilder: traceBuilder,
    );
    var transcript = repaired.transcript;
    var current = repaired.plans;

    final assembly = await _repairAssemblyCoverage(
      plans: current,
      sourcePack: sourcePack,
      originalPlans: plans,
      baseTranscript: transcript,
      onLog: onLog,
      traceBuilder: traceBuilder,
    );
    current = assembly.plans;
    transcript = assembly.transcript;

    // 汇总最终校验结果。即便修复失败也保留结果，编译器会尝试容错，
    // 但会带上未通过校验的 warning 交给用户复核。
    final validation = _validatePlans(current, sourcePack);
    final finalModes = {for (final p in current) p.uiMode};
    // 覆盖保护：只要没有"整个 uiMode 生命周期"消失，就接受修复结果。
    // 用 containsAll 而非长度比较——重复 uiMode / scene+companion 互斥
    // 这类"多造"错误修复后 mode 数会减少，但每个 mode 仍各保留一份，
    // 不能因此丢弃修复。只有某套生命周期被整个删掉才退回原方案。
    final missingModes = allModes.difference(finalModes);
    if (missingModes.isNotEmpty) {
      onLog?.call('  修复导致 UI 生命周期缺失（${missingModes.join(', ')}），丢弃修复结果，退回原方案。');
      return UiRepairedResult(
        plans: plans,
        validation: validation,
        transcript: transcript,
      );
    }
    return UiRepairedResult(
      plans: current,
      validation: validation,
      transcript: transcript,
    );
  }

  /// 结构校验 + 修复：单套结构错误 → 逐套单独修复，保持 uiMode 不丢。
  static Future<UiRepairedResult> _repairStructural({
    required List<UiDesignPlan> plans,
    required UiSourcePack sourcePack,
    required List<ChatMessage> baseTranscript,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final perPlan = <UiPlanValidationResult>[
      for (final p in plans) UiPlanValidator.validate(p, sourcePack),
    ];
    final structuralErrors = <(UiDesignPlan, List<String>)>[
      for (var i = 0; i < plans.length; i++)
        if (!perPlan[i].ok) (plans[i], perPlan[i].errors),
    ];
    if (structuralErrors.isEmpty) {
      return UiRepairedResult(
        plans: plans,
        validation: _validatePlans(plans, sourcePack),
        transcript: baseTranscript,
      );
    }
    final step = traceBuilder?.beginStep(
      stage: 'repair',
      targetMode: '',
      label: 'UI 方案修复',
    );
    onLog?.call('  结构校验失败：${structuralErrors.length} 套（${structuralErrors.map((e) => e.$1.uiMode).join(', ')}）需修复。');
    var repairedPlans = <UiDesignPlan>[];
    final seen = <String>{};
    for (final plan in plans) {
      if (seen.add(plan.uiMode)) repairedPlans.add(plan);
    }
    for (final entry in structuralErrors) {
      final mode = entry.$1.uiMode;
      try {
        // 每套错误用**独立**修复请求：messages 只包含该套的错误清单，
        // 避免多条"只输出 X 的修正"指令挤在同一请求里互相冲突，
        // 导致模型输出内容被强制标错 uiMode。
        final messages = [
          ...baseTranscript,
          ChatMessage(
            role: 'user',
            content: '以下这套 UiDesignPlan（uiMode=$mode）没通过结构校验：\n'
                '${entry.$2.map((e) => '- $e').join('\n')}\n\n'
                '请只输出这一套 uiMode=$mode 的修正后 UiDesignPlan JSON 对象。'
                '【关键】必须保持 uiMode 与 uiName 不变，只修正字段/页面等结构问题；'
                '不要引入其他生命周期，不要输出 assemblies 数组。',
          ),
        ];
        final result = await JsonAiClient.completeObjectWithTranscript(
          taskName: 'UI 方案修复/$mode',
          messages: messages,
          temperature: 0.0,
          maxTokens: 12000,
          onLog: onLog,
          trace: step,
        );
        final json = Map<String, dynamic>.from(result.json);
        json['uiMode'] = mode;
        json.putIfAbsent('uiName', () => entry.$1.uiName);
        json.putIfAbsent('hasUi', () => true);
        final fixed = UiDesignPlan.fromJson(json);
        repairedPlans = mergeFixedPlans(repairedPlans, fixed);
        _logRepairResult(onLog, 'UI 方案修复/$mode', step);
      } catch (e) {
        onLog?.call('  UI 方案修复/$mode 失败（${e.toString().split('\n').first}），保留原方案。');
      }
    }
    step?.complete(parsedOk: true);
    return UiRepairedResult(
      plans: repairedPlans,
      validation: _validatePlans(repairedPlans, sourcePack),
      transcript: baseTranscript,
    );
  }

  /// 把修复好的单套 plan 并入列表：同 uiMode 的原 plan 被**替换**而非追加。
  ///
  /// 结构修复是逐套进行的，原方案 + 修复版如果同时保留，同一套 UI 会被
  /// 编译成两份 assembly（用户看到的"为什么 4 份 UI"）。所以修复结果
  /// 必须顶替同 uiMode 的原 plan；若列表里还没有该 mode 才追加。
  static List<UiDesignPlan> mergeFixedPlans(
    List<UiDesignPlan> plans,
    UiDesignPlan fixed,
  ) {
    final out = List<UiDesignPlan>.of(plans);
    final existing = out.indexWhere((p) => p.uiMode == fixed.uiMode);
    if (existing >= 0) {
      out[existing] = fixed;
    } else {
      out.add(fixed);
    }
    return out;
  }

  /// 跨套组合校验 + 修复：整体修复后把被漏掉的 uiMode 用原方案补回。
  static Future<UiRepairedResult> _repairAssemblyCoverage({
    required List<UiDesignPlan> plans,
    required UiSourcePack sourcePack,
    required List<UiDesignPlan> originalPlans,
    required List<ChatMessage> baseTranscript,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
    final assembly = UiPlanValidator.validateAssemblies(plans, sourcePack);
    if (assembly.ok) {
      return UiRepairedResult(
        plans: plans,
        validation: assembly,
        transcript: baseTranscript,
      );
    }
    final step = traceBuilder?.beginStep(
      stage: 'repair',
      targetMode: '',
      label: 'UI 方案组合修复',
    );
    final messages = [
      ...baseTranscript,
      ChatMessage(
        role: 'user',
        content: '以下多套 UiDesignPlan 组合关系没通过校验：\n'
            '${assembly.errors.map((e) => '- $e').join('\n')}\n\n'
            '请输出修正后的完整 JSON（可含顶层 assemblies 数组，包含全部需要的 UI）。'
            '【关键】角色卡需要这些生命周期：${originalPlans.map((p) => p.uiMode).join(', ')}。'
            '它们缺一不可，请全部保留。',
      ),
    ];
    onLog?.call('  组合校验失败：${assembly.errors.length} 个错误，请求整体修复…');
    JsonAiResult result;
    try {
      result = await JsonAiClient.completeObjectWithTranscript(
        taskName: 'UI 方案组合修复',
        messages: messages,
        temperature: 0.0,
        maxTokens: 16000,
        onLog: onLog,
        trace: step,
      );
    } catch (e) {
      step?.complete(parsedOk: true, error: e.toString());
      onLog?.call('  组合修复请求失败（${e.toString().split('\n').first}），保留原方案。');
      return UiRepairedResult(
        plans: plans,
        validation: assembly,
        transcript: baseTranscript,
      );
    }
    var fixed = UiDesignPlan.listFromJson(result.json).where((p) => p.hasUi).toList();
    // 补回被修复模型漏掉的 uiMode（用已设计的原方案），确保覆盖不丢。
    final restored = restoreDroppedModes(fixed, originalPlans, onLog);
    _logRepairResult(onLog, 'UI 方案组合修复', step);
    return UiRepairedResult(
      plans: restored,
      validation: _validatePlans(restored, sourcePack),
      transcript: result.transcript,
    );
  }

  /// 把被修复结果漏掉的 uiMode（相对 [originals]）用原方案补回。
  ///
  /// 修复轮只该"修正"不该"删 UI"：模型可能在整体修复时顺手丢掉某套已
  /// 设计好的生命周期。这里保证设计成果不因修复而凭空消失。
  /// 返回补全后的列表；[onLog] 用于记录每套补回。
  static List<UiDesignPlan> restoreDroppedModes(
    List<UiDesignPlan> fixed,
    List<UiDesignPlan> originals,
    void Function(String line)? onLog,
  ) {
    final out = List<UiDesignPlan>.of(fixed);
    final covered = {for (final p in out) p.uiMode};
    final originalByMode = {for (final p in originals) p.uiMode: p};
    var restored = false;
    for (final mode in originalByMode.keys) {
      if (!covered.contains(mode)) {
        out.add(originalByMode[mode]!);
        covered.add(mode);
        restored = true;
        onLog?.call('  修复漏掉了 uiMode=$mode，用原方案补回。');
      }
    }
    if (restored) {
      onLog?.call('  已补回被修复轮漏掉的 UI，校验重跑…');
    }
    return out;
  }

  /// 修复轮完成后写一条简洁的日志/trace 诊断。
  static void _logRepairResult(
    void Function(String line)? onLog,
    String label,
    TraceStepBuilder? step,
  ) {
    onLog?.call('  $label：修复完成。');
    step?.addDiagnostic('修复完成');
  }

  /// 原「单轮全量注入」实现，作为分级各阶段失败时的整体回退。
  ///
  /// 一次请求把「知识库 + 完整证据包」发给模型，输出完整 UiDesignPlan
  /// （必要时用 assemblies 表达多个生命周期）。
  static Future<AiUiInterpretation> _understandSingleShot({
    required UiSourcePack sourcePack,
    required String characterName,
    UiVisualProfile? visualProfile,
    void Function(String line)? onLog,
    UiTranslateTraceBuilder? traceBuilder,
  }) async {
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
      visualProfile: visualProfile,
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
    // 修复请求失败（网络/解析异常）不应中断整个转译——保留原方案继续。
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
            '请只输出修正后的 JSON 对象。确保满足所有 schema 要求。'
            '【关键】这些 uiMode 缺一不可，必须全部保留：${plans.map((p) => p.uiMode).join(', ')}。',
      );
      try {
        final repairResult = await JsonAiClient.completeObjectWithTranscript(
          taskName: 'UI 理解方案修复',
          messages: [...transcript, repairPrompt],
          temperature: 0.0,
          maxTokens: 16000,
          onLog: onLog,
          trace: repairStep,
        );
        repairStep?.complete(parsedOk: true, parsedJson: repairResult.json);
        final repairedPlans = UiDesignPlan.listFromJson(repairResult.json);
        validation = _validatePlans(repairedPlans, sourcePack);
        transcript = repairResult.transcript;
        // 修复若丢掉了原方案的 uiMode（模型“顺手”删 UI），用原方案补回，
        // 保证已设计的 UI 不因修复而凭空消失。
        plans = restoreDroppedModes(repairedPlans, plans, onLog);
        if (plans.length > repairedPlans.length) {
          validation = _validatePlans(plans, sourcePack);
        }
      } catch (e) {
        repairStep?.complete(parsedOk: true, error: e.toString());
        onLog?.call('  修复请求失败（${e.toString().split('\n').first}），保留原方案。');
      }
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

  static String _visualSection(UiVisualProfile? visualProfile) {
    if (visualProfile == null || visualProfile.isEmpty) return '';
    return '\n\n${visualProfile.toPromptSlim()}';
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
    UiVisualProfile? visualProfile,
  }) {
    final visualSection = (visualProfile == null || visualProfile.isEmpty)
        ? ''
        : '\n\n${visualProfile.toPromptSlim()}';
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译架构师。你的任务是阅读原卡证据，智能地将其转译为 LLM Project UIEngine 的高层 UiDesignPlan。

【核心使命：多 UI 组合是“工业标准”】
1. **Assemblies 组合模式（必须执行）**：一张 SillyTavern 卡绝不是单一的 UI。你必须习惯于同时输出多个组件：
   - **Opening** (必选)：处理 `first_mes` 和 `alternate_greetings` 里的所有 `onclick/send` 按钮、身份选择及初始资料填写。
   - **Extra_Companion** (常驻推荐)：处理 `regex_scripts` 定义的监控面板、属性栏。这是最符合原版“状态栏”体验的模式。
   - **多 UI 输出惯例**：只要检测到上述两种证据，你**必须**使用 `{"assemblies": [opening方案, extra_companion方案]}` 结构。严禁只给其中一个，严禁询问“要不要补全”。
2. **彻底打破系统套路**：严禁套用“属性/档案/选项”模板。根据角色身份构建独特布局（如：商店、技能、个人终端）。
3. **视觉风格定制**：配色必须反映角色的灵魂（魔法少女-明亮/发光，硬汉-工业/粗犷，地牢-暗黑/压抑）。尽量还原原卡的 CSS 视觉特征（渐变/描边/发光/气泡配色），映射到 visualStyle 字段；拿不准就留空。
4. **空间利用**：优先使用 `columns: 2` 或 `3`。数值字段应紧凑。

【执行指令】
- 输出必须是合法的 UiDesignPlan JSON，放在顶级 `assemblies` 列表中。
- 绝不解释，绝不输出思考链，绝不使用 markdown。
''',
      ),
      ChatMessage(
        role: 'user',
        content: '【UIEngine 知识库】\n$knowledge',
      ),
      ChatMessage(
        role: 'user',
        content: '【待分析角色卡：$characterName】\n${sourcePack.toPromptTextSlim()}$visualSection',
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
    // 跨 assembly 组合校验：多开场白必须含 opening 并做差异化、高密度
    // 场景建议等，须在所有单 plan 校验通过/汇总后统一追加。
    final assemblyResult = UiPlanValidator.validateAssemblies(plans, sourcePack);
    errors.addAll(assemblyResult.errors);
    warnings.addAll(assemblyResult.warnings);
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

/// [AiUiInterpreter._runScout] 的产出：判级结果 + 该次请求的转录。
class UiScoutOutcome {
  final UiScoutResult scout;
  final List<ChatMessage> transcript;

  const UiScoutOutcome({required this.scout, required this.transcript});
}

/// [AiUiInterpreter._runDetailer] 的产出：单套 plan（成功）或错误（失败）。
///
/// 并行 detailer 的单套失败不抛整体异常，而是以 [error] 形式返回，
/// 由调用方记录后跳过该套。
class UiDetailerOutcome {
  final UiDesignPlan? plan;
  final List<ChatMessage> transcript;
  final String? error;
  final String mode;

  UiDetailerOutcome.plan({
    required this.plan,
    required this.transcript,
  })  : error = null,
        mode = plan!.uiMode;

  const UiDetailerOutcome.error({
    required this.mode,
    required this.error,
  })  : plan = null,
        transcript = const [];
}

/// [AiUiInterpreter._validateAndRepair] 的产出：修复后的 plans + 校验结果 + 转录。
class UiRepairedResult {
  final List<UiDesignPlan> plans;
  final UiPlanValidationResult validation;
  final List<ChatMessage> transcript;

  const UiRepairedResult({
    required this.plans,
    required this.validation,
    required this.transcript,
  });
}
