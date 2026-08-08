/// 给 AI UI 理解阶段的“证据包”。
///
/// 它不是规则 UI 生成器：只负责把整张 SillyTavern 卡里可能与 UI 有关的
/// 片段按路径整理出来，供 AI 判断“原卡到底有没有 UI、应该怎么迁移”。
class UiSourcePack {
  final String cardName;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final List<String> alternateGreetings;
  final String mesExample;
  final String systemPrompt;
  final List<UiRegexEvidence> regexScripts;
  final List<UiPluginEvidence> pluginScripts;
  final List<WorldBookEvidence> worldBookEvidence;
  final List<UiSnippetEvidence> htmlSnippets;
  final List<UiActionEvidence> actionSnippets;

  const UiSourcePack({
    required this.cardName,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMes,
    required this.alternateGreetings,
    required this.mesExample,
    required this.systemPrompt,
    required this.regexScripts,
    required this.pluginScripts,
    required this.worldBookEvidence,
    required this.htmlSnippets,
    required this.actionSnippets,
  });

  bool get hasEvidence =>
      regexScripts.isNotEmpty ||
      pluginScripts.isNotEmpty ||
      htmlSnippets.isNotEmpty ||
      actionSnippets.isNotEmpty ||
      worldBookEvidence.isNotEmpty;

  bool get hasQuestSchema => _hasSchemaToken('quest:') ||
      worldBookEvidence.any((e) => e.content.contains('{quest:'));

  bool get hasChoiceBoxSchema => _hasSchemaToken('DQ_ChoiceBox') ||
      worldBookEvidence.any((e) => e.content.contains('DQ_ChoiceBox'));

  bool get hasFriendsAlbumSchema => _hasSchemaToken('FriendsAlbumPage') ||
      worldBookEvidence.any((e) => e.content.contains('FriendsAlbumPage'));

  bool get hasPlayerStatusSchema => _hasSchemaToken('PlayerStatus') ||
      worldBookEvidence.any((e) => e.content.contains('PlayerStatus')) ||
      // XML 标签格式状态栏：<生命>x</生命> <精神> <体力> <饱腹> 等
      hasXmlStatusTags;

  /// 是否含 XML 标签格式的状态栏（如 `<生命>84</生命>`）。
  ///
  /// SillyTavern 卡除了 `{PlayerStatus|...}`，还常用自定义 XML 标签
  /// 表达状态（黑曜石法外特区：`<生命>` `<精神>` `<体力>` `<饱腹>`
  /// `<势力>` `<关系>` `<声望>` `<点数>` `<物品>` `<位置>`）。
  /// 这类标签从 regex findRegex 或 first_mes 里可识别。
  /// 已知的 XML 标签格式状态字段名（黑曜石等卡用 `<生命>x</生命>` 表达状态）。
  static const Set<String> knownXmlStatusTags = {
    '生命', '精神', '体力', '饱腹', '势力', '声望', '点数',
    '物品', '位置', '称号', '编号', '罪名', '关系', 'HP', 'MP', 'XP',
  };

  /// 直接扫描所有开场分支文本里出现的已知 XML 状态标签，不依赖 regex findRegex。
  ///
  /// [hasXmlStatusTags] 只查 first_mes；这里全分支扫描，供密度评估更鲁棒地
  /// 统计"即使标签没进 regex 也能识别"。
  Set<String> xmlStatusTagsInBranches() {
    final out = <String>{};
    final total = 1 + alternateGreetings.length;
    for (var branch = 0; branch < total; branch++) {
      final text = branchText(branch);
      for (final name in knownXmlStatusTags) {
        if (text.contains('<$name>')) out.add(name);
      }
    }
    // 从 regex findRegex 的稳定标签里也收集（覆盖未出现在开场白但出现在
    // 运行时消息里的情况）。
    for (final tag in stableTagNames) {
      if (knownXmlStatusTags.contains(tag)) out.add(tag);
    }
    return out;
  }

  /// 直接扫描所有开场分支文本，是否出现正文被 UI 包裹的标记（`<正文>`/`<Alliance>`）。
  bool get _branchHasNarrativeWrapper {
    final total = 1 + alternateGreetings.length;
    final pattern = RegExp(
      r'<\s*(?:正文|alliance|outputtext|story)[^>]*>',
      caseSensitive: false,
    );
    for (var branch = 0; branch < total; branch++) {
      if (pattern.hasMatch(branchText(branch))) return true;
    }
    return false;
  }

  bool get hasXmlStatusTags {
    for (final tag in stableTagNames) {
      if (knownXmlStatusTags.contains(tag)) return true;
    }
    // 直接查 first_mes 里的 <生命> 等标签。
    for (final name in knownXmlStatusTags) {
      if (branchText(0).contains('<$name>')) return true;
    }
    return false;
  }

  bool get suggestsProfilePool => _sourceSuggestsProfilePool;

  List<QuestSummary> get questSummaries {
    final out = <QuestSummary>[];
    void collect(String text, String path) {
      out.addAll(_questSummariesOf(text, path));
    }

    collect(firstMes, 'data.first_mes');
    for (var i = 0; i < alternateGreetings.length; i++) {
      collect(alternateGreetings[i], 'data.alternate_greetings[$i]');
    }
    for (final e in worldBookEvidence) {
      collect(e.content, e.path);
    }
    final seen = <String>{};
    return out
        .where((q) => !q.isTemplatePlaceholder)
        .where((q) => seen.add('${q.name}|${q.description}'))
        .toList();
  }

  String branchText(int branchIndex) {
    if (branchIndex == 0) return firstMes;
    final altIndex = branchIndex - 1;
    if (altIndex >= 0 && altIndex < alternateGreetings.length) {
      return alternateGreetings[altIndex];
    }
    return '';
  }

  bool branchHasPlayerStatus(int branchIndex) {
    final text = branchText(branchIndex);
    return text.contains('{PlayerStatus|') ||
        RegExp(r'<\s*status\s+bar\s*>', caseSensitive: false).hasMatch(text);
  }

  List<QuestSummary> questSummariesForBranchIndex(int branchIndex) {
    final path = branchIndex == 0
        ? 'data.first_mes'
        : 'data.alternate_greetings[${branchIndex - 1}]';
    final seen = <String>{};
    return _questSummariesOf(branchText(branchIndex), path)
        .where((q) => !q.isTemplatePlaceholder)
        .where((q) => seen.add('${q.name}|${q.description}'))
        .toList();
  }

  List<String> choiceTextsForBranchIndex(int branchIndex) {
    final text = branchText(branchIndex);
    final choices = _choiceTextsOf(text);
    if (choices.isNotEmpty) return choices;
    return _optionTagChoicesOf(text);
  }

  Map<String, String> playerStatusForBranchIndex(int branchIndex) =>
      _playerStatusOf(branchText(branchIndex));

