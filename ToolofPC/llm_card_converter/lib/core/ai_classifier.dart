import 'dart:convert';

import 'api_service.dart';
import 'app_settings.dart';
import 'conversion_models.dart';

/// 第二步：AI 智能归类。
///
/// 把规则转换结果里"一锅塞"的内容（尤其 description）重新拆分、归位到
/// LLM Project 的结构化条目。严格防幻觉：
///   - 只能重组 / 拆分 / 改写原文，禁止新增设定；
///   - 允许最小必要改写（补主语、换代词、调语序、删连接词）使条目通顺；
///   - 输出结构化 JSON，解析或校验失败则回退规则结果（不破坏流程）。
class AiClassifier {
  /// 对 [ruleResult] 做 AI 归类。[sourceJson] 为原始第三方卡 JSON（提供上下文）。
  /// 失败时抛异常（由调用方决定是否回退）。
  static Future<CardConversionResult> classify(
      CardConversionResult ruleResult,
      Map<String, dynamic> sourceJson,
      ) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    final base = (sourceJson['data'] is Map)
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;

    final isSystem =
        (ruleResult.characterData?['card_type']?.toString() ?? '') == 'system';

    final raw = await ApiService.chatComplete(
      baseUrl: cfg.baseUrl,
      apiKey: cfg.apiKey,
      model: cfg.model,
      systemPrompt: isSystem ? _systemCardPrompt : _systemPrompt,
      userPrompt: _buildUserPrompt(base),
      temperature: 0.2,
    );

    final parsed = _parseJson(raw);
    if (parsed == null) {
      throw const FormatException('AI 返回的不是合法 JSON');
    }

