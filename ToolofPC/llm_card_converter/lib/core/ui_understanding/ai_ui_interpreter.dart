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
            '请只输出修正后的 JSON 对象。不要新增原卡没有证据的 UI 字段；'
            '如果证据不足，应改为 hasUi=false。',
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

    // 校验仍失败，或 AI 判定无 UI：回落确定性骨架（如果证据支持）。
    if (!validation.ok && _canBuildDeterministicFallback(sourcePack)) {
      onLog?.call('  AI 方案未通过校验，使用确定性骨架兜底。');
      return _deterministicInterpretation(
        sourcePack: sourcePack,
        characterName: characterName,
        traceBuilder: traceBuilder,
      );
    }

    if (!validation.ok) {
      throw FormatException('AI UI 方案未通过校验：${validation.errors.join('；')}');
    }

    // ── 补齐缺失的生命周期 ──
    // AI 对「多生命周期判断」不可靠：可能只输出 opening 漏 scene，
    // 或只输出 scene 漏 opening。用程序确定性地检查证据，补齐缺失项。
    // AI 输出什么就保留什么；缺失的用确定性骨架补上，不重复覆盖。
    final existingModes = plans.map((p) => p.uiMode).toSet();
    final toAppend = <Map<String, dynamic>>[];
    if (_canBuildOpeningDeterministically(sourcePack) &&
        !existingModes.contains('opening')) {
      onLog?.call('  证据支持 opening 但 AI 未输出，用确定性骨架补齐。');
      final detStep = traceBuilder?.beginStep(
        stage: 'deterministic',
        targetMode: 'opening',
        label: '确定性补齐/opening',
      );
      final opening = _buildDeterministicOpeningJson(sourcePack, characterName);
      toAppend.add(opening);
      detStep?.complete(parsedOk: true, parsedJson: opening);
    }
    if (_canBuildSceneFallback(sourcePack) &&
        !existingModes.contains('scene')) {
      onLog?.call('  证据支持 scene 但 AI 未输出，用确定性骨架补齐。');
      final detStep = traceBuilder?.beginStep(
        stage: 'deterministic',
        targetMode: 'scene',
        label: '确定性补齐/scene',
      );
      final scene = _buildDeterministicSceneJson(sourcePack, characterName);
      toAppend.add(scene);
      detStep?.complete(parsedOk: true, parsedJson: scene);
    }
    if (toAppend.isNotEmpty) {
      plans = [...plans, for (final json in toAppend) ...UiDesignPlan.listFromJson(json)];
      onLog?.call('  已补齐 ${toAppend.length} 个缺失生命周期，共 ${plans.length} 份 UI。');
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

  /// 证据支持时，可用确定性骨架兜底。
  static bool _canBuildDeterministicFallback(UiSourcePack sourcePack) =>
      _canBuildOpeningDeterministically(sourcePack) ||
      _canBuildSceneFallback(sourcePack);

  /// 确定性兜底：根据稳定 schema 生成 opening / scene 骨架。
  static AiUiInterpretation _deterministicInterpretation({
    required UiSourcePack sourcePack,
    required String characterName,
    UiTranslateTraceBuilder? traceBuilder,
  }) {
    final detailJsons = <Map<String, dynamic>>[];
    final transcripts = <ChatMessage>[];

    if (_canBuildOpeningDeterministically(sourcePack)) {
      final detStep = traceBuilder?.beginStep(
        stage: 'deterministic',
        targetMode: 'opening',
        label: '确定性生成/opening',
      );
      final opening = _buildDeterministicOpeningJson(sourcePack, characterName);
      detailJsons.add(opening);
      transcripts.addAll(_syntheticTranscript(
        'opening',
        '确定性生成：opening 由分支摘要 + 玩家资料输入机会确定生成，未请求模型。',
        opening,
      ));
      detStep?.complete(parsedOk: true, parsedJson: opening);
    }

    if (_canBuildSceneFallback(sourcePack)) {
      final detStep = traceBuilder?.beginStep(
        stage: 'deterministic',
        targetMode: 'scene',
        label: '确定性生成/scene',
      );
      final scene = _buildDeterministicSceneJson(sourcePack, characterName);
      detailJsons.add(scene);
      transcripts.addAll(_syntheticTranscript(
        'scene',
        '确定性生成：scene 由稳定 schema 证据生成：message_flow + 状态/任务/羁绊 overlay，未请求模型。',
        scene,
      ));
      detStep?.complete(parsedOk: true, parsedJson: scene);
    }

    if (detailJsons.isEmpty) {
      final plan = UiDesignPlan(
        hasUi: false,
        confidence: 0.4,
        uiMode: 'extra_companion',
        uiName: '无 UI',
        evidenceSummary: '未识别到可确定性转译的 opening/scene UI schema。',
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
          borderRadius: 14,
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
        notes: const ['未识别到可确定性转译的 UI schema。'],
      );
      return AiUiInterpretation(
        plans: [plan],
        validationWarnings: const [],
        sourcePack: sourcePack,
        conversationContext: const [],
      );
    }

    final plans = <UiDesignPlan>[];
    for (final json in detailJsons) {
      plans.addAll(UiDesignPlan.listFromJson(json));
    }
    return AiUiInterpretation(
      plans: plans,
      validationWarnings: const [],
      sourcePack: sourcePack,
      conversationContext: transcripts,
    );
  }

  static bool _canBuildOpeningDeterministically(UiSourcePack sourcePack) =>
      sourcePack.alternateGreetings.isNotEmpty || sourcePack.suggestsProfilePool;

  /// 判断一个 DQ 选项是否属于「开场选择」。
  ///
  /// 黑曜石 first_mes 的选项是「选择开场1：新人入狱」这类——它们是
  /// opening 生命周期的分支选择，不应混进 scene 的剧情动作里。
  static bool _isOpeningChoice(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t.contains('选择开场') ||
        t.contains('开场1') ||
        t.contains('开场2') ||
        t.contains('开场3') ||
        t.contains('开场4') ||
        t.contains('开场5') ||
        t.contains('开局') ||
        t.startsWith('[0') ||
        t.startsWith('[1') ||
        t.startsWith('[2') ||
        t.startsWith('[3') ||
        t.startsWith('[4') ||
        t.startsWith('[5');
  }

  static bool _canBuildSceneFallback(UiSourcePack sourcePack) =>
      sourcePack.hasNarrativeUiWrapper ||
      sourcePack.hasQuestSchema ||
      sourcePack.hasChoiceBoxSchema ||
      sourcePack.hasFriendsAlbumSchema ||
      sourcePack.hasPlayerStatusSchema;

  static List<ChatMessage> _syntheticTranscript(
    String targetMode,
    String reason,
    Map<String, dynamic> json,
  ) =>
      [
        ChatMessage(
          role: 'system',
          content: '确定性 UI 生成/$targetMode：$reason',
        ),
        ChatMessage(role: 'assistant', content: jsonEncode(json)),
      ];

  static Map<String, dynamic> _baseVisualStyle(String styleName) => {
        'styleName': styleName,
        'pcbColor': '#2C1A0E',
        'panelColor': '#F7E9D7',
        'titleColor': '#4A3408',
        'labelColor': '#6D4C30',
        'valueColor': '#4A3C2C',
        'accentColor': '#8B7355',
        'buttonBgColor': '#E0C8A0',
        'barFillColor': '#DAA520',
        'barTrackColor': '#4F3A1B',
        'borderRadius': 12,
        'glow': false,
      };

  static Map<String, dynamic> _buildDeterministicOpeningJson(
    UiSourcePack sourcePack,
    String characterName,
  ) {
    final page = '冒险者登记';
    final inputs = <Map<String, dynamic>>[];
    void addInput(String name, String key) {
      inputs.add({
        'name': name,
        'sourceKey': key,
        'placeholder': '留空则按原卡规则随机生成',
        'initialValue': '',
        'sendOnSubmit': false,
        'targetKind': 'status_field',
        'page': page,
        'sourceRef': 'description: 角色生成/未指定则随机生成',
      });
    }

    if (sourcePack.suggestsProfilePool) {
      addInput('姓名', 'UserProfile_Name');
      addInput('年龄', 'UserProfile_Age');
      addInput('服装', 'UserProfile_Outfit');
      addInput('外貌', 'UserProfile_Appearance');
      addInput('性格', 'UserProfile_Personality');
    }

    final branchCount = 1 + sourcePack.alternateGreetings.length;
    final actions = <Map<String, dynamic>>[
      for (var branch = 0; branch < branchCount; branch++)
        {
          'label': _branchLabel(sourcePack, branch),
          'sendText': '',
          'keyAction': false,
          'branchIndex': branch,
          'page': page,
          'sourceRef': branch == 0
              ? 'data.first_mes branchIndex 0'
              : 'data.alternate_greetings[${branch - 1}] branchIndex $branch',
        },
    ];

    return {
      'hasUi': true,
      'confidence': 0.82,
      'uiMode': 'opening',
      'uiName': '$characterName·开场登记',
      'evidenceSummary': '检测到开场分支与玩家资料随机生成规则，确定性生成 opening：资料输入 + branchIndex 分支选择。',
      'sourceRefs': [
        'data.first_mes',
        if (sourcePack.alternateGreetings.isNotEmpty) 'data.alternate_greetings',
        'description: 角色生成规则',
      ],
      'visualStyle': _baseVisualStyle('羊皮纸登记卡'),
      'layout': {
        'kind': 'opening_choices',
        'navigation': 'none',
        'columns': 1,
        'pages': [
          {'title': page, 'role': 'form', 'type': 'base', 'columns': 1, 'density': 'normal', 'fill': true},
        ],
      },
      'fields': <Map<String, dynamic>>[],
      'inputs': inputs,
      'actions': actions,
      'unsupported': <Map<String, dynamic>>[],
      'notes': [
        'opening 由程序根据稳定证据生成，避免为开场登记单独请求长 JSON。',
        '分支内部 DQ/quest 选择不提升为 opening。',
      ],
    };
  }

  static String _branchLabel(UiSourcePack sourcePack, int branchIndex) {
    final text = sourcePack.branchText(branchIndex)
        .replaceAll('{{user}}', '')
        .replaceAll('{{char}}', '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return branchIndex == 0 ? '默认开场' : '开场分支 $branchIndex';
    final end = text.length > 18 ? 18 : text.length;
    return text.substring(0, end);
  }

  static Map<String, dynamic> _buildDeterministicSceneJson(
    UiSourcePack sourcePack,
    String characterName,
  ) {
    const storyPage = '公会大厅';
    const statsPage = '冒险者档案';
    const taskPage = '任务板';
    const friendsPage = '羁绊名录';
    final fields = <Map<String, dynamic>>[];
    final status = sourcePack.playerStatusForBranchIndex(0);

    void addTextField(String name, String key, String group, String value, String page) {
      fields.add({
        'name': name,
        'sourceKey': key,
        'group': group,
        'type': 'text',
        'display': 'text',
        'textAlign': 'left',
        'overflow': 'wrap',
        'initialValue': value,
        'owner': 'player',
        'page': page,
        'sourceRef': 'data.first_mes PlayerStatus:$key',
      });
    }

    void addNumberField(String name, String key, String group, String value, String display) {
      final parts = value.split('/');
      final current = parts.isNotEmpty ? parts.first : value;
      final max = parts.length > 1 ? double.tryParse(parts[1]) : null;
      fields.add({
        'name': name,
        'sourceKey': key,
        'group': group,
        'type': 'number',
        'display': display,
        'textAlign': 'center',
        'overflow': 'ellipsis',
        'initialValue': current,
        'min': 0,
        'max': ?max,
        'owner': 'player',
        'page': statsPage,
        'sourceRef': 'data.first_mes PlayerStatus:$key',
      });
    }

    if (status.isNotEmpty) {
      addTextField('姓名', 'Name', '身份', status['Name'] ?? '{{user}}', statsPage);
      addNumberField('等级', 'Level', '身份', status['Level'] ?? '1', 'badge');
      addTextField('职业', 'Class', '身份', status['Class'] ?? '冒险者', statsPage);
      addNumberField('生命值 (HP)', 'HP', '核心状态', status['HP'] ?? '100/100', 'progress');
      addNumberField('法力值 (MP)', 'MP', '核心状态', status['MP'] ?? '100/100', 'progress');
      addNumberField('经验值 (XP)', 'XP', '核心状态', status['XP'] ?? '0/100', 'progress');
      for (final key in const ['STR', 'AGI', 'INT', 'CON', 'PER', 'CHA']) {
        final names = {
          'STR': '力量 (STR)',
          'AGI': '敏捷 (AGI)',
          'INT': '智力 (INT)',
          'CON': '体质 (CON)',
          'PER': '感知 (PER)',
          'CHA': '魅力 (CHA)',
        };
        addNumberField(names[key]!, key, '核心属性', status[key] ?? '0', 'badge');
      }
      addTextField('状态效果', 'Status', '装备与状态', status['Status'] ?? '无', statsPage);
      addTextField('当前武器', 'Weapon', '装备与状态', status['Weapon'] ?? '—', statsPage);
      addTextField('当前护甲', 'Armor', '装备与状态', status['Armor'] ?? '—', statsPage);
    }

    // XML 标签状态栏：黑曜石法外特区等卡用 <生命>84</生命> 表达状态。
    // 状态值可能在 first_mes 也可能在 alternate_greetings 分支里，
    // 因此从所有分支聚合提取，首个非空值优先。
    if (status.isEmpty && sourcePack.hasXmlStatusTags) {
      const xmlLabel = {
        '生命': '生命值', '精神': '精神值', '体力': '体力值', '饱腹': '饱腹值',
        '势力': '势力', '关系': '关系', '声望': '声望', '点数': '点数',
        '物品': '物品', '位置': '位置', '称号': '称号', '编号': '编号', '罪名': '罪名',
        'HP': '生命值 (HP)', 'MP': '法力值 (MP)', 'XP': '经验值 (XP)',
      };
      const numericTags = {'生命', '精神', '体力', '饱腹', '声望', '点数', 'HP', 'MP', 'XP'};
      // 聚合所有分支的 XML 标签值。
      final aggregated = <String, String>{};
      final branchCount = 1 + sourcePack.alternateGreetings.length;
      for (var branch = 0; branch < branchCount; branch++) {
        final vals = sourcePack.tagValuesForBranchIndex(branch);
        for (final tag in xmlLabel.keys) {
          final v = vals[tag];
          if (v == null || v.isEmpty) continue;
          aggregated.putIfAbsent(tag, () => v);
        }
      }
      for (final tag in aggregated.keys) {
        final label = xmlLabel[tag]!;
        final value = aggregated[tag] ?? '';
        if (numericTags.contains(tag)) {
          addNumberField(label, tag, '状态', value.isEmpty ? '0' : value, 'progress');
        } else {
          addTextField(label, tag, '状态', value.isEmpty ? '—' : value, statsPage);
        }
      }
    }

    if (sourcePack.hasQuestSchema) {
      fields.add({
        'name': '任务板',
        'sourceKey': 'TaskBoard',
        'group': '任务板',
        'type': 'text',
        'display': 'text',
        'textAlign': 'left',
        'overflow': 'scroll',
        'initialValue': '__AUTO_QUEST_BOARD__',
        'owner': 'neutral',
        'span': 2,
        'page': taskPage,
        'sourceRef': 'data.first_mes task information / quest schema',
      });
    }
    if (sourcePack.hasFriendsAlbumSchema) {
      fields.add({
        'name': '羁绊名录',
        'sourceKey': 'FriendsAlbum',
        'group': '社交',
        'type': 'text',
        'display': 'text',
        'textAlign': 'left',
        'overflow': 'scroll',
        'initialValue': '__AUTO_FRIENDS_ALBUM_EMPTY__',
        'owner': 'neutral',
        'span': 2,
        'page': friendsPage,
        'sourceRef': 'data.character_book FriendsAlbumPage / regex FriendsAlbumPage',
      });
    }

    // scene 的 actions 只放「分支内部的剧情选择」，不放「开场选择」。
    // 黑曜石 first_mes 的 DQ 选项是「选择开场1：新人入狱」——那属于
    // opening 生命周期，不该出现在 scene 里。
    final branch0Choices = sourcePack.choiceTextsForBranchIndex(0);
    final actions = <Map<String, dynamic>>[
      for (final choice in branch0Choices)
        if (!_isOpeningChoice(choice))
          {
            'label': choice,
            'sendText': choice,
            'keyAction': false,
            'page': storyPage,
            'sourceRef': 'data.first_mes DQ_ChoiceBox',
          },
    ];

    return {
      'hasUi': true,
      'confidence': 0.76,
      'uiMode': 'scene',
      'uiName': '$characterName·冒险终端',
      'evidenceSummary': '检测到叙事包装、PlayerStatus、quest、DQ_ChoiceBox、FriendsAlbumPage 等稳定 UI schema，确定性生成 scene 骨架。',
      'sourceRefs': ['data.first_mes', 'data.extensions.regex_scripts', 'data.character_book'],
      'visualStyle': _baseVisualStyle('羊皮纸冒险终端'),
      'layout': {
        'kind': 'scene_dashboard',
        'navigation': 'tabs_and_swipe',
        'columns': 1,
        'pages': [
          {'title': storyPage, 'role': 'story', 'type': 'base', 'columns': 1, 'density': 'normal', 'fill': true},
          if (fields.any((field) => field['page'] == statsPage))
            {'title': statsPage, 'role': 'stats', 'type': 'overlay', 'parentPage': storyPage, 'columns': 2, 'density': 'compact'},
          if (sourcePack.hasQuestSchema)
            {'title': taskPage, 'role': 'tasks', 'type': 'overlay', 'parentPage': storyPage, 'columns': 1, 'density': 'normal', 'fill': true},
          if (sourcePack.hasFriendsAlbumSchema)
            {'title': friendsPage, 'role': 'social', 'type': 'overlay', 'parentPage': storyPage, 'columns': 1, 'density': 'normal', 'fill': true},
        ],
      },
      'fields': fields,
      'inputs': [
        {
          'name': '自由行动',
          'placeholder': '在此输入你的决定...',
          'initialValue': '',
          'sendOnSubmit': true,
          'targetKind': 'none',
          'page': storyPage,
          'sourceRef': 'data.first_mes DQ_ChoiceBox input_prompt',
        },
      ],
      'actions': actions,
      'unsupported': [
        if (sourcePack.alternateGreetings.isNotEmpty)
          {
            'kind': 'branch_dynamic_actions',
            'reason': '当前编译器尚不支持 scene 动作按钮按开场分支切换；branch 1 的 DQ 选项需由 LLM 后续消息/自由输入承载。',
            'sourceRef': 'data.alternate_greetings DQ_ChoiceBox',
          },
      ],
      'notes': [
        'scene 骨架由程序兜底生成，避免长 prompt 空返回；任务板和羁绊名录使用 AUTO 占位由 Dart 填充。',
      ],
    };
  }

  /// 单轮全量注入的 prompt：完整知识库 + 完整证据包。
  static List<ChatMessage> _buildMessages({
    required UiSourcePack sourcePack,
    required String knowledge,
    required String characterName,
  }) {
    return [
      const ChatMessage(
        role: 'system',
        content: '''
你是 SillyTavern 角色卡 UI 转译架构师。你的任务是阅读原卡证据，将其 UI / 状态栏 / 点击选项 / 插件界面，
智能地转译为 LLM Project UIEngine 的高层 UiDesignPlan。

【核心使命：拒绝平庸，追求定制化】
你生成的 UI 不应千篇一律。请根据角色的「姓名、背景、性格、身份」深度定制视觉风格与布局：
1. **视觉风格定制**：不要只用默认深色。如果是魔法少女，可以用粉色/发光风格；如果是克苏鲁，可以用墨绿/粘稠风格；如果是赛博朋克，可以用霓虹/冷色。
2. **布局智能决策**：不要死板套用「属性/档案/选项」三页。根据证据判断：如果任务多，任务页应该是 base 页；如果属性简单，可以合并进主页。
3. **多生命周期**：必须区分 opening（开场）与 scene（常驻）。如果原卡有开场按钮，必须有 opening；如果原卡有状态栏，必须有 scene。

硬性规则：
1. 只输出一个 JSON 对象（含 assemblies 时顶层是一个对象），不要 markdown，不要解释。
2. 不要输出内部 assembly JSON。
3. 原卡没有明确 UI 证据时，必须返回 hasUi=false。
4. 每个字段/动作都应有 sourceRef。没有证据不要生成。
5. 忠实迁移原 UI 语义，并根据移动端适配做合理增强。你可以基于角色主题「脑补」符合美学的配色方案，但不要脑补不存在的数据字段。
6. 使用提供的 columns/density/fill/span 布局意图字段控制空间分配，消灭稀疏的「一字段一行」布局。

【重要】你是推理模型，但本任务不需要任何思考过程。
直接根据证据输出最终 JSON，不要输出 reasoning_content / 思考链 / 分析过程。
你的 entire 输出必须是合法 UiDesignPlan JSON，仅此而已。
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
