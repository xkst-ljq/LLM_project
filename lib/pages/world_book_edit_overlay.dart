import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/world_book.dart';
import '../models/world_book_entry.dart';
import '../services/database_service.dart';
import '../utils/id_utils.dart';

class WorldBookEditOverlay extends StatefulWidget {
  final WorldBook worldBook;
  final Rect? cardRect;
  const WorldBookEditOverlay({super.key, required this.worldBook, this.cardRect});

  @override
  State<WorldBookEditOverlay> createState() => _WorldBookEditOverlayState();
}

class _WorldBookEditOverlayState extends State<WorldBookEditOverlay>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late List<WorldBookEntry> _entries;

  // 动画相关
  late AnimationController _animController;
  Animation<Rect?>? _rectAnimation;

  bool _editingName = false;
  bool _editingDesc = false;
  bool _showNameError = false;
  String _nameErrorText = '';
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.worldBook.name);
    _descCtrl = TextEditingController(text: widget.worldBook.description);
    // 用 copyWith 复制，避免漏带高级触发字段
    // （keys / secondaryKeys / enabled / insertionOrder / position）。
    _entries = widget.worldBook.entries.map((e) => e.copyWith()).toList();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rectAnimation != null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final targetWidth = screenWidth * 0.9;
    final targetHeight = screenHeight * 0.8;
    final targetRect = Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: targetWidth,
      height: targetHeight,
    );
    // 无 cardRect 时从中心零尺寸弹出
    final beginRect = widget.cardRect ?? Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: 0,
      height: 0,
    );
    _rectAnimation = RectTween(begin: beginRect, end: targetRect).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _closeWithAnimation() async {
    if (_isClosing || !mounted) return;

    _isClosing = true;
    FocusScope.of(context).unfocus();

    Navigator.pop(context);
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    final all = await DatabaseService.getAllWorldBooks();
    final existingNames = all
        .where((wb) => wb['id'] != widget.worldBook.id)
        .map((wb) => wb['name'] as String)
        .toSet();
    if (existingNames.contains(newName)) {
      setState(() {
        _nameErrorText = '世界书名称"$newName"已存在，请换一个名字。';
        _showNameError = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showNameError = false);
      });
      return;
    }

    await DatabaseService.updateWorldBook({
      'id': widget.worldBook.id,
      'name': newName,
      'description': _descCtrl.text.trim(),
      'entries_json': jsonEncode(_entries.map((e) => e.toJson()).toList()),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      await _closeWithAnimation();
    }
  }

  void _addEntry() {
    final newEntry = WorldBookEntry(
      id: IdUtils.timestampId(),
      title: '新条目 ${_entries.length + 1}',
      sortOrder: _entries.length,
    );
    setState(() => _entries.add(newEntry));
  }

  void _editEntry(WorldBookEntry entry) async {
    final result = await Navigator.push<WorldBookEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => _EntryEditPage(entry: entry),
      ),
    );
    if (result != null) {
      setState(() {
        final index = _entries.indexWhere((e) => e.id == result.id);
        if (index != -1) _entries[index] = result;
      });
    }
  }

  void _deleteEntry(WorldBookEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除条目“${entry.title}”吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _entries.removeWhere((e) => e.id == entry.id));
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_rectAnimation == null) return const SizedBox.shrink();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeWithAnimation();
      },
      child: AnimatedOpacity(
        opacity: _isClosing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Stack(
          children: [
            // 半透明背景（点击关闭）
            GestureDetector(
              onTap: _closeWithAnimation,
              child: const SizedBox.expand(),
            ),
            // 带动画的编辑窗口
            AnimatedBuilder(
              animation: _rectAnimation!,
              builder: (context, child) {
                final rect = _rectAnimation!.value!;
                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: GestureDetector(
                    onTap: () {}, // 阻止点击穿透
                    child: Material(
                      borderRadius: BorderRadius.circular(20),
                      elevation: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 名称行
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('世界书名称', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        if (_showNameError)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withAlpha(25),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(_nameErrorText, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                            ),
                                          ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => setState(() => _editingName = !_editingName),
                                          child: Icon(_editingName ? Icons.check : Icons.edit, size: 16, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _editingName
                                        ? TextField(
                                      controller: _nameCtrl,
                                      autofocus: true,
                                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                                    )
                                        : Center(
                                      child: Text(
                                        _nameCtrl.text.isEmpty ? '未命名' : _nameCtrl.text,
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 描述行
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('简短描述', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => setState(() => _editingDesc = !_editingDesc),
                                          child: Icon(_editingDesc ? Icons.check : Icons.edit, size: 16, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _editingDesc
                                        ? TextField(
                                      controller: _descCtrl,
                                      autofocus: true,
                                      maxLines: 2,
                                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                                    )
                                        : Center(
                                      child: Text(
                                        _descCtrl.text.isEmpty ? '暂无描述' : _descCtrl.text,
                                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 条目列表标题
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('设定条目', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle, color: Colors.blue),
                                          onPressed: _addEntry,
                                          tooltip: '添加条目',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // 条目列表
                                    if (_entries.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text('暂无条目，点击 + 添加', style: TextStyle(color: Colors.grey)),
                                      )
                                    else
                                      ListView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: _entries.length,
                                        itemBuilder: (ctx, i) {
                                          final entry = _entries[i];
                                          return Opacity(
                                            opacity: entry.enabled ? 1.0 : 0.45,
                                            child: Card(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: ListTile(
                                              title: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(entry.title,
                                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                                        overflow: TextOverflow.ellipsis),
                                                  ),
                                                  if (!entry.enabled)
                                                    Container(
                                                      margin: const EdgeInsets.only(left: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade300,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text('已停用',
                                                          style: TextStyle(fontSize: 10, color: Colors.black54)),
                                                    ),
                                                ],
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (entry.hasKeys)
                                                    Padding(
                                                      padding: const EdgeInsets.only(bottom: 4),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          entry.keywordDisplay,
                                                          style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
                                                        ),
                                                      ),
                                                    ),
                                                  Text(
                                                    entry.content.isEmpty ? '无内容' : entry.content,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                                onPressed: () => _deleteEntry(entry),
                                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                padding: EdgeInsets.zero,
                                              ),
                                              onTap: () => _editEntry(entry),
                                            ),
                                          ),
                                          );
                                        },
                                      ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(onPressed: _save, child: const Text('保存')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 条目全屏编辑页 ==========

class _EntryEditPage extends StatefulWidget {
  final WorldBookEntry entry;
  const _EntryEditPage({required this.entry});

  @override
  State<_EntryEditPage> createState() => _EntryEditPageState();
}

class _EntryEditPageState extends State<_EntryEditPage> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _keywordCtrl;
  late TextEditingController _secondaryCtrl;
  late TextEditingController _orderCtrl;
  late bool _enabled;
  late bool _alwaysActive;
  late bool _recursive;
  late String _position;

  bool get _isClosing => false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry.title);
    _contentCtrl = TextEditingController(text: widget.entry.content);
    _keywordCtrl = TextEditingController(text: widget.entry.keywordDisplay);
    _secondaryCtrl =
        TextEditingController(text: widget.entry.secondaryKeys.join('，'));
    _orderCtrl =
        TextEditingController(text: widget.entry.insertionOrder.toString());
    _enabled = widget.entry.enabled;
    _alwaysActive = widget.entry.alwaysActive;
    _recursive = widget.entry.recursive;
    _position = widget.entry.position == 'after_char'
        ? 'after_char'
        : 'before_char';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _keywordCtrl.dispose();
    _secondaryCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final order = int.tryParse(_orderCtrl.text.trim()) ??
        widget.entry.insertionOrder;
    final updated = widget.entry.copyWith(
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      keys: WorldBookEntry.splitKeys(_keywordCtrl.text),
      secondaryKeys: WorldBookEntry.splitKeys(_secondaryCtrl.text),
      insertionOrder: order,
      position: _position,
      enabled: _enabled,
      alwaysActive: _alwaysActive,
      recursive: _recursive,
    );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑条目'),
        actions: [
          TextButton(
            onPressed: _isClosing ? null : _save,
            child: const Text('保存'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '条目名称',
                hintText: '如：魔法体系、种族设定',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keywordCtrl,
              decoration: const InputDecoration(
                labelText: '触发关键词（可选，多个用逗号分隔）',
                hintText: '对话中提到任一关键词时自动注入此条目',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secondaryCtrl,
              decoration: const InputDecoration(
                labelText: '次要关键词（可选，多个用逗号分隔）',
                hintText: '保留自第三方卡的次关键词，暂作普通关键词处理',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('启用条目',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            const Text(
              '关闭后此条目不会注入对话（导入的第三方卡中作者关闭的条目默认在此关闭）。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('永久激活'),
                const Spacer(),
                Switch(
                  value: _alwaysActive,
                  onChanged: (v) => setState(() => _alwaysActive = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('允许递归触发'),
                const Spacer(),
                Switch(
                  value: _recursive,
                  onChanged: (v) => setState(() => _recursive = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 注入位置
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('注入位置'),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'before_char',
                    label: Text('角色设定前'),
                  ),
                  ButtonSegment(
                    value: 'after_char',
                    label: Text('角色设定后'),
                  ),
                ],
                selected: {_position},
                onSelectionChanged: (s) =>
                    setState(() => _position = s.first),
              ),
            ),
            const SizedBox(height: 12),
            // 注入优先级
            TextField(
              controller: _orderCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '注入优先级',
                hintText: '数值越小越靠前，多条命中时靠前的更受重视（默认 0）',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '条目内容',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}