import 'package:flutter/material.dart';

import '../core/ai_ui_blueprint.dart';

/// 蓝图确认对话框：把 AI 产出的 UI 蓝图**整体**展示，供用户确认。
///
/// 分两个视图：
/// - **概览**：以 `1. 2. 3.` 编号列出整体蓝图（只读），一目了然；
/// - **编辑**：点「编辑蓝图」进入逐条编辑（可删条目、改标题/意图）。
///
/// 确认返回修改后的蓝图；取消返回 null → 回退确定性模板。
class BlueprintConfirmDialog extends StatefulWidget {
  final UiBlueprint blueprint;
  const BlueprintConfirmDialog({super.key, required this.blueprint});

  @override
  State<BlueprintConfirmDialog> createState() => _BlueprintConfirmDialogState();
}

class _BlueprintConfirmDialogState extends State<BlueprintConfirmDialog> {
  late List<BlueprintItem> _items;
  bool _editing = false;
  late final Map<int, TextEditingController> _titleCtrls;
  late final Map<int, TextEditingController> _intentCtrls;

  @override
  void initState() {
    super.initState();
    _items = widget.blueprint.items.map((i) => i).toList();
    _titleCtrls = {
      for (final i in _items) i.index: TextEditingController(text: i.title),
    };
    _intentCtrls = {
      for (final i in _items) i.index: TextEditingController(text: i.intent),
    };
  }

  @override
  void dispose() {
    for (final c in _titleCtrls.values) {
      c.dispose();
    }
    for (final c in _intentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleEditing() {
    // 进入编辑前把 controller 同步为当前 items 的值
    if (!_editing) {
      for (final it in _items) {
        _titleCtrls[it.index]?.text = it.title;
        _intentCtrls[it.index]?.text = it.intent;
      }
    }
    setState(() => _editing = !_editing);
  }

  void _deleteItem(int idx) {
    setState(() => _items.removeAt(idx));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(_editing ? '编辑 UI 蓝图 · ${widget.blueprint.cardName}'
                : '确认 UI 蓝图 · ${widget.blueprint.cardName}'),
          ),
          IconButton(
            tooltip: _editing ? '完成编辑' : '编辑蓝图',
            icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            onPressed: _toggleEditing,
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 460,
        child: _items.isEmpty
            ? const Center(child: Text('蓝图为空，将不生成 UI。'))
            : _editing ? _buildEditor() : _buildOverview(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消（回退模板）'),
        ),
        FilledButton(
          onPressed: () {
            final kept = _items.where((i) => i.keep).toList();
            Navigator.pop(
              context,
              UiBlueprint(
                cardName: widget.blueprint.cardName,
                items: kept,
                reasoning: widget.blueprint.reasoning,
              ),
            );
          },
          child: Text('确认（${_items.where((i) => i.keep).length} 项）'),
        ),
      ],
    );
  }

  /// 概览视图：编号列出整体蓝图（只读）。
  Widget _buildOverview() {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final it = _items[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 编号
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text('${idx + 1}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('[${it.kind}]',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45)),
                    const SizedBox(height: 4),
                    Text(it.intent,
                        style: const TextStyle(fontSize: 12, height: 1.4)),
                    if (it.fields.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('字段: ${it.fields.join(', ')}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45)),
                      ),
                    if (it.relationship.isNotEmpty)
                      Text('关系: ${it.relationship}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 编辑视图：逐条可删、可改标题/意图。
  Widget _buildEditor() {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final it = _items[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '删除这条',
                icon: const Icon(Icons.delete_outline, size: 18,
                    color: Colors.redAccent),
                onPressed: () => _deleteItem(idx),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${idx + 1}. [${it.kind}]',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _titleCtrls[it.index],
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '标题',
                      ),
                      onChanged: (_) => it.title = _titleCtrls[it.index]!.text,
                    ),
                    TextField(
                      controller: _intentCtrls[it.index],
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '设计意图…',
                      ),
                      onChanged: (_) => it.intent = _intentCtrls[it.index]!.text,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
