import 'dart:convert';

import '../pipeline/pipeline.dart';
import 'api_service.dart';
import 'app_settings.dart';
import 'conversion_models.dart';

/// 第三步：检查精修（审计）。
///
/// 让 AI 对照"原文"与"当前转译结果"，找出三类问题，产出问题清单：
///   - missing   漏转：原文有、结果未体现
///   - added     疑似新增（幻觉）：结果有、原文无依据
///   - duplicate 重复归类：同一信息出现在多个条目
///
/// 只产审计意见，不自动改内容（用户自行应用/忽略）。
/// NSFW 容错：模型拒绝 / 返回空 → 视为"无问题"返回空清单，不阻断流程。
class AiRefiner {
  /// 审计 [current] 结果。[sourceJson] 为原始第三方卡 JSON。
  /// 返回问题清单（可能为空）。真正的网络/解析错误才抛异常。
  static Future<List<RefineIssue>> refine(
      CardConversionResult current,
      Map<String, dynamic> sourceJson,
      ) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    final base = (sourceJson['data'] is Map)
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;

    final raw = await ApiService.chatComplete(
      baseUrl: cfg.baseUrl,
      apiKey: cfg.apiKey,
      model: cfg.model,
      systemPrompt: _systemPrompt,
      userPrompt: _buildUserPrompt(base, current),
      temperature: 0.1,
    );

    // NSFW / 审核拒绝：当作"无可审计"返回空清单，流程照常完成。
    if (ApiService.looksLikeRefusal(raw)) {
      return const [];
    }

    final parsed = _parseIssues(raw);
    return parsed;
  }

  // ---------------- Prompt ----------------

  static const String _systemPrompt = '''
你是角色卡迁移质检助手。给你"原始角色卡字段"和"已整理的结构化结果"，
请审计整理结果是否忠实于原文，找出问题。

只检查以下三类问题：
1. missing（漏转）：原始字段里有、但整理结果里完全没体现的设定信息。
2. added（疑似新增）：整理结果里有、但在原始字段中找不到依据的内容（可能是幻觉）。
3. duplicate（重复）：同一条信息被重复放进了多个条目。

规则：
- 只审计"角色人物设定"（外貌、性格、关系、背景、经历、场景等）的忠实度。
- 忽略以下内容，不要因它们未体现而报 missing：
  输出格式规则、回复格式、状态栏要求、对话风格指令、{{original}} 等占位、
  被 <Rule> <Reply> <format> 等标签包裹的"写作/输出指令"，
  以及作者备注、来源、群号、版权声明等元信息。
- 不要因为措辞不同就报 added；只要语义在原文（含 description / personality /
  creator / creator_notes / tags）有依据就算忠实。
- 合理的补主语、改代词、拆句不算问题。
- 不评价文笔，只看角色设定信息是否忠实、完整、无重复。
- 必须只输出一个 JSON 数组，不要输出解释或 markdown 代码块。
- 没有问题时输出空数组 []。

输出格式（数组，每个元素）：
[
  {
    "type": "missing|added|duplicate",
    "fields": ["涉及的目标字段或条目，如 心理数据 / 背景数据"],
    "text": "相关的具体文本片段",
    "suggestion": "简短建议，如：建议补入背景；疑似原文无此设定，建议删除；与背景重复，建议保留其一",
    "confidence": 0.0
  }
]
''';

  static String _buildUserPrompt(
      Map<String, dynamic> sourceData,
      CardConversionResult current,
      ) {
    String s(String k) => (sourceData[k] ?? '').toString().trim();

    final buf = StringBuffer();
    buf.writeln('【原始角色卡字段】');
    buf.writeln('name: ${s('name')}');
    buf.writeln('description: ${s('description')}');
    if (s('personality').isNotEmpty) {
      buf.writeln('personality: ${s('personality')}');
    }
    if (s('scenario').isNotEmpty) buf.writeln('scenario: ${s('scenario')}');
    // 把元信息也作为"原文依据"提供，避免它们被误判为新增。
    if (s('creator').isNotEmpty) buf.writeln('creator: ${s('creator')}');
    if (s('creator_notes').isNotEmpty) {
      buf.writeln('creator_notes: ${s('creator_notes')}');
    }
    final tags = sourceData['tags'];
    if (tags is List && tags.isNotEmpty) {
      buf.writeln('tags: ${tags.join(', ')}');
    }

    buf.writeln();
    buf.writeln('【已整理的结构化结果】（仅审计以下人设条目）');
    final entries = _decodeEntries(
        current.characterData?['entries_json'] as String? ?? '[]');
    for (final e in entries) {
      final id = e['id']?.toString() ?? '';
      // 只审计"从自由文本拆出的人设条目"。
      // 元信息 / 备份 / 后置指令 / 示例对话等不参与漏转/新增审计。
      if (!_auditableEntryId(id)) continue;
      final title = e['title']?.toString() ?? '';
      final content = _readableContent(e['content']?.toString() ?? '');
      if (content.trim().isEmpty) continue;
      buf.writeln('- $title：$content');
    }
    return buf.toString();
  }

  /// 参与审计的条目：固定人设条目 + AI 拆出的场景/自定义。
  /// 排除：tp_raw / tp_source_meta / tp_creator_notes / tp_mes_example /
  /// tp_post_history 等元信息类。
  static bool _auditableEntryId(String id) {
    const fixed = {
      'name_entry',
      'relationship',
      'body',
      'psychology',
      'background',
    };
    if (fixed.contains(id)) return true;
    if (id == 'tp_scenario') return true;
    if (id.startsWith('ai_custom_')) return true;
    return false;
  }

  static String _readableContent(String raw) {
    final t = raw.trim();
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t) as Map;
        return m.entries
            .map((e) => '${e.value}')
            .where((v) => v.trim().isNotEmpty)
            .join('；');
      } catch (_) {}
    }
    return t;
  }

  // ---------------- 解析 ----------------

  static List<RefineIssue> _parseIssues(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final start = t.indexOf('[');
    final end = t.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final list = jsonDecode(t.substring(start, end + 1)) as List;
      final issues = <RefineIssue>[];
      for (final e in list) {
        if (e is! Map) continue;
        final type = _parseType(e['type']?.toString());
        if (type == null) continue;
        issues.add(RefineIssue(
          type: type,
          fields: (e['fields'] is List)
              ? (e['fields'] as List).map((x) => x.toString()).toList()
              : const [],
          text: e['text']?.toString() ?? '',
          suggestion: e['suggestion']?.toString() ?? '',
          confidence: _parseConfidence(e['confidence']),
        ));
      }
      return issues;
    } catch (_) {
      return const [];
    }
  }

  static RefineIssueType? _parseType(String? s) {
    switch (s) {
      case 'missing':
        return RefineIssueType.missing;
      case 'added':
        return RefineIssueType.added;
      case 'duplicate':
        return RefineIssueType.duplicate;
      case 'misclassified':
        return RefineIssueType.misclassified;
    }
    return null;
  }

  static double _parseConfidence(dynamic v) {
    if (v is num) return v.toDouble().clamp(0, 1);
    if (v is String) return (double.tryParse(v) ?? 0).clamp(0, 1);
    return 0;
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
