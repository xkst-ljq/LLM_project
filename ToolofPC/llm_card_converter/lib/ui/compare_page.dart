import 'package:flutter/material.dart';

import '../pipeline/pipeline.dart';
import 'card_preview.dart';

/// 比对页（独占一页，只读）：横向并排展示
///   原文 → 规则转译 → AI 智能归类 → 成品
/// 四个版本，供用户核对每一步的变化与信息忠实度。
class ComparePage extends StatelessWidget {
  final CardWorkItem item;
  const ComparePage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final rule = item.stageOutputs[PipelineStage.rule];
    final ai = item.stageOutputs[PipelineStage.aiClassify];
    final current = item.current;

    final cols = <_Col>[
      _Col('原文', '酒馆原始字段', Colors.blueGrey,
          _OriginalView(sourceJson: item.sourceJson)),
    ];
    if (rule != null) {
      cols.add(_Col('规则转译', '第一步 · 字段映射', Colors.indigo,
          CardPreview(result: rule)));
    }
    if (ai != null) {
      cols.add(_Col('AI 智能归类', '第二步 · 拆分归位', Colors.deepPurple,
          CardPreview(result: ai)));
    }
    // 成品：最终交付版（含手动编辑）。若与 AI/规则同一对象则仍单列展示，方便对照。
    if (current != null) {
      cols.add(_Col('成品', '最终交付版本', Colors.teal,
          CardPreview(result: current)));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('版本比对（只读）'),
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: LayoutBuilder(
        builder: (context, constraints) {
          const minColWidth = 330.0;
          final totalMin = minColWidth * cols.length;
          final fit = totalMin <= constraints.maxWidth;
          final colWidth =
          fit ? constraints.maxWidth / cols.length : minColWidth;

          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in cols)
                SizedBox(width: colWidth, child: _columnCard(context, c)),
            ],
          );

          return fit
              ? row
              : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: totalMin, child: row),
          );
        },
      ),
    );
  }

  Widget _columnCard(BuildContext context, _Col c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: c.color.withValues(alpha: 0.10),
              child: Row(
                children: [
                  Container(width: 4, height: 30, color: c.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: c.color)),
                        Text(c.subtitle,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: c.child),
          ],
        ),
      ),
    );
  }
}

class _Col {
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;
  _Col(this.title, this.subtitle, this.color, this.child);
}

/// 原文列：把酒馆原始字段做成与右侧一致的卡片观感；
/// 开场白、内嵌世界书默认折叠（点开查看），与后面列对齐。
class _OriginalView extends StatelessWidget {
  final Map<String, dynamic>? sourceJson;
  const _OriginalView({required this.sourceJson});

  @override
  Widget build(BuildContext context) {
    final json = sourceJson;
    if (json == null) {
      return const Center(
        child: Text('无原始数据', style: TextStyle(color: Colors.black45)),
      );
    }
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    String s(String k) => (data[k] ?? '').toString().trim();
    List<String> list(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
      return const [];
    }

    final children = <Widget>[];

    void field(String label, String value) {
      if (value.trim().isEmpty) return;
      children.add(_FieldBlock(label: label, content: value));
    }

    field('名称', s('name'));
    field('描述', s('description'));
    field('性格', s('personality'));
    field('场景', s('scenario'));
    field('系统提示', s('system_prompt'));
    field('历史后指令', s('post_history_instructions'));

    // 开场白（折叠）
    final greetings = <String>[];
    if (s('first_mes').isNotEmpty) greetings.add(s('first_mes'));
    greetings.addAll(list(data['alternate_greetings']));
    if (greetings.isNotEmpty) {
      children.add(_CollapsibleBlock(
        label: '开场白（${greetings.length}）',
        items: [
          for (var i = 0; i < greetings.length; i++)
            _SubItem('开场白 ${i + 1}', greetings[i]),
        ],
      ));
    }

    // 示例对话（折叠，可能很长）
    if (s('mes_example').isNotEmpty) {
      children.add(_CollapsibleBlock(
        label: '示例对话',
        items: [_SubItem('mes_example', s('mes_example'))],
      ));
    }

    // 内嵌世界书（折叠）
    final book = data['character_book'];
    if (book is Map) {
      final entries = book['entries'];
      if (entries is List && entries.isNotEmpty) {
        children.add(_CollapsibleBlock(
          label: '内嵌世界书（${entries.length}）',
          items: [
            for (var i = 0; i < entries.length; i++)
              if (entries[i] is Map)
                _SubItem(
                      () {
                    final keys = list((entries[i] as Map)['keys']);
                    return '条目 ${i + 1}${keys.isNotEmpty ? '（${keys.join('/')}）' : ''}';
                  }(),
                  ((entries[i] as Map)['content'] ?? '').toString(),
                ),
          ],
        ));
      }
    }

    // 元信息（折叠）
    final meta = <_SubItem>[];
    if (s('creator').isNotEmpty) meta.add(_SubItem('作者', s('creator')));
    if (s('character_version').isNotEmpty) {
      meta.add(_SubItem('版本', s('character_version')));
    }
    final tags = list(data['tags']);
    if (tags.isNotEmpty) meta.add(_SubItem('标签', tags.join('、')));
    final cn = s('creator_notes').isNotEmpty
        ? s('creator_notes')
        : s('creator comment');
    if (cn.isNotEmpty) meta.add(_SubItem('作者备注', cn));
    if (meta.isNotEmpty) {
      children.add(_CollapsibleBlock(label: '元信息', items: meta));
    }

    if (children.isEmpty) {
      return const Center(
        child: Text('原始字段为空', style: TextStyle(color: Colors.black45)),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

/// 普通字段块（标题 + 内容，常驻展示）。
class _FieldBlock extends StatelessWidget {
  final String label;
  final String content;
  const _FieldBlock({required this.label, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 3),
          SelectableText(content,
              style: const TextStyle(fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }
}

class _SubItem {
  final String title;
  final String content;
  _SubItem(this.title, this.content);
}

/// 可折叠块（开场白 / 世界书 / 元信息）：点击展开/收起。
class _CollapsibleBlock extends StatefulWidget {
  final String label;
  final List<_SubItem> items;
  const _CollapsibleBlock({required this.label, required this.items});

  @override
  State<_CollapsibleBlock> createState() => _CollapsibleBlockState();
}

class _CollapsibleBlockState extends State<_CollapsibleBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(widget.label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                ],
              ),
            ),
          ),
          if (_open)
            ...widget.items.map((it) => Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 2),
                  SelectableText(it.content,
                      style: const TextStyle(fontSize: 12, height: 1.45)),
                ],
              ),
            )),
        ],
      ),
    );
  }
}
