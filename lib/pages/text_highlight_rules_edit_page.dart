import 'package:flutter/material.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

/// 文本着色规则编辑页。
///
/// 作者用正则描述「哪些片段要变色」，即时预览效果。
/// 只影响显示，不改写文本内容——发给 LLM 与存库的始终是原文。
class TextHighlightRulesEditPage extends StatefulWidget {
  final List<TextHighlightRule> rules;

  const TextHighlightRulesEditPage({super.key, required this.rules});

  @override
  State<TextHighlightRulesEditPage> createState() =>
      _TextHighlightRulesEditPageState();
}

class _TextHighlightRulesEditPageState
    extends State<TextHighlightRulesEditPage> {
  late List<TextHighlightRule> _rules;
  late final TextEditingController _previewController;

  /// 预览样例：刻意把四种默认规则都用上，作者一进来就能看出规则在干什么。
  static const String _defaultPreview =
      '她合上《星雾志》，（心里默数了三下），才抬起头。\n'
      '“你确定要走这条路？”\n'
      '【系统提示】前方区域危险度 +30。';

  @override
  void initState() {
    super.initState();
    // 空表示「没配过」，此时把内置默认铺出来给作者当起点，
    // 比丢一个空列表让人猜格式友好得多。
    _rules = (widget.rules.isEmpty
            ? TextHighlightRule.defaults()
            : widget.rules)
        .map((r) => r.copyWith())
        .toList();
    _previewController = TextEditingController(text: _defaultPreview);
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  void _addRule() {
    setState(() {
      _rules.add(const TextHighlightRule(
        name: '新规则',
        regex: '',
        colorValue: 0xFF3949AB,
      ));
    });
  }

  Future<void> _pickColor(int index) async {
    // 取色盘用固定色板而非取色器：着色是为了区分语义，
    // 十来种高辨识度的颜色足够，全色域反而让作者挑出一堆相近色。
    const palette = <int>[
      0xFF000000, 0xFF6A5A78, 0xFF4E6FAE, 0xFFB8632A,
      0xFFC62828, 0xFF2E7D32, 0xFF00838F, 0xFF6A1B9A,
      0xFFE8833A, 0xFF546E7A, 0xFFAD1457, 0xFF827717,
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in palette)
                InkWell(
                  onTap: () => Navigator.pop(ctx, c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(c),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('沿用正文颜色'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _rules[index] = picked == -1
          ? _rules[index].copyWith(clearColor: true)
          : _rules[index].copyWith(colorValue: picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文本着色'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _rules = TextHighlightRule.defaults()),
            child: const Text('恢复默认'),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            // 名称留空不拦截（只是标签），但正则非法的条目会被静默跳过，
            // 所以在列表里就用红字提示，这里不再二次拦截。
            onPressed: () => Navigator.pop(context, _rules),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          const Text(
            '用正则表达式匹配文本片段并着色。规则按从上到下的顺序生效，'
            '靠前的先占位，后面的规则不会覆盖已着色的部分。\n'
            '着色只影响显示，不会改写内容——发给模型和存档的始终是原文。',
            style: TextStyle(fontSize: 12, color: Color(0xFF777783), height: 1.4),
          ),
          const SizedBox(height: 14),
          _buildPreview(),
          const SizedBox(height: 16),
          for (var i = 0; i < _rules.length; i++) _buildRuleCard(i),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add),
            label: const Text('添加规则'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    const baseStyle = TextStyle(
      fontSize: 14,
      height: 1.5,
      color: Colors.black87,
      decoration: TextDecoration.none,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('预览',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _previewController,
            maxLines: 4,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '在这里粘一段实际文本试试',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text.rich(
              TextHighlightEngine.buildSpan(
                _previewController.text,
                _rules,
                baseStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(int index) {
    final rule = _rules[index];
    final invalid = rule.regex.trim().isNotEmpty && !rule.isValid;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: rule.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '规则名（仅自己看）',
                    ),
                    onChanged: (v) => setState(
                        () => _rules[index] = rule.copyWith(name: v)),
                  ),
                ),
                Switch(
                  value: rule.enabled,
                  onChanged: (v) => setState(
                      () => _rules[index] = rule.copyWith(enabled: v)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => _rules.removeAt(index)),
                ),
              ],
            ),
            TextFormField(
              initialValue: rule.regex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: '正则表达式',
                errorText: invalid ? '正则语法有误，这条规则不会生效' : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  setState(() => _rules[index] = rule.copyWith(regex: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                InkWell(
                  onTap: () => _pickColor(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: rule.colorValue == null
                          ? Colors.transparent
                          : Color(rule.colorValue!),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black26),
                    ),
                    child: rule.colorValue == null
                        ? const Icon(Icons.format_color_reset, size: 16)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('加粗'),
                  selected: rule.bold,
                  onSelected: (v) => setState(
                      () => _rules[index] = rule.copyWith(bold: v)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('斜体'),
                  selected: rule.italic,
                  onSelected: (v) => setState(
                      () => _rules[index] = rule.copyWith(italic: v)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: '上移（提高优先级）',
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                            final r = _rules.removeAt(index);
                            _rules.insert(index - 1, r);
                          }),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: '下移',
                  onPressed: index == _rules.length - 1
                      ? null
                      : () => setState(() {
                            final r = _rules.removeAt(index);
                            _rules.insert(index + 1, r);
                          }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
