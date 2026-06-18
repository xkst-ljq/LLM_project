import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/conversion_models.dart';

/// 角色卡结果预览组件。
///
/// 把 [CardConversionResult] 渲染成可读的卡片：立绘 + 名称 + 描述 +
/// 条目（启用/禁用）+ 开场白数 + 世界书 + 提示。用于工作区中部"预览"区域。
class CardPreview extends StatelessWidget {
  final CardConversionResult? result;

  /// 占位提示（无结果时显示）。
  final String placeholder;

  /// 需要高亮（绿色）的条目 id 集合：用于标记被手动编辑过 / 改动过的条目。
  final Set<String> highlightEntryIds;

  const CardPreview({
    super.key,
    required this.result,
    this.placeholder = '预览',
    this.highlightEntryIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return Center(
        child: Text(
          placeholder,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.black45,
          ),
        ),
      );
    }

    if (!r.success) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text('转译失败：${r.sourceName}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final n in r.notes)
                Text(n.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    final c = r.characterData!;
    final entries = _parseEntries(c['entries_json'] as String? ?? '[]');
    final greetings = _parseList(c['opening_greetings'] as String? ?? '[]');
    final meta = _parseMeta(c['meta_json'] as String? ?? '{}');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 头部：立绘 + 名称 + 来源
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(r.imageBytes),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.characterName,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('来源：${r.format.label}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                  if (r.partial)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('（部分高级字段已降级）',
                          style:
                          TextStyle(fontSize: 12, color: Colors.orange)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _section('简短描述', (c['description'] as String?) ?? ''),

        _label('角色设定条目（${entries.where((e) => e.enabled).length}/${entries.length} 启用）'),
        ...entries.map((e) => _EntryTile(
          entry: e,
          highlighted: highlightEntryIds.contains(e.id),
        )),

        const SizedBox(height: 8),
        _label('开场白：${greetings.length} 条'),

        if (r.worldBooks.isNotEmpty) ...[
          const SizedBox(height: 8),
          _label('内嵌世界书：${r.worldBooks.length} 本'),
          ...r.worldBooks.map((wb) {
            final wbEntries = _parseList(wb['entries_json'] as String? ?? '[]');
            return Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('· ${wb['name']}（${wbEntries.length} 条）',
                  style: const TextStyle(fontSize: 13)),
            );
          }),
        ],

        if (meta.isNotEmpty) ...[
          const SizedBox(height: 12),
          _label('元信息'),
          if ((meta['tags'] as List?)?.isNotEmpty ?? false)
            _kv('标签', (meta['tags'] as List).join('、')),
          if ((meta['creator'] ?? '').toString().isNotEmpty)
            _kv('作者', meta['creator'].toString()),
          if ((meta['character_version'] ?? '').toString().isNotEmpty)
            _kv('版本', meta['character_version'].toString()),
          if ((meta['post_history_instructions'] ?? '').toString().isNotEmpty)
            _kv('历史后指令', '已包含'),
        ],

        if (r.unsupportedFields.isNotEmpty) ...[
          const SizedBox(height: 12),
          _label('未支持 / 已降级'),
          Text(r.unsupportedFields.join('、'),
              style: const TextStyle(fontSize: 12, color: Colors.orange)),
        ],
      ],
    );
  }

  Widget _avatar(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: 96,
        height: 144,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person, size: 48, color: Colors.white70),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        Uint8List.fromList(bytes),
        width: 96,
        height: 144,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          width: 96,
          height: 144,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(title),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(s,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black87)),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 80,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54))),
        Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  List<_Entry> _parseEntries(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) {
        final m = e as Map;
        return _Entry(
          id: m['id']?.toString() ?? '',
          title: m['title']?.toString() ?? '',
          content: m['content']?.toString() ?? '',
          enabled: m['enabled'] == true,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List _parseList(String json) {
    try {
      return jsonDecode(json) as List;
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _parseMeta(String json) {
    try {
      final m = jsonDecode(json);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return {};
  }
}

class _Entry {
  final String id;
  final String title;
  final String content;
  final bool enabled;
  _Entry({
    required this.id,
    required this.title,
    required this.content,
    required this.enabled,
  });

  /// 条目内容单行预览（收起态）：固定条目把 JSON 子字段拼成可读文本。
  String get previewContent {
    final raw = content.trim();
    if (raw.isEmpty) return '（空）';
    if (raw.startsWith('{')) {
      final fields = subFields;
      if (fields.isEmpty) return '（空）';
      final joined = fields.map((e) => e.value).join('；');
      return joined.length > 60 ? '${joined.substring(0, 60)}…' : joined;
    }
    return raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
  }

  /// 是否为结构化（JSON 子字段）条目。
  bool get isStructured => content.trim().startsWith('{');

  /// 结构化条目的子字段（标签 + 值），只含非空值。
  List<MapEntry<String, String>> get subFields {
    final raw = content.trim();
    if (!raw.startsWith('{')) return const [];
    try {
      final m = jsonDecode(raw) as Map;
      return m.entries
          .map((e) => MapEntry(_fieldLabel(e.key.toString()),
          (e.value ?? '').toString().trim()))
          .where((e) => e.value.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 纯文本条目的全文。
  String get fullText {
    final raw = content.trim();
    return raw.isEmpty ? '（空）' : raw;
  }

  static String _fieldLabel(String key) {
    const map = {
      'last_name': '姓',
      'first_name': '名',
      'other': '其他',
      'race': '种族',
      'gender': '性别',
      'age': '年龄',
      'height': '身高',
      'weight': '体重',
      'measurements': '三围',
      'personality': '性格',
      'thoughts': '思想',
      'interests': '兴趣',
      'origin': '出身背景',
      'experiences': '经历事件',
      'current': '当前背景',
      // 系统卡子字段
      'world_setting': '世界设定',
      'worldview': '世界观',
      'system_mechanism': '系统机制',
      'cause': '起因',
      'events': '事件',
      'goal': '目标',
      'possible_endings': '可能结局',
      'name': '名称',
      'detail': '详细设定',
      'body': '身体',
      'background': '背景',
    };
    return map[key] ?? key;
  }
}

/// 可展开的条目行：收起显示单行摘要，点击展开看全文/子字段。
class _EntryTile extends StatefulWidget {
  final _Entry entry;
  final bool highlighted;
  const _EntryTile({required this.entry, this.highlighted = false});

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: widget.highlighted
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: widget.highlighted
              ? Border.all(color: Colors.green.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              e.enabled ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: e.enabled ? Colors.green : Colors.black26,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _expanded ? _expandedView(e) : _collapsedView(e),
            ),
            if (widget.highlighted)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.edit, size: 13, color: Colors.green),
              ),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                size: 16, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _collapsedView(_Entry e) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        children: [
          TextSpan(
              text: '${e.title}：',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: e.previewContent),
        ],
      ),
    );
  }

  Widget _expandedView(_Entry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (e.isStructured)
          ...e.subFields.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 2),
            child: RichText(
              text: TextSpan(
                style:
                const TextStyle(fontSize: 12, color: Colors.black87),
                children: [
                  TextSpan(
                      text: '${f.key}：',
                      style: const TextStyle(color: Colors.black54)),
                  TextSpan(text: f.value),
                ],
              ),
            ),
          ))
        else
          SelectableText(e.fullText,
              style: const TextStyle(fontSize: 12, height: 1.45)),
        if (e.isStructured && e.subFields.isEmpty)
          const Text('（空）',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
      ],
    );
  }
}
