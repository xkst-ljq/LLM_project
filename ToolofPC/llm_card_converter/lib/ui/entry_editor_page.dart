import 'dart:convert';

import 'package:flutter/material.dart';

/// 条目手动编辑页。
///
/// 传入 entries_json，用户编辑后返回 (新的 entries_json, 改动过的条目 id 集合)。
/// 结构化条目（content 是 JSON 子字段）按子字段编辑；纯文本条目整段编辑。
class EntryEditorPage extends StatefulWidget {
  final String entriesJson;
  const EntryEditorPage({super.key, required this.entriesJson});

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EditableEntry {
  final String id;
  String title;
  final bool isStructured;

  /// 结构化：子字段 key -> controller；纯文本：仅用 [textCtrl]。
  final Map<String, TextEditingController> fieldCtrls;
  final TextEditingController? textCtrl;
  bool enabled;

  /// 原始内容快照，用于判断是否被改动。
  final String original;

  _EditableEntry({
    required this.id,
    required this.title,
    required this.isStructured,
    required this.fieldCtrls,
    required this.textCtrl,
    required this.enabled,
    required this.original,
  });
}

const Map<String, String> _fieldLabels = {
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
};

class _EntryEditorPageState extends State<EntryEditorPage> {
  final List<_EditableEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final list = jsonDecode(widget.entriesJson) as List;
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m['id']?.toString() ?? '';
        final title = m['title']?.toString() ?? '';
        final content = m['content']?.toString() ?? '';
        final enabled = m['enabled'] == true;
        final structured = content.trim().startsWith('{');

        if (structured) {
          final fields = <String, TextEditingController>{};
          try {
            final obj = jsonDecode(content) as Map;
            for (final entry in obj.entries) {
              fields[entry.key.toString()] = TextEditingController(
                  text: (entry.value ?? '').toString());
            }
          } catch (_) {}
          _entries.add(_EditableEntry(
            id: id,
            title: title,
            isStructured: true,
            fieldCtrls: fields,
            textCtrl: null,
            enabled: enabled,
            original: content,
          ));
        } else {
          _entries.add(_EditableEntry(
            id: id,
            title: title,
            isStructured: false,
            fieldCtrls: {},
            textCtrl: TextEditingController(text: content),
            enabled: enabled,
            original: content,
          ));
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.textCtrl?.dispose();
      for (final c in e.fieldCtrls.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _currentContent(_EditableEntry e) {
    if (e.isStructured) {
      final obj = <String, dynamic>{};
      for (final entry in e.fieldCtrls.entries) {
        obj[entry.key] = entry.value.text;
      }
      return jsonEncode(obj);
    }
    return e.textCtrl?.text ?? '';
  }

  void _save() {
    final out = <Map<String, dynamic>>[];
    final changed = <String>{};
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      final content = _currentContent(e);
      if (content != e.original) changed.add(e.id);
      out.add({
        'id': e.id,
        'title': e.title,
        'content': content,
        'enabled': e.enabled,
        'is_custom': !_isFixed(e.id),
        'sort_order': i,
      });
    }
    Navigator.pop(context, (jsonEncode(out), changed));
  }

  bool _isFixed(String id) => const {
    'name_entry',
    'relationship',
    'body',
    'psychology',
    'background',
  }.contains(id);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // 侧边面板：占屏幕一半，最宽 640，最窄 360
    final panelWidth = width.clamp(360.0, 1280.0) * 0.5;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 16,
        child: SizedBox(
          width: panelWidth.clamp(360.0, 640.0),
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                // 顶部栏
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('编辑条目',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (context, i) => _entryCard(_entries[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryCard(_EditableEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(e.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            // 启用开关
            Row(
              children: [
                const Text('启用', style: TextStyle(fontSize: 12)),
                Switch(
                  value: e.enabled,
                  onChanged: (v) => setState(() => e.enabled = v),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (e.isStructured)
          ...e.fieldCtrls.entries.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: f.value,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: _fieldLabels[f.key] ?? f.key,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ))
        else
          TextField(
            controller: e.textCtrl,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
      ],
    );
  }
}
