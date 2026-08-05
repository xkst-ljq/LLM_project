import 'package:flutter/material.dart';

import '../core/ai_ui_blueprint.dart';

/// 蓝图确认对话框：把 AI 产出的分条目 UI 蓝图逐条展示，供用户确认/修改。
///
/// 用户可：
/// - 逐条勾选保留/删除（keep）；
/// - 修改某条的 title / intent；
/// - 确认（返回修改后的蓝图）或取消（返回 null → 回退确定性模板）。
class BlueprintConfirmDialog extends StatefulWidget {
  final UiBlueprint blueprint;
  const BlueprintConfirmDialog({super.key, required this.blueprint});

  @override
  State<BlueprintConfirmDialog> createState() => _BlueprintConfirmDialogState();
}

class _BlueprintConfirmDialogState extends State<BlueprintConfirmDialog> {
  late List<BlueprintItem> _items;
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

  void _sync() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('确认 UI 蓝图 · ${widget.blueprint.cardName}'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: _items.isEmpty
            ? const Center(child: Text('蓝图为空，将不生成 UI。'))
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final it = _items[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: it.keep,
                          onChanged: (v) {
                            setState(() => it.keep = v ?? true);
                          },
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${it.index} [${it.kind}]',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: it.keep
                                          ? Colors.black54
                                          : Colors.black26)),
                              const SizedBox(height: 2),
                              TextField(
                                controller: _titleCtrls[it.index],
                                enabled: it.keep,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '标题',
                                ),
                                onChanged: (_) =>
                                    it.title = _titleCtrls[it.index]!.text,
                              ),
                              if (it.fields.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('字段: ${it.fields.join(', ')}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: it.keep
                                              ? Colors.black45
                                              : Colors.black26)),
                                ),
                              TextField(
                                controller: _intentCtrls[it.index],
                                enabled: it.keep,
                                minLines: 1,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '设计意图…',
                                ),
                                onChanged: (_) =>
                                    it.intent = _intentCtrls[it.index]!.text,
                              ),
                              if (it.relationship.isNotEmpty)
                                Text('关系: ${it.relationship}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: it.keep
                                            ? Colors.black38
                                            : Colors.black26)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
          child: Text('确认（保留 ${_items.where((i) => i.keep).length} 条）'),
        ),
      ],
    );
  }
}
