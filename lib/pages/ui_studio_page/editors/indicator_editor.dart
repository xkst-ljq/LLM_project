import 'package:flutter/material.dart';

/// 多态状态指示点规格编辑器
/// 对应 UI 模块类型：UIModuleType.indicator
class IndicatorEditor extends StatefulWidget {
  final Map<String, dynamic> initialProperties;
  final String moduleName;
  final int layerId;
  final Offset initialPosition;
  final VoidCallback onDelete;
  final Function(Map<String, dynamic>) onSave;

  const IndicatorEditor({
    super.key,
    required this.initialProperties,
    required this.moduleName,
    required this.layerId,
    required this.initialPosition,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<IndicatorEditor> createState() => _IndicatorEditorState();
}

class _IndicatorEditorState extends State<IndicatorEditor> {
  late TextEditingController _nameController;
  late TextEditingController _currentValController;
  late Color _defaultColor;
  late bool _defaultGlow;
  late double _dotSize;
  late List<Map<String, dynamic>> _statusRules;

  final List<Color> _swatchColors = const [
    Color(0xFF4CAF50), // 绿色 (安全/正常)
    Color(0xFFEF5350), // 红色 (警报/危险)
    Color(0xFFFFA726), // 橙黄 (警告/注意)
    Color(0xFF29B6F6), // 蓝色 (信息/能量)
    Color(0xFFAB47BC), // 紫色 (特殊/高阶)
    Color(0xFF9E9E9E), // 灰色 (离线/默认)
    Color(0xFF26A69A), // 青色 (防护)
    Color(0xFFEC407A), // 粉红 (情绪)
  ];

  @override
  void initState() {
    super.initState();
    final props = widget.initialProperties;

    _nameController = TextEditingController(text: widget.moduleName);
    _currentValController = TextEditingController(
      text: props['currentValue']?.toString() ?? '',
    );

    final defColorVal = props['defaultColor'] ?? 0xFF9E9E9E;
    _defaultColor = Color(defColorVal is int ? defColorVal : 0xFF9E9E9E);
    _defaultGlow = props['defaultGlow'] == true;
    _dotSize = (props['dotSize'] as num?)?.toDouble().clamp(8.0, 28.0) ?? 14.0;

    final rawRules = props['statusRules'];
    if (rawRules is List && rawRules.isNotEmpty) {
      _statusRules = rawRules.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _statusRules = [
        {
          'matchType': 'exact',
          'matchValue': '正常',
          'color': 0xFF4CAF50,
          'isGlow': true,
          'glowRadius': 12.0,
        },
        {
          'matchType': 'exact',
          'matchValue': '警报',
          'color': 0xFFEF5350,
          'isGlow': true,
          'glowRadius': 14.0,
        },
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentValController.dispose();
    super.dispose();
  }

  void _addRule() {
    setState(() {
      _statusRules.add({
        'matchType': 'exact',
        'matchValue': '状态 ${_statusRules.length + 1}',
        'color': 0xFF29B6F6,
        'isGlow': true,
        'glowRadius': 12.0,
      });
    });
  }

  void _removeRule(int index) {
    setState(() {
      _statusRules.removeAt(index);
    });
  }

  void _save() {
    final newProps = {
      'type': 'indicator',
      'currentValue': _currentValController.text.trim(),
      'name': _nameController.text.trim(),
      'defaultColor': _defaultColor.toARGB32(),
      'defaultGlow': _defaultGlow,
      'dotSize': _dotSize,
      'statusRules': _statusRules,
    };

    widget.onSave(newProps);
    Navigator.of(context).pop();
  }

  void _handleDelete() {
    widget.onDelete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏（R5防溢出：使用 Expanded 与 ellipsis）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lens, color: Color(0xFF4CAF50), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '多态指示点配置 (Indicator)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.moduleName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 实时预览工作台
            _buildLivePreviewBox(),

            // 弹性内容区（R5防溢出）
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHostSection(),
                    const SizedBox(height: 16),
                    _buildAppearanceSection(),
                    const SizedBox(height: 16),
                    _buildRulesSection(),
                  ],
                ),
              ),
            ),

            // 底槽按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _handleDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    label: const Text('删除', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('保存配置', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreviewBox() {
    final currentVal = _currentValController.text.trim();
    Color activeColor = _defaultColor;
    bool activeGlow = _defaultGlow;
    double glowRadius = 12.0;

    for (final rule in _statusRules) {
      final matchType = rule['matchType']?.toString() ?? 'exact';
      bool matched = false;

      if (matchType == 'exact') {
        if (currentVal == (rule['matchValue']?.toString().trim() ?? '')) {
          matched = true;
        }
      } else if (matchType == 'bool') {
        final targetBool = rule['matchValue']?.toString().toLowerCase() == 'true';
        final curBool = currentVal.toLowerCase() == 'true' || currentVal == '1' || currentVal == '开启';
        if (curBool == targetBool && currentVal.isNotEmpty) matched = true;
      } else if (matchType == 'range') {
        final double? curNum = double.tryParse(currentVal);
        final double? targetNum = double.tryParse(rule['matchValNum']?.toString() ?? '');
        final op = rule['matchOp']?.toString() ?? '>';
        if (curNum != null && targetNum != null) {
          if (op == '>' && curNum > targetNum) matched = true;
          if (op == '<' && curNum < targetNum) matched = true;
          if (op == '>=' && curNum >= targetNum) matched = true;
          if (op == '<=' && curNum <= targetNum) matched = true;
          if (op == '==' && curNum == targetNum) matched = true;
        }
      }

      if (matched) {
        activeColor = Color((rule['color'] as int?) ?? activeColor.toARGB32());
        activeGlow = rule['isGlow'] == true;
        glowRadius = (rule['glowRadius'] as num?)?.toDouble() ?? 12.0;
        break;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          const Text('发光信号：', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: activeColor.withValues(alpha: 0.35), width: 1),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: activeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
                boxShadow: activeGlow
                    ? [
                  BoxShadow(color: activeColor.withValues(alpha: 0.7), blurRadius: glowRadius, spreadRadius: 2),
                  BoxShadow(color: activeColor.withValues(alpha: 0.4), blurRadius: glowRadius * 1.5, spreadRadius: 4),
                ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentVal.isEmpty ? '等待源数据...' : '接收: "$currentVal"',
              style: const TextStyle(color: Color(0xFF80CBC4), fontSize: 12, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基本与测试信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模块名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: TextField(
                controller: _currentValController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '测试输入值 (选填)',
                  hintText: '如: 暴雨 / 85 / true',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'L${widget.layerId} 图层 · 坐标(${widget.initialPosition.dx.toInt()}, ${widget.initialPosition.dy.toInt()}) · 36x36 磁吸框',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('圆点规格与默认样式 (兜底状态)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('尺寸:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            ...[10.0, 14.0, 18.0, 22.0].map((size) {
              final active = _dotSize == size;
              return ChoiceChip(
                label: Text('${size.toInt()}px', style: const TextStyle(fontSize: 11)),
                selected: active,
                onSelected: (val) {
                  if (val) setState(() => _dotSize = size);
                },
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('未命中光晕:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const Spacer(),
            Switch(
              value: _defaultGlow,
              onChanged: (v) => setState(() => _defaultGlow = v),
              activeThumbColor: _defaultColor,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('兜底底色:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _swatchColors.map((col) {
                  final sel = col.toARGB32() == _defaultColor.toARGB32();
                  return GestureDetector(
                    onTap: () => setState(() => _defaultColor = col),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: sel ? Border.all(color: Colors.black, width: 2) : null,
                        boxShadow: sel ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 4)] : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('多态映射引擎 (优先级由上到下)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${_statusRules.length} 条规则', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              ..._statusRules.asMap().entries.map((entry) {
                final idx = entry.key;
                final rule = entry.value;
                final matchType = rule['matchType']?.toString() ?? 'exact';
                final colorVal = (rule['color'] as int?) ?? 0xFF4CAF50;
                final ruleColor = Color(colorVal);
                final isGlow = rule['isGlow'] == true;

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: idx.isEven ? Colors.white : Colors.grey[50],
                    border: idx > 0 ? Border(top: BorderSide(color: Colors.grey.shade200)) : null,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle),
                            child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: DropdownButton<String>(
                              value: ['exact', 'range', 'bool'].contains(matchType) ? matchType : 'exact',
                              isDense: true,
                              isExpanded: true,
                              underline: const SizedBox(),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF111116), fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(value: 'exact', child: Text('字面量 (=)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'range', child: Text('数值比较', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'bool', child: Text('开关状态', overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    rule['matchType'] = v;
                                    if (v == 'bool') rule['matchValue'] = 'true';
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('发光', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                          SizelessSwitch(
                            value: isGlow,
                            onChanged: (val) => setState(() => rule['isGlow'] = val),
                            color: ruleColor,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                            onPressed: () => _removeRule(idx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (matchType == 'exact') ...[
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(text: rule['matchValue']?.toString() ?? ''),
                                onChanged: (v) => rule['matchValue'] = v,
                                decoration: const InputDecoration(
                                  hintText: '完全匹配字面量 (如: 暴雨)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),
                          ] else if (matchType == 'bool') ...[
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: (rule['matchValue']?.toString() == 'false') ? 'false' : 'true',
                                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(value: 'true', child: Text('当开关 开启 (true)', style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(value: 'false', child: Text('当开关 关闭 (false)', style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => rule['matchValue'] = v);
                                },
                              ),
                            ),
                          ] else if (matchType == 'range') ...[
                            SizedBox(
                              width: 55,
                              child: DropdownButtonFormField<String>(
                                initialValue: ['>', '<', '>=', '<=', '=='].contains(rule['matchOp']?.toString()) ? rule['matchOp']?.toString() : '>',
                                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(value: '>', child: Text('>')),
                                  DropdownMenuItem(value: '<', child: Text('<')),
                                  DropdownMenuItem(value: '>=', child: Text('>=')),
                                  DropdownMenuItem(value: '<=', child: Text('<=')),
                                  DropdownMenuItem(value: '==', child: Text('==')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => rule['matchOp'] = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(text: rule['matchValNum']?.toString() ?? ''),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => rule['matchValNum'] = double.tryParse(v) ?? rule['matchValNum'],
                                decoration: const InputDecoration(
                                  hintText: '比较阈值 (如: 80)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          const Text('色盘:', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                          const SizedBox(width: 4),
                          Wrap(
                            spacing: 4,
                            children: _swatchColors.take(4).map((col) {
                              final sel = col.toARGB32() == ruleColor.toARGB32();
                              return GestureDetector(
                                onTap: () => setState(() => rule['color'] = col.toARGB32()),
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: col,
                                    shape: BoxShape.circle,
                                    border: sel ? Border.all(color: Colors.black, width: 2) : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              InkWell(
                onTap: _addRule,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: const Center(
                    child: Text(
                      '+ 添加状态映射规则',
                      style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SizelessSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  const SizelessSwitch({super.key, required this.value, required this.onChanged, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.75,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: color,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
