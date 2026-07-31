import 'package:flutter/material.dart';

import '../models/status_bar_field.dart';
import '../services/ui_engine/data_channel_service.dart';

/// 状态栏字段定义编辑页。
///
/// 在此定义角色卡的状态栏字段（名称 / 类型 / 初始值 / 范围 / 常驻 / 排序）。
/// 字段定义随卡片保存；运行时当前值另存于会话副本，清空记录后回到初始值。
class StatusBarFieldsEditPage extends StatefulWidget {
  final List<StatusBarField> fields;

  /// UI 里写了字段名、但角色卡还没有该字段的「预绑定」条目。
  ///
  /// 作者在数据通道里写下「生命值」时，角色卡可能还没这个字段——
  /// 此时通道记为 pendingName 等待创建。他之后来这个页面建字段，
  /// 不该还得自己回忆当时打的是什么名字，所以在这里直接列出来。
  final List<PendingStatusBinding> pendingBindings;

  const StatusBarFieldsEditPage({
    super.key,
    required this.fields,
    this.pendingBindings = const <PendingStatusBinding>[],
  });

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

  /// 自增序号：仅靠时间戳时，连续快速添加会落在同一微秒导致 id 重复，
  /// 而列表用 ValueKey(id) 做 key，重复 key 会让 Flutter 报错或 State 错乱，
  /// 表现为「加不进去字段」。
  int _idSeed = 0;

  String _newId() {
    final existing = _fields.map((f) => f.id).toSet();
    String candidate;
    do {
      candidate = 'sbf_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}';
    } while (existing.contains(candidate));
    return candidate;
  }

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

