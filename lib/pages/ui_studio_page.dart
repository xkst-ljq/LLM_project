import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

class UIStudioPage extends StatefulWidget {
  const UIStudioPage({super.key});

  @override
  State<UIStudioPage> createState() => _UIStudioPageState();
}

class _UIStudioPageState extends State<UIStudioPage> {
  // 图层是给用户组织 UI 组件用的工作区结构，不应真正无限增长。
  // 64 层已经远超常规编辑需求，同时能避免误触连续创建导致存档结构失控。
  static const int _maxSceneLayerCount = 64;
  static const double _canvasExtent = 20000.0;
  static const Offset _canvasOrigin = Offset(_canvasExtent / 2, _canvasExtent / 2);

  final UIAssetService _assetService = UIAssetService();
  
  // 独立维护双模式工作台面数据
  List<UIElement> _atomicWorkspaceElements = [];
  List<UIElement> _compositeWorkspaceElements = [];
  
  // 绝对跟手无阻尼平移桌面偏移量
  Offset _workspaceOffset = Offset.zero;

  // --- 极其严谨卓越的动态图层管理体系 (The Targeted Dynamic Layer Engine) ---
  List<LayerScene> _sceneLayers = [LayerScene(id: 0, name: '图层 Level 0')];
  int _activeLayerIndex = 0;
  bool _showLayerManager = false;

  // 按压瞬间绝对屏幕坐标与初始偏移锚定
  Offset _startTouchScreenPos = Offset.zero;
  Offset _startTouchElemOffset = Offset.zero;

  // 右下角拉伸把手全局锚定状态 (1:1 Flawless Absolute Resizing Sync)
  double _startTouchWidth = 150.0;
  double _startTouchHeight = 70.0;
  Offset _startTouchGlobalPos = Offset.zero;

  // 当前激活把手的元素 ID
  String? _selectedTransformationId;
  
  // 左右边栏抽屉开关状态
  bool _showLeftDrawer = false;  // 左侧基本部件抽屉
  bool _showRightDrawer = false; // 右侧完成资产抽屉

  // 底部工作模式开关 (0: 基础原子部件模式, 1: 复合多重组块模式)
  int _bottomModeIndex = 0;

