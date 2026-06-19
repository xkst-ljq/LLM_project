import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_meta.dart';
import '../services/database_service.dart';
import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

class UIStudioPage extends StatefulWidget {
  const UIStudioPage({super.key});

  @override
  State<UIStudioPage> createState() => _UIStudioPageState();
}

class _UIStudioPageState extends State<UIStudioPage> {
  final UIAssetService _assetService = UIAssetService();
  
  // 目标角色与排版布局列表
  List<Map<String, dynamic>> _characters = [];
  String _selectedCharacterId = 'global'; // 'global' 表示全局默认排版
  
  // 画布上的元素列表
  List<UIElement> _canvasElements = [];
  // 当前选中的元素 ID
  String? _selectedElementId;
  
  // 面板开关状态
  bool _showAssets = false;
  bool _showProperties = false;

  @override
  void initState() {
    super.initState();
    _loadCharactersAndLayout();
  }

  // 加载角色列表与当前选中布局
  Future<void> _loadCharactersAndLayout() async {
    final chars = await DatabaseService.getAllCharacters();
    setState(() {
      _characters = chars;
    });
    await _loadLayoutForCharacter(_selectedCharacterId);
  }

  // 切换目标角色排版
  Future<void> _loadLayoutForCharacter(String charId) async {
    List<UIElement> loadedElements = [];
    if (charId == 'global') {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('global_ui_layout');
      if (raw != null) {
        try {
          final List list = jsonDecode(raw);
          loadedElements = list.map((e) => UIElement.fromJson(e)).toList();
        } catch (_) {}
      }
    } else {
      final targetChar = _characters.firstWhere((c) => c['id'] == charId, orElse: () => {});
      if (targetChar.isNotEmpty) {
        final meta = CharacterMeta.fromJsonString(targetChar['meta_json'] as String?);
        loadedElements = meta.uiElements;
      }
    }

    setState(() {
      _selectedCharacterId = charId;
      _canvasElements = loadedElements;
      _selectedElementId = null;
      _showProperties = false;
    });
  }