  List<String> get stableTagNames {
    final out = <String>[];
    final seen = <String>{};
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || v.length > 16) return;
      if (seen.add(v)) out.add(v);
    }

    final tagPattern = RegExp(r'<\/?\s*([\w\u4e00-\u9fff]+)');
    for (final script in regexScripts.where((e) => e.enabled)) {
      for (final match in tagPattern.allMatches(script.findRegex)) {
        add(match.group(1) ?? '');
      }
    }
    return out;
  }

  bool get hasGenericTagSchema => stableTagNames.any((tag) =>
      !const {'正文', 'Alliance', 'OutputText', 'status', 'statusbar'}
          .contains(tag));

  Map<String, String> tagValuesForBranchIndex(int branchIndex) {
    final text = branchText(branchIndex);
    if (text.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final tag in stableTagNames) {
      final escaped = RegExp.escape(tag);
      // 相邻字符串字面量拼接：raw 段保留 \s 正则语义，插值段嵌入 tag。
      final pattern = r'<\s*' '$escaped' r'\s*>([\s\S]*?)<\/\s*' '$escaped' r'\s*>';
      final match = RegExp(
        pattern,
        caseSensitive: false,
      ).firstMatch(text);
      final value = match?.group(1)?.trim() ?? '';
      if (value.isNotEmpty) out[tag] = value;
    }
    return out;
  }

  bool get hasNarrativeUiWrapper {
    bool scriptWrapsNarrative(UiRegexEvidence e) {
      final find = e.findRegex;
      final replace = e.replaceString;
      final lower = '${e.scriptName}\n$find\n$replace'.toLowerCase();
      final wrapsKnownTag = RegExp(
        r'<\s*(alliance|outputtext|正文|main|story|content|message)[^>]*>',
        caseSensitive: false,
      ).hasMatch(find);
      final hasContentSlot = lower.contains('content goes here') ||
          lower.contains('正文内容') ||
          lower.contains('main content area') ||
          lower.contains('scrollable content area') ||
          lower.contains('公会阅读界面') ||
          lower.contains('阅读界面');
      return wrapsKnownTag || hasContentSlot;
    }

    return regexScripts.any(scriptWrapsNarrative);
  }

  bool get hasOpeningBranchActions => actionSnippets.any((a) =>
      a.path.startsWith('data.alternate_greetings') ||
      a.path.startsWith('data.first_mes'));

  /// 是否存在"开场方向选择"需求。
  ///
  /// 多开场白（alternate_greetings 非空）本身就构成 opening 需求——玩家需要
  /// 在多个开场方向中做选择，即使原卡没有 onclick/send 按钮。因此信号
  /// = alternateGreetings 存在 || 有 first_mes/alts 内的 send() 动作。
  bool get needsOpeningBranchChoice =>
      alternateGreetings.isNotEmpty || hasOpeningBranchActions;

  /// 评估原卡的 UI 信息密度，供 AI 决策 mode 与证据包注入。
  ///
  /// 高密度卡（大量持久状态字段 + 正文被 UI 包裹 + 多套稳定 schema +
  /// 复杂多区 regex）适合全屏 scene；低密度"专项单一"卡（一两个字段、
  /// 单一面板）应落在 extra_companion/extra_sticky，而不是过度设计成 scene。
  UiDensityAssessment densityAssessment() {
    final reasons = <String>[];
    var score = 0;

    // 1) 检测到的持久状态字段数（优先直接扫描开场分支，兼顾 regex 提取）。
    final statusCount =
        xmlStatusTagsInBranches().isNotEmpty
            ? xmlStatusTagsInBranches().length
            : _detectedStatusFields().length;
    if (statusCount >= 8) {
      score += 3;
      reasons.add('$statusCount 个持久状态字段');
    } else if (statusCount >= 5) {
      score += 2;
      reasons.add('$statusCount 个持久状态字段');
    } else if (statusCount >= 3) {
      score += 1;
      reasons.add('$statusCount 个持久状态字段');
    }

    // 2) 正文被 UI 包裹（<正文>/<Alliance>/scrollable content，regex 或分支文本）。
    final hasNarrative = hasNarrativeUiWrapper || _branchHasNarrativeWrapper;
    if (hasNarrative) {
      score += 2;
      reasons.add('正文被 UI 包裹');
    }

    // 3) 稳定 schema 数量（quest / DQ_ChoiceBox / FriendsAlbumPage）。
    var schemaCount = 0;
    if (hasQuestSchema) schemaCount++;
    if (hasChoiceBoxSchema) schemaCount++;
    if (hasFriendsAlbumSchema) schemaCount++;
    if (schemaCount >= 2) {
      score += 2;
      reasons.add('$schemaCount 套稳定 UI schema');
    }

    // 4) 复杂 regex 脚本（大 replaceString / findRegex）条数。
    final complexRegex = regexScripts
        .where((e) => e.enabled && (e.replaceString.runes.length > 1500 || e.findRegex.runes.length > 600))
        .length;
    if (complexRegex >= 2) {
      score += 2;
      reasons.add('$complexRegex 个复杂多区 regex');
    } else if (complexRegex == 1) {
      score += 1;
      reasons.add('1 个复杂多区 regex');
    }

    // 5) 组合信号：大量持久状态字段 + 正文被 UI 包裹本身即构成全屏沉浸场景
    //    的强证据（无 regex 的 XML 状态栏卡也能识别），补足到 high。
    if (statusCount >= 5 && hasNarrative && score < 6) {
      score += 2;
      reasons.add('状态字段密集 + 正文被 UI 包裹');
    }

    final level = score >= 6
        ? UiDensity.high
        : (score >= 3 ? UiDensity.medium : UiDensity.low);
    return UiDensityAssessment(level: level, reasons: reasons);
  }

  /// 汇总给 AI 的「该输出几套 UI」建议。返回 '' 表示无强信号。
  ///
  /// 帮助 AI 决定 assemblies 的数量与 mode，避免「只有状态栏却硬造 opening」
  /// 或「只有开场按钮却硬造 scene」这类多造/遗漏。
  String modeSuggestion() {
    final hasOpening = needsOpeningBranchChoice;
    final hasPersistent = hasPlayerStatusSchema ||
        hasXmlStatusTags ||
        hasNarrativeUiWrapper;
    final density = densityAssessment();
    final immersive = density.level == UiDensity.high ||
        hasNarrativeUiWrapper ||
        _branchHasNarrativeWrapper;

    if (hasOpening && hasPersistent) {
      if (immersive) {
        return '建议 assemblies=[opening, scene]（高信息密度/正文被 UI 包裹，适合全屏沉浸终端）。';
      }
      return '建议 assemblies=[opening, extra_companion]（专项信息密度不高，伴生栏足够承载）。';
    }
    if (hasOpening) {
      final diff = alternateGreetings.isNotEmpty
          ? '多开场白必须做分支差异化（branchIndex 映射 + branchInitialValues/branchPlans）。'
          : '';
      return '建议 assemblies=[opening]。$diff';
    }
    if (hasPersistent) {
      if (immersive) {
        return '建议 assemblies=[scene]（高信息密度/正文被 UI 包裹，全屏沉浸终端）。';
      }
      return '建议 assemblies=[extra_companion]（专项单一信息用伴生栏即可，不要过度设计成 scene；'
          '若是顶层/底部轻量工具条则用 extra_sticky）。';
    }
    return '';
  }

  bool _hasSchemaToken(String token) {
    if (firstMes.contains(token)) return true;
    if (alternateGreetings.any((e) => e.contains(token))) return true;
    if (regexScripts.any((e) => e.findRegex.contains(token) || e.replaceString.contains(token))) {
      return true;
    }
    return false;
  }

  bool get _sourceSuggestsProfilePool {
    final text = '$description\n$systemPrompt\n$firstMes\n${alternateGreetings.join('\n')}'
        .toLowerCase();
    const markers = [
      '未指定',
      '随机生成',
      '姓名',
      '年龄',
      '服装',
      '外貌',
      '性格',
      '无设定user',
      '无具体设定',
      '自定义',
      '出场方式',
      '身份',
    ];
    return markers.any(text.contains);
  }

  /// 压成适合模型阅读的文本。
  String toPromptText() {
    final b = StringBuffer();
    b.writeln('# Card Basic Fields');
    b.writeln('sourcePackVersion: ui_source_pack_v2026-08-07.7');
    b.writeln('name: $cardName');
    _writeOpeningBranchSummary(b);
    _writeBranchRuntimeDataSummary(b);
    if (_sourceSuggestsProfilePool) {
      b.writeln('\n# Player profile input opportunity');
      b.writeln('The source says player traits may be specified or randomly generated. If opening UI is generated, add multiple profile input fields bound to status_field, e.g. 姓名/年龄/性别/外貌/性格/身份职业倾向/补充设定. Leave them optional; blank means the original random-generation rule still applies.');
    }
    if (hasQuestSchema || hasChoiceBoxSchema || hasFriendsAlbumSchema) {
      b.writeln('\n# Stable UI schemas that may become persistent UI');
      if (hasQuestSchema) {
        b.writeln('- quest schema exists. If making a persistent UI, prefer a task_board scroll text field/page that LLM can update, instead of marking quest unsupported by default. Do not show raw `{quest:...}` text to the player; format it into readable task cards/sections.');
        final quests = questSummaries;
        if (quests.isNotEmpty) {
          b.writeln('  extracted initial quests:');
          for (final quest in quests.take(6)) {
            b.writeln('  - ${quest.toPromptLine()}');
          }
        }
      }
      if (hasChoiceBoxSchema) {
        b.writeln('- DQ_ChoiceBox schema exists. If options are usable choices, generate sendsMessage actions/buttons; input_prompt may become an input in scene/opening.');
      }
      if (hasFriendsAlbumSchema) {
        b.writeln('- FriendsAlbumPage schema exists. Consider a friends_album scroll text field/page that LLM can update for current team/known companions. Do not show raw `{FriendsAlbumPage|...}` text to the player.');
      }
    }
    if (hasNarrativeUiWrapper) {
      b.writeln('\n# Scene message_flow requirement');
      b.writeln('The source has a narrative/message wrapper regex (for example <Alliance>/<正文>/scrollable content). If you choose uiMode=scene, you MUST declare a base layout page with role="story"/"message"/"narrative" so Dart inserts a real message_flow component. Mentioning message_flow only in notes is not enough. Put DQ choices/free input on that same story page near the message_flow; move low-frequency status/task/friends details into overlay pages when crowded. Overlay pages must be large enough to contain their fields; use scroll fields for long task/friend text instead of designing a tiny popup. TaskBoard/FriendsAlbum text fields are compiled with status_field dataChannel, so they are LLM-updatable persistent streams, not dead static labels.');
    }
    if (description.trim().isNotEmpty) {
      b.writeln('\n## description\n${_clip(description, 5000)}');
    }
    if (personality.trim().isNotEmpty) {
      b.writeln('\n## personality\n${_clip(personality, 2000)}');
    }
    if (scenario.trim().isNotEmpty) {
      b.writeln('\n## scenario\n${_clip(scenario, 2000)}');
    }
    if (firstMes.trim().isNotEmpty) {
      b.writeln('\n## first_mes\n${_clip(firstMes, 7000)}');
    }
    if (alternateGreetings.isNotEmpty) {
      b.writeln('\n## alternate_greetings');
      for (var i = 0; i < alternateGreetings.length && i < 8; i++) {
        b.writeln('\n[$i]\n${_clip(alternateGreetings[i], 2500)}');
      }
      if (alternateGreetings.length > 8) {
        b.writeln('\n... omitted ${alternateGreetings.length - 8} alternate greetings');
      }
    }
    if (mesExample.trim().isNotEmpty) {
      b.writeln('\n## mes_example\n${_clip(mesExample, 3000)}');
    }
    if (systemPrompt.trim().isNotEmpty) {
      b.writeln('\n## system_prompt\n${_clip(systemPrompt, 1200)}');
    }

    if (regexScripts.isNotEmpty) {
      b.writeln('\n# extensions.regex_scripts');
      for (final e in regexScripts) {
        b.writeln('\n## ${e.path} ${e.scriptName} enabled=${e.enabled}');
        final hint = _layoutHintOf(e.replaceString);
        if (hint.isNotEmpty) b.writeln('layout hints: $hint');
        b.writeln('findRegex:\n${_clip(e.findRegex, 3000)}');
        b.writeln('replaceString excerpt:\n${_clip(e.replaceString, 7000)}');
      }
    }

    if (pluginScripts.isNotEmpty) {
      b.writeln('\n# extensions.tavern_helper script snippets');
      for (final e in pluginScripts) {
        b.writeln('\n## ${e.path} enabled=${e.enabled}');
        if (e.urls.isNotEmpty) b.writeln('urls: ${e.urls.join(', ')}');
        b.writeln(_clip(e.content, 4000));
      }
    }

    if (actionSnippets.isNotEmpty) {
      b.writeln('\n# onclick/send actions');
      for (final e in actionSnippets) {
        b.writeln('- ${e.path}: ${e.text}');
      }
    }

    if (htmlSnippets.isNotEmpty) {
      b.writeln('\n# Inline HTML/CSS snippets');
      for (final e in htmlSnippets) {
        b.writeln('\n## ${e.path}\n${_clip(e.text, 3000)}');
      }
    }

    if (worldBookEvidence.isNotEmpty) {
      b.writeln('\n# Suspected UI/variable world book entries');
      for (final e in worldBookEvidence) {
        b.writeln('\n## ${e.path} ${e.title}');
        b.writeln(_clip(e.content, 3000));
      }
    }

    if (!hasEvidence) {
      b.writeln('\n# UI evidence\nNo explicit UI evidence was extracted. If the original card does not contain UI, return hasUi=false.');
    }

    return b.toString();
  }

  /// 精简版证据包：大幅裁剪每个字段，供「单轮全量注入」使用。
  ///
  /// 黑曜石卡实测完整版 57k 字符（≈33k tokens），加上知识库后 prompt
  /// 高达 80k 字符，模型直接空回复。这个版本把各项 clip 上限砍到
  /// 能保留关键信息的最小值，目标整包降到 ~15k 字符。
  String toPromptTextSlim() {
    final b = StringBuffer();
    b.writeln('# Card Basic Fields');
    b.writeln('sourcePackVersion: ui_source_pack_v2026-08-07.7');
    b.writeln('name: $cardName');
    _writeOpeningBranchSummary(b);
    _writeBranchRuntimeDataSummary(b);
    final suggestion = modeSuggestion();
    if (suggestion.isNotEmpty) {
      b.writeln('\n# UI assembly count suggestion');
      b.writeln('$suggestion 不要多造：没有对应证据就不要多输出一套 UI；'
          '也不要遗漏：有证据就必须包含对应 mode。');
    }
    final density = densityAssessment();
    if (density.level != UiDensity.low || suggestion.isNotEmpty) {
      b.writeln('\n# UI density assessment');
      b.writeln('信息密度: ${density.level.name}${density.reasons.isEmpty ? '' : '（${density.reasons.join('; ')}）'}');
      b.writeln('决策判据：高密度/正文被 UI 包裹 → scene 全屏沉浸；'
          '专项单一信息 → extra_companion/extra_sticky，不要过度用 scene。');
    }
    if (_sourceSuggestsProfilePool) {
      b.writeln('\n# Player profile input opportunity');
      b.writeln('Source allows player-specified traits. If opening UI generated, add profile input fields (name/age/gender/appearance/personality) bound to status_field, optional.');
    }
    if (hasQuestSchema || hasChoiceBoxSchema || hasFriendsAlbumSchema) {
      b.writeln('\n# Stable UI schemas');
      if (hasQuestSchema) {
        b.writeln('- quest schema: prefer a task_board scroll field that LLM can update; format quests into readable cards, not raw `{quest:...}`.');
        final quests = questSummaries;
        if (quests.isNotEmpty) {
          b.writeln('  initial quests:');
          for (final quest in quests.take(4)) {
            b.writeln('  - ${quest.toPromptLine()}');
          }
        }
      }
      if (hasChoiceBoxSchema) {
        b.writeln('- DQ_ChoiceBox schema: usable choices become sendsMessage actions; input_prompt may become an input in scene/opening.');
      }
      if (hasFriendsAlbumSchema) {
        b.writeln('- FriendsAlbumPage schema: consider a friends_album scroll field that LLM can update.');
      }
    }
    if (hasNarrativeUiWrapper) {
      b.writeln('\n# Scene message_flow requirement');
      b.writeln('Narrative wrapper detected. If uiMode=scene, declare a base layout page role="story"/"message"/"narrative" so Dart inserts message_flow. Put DQ choices/free input on that same page; move status/task/friends details to overlay pages.');
    }
    if (description.trim().isNotEmpty) {
      b.writeln('\n## description\n${_clip(description, 1500)}');
    }
    if (personality.trim().isNotEmpty) {
      b.writeln('\n## personality\n${_clip(personality, 800)}');
    }
    if (scenario.trim().isNotEmpty) {
      b.writeln('\n## scenario\n${_clip(scenario, 800)}');
    }
    if (firstMes.trim().isNotEmpty) {
      b.writeln('\n## first_mes\n${_clip(firstMes, 2000)}');
    }
    if (alternateGreetings.isNotEmpty) {
      b.writeln('\n## alternate_greetings');
      for (var i = 0; i < alternateGreetings.length && i < 6; i++) {
        b.writeln('\n[$i]\n${_clip(alternateGreetings[i], 600)}');
      }
      if (alternateGreetings.length > 6) {
        b.writeln('\n... omitted ${alternateGreetings.length - 6} branches');
      }
    }
    if (mesExample.trim().isNotEmpty) {
      b.writeln('\n## mes_example\n${_clip(mesExample, 1200)}');
    }
    if (systemPrompt.trim().isNotEmpty) {
      b.writeln('\n## system_prompt\n${_clip(systemPrompt, 800)}');
    }

    if (regexScripts.isNotEmpty) {
      b.writeln('\n# extensions.regex_scripts');
      for (final e in regexScripts) {
        b.writeln('\n## ${e.path} ${e.scriptName} enabled=${e.enabled}');
        final hint = _layoutHintOf(e.replaceString);
        if (hint.isNotEmpty) b.writeln('layout hints: $hint');
        b.writeln('findRegex:\n${_clip(e.findRegex, 600)}');
        b.writeln('replaceString excerpt:\n${_clip(_sanitizeVisualCss(e.replaceString), 1500)}');
      }
      _writeOmittedNote(b, 'regex_scripts', regexScripts.length, 18);
    }

    // ── 视觉语义提示（给 AI 参考，不强制）──
    // 原卡 regex 脚本里的 HTML 注释（sections=...）和 findRegex 的 XML 标签
    // 描述了原 UI 的视觉结构与布局意图。把这些线索显式汇总，让 AI
    // 自行研究并决定如何在 opening/scene 里还原，而不是当作动态脚本丢弃。
    final visualHints = _visualSemantics();
    if (visualHints.isNotEmpty) {
      b.writeln('\n# Visual semantics hints (study and decide how to reproduce)');
      b.writeln('These are the original card\'s UI visual cues extracted from regex scripts. '
          'Reproduce them where faithful, using visualStyle / layout / components. '
          'You decide how; this is reference material, not a hard requirement:');
      for (final line in visualHints) {
        b.writeln('- $line');
      }
      b.writeln('Map these CSS cues to visualStyle fields when confident: '
          'gradientTo / surfaceMaterial / strokeColor / glowColor / glowIntensity / '
          'userBubbleColor / assistantBubbleColor. Leave them empty otherwise (defaults apply).');
    }

    if (pluginScripts.isNotEmpty) {
      b.writeln('\n# extensions.tavern_helper script snippets');
      for (final e in pluginScripts) {
        b.writeln('\n## ${e.path} enabled=${e.enabled}');
        if (e.urls.isNotEmpty) b.writeln('urls: ${e.urls.join(', ')}');
        b.writeln(_clip(e.content, 1200));
      }
      _writeOmittedNote(b, 'tavern_helper scripts', pluginScripts.length, 12);
    }

    if (actionSnippets.isNotEmpty) {
      b.writeln('\n# onclick/send actions');
      for (final e in actionSnippets) {
        b.writeln('- ${e.path}: ${e.text}');
      }
      _writeOmittedNote(b, 'onclick/send actions', actionSnippets.length, 20);
    }

    if (htmlSnippets.isNotEmpty) {
      b.writeln('\n# Inline HTML/CSS snippets');
      for (final e in htmlSnippets) {
        b.writeln('\n## ${e.path}\n${_clip(_sanitizeVisualCss(e.text), 1200)}');
      }
      _writeOmittedNote(b, 'inline HTML snippets', htmlSnippets.length, 8);
    }

    if (worldBookEvidence.isNotEmpty) {
      b.writeln('\n# Suspected UI/variable world book entries');
      var shown = 0;
      for (final e in worldBookEvidence) {
        if (shown >= 6) break;
        b.writeln('\n## ${e.path} ${e.title}');
        b.writeln(_clip(e.content, 800));
        shown++;
      }
      if (worldBookEvidence.length > shown) {
        b.writeln('\n... omitted ${worldBookEvidence.length - shown} more entries');
      }
    }

    // ── 检测到的状态字段（显式列出，避免 AI 因信息藏在 HTML 里而漏判）──
    final detectedStatus = _detectedStatusFields();
    if (detectedStatus.isNotEmpty) {
      b.writeln('\n# Detected persistent status fields (migrate these to permanent Companion UI)');
      b.writeln('The card has persistent status fields with static initial values found in greetings. '
          'Extract them into a permanent extra_companion UI:');
      for (final entry in detectedStatus.entries) {
        b.writeln('- ${entry.key}: ${entry.value}');
      }
      b.writeln('Map these to an extra_companion UI with multi-column layout. '
          'Numeric values (percent or HP/MP/XP) use display=progress; text values use display=text.');
    }

    if (!hasEvidence) {
      b.writeln('\n# UI evidence\nNo explicit UI evidence extracted. Return hasUi=false.');
    }

    return b.toString();
  }

  /// 汇总各分支可提取的状态字段与初始值。
  ///
  /// 覆盖两种格式：
  /// 1. `{PlayerStatus|HP:100/100|MP:50/50}` 标准格式
  /// 2. `<生命>100%</生命>` XML 标签格式
  /// 返回 字段名 → 首个非空值，按黑曜石等卡的布局顺序排列。
  Map<String, String> _detectedStatusFields() {
    final out = <String, String>{};
    // 标准 PlayerStatus 格式
    final ps = playerStatusForBranchIndex(0);
    if (ps.isNotEmpty) {
      const order = ['Name', 'Level', 'HP', 'MP', 'XP', 'STR', 'AGI', 'INT', 'CON', 'PER', 'CHA', 'Class', 'Status', 'Weapon', 'Armor'];
      for (final k in order) {
        final v = ps[k];
        if (v != null && v.isNotEmpty) out[k] = v;
      }
    }
    // XML 标签格式（跨分支聚合）
    const xmlLabels = {
      '生命': '生命', '精神': '精神', '体力': '体力', '饱腹': '饱腹',
      '势力': '势力', '关系': '关系', '声望': '声望', '点数': '点数',
      '物品': '物品', '位置': '位置', '称号': '称号', '编号': '编号', '罪名': '罪名',
    };
    if (hasXmlStatusTags) {
      final branchCount = 1 + alternateGreetings.length;
      for (var branch = 0; branch < branchCount; branch++) {
        final vals = tagValuesForBranchIndex(branch);
        for (final tag in xmlLabels.keys) {
          final v = vals[tag];
          if (v == null || v.isEmpty) continue;
          out.putIfAbsent(tag, () => v);
        }
      }
    }
    return out;
  }

  /// 汇总原卡的视觉语义线索（供 AI 参考，不强制）。
  ///
  /// 从两个来源提取：
  /// 1. findRegex 里的 XML 标签（如 `<终端状态>` `<当前位置>` `<当前时间>`）——
  ///    它们描述了 UI 的结构分区，不只是数据字段。
  /// 2. regex replaceString 的 HTML 注释（`sections=...`）——
  ///    描述原 UI 的视觉布局（顶部状态栏、信息数据流、正文区、选项区等）。
  ///
  /// 返回逐行提示，AI 据此自行研究如何还原，而不是把带这些语义的
  /// regex 当「动态脚本」整段丢弃。
  List<String> _visualSemantics() {
    final lines = <String>[];
    final seen = <String>{};

    // 1. findRegex 的 XML 标签（结构分区语义）
    final tagPattern = RegExp(r'<([一-鿿A-Za-z]{2,8})>');
    for (final script in regexScripts.where((e) => e.enabled)) {
      for (final m in tagPattern.allMatches(script.findRegex)) {
        final tag = m.group(1)!;
        if (seen.add('tag:$tag')) {
          lines.add('xml-section tag <$tag>: a UI region in the original layout');
        }
      }
      // 2. HTML 注释的 sections 结构
      final hint = _layoutHintOf(script.replaceString);
      if (hint.isNotEmpty && seen.add('hint:$hint')) {
        lines.add('layout hint: $hint');
      }
      // 3. 视觉特征（渐变 / 描边 / 发光 / 两列网格）——直接告诉 AI
      //    原卡用了哪些视觉手法，方便映射到 visualStyle。
      final css = _sanitizeVisualCss(script.replaceString);
      if (RegExp(r'linear-gradient', caseSensitive: false).hasMatch(css) &&
          seen.add('gradient')) {
        lines.add('visual: linear-gradient surfaces (map to gradientTo / surfaceMaterial="gradient")');
      }
      if (RegExp(r'box-shadow\s*:\s*[^;]*\d+', caseSensitive: false).hasMatch(css) &&
          seen.add('glow')) {
        lines.add('visual: box-shadow glow (map to glowColor + glowIntensity>0)');
      }
      if (RegExp(r'border\s*:\s*[^;]*(solid|1px|2px)', caseSensitive: false)
              .hasMatch(css) &&
          seen.add('stroke')) {
        lines.add('visual: bordered panels (map to strokeColor / surfaceMaterial="outline")');
      }
      if (RegExp(r'width\s*:\s*48%|grid-template-columns\s*:\s*1fr\s+1fr',
              caseSensitive: false)
          .hasMatch(css) &&
          seen.add('two-col')) {
        lines.add('visual: two-column layout (map to layout columns:2)');
      }
    }

    // 4. 原卡出现的颜色候选（不强制，仅参考）。
    final colors = _colorCandidates();
    if (colors.isNotEmpty && seen.add('colors')) {
      lines.add('original palette samples: ${colors.join(' ')}');
    }
    return lines;
  }

  /// 从 replaceString 里抓出现过的 hex 颜色，作为 AI 配色参考。
  ///
  /// 只取前 N 个去重结果，避免被渐变/阴影里的大量相近色刷屏。
  List<String> _colorCandidates() {
    final seen = <String>{};
    final out = <String>[];
    void collect(String css) {
      for (final m in RegExp(r'#[0-9a-fA-F]{6}\b').allMatches(css)) {
        final v = m.group(0)!.toUpperCase();
        if (seen.add(v)) {
          out.add(v);
          if (out.length >= 8) return;
        }
      }
    }

    for (final e in regexScripts.where((e) => e.enabled)) {
      collect(e.replaceString);
      if (out.length >= 8) break;
    }
    return out;
  }

  /// 阶段 1（Scout）用的证据摘要：远小于 [toPromptText]。
  ///
  /// 只给出每个证据源的“指纹”——路径、名称、布局 hint、长度——
  /// 让 AI 判断原卡是否有 UI、大致是什么，并点名要看哪些证据的细节。
  /// 完整内容由 [detailPromptFor] 按需切片，避免一次性全量塞入。
  String summaryPrompt() {
    final b = StringBuffer();
    b.writeln('# Card Evidence Summary (index only)');
    b.writeln('name: $cardName');
    b.writeln('sourcePackVersion: ui_source_pack_v2026-08-07.7');
    _writeOpeningBranchSummary(b);
    _writeBranchRuntimeDataSummary(b);

    if (_sourceSuggestsProfilePool) {
      b.writeln('\n# Player profile input opportunity');
      b.writeln('Source allows player-specified traits. If opening UI generated, consider profile input fields (name/age/gender/appearance/personality) bound to status_field.');
    }
    if (hasQuestSchema || hasChoiceBoxSchema || hasFriendsAlbumSchema) {
      b.writeln('\n# Stable UI schemas');
      if (hasQuestSchema) {
        b.writeln('- quest schema: ${questSummaries.length} quests found. First: ${questSummaries.isEmpty ? 'none' : questSummaries.first.toPromptLine()}');
      }
      if (hasChoiceBoxSchema) b.writeln('- DQ_ChoiceBox schema present');
      if (hasFriendsAlbumSchema) b.writeln('- FriendsAlbumPage schema present');
    }
    if (hasNarrativeUiWrapper) b.writeln('\n# Narrative/message wrapper present (scene message_flow candidate)');

    b.writeln('\n# Evidence fingerprints');
    if (description.trim().isNotEmpty) {
      b.writeln('- description: ${description.runes.length} chars');
    }
    if (firstMes.trim().isNotEmpty) {
      b.writeln('- first_mes: ${firstMes.runes.length} chars');
    }
    if (alternateGreetings.isNotEmpty) {
      b.writeln('- alternate_greetings: ${alternateGreetings.length} entries');
    }
    if (systemPrompt.trim().isNotEmpty) {
      b.writeln('- system_prompt: ${systemPrompt.runes.length} chars');
    }
    for (var i = 0; i < regexScripts.length; i++) {
      final e = regexScripts[i];
      final hint = _layoutHintOf(e.replaceString);
      b.writeln('- regex[$i] ${e.scriptName} enabled=${e.enabled} find=${e.findRegex.runes.length}c replace=${e.replaceString.runes.length}c${hint.isEmpty ? '' : ' | hints: $hint'}');
    }
    for (var i = 0; i < pluginScripts.length; i++) {
      final e = pluginScripts[i];
      b.writeln('- plugin[$i] enabled=${e.enabled} ${e.content.runes.length}c${e.urls.isEmpty ? '' : ' urls=${e.urls.join(',')}'}');
    }
    for (var i = 0; i < htmlSnippets.length; i++) {
      final e = htmlSnippets[i];
      b.writeln('- html[$i] ${e.text.runes.length}c');
    }
    for (var i = 0; i < actionSnippets.length; i++) {
      final e = actionSnippets[i];
      b.writeln('- action[$i] ${e.text}');
    }
    for (var i = 0; i < worldBookEvidence.length; i++) {
      final e = worldBookEvidence[i];
      b.writeln('- worldbook[$i] ${e.title} ${e.content.runes.length}c');
    }
    if (!hasEvidence) b.writeln('\n# UI evidence\nNo explicit UI evidence. Return hasUi=false unless card text clearly describes an interface.');
    return b.toString();
  }

  /// 阶段 2（Detailer）用的按需切片。
  ///
  /// [regexIndices] / [pluginIndices] / [htmlIndices] / [worldBookIndices] 由
  /// 阶段 1 的选型指定，只把这些索引对应的完整证据拼进来，其余忽略。
  /// [includeFullBranches] 为 true 时给出完整开场白文本（选型确认需要
  /// 精确提取字段/动作时才开）。
  String detailPromptFor({
    Set<int> regexIndices = const {},
    Set<int> pluginIndices = const {},
    Set<int> htmlIndices = const {},
    Set<int> worldBookIndices = const {},
    bool includeFullBranches = false,
  }) {
    final b = StringBuffer();
    b.writeln('# Card Detail Evidence (selected slices)');

    if (includeFullBranches) {
      b.writeln('\n## first_mes\n${_clip(firstMes, 7000)}');
      if (alternateGreetings.isNotEmpty) {
        b.writeln('\n## alternate_greetings');
        for (var i = 0; i < alternateGreetings.length && i < 8; i++) {
          b.writeln('\n[$i]\n${_clip(alternateGreetings[i], 2500)}');
        }
      }
    } else {
      _writeOpeningBranchSummary(b);
      _writeBranchRuntimeDataSummary(b);
    }

    if (description.trim().isNotEmpty) {
      b.writeln('\n## description\n${_clip(description, 1600)}');
    }
    if (personality.trim().isNotEmpty) {
      b.writeln('\n## personality\n${_clip(personality, 800)}');
    }
    if (scenario.trim().isNotEmpty) {
      b.writeln('\n## scenario\n${_clip(scenario, 800)}');
    }
    if (systemPrompt.trim().isNotEmpty) {
      b.writeln('\n## system_prompt\n${_clip(systemPrompt, 1200)}');
    }

    for (final i in regexIndices) {
      if (i < 0 || i >= regexScripts.length) continue;
      final e = regexScripts[i];
      b.writeln('\n## regex[$i] ${e.path} ${e.scriptName} enabled=${e.enabled}');
      final hint = _layoutHintOf(e.replaceString);
      if (hint.isNotEmpty) b.writeln('layout hints: $hint');
      b.writeln('findRegex:\n${_clip(_sanitizePromptEvidence(e.findRegex), 1000)}');
      b.writeln('replaceString:\n${_clip(_sanitizePromptEvidence(e.replaceString), 1400)}');
    }
    for (final i in pluginIndices) {
      if (i < 0 || i >= pluginScripts.length) continue;
      final e = pluginScripts[i];
      b.writeln('\n## plugin[$i] ${e.path} enabled=${e.enabled}');
      if (e.urls.isNotEmpty) b.writeln('urls: ${e.urls.join(', ')}');
      b.writeln(_clip(_sanitizePromptEvidence(e.content), 2200));
    }
    for (final i in htmlIndices) {
      if (i < 0 || i >= htmlSnippets.length) continue;
      final e = htmlSnippets[i];
      b.writeln('\n## html[$i] ${e.path}\n${_clip(_sanitizePromptEvidence(e.text), 1000)}');
    }
    for (final i in worldBookIndices) {
      if (i < 0 || i >= worldBookEvidence.length) continue;
      final e = worldBookEvidence[i];
      b.writeln('\n## worldbook[$i] ${e.path} ${e.title}\n${_clip(_sanitizePromptEvidence(e.content), 1000)}');
    }
    if (actionSnippets.isNotEmpty) {
      b.writeln('\n# onclick/send actions');
      for (final e in actionSnippets) {
        b.writeln('- ${e.path}: ${e.text}');
      }
    }
    return b.toString();
  }

  void _writeOpeningBranchSummary(StringBuffer b) {
    b.writeln('\n# Opening greeting branches (branchIndex mapping)');
    b.writeln('IMPORTANT: opening UI, if generated, should choose among these branch directions.');
    b.writeln('Do NOT promote DQ_ChoiceBox / quest choices inside one branch into opening-level choices.');
    final all = <({int index, String label, String text})>[
      (index: 0, label: 'first_mes', text: firstMes),
      for (var i = 0; i < alternateGreetings.length; i++)
        (index: i + 1, label: 'alternate_greetings[$i]', text: alternateGreetings[i]),
    ];
    for (final item in all.take(8)) {
      final summary = _summarizeBranchText(item.text);
      b.writeln('- branchIndex ${item.index} (${item.label}): $summary');
      final choices = _choiceTextsOf(item.text);
      if (choices.isNotEmpty) {
        b.writeln('  internal DQ choices in this branch (not opening-level choices): ${choices.join(' / ')}');
      }
    }
    if (all.length > 8) b.writeln('- ... omitted ${all.length - 8} extra branches');
  }

  void _writeBranchRuntimeDataSummary(StringBuffer b) {
    if (alternateGreetings.isEmpty) return;
    b.writeln('\n# Branch-specific runtime UI data availability');
    b.writeln('Use this to avoid silently reusing branch 0 task/status data for all openings. If a persistent scene field is initialized from branch 0 but another branch lacks or differs in that schema, set fields[].branchInitialValues for that branch (for example TaskBoard branch 1 = 暂无公会任务/待剧情更新), or explain the unsupported difference.');
    final total = 1 + alternateGreetings.length;
    for (var branch = 0; branch < total && branch < 8; branch++) {
      final quests = questSummariesForBranchIndex(branch);
      final choices = choiceTextsForBranchIndex(branch);
      final statusMap = playerStatusForBranchIndex(branch);
      final status = statusMap.isEmpty
          ? 'no'
          : statusMap.entries
              .map((entry) => '${entry.key}:${entry.value}')
              .take(18)
              .join(', ');
      final questLabel = quests.isEmpty
          ? 'none'
          : quests.map((q) => q.name).take(4).join(' / ');
      final choiceLabel = choices.isEmpty ? 'none' : choices.take(5).join(' / ');
      b.writeln('- branchIndex $branch: PlayerStatus=$status; quests=$questLabel; DQ choices=$choiceLabel');
    }
  }

  static Map<String, String> _playerStatusOf(String text) {
    const marker = '{PlayerStatus|';
    final start = text.indexOf(marker);
    if (start < 0) return const <String, String>{};
    final bodyStart = start + marker.length;
    var i = bodyStart;
    var end = -1;
    while (i < text.length) {
      // PlayerStatus 里常出现 {{user}} 这类宏，不能把宏里的 `}` 当成
      // schema 结束符。跳过整段双花括号宏。
      if (i + 1 < text.length && text.codeUnitAt(i) == 0x7B && text.codeUnitAt(i + 1) == 0x7B) {
        final macroEnd = text.indexOf('}}', i + 2);
        if (macroEnd < 0) break;
        i = macroEnd + 2;
        continue;
      }
      if (text.codeUnitAt(i) == 0x7D) {
        end = i;
        break;
      }
      i++;
    }
    if (end <= bodyStart) return const <String, String>{};
    final raw = text.substring(bodyStart, end);
    final out = <String, String>{};
    for (final part in raw.split('|')) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim();
      final value = part.substring(idx + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static List<QuestSummary> _questSummariesOf(String text, String path) {
    final out = <QuestSummary>[];
    final re = RegExp(r'\{quest:([^|}]+)\|type:([^|}]*)\|desc:([^|}]*)\|diff:([^|}]*)\|client:([^|}]*)\|reward:([^|}]*)\|location:([^|}]*)\|time:([^|}]*)\|equip:([^|}]*)\|risk:([^|}]*)\|note:([^}]*)\}');
    for (final m in re.allMatches(text)) {
      out.add(QuestSummary(
        path: path,
        name: m.group(1)?.trim() ?? '',
        type: m.group(2)?.trim() ?? '',
        description: m.group(3)?.trim() ?? '',
        difficulty: m.group(4)?.trim() ?? '',
        client: m.group(5)?.trim() ?? '',
        reward: m.group(6)?.trim() ?? '',
        location: m.group(7)?.trim() ?? '',
        time: m.group(8)?.trim() ?? '',
        equipment: m.group(9)?.trim() ?? '',
        risk: m.group(10)?.trim() ?? '',
        note: m.group(11)?.trim() ?? '',
      ));
    }
    return out;
  }

  static String _layoutHintOf(String html) {
    if (html.trim().isEmpty) return '';
    int count(String pattern) =>
        RegExp(pattern, caseSensitive: false).allMatches(html).length;
    final hints = <String>[];
    final comments = RegExp(r'<!--\s*(.*?)\s*-->')
        .allMatches(html)
        .map((m) => m.group(1)!.trim())
        .where((v) => v.isNotEmpty && v.length <= 32)
        .take(8)
        .toList();
    if (comments.isNotEmpty) hints.add("sections=${comments.join(' > ')}");
    final flex = count(r'display\s*:\s*flex');
    final grid = count(r'display\s*:\s*grid');
    if (flex > 0) hints.add('flex=$flex');
    if (grid > 0) hints.add('grid=$grid');
    if (count(r'flex-wrap') > 0) hints.add('wrap-layout');
    if (count(r'justify-content\s*:\s*space-between') > 0) {
      hints.add('space-between rows');
    }
    if (count(r'overflow-y\s*:\s*auto|overflow\s*:\s*auto') > 0) {
      hints.add('scrollable content');
    }
    if (count(r'border') > 3) hints.add('bordered panels');
    if (count(r'linear-gradient') > 0) hints.add('gradient surfaces');
    if (count(r'width\s*:\s*48%') > 0) hints.add('two-column 48/48 layout');
    return hints.join('; ');
  }

  static String _summarizeBranchText(String text) {
    var t = text
        .replaceAll('{{user}}', '__USER_MACRO__')
        .replaceAll('{{char}}', '__CHAR_MACRO__')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
        .replaceAll('__USER_MACRO__', '{{user}}')
        .replaceAll('__CHAR_MACRO__', '{{char}}')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return '(empty)';
    if (t.length > 120) t = '${t.substring(0, 120)}...';
    return t;
  }

  static List<String> _optionTagChoicesOf(String text) {
    final match = RegExp(
      r'<\s*(?:选项|选项列表)\s*>([\s\S]*?)<\/\s*(?:选项|选项列表)\s*>',
      caseSensitive: false,
    ).firstMatch(text);
    final raw = match?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return const [];
    final out = <String>[];
    final sendRe = RegExp(r"""send\(\s*['"](.+?)['"]\s*\)""");
    for (final m in sendRe.allMatches(raw)) {
      final value = m.group(1)?.trim() ?? '';
      if (value.isNotEmpty) out.add(value);
      if (out.length >= 5) return out;
    }
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      var value = line
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'^\s*\d+[\.、)]\s*'), '')
          .trim();
      if (value.isEmpty) continue;
      if (value.length > 48) value = value.substring(0, 48);
      out.add(value);
      if (out.length >= 5) break;
    }
    return out;
  }

  static List<String> _choiceTextsOf(String text) {
    final out = <String>[];
    final re = RegExp(r'option\d+_text:([^|}]+)');
    for (final m in re.allMatches(text)) {
      final value = m.group(1)?.trim() ?? '';
      if (value.isNotEmpty) out.add(value);
      if (out.length >= 5) break;
    }
    return out;
  }

  static String _sanitizePromptEvidence(String raw) {
    var s = raw;
    s = _stripDataUris(s);
    // hover / inline JS 不能执行，只保留“有 hover 行为”的事实。
    s = s.replaceAll(
      RegExp('\\s+on(?:mouse|click|input|change|touch)[a-zA-Z]*\\s*=\\s*"[\\s\\S]*?"'),
      ' data-event="[omitted inline handler]"',
    );
    s = s.replaceAll(
      RegExp("\\s+on(?:mouse|click|input|change|touch)[a-zA-Z]*\\s*=\\s*'[\\s\\S]*?'"),
      ' data-event="[omitted inline handler]" ',
    );
    // CSS 动画关键帧只需记录不支持，正文不需要完整 keyframes。
    s = s.replaceAll(
      RegExp('@keyframes[\\s\\S]*?}\\s*}', caseSensitive: false),
      '@keyframes [omitted]',
    );
    // 压缩空行，避免 HTML/CSS 缩进撑大上下文。
    s = s.replaceAll(RegExp('\\n{3,}'), '\n\n');
    return s.trim();
  }

  /// 轻量净化活路径的 CSS 证据：只去掉会爆 token 的 data URI / base64，
  /// **保留颜色、边框、渐变、发光等视觉属性**，让 AI 能读到原卡外观。
  ///
  /// 与 [_sanitizePromptEvidence] 的区别：不动内联 on* 事件与 keyframes
  /// （那些是行为提示不是 token 大头），只清掉 base64 图片数据。
  static String _sanitizeVisualCss(String raw) => _stripDataUris(raw).trim();

  /// 抽掉 `data:image/...;base64,...` 与长 base64 块。
  ///
  /// 注意这里不用 Dart raw string，避免把 `\s` / `\(` 双重转义成字面反斜杠。
  static String _stripDataUris(String s) {
    s = s.replaceAll(
      RegExp("url\\((['\"]?)data:image[\\s\\S]*?\\1\\)", caseSensitive: false),
      'url([omitted data:image])',
    );
    s = s.replaceAll(
      RegExp("data:image/[^\\s'\"<>)]{80,}", caseSensitive: false),
      '[omitted data:image]',
    );
    s = s.replaceAll(
      RegExp('base64,[A-Za-z0-9+/=]{80,}', caseSensitive: false),
      'base64,[omitted]',
    );
    return s;
  }

  static String _clip(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}\n...[truncated ${t.length - max} chars]';
  }

  /// 证据包超出展示上限时，明确告诉 AI「有东西被截断但没进 prompt」。
  ///
  /// 让 AI 知道它看到的是前 [shown] 条，其余被省略——若被省略的证据里
  /// 可能有 UI，应在 notes 标注「可能遗漏」，而不是默认没看到。
  static void _writeOmittedNote(StringBuffer b, String label, int total, int shown) {
    if (total > shown) {
      b.writeln(
          '\n... $label：原卡共有 $total 条，证据包只保留前 $shown 条，'
          '已省略 ${total - shown} 条（未进入本次分析）。若省略部分可能含 UI，请在 notes 标注可能遗漏。');
    }
  }
}

