import 'package:flutter/material.dart';

import '../models/status_bar_field.dart';

/// 状态栏字段定义编辑页。
///
/// 在此定义角色卡的状态栏字段（名称 / 类型 / 初始值 / 范围 / 常驻 / 排序）。
/// 字段定义随卡片保存；运行时当前值另存于会话副本，清空记录后回到初始值。
class StatusBarFieldsEditPage extends StatefulWidget {
  final List<StatusBarField> fields;
  const StatusBarFieldsEditPage({super.key, required this.fields});

  @override
  State<StatusBarFieldsEditPage> createState() =>
      _StatusBarFieldsEditPageState();
}

class _StatusBarFieldsEditPageState extends State<StatusBarFieldsEditPage> {
  late List<StatusBarField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = widget.fields.map((f) => f.copyWith()).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  String _newId() => 'sbf_${DateTime.now().microsecondsSinceEpoch}';

  void _addField() {
    setState(() {
      _fields.add(StatusBarField(
        id: _newId(),
        name: '',
        type: 'number',
        initialValue: '0',
        minValue: 0,
        maxValue: 100,
        pinSide: 'none',
        order: _fields.length,
      ));
    });
  }

  void _deleteField(int i) {
    setState(() => _fields.removeAt(i));
  }

  void _save() {
    // 过滤掉没填名称的字段；重排 order。
    final cleaned = <StatusBarField>[];
    for (final f in _fields) {
      if (f.name.trim().isEmpty) continue;
      cleaned.add(f.copyWith(order: cleaned.length));
    }
    Navigator.pop(context, cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('状态栏字段'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: _fields.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _fields.length,
              itemBuilder: (ctx, i) => _buildFieldCard(i),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addField,
        icon: const Icon(Icons.add),
        label: const Text('添加字段'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '还没有状态栏字段。\n点击下方「添加字段」创建，例如：生命、好感、地点。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard(int i) {
    final f = _fields[i];
    final isNumber = f.isNumber;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: f.name,
                    decoration: const InputDecoration(
                      labelText: '字段名称',
                      hintText: '如：生命、好感、地点',
                      isDense: true,
                    ),
                    onChanged: (v) => _fields[i] = f.copyWith(name: v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteField(i),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 类型
            Row(
              children: [
                const Text('类型'),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'number', label: Text('数值')),
                    ButtonSegment(value: 'text', label: Text('文本')),
                  ],
                  selected: {f.type},
                  onSelectionChanged: (s) =>
                      setState(() => _fields[i] = f.copyWith(type: s.first)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 初始值
            TextFormField(
              initialValue: f.initialValue,
              keyboardType: isNumber
                  ? const TextInputType.numberWithOptions(
                      signed: true, decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: '初始值',
                hintText: isNumber ? '如：80' : '如：监控室',
                isDense: true,
              ),
              onChanged: (v) => _fields[i] = f.copyWith(initialValue: v),
            ),
            if (isNumber) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: f.minValue?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最小值（可空）',
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          _fields[i].minValue = double.tryParse(v.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: f.maxValue?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最大值（可空）',
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          _fields[i].maxValue = double.tryParse(v.trim()),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '提示：是否固定显示在聊天页长条上（左/右），在聊天页展开状态栏后用每个块顶部的小滑块设置。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
