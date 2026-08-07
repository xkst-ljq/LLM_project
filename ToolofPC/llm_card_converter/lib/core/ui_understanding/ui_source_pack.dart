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
    b.writeln('sourcePackVersion: ui_source_pack_v2026-08-07.5');
    b.writeln('name: $cardName');
    _writeOpeningBranchSummary(b);
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
      b.writeln('The source has a narrative/message wrapper regex (for example <Alliance>/<正文>/scrollable content). If you choose uiMode=scene, you MUST declare a base layout page with role="story"/"message"/"narrative" so Dart inserts a real message_flow component. Mentioning message_flow only in notes is not enough. Put DQ choices/free input on that same story page near the message_flow; move low-frequency status/task/friends details into overlay pages when crowded.');
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
      b.writeln('\n## system_prompt\n${_clip(systemPrompt, 3000)}');
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

  static String _clip(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}\n...[truncated ${t.length - max} chars]';
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
