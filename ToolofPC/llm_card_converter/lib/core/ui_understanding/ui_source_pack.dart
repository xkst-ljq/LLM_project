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

  /// 压成适合模型阅读的文本。
  String toPromptText() {
    final b = StringBuffer();
    b.writeln('# Card Basic Fields');
    b.writeln('name: $cardName');
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
