import 'dart:convert';

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
  final UIAssetService _assetService = UIAssetService();
  
  // 两种不同模式的工作台面独立维护，彻底避免桌面冲突
  List<UIElement> _atomicWorkspaceElements = [];
  List<UIElement> _compositeWorkspaceElements = [];
  
  // 画布整体平移偏移量 (自定义跟手手势引擎，完全摆脱 InteractiveViewer 阻尼与跟手 Bug)
  Offset _workspaceOffset = Offset.zero;

  // 单点形变触发：记录当前激活 8 个形变点把手的元素 ID
  String? _selectedTransformationId;
  
  // 抽屉开关状态 (固定箭头把手不会动，缩小时抽屉完全消失不见)
  bool _showLeftDrawer = false;  // 左侧基本组件抽屉
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
    
    // 读取原子工作台面
    final atomicData = prefs.getString('ui_studio_atomic_workspace');
    if (atomicData != null) {
      try {
        final List list = jsonDecode(atomicData);
        _atomicWorkspaceElements = list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    // 读取复合工作台面
    final compositeData = prefs.getString('ui_studio_composite_workspace');
    if (compositeData != null) {
      try {
        final List list = jsonDecode(compositeData);
        _compositeWorkspaceElements = list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    setState(() {});
  }

  Future<void> _saveWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存原子工作台面
    final atomicData = jsonEncode(_atomicWorkspaceElements.map((e) => e.toJson()).toList());
    await prefs.setString('ui_studio_atomic_workspace', atomicData);

    // 保存复合工作台面
    final compositeData = jsonEncode(_compositeWorkspaceElements.map((e) => e.toJson()).toList());
    await prefs.setString('ui_studio_composite_workspace', compositeData);
    
    // 入库全局共享
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
        const SnackBar(content: Text('两套工作台面数据与模组资产已完整入库！✅'), backgroundColor: Colors.green),
      );
    }
  }

  // 拖出添加组件或基本框到工作区域
  void _addElement(UIModule module) {
    setState(() {
      final len = _currentElements.length;
      final dx = 120.0 + (len * 25) % 150 - _workspaceOffset.dx;
      final dy = 100.0 + (len * 25) % 150 - _workspaceOffset.dy;

      final Size initialSize = module.type == 'base_box' ? const Size(240, 160) : const Size(150, 70);

      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: module.type == 'base_box',
        module: module.type != 'base_box' ? module.copyWith() : null,
        composite: module.type == 'base_box'
            ? UIComposite(
                id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
                name: '复合多重容器',
                layoutType: 'base_box',
                children: [],
                color: Colors.blueGrey,
              )
            : null,
        offset: Offset(dx, dy),
        size: initialSize,
      );

      if (_bottomModeIndex == 0) {
        _atomicWorkspaceElements.add(newElement);
      } else {
        _compositeWorkspaceElements.add(newElement);
      }

      _selectedTransformationId = newElement.id;
    });
  }

  // 更新元素几何规范 (1:1 绝对跟手无阻尼平移)
  void _updateElementGeometry(String id, Offset newOffset, Size newSize) {
    setState(() {
      final list = _currentElements;
      final index = list.indexWhere((e) => e.id == id);
      if (index != -1) {
        list[index] = list[index].copyWith(offset: newOffset, size: newSize);
      }
    });
  }

  // 删除组件
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

  // 专门 tailored 的独立高级参数设定窗
  void _showTailoredPrecisionEditorDialog(UIElement el) {
    final bool isComp = el.isComposite;
    String name = isComp ? (el.composite?.name ?? '') : (el.module?.name ?? '');
    Color color = (isComp ? el.composite?.color : el.module?.color) ?? Colors.white;
    UIModuleShape shape = (!isComp ? el.module?.shape : null) ?? UIModuleShape.rounded;
    UIModuleMaterial material = (isComp ? el.composite?.material : el.module?.material) ?? UIModuleMaterial.glass;

    // 针对具体类型独立抽取的属性
    Map<String, dynamic> props = Map.from(!isComp ? (el.module?.properties ?? {}) : {});
    String textProp = props['text']?.toString() ?? '';
    String labelProp = props['label']?.toString() ?? '';
    double maxProp = (props['max'] ?? 100.0).toDouble();
    double curProp = (props['current'] ?? 80.0).toDouble();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C22), // 极其高雅、高对比度的深色调
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('全局模组资产规格配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 模块通用配置 (无杂乱图标) ---
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true, fillColor: Colors.black38,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 16),

                    // --- 根据具体类型的独立定制编辑 (Tailored Setup) ---
                    if (!isComp && el.module?.type == 'progress') ...[
                      const Text('进度条范围设定 (最大值 / 当前预览值)', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: maxProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: maxProp.toStringAsFixed(0).length),
                              style: const TextStyle(fontSize: 13, color: Colors.white),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(filled: true, fillColor: Colors.black38, labelText: '最大值', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                              onChanged: (v) => maxProp = double.tryParse(v) ?? 100.0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: curProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: curProp.toStringAsFixed(0).length),
                              style: const TextStyle(fontSize: 13, color: Colors.white),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(filled: true, fillColor: Colors.black38, labelText: '预览值', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                              onChanged: (v) => curProp = double.tryParse(v) ?? 80.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!isComp && (el.module?.type == 'button' || el.module?.type == 'text')) ...[
                      const Text('显示文本内容', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: TextEditingController(text: textProp)..selection = TextSelection.collapsed(offset: textProp.length),
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(filled: true, fillColor: Colors.black38, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                        onChanged: (v) => textProp = v,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (!isComp && el.module?.type == 'input') ...[
                      const Text('输入占位提示文字 (Placeholder)', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: TextEditingController(text: labelProp)..selection = TextSelection.collapsed(offset: labelProp.length),
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(filled: true, fillColor: Colors.black38, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                        onChanged: (v) => labelProp = v,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- 主色调卡 (Swatches) ---
                    const Text('主色调调色板', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        Colors.redAccent, Colors.deepOrange, Colors.amberAccent,
                        Colors.greenAccent, Colors.cyan, Colors.blueAccent,
                        Colors.purpleAccent, Colors.pinkAccent, Colors.white, Colors.blueGrey
                      ].map((c) {
                        return GestureDetector(
                          onTap: () => setDialogState(() => color = c),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: c, shape: BoxShape.circle,
                              border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2),
                              boxShadow: [if (color == c) const BoxShadow(color: Colors.white54, blurRadius: 6)],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // --- 材质与几何下拉 ---
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('渲染材质风格', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<UIModuleMaterial>(
                                value: material,
                                decoration: InputDecoration(filled: true, fillColor: Colors.black38, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                dropdownColor: const Color(0xFF2A2A32),
                                style: const TextStyle(fontSize: 12, color: Colors.white),
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
                                const Text('几何外延', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<UIModuleShape>(
                                  value: shape,
                                  decoration: InputDecoration(filled: true, fillColor: Colors.black38, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                  dropdownColor: const Color(0xFF2A2A32),
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.pinkAccent.shade200, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      final list = _currentElements;
                      final index = list.indexWhere((e) => e.id == el.id);
                      if (index != -1) {
                        if (!isComp) {
                          Map<String, dynamic> updatedProps = Map.from(el.module!.properties);
                          updatedProps['text'] = textProp;
                          updatedProps['label'] = labelProp;
                          updatedProps['max'] = maxProp;
                          updatedProps['current'] = curProp;
                          final newMod = el.module!.copyWith(
                            name: name, color: color, shape: shape, material: material, properties: updatedProps,
                          );
                          list[index] = el.copyWith(module: newMod);
                        } else {
                          final newComp = el.composite!.copyWith(name: name, color: color, material: material);
                          list[index] = el.copyWith(composite: newComp);
                        }
                      }
                    });
                  },
                  child: const Text('确定应用', style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF141418), // 极具质感、高档深邃的暗灰主题背景，彻底告别死黑
      body: Stack(
        children: [
          // 1. 无限绝对跟手工作区域 (摆脱 InteractiveViewer 阻尼，1:1 跟随鼠标/手指)
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: (details) {
                // 平移整个工作桌面
                setState(() => _workspaceOffset += details.delta);
              },
              onTap: () => setState(() => _selectedTransformationId = null),
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 高对比度专业网格背景
                    Positioned.fill(
                      child: CustomPaint(painter: StudioGridPainter(_workspaceOffset)),
                    ),

                    // 当前模式桌面上的所有实体积木节点
                    ..._currentElements.map((el) {
                      return Positioned(
                        left: el.offset.dx + _workspaceOffset.dx,
                        top: el.offset.dy + _workspaceOffset.dy,
                        width: el.size.width,
                        height: el.size.height,
                        child: _buildCADInstanceNode(el),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),

          // 2. 左上角：圆角返回把手
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Material(
              color: const Color(0xFF282832),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: Icon(Icons.reply_rounded, color: Colors.white, size: 26),
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
                backgroundColor: Colors.pinkAccent.shade200,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('保存成果', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _saveWorkspaces,
            ),
          ),

          // 4. 左侧抽屉系统 (固定箭头在屏幕边缘，缩小时整个抽屉消失不见)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            left: _showLeftDrawer ? 0 : -180, // 完全缩回屏幕外
            top: 100, bottom: 100,
            width: 180, // 小巧精致，绝不遮挡屏幕
            child: _buildLeftCompactAssetPreviewDrawer(),
          ),
          
          // 固定不会动的左侧展开箭头把手
          Positioned(
            left: 0,
            top: MediaQuery.of(context).size.height / 2 - 20,
            child: GestureDetector(
              onTap: () => setState(() => _showLeftDrawer = !_showLeftDrawer),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                ),
                child: Icon(_showLeftDrawer ? Icons.arrow_back_ios : Icons.arrow_forward_ios, size: 14, color: Colors.white),
              ),
            ),
          ),

          // 5. 右侧抽屉系统
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            right: _showRightDrawer ? 0 : -200, // 缩回屏幕外
            top: 120, bottom: 120,
            width: 200,
            child: _buildRightCompletedAssetsDrawer(),
          ),

          // 固定不会动的右侧展开箭头把手
          Positioned(
            right: 0,
            top: MediaQuery.of(context).size.height / 2 - 20,
            child: GestureDetector(
              onTap: () => setState(() => _showRightDrawer = !_showRightDrawer),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                ),
                child: Icon(_showRightDrawer ? Icons.arrow_forward_ios : Icons.arrow_back_ios, size: 14, color: Colors.white),
              ),
            ),
          ),

          // 6. 底部正中央：两种独立模式工作台面切换钮
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
          color: isSel ? Colors.pinkAccent.shade200 : const Color(0xFF2A2A34),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSel ? [BoxShadow(color: Colors.pinkAccent.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4))] : [],
          border: Border.all(color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  // 左侧基本组件抽屉 —— 废除图标加文字，全幅采用真实的 Live Preview 预览图卡片
  Widget _buildLeftCompactAssetPreviewDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15)],
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('拖拽基础预览', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _showLeftDrawer = false),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),

          // 预览图插槽列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                if (_bottomModeIndex == 1) ...[
                  const Text('复合基本边界容器', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  _buildPreviewDraggableCard(
                    UIModule(id: 'box', name: '基本边界框', type: 'base_box', properties: {}, color: Colors.cyan),
                    Container(height: 54, decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent, width: 1.5, style: BorderStyle.none), borderRadius: BorderRadius.circular(8), color: Colors.cyan.withValues(alpha: 0.1)), child: const Center(child: Text('📦 拖出基本边界框', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)))),
                  ),
                  const Divider(color: Colors.white12),
                ],

                const Text('状态进度条预览', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                _buildPreviewDraggableCard(
                  UIModule(id: 'prog', name: '生命条', type: 'progress', properties: {'min': 0, 'max': 100, 'current': 75}, color: Colors.pinkAccent),
                  Container(height: 48, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('生命条', style: TextStyle(color: Colors.white, fontSize: 10)), Text('75/100', style: TextStyle(color: Colors.white70, fontSize: 9))]), const SizedBox(height: 4), Container(height: 6, decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(3)))])),
                ),

                const SizedBox(height: 12),
                const Text('动作按钮预览', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                _buildPreviewDraggableCard(
                  UIModule(id: 'btn', name: '发起动作', type: 'button', properties: {'text': '发起动作'}, color: Colors.deepPurpleAccent),
                  Container(height: 40, decoration: BoxDecoration(color: Colors.deepPurpleAccent, borderRadius: BorderRadius.circular(8)), child: const Center(child: Text('发起动作', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
                ),

                const SizedBox(height: 12),
                const Text('称号文本预览', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                _buildPreviewDraggableCard(
                  UIModule(id: 'txt', name: '传奇勇者', type: 'text', properties: {'text': '传奇勇者标签'}, color: Colors.tealAccent),
                  Container(height: 36, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4))), child: const Center(child: Text('传奇勇者标签', style: TextStyle(color: Colors.tealAccent, fontSize: 11)))),
                ),

                const SizedBox(height: 12),
                const Text('输入提示框预览', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                _buildPreviewDraggableCard(
                  UIModule(id: 'inp', name: '自定称呼', type: 'input', properties: {'label': '请输入称呼...'}, color: Colors.greenAccent),
                  Container(height: 38, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)), alignment: Alignment.centerLeft, child: const Text('请输入称呼...', style: TextStyle(color: Colors.white54, fontSize: 11))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewDraggableCard(UIModule module, Widget visualPreview) {
    return GestureDetector(
      onTap: () => _addElement(module),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
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
        color: const Color(0xFF1E1E26).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15)],
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _showRightDrawer = false),
                ),
                const Text('已制资产库', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: modules.map((m) => Card(
                color: Colors.white.withValues(alpha: 0.05),
                elevation: 0,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  trailing: const Icon(Icons.add_circle, size: 18, color: Colors.greenAccent),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  onTap: () => _addElement(m),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 构建支持丝滑 1:1 跟手、独立 8 个拉伸形变把手、长按专属定制设定的节点
  Widget _buildCADInstanceNode(UIElement el) {
    bool isActive = _selectedTransformationId == el.id;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 核心被触控体
        Positioned.fill(
          child: GestureDetector(
            onPanUpdate: (details) {
              // 极其精确跟手平移
              _updateElementGeometry(el.id, el.offset + details.delta, el.size);
            },
            onTap: () {
              setState(() => _selectedTransformationId = el.id);
            },
            onLongPress: () {
              _showTailoredPrecisionEditorDialog(el);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isActive ? Colors.pinkAccent : Colors.transparent,
                  width: isActive ? 1.5 : 0.0,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: UIRenderer.render(context, el),
            ),
          ),
        ),

        // --- 真正的 CAD 8 个拉伸把手 (8-Point CAD Handles) ---
        
        // 1. 左上角：调整 dx, dy, w, h
        if (isActive)
          Positioned(
            left: -8, top: -8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width - delta.dx).clamp(60.0, 900.0);
              final nh = (el.size.height - delta.dy).clamp(40.0, 900.0);
              final ndx = el.size.width - delta.dx >= 60.0 ? el.offset.dx + delta.dx : el.offset.dx;
              final ndy = el.size.height - delta.dy >= 40.0 ? el.offset.dy + delta.dy : el.offset.dy;
              _updateElementGeometry(el.id, Offset(ndx, ndy), Size(nw, nh));
            }),
          ),

        // 2. 顶部正中：调整 dy, h
        if (isActive)
          Positioned(
            left: el.size.width / 2 - 8, top: -8,
            child: _buildCADHandleDot((delta) {
              final nh = (el.size.height - delta.dy).clamp(40.0, 900.0);
              final ndy = el.size.height - delta.dy >= 40.0 ? el.offset.dy + delta.dy : el.offset.dy;
              _updateElementGeometry(el.id, Offset(el.offset.dx, ndy), Size(el.size.width, nh));
            }),
          ),

        // 3. 右上角：调整 dy, w, h
        if (isActive)
          Positioned(
            right: -8, top: -8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width + delta.dx).clamp(60.0, 900.0);
              final nh = (el.size.height - delta.dy).clamp(40.0, 900.0);
              final ndy = el.size.height - delta.dy >= 40.0 ? el.offset.dy + delta.dy : el.offset.dy;
              _updateElementGeometry(el.id, Offset(el.offset.dx, ndy), Size(nw, nh));
            }),
          ),

        // 4. 左侧正中：调整 dx, w
        if (isActive)
          Positioned(
            left: -8, top: el.size.height / 2 - 8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width - delta.dx).clamp(60.0, 900.0);
              final ndx = el.size.width - delta.dx >= 60.0 ? el.offset.dx + delta.dx : el.offset.dx;
              _updateElementGeometry(el.id, Offset(ndx, el.offset.dy), Size(nw, el.size.height));
            }),
          ),

        // 5. 右侧正中：调整 w
        if (isActive)
          Positioned(
            right: -8, top: el.size.height / 2 - 8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width + delta.dx).clamp(60.0, 900.0);
              _updateElementGeometry(el.id, el.offset, Size(nw, el.size.height));
            }),
          ),

        // 6. 左下角：调整 dx, w, h
        if (isActive)
          Positioned(
            left: -8, bottom: -8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width - delta.dx).clamp(60.0, 900.0);
              final nh = (el.size.height + delta.dy).clamp(40.0, 900.0);
              final ndx = el.size.width - delta.dx >= 60.0 ? el.offset.dx + delta.dx : el.offset.dx;
              _updateElementGeometry(el.id, Offset(ndx, el.offset.dy), Size(nw, nh));
            }),
          ),

        // 7. 底部正中：调整 h
        if (isActive)
          Positioned(
            left: el.size.width / 2 - 8, bottom: -8,
            child: _buildCADHandleDot((delta) {
              final nh = (el.size.height + delta.dy).clamp(40.0, 900.0);
              _updateElementGeometry(el.id, el.offset, Size(el.size.width, nh));
            }),
          ),

        // 8. 右下角：调整 w, h
        if (isActive)
          Positioned(
            right: -8, bottom: -8,
            child: _buildCADHandleDot((delta) {
              final nw = (el.size.width + delta.dx).clamp(60.0, 900.0);
              final nh = (el.size.height + delta.dy).clamp(40.0, 900.0);
              _updateElementGeometry(el.id, el.offset, Size(nw, nh));
            }),
          ),

        // 9. 顶部悬浮的一键删除专属把手
        if (isActive)
          Positioned(
            right: 16, top: -26,
            child: GestureDetector(
              onTap: () => _deleteElement(el.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.delete_forever, size: 12, color: Colors.white), SizedBox(width: 4), Text('移除该部件', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 单个 CAD 纯正 8 点形变圆点
  Widget _buildCADHandleDot(Function(Offset delta) onDrag) {
    return GestureDetector(
      onPanUpdate: (details) => onDrag(details.delta),
      child: Container(
        width: 16, height: 16,
        decoration: BoxDecoration(color: Colors.pinkAccent.shade200, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
      ),
    );
  }
}

// 极其优雅明显的暗夜专业网格画笔
class StudioGridPainter extends CustomPainter {
  final Offset offset;
  StudioGridPainter(this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFF2C2C36) // 极其优雅明显的线条颜色
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
  bool shouldRepaint(covariant StudioGridPainter oldDelegate) => oldDelegate.offset != offset;
}
