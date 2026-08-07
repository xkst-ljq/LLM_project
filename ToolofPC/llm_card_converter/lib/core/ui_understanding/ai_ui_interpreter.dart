import 'dart:convert';

import '../api_service.dart';
import '../json_ai_client.dart';
import '../conversion_models.dart';
import '../ui_engine_api/ui_engine_api_dictionary.dart';
import 'ui_design_plan.dart';
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

    // ── 阶段 2：Detailer —— 程序确定生命周期，按 mode 分拆生成 ──
    final targetModes = _targetModes(sourcePack, scoutPlan);
    onLog?.call('  UI 生命周期目标：${targetModes.join(' + ')}（Scout mode=${scoutPlan.uiMode} 仅作证据参考）');

    final detailJsons = <Map<String, dynamic>>[];
    final allPlans = <UiDesignPlan>[];
    final transcript = <ChatMessage>[];
    for (final targetMode in targetModes) {
      final result = await _runDetailer(
        sourcePack: sourcePack,
        scoutPlan: scoutPlan,
        characterName: characterName,
        targetMode: targetMode,
        onLog: onLog,
      );
      detailJsons.add(result.json);
      transcript.addAll(result.transcript);
      final parsed = UiDesignPlan.listFromJson(result.json);
      final selected = parsed.where((plan) => plan.uiMode == targetMode).toList();
      allPlans.addAll(selected.isEmpty ? parsed : selected);
    }

    var plans = allPlans;
    var validation = _validatePlans(plans, sourcePack);

    // 语义校验失败时，用“瘦身修复 prompt”：只发错误 + 当前 JSON + 证据摘要，
    // 不再把完整证据切片和组件 API 全量塞回去，避免修复轮爆炸。
    if (!validation.ok) {
      onLog?.call('  UI 方案校验失败：${validation.errors.length} 个错误，准备请求模型修复…');
      final repairMessages = _buildSlimRepairMessages(
        sourcePack: sourcePack,
        targetModes: targetModes,
        currentJson: _wrapDetailJsons(detailJsons),
        errors: validation.errors,
      );
      onLog?.call('  UI 修复 prompt 大小：${_promptSizeLabel(_messageChars(repairMessages))}');
      final repairResult = await JsonAiClient.completeObjectWithTranscript(
        taskName: 'UI 理解方案修复',
        messages: repairMessages,
        temperature: 0.0,
        maxTokens: 5000,
        repairAttempts: 1,
        onLog: onLog,
      );
      plans = UiDesignPlan.listFromJson(repairResult.json);
      validation = _validatePlans(plans, sourcePack);
      transcript.addAll(repairResult.transcript);
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

  static List<String> _targetModes(
    UiSourcePack sourcePack,
    UiScoutPlan scoutPlan,
  ) {
    final out = <String>[];
    final needsOpening =
        sourcePack.alternateGreetings.isNotEmpty || sourcePack.suggestsProfilePool;
    final needsScene = sourcePack.hasNarrativeUiWrapper ||
        sourcePack.hasQuestSchema ||
        sourcePack.hasChoiceBoxSchema ||
        sourcePack.hasFriendsAlbumSchema ||
        sourcePack.hasPlayerStatusSchema;
    if (needsOpening) out.add('opening');
    if (needsScene) out.add('scene');
    if (out.isEmpty && scoutPlan.hasUi) out.add(scoutPlan.uiMode);
    if (out.isEmpty) out.add('extra_companion');
    return out.toSet().toList();
  }

  static Map<String, dynamic> _wrapDetailJsons(
    List<Map<String, dynamic>> detailJsons,
  ) {
    if (detailJsons.length == 1) return detailJsons.first;
    return {'hasUi': true, 'assemblies': detailJsons};
  }

  static List<ChatMessage> _buildSlimRepairMessages({
    required UiSourcePack sourcePack,
    required List<String> targetModes,
    required Map<String, dynamic> currentJson,
    required List<String> errors,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '你是 UiDesignPlan JSON 修复器。只输出修正后的 JSON 对象，不要 markdown，不要解释，不要新增无证据字段。',
      ),
      ChatMessage(
        role: 'user',
        content: '【目标生命周期】${targetModes.join(' + ')}\n'
            '【证据摘要】\n${sourcePack.summaryPrompt()}\n\n'
            '【当前 JSON】\n${jsonEncode(currentJson)}\n\n'
            '【校验错误】\n${errors.map((e) => '- $e').join('\n')}\n\n'
            '请只修复这些错误。若多生命周期存在，继续使用 assemblies。',
      ),
    ];
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
      onLog: onLog,
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

  static List<String> _componentsForTarget(
    UiSourcePack sourcePack,
    UiScoutPlan scoutPlan,
    String targetMode,
  ) {
    final out = <String>{...scoutPlan.components};
    if (targetMode == 'opening') {
      out.addAll(const ['surface', 'text', 'button', 'input']);
    } else if (targetMode == 'scene') {
      out.addAll(const ['surface', 'text', 'progress', 'button', 'input', 'message_flow', 'line']);
      if (sourcePack.hasFriendsAlbumSchema) out.add('indicator');
    }
    return out.toList();
  }

  static Set<int> _regexIndicesForTarget(
    UiSourcePack sourcePack,
    UiScoutPlan scoutPlan,
    String targetMode,
  ) {
    final out = <int>{};

    int? firstEnabledWhere(bool Function(UiRegexEvidence e) test) {
      for (var i = 0; i < sourcePack.regexScripts.length; i++) {
        final evidence = sourcePack.regexScripts[i];
        if (evidence.enabled && test(evidence)) return i;
      }
      return null;
    }

    void addFirst(bool Function(UiRegexEvidence e) test) {
      final index = firstEnabledWhere(test);
      if (index != null) out.add(index);
    }

    bool hasAny(UiRegexEvidence e, List<String> needles) {
      final hay = '${e.scriptName}\n${e.findRegex}\n${e.replaceString}'.toLowerCase();
      return needles.any((needle) => hay.contains(needle.toLowerCase()));
    }

    if (targetMode == 'opening') {
      addFirst((e) => hasAny(e, const ['<Alliance>', 'alliance', '阅读界面']));
      return out.take(1).toSet();
    }

    if (targetMode == 'scene') {
      // 每类证据只取一个代表脚本，避免 quest 皮肤 1/2/3、多个视觉变体同时塞入。
      addFirst((e) => hasAny(e, const ['<Alliance>', 'alliance', '阅读界面']));
      addFirst((e) => hasAny(e, const ['PlayerStatus', '玩家状态栏', '状态栏']));
      addFirst((e) => hasAny(e, const ['{quest:', r'\{quest:', '任务界面']));
      addFirst((e) => hasAny(e, const ['DQ_ChoiceBox', '玩家选项栏', '选项栏']));
      addFirst((e) => hasAny(e, const ['FriendsAlbumPage', '好友列表', '羁绊']));
      return out.take(5).toSet();
    }

    for (final index in scoutPlan.regexIndices) {
      if (index >= 0 &&
          index < sourcePack.regexScripts.length &&
          sourcePack.regexScripts[index].enabled) {
        out.add(index);
      }
    }
    return out.take(5).toSet();
  }

  static Set<int> _worldBookIndicesForTarget(
    UiSourcePack sourcePack,
    UiScoutPlan scoutPlan,
    String targetMode,
  ) {
    if (targetMode == 'opening') return const {};
    final out = <int>{};

    int? firstWhere(bool Function(WorldBookEvidence e) test) {
      for (var i = 0; i < sourcePack.worldBookEvidence.length; i++) {
        if (test(sourcePack.worldBookEvidence[i])) return i;
      }
      return null;
    }

    void addFirst(bool Function(WorldBookEvidence e) test) {
      final index = firstWhere(test);
      if (index != null) out.add(index);
    }

    addFirst((e) => e.content.contains('{quest:') || e.title.contains('任务界面'));
    addFirst((e) => e.content.contains('PlayerStatus') || e.title.contains('玩家状态'));
    addFirst((e) => e.content.contains('FriendsAlbumPage') || e.title.contains('羁绊'));
    return out.take(3).toSet();
  }

  /// 阶段 2：Detailer。按生命周期目标拼「组件 API + 证据切片」，输出单个 plan。
  static Future<JsonAiResult> _runDetailer({
    required UiSourcePack sourcePack,
    required UiScoutPlan scoutPlan,
    required String characterName,
    required String targetMode,
    void Function(String line)? onLog,
  }) async {
    onLog?.call('  精修检索（阶段 2/$targetMode）：拼装组件 API + 证据切片…');
    final components = _componentsForTarget(sourcePack, scoutPlan, targetMode);
    final regexIndices = _regexIndicesForTarget(sourcePack, scoutPlan, targetMode);
    final worldBookIndices = _worldBookIndicesForTarget(sourcePack, scoutPlan, targetMode);
    final componentDetails = UiEngineApiDictionary.detailForComponents(
      components,
      includeLinkerGroups: false,
    );
    final detailEvidence = sourcePack.detailPromptFor(
      regexIndices: regexIndices,
      pluginIndices: scoutPlan.pluginIndices.toSet(),
      htmlIndices: targetMode == 'opening' ? const <int>{} : scoutPlan.htmlIndices.toSet(),
      worldBookIndices: worldBookIndices,
      includeFullBranches: false,
    );
    final messages = _buildDetailerMessages(
      sourcePack: sourcePack,
      characterName: characterName,
      scoutPlan: scoutPlan,
      targetMode: targetMode,
      componentDetails: componentDetails,
      detailEvidence: detailEvidence,
    );
    onLog?.call('  精修组件 API 大小：${componentDetails.runes.length} 字符；证据切片大小：${detailEvidence.runes.length} 字符');
    onLog?.call('  UI 精修/$targetMode prompt 总大小：${_promptSizeLabel(_messageChars(messages))}');
    if (regexIndices.isNotEmpty || worldBookIndices.isNotEmpty) {
      onLog?.call('  精修/$targetMode 证据索引：regex=${regexIndices.join(',')} worldbook=${worldBookIndices.join(',')} branches=summary');
    }
    var received = 0;
    final result = await JsonAiClient.completeObjectWithTranscript(
      taskName: 'UI 理解/$targetMode',
      messages: messages,
      temperature: 0.12,
      maxTokens: targetMode == 'opening' ? 2600 : 4200,
      timeout: const Duration(seconds: 360),
      repairAttempts: 1,
      onLog: onLog,
      onDelta: (delta) {
        received += delta.length;
        if (received % 400 < delta.length) {
          onLog?.call('  生成 $targetMode 中…（已接收 $received 字符）');
        }
      },
    );
    onLog?.call('  $targetMode 生成完成，已接收 $received 字符');
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
    required String targetMode,
    required String componentDetails,
    required String detailEvidence,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译架构师。你已确认原卡包含可转译 UI，
现在基于提供的组件 API 详情与证据切片，只输出目标生命周期的一份 UiDesignPlan，
交给 Dart 编译器生成 UIEngine JSON。不要输出 assemblies；程序会合并多个生命周期。

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
        content: '【目标生命周期】$targetMode（程序强制；Scout uiMode=${scoutPlan.uiMode} 仅供参考）\n'
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
        content: '请输出单个 UiDesignPlan JSON（uiMode 必须为 $targetMode）。最小 schema 与规则如下：\n'
            '${_minimalSchemaPrompt(targetMode)}',
      ),
    ];
  }

  static String _minimalSchemaPrompt(String targetMode) => """
{
  "hasUi": true,
  "confidence": 0.0,
  "uiMode": "$targetMode",
  "uiName": "简短名称",
  "evidenceSummary": "证据摘要",
  "sourceRefs": ["data..."],
  "visualStyle": {"styleName":"...","pcbColor":"#111318","panelColor":"#1E232B","titleColor":"#FFFFFF","labelColor":"#AAB0BC","valueColor":"#E8EDF5","accentColor":"#4FA3D1","buttonBgColor":"#2A3340","barFillColor":"#4FA3D1","barTrackColor":"#2A2D36","borderRadius":14,"glow":false},
  "layout": {"kind":"opening_choices|scene_dashboard|single_panel","navigation":"tabs|swipe|tabs_and_swipe|none","columns":1,"pages":[{"title":"页面","role":"story|stats|tasks|form","type":"base|overlay","parentPage":"父页","columns":1,"density":"compact|normal|spacious","fill":true}]},
  "fields": [{"name":"字段名","sourceKey":"Key","group":"精确分组","type":"number|text|bool","display":"progress|text|badge","overflow":"ellipsis|wrap|scroll","initialValue":"...","branchInitialValues":{"1":"..."},"min":0,"max":100,"owner":"player|char|neutral","span":1,"layout":"","page":"页面","sourceRef":"证据路径"}],
  "inputs": [{"name":"输入名","sourceKey":"UserProfile_Name","placeholder":"...","initialValue":"","sendOnSubmit":false,"targetKind":"status_field|none","page":"页面","sourceRef":"证据路径"}],
  "actions": [{"label":"按钮文案","sendText":"发送文本；opening 分支按钮通常留空","keyAction":false,"branchIndex":0,"page":"页面","sourceRef":"证据路径"}],
  "unsupported": [{"kind":"...","reason":"...","sourceRef":"..."}],
  "notes": []
}
规则：
- 只输出这个 mode 的单个 UiDesignPlan，不要 assemblies。
- opening：只做开场方向选择与少量资料输入；不要放完整 PlayerStatus/任务板。
- scene：必须有 role=story 的 base 页以插入 message_flow；任务/状态/羁绊等低频详情用 overlay。
- 长任务板/好友列表可用 initialValue="__AUTO_QUEST_BOARD__" / "__AUTO_FRIENDS_ALBUM_EMPTY__" 让 Dart 自动填充，减少输出长度；TaskBoard 在 branch 1 无任务时写 branchInitialValues["1"]="暂无公会任务，待剧情更新"。
- 所有字段/动作/输入必须有 sourceRef；meaningful text 不要 ellipsis。
""";

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
