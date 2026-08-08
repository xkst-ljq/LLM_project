import 'dart:convert';

import 'conversion_models.dart';

/// 将 SillyTavern / TavernAI 角色卡（V1 / V2 JSON）映射为 LLM Project 内部结构。
///
/// 输出的 character map 字段与 CharacterCardAssetService 的 data/character.json
/// 完全一致，因此可以直接写入 .llmcard，也可以直接 insertCharacter。
///
/// 重要原则：
///   - 规则映射，忠实搬运，不新增设定；
///   - 不支持 / 高级字段统一降级为「禁用的自定义条目」+ 报告说明，不丢失；
///   - 原始第三方 JSON 整体保留为一个禁用条目，便于以后重新转换。
class CharacterCardMapper {
  /// [outerJson] 为外层 JSON：
  ///   - V2: {spec, spec_version, data:{...}}
  ///   - V1: {name, description, ...}
  static CardConversionResult map({
    required Map<String, dynamic> outerJson,
    required ThirdPartyCardFormat format,
    required String sourceName,
    List<int>? imageBytes,
    String cardType = 'character', // 'character' 人物卡 / 'system' 系统卡
  }) {
    // 统一取出「数据体」：V2 在 data 下，V1 在顶层。
    final data = (outerJson['data'] is Map)
        ? Map<String, dynamic>.from(outerJson['data'] as Map)
        : Map<String, dynamic>.from(outerJson);

    final converted = <String>[];
    final unsupported = <String>[];
    final notes = <ConversionNote>[];

    String s(String key) => (data[key] ?? '').toString().trim();

    final name = s('name');
    if (name.isEmpty) {
      return CardConversionResult.failure(
        sourceName,
        format,
        '未在角色卡中找到角色名（name），无法转换。',
      );
    }
    converted.add('名称');

    final description = s('description');
    final personality = s('personality');
    final scenario = s('scenario');
    final mesExample = s('mes_example');
    final firstMes = s('first_mes');
    final systemPrompt = s('system_prompt');
    final postHistory = s('post_history_instructions');
    final creatorNotes = s('creator_notes').isNotEmpty
        ? s('creator_notes')
        : s('creatorcomment');
    final creator = s('creator');
    final characterVersion = s('character_version');
    final spec = outerJson['spec']?.toString() ?? '';
    final specVersion = outerJson['spec_version']?.toString() ?? '';

    // -------- 固定条目（按卡类型）--------
    final isSystem = cardType == 'system';
    final entries = <Map<String, dynamic>>[];
    var order = 0;

    void addEntry(Map<String, dynamic> e) {
      e['sort_order'] = order++;
      entries.add(e);
    }

    String customId(String suffix) =>
        'tp_$suffix'; // third-party，稳定可读，避免与时间戳冲突

    if (isSystem) {
      // 系统卡固定条目（系统名称 / 概要 / 详情 / 主角设定 / 剧情）。
      // 规则阶段只整段搬运：description 先粗塞进系统详情的世界观，
      // 精细拆分（世界设定 / 世界观 / 系统机制）交给第二步 AI 归类。
      addEntry({
        'id': 'system_name',
        'title': '系统名称',
        'content': name,
        'enabled': true,
        'is_custom': false,
      });
      addEntry({
        'id': 'system_summary',
        'title': '系统概要',
        'content': '',
        'enabled': true,
        'is_custom': false,
      });
      addEntry({
        'id': 'system_details',
        'title': '系统详情',
        'content': jsonEncode({
          'world_setting': '',
          'worldview': description,
          'system_mechanism': '',
        }),
        'enabled': description.isNotEmpty,
        'is_custom': false,
      });
      if (description.isNotEmpty) converted.add('简介/描述(description)');
      addEntry({
        'id': 'protagonist',
        'title': '主角设定',
        'content': jsonEncode({
          'name': '',
          'detail': {
            'race': '',
            'gender': '',
            'age': '',
            'body': '',
            'background': '',
          },
        }),
        'enabled': false,
        'is_custom': false,
      });
      addEntry({
        'id': 'plot',
        'title': '剧情',
        'content': jsonEncode({
          'cause': scenario,
          'events': '',
          'goal': '',
          'possible_endings': '',
        }),
        'enabled': scenario.isNotEmpty,
        'is_custom': false,
      });
      if (personality.isNotEmpty) {
        // 系统卡无心理数据，personality 先并入世界观备查
        addEntry({
          'id': customId('personality'),
          'title': '附加设定 (personality)',
          'content': personality,
          'enabled': true,
          'is_custom': true,
        });
        converted.add('性格(personality)');
      }
    } else {
      // 名称条目
      addEntry({
        'id': 'name_entry',
        'title': '名称',
        'content':
            jsonEncode({'last_name': '', 'first_name': name, 'other': ''}),
        'enabled': true,
        'is_custom': false,
      });

      // 与用户关系（V1/V2 无对应，留空启用）
      addEntry({
        'id': 'relationship',
        'title': '与用户关系',
        'content': '',
        'enabled': true,
        'is_custom': false,
      });

      // 身体数据（无对应字段，留空禁用）
      addEntry({
        'id': 'body',
        'title': '身体数据',
        'content': jsonEncode({
          'race': '',
          'gender': '',
          'age': '',
          'height': '',
          'weight': '',
          'measurements': '',
          'other': '',
        }),
        'enabled': false,
        'is_custom': false,
      });

      // 心理数据 <- personality
      addEntry({
        'id': 'psychology',
        'title': '心理数据',
        'content': jsonEncode({
          'personality': personality,
          'thoughts': '',
          'interests': '',
        }),
        'enabled': personality.isNotEmpty,
        'is_custom': false,
      });
      if (personality.isNotEmpty) converted.add('性格(personality)');

      // 背景数据 <- description（作为出身/背景信息保留）
      addEntry({
        'id': 'background',
        'title': '背景数据',
        'content': jsonEncode({
          'origin': description,
          'experiences': '',
          'current': '',
        }),
        'enabled': description.isNotEmpty,
        'is_custom': false,
      });
      if (description.isNotEmpty) converted.add('简介/描述(description)');
    }

    // -------- 自定义条目 --------
    // 系统卡的 scenario 已并入「剧情.cause」，此处只对人物卡补"当前场景"。
    if (!isSystem && scenario.isNotEmpty) {
      addEntry({
        'id': customId('scenario'),
        'title': '当前场景',
        'content': scenario,
        'enabled': true,
        'is_custom': true,
      });
      converted.add('场景(scenario)');
    }

    if (mesExample.isNotEmpty) {
      addEntry({
        'id': customId('mes_example'),
        'title': '示例对话',
        'content': mesExample,
        'enabled': true,
        'is_custom': true,
      });
      converted.add('示例对话(mes_example)');
    }

    if (postHistory.isNotEmpty) {
      addEntry({
        'id': customId('post_history'),
        'title': '后置指令 (post_history_instructions)',
        'content': postHistory,
        'enabled': true,
        'is_custom': true,
      });
      converted.add('后置指令(post_history_instructions)');
      notes.add(ConversionNote.info(
          '已导入 post_history_instructions 为「后置指令」条目。'));
    }

    // 元信息（默认不注入 Prompt）
    final metaLines = <String>[];
    if (creator.isNotEmpty) metaLines.add('作者：$creator');
    if (characterVersion.isNotEmpty) metaLines.add('角色版本：$characterVersion');
    if (spec.isNotEmpty) {
      metaLines.add('来源格式：$spec${specVersion.isNotEmpty ? ' $specVersion' : ''}');
    }
    final tags = _stringList(data['tags']);
    if (tags.isNotEmpty) metaLines.add('标签：${tags.join('、')}');
    if (metaLines.isNotEmpty) {
      addEntry({
        'id': customId('source_meta'),
        'title': '来源信息',
        'content': metaLines.join('\n'),
        'enabled': false,
        'is_custom': true,
      });
      converted.add('来源信息(creator/version/tags)');
    }

    if (creatorNotes.isNotEmpty) {
      addEntry({
        'id': customId('creator_notes'),
        'title': '作者备注',
        'content': creatorNotes,
        'enabled': false,
        'is_custom': true,
      });
      converted.add('作者备注(creator_notes)');
    }

    // -------- 检测未支持 / 高级字段 --------
    final ext = data['extensions'];
    if (ext is Map && ext.isNotEmpty) {
      unsupported.add('extensions（扩展字段）');
      if (ext['depth_prompt'] != null) unsupported.add('depth_prompt');
      if (ext['regex_scripts'] != null) {
        unsupported.add('regex_scripts（正则脚本，不执行）');
      }
    }
    if (data['talkativeness'] != null) unsupported.add('talkativeness');
    if (_hasMacros('$description$personality$scenario$firstMes$mesExample')) {
      notes.add(ConversionNote.info(
          '检测到 {{char}} / {{user}} 等占位符，已原样保留（本应用同样支持）。'));
    }

    // -------- 原始数据保留 --------
    addEntry({
      'id': customId('raw'),
      'title': '原始第三方角色卡数据',
      'content': const JsonEncoder.withIndent('  ').convert(outerJson),
      'enabled': false,
      'is_custom': true,
    });

    // -------- 开场白 --------
    final greetings = <Map<String, dynamic>>[];
    var gi = 0;
    if (firstMes.isNotEmpty) {
      greetings.add({'id': 'g_${gi++}', 'content': firstMes});
      converted.add('开场白(first_mes)');
    }
    final alts = _stringList(data['alternate_greetings']);
    for (final a in alts) {
      if (a.trim().isEmpty) continue;
      greetings.add({'id': 'g_${gi++}', 'content': a});
    }
    if (alts.isNotEmpty) {
      converted.add('备用开场白(alternate_greetings) ×${alts.length}');
    }

    // -------- 内嵌世界书 --------
    final worldBooks = <Map<String, dynamic>>[];
    var worldBookId = '';
    final book = data['character_book'];
    if (book is Map) {
      final wb = _mapCharacterBook(
        Map<String, dynamic>.from(book),
        characterName: name,
        unsupported: unsupported,
        notes: notes,
      );
      if (wb != null) {
        worldBooks.add(wb);
        worldBookId = wb['id'] as String;
        converted.add('内嵌世界书(character_book) '
            '${(wb['__entry_count__'] ?? 0)} 条');
        wb.remove('__entry_count__');
      }
    }

    // -------- 扩展元信息（标签 / 作者 / 来源 / post_history / 示例对话）--------
    final meta = <String, dynamic>{
      'tags': tags,
      'creator': creator,
      'creator_notes': creatorNotes,
      'character_version': characterVersion,
      'source_format': format.label,
      'post_history_instructions': postHistory,
      'mes_example': mesExample,
    };

    // -------- 组装 LLM Project 角色 --------
    final character = <String, dynamic>{
      'id': customId('id'), // 写入 .llmcard 时由导入流程重新分配
      'name': name,
      'avatar': '',
      'card_image_path': '',
      'description': description,
      'system_prompt': systemPrompt,
      'world_book_id': worldBookId,
      'background_id': '',
      'card_type': cardType,
      'entries_json': jsonEncode(entries),
      'opening_greetings': jsonEncode(greetings),
      'meta_json': jsonEncode(meta),
      'user_name': '',
      'user_avatar': '',
      'user_detail_setting': '',
    };
    if (systemPrompt.isNotEmpty) converted.add('系统提示(system_prompt)');

    final partial = unsupported.isNotEmpty;
    if (partial) {
      notes.add(ConversionNote.warning(
          '部分高级 / 扩展字段当前不支持执行，已保留原始数据但不会生效。'));
    }

    return CardConversionResult(
      sourceName: sourceName,
      format: format,
      success: true,
      partial: partial,
      characterData: character,
      worldBooks: worldBooks,
      imageBytes: imageBytes,
      convertedFields: converted,
      unsupportedFields: unsupported,
      notes: notes,
    );
  }