  /// 尚未被创建的预绑定项。
  ///
  /// 已经建了同名字段的就不再提示——那条预绑定下次打开 UI 组装页时
  /// 会被 `_reconcileStatusChannelBindings` 自动补绑成真实 targetId。
  List<PendingStatusBinding> get _unresolvedBindings {
    final existing = _fields
        .map((f) => f.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    return widget.pendingBindings
        .where((b) => !existing.contains(b.name.trim().toLowerCase()))
        .toList();
  }

  /// 按预绑定创建字段。
  ///
  /// **初始值取 UI 组件当前的值**——这是用户明确的方向：
  /// 状态栏还没有该字段时以 UI 为准，反之（字段已存在）以状态栏为准。
  void _createFromBinding(PendingStatusBinding binding) {
    final value = binding.initialValue.trim();
    setState(() {
      _fields.add(StatusBarField(
        id: _newId(),
        name: binding.name,
        type: binding.isNumber ? 'number' : 'text',
        initialValue: value.isEmpty ? (binding.isNumber ? '0' : '') : value,
        // 数值型给个能容纳初始值的默认量程，免得一建出来就越界。
        minValue: binding.isNumber ? 0 : null,
        maxValue: binding.isNumber
            ? _defaultMaxFor(double.tryParse(value) ?? 0)
            : null,
        pinSide: 'none',
        order: _fields.length,
      ));
    });
  }

  /// 默认上限：至少 100，初始值更大时向上取整到百。
  double _defaultMaxFor(double initial) {
    if (initial <= 100) return 100;
    return (initial / 100).ceil() * 100.0;
  }

  void _deleteField(int i) {
    setState(() => _fields.removeAt(i));
  }

  /// 是否存在「填了内容但没填名称」的字段。
  ///
  /// 这类字段保存时会被丢弃。静默丢弃会让用户以为「存不上」，
  /// 因此保存前要提示。
  bool _hasNamelessFieldWithContent() {
    for (final f in _fields) {
      if (f.name.trim().isNotEmpty) continue;
      if (f.initialValue.trim().isNotEmpty && f.initialValue.trim() != '0') {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (_hasNamelessFieldWithContent()) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('有字段未填名称'),
          content: const Text('未填写名称的字段不会被保存。\n要继续保存并丢弃这些字段吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回填写'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续保存'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;

    // 过滤掉没填名称的字段；重排 order。
    final cleaned = <StatusBarField>[];
    for (final f in _fields) {
      if (f.name.trim().isEmpty) continue;
      cleaned.add(f.copyWith(order: cleaned.length));
    }
    Navigator.pop(context, cleaned);
  }

  /// 编辑内容是否与进入时不同。
  bool get _isDirty {
    final original = widget.fields;
    if (original.length != _fields.length) return true;
    for (var i = 0; i < _fields.length; i++) {
      final a = original[i];
      final b = _fields[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.type != b.type ||
          a.initialValue != b.initialValue ||
          a.minValue != b.minValue ||
          a.maxValue != b.maxValue ||
          a.pinSide != b.pinSide ||
          a.owner != b.owner) {
        return true;
      }
    }
    return false;
  }

  /// 返回键 / 返回箭头退出时的确认。
  ///
  /// 此前直接 pop 会返回 null，父页 `if (result != null)` 不成立，
  /// 于是全部编辑被静默丢弃——这是「改了却没保存上」最常见的原因。
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('你有未保存的修改，直接返回会丢失这些改动。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('去保存'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 拦截返回键 / 返回箭头：直接 pop 会返回 null，
      // 父页据此判定「未修改」，导致全部编辑被静默丢弃。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 先取好 navigator 再 await：await 之后再用 context 会触发
        // use_build_context_synchronously，且此时 context 可能已失效。
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          navigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('状态栏字段'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          // 预绑定提示排在列表之上：作者进这个页面多半就是为了
          // 把 UI 里写下的名字建出来，藏在底部等于没做。
          if (_unresolvedBindings.isNotEmpty) _buildPendingBindingBanner(),
          Expanded(
            child: _fields.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _fields.length,
                    itemBuilder: (ctx, i) => KeyedSubtree(
                      // 没有 key 时，增删字段会让 TextFormField 的 State
                      // 错位复用，输入内容可能串到别的字段上。
                      key: ValueKey(_fields[i].id),
                      child: _buildFieldCard(i),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addField,
        icon: const Icon(Icons.add),
        label: const Text('添加字段'),
      ),
      ),
    );
  }

  /// 预绑定提示条：列出 UI 里已引用、但角色卡还没建的字段名。
  Widget _buildPendingBindingBanner() {
    final items = _unresolvedBindings;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded,
                  size: 17, color: Color(0xFFE65100)),
              const SizedBox(width: 6),
              Text(
                '界面里引用了 ${items.length} 个还未创建的字段',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '点击即可按界面组件的当前值创建。创建后回到界面组装页会自动完成绑定。',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8D6E63),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final b in items)
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => _createFromBinding(b),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded,
                              size: 15, color: Color(0xFFE65100)),
                          const SizedBox(width: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                b.name,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5D4037),
                                ),
                              ),
                              Text(
                                [
                                  b.isNumber ? '数值' : '文本',
                                  if (b.initialValue.isNotEmpty)
                                    '初始 ${b.initialValue}',
                                  if (b.sourceComponent.isNotEmpty)
                                    b.sourceComponent,
                                ].join(' · '),
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: Color(0xFFA1887F),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
                    // 一律基于 _fields[i] 的最新对象改写，不要用闭包捕获的 f：
                    // f 是本次 build 时的旧引用，其他输入框改过之后就过期了。
                    onChanged: (v) => _fields[i] = _fields[i].copyWith(name: v),
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
            // 归属：决定 Prompt 里的主语，直接影响 LLM 判断增减方向。
            Row(
              children: [
                const Text('归属'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: f.owner,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: 'player', child: Text('玩家的属性')),
                      DropdownMenuItem(
                          value: 'char', child: Text('角色自己的属性')),
                      DropdownMenuItem(
                          value: 'neutral', child: Text('中立 / 环境')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(
                          () => _fields[i] = _fields[i].copyWith(owner: v));
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '注入 Prompt 时会带上主语（如「玩家的金钱」），'
                '帮助 AI 判断该加还是该减。',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
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
              onChanged: (v) =>
                  _fields[i] = _fields[i].copyWith(initialValue: v),
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
                      onChanged: (v) => _fields[i] = _fields[i].copyWith(
                            minValue: double.tryParse(v.trim()),
                            clearMinValue: v.trim().isEmpty,
                          ),
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
                      onChanged: (v) => _fields[i] = _fields[i].copyWith(
                            maxValue: double.tryParse(v.trim()),
                            clearMaxValue: v.trim().isEmpty,
                          ),
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