  // 保存当前画布布局
  Future<void> _saveCurrentLayout() async {
    if (_selectedCharacterId == 'global') {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_canvasElements.map((e) => e.toJson()).toList());
      await prefs.setString('global_ui_layout', data);
    } else {
      final index = _characters.indexWhere((c) => c['id'] == _selectedCharacterId);
      if (index != -1) {
        final char = Map<String, dynamic>.from(_characters[index]);
        final meta = CharacterMeta.fromJsonString(char['meta_json'] as String?);
        meta.uiElements = _canvasElements;
        char['meta_json'] = meta.toJsonString();
        await DatabaseService.updateCharacter(char);
        setState(() {
          _characters[index] = char;
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedCharacterId == 'global' ? '全局默认 UI 排版保存成功！' : '角色专属 UI 排版保存成功！'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // 添加组件到画布 (智能交错计算位置，避免完全重叠)
  void _addElement(UIModule module) {
    setState(() {
      final len = _canvasElements.length;
      final dx = 100.0 + (len * 25) % 180;
      final dy = 100.0 + (len * 25) % 180;

      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: false,
        module: module.copyWith(), // 复制一份以供独立修改
        offset: Offset(dx, dy),
        size: const Size(160, 80),
      );
      _canvasElements.add(newElement);
      _selectedElementId = newElement.id;
      _showAssets = false; // 添加后关闭资产栏
      _showProperties = true; // 自动打开属性栏
    });
  }

  void _addComposite(UIComposite composite) {
    setState(() {
      final len = _canvasElements.length;
      final dx = 120.0 + (len * 30) % 180;
      final dy = 120.0 + (len * 30) % 180;

      final newElement = UIElement(
        id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: true,
        composite: composite.copyWith(),
        offset: Offset(dx, dy),
        size: const Size(280, 160),
      );
      _canvasElements.add(newElement);
      _selectedElementId = newElement.id;
      _showAssets = false;
      _showProperties = true;
    });
  }

  // 删除元素
  void _deleteElement(String id) {
    setState(() {
      _canvasElements.removeWhere((e) => e.id == id);
      if (_selectedElementId == id) {
        _selectedElementId = null;
        _showProperties = false;
      }
    });
  }

  // 更新元素位置
  void _updateElementPosition(String id, Offset newOffset) {
    setState(() {
      final index = _canvasElements.indexWhere((e) => e.id == id);
      if (index != -1) {
        _canvasElements[index] = _canvasElements[index].copyWith(offset: newOffset);
      }
    });
  }

  // 更新元素大小
  void _updateElementSize(String id, Size newSize) {
    setState(() {
      final index = _canvasElements.indexWhere((e) => e.id == id);
      if (index != -1) {
        _canvasElements[index] = _canvasElements[index].copyWith(size: newSize);
      }
    });
  }

  // 更新模块属性
  void _updateSelectedModule({
    String? name,
    Color? color,
    UIModuleShape? shape,
    UIModuleMaterial? material,
    String? boundVariable,
    String? textProperty,
  }) {
    if (_selectedElementId == null) return;
    setState(() {
      final index = _canvasElements.indexWhere((e) => e.id == _selectedElementId);
      if (index != -1) {
        final el = _canvasElements[index];
        if (!el.isComposite && el.module != null) {
          Map<String, dynamic> updatedProps = Map.from(el.module!.properties);
          if (textProperty != null) {
            updatedProps['text'] = textProperty;
          }
          final newMod = el.module!.copyWith(
            name: name,
            color: color,
            shape: shape,
            material: material,
            boundVariable: boundVariable,
            properties: updatedProps,
          );
          _canvasElements[index] = el.copyWith(module: newMod);
        } else if (el.isComposite && el.composite != null) {
          final newComp = el.composite!.copyWith(
            name: name,
            color: color,
            material: material,
          );
          _canvasElements[index] = el.copyWith(composite: newComp);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 创作工作室'),
        titleSpacing: 0,
        actions: [
          // 目标角色选择下拉框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: _selectedCharacterId,
              underline: const SizedBox(),
              dropdownColor: Theme.of(context).cardColor,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
              style: const TextStyle(fontSize: 13, color: Colors.white),
              items: [
                const DropdownMenuItem(value: 'global', child: Text('🌐 全局默认 UI')),
                ..._characters.map((c) {
                  return DropdownMenuItem(
                    value: c['id'].toString(),
                    child: Text('👤 ${c['name']}'),
                  );
                }).toList(),
              ],
              onChanged: (val) {
                if (val != null) _loadLayoutForCharacter(val);
              },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存配置'),
            onPressed: _saveCurrentLayout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 1. 底层：无限画布 (全屏)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedElementId = null;
                _showProperties = false;
              }),
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(2000),
                minScale: 0.1,
                maxScale: 3.0,
                child: Stack(
                  children: [
                    // 绘制网格背景 (辅助对齐)
                    Positioned.fill(child: _buildGridBackground()),
                    
                    // 渲染画布元素 (支持平移、缩放手柄与删除)
                    ..._canvasElements.map((el) => _buildDraggableNode(el)).toList(),
                  ],
                ),
              ),
            ),
          ),
          
          // 2. 左侧：资产库浮窗
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            left: _showAssets ? 0 : -260,
            top: 0,
            bottom: 0,
            width: 250,
            child: _buildAssetPanel(),
          ),
          
          // 3. 右侧：属性面板浮窗
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            right: _showProperties ? 0 : -310,
            top: 0,
            bottom: 0,
            width: 300,
            child: _buildPropertiesPanel(),
          ),

          // 底部控制条 (用于快速切换面板)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'asset_btn',
                    backgroundColor: _showAssets ? Colors.cyan : Theme.of(context).cardColor,
                    foregroundColor: _showAssets ? Colors.white : Colors.cyanAccent,
                    onPressed: () => setState(() => _showAssets = !_showAssets),
                    icon: Icon(_showAssets ? Icons.close : Icons.grid_view, size: 18),
                    label: const Text('模组资产'),
                  ),
                  const SizedBox(width: 20),
                  FloatingActionButton.extended(
                    heroTag: 'prop_btn',
                    backgroundColor: _showProperties ? Colors.cyan : Theme.of(context).cardColor,
                    foregroundColor: _showProperties ? Colors.white : Colors.cyanAccent,
                    onPressed: () => setState(() => _showProperties = !_showProperties),
                    icon: Icon(_showProperties ? Icons.close : Icons.tune, size: 18),
                    label: const Text('属性参数'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15)],
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('模组资产库', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _showAssets = false),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                _buildAssetSection('原子模组 (基础控件)', _assetService.getAllModules()),
                const Divider(),
                _buildAssetSection('组合块 (复合面板)', _assetService.getAllComposites()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetSection(String title, List<dynamic> assets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 12, color: Colors.cyanAccent)),
        ),
        ...assets.map((asset) {
          final name = (asset is UIModule) ? asset.name : (asset as UIComposite).name;
          final typeIcon = (asset is UIModule) ? Icons.widgets : Icons.dashboard_customize;
          return Card(
            color: Colors.white.withValues(alpha: 0.05),
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(typeIcon, size: 18, color: Colors.cyan),
              title: Text(name, style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
              onTap: () {
                if (asset is UIModule) {
                  _addElement(asset);
                } else if (asset is UIComposite) {
                  _addComposite(asset);
                }
              },
            ),
          );
        }).toList(),
      ],
    );
  }

  // 构建支持自由平移、缩放把手和快捷删除的交互画布节点
  Widget _buildDraggableNode(UIElement el) {
    bool isSelected = _selectedElementId == el.id;

    return Positioned(
      left: el.offset.dx,
      top: el.offset.dy,
      width: el.size.width,
      height: el.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主体节点手势支持 (平移)
          GestureDetector(
            onTap: () => setState(() {
              _selectedElementId = el.id;
              _showProperties = true;
            }),
            onPanUpdate: (details) {
              _updateElementPosition(el.id, el.offset + details.delta);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.cyanAccent : Colors.transparent,
                  width: isSelected ? 2.0 : 0.0,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected
                    ? [BoxShadow(color: Colors.cyan.withValues(alpha: 0.3), blurRadius: 10)]
                    : [],
              ),
              // 使用 FittedBox 完美实现矢量级自适应缩放
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: UIRenderer.render(context, el),
                ),
              ),
            ),
          ),

          // 右上角：快速删除按钮
          if (isSelected)
            Positioned(
              right: -10,
              top: -10,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _deleteElement(el.id),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.delete_outline, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),

          // 右下角：缩放把手 (Procreate/ComfyUI 式拖拽把手)
          if (isSelected)
            Positioned(
              right: -10,
              bottom: -10,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final newWidth = (el.size.width + details.delta.dx).clamp(60.0, 800.0);
                    final newHeight = (el.size.height + details.delta.dy).clamp(40.0, 800.0);
                    _updateElementSize(el.id, Size(newWidth, newHeight));
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.cyanAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Icons.open_with, size: 12, color: Colors.black),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridBackground() {
    return CustomPaint(
      painter: GridPainter(),
      size: Size.infinite,
    );
  }

  // 深度精细的实时属性编辑器
  Widget _buildPropertiesPanel() {
    if (_selectedElementId == null) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Center(child: Text('请在画布上选择一个模组进行编辑', style: TextStyle(color: Colors.grey))),
      );
    }

    final el = _canvasElements.firstWhere((e) => e.id == _selectedElementId);
    final isComp = el.isComposite;
    final name = isComp ? el.composite?.name : el.module?.name;
    final color = isComp ? el.composite?.color : el.module?.color;
    final material = isComp ? el.composite?.material : el.module?.material;
    final shape = !isComp ? el.module?.shape : null;
    final boundVar = !isComp ? el.module?.boundVariable : null;
    final textProp = !isComp ? el.module?.properties['text']?.toString() : null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15)],
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('实时属性编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _showProperties = false),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text('类型: ${isComp ? "组合块 (Composite)" : "原子模组 (Module)"}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                const SizedBox(height: 12),
                
                // 1. 修改名称
                TextFormField(
                  initialValue: name ?? '',
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: '模组名称', border: OutlineInputBorder()),
                  onChanged: (val) => _updateSelectedModule(name: val),
                ),
                const SizedBox(height: 16),

                // 2. 修改文本内容 (若是原子控件)
                if (!isComp && textProp != null) ...[
                  TextFormField(
                    initialValue: textProp,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(labelText: '显示文字内容', border: OutlineInputBorder()),
                    onChanged: (val) => _updateSelectedModule(textProperty: val),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. 修改绑定变量 (若是原子控件)
                if (!isComp) ...[
                  TextFormField(
                    initialValue: boundVar ?? '',
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: '绑定 Prompt 变量名',
                      hintText: '如 var.hp, var.gold',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => _updateSelectedModule(boundVariable: val),
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. 颜色选择器 (Swatches)
                const Text('主色调', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Colors.redAccent,
                    Colors.deepOrange,
                    Colors.amberAccent,
                    Colors.greenAccent,
                    Colors.cyan,
                    Colors.blueAccent,
                    Colors.purpleAccent,
                    Colors.pinkAccent,
                    Colors.white,
                    Colors.blueGrey,
                  ].map((c) {
                    return GestureDetector(
                      onTap: () => _updateSelectedModule(color: c),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2),
                          boxShadow: [if (color == c) const BoxShadow(color: Colors.white54, blurRadius: 6)],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 5. 材质切换
                const Text('渲染材质风格', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                DropdownButtonFormField<UIModuleMaterial>(
                  value: material ?? UIModuleMaterial.glass,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  dropdownColor: Theme.of(context).cardColor,
                  items: const [
                    DropdownMenuItem(value: UIModuleMaterial.glass, child: Text('✨ Glassmorphism (毛玻璃)')),
                    DropdownMenuItem(value: UIModuleMaterial.solid, child: Text('🎨 Solid (纯色实心)')),
                    DropdownMenuItem(value: UIModuleMaterial.gradient, child: Text('🌈 Gradient (科技渐变)')),
                    DropdownMenuItem(value: UIModuleMaterial.outline, child: Text('⭕ Outline (极简描边)')),
                  ],
                  onChanged: (val) {
                    if (val != null) _updateSelectedModule(material: val);
                  },
                ),
                const SizedBox(height: 16),

                // 6. 形状切换 (若是原子控件)
                if (!isComp) ...[
                  const Text('外框形状', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<UIModuleShape>(
                    value: shape ?? UIModuleShape.rounded,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    dropdownColor: Theme.of(context).cardColor,
                    items: const [
                      DropdownMenuItem(value: UIModuleShape.rectangle, child: Text('直角矩形')),
                      DropdownMenuItem(value: UIModuleShape.rounded, child: Text('圆角矩形')),
                      DropdownMenuItem(value: UIModuleShape.capsule, child: Text('胶囊形 (Capsule)')),
                      DropdownMenuItem(value: UIModuleShape.circle, child: Text('正圆形')),
                    ],
                    onChanged: (val) {
                      if (val != null) _updateSelectedModule(shape: val);
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. 位置与大小数值微调
                const Text('坐标与几何规范', style: TextStyle(fontSize: 12, color: Colors.cyanAccent)),
                const Divider(),
                _buildNumberAdjuster('X 坐标 (px)', el.offset.dx, (v) => _updateElementPosition(el.id, Offset(v, el.offset.dy))),
                _buildNumberAdjuster('Y 坐标 (px)', el.offset.dy, (v) => _updateElementPosition(el.id, Offset(el.offset.dx, v))),
                _buildNumberAdjuster('宽度 (px)', el.size.width, (v) => _updateElementSize(el.id, Size(v, el.size.height)), min: 50, max: 800),
                _buildNumberAdjuster('高度 (px)', el.size.height, (v) => _updateElementSize(el.id, Size(el.size.width, v)), min: 40, max: 800),
                
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('从画布移除该模组'),
                  onPressed: () => _deleteElement(el.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberAdjuster(String label, double value, Function(double) onChanged, {double min = -1000, double max = 2000}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                onPressed: () => onChanged((value - 10).clamp(min, max)),
              ),
              SizedBox(
                width: 50,
                child: Text(value.toStringAsFixed(0), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 16),
                onPressed: () => onChanged((value + 10).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const double step = 50.0;
    for (double x = -2000; x < 4000; x += step) {
      canvas.drawLine(Offset(x, -2000), Offset(x, 4000), paint);
    }
    for (double y = -2000; y < 4000; y += step) {
      canvas.drawLine(Offset(-2000, y), Offset(4000, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
