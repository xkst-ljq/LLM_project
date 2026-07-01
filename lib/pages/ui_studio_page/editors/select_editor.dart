import 'package:flutter/material.dart';

/// 下拉单选框规格编辑器
/// 对应 UI 模块类型：UIModuleType.select
class SelectEditor extends StatefulWidget {
  final Map<String, dynamic> initialProperties;
  final String moduleName;
  final int layerId;
  final Offset initialPosition;
  final VoidCallback onDelete;
  final Function(Map<String, dynamic>) onSave;

  const SelectEditor({
    super.key,
    required this.initialProperties,
    required this.moduleName,
    required this.layerId,
    required this.initialPosition,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<SelectEditor> createState() => _SelectEditorState();
}

class _SelectEditorState extends State<SelectEditor> {
  late TextEditingController _nameController;
  late List<String> _options;
  late String _defaultValue;
  late TextEditingController _varController;
  late Color _accentColor;

  final List<Color> _accentColors = const [
    Color(0xFF7E57C2), // 默认紫色
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF29B6F6),
  ];

  @override
  void initState() {
    super.initState();

    final props = widget.initialProperties;

    _nameController = TextEditingController(text: widget.moduleName);

    _options = List<String>.from(props['options'] ?? ['选项 1']);
    if (_options.isEmpty) _options = ['选项 1'];

    _defaultValue = props['defaultValue'] ?? _options.first;

    _varController = TextEditingController(
      text: props['sessionVar'] ?? 'var.select',
    );

    final colorValue = props['accentColor'] ?? 0xFF7E57C2;
    _accentColor = Color(colorValue is int ? colorValue : 0xFF7E57C2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _varController.dispose();
    super.dispose();
  }

  // ==================== 选项池操作 ====================

  void _addOption() {
    setState(() {
      _options.add('选项 ${_options.length + 1}');
    });
  }

  void _removeOption(int index) {
    if (_options.length <= 1) return;

    setState(() {
      final removed = _options.removeAt(index);

      // 脏数据清洗
      if (_defaultValue == removed) {
        _defaultValue = _options.first;
      }
    });
  }

  void _updateOption(int index, String value) {
    setState(() {
      _options[index] = value;

      if (_defaultValue == _options[index]) {
        _defaultValue = value;
      }
    });
  }

  // ==================== 保存与删除 ====================

  void _save() {
    final newProps = {
      'options': _options,
      'defaultValue': _defaultValue,
      'sessionVar': _varController.text.trim(),
      'accentColor': _accentColor.toARGB32(),
      'type': 'select',
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
      child: Container(
        width: 420,
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
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Text(
                    '下拉单选框规格配置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    widget.moduleName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),

            // 内容区
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHostSection(),
                  const SizedBox(height: 20),
                  _buildOptionsSection(),
                  const SizedBox(height: 20),
                  _buildDefaultSection(),
                  const SizedBox(height: 20),
                  _buildVarSection(),
                  const SizedBox(height: 20),
                  _buildAccentColorSection(),
                ],
              ),
            ),

            // 底槽按钮
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _handleDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('删除节点', style: TextStyle(color: Colors.red)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('保存配置'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 各区块构建 ====================

  Widget _buildHostSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基本信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '模块名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('图层：${widget.layerId}', style: TextStyle(color: Colors.grey[700])),
            ),
            Expanded(
              child: Text(
                '坐标：(${widget.initialPosition.dx.toInt()}, ${widget.initialPosition.dy.toInt()})',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选项词条池', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              ..._options.asMap().entries.map((entry) {
                final index = entry.key;
                final option = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: option),
                          onChanged: (val) => _updateOption(index, val),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_options.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                          onPressed: () => _removeOption(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                    ],
                  ),
                );
              }),
              InkWell(
                onTap: _addOption,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: const Center(
                    child: Text(
                      '+ 添加新选项',
                      style: TextStyle(color: Color(0xFF7E57C2), fontWeight: FontWeight.w500),
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

  Widget _buildDefaultSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('初始默认选中项', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _defaultValue,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _options.map((option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _defaultValue = value;
              });
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          '删除选项后会自动清洗为当前第一项',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildVarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('运行时绑定变量', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _varController,
          decoration: const InputDecoration(
            hintText: 'var.select',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '聊天运行时选择不同选项，字面量将实时解包覆盖至提示词字典 {{var.select}}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildAccentColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('控件高亮主题色', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: _accentColors.map((color) {
            final isSelected = color.toARGB32() == _accentColor.toARGB32();
            return GestureDetector(
              onTap: () {
                setState(() {
                  _accentColor = color;
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 2.5)
                      : null,
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