    return isSystem
        ? _applySystemResult(ruleResult, parsed)
        : _applyToResult(ruleResult, parsed);
  }

  // ---------------- Prompt ----------------

  static const String _systemPrompt = '''
你是角色卡迁移助手。你的任务是把给定的角色卡原始字段，重新整理归类到目标结构中。

严格规则：
1. 只能使用原文中已存在的信息进行拆分、归类、改写；禁止新增任何原文没有的设定、经历、关系、能力或外貌。
2. 允许最小必要改写：补全主语、替换代词、调整语序、删除连接词，使每个条目语句通顺。
3. 不要翻译；保留原文语言。保留 {{char}} 与 {{user}} 占位符不变。
4. 如果某类信息原文没有，对应字段留空字符串，不要编造。
5. 必须只输出一个 JSON 对象，不要输出任何解释、注释或 markdown 代码块。

输出 JSON 结构（所有字段都必须存在）：
{
  "summary": "",                     // 一句话简短描述（不超过30字），概括角色，不得新增设定
  "name": {"last_name": "", "first_name": "", "other": ""},
  "relationship": "",                // 与用户(玩家)的关系
  "body": {"race":"","gender":"","age":"","height":"","weight":"","measurements":"","other":""},
  "psychology": {"personality":"","thoughts":"","interests":""},
  "background": {"origin":"","experiences":"","current":""},
  "scenario": "",                    // 当前场景/开场情境
  "custom_entries": [                // 无法归入以上类别、但属于角色设定的内容
    {"title":"", "content":""}
  ]
}

注意：
- name.first_name 通常就是角色名；姓名无法拆分时放 first_name。
- 外貌/身材信息归入 body；性格/喜好/思想归入 psychology；来历/经历/现状归入 background。
- 说话风格、特殊设定等可放 custom_entries。
- 不确定归类时，宁可放 custom_entries，也不要丢弃信息。
''';

  /// 系统卡归类 prompt：把世界/系统类设定拆进系统卡结构。
  static const String _systemCardPrompt = '''
你是角色卡迁移助手。这是一张"系统卡 / 世界卡"（扮演一个世界、系统或一群角色，
而非单一角色）。请把给定原始字段重新整理归类到目标结构中。

严格规则：
1. 只能使用原文中已存在的信息进行拆分、归类、改写；禁止新增任何原文没有的设定。
2. 允许最小必要改写（补主语、调整语序、删除连接词）使条目通顺。
3. 不要翻译；保留原文语言。保留 {{char}} 与 {{user}} 占位符不变。
4. 某类信息原文没有时，对应字段留空字符串，不要编造。
5. 必须只输出一个 JSON 对象，不要输出解释、注释或 markdown 代码块。

字段含义（务必区分清楚）：
- world_setting（世界设定）：对世界纯客观、物理性质的阐述。
  例："这是一个魔法世界""XX 是最大的帝国""羊村内有操场，灰太狼进不去"。
- worldview（世界观）：人/社会/文化层面的观念与规则。
  例："不会魔法的人被当作天生奴隶""羊族与狼族敌对，见面必生冲突"。
- system_mechanism（系统机制）：系统/世界的运行机制、规则、流程。
  例："完成任务触发奖励""火魔法的产生过程是…""回复格式/剧情运行规则"。
- characters（自带角色）：卡里附带的具体角色，每个拆成 name + setting。
  并非所有系统卡都有；没有就给空数组。

输出 JSON 结构（所有字段都必须存在）：
{
  "summary": "",                 // 一句话简短描述（不超过30字）
  "system_name": "",             // 这个系统/世界叫什么
  "system_summary": "",          // 一句话概括这个系统/世界
  "world_setting": "",
  "worldview": "",
  "system_mechanism": "",
  "protagonist": "",             // {{user}} 扮演谁；原文没写则留空
  "plot": "",                    // 开场情境/起因
  "characters": [                // 自带角色，没有则 []
    {"name": "", "setting": ""}
  ]
}
''';

  static String _buildUserPrompt(Map<String, dynamic> data) {
    String s(String k) => (data[k] ?? '').toString().trim();
    final buf = StringBuffer();
    buf.writeln('请整理以下角色卡原始字段：');
    buf.writeln();
    buf.writeln('【name】\n${s('name')}');
    buf.writeln('\n【description】\n${s('description')}');
    final personality = s('personality');
    if (personality.isNotEmpty) buf.writeln('\n【personality】\n$personality');
    final scenario = s('scenario');
    if (scenario.isNotEmpty) buf.writeln('\n【scenario】\n$scenario');
    // mes_example / first_mes 不参与归类（它们是对话示例/开场白，原样保留）
    return buf.toString();
  }

  // ---------------- 解析 ----------------

  /// 容错解析：去掉可能的 ```json 包裹，截取第一个 { 到最后一个 }。
  static Map<String, dynamic>? _parseJson(String raw) {
    var t = raw.trim();
    // 去 markdown 代码块
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final body = t.substring(start, end + 1);
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  // ---------------- 应用到结果 ----------------

  /// 用 AI 归类结果重建 character 的条目，保留规则结果的其它部分
  /// （开场白 / 示例对话 / 元信息 / 世界书 / 图片 / 原始数据等不动）。
  /// 系统卡：用 AI 结果重建系统卡条目，保留 tp_ 元信息条目。
  static CardConversionResult _applySystemResult(
      CardConversionResult ruleResult,
      Map<String, dynamic> ai,
      ) {
    final character = Map<String, dynamic>.from(ruleResult.characterData!);

    final oldEntries =
    _decodeEntries(character['entries_json'] as String? ?? '[]');
    final preserved = oldEntries.where((e) {
      final id = e['id']?.toString() ?? '';
      // 保留元信息类；丢弃旧的固定条目和旧的 personality 附加（将由 AI 重建）
      return id.startsWith('tp_') && id != 'tp_personality';
    }).toList();

    String str(dynamic v) => (v ?? '').toString();
    String j(Map m) => jsonEncode(m);

    final entries = <Map<String, dynamic>>[];
    var order = 0;
    void add(Map<String, dynamic> e) {
      e['sort_order'] = order++;
      entries.add(e);
    }

    final sysName = str(ai['system_name']).trim();
    add({
      'id': 'system_name',
      'title': '系统名称',
      'content': sysName.isNotEmpty ? sysName : ruleResult.characterName,
      'enabled': true,
      'is_custom': false,
    });

    final sysSummary = str(ai['system_summary']);
    add({
      'id': 'system_summary',
      'title': '系统概要',
      'content': sysSummary,
      'enabled': sysSummary.trim().isNotEmpty,
      'is_custom': false,
    });

    final detail = {
      'world_setting': str(ai['world_setting']),
      'worldview': str(ai['worldview']),
      'system_mechanism': str(ai['system_mechanism']),
    };
    add({
      'id': 'system_details',
      'title': '系统详情',
      'content': j(detail),
      'enabled': detail.values.any((v) => v.trim().isNotEmpty),
      'is_custom': false,
    });

    final protagonist = str(ai['protagonist']);
    add({
      'id': 'protagonist',
      'title': '主角设定',
      'content': j({
        'name': '',
        'detail': {
          'race': '',
          'gender': '',
          'age': '',
          'body': '',
          'background': protagonist,
        },
      }),
      'enabled': protagonist.trim().isNotEmpty,
      'is_custom': false,
    });

    final plot = str(ai['plot']);
    add({
      'id': 'plot',
      'title': '剧情',
      'content': j({
        'cause': plot,
        'events': '',
        'goal': '',
        'possible_endings': '',
      }),
      'enabled': plot.trim().isNotEmpty,
      'is_custom': false,
    });

    // 自带角色 -> 自定义条目
    final chars = ai['characters'];
    if (chars is List) {
      var i = 0;
      for (final c in chars) {
        if (c is! Map) continue;
        final cname = str(c['name']).trim();
        final setting = str(c['setting']).trim();
        if (cname.isEmpty && setting.isEmpty) continue;
        add({
          'id': 'ai_char_$i',
          'title': cname.isEmpty ? '角色 ${i + 1}' : cname,
          'content': setting,
          'enabled': true,
          'is_custom': true,
        });
        i++;
      }
    }

    for (final e in preserved) {
      add(Map<String, dynamic>.from(e));
    }

    character['entries_json'] = jsonEncode(entries);
    final summary = str(ai['summary']).trim();
    if (summary.isNotEmpty) character['description'] = summary;

    return ruleResult.copyWith(
      characterData: character,
      convertedFields: [...ruleResult.convertedFields, 'AI 系统卡归类'],
      notes: [
        ...ruleResult.notes,
        ConversionNote.info('已由 AI 按系统卡结构重新归类。'),
      ],
    );
  }

  static CardConversionResult _applyToResult(
      CardConversionResult ruleResult,
      Map<String, dynamic> ai,
      ) {
    final character = Map<String, dynamic>.from(ruleResult.characterData!);

    // 解析规则结果原有条目，保留我们不重排的那些（示例对话/来源/作者备注/原始数据/自定义）
    final oldEntries = _decodeEntries(character['entries_json'] as String? ?? '[]');
    final preserved = oldEntries.where((e) {
      final id = e['id']?.toString() ?? '';
      return id.startsWith('tp_'); // tp_mes_example / tp_source_meta / tp_creator_notes / tp_raw / tp_scenario 等
    }).toList();

    String j(Map m) => jsonEncode(m);
    Map<String, dynamic> mp(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

    final name = mp(ai['name']);
    final body = mp(ai['body']);
    final psy = mp(ai['psychology']);
    final bg = mp(ai['background']);
    String str(dynamic v) => (v ?? '').toString();

    final entries = <Map<String, dynamic>>[];
    var order = 0;
    void add(Map<String, dynamic> e) {
      e['sort_order'] = order++;
      entries.add(e);
    }

    add({
      'id': 'name_entry',
      'title': '名称',
      'content': j({
        'last_name': str(name['last_name']),
        'first_name': str(name['first_name']).isNotEmpty
            ? str(name['first_name'])
            : (ruleResult.characterName),
        'other': str(name['other']),
      }),
      'enabled': true,
      'is_custom': false,
    });

    final relationship = str(ai['relationship']);
    add({
      'id': 'relationship',
      'title': '与用户关系',
      'content': relationship,
      'enabled': true,
      'is_custom': false,
    });

    final bodyMap = {
      'race': str(body['race']),
      'gender': str(body['gender']),
      'age': str(body['age']),
      'height': str(body['height']),
      'weight': str(body['weight']),
      'measurements': str(body['measurements']),
      'other': str(body['other']),
    };
    add({
      'id': 'body',
      'title': '身体数据',
      'content': j(bodyMap),
      'enabled': bodyMap.values.any((v) => v.trim().isNotEmpty),
      'is_custom': false,
    });

    final psyMap = {
      'personality': str(psy['personality']),
      'thoughts': str(psy['thoughts']),
      'interests': str(psy['interests']),
    };
    add({
      'id': 'psychology',
      'title': '心理数据',
      'content': j(psyMap),
      'enabled': psyMap.values.any((v) => v.trim().isNotEmpty),
      'is_custom': false,
    });

    final bgMap = {
      'origin': str(bg['origin']),
      'experiences': str(bg['experiences']),
      'current': str(bg['current']),
    };
    add({
      'id': 'background',
      'title': '背景数据',
      'content': j(bgMap),
      'enabled': bgMap.values.any((v) => v.trim().isNotEmpty),
      'is_custom': false,
    });

    // AI 给的场景：若规则结果里没有 tp_scenario，则补一个
    final scenario = str(ai['scenario']);
    final hasScenario = preserved.any((e) => e['id'] == 'tp_scenario');
    if (scenario.isNotEmpty && !hasScenario) {
      add({
        'id': 'tp_scenario',
        'title': '当前场景',
        'content': scenario,
        'enabled': true,
        'is_custom': true,
      });
    }

    // AI 的自定义条目
    final custom = ai['custom_entries'];
    if (custom is List) {
      var i = 0;
      for (final c in custom) {
        if (c is! Map) continue;
        final content = str(c['content']).trim();
        if (content.isEmpty) continue;
        add({
          'id': 'ai_custom_$i',
          'title': str(c['title']).trim().isEmpty ? '设定 ${i + 1}' : str(c['title']),
          'content': content,
          'enabled': true,
          'is_custom': true,
        });
        i++;
      }
    }

    // 追加保留的规则条目（示例对话/来源/备注/原始数据等）
    for (final e in preserved) {
      add(Map<String, dynamic>.from(e));
    }

    character['entries_json'] = jsonEncode(entries);

    // 简短描述：用 AI 生成的一句话 summary 替换原本冗长的整段 description。
    // 原始 description 全文仍保留在背景条目与 tp_raw 中，不丢失。
    final summary = str(ai['summary']).trim();
    if (summary.isNotEmpty) {
      character['description'] = summary;
    }

    final converted = List<String>.from(ruleResult.convertedFields)
      ..add('AI 智能归类');

    return CardConversionResult(
      sourceName: ruleResult.sourceName,
      format: ruleResult.format,
      success: true,
      partial: ruleResult.partial,
      characterData: character,
      worldBooks: ruleResult.worldBooks,
      imageBytes: ruleResult.imageBytes,
      convertedFields: converted,
      unsupportedFields: ruleResult.unsupportedFields,
      notes: [
        ...ruleResult.notes,
        ConversionNote.info('已由 AI 重新归类角色设定条目。'),
      ],
    );
  }

  static List<Map<String, dynamic>> _decodeEntries(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