  /// character_book -> LLM Project 世界书（world_books.json 形态）。
  static Map<String, dynamic>? _mapCharacterBook(
    Map<String, dynamic> book, {
    required String characterName,
    required List<String> unsupported,
    required List<ConversionNote> notes,
  }) {
    final rawEntries = book['entries'];
    final List entryList;
    if (rawEntries is List) {
      entryList = rawEntries;
    } else if (rawEntries is Map) {
      // 部分格式 entries 是以索引为 key 的 Map
      entryList = rawEntries.values.toList();
    } else {
      entryList = const [];
    }
    if (entryList.isEmpty) return null;

    var downgraded = false;
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < entryList.length; i++) {
      final e = entryList[i];
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final keys = _stringList(m['keys']);
      final secondary = _stringList(m['secondary_keys']);
      final content = (m['content'] ?? '').toString();
      final title = (m['comment'] ?? m['name'] ?? '').toString().trim();
      // 酒馆条目 enabled=false 视为作者关闭：仍导入，但默认不启用，
      // 用户可在世界书里手动开启（忠实保留作者内容，由用户决定）。
      final enabled = m['enabled'] != false;
      final constant = m['constant'] == true;

      // insertion_order（注入优先级）：兼容 priority 字段。
      final order = _readInt(m['insertion_order']) ?? _readInt(m['priority']);

      // position（插入位置）：酒馆 0/before_char -> before_char；其余 -> after_char。
      final position = _mapPosition(m['position']);

      // 仍无法表达的高级字段（深度 / 概率 / selective / 大小写）记为降级。
      for (final adv in const [
        'depth',
        'probability',
        'selective',
        'case_sensitive',
      ]) {
        if (m.containsKey(adv) && m[adv] != null) downgraded = true;
      }

      entries.add({
        'id': 'wbe_$i',
        'title': title.isNotEmpty
            ? title
            : (keys.isNotEmpty ? keys.first : '条目 ${i + 1}'),
        'content': content,
        'keys': keys,
        'secondary_keys': secondary,
        'sort_order': i,
        'insertion_order': order ?? i,
        'position': position,
        'enabled': enabled,
        'always_active': constant,
        'recursive': true,
      });
    }