class UiRegexEvidence {
  final String path;
  final String scriptName;
  final bool enabled;
  final String findRegex;
  final String replaceString;

  const UiRegexEvidence({
    required this.path,
    required this.scriptName,
    required this.enabled,
    required this.findRegex,
    required this.replaceString,
  });
}

class UiPluginEvidence {
  final String path;
  final bool enabled;
  final String content;
  final List<String> urls;

  const UiPluginEvidence({
    required this.path,
    required this.enabled,
    required this.content,
    required this.urls,
  });
}

class WorldBookEvidence {
  final String path;
  final String title;
  final String content;

  const WorldBookEvidence({
    required this.path,
    required this.title,
    required this.content,
  });
}

class UiSnippetEvidence {
  final String path;
  final String text;

  const UiSnippetEvidence({required this.path, required this.text});
}

class UiActionEvidence {
  final String path;
  final String text;

  const UiActionEvidence({required this.path, required this.text});
}

class QuestSummary {
  final String path;
  final String name;
  final String type;
  final String description;
  final String difficulty;
  final String client;
  final String reward;
  final String location;
  final String time;
  final String equipment;
  final String risk;
  final String note;

  const QuestSummary({
    required this.path,
    required this.name,
    required this.type,
    required this.description,
    required this.difficulty,
    required this.client,
    required this.reward,
    required this.location,
    required this.time,
    required this.equipment,
    required this.risk,
    required this.note,
  });

