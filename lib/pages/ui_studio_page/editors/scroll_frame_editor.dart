import 'package:flutter/material.dart';

import '../../../services/ui_engine/ui_models.dart';
import '../../../services/ui_engine/ui_renderer.dart';

/// 局部滚动视窗规格编辑器
/// 对应 UI 模块类型：UIModuleType.scroll_frame
class ScrollFrameEditor extends StatefulWidget {
  final Map<String, dynamic> initialProperties;
  final String moduleName;
  final int layerId;
  final Offset initialPosition;
  final VoidCallback onDelete;
  final Function(Map<String, dynamic>) onSave;

  const ScrollFrameEditor({
    super.key,
    required this.initialProperties,
    required this.moduleName,
    required this.layerId,
    required this.initialPosition,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<ScrollFrameEditor> createState() => _ScrollFrameEditorState();
}

class _ScrollFrameEditorState extends State<ScrollFrameEditor> {
  late TextEditingController _nameController;
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late String _scrollMode;
  late bool _clipToBounds;
  late bool _showScrollbar;
  late String _physics;
  late Color _backgroundColor;
  late List<Map<String, dynamic>> _adoptedChildren;

  final List<Color> _swatchColors = const [
    Color(0xFFF0F0F5), // 极简高级灰 (默认)
    Color(0xFFFFFFFF), // 纯白
    Color(0xFF1E1E24), // 科技黑/暗黑
    Color(0x00000000), // 全透明
    Color(0xFFE8EAF6), // 蓝灰靛青
    Color(0xFFFFF8E1), // 暖米黄
    Color(0xFFE8F5E9), // 清新薄绿
    Color(0xFFFCE4EC), // 浅樱桃粉
  ];

  @override
  void initState() {
    super.initState();
    final props = widget.initialProperties;

    _nameController = TextEditingController(text: widget.moduleName);
    _widthController = TextEditingController(
      text: (props['contentWidth'] ?? 300.0).toString(),
    );
    _heightController = TextEditingController(
      text: (props['contentHeight'] ?? 500.0).toString(),
    );

    _scrollMode = props['scrollMode']?.toString() ?? 'vertical';
    _clipToBounds = props['clipToBounds'] != false;
    _showScrollbar = props['showScrollbar'] != false;
    _physics = props['physics']?.toString() ?? 'bouncing';

    final bgColorVal = props['backgroundColor'] ?? 0xFFF0F0F5;
    _backgroundColor = Color(bgColorVal is int ? bgColorVal : 0xFFF0F0F5);

    final rawAdopted = props['adoptedChildElements'];
    if (rawAdopted is List && rawAdopted.isNotEmpty) {
      _adoptedChildren = rawAdopted.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _adoptedChildren = [];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _removeAdoptedChild(int index) {
    setState(() {
      _adoptedChildren.removeAt(index);
    });
  }

  void _save() {
    final double contentW = double.tryParse(_widthController.text.trim()) ?? 300.0;
    final double contentH = double.tryParse(_heightController.text.trim()) ?? 500.0;

    final newProps = {
      'type': 'scroll_frame',
      'name': _nameController.text.trim(),
      'scrollMode': _scrollMode,
      'clipToBounds': _clipToBounds,
      'showScrollbar': _showScrollbar,
      'physics': _physics,
      'contentWidth': contentW,
      'contentHeight': contentH,
      'backgroundColor': _backgroundColor.toARGB32(),
      'adoptedChildElements': _adoptedChildren,
      'adoptedChildren': _adoptedChildren.map((e) => e['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList(),
    };

    widget.onSave(newProps);
    Navigator.of(context).pop();
  }

  void _handleDelete() {
    widget.onDelete();
    Navigator.of(context).pop();
  }

  void _showSubWorkspaceDialog() {
    final double contentW = double.tryParse(_widthController.text.trim()) ?? 300.0;
    final double contentH = double.tryParse(_heightController.text.trim()) ?? 500.0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (subCtx, setSubState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                width: 620,
                height: 560,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pan_tool_alt_outlined, color: Color(0xFF3F51B5), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '内部排版空间 [宽:${contentW.toInt()} x 高:${contentH.toInt()}px] · 相对(0,0)坐标拖拽',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(subCtx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: const Color(0xFF2A2A32),
                        alignment: Alignment.center,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: Container(
                              width: contentW,
                              height: contentH,
                              decoration: BoxDecoration(
                                color: _backgroundColor,
                                border: Border.all(color: const Color(0xFF3F51B5), width: 2),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Center(
                                      child: Text(
                                        '相对坐标系 (0,0)\n可拖拽调整内部收容控件物理位置',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  ..._adoptedChildren.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final childMap = entry.value;
                                    final offsetMap = childMap['offset'] as Map? ?? {'dx': 20.0, 'dy': 20.0};
                                    final double dx = (offsetMap['dx'] as num?)?.toDouble() ?? 20.0;
                                    final double dy = (offsetMap['dy'] as num?)?.toDouble() ?? 20.0;
                                    final modMap = childMap['module'] as Map? ?? {};
                                    final String childName = modMap['name']?.toString() ?? '收容件 ${idx + 1}';
                                    final String childType = modMap['type']?.toString() ?? 'unknown';

                                    UIElement? parsedEl;
                                    try {
                                      parsedEl = UIElement.fromJson(childMap);
                                    } catch (_) {}

                                    return Positioned(
                                      left: dx,
                                      top: dy,
                                      child: GestureDetector(
                                        onPanUpdate: (details) {
                                          setSubState(() {
                                            final newX = (dx + details.delta.dx).clamp(0.0, contentW - 20.0);
                                            final newY = (dy + details.delta.dy).clamp(0.0, contentH - 20.0);
                                            childMap['offset'] = {'dx': newX, 'dy': newY};
                                          });
                                          setState(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF3F51B5), width: 1.5),
                                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF3F51B5)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '$childName [$childType] (${dx.toInt()}, ${dy.toInt()})',
                                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF3F51B5)),
                                                  ),
                                                ],
                                              ),
                                              if (parsedEl != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: IgnorePointer(
                                                    child: SizedBox(
                                                      width: parsedEl.size.width,
                                                      height: parsedEl.size.height,
                                                      child: UIRenderer.render(subCtx, parsedEl),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                  const Icon(Icons.view_day_outlined, color: Color(0xFF3F51B5), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '局部滚动视窗规格配置 (Scroll Frame)',
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

            // 弹性内容区（R5防溢出）
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHostSection(),
                    const SizedBox(height: 16),
                    _buildModeSection(),
                    const SizedBox(height: 16),
                    _buildDimensionsSection(),
                    const SizedBox(height: 16),
                    _buildAppearanceSection(),
                    const SizedBox(height: 16),
                    _buildAdoptedChildrenSection(),
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
                    label: const Text('删除视窗', style: TextStyle(color: Colors.red, fontSize: 13)),
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
                      backgroundColor: const Color(0xFF3F51B5),
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

  Widget _buildHostSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基本信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '模块名称',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '物理坐标(${widget.initialPosition.dx.toInt()}, ${widget.initialPosition.dy.toInt()}) · 物理尺寸由工作台八角拉伸柄调整',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('视窗排版模式 (核心滑动方向)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildModeChip('vertical', '📜 竖直滚动 (标准)', '锁定横向，容纳超长属性/物品簿'),
            _buildModeChip('horizontal', '📜 横向滚动 (卡牌)', '锁定纵向，容纳横向画廊或立绘'),
            _buildModeChip('omni', '🗺️ 2D 无极沙盘', '360°八向自由平移，探索沙盘地图'),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChip(String mode, String title, String subtitle) {
    final bool active = _scrollMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _scrollMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8EAF6) : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFF3F51B5) : Colors.grey.shade300, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.w600, color: active ? const Color(0xFF3F51B5) : const Color(0xFF111116))),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('虚拟底板总宽高 (决定视窗内能容纳多长的滑动内容)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '虚拟总宽度 (px)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '虚拟总高度 (px)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [300, 500, 800, 1200].map((val) {
            return ActionChip(
              label: Text('${val}px', style: const TextStyle(fontSize: 10)),
              onPressed: () {
                setState(() {
                  if (_scrollMode == 'horizontal') {
                    _widthController.text = val.toString();
                  } else if (_scrollMode == 'vertical') {
                    _heightController.text = val.toString();
                  } else {
                    _widthController.text = val.toString();
                    _heightController.text = val.toString();
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('外框同色封底、自定义底色与阻尼特性', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('视窗底色(默认灰):', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _swatchColors.map((col) {
                  final sel = col.toARGB32() == _backgroundColor.toARGB32();
                  return GestureDetector(
                    onTap: () => setState(() => _backgroundColor = col),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: sel ? Border.all(color: Colors.black, width: 2) : Border.all(color: Colors.grey.shade300, width: 0.8),
                        boxShadow: sel ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 4)] : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('阻尼特性:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('bouncing 弹性回弹', style: TextStyle(fontSize: 11)),
              selected: _physics == 'bouncing',
              onSelected: (val) {
                if (val) setState(() => _physics = 'bouncing');
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('clamping 硬边截止', style: TextStyle(fontSize: 11)),
              selected: _physics == 'clamping',
              onSelected: (val) {
                if (val) setState(() => _physics = 'clamping');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('严密裁切:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _clipToBounds,
                onChanged: (v) => setState(() => _clipToBounds = v),
                activeThumbColor: const Color(0xFF3F51B5),
              ),
            ),
            const Spacer(),
            const Text('微滚动条:', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _showScrollbar,
                onChanged: (v) => setState(() => _showScrollbar = v),
                activeThumbColor: const Color(0xFF3F51B5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdoptedChildrenSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('连线收容子组件列表 (Adopted Children)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${_adoptedChildren.length} 个成员', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              if (_adoptedChildren.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('当前无收容组件。请在工作台中拖拉联动器连线指向本视窗，选定“移交收容”方案，即可自动入驻！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
                )
              else ...[
                ..._adoptedChildren.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final child = entry.value;
                  final modMap = child['module'] as Map? ?? {};
                  final String childName = modMap['name']?.toString() ?? '收容件 ${idx + 1}';
                  final String childType = modMap['type']?.toString() ?? 'unknown';
                  final offsetMap = child['offset'] as Map? ?? {'dx': 0, 'dy': 0};

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.widgets_outlined, size: 16, color: Color(0xFF3F51B5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$childName [$childType] - (${offsetMap['dx']}, ${offsetMap['dy']})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.link_off, size: 16, color: Colors.redAccent),
                          onPressed: () => _removeAdoptedChild(idx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          tooltip: '移出视窗并释放回工作台',
                        ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _adoptedChildren.isEmpty ? null : _showSubWorkspaceDialog,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('🚪 进入内部排版视窗 (重新定位收容子件)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 38),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