  List<UIElement> get _currentElements => 
      _bottomModeIndex == 0 ? _atomicWorkspaceElements : _compositeWorkspaceElements;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 加载独立图层列表
    final layerData = prefs.getString('ui_studio_scene_layers_v4');
    if (layerData != null) {
      try {
        final List list = jsonDecode(layerData);
        if (list.isNotEmpty) {
          _sceneLayers = list.map((e) => LayerScene.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    final atomicData = prefs.getString('ui_studio_atomic_workspace_v4');
    if (atomicData != null) {
      try {
        final List list = jsonDecode(atomicData);
        _atomicWorkspaceElements = list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    final compositeData = prefs.getString('ui_studio_composite_workspace_v4');
    if (compositeData != null) {
      try {
        final List list = jsonDecode(compositeData);
        _compositeWorkspaceElements = list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    _repairSceneLayerData();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveWorkspaces() async {
    try {
      _repairSceneLayerData();

      final prefs = await SharedPreferences.getInstance();
      
      final layerData = jsonEncode(_sceneLayers.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_scene_layers_v4', layerData);

      final atomicData = jsonEncode(_atomicWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_atomic_workspace_v4', atomicData);

      final compositeData = jsonEncode(_compositeWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_composite_workspace_v4', compositeData);
      
      for (final el in _atomicWorkspaceElements) {
        if (!el.isComposite && el.module != null) {
          _assetService.addModule(el.module!);
        }
      }
      for (final el in _compositeWorkspaceElements) {
        if (el.isComposite && el.composite != null) {
          _assetService.addComposite(el.composite!);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('动态图层总览与模组资产已完整入库保存！✅'), backgroundColor: Color(0xFF00C853)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e'), backgroundColor: const Color(0xFFD32F2F)),
        );
      }
    }
  }

  /// 修复图层存档与元素 layerIndex 不一致的问题，避免出现无法切换/无法编辑的
  /// “幽灵元素”。此方法只做确定性的兜底修复，不删除用户数据。
  void _repairSceneLayerData() {
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '图层 Level 0')];
    }

    // 去重：未来如果加入删除/重排图层，旧存档也不会因为重复 id 导致选择混乱。
    final uniqueLayers = <int, LayerScene>{};
    for (final layer in _sceneLayers) {
      if (layer.id < 0) continue;
      uniqueLayers.putIfAbsent(layer.id, () => layer);
    }
    if (uniqueLayers.isEmpty) {
      uniqueLayers[0] = LayerScene(id: 0, name: '图层 Level 0');
    }
    _sceneLayers = uniqueLayers.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    final existingIds = _sceneLayers.map((e) => e.id).toSet();

    void repairElements(List<UIElement> elements) {
      for (var i = 0; i < elements.length; i++) {
        final el = elements[i];
        if (el.layerIndex < 0) {
          elements[i] = el.copyWith(layerIndex: 0);
          if (!existingIds.contains(0)) {
            _sceneLayers.add(LayerScene(id: 0, name: '图层 Level 0'));
            existingIds.add(0);
          }
          continue;
        }
        if (!existingIds.contains(el.layerIndex)) {
          // 元素引用了图层列表里不存在的层：自动补回该层，而不是丢弃元素。
          _sceneLayers.add(LayerScene(id: el.layerIndex, name: '图层 Level ${el.layerIndex}'));
          existingIds.add(el.layerIndex);
        }
      }
    }

    repairElements(_atomicWorkspaceElements);
    repairElements(_compositeWorkspaceElements);

    _sceneLayers.sort((a, b) => a.id.compareTo(b.id));

    if (!_sceneLayers.any((e) => e.id == _activeLayerIndex)) {
      _activeLayerIndex = _sceneLayers.first.id;
      _selectedTransformationId = null;
    }
  }

  int _nextAvailableLayerId() {
    var maxId = -1;
    for (final layer in _sceneLayers) {
      if (layer.id > maxId) maxId = layer.id;
    }
    return maxId + 1;
  }

  void _switchActiveSceneLayer(int newLayerId) {
    setState(() {
      _activeLayerIndex = newLayerId;
      _selectedTransformationId = null;
    });
  }

  void _createNewSceneLayer() {
    if (_sceneLayers.length >= _maxSceneLayerCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('图层数量已达上限 64 层，建议整理或复用现有图层。'),
          backgroundColor: Color(0xFFFF8F00),
        ),
      );
      return;
    }

    setState(() {
      final newId = _nextAvailableLayerId();
      _sceneLayers.add(LayerScene(id: newId, name: '图层 Level $newId'));
      _activeLayerIndex = newId; // 自动无缝切至新图层！
      _selectedTransformationId = null;
    });
  }

  // 拖拽添加新积木：生成在完全避开边栏与顶部控制区域的安全中心区，同时立刻自动收回边栏抽屉，彻底释放触控交互空间！
  void _addElement(UIModule module) {
    setState(() {
      final len = _currentElements.length;
      // 极其智能安全的可视中心生成坐标，绝不碰撞边栏与顶部按钮
      final dx = 180.0 + (len * 35) % 200 - _workspaceOffset.dx;
      final dy = 140.0 + (len * 25) % 200 - _workspaceOffset.dy;

      Size initialSize = const Size(150, 68);
      if (module.type == 'base_box') {
        initialSize = const Size(260, 160);
      } else if (module.type == 'progress') {
        initialSize = const Size(180, 18);
      } else if (module.type == 'button') {
        initialSize = const Size(120, 44);
      } else if (module.type == 'input') {
        initialSize = const Size(160, 42);
      } else if (module.type == 'surface') {
        initialSize = const Size(160, 70);
      } else if (module.type == 'text') {
        initialSize = const Size(150, 34);
      }

      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: module.type == 'base_box',
        module: module.type != 'base_box' ? module.copyWith() : null,
        composite: module.type == 'base_box'
            ? UIComposite(
                id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
                name: '复合多重边界框',
                layoutType: 'base_box',
                children: [],
                color: const Color(0xFFECEFF1),
              )
            : null,
        offset: Offset(dx, dy),
        size: initialSize,
        layerIndex: _activeLayerIndex, // 完美挂载至动态当前工作层！
      );

      if (_bottomModeIndex == 0) {
        _atomicWorkspaceElements.add(newElement);
      } else {
        _compositeWorkspaceElements.add(newElement);
      }

      _selectedTransformationId = newElement.id;
      
      // 核心绝杀：添加积木瞬间，立刻自动收回两边与图层管理抽屉！彻底杜绝新模块生成在抽屉正下方导致漏按、被吃掉 Bug！
      _showLeftDrawer = false;
      _showRightDrawer = false;
      _showLayerManager = false;
    });
  }

  Size _minElementSize(UIElement el) {
    final type = el.module?.type;
    if (type == 'progress') return const Size(8, 2);
    if (type == 'button') return const Size(4, 4);
    if (type == 'input') return const Size(4, 4);
    if (type == 'text') return const Size(8, 8);
    if (type == 'surface') return const Size(4, 4);
    if (type == 'base_box' || el.isComposite) return const Size(12, 12);
    return const Size(4, 4);
  }

  Size _maxElementSize(UIElement el) => const Size(4000, 4000);

  UIModuleShape _outlineShapeOf(UIElement el) {
    final module = el.module;
    if (module == null) return UIModuleShape.rounded;
    if (module.type == 'progress') return UIModuleShape.capsule;
    if (module.type == 'button' || module.type == 'input') {
      return UIModuleShape.rectangle;
    }
    return module.shape;
  }

  double _outlineBorderRadiusOf(UIElement el) {
    final module = el.module;
    if (module == null) return 12;
    if (module.type == 'progress') return 999;
    return module.borderRadius;
  }

  // 执行同层温和推开防重叠避碰法则
  void _updateElementGeometry(String id, Offset newOffset, Size newSize) {
    setState(() {
      final list = _currentElements;
      final index = list.indexWhere((e) => e.id == id);
      if (index == -1) return;

      final targetEl = list[index];
      Offset updatedOffset = newOffset;

      for (final other in list) {
        if (other.id == id || other.layerIndex != targetEl.layerIndex) continue;

        final Rect newRect = Rect.fromLTWH(updatedOffset.dx, updatedOffset.dy, newSize.width, newSize.height);
        final Rect otherRect = Rect.fromLTWH(other.offset.dx, other.offset.dy, other.size.width, other.size.height);

        if (newRect.overlaps(otherRect)) {
          final double overLeft = newRect.right - otherRect.left;
          final double overRight = otherRect.right - newRect.left;
          final double overTop = newRect.bottom - otherRect.top;
          final double overBottom = otherRect.bottom - newRect.top;

          final double minOver = [overLeft, overRight, overTop, overBottom].reduce((a, b) => a < b ? a : b);

          if (minOver == overLeft) {
            updatedOffset = Offset(otherRect.left - newSize.width - 2.0, updatedOffset.dy);
          } else if (minOver == overRight) {
            updatedOffset = Offset(otherRect.right + 2.0, updatedOffset.dy);
          } else if (minOver == overTop) {
            updatedOffset = Offset(updatedOffset.dx, otherRect.top - newSize.height - 2.0);
          } else if (minOver == overBottom) {
            updatedOffset = Offset(updatedOffset.dx, otherRect.bottom + 2.0);
          }
        }
      }

      list[index] = targetEl.copyWith(offset: updatedOffset, size: newSize);
    });
  }

  void _deleteElement(String id) {
    setState(() {
      if (_bottomModeIndex == 0) {
        _atomicWorkspaceElements.removeWhere((e) => e.id == id);
      } else {
        _compositeWorkspaceElements.removeWhere((e) => e.id == id);
      }
      if (_selectedTransformationId == id) {
        _selectedTransformationId = null;
      }
    });
  }

  // 高雅通透模组规格配置窗
  void _showTailoredPrecisionEditorDialog(UIElement el) {
    final bool isComp = el.isComposite;
    String name = isComp ? (el.composite?.name ?? '') : (el.module?.name ?? '');
    Color color = (isComp ? el.composite?.color : el.module?.color) ?? Colors.white;
    UIModuleShape shape = (!isComp ? el.module?.shape : null) ?? UIModuleShape.rounded;
    UIModuleMaterial material = (isComp ? el.composite?.material : el.module?.material) ?? UIModuleMaterial.glass;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex)
          ? _activeLayerIndex
          : _sceneLayers.first.id;
    }

    Map<String, dynamic> props = Map.from(!isComp ? (el.module?.properties ?? {}) : {});
    String textProp = props['text']?.toString() ?? '';
    String labelProp = props['label']?.toString() ?? props['variable']?.toString() ?? '';
    double maxProp = (props['max'] ?? 100.0).toDouble();
    double curProp = (props['current'] ?? 75.0).toDouble();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('全局模组资产规格配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                      decoration: InputDecoration(
                        filled: true, fillColor: const Color(0xFFF2F2F6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 16),

                    const Text('模块所属独立 Z 轴图层 (同层避碰阻止重叠，跨层覆盖)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: selectedLayer,
                      decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: _sceneLayers.map((ly) {
                        return DropdownMenuItem<int>(value: ly.id, child: Text('${ly.name}${ly.id == _activeLayerIndex ? " (当前创作层)" : ""}'));
                      }).toList(),
                      onChanged: (v) => setDialogState(() => selectedLayer = v ?? _activeLayerIndex),
                    ),
                    const SizedBox(height: 16),

                    if (!isComp && el.module?.type == 'progress') ...[
                      const Text('进度条范围设定 (最大值 / 当前预览值)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: maxProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: maxProp.toStringAsFixed(0).length),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), labelText: '最大值', labelStyle: const TextStyle(color: Color(0xFF888896)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                              onChanged: (v) => maxProp = double.tryParse(v) ?? 100.0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: curProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: curProp.toStringAsFixed(0).length),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), labelText: '预览值', labelStyle: const TextStyle(color: Color(0xFF888896)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                              onChanged: (v) => curProp = double.tryParse(v) ?? 75.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!isComp && el.module?.type == 'text') ...[
                      const Text('文本显示内容', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: TextEditingController(text: textProp)..selection = TextSelection.collapsed(offset: textProp.length),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                        onChanged: (v) => textProp = v,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!isComp && el.module?.type == 'input') ...[
                      const Text('输入逻辑变量名（可选）', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: TextEditingController(text: labelProp)..selection = TextSelection.collapsed(offset: labelProp.length),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                        onChanged: (v) => labelProp = v,
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Text('外观调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40),
                        const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF),
                        const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F)
                      ].map((c) {
                        return GestureDetector(
                          onTap: () => setDialogState(() => color = c),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: c, shape: BoxShape.circle,
                              border: Border.all(color: color == c ? const Color(0xFF111116) : Colors.black12, width: color == c ? 2.5 : 1),
                              boxShadow: [if (color == c) const BoxShadow(color: Colors.black26, blurRadius: 6)],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('渲染材质皮肤', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<UIModuleMaterial>(
                                initialValue: material,
                                decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                dropdownColor: Colors.white,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                items: const [
                                  DropdownMenuItem(value: UIModuleMaterial.glass, child: Text('毛玻璃质感')),
                                  DropdownMenuItem(value: UIModuleMaterial.solid, child: Text('纯色实心')),
                                  DropdownMenuItem(value: UIModuleMaterial.gradient, child: Text('科技渐变')),
                                  DropdownMenuItem(value: UIModuleMaterial.outline, child: Text('极简描边')),
                                ],
                                onChanged: (v) => setDialogState(() => material = v ?? UIModuleMaterial.glass),
                              ),
                            ],
                          ),
                        ),
                        if (!isComp) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('几何外延', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<UIModuleShape>(
                                  initialValue: shape,
                                  decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF2F2F6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                  dropdownColor: Colors.white,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                  items: const [
                                    DropdownMenuItem(value: UIModuleShape.rectangle, child: Text('直角')),
                                    DropdownMenuItem(value: UIModuleShape.rounded, child: Text('圆角')),
                                    DropdownMenuItem(value: UIModuleShape.capsule, child: Text('胶囊')),
                                    DropdownMenuItem(value: UIModuleShape.circle, child: Text('正圆')),
                                  ],
                                  onChanged: (v) => setDialogState(() => shape = v ?? UIModuleShape.rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Color(0xFF888896)))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      final list = _currentElements;
                      final index = list.indexWhere((e) => e.id == el.id);
                      if (index != -1) {
                        if (!isComp) {
                          Map<String, dynamic> updatedProps = Map.from(el.module!.properties);
                          updatedProps['text'] = textProp;
                          if (el.module!.type == 'input') {
                            updatedProps['variable'] = labelProp;
                            updatedProps.remove('label');
                          } else {
                            updatedProps['label'] = labelProp;
                          }
                          updatedProps['max'] = maxProp;
                          updatedProps['current'] = curProp;
                          final newMod = el.module!.copyWith(
                            name: name, color: color, shape: shape, material: material, properties: updatedProps,
                          );
                          list[index] = el.copyWith(module: newMod, layerIndex: selectedLayer);
                        } else {
                          final newComp = el.composite!.copyWith(name: name, color: color, material: material);
                          list[index] = el.copyWith(composite: newComp, layerIndex: selectedLayer);
                        }
                      }
                    });
                  },
                  child: const Text('确定应用', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedElements = _currentElements.toList()..sort((a, b) => a.layerIndex.compareTo(b.layerIndex));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      body: Stack(
        children: [
          // 1. 无限绝对跟手工作台面底壳
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                setState(() => _workspaceOffset += details.delta);
              },
              onTap: () => setState(() => _selectedTransformationId = null),
              child: ClipRect(
                child: CustomPaint(
                  painter: StudioWarmGridPainter(_workspaceOffset),
                  child: Transform.translate(
                    // 使用超大画布 + 原点偏移，避免元素拖远后超出 Stack hitTest 范围导致交互失效。
                    offset: _workspaceOffset - _canvasOrigin,
                    child: SizedBox(
                      width: _canvasExtent,
                      height: _canvasExtent,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 真实模块层：严格按 layerIndex 顺序绘制，保持最终 UI 预览效果。
                          ...sortedElements.map((el) {
                            final double p = el.id == _selectedTransformationId ? 20.0 : 0.0;
                            return Positioned(
                              left: _canvasOrigin.dx + el.offset.dx - p,
                              top: _canvasOrigin.dy + el.offset.dy - p,
                              width: el.size.width + p * 2,
                              height: el.size.height + p * 2,
                              child: _buildTrueSingleHandleNode(el, p),
                            );
                          }),

                          // 当前编辑层辅助层：只把“层号角标 + 细黑白虚线边界”置顶，
                          // 不改变模块本体层级，避免破坏真实预览。
                          ...sortedElements
                              .where((el) => el.layerIndex == _activeLayerIndex)
                              .map((el) {
                            final bool selected = el.id == _selectedTransformationId;
                            return Positioned(
                              // 辅助层不再外扩覆盖模块颜色；只在元素原始边界内绘制细虚线。
                              left: _canvasOrigin.dx + el.offset.dx,
                              top: _canvasOrigin.dy + el.offset.dy - 18,
                              width: el.size.width,
                              height: el.size.height + 18,
                              child: _buildActiveLayerLocatorOverlay(el, selected),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. 左上角返回键
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Material(
              color: Colors.white.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: Icon(Icons.reply_rounded, color: Color(0xFF111116), size: 26),
                ),
              ),
            ),
          ),

          // 3. 右上角：一键保存成果
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4081),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 4,
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('保存成果', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _saveWorkspaces,
            ),
          ),

          // 4. 【📑图层管理】专属按键：精准部署在保存按键的正下方 (`top: 68`)！
          Positioned(
            top: MediaQuery.of(context).padding.top + 68,
            right: 16,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF111116),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 4,
              ),
              icon: const Icon(Icons.layers_rounded, size: 18),
              label: Text('图层 (Level $_activeLayerIndex)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => setState(() => _showLayerManager = true),
            ),
          ),

          // 5. 动态图层管理展示抽屉
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            right: _showLayerManager ? 0 : -260,
            top: 100, bottom: 100,
            width: 240,
            child: _buildDedicatedLayerManagerDrawer(),
          ),

          // 6. 左侧基础部件抽屉
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            left: _showLeftDrawer ? 0 : -150,
            top: 100, bottom: 100,
            width: 150,
            child: _buildLeftCompactAssetPreviewDrawer(),
          ),
          
          if (!_showLeftDrawer)
            Positioned(
              left: 0,
              top: MediaQuery.of(context).size.height / 2 - 24,
              child: GestureDetector(
                onTap: () => setState(() => _showLeftDrawer = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4081).withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomRight: Radius.circular(14)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
                ),
              ),
            ),

          // 7. 右侧已完成资产抽屉
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            right: _showRightDrawer ? 0 : -160,
            top: 120, bottom: 120,
            width: 160,
            child: _buildRightCompletedAssetsDrawer(),
          ),

          if (!_showRightDrawer && !_showLayerManager)
            Positioned(
              right: 0,
              top: MediaQuery.of(context).size.height / 2 - 24,
              child: GestureDetector(
                onTap: () => setState(() => _showRightDrawer = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF111116)),
                ),
              ),
            ),

          // 8. 底部正中央模式轮盘
          Positioned(
            bottom: 24,
            left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildBottomPinkModeButton('原子部件创作台', 0),
                const SizedBox(width: 16),
                _buildBottomPinkModeButton('复合多重拼装台', 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDedicatedLayerManagerDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 25)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showLayerManager = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF00ACC1)), Text(' 收回', style: TextStyle(fontSize: 10, color: Color(0xFF00ACC1), fontWeight: FontWeight.bold))]),
                      ),
                    ),
                    const Text('动态图层总览', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: const Color(0xFF111116), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  icon: const Icon(Icons.add_circle, size: 18),
                  label: const Text('新建图层', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _createNewSceneLayer,
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text('图层专注模式：仅激活选中层，屏蔽旧图层误触', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
              ),
              const Divider(color: Colors.black12),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: _sceneLayers.map((ly) {
                    final bool isSel = _activeLayerIndex == ly.id;
                    return Card(
                      color: isSel ? const Color(0xFF111116) : const Color(0xFFF6F6F9),
                      elevation: isSel ? 4 : 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSel ? const Color(0xFF00E5FF) : Colors.black.withValues(alpha: 0.05), width: isSel ? 1.5 : 1)),
                      child: ListTile(
                        leading: Icon(Icons.layers, color: isSel ? const Color(0xFF00E5FF) : const Color(0xFF888896), size: 18),
                        title: Text(ly.name, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF111116), fontSize: 12, fontWeight: FontWeight.bold)),
                        trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFF00E5FF), size: 18) : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        onTap: () => _switchActiveSceneLayer(ly.id),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPinkModeButton(String label, int modeIndex) {
    final bool isSel = _bottomModeIndex == modeIndex;
    return GestureDetector(
      onTap: () => setState(() {
        _bottomModeIndex = modeIndex;
        _selectedTransformationId = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFFF4081) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: (isSel ? const Color(0xFFFF4081) : Colors.black).withValues(alpha: isSel ? 0.4 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: isSel ? const Color(0xFFFF4081) : Colors.black.withValues(alpha: 0.05), width: 1.5),
        ),
        child: Text(label, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF555562), fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildLeftCompactAssetPreviewDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('基础预览', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13)),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showLeftDrawer = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFF4081).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [Text('收回 ', style: TextStyle(fontSize: 10, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)), Icon(Icons.arrow_back_ios, size: 10, color: Color(0xFFFF4081))]),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: [
                    if (_bottomModeIndex == 1) ...[
                      const Text('复合基本边界框', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                      const SizedBox(height: 4),
                      _buildPreviewDraggableCard(
                        UIModule(id: 'box', name: '基本边界框', type: 'base_box', properties: {}, color: Colors.cyan),
                        Container(height: 50, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00ACC1), width: 1.5, style: BorderStyle.none), borderRadius: BorderRadius.circular(8), color: const Color(0xFF00ACC1).withValues(alpha: 0.08)), child: const Center(child: Text('📦 拖出边界框', style: TextStyle(color: Color(0xFF00ACC1), fontSize: 11, fontWeight: FontWeight.bold)))),
                      ),
                      const Divider(color: Colors.black12),
                    ],

                    const Text('纯进度条原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'prog', name: '进度条原子', type: 'progress', properties: {'min': 0, 'max': 100, 'current': 75}, color: const Color(0xFFFF4081)),
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.75,
                          child: Container(decoration: BoxDecoration(color: const Color(0xFFFF4081), borderRadius: BorderRadius.circular(99))),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    const SizedBox(height: 10),
                    const Text('视觉表面原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'surface', name: '胶囊表面原子', type: 'surface', properties: {}, color: const Color(0xFF651FFF), material: UIModuleMaterial.gradient, shape: UIModuleShape.capsule),
                      Container(height: 34, decoration: BoxDecoration(color: const Color(0xFF651FFF), borderRadius: BorderRadius.circular(999))),
                    ),

                    const SizedBox(height: 10),
                    const Text('按钮逻辑区原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'btn', name: '按钮点击逻辑区', type: 'button', properties: {'action': 'tap'}, color: Colors.transparent),
                      Container(height: 34, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFF4081), width: 1), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const Text('透明点击热区', style: TextStyle(color: Color(0xFFFF4081), fontSize: 10, fontWeight: FontWeight.bold))),
                    ),

                    const SizedBox(height: 10),
                    const Text('纯文本原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'txt', name: '文本原子', type: 'text', properties: {'text': '传奇勇者标签'}, color: const Color(0xFF00B0FF)),
                      const SizedBox(height: 30, child: Center(child: Text('传奇勇者标签', style: TextStyle(color: Color(0xFF00B0FF), fontSize: 12, fontWeight: FontWeight.bold)))),
                    ),

                    const SizedBox(height: 10),
                    const Text('输入逻辑区原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'inp', name: '输入触发逻辑区', type: 'input', properties: {'variable': 'var.input'}, color: Colors.transparent),
                      Container(height: 34, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00ACC1), width: 1), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const Text('透明输入热区', style: TextStyle(color: Color(0xFF00ACC1), fontSize: 10, fontWeight: FontWeight.bold))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewDraggableCard(UIModule module, Widget visualPreview) {
    return GestureDetector(
      onTap: () => _addElement(module),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: visualPreview,
        ),
      ),
    );
  }

  Widget _buildRightCompletedAssetsDrawer() {
    final modules = _assetService.getAllModules();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 14, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showRightDrawer = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF00ACC1)), Text(' 收回', style: TextStyle(fontSize: 10, color: Color(0xFF00ACC1), fontWeight: FontWeight.bold))]),
                      ),
                    ),
                    const Text('完成资产库', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: modules.map((m) => Card(
                    color: const Color(0xFFF6F6F9),
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.black.withValues(alpha: 0.03))),
                    child: ListTile(
                      title: Text(m.name, style: const TextStyle(color: Color(0xFF111116), fontSize: 11, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.add_circle, size: 16, color: Color(0xFF00E676)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: () => _addElement(m),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前编辑层的置顶定位辅助层。
  ///
  /// 只绘制“层号小角标 + 元素边界内侧的黑白交替细虚线”。
  /// 不加阴影、不加半透明蒙版、不重新渲染模块本体，避免影响原始颜色判断。
  /// 整体 IgnorePointer，避免遮挡原有拖拽、缩放、删除等交互命中。
  Widget _buildActiveLayerLocatorOverlay(UIElement el, bool selected) {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 18,
            width: el.size.width,
            height: el.size.height,
            child: CustomPaint(
              painter: StudioAlternatingDashedBorderPainter(
                strokeWidth: selected ? 1.6 : 1.2,
                shape: _outlineShapeOf(el),
                borderRadius: _outlineBorderRadiusOf(el),
              ),
              child: const SizedBox.expand(),
            ),
          ),

          // 只显示层号，尽量减少对最终视觉预览的干扰。
          Positioned(
            left: 4,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 0.7,
                ),
              ),
              child: Text(
                'L${el.layerIndex}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 极其严谨完美的 单一把手 + 当前图层专注锁定法则 节点 ---
  Widget _buildTrueSingleHandleNode(UIElement el, double p) {
    final bool isTransformationActive = _selectedTransformationId == el.id;
    final bool isCurrentLayerActive = el.layerIndex == _activeLayerIndex;

    // 极其完美正确的图层专注锁定法则声明，完美保持视觉相对位置静止无偏差！
    if (!isCurrentLayerActive) {
      return IgnorePointer(
        ignoring: true, // 彻底屏蔽旧图层误触，同时保持真实预览不降透明度。
        child: Container(
          margin: EdgeInsets.only(left: p, top: p), // 完美正确的布局参数！
          width: el.size.width,
          height: el.size.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: UIRenderer.render(context, el),
        ),
      );
    }

    Widget mainContent = SizedBox(
      width: el.size.width,
      height: el.size.height,
      child: UIRenderer.render(context, el),
    );

    Widget touchableBody = GestureDetector(
      // 必须显式使用 opaque：button/input 等逻辑型原子本体是透明 SizedBox，
      // 若沿用默认 deferToChild，透明子树不会参与 hitTest，导致模块看得见但点不动。
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _startTouchElemOffset = el.offset;
        _startTouchScreenPos = details.globalPosition;
      },
      onPanUpdate: (details) {
        final delta = details.globalPosition - _startTouchScreenPos;
        _updateElementGeometry(el.id, _startTouchElemOffset + delta, el.size);
      },
      onPanEnd: (_) => _startTouchElemOffset = Offset.zero,
      onTap: () {
        setState(() => _selectedTransformationId = el.id);
      },
      onLongPress: () {
        _showTailoredPrecisionEditorDialog(el);
      },
      child: mainContent,
    );

    if (!isTransformationActive) {
      return touchableBody;
    }

    return Stack(
      children: [
        Positioned(
          left: p, top: p,
          child: touchableBody,
        ),

        Positioned(
          right: 0, bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _startTouchWidth = el.size.width;
              _startTouchHeight = el.size.height;
              _startTouchGlobalPos = details.globalPosition;
            },
            onPanUpdate: (details) {
              final deltaX = details.globalPosition.dx - _startTouchGlobalPos.dx;
              final deltaY = details.globalPosition.dy - _startTouchGlobalPos.dy;
              final minSize = _minElementSize(el);
              final maxSize = _maxElementSize(el);
              final newWidth = (_startTouchWidth + deltaX)
                  .clamp(minSize.width, maxSize.width)
                  .toDouble();
              final newHeight = (_startTouchHeight + deltaY)
                  .clamp(minSize.height, maxSize.height)
                  .toDouble();
              _updateElementGeometry(el.id, el.offset, Size(newWidth, newHeight));
            },
            child: Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              child: Container(
                width: 22, height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFF4081), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                child: const Icon(Icons.open_with, size: 12, color: Colors.white),
              ),
            ),
          ),
        ),

        Positioned(
          right: 0, top: 0,
          child: GestureDetector(
            onTap: () => _deleteElement(el.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFFF4081), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.delete_outline, size: 12, color: Colors.white), SizedBox(width: 4), Text('移除该部件', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StudioAlternatingDashedBorderPainter extends CustomPainter {
  final double strokeWidth;
  final UIModuleShape shape;
  final double borderRadius;

  StudioAlternatingDashedBorderPainter({
    this.strokeWidth = 1.2,
    this.shape = UIModuleShape.rounded,
    this.borderRadius = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path();
    switch (shape) {
      case UIModuleShape.rectangle:
        path.addRect(rect);
        break;
      case UIModuleShape.circle:
        path.addOval(rect);
        break;
      case UIModuleShape.capsule:
        path.addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(rect.shortestSide / 2),
          ),
        );
        break;
      case UIModuleShape.rounded:
        path.addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
        );
        break;
    }

    final blackPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dashLength = 6.0;
    const gapLength = 2.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var drawWhite = false;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length).toDouble();
        final dashPath = metric.extractPath(distance, next);
        canvas.drawPath(dashPath, drawWhite ? whitePaint : blackPaint);
        distance = next + gapLength;
        drawWhite = !drawWhite;
      }
    }
  }

  @override
  bool shouldRepaint(covariant StudioAlternatingDashedBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.shape != shape ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class StudioWarmGridPainter extends CustomPainter {
  final Offset offset;
  StudioWarmGridPainter(this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFFE2E2E8)
      ..strokeWidth = 1.0;

    const double step = 40.0;
    final double startX = offset.dx % step;
    final double startY = offset.dy % step;

    for (double x = startX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintLine);
    }
    for (double y = startY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLine);
    }
  }

  @override
  bool shouldRepaint(covariant StudioWarmGridPainter oldDelegate) => oldDelegate.offset != offset;
}