  bool get isTemplatePlaceholder {
    const placeholders = {
      '任务名称',
      '任务名',
      '任务类型',
      '任务描述',
      '难度等级',
      '委托人姓名',
      '任务报酬',
      '任务地点',
      '时间限制',
      '推荐装备',
      '潜在风险',
      '特别说明',
    };
    final values = [
      name,
      type,
      description,
      difficulty,
      client,
      reward,
      location,
      time,
      equipment,
      risk,
      note,
    ].map((v) => v.trim()).toList();
    if (placeholders.contains(name.trim())) return true;
    final placeholderHits = values.where((v) {
      if (v.isEmpty) return false;
      if (placeholders.contains(v)) return true;
      if (RegExp(r'^\{\{.*\}\}$').hasMatch(v)) return true;
      return false;
    }).length;
    return placeholderHits >= 3;
  }

  String toPromptLine() {
    final parts = <String>[
      if (type.isNotEmpty) '类型:$type',
      if (difficulty.isNotEmpty) '难度:$difficulty',
      if (client.isNotEmpty) '委托人:$client',
      if (reward.isNotEmpty) '报酬:$reward',
      if (location.isNotEmpty) '地点:$location',
      if (description.isNotEmpty) '描述:$description',
      if (risk.isNotEmpty) '风险:$risk',
      if (note.isNotEmpty) '说明:$note',
    ];
    return "$name (${parts.join('；')}) [$path]";
  }
}

/// UI 信息密度分档，供 AI 决策 mode 与跨 assembly 校验使用。
enum UiDensity { low, medium, high }

/// [UiSourcePack.densityAssessment] 的评估结果。
class UiDensityAssessment {
  final UiDensity level;
  final List<String> reasons;

  const UiDensityAssessment({required this.level, required this.reasons});

  bool get isHigh => level == UiDensity.high;
}
