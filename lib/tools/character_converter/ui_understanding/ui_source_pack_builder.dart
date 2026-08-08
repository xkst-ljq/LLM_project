import 'ui_source_pack.dart';

/// 从原始第三方卡 JSON 构建 AI UI 理解证据包。
///
/// 注意：这里不判断“应该生成什么 UI”，只抽取证据和 source path。
class UiSourcePackBuilder {
  const UiSourcePackBuilder._();

  static UiSourcePack build(Map<String, dynamic> sourceJson) {
    final data = sourceJson['data'] is Map
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;
    final ext = data['extensions'] is Map
        ? Map<String, dynamic>.from(data['extensions'] as Map)
        : <String, dynamic>{};

    String s(String key) => (data[key] ?? '').toString();

    final firstMes = s('first_mes');
    final alts = (data['alternate_greetings'] is List)
        ? (data['alternate_greetings'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final regex = _extractRegexScripts(ext);
    final plugins = _extractPluginScripts(ext);
    final actions = <UiActionEvidence>[
      ..._extractSendActions(firstMes, 'data.first_mes'),
      for (var i = 0; i < alts.length; i++)
        ..._extractSendActions(alts[i], 'data.alternate_greetings[$i]'),
    ];

    final htmlSnippets = <UiSnippetEvidence>[
      ..._extractHtmlSnippets(s('description'), 'data.description'),
      ..._extractHtmlSnippets(firstMes, 'data.first_mes'),
      for (var i = 0; i < alts.length && i < 8; i++)
        ..._extractHtmlSnippets(alts[i], 'data.alternate_greetings[$i]'),
      ..._extractHtmlSnippets(s('mes_example'), 'data.mes_example'),
    ];

    return UiSourcePack(
      cardName: s('name').trim(),
      description: s('description'),
      personality: s('personality'),
      scenario: s('scenario'),
      firstMes: firstMes,
      alternateGreetings: alts,
      mesExample: s('mes_example'),
      systemPrompt: s('system_prompt'),
      regexScripts: regex,
      pluginScripts: plugins,
      worldBookEvidence: _extractWorldBookEvidence(data),
      htmlSnippets: htmlSnippets,
      actionSnippets: actions,
    );
  }

  static List<UiRegexEvidence> _extractRegexScripts(Map<String, dynamic> ext) {
    final raw = ext['regex_scripts'];
    if (raw is! List) return const [];
    final out = <UiRegexEvidence>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final find = m['findRegex']?.toString() ?? '';
      final replace = m['replaceString']?.toString() ?? '';
      if (find.trim().isEmpty && replace.trim().isEmpty) continue;
      out.add(UiRegexEvidence(
        path: 'data.extensions.regex_scripts[$i]',
        scriptName: m['scriptName']?.toString() ?? '(未命名正则)',
        enabled: m['disabled'] != true && m['enabled'] != false,
        findRegex: find,
        replaceString: replace,
      ));
      if (out.length >= 18) break;
    }
    return out;
  }

  static List<UiPluginEvidence> _extractPluginScripts(Map<String, dynamic> ext) {
    final helper = ext['tavern_helper'];
    if (helper == null) return const [];
    final out = <UiPluginEvidence>[];

    void walk(dynamic node, String path) {
      if (out.length >= 12) return;
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], '$path[$i]');
        }
      } else if (node is Map) {
        final m = Map<String, dynamic>.from(node);
        final type = m['type']?.toString();
        final content = m['content']?.toString() ?? '';
        if (type == 'script' && content.trim().isNotEmpty) {
          out.add(UiPluginEvidence(
            path: path,
            enabled: m['enabled'] == true,
            content: content,
            urls: _extractJsUrls(content),
          ));
        }
        m.forEach((key, value) => walk(value, '$path.$key'));
      }
    }

    walk(helper, 'data.extensions.tavern_helper');
    return out;
  }

  static List<String> _extractJsUrls(String text) {
    return RegExp(r"https?://[^\s\\\x22']+\.js")
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
  }

  static List<UiActionEvidence> _extractSendActions(String text, String path) {
    if (text.trim().isEmpty) return const [];
    final out = <UiActionEvidence>[];
    final re = RegExp(r"""send\(\s*['"](.+?)['"]\s*\)""");
    for (final m in re.allMatches(text)) {
      final value = m.group(1)?.trim() ?? '';
      if (value.isEmpty) continue;
      out.add(UiActionEvidence(path: path, text: value));
      if (out.length >= 20) break;
    }
    return out;
  }

  static List<UiSnippetEvidence> _extractHtmlSnippets(String text, String path) {
    if (!text.contains('<') || !text.contains('>')) return const [];
    final out = <UiSnippetEvidence>[];
    final patterns = <RegExp>[
      RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
      RegExp(r'<div[\s\S]{0,2500}</div>', caseSensitive: false),
      RegExp(r'<[a-zA-Z][^>]*(style|onclick)=[\s\S]{0,1800}>', caseSensitive: false),
    ];
    for (final p in patterns) {
      for (final m in p.allMatches(text)) {
        final snippet = m.group(0)?.trim() ?? '';
        if (snippet.isEmpty) continue;
        out.add(UiSnippetEvidence(path: path, text: snippet));
        if (out.length >= 8) return out;
      }
    }
    return out;
  }

  static List<WorldBookEvidence> _extractWorldBookEvidence(
    Map<String, dynamic> data,
  ) {
    final book = data['character_book'];
    if (book is! Map) return const [];
    final rawEntries = book['entries'];
    final List entries;
    if (rawEntries is List) {
      entries = rawEntries;
    } else if (rawEntries is Map) {
      entries = rawEntries.values.toList();
    } else {
      return const [];
    }

    final out = <WorldBookEvidence>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final title = (m['comment'] ?? m['name'] ?? '').toString();
      final content = (m['content'] ?? '').toString();
      final hay = '$title\n$content'.toLowerCase();
      if (!_looksUiOrVarRelated(hay)) continue;
      out.add(WorldBookEvidence(
        path: 'data.character_book.entries[$i]',
        title: title.trim().isEmpty ? '条目 ${i + 1}' : title.trim(),
        content: content,
      ));
      if (out.length >= 20) break;
    }
    return out;
  }

  static bool _looksUiOrVarRelated(String text) {
    const markers = [
      'ui',
      'html',
      'css',
      '状态',
      '状态栏',
      '界面',
      '变量',
      '数值',
      'initvar',
      'var',
      'mvu',
      'status',
      'attribute',
      'stats',
      'onclick',
      'send(',
    ];
    return markers.any(text.contains);
  }
}