    if (entries.isEmpty) return null;

    if (downgraded) {
      unsupported.add('世界书部分高级触发字段（扫描深度 / 概率 / selective / 大小写敏感）');
      notes.add(ConversionNote.warning(
          '关键词列表、次关键词、启用状态、优先级、插入位置已保留；'
          '扫描深度 / 概率 / selective / 大小写敏感等字段暂不支持，已忽略。'));
    }

    final bookName = (book['name'] ?? '').toString().trim();
    return {
      'id': 'tp_wb_id',
      'name': bookName.isNotEmpty ? bookName : '$characterName 的世界书',
      'description': (book['description'] ?? '').toString(),
      'detailed_setting': '',
      'entries_json': jsonEncode(entries),
      'cover_image_path': '',
      'is_preset': 0,
      '__entry_count__': entries.length,
    };
  }

  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const [];
  }

  static int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// 把酒馆的 position 映射到本项目的 before_char / after_char。
  /// 酒馆数值：0=角色定义之前 -> before_char；其余 -> after_char。
  /// 字符串：包含 'after' -> after_char；其余 -> before_char。
  static String _mapPosition(dynamic v) {
    if (v is int) return v == 0 ? 'before_char' : 'after_char';
    if (v is num) return v == 0 ? 'before_char' : 'after_char';
    if (v is String) {
      final s = v.toLowerCase();
      if (s.contains('after')) return 'after_char';
      if (s.contains('before')) return 'before_char';
      final n = int.tryParse(s.trim());
      if (n != null) return n == 0 ? 'before_char' : 'after_char';
    }
    return 'before_char';
  }

  static bool _hasMacros(String text) =>
      RegExp(r'\{\{\s*(char|user)\s*\}\}', caseSensitive: false).hasMatch(text);
}
