import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

/// 拖拽统一载荷：原子模组 或 复合组件（二选一）。
/// 左右抽屉的卡片均产出此类型，画布 DragTarget 统一接收。
class _DragPayload {
  final UIModule? module;
  final UIComposite? composite;
  _DragPayload({this.module, this.composite});
}

class UIStudioPage extends StatefulWidget {
  const UIStudioPage({super.key});

  @override
  State<UIStudioPage> createState() => _UIStudioPageState();
}

class _UIStudioPageState extends State<UIStudioPage> {
  // 图层是给用户组织 UI 组件用的工作区结构，不应真正无限增长。
  // 64 层已经远超常规编辑需求，同时能避免误触连续创建导致存档结构失控。
  static const int _maxSceneLayerCount = 64;

  final UIAssetService _assetService = UIAssetService();
  final GlobalKey _canvasDropKey = GlobalKey();
  
  // 历史原子工作台草稿保留用于兼容读取；当前 UI 只使用统一工作台。
  List<UIElement> _atomicWorkspaceElements = [];
  List<UIElement> _compositeWorkspaceElements = [];
  
  // 绝对跟手无阻尼平移桌面偏移量
  Offset _workspaceOffset = Offset.zero;

  // --- 极其严谨卓越的动态图层管理体系 (The Targeted Dynamic Layer Engine) ---
  List<LayerScene> _sceneLayers = [LayerScene(id: 0, name: '图层 Level 0')];
  int _activeLayerIndex = 0;
  bool _showLayerManager = false;
  bool _showConstructionManager = false; // 工作台元素/构造层列表

  // 按压瞬间绝对屏幕坐标与初始偏移锚定
  Offset _startTouchScreenPos = Offset.zero;
  Offset _startTouchElemOffset = Offset.zero;

  // 右下角拉伸把手全局锚定状态 (1:1 Flawless Absolute Resizing Sync)
  double _startTouchWidth = 150.0;
  double _startTouchHeight = 70.0;
  Offset _startTouchGlobalPos = Offset.zero;

  // 旋转模式拖拽锚定：按下时记录元素中心(全局)、把手相对中心的角度、起始旋转角。
  // 元素中心由 工作台偏移 + 元素 offset + 半尺寸 直接算出，无需 GlobalKey。
  Offset _rotationCenter = Offset.zero;
  double _startHandleAngle = 0.0;
  double _startRotation = 0.0;

  // 当前激活把手的元素 ID
  String? _selectedTransformationId;

  // 右下角单一变换把手模式：false=缩放，true=旋转（旋转行为后续接入）。
  bool _transformHandleRotateMode = false;
  
  // 左右边栏抽屉开关状态
  bool _showLeftDrawer = false;  // 左侧基本部件抽屉
  bool _showRightDrawer = false; // 右侧完成资产抽屉

  // 当前阶段收敛为单一“工作台”。
  List<UIElement> get _currentElements => _compositeWorkspaceElements;

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

  Future<void> _saveWorkspaceDraft({bool showMessage = true}) async {
    try {
      _repairSceneLayerData();

      final prefs = await SharedPreferences.getInstance();

      final layerData = jsonEncode(_sceneLayers.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_scene_layers_v4', layerData);

      // 旧原子工作台草稿保留兼容；当前统一工作台使用 composite_workspace。
      final atomicData = jsonEncode(_atomicWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_atomic_workspace_v4', atomicData);

      final compositeData = jsonEncode(_compositeWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_composite_workspace_v4', compositeData);

      if (mounted && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('工作台草稿已保存 ✅'), backgroundColor: Color(0xFF00C853)),
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

  void _showSaveMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bakeable = _currentElements.where(_isBakeableElement).length;
        final skipped = _currentElements.length - bakeable;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '保存成果',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111116)),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前工作台元素：${_currentElements.length} 个 · 可烘焙视觉层：$bakeable 个 · 跳过：$skipped 个',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF777783)),
                ),
                const SizedBox(height: 14),
                _buildSaveMenuTile(
                  icon: Icons.save_alt_rounded,
                  title: '保存工作台草稿',
                  subtitle: '只保存当前画布，方便下次继续编辑；不加入资产库。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveWorkspaceDraft();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.dashboard_customize_rounded,
                  title: '保存为复合组件',
                  subtitle: '把当前画布元素保存为一个通用组件，子元素运行时仍独立存在。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveCurrentWorkspaceAsComposite();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.layers_clear_rounded,
                  title: '烘焙为面原子',
                  subtitle: '只合成可烘焙视觉层，文本/数据/交互热区会被跳过。',
                  onTap: bakeable == 0
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _bakeCurrentWorkspaceAsAtom();
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Card(
      elevation: 0,
      color: enabled ? const Color(0xFFF6F6F9) : const Color(0xFFE9E9EF),
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: enabled ? const Color(0xFFFF4081) : const Color(0xFFAAAAB4)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111116))),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF777783))),
        onTap: onTap,
      ),
    );
  }

  Rect? _currentWorkspaceBounds({bool onlyBakeable = false}) {
    final elements = onlyBakeable
        ? _currentElements.where(_isBakeableElement).toList()
        : _currentElements.toList();
    if (elements.isEmpty) return null;

    var bounds = Rect.fromLTWH(
      elements.first.offset.dx,
      elements.first.offset.dy,
      elements.first.size.width,
      elements.first.size.height,
    );
    for (final el in elements.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromLTWH(
        el.offset.dx,
        el.offset.dy,
        el.size.width,
        el.size.height,
      ));
    }
    return bounds.width > 0 && bounds.height > 0 ? bounds : null;
  }

  Future<String?> _askAssetName({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111116))),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFF111116)),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF2F2F6),
              hintText: initialValue,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    // 注意：不要在 showDialog 返回后立刻 dispose 这个局部 controller。
    // 在部分 Android/Flutter 版本中，弹窗关闭和键盘/Overlay 退场动画期间
    // TextField 仍可能触发一次 rebuild，过早 dispose 会导致
    // “A TextEditingController was used after being disposed”。
    // 这里是短生命周期命名弹窗，保留给 GC 回收更安全。
    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> _saveCurrentWorkspaceAsComposite() async {
    if (_currentElements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前工作台没有可保存的元素。'), backgroundColor: Color(0xFFFF8F00)),
      );
      return;
    }

    final assetName = await _askAssetName(title: '保存为复合组件', initialValue: '未命名复合组件');
    if (assetName == null) return;

    final bounds = _currentWorkspaceBounds();
    if (bounds == null) return;

    final children = _currentElements.map((el) {
      return el.copyWith(
        offset: Offset(el.offset.dx - bounds.left, el.offset.dy - bounds.top),
      );
    }).toList();

    final composite = UIComposite(
      id: 'custom_comp_${DateTime.now().millisecondsSinceEpoch}',
      name: assetName,
      layoutType: 'base_box',
      color: Colors.transparent,
      opacity: 0.0,
      children: children,
    );

    await _saveWorkspaceDraft(showMessage: false);
    _assetService.addComposite(composite);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存为复合组件：$assetName ✅'), backgroundColor: const Color(0xFF00C853)),
      );
    }
  }

  Future<void> _bakeCurrentWorkspaceAsAtom() async {
    if (_bakeAtomicWorkspaceToModule() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可烘焙的视觉层。'), backgroundColor: Color(0xFFFF8F00)),
      );
      return;
    }

    final assetName = await _askAssetName(title: '烘焙为面原子', initialValue: '面原子 / 自定义');
    if (assetName == null) return;
    final baked = _bakeAtomicWorkspaceToModule(name: assetName);
    if (baked == null) return;

    await _saveWorkspaceDraft(showMessage: false);
    _assetService.addModule(baked);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已烘焙为面原子：${baked.name} ✅'), backgroundColor: const Color(0xFF00C853)),
      );
    }
  }


  bool _isBakeableElement(UIElement el) {
    final type = el.module?.type;
    return !el.isComposite &&
        el.module != null &&
        (type == 'surface' ||
            type == 'base_box' ||
            type == 'surface_art' ||
            type == 'light_effect' ||
            type == 'primitive_art');
  }

  String _elementTypeLabel(UIElement el) {
    final type = el.module?.type ?? (el.isComposite ? 'composite' : 'unknown');
    switch (type) {
      case 'surface':
        return '面';
      case 'surface_art':
        return '面';
      case 'light_effect':
        return '光效';
      case 'primitive_art':
        return '装饰层';
      case 'progress':
        return '数据条';
      case 'slider':
        return '滑块';
      case 'text':
        return '文本';
      case 'button':
        return '点击热区';
      case 'input':
        return '输入热区';
      case 'base_box':
        return '容器面';
      case 'composite':
        return '复合组件';
      default:
        return type;
    }
  }

  void _moveAtomicConstructionLayer(String id, int delta) {
    setState(() {
      final index = _currentElements.indexWhere((e) => e.id == id);
      if (index == -1) return;
      final target = (index + delta).clamp(0, _currentElements.length - 1);
      if (target == index) return;
      final el = _currentElements.removeAt(index);
      _currentElements.insert(target, el);
    });
  }

  Map<String, dynamic> _syncArtModuleProperties({
    required UIModule module,
    required Map<String, dynamic> props,
    required Color color,
    required double opacity,
    required UIModuleShape shape,
    required UIModuleMaterial material,
    required double borderRadius,
  }) {
    final type = module.type;
    if (type != 'surface_art' && type != 'primitive_art' && type != 'light_effect') {
      return props;
    }

    final rawLayers = props['layers'];
    if (rawLayers is! List) return props;

    var updatedOne = false;
    final updatedLayers = <dynamic>[];
    for (final raw in rawLayers) {
      if (raw is! Map) {
        updatedLayers.add(raw);
        continue;
      }
      final layer = UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw));
      final shouldUpdate = !updatedOne &&
          ((type == 'surface_art' && layer.kind == 'surface') ||
              (type == 'light_effect' && (layer.kind == 'glow' || layer.kind == 'surface')) ||
              (type == 'primitive_art' && (layer.kind == 'line' || layer.kind == 'stroke' || layer.kind == 'surface')));
      if (!shouldUpdate) {
        updatedLayers.add(layer.toJson());
        continue;
      }

      final layerProps = Map<String, dynamic>.from(layer.properties);
      layerProps['material'] = material.index;
      updatedLayers.add(UIPrimitiveLayer(
        id: layer.id,
        kind: layer.kind,
        offset: layer.offset,
        size: layer.size,
        color: color,
        opacity: opacity,
        shape: shape,
        borderRadius: borderRadius,
        properties: layerProps,
      ).toJson());
      updatedOne = true;
    }

    props['layers'] = updatedLayers;
    return props;
  }

  UIModule? _bakeAtomicWorkspaceToModule({String name = '面原子 / 自定义'}) {
    final order = <String, int>{};
    for (var i = 0; i < _currentElements.length; i++) {
      order[_currentElements[i].id] = i;
    }
    final elements = _currentElements
        .where((e) => !e.isComposite && e.module != null)
        .toList()
      ..sort((a, b) {
        final layer = a.layerIndex.compareTo(b.layerIndex);
        if (layer != 0) return layer;
        return (order[a.id] ?? 0).compareTo(order[b.id] ?? 0);
      });
    if (elements.isEmpty) return null;

    final supportedElements = elements.where(_isBakeableElement).toList();
    if (supportedElements.isEmpty) return null;

    Rect bounds = Rect.fromLTWH(
      supportedElements.first.offset.dx,
      supportedElements.first.offset.dy,
      supportedElements.first.size.width,
      supportedElements.first.size.height,
    );
    for (final el in supportedElements.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromLTWH(
        el.offset.dx,
        el.offset.dy,
        el.size.width,
        el.size.height,
      ));
    }
    if (bounds.width <= 0 || bounds.height <= 0) return null;

    final layers = <UIPrimitiveLayer>[];
    for (final el in supportedElements) {
      layers.addAll(_bakeElementToPrimitiveLayers(el, bounds));
    }
    if (layers.isEmpty) return null;

    final id = 'custom_atom_${DateTime.now().millisecondsSinceEpoch}';
    return UIModule(
      id: id,
      name: name,
      type: 'surface_art',
      color: Colors.white,
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rectangle,
      properties: {
        'source': 'basic_workbench_bake',
        'defaultWidth': bounds.width,
        'defaultHeight': bounds.height,
        'layers': layers.map((e) => e.toJson()).toList(),
      },
    );
  }

  List<UIPrimitiveLayer> _bakeElementToPrimitiveLayers(UIElement el, Rect bounds) {
    final module = el.module;
    if (module == null) return const [];

    final elRect = Rect.fromLTWH(
      el.offset.dx,
      el.offset.dy,
      el.size.width,
      el.size.height,
    );

    Offset normalizeOffset(Offset absolute) => Offset(
          (absolute.dx - bounds.left) / bounds.width,
          (absolute.dy - bounds.top) / bounds.height,
        );

    Size normalizeSize(Size absolute) => Size(
          absolute.width / bounds.width,
          absolute.height / bounds.height,
        );

    UIPrimitiveLayer normalizeLayer(UIPrimitiveLayer layer) {
      final absoluteOffset = Offset(
        elRect.left + layer.offset.dx * elRect.width,
        elRect.top + layer.offset.dy * elRect.height,
      );
      final absoluteSize = Size(
        layer.size.width * elRect.width,
        layer.size.height * elRect.height,
      );
      return UIPrimitiveLayer(
        id: '${el.id}_${layer.id}',
        kind: layer.kind,
        offset: normalizeOffset(absoluteOffset),
        size: normalizeSize(absoluteSize),
        color: layer.color,
        opacity: layer.opacity,
        shape: layer.shape,
        borderRadius: layer.borderRadius,
        properties: Map<String, dynamic>.from(layer.properties),
      );
    }

    final type = module.type;
    if (type == 'surface' || type == 'base_box') {
      return [
        UIPrimitiveLayer(
          id: '${el.id}_surface',
          kind: 'surface',
          offset: normalizeOffset(elRect.topLeft),
          size: normalizeSize(el.size),
          color: module.color,
          opacity: module.opacity,
          shape: module.shape,
          borderRadius: module.borderRadius,
          properties: {'material': module.material.index},
        ),
      ];
    }

    final rawLayers = module.properties['layers'];
    if (rawLayers is List) {
      final out = <UIPrimitiveLayer>[];
      for (final raw in rawLayers) {
        if (raw is Map) {
          out.add(normalizeLayer(
            UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw)),
          ));
        }
      }
      return out;
    }

    return const [];
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
      _transformHandleRotateMode = false;
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
      _transformHandleRotateMode = false;
    });
  }

  Size _initialSizeForModule(UIModule module) {
    if (module.type == 'base_box') return const Size(260, 160);
    if (module.type == 'progress') return const Size(180, 18);
    if (module.type == 'button') return const Size(120, 44);
    if (module.type == 'input') return const Size(160, 42);
    if (module.type == 'surface') return const Size(160, 70);
    if (module.type == 'surface_art') return const Size(180, 90);
    if (module.type == 'light_effect') return const Size(120, 120);
    if (module.type == 'primitive_art') return const Size(160, 18);
    if (module.type == 'slider') return const Size(180, 32);
    if (module.type == 'text') return const Size(150, 34);
    return const Size(150, 68);
  }

  void _addElement(UIModule module) {
    final len = _currentElements.length;
    // 点击生成仍保留：生成在视野安全中心区。
    final dx = 180.0 + (len * 35) % 200 - _workspaceOffset.dx;
    final dy = 140.0 + (len * 25) % 200 - _workspaceOffset.dy;
    _addElementAt(module, Offset(dx, dy));
  }

  // 从资产区拖到画布时使用：canvasOffset 是工作台坐标系下的左上角位置。
  void _addElementAt(UIModule module, Offset canvasOffset) {
    setState(() {
      final initialSize = _initialSizeForModule(module);

      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: module.type == 'base_box',
        module: module.type != 'base_box' ? module.copyWith() : null,
        composite: module.type == 'base_box'
            ? UIComposite(
                id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
                name: '容器边界框',
                layoutType: 'base_box',
                children: [],
                color: const Color(0xFFECEFF1),
              )
            : null,
        offset: canvasOffset,
        size: initialSize,
        layerIndex: _activeLayerIndex,
      );

      _compositeWorkspaceElements.add(newElement);

      _selectedTransformationId = newElement.id;
      _transformHandleRotateMode = false;

      // 添加积木后自动收回抽屉，释放画布交互空间。
      _showLeftDrawer = false;
      _showRightDrawer = false;
      _showLayerManager = false;
      _showConstructionManager = false;
    });
  }

  // 拖拽统一载荷：原子模组 或 复合组件二选一。
  // 画布 DragTarget<_DragPayload> 据此分派到 _addElementAt / _addCompositeAt。
  // 子元素旋转后的轴对齐外接矩形 (AABB)。
  // 复合组件的边框尺寸必须包裹旋转后的实际范围，否则边框偏小。
  Rect _childRotatedAABB(UIElement el) {
    if (el.rotation == 0.0) {
      return Rect.fromLTWH(
          el.offset.dx, el.offset.dy, el.size.width, el.size.height);
    }
    final cx = el.offset.dx + el.size.width / 2;
    final cy = el.offset.dy + el.size.height / 2;
    final rad = el.rotation * math.pi / 180.0;
    final cosA = math.cos(rad).abs();
    final sinA = math.sin(rad).abs();
    final newW = el.size.width * cosA + el.size.height * sinA;
    final newH = el.size.width * sinA + el.size.height * cosA;
    return Rect.fromCenter(center: Offset(cx, cy), width: newW, height: newH);
  }

  // 复合组件内容的外接矩形（含子元素旋转后的范围）。
  Rect _compositeBoundsRect(UIComposite composite) {
    if (composite.children.isEmpty) return Rect.zero;
    Rect? bounds;
    for (final child in composite.children) {
      final aabb = _childRotatedAABB(child);
      bounds = (bounds == null) ? aabb : bounds.expandToInclude(aabb);
    }
    return bounds ?? Rect.zero;
  }

  Size? _compositeBounds(UIComposite composite) {
    final rect = _compositeBoundsRect(composite);
    if (rect.width <= 0 || rect.height <= 0) return null;
    return Size(rect.width, rect.height);
  }

  // 从资产库拖出一个已保存的复合组件到画布。
  void _addCompositeAt(UIComposite composite, Offset canvasOffset) {
    setState(() {
      final bounds = _compositeBoundsRect(composite);
      final initialSize = (bounds.width > 0 && bounds.height > 0)
          ? Size(bounds.width, bounds.height)
          : const Size(200, 120);

      // 子元素 offset 平移到外接矩形左上角，使内容从 (0,0) 开始。
      // 这样 Stack(0,0)-(w,h) 正好对齐内容范围，边框不再错位。
      final adjustedChildren = composite.children.map((c) => c.copyWith(
        offset: Offset(c.offset.dx - bounds.left, c.offset.dy - bounds.top),
      )).toList();

      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: true,
        module: null,
        composite: composite.copyWith(children: adjustedChildren),
        offset: canvasOffset,
        size: initialSize,
        layerIndex: _activeLayerIndex,
      );

      _compositeWorkspaceElements.add(newElement);

      _selectedTransformationId = newElement.id;
      _transformHandleRotateMode = false;

      _showLeftDrawer = false;
      _showRightDrawer = false;
      _showLayerManager = false;
      _showConstructionManager = false;
    });
  }

  Size _minElementSize(UIElement el) {
    final type = el.module?.type;
    if (type == 'progress') return const Size(8, 2);
    if (type == 'button') return const Size(4, 4);
    if (type == 'input') return const Size(4, 4);
    if (type == 'text') return const Size(8, 8);
    if (type == 'surface') return const Size(4, 4);
    if (type == 'surface_art') return const Size(12, 12);
    if (type == 'light_effect') return const Size(8, 8);
    if (type == 'primitive_art') return const Size(4, 1);
    if (type == 'slider') return const Size(20, 8);
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
    if (module.type == 'light_effect') return UIModuleShape.circle;
    if (module.type == 'primitive_art') return UIModuleShape.rectangle;
    if (module.type == 'slider') return UIModuleShape.capsule;
    return module.shape;
  }

  double _outlineBorderRadiusOf(UIElement el) {
    final module = el.module;
    if (module == null) return 12;
    if (module.type == 'progress') return 999;
    return module.borderRadius;
  }

  // 更新元素几何。
  //
  // UI 创作需要允许同级重叠：例如表面 + 高光 + 光效、按钮底板 + 文本 + 热区。
  // 因此这里不再强制同层避碰，显示上下关系由 layerIndex + 构造层/元素列表顺序决定。
  void _updateElementGeometry(String id, Offset newOffset, Size newSize) {
    setState(() {
      final list = _currentElements;
      final index = list.indexWhere((e) => e.id == id);
      if (index == -1) return;

      final targetEl = list[index];
      list[index] = targetEl.copyWith(offset: newOffset, size: newSize);
    });
  }

  void _updateElementRotation(String id, double rotation) {
    setState(() {
      final list = _currentElements;
      final index = list.indexWhere((e) => e.id == id);
      if (index == -1) return;
      list[index] = list[index].copyWith(rotation: rotation);
    });
  }

  // 旋转吸附：接近 90° 整数倍(误差 ≤5°)时吸附，方便摆正。
  double _snapRotation(double deg) {
    final snapped = ((deg / 90).round()) * 90.0;
    if ((deg - snapped).abs() <= 5.0) return snapped;
    return deg;
  }

  void _deleteElement(String id) {
    setState(() {
      _compositeWorkspaceElements.removeWhere((e) => e.id == id);
      if (_selectedTransformationId == id) {
        _selectedTransformationId = null;
        _transformHandleRotateMode = false;
      }
    });
  }

  void _deleteSelectedElement() {
    final id = _selectedTransformationId;
    if (id == null) return;
    _deleteElement(id);
  }

  void _moveSelectedElementOrder(int delta) {
    final id = _selectedTransformationId;
    if (id == null) return;
    setState(() {
      final list = _currentElements;
      final index = list.indexWhere((e) => e.id == id);
      if (index == -1) return;
      final target = (index + delta).clamp(0, list.length - 1);
      if (target == index) return;
      final el = list.removeAt(index);
      list.insert(target, el);
    });
  }

  // 高雅通透模组规格配置窗
  void _showTailoredPrecisionEditorDialog(UIElement el) {
    final bool isComp = el.isComposite;
    String name = isComp ? (el.composite?.name ?? '') : (el.module?.name ?? '');
    Color color = (isComp ? el.composite?.color : el.module?.color) ?? Colors.white;
    UIModuleShape shape = (!isComp ? el.module?.shape : null) ?? UIModuleShape.rounded;
    UIModuleMaterial material = (isComp ? el.composite?.material : el.module?.material) ?? UIModuleMaterial.glass;
    double opacity = ((isComp ? el.composite?.opacity : el.module?.opacity) ?? 1.0).clamp(0.0, 1.0).toDouble();
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex)
          ? _activeLayerIndex
          : _sceneLayers.first.id;
    }

    Map<String, dynamic> props = Map.from(!isComp ? (el.module?.properties ?? {}) : {});
    // 归一到 (-180, 180]，保证滑块与显示一致，且 270 与 -90 等价。
    double rotation =
        ((el.rotation + 180) % 360 + 360) % 360 - 180;
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

                    const Text('模块所属独立 Z 轴图层（控制大层级显示顺序）', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('透明度 / 融合强度', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        Text('${(opacity * 100).round()}%', style: const TextStyle(fontSize: 11, color: Color(0xFF888896), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: opacity,
                      min: 0.05,
                      max: 1.0,
                      divisions: 19,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) => setDialogState(() => opacity = v),
                    ),
                    const Text('提示：当前不再提供自动重叠融合；如需柔和过渡，请通过透明度或颜色渐变设计实现。', style: TextStyle(fontSize: 10, color: Color(0xFF888896), height: 1.25)),
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
                                    DropdownMenuItem(value: UIModuleShape.circle, child: Text('椭圆 / 正圆')),
                                  ],
                                  onChanged: (v) => setDialogState(() => shape = v ?? UIModuleShape.rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // 旋转角度（围绕元素中心）。对原子 / 复合块均生效。
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('旋转角度 (绕中心)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${rotation.round()}°', style: const TextStyle(fontSize: 11, color: Color(0xFF888896), fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => setDialogState(() => rotation = 0.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFFFF4081).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Text('复位', style: TextStyle(fontSize: 10, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0),
                      min: -180,
                      max: 180,
                      divisions: 360,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) => setDialogState(() => rotation = v),
                    ),
                    const Text('提示：画布上拖右下角把手(青色旋转模式)可自由旋转，接近水平/垂直会自动吸附。', style: TextStyle(fontSize: 10, color: Color(0xFF888896), height: 1.25)),
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
                          updatedProps = _syncArtModuleProperties(
                            module: el.module!,
                            props: updatedProps,
                            color: color,
                            opacity: opacity,
                            shape: shape,
                            material: material,
                            borderRadius: el.module!.borderRadius,
                          );
                          final newMod = el.module!.copyWith(
                            name: name, color: color, shape: shape, material: material, opacity: opacity, properties: updatedProps,
                          );
                          list[index] = el.copyWith(module: newMod, layerIndex: selectedLayer, rotation: rotation);
                        } else {
                          final newComp = el.composite!.copyWith(name: name, color: color, material: material, opacity: opacity);
                          list[index] = el.copyWith(composite: newComp, layerIndex: selectedLayer, rotation: rotation);
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

  Widget _buildFloatingObjectAction({
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 5,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: foreground, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elementOrder = <String, int>{};
    for (var i = 0; i < _currentElements.length; i++) {
      elementOrder[_currentElements[i].id] = i;
    }
    final sortedElements = _currentElements.toList()
      ..sort((a, b) {
        final layer = a.layerIndex.compareTo(b.layerIndex);
        if (layer != 0) return layer;
        return (elementOrder[a.id] ?? 0).compareTo(elementOrder[b.id] ?? 0);
      });
    const double rightDrawerWidth = 160.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      body: Stack(
        children: [
          // 1. 无限绝对跟手工作台面底壳
          Positioned.fill(
            child: DragTarget<_DragPayload>(
              key: _canvasDropKey,
              onAcceptWithDetails: (details) {
                final box = _canvasDropKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(details.offset);
                final payload = details.data;
                final Size payloadSize;
                if (payload.module != null) {
                  payloadSize = _initialSizeForModule(payload.module!);
                } else if (payload.composite != null) {
                  payloadSize = _compositeBounds(payload.composite!) ??
                      const Size(200, 120);
                } else {
                  payloadSize = const Size(150, 68);
                }
                // 拖拽落点以模块中心为准，换算回工作台坐标。
                final canvasOffset = local -
                    _workspaceOffset -
                    Offset(payloadSize.width / 2, payloadSize.height / 2);
                if (payload.module != null) {
                  _addElementAt(payload.module!, canvasOffset);
                } else if (payload.composite != null) {
                  _addCompositeAt(payload.composite!, canvasOffset);
                }
              },
              builder: (context, candidateData, rejectedData) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() => _workspaceOffset += details.delta);
                  },
                  onTap: () => setState(() => _selectedTransformationId = null),
                  child: ClipRect(
                    child: CustomPaint(
                      painter: StudioWarmGridPainter(_workspaceOffset),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 真实模块层：直接换算为屏幕坐标，避免超大 Transform 画布造成 hitTest 坐标落在 Stack 尺寸外。
                          ...sortedElements.map((el) {
                            final double p = el.id == _selectedTransformationId ? 20.0 : 0.0;
                            return Positioned(
                              left: _workspaceOffset.dx + el.offset.dx - p,
                              top: _workspaceOffset.dy + el.offset.dy - p,
                              width: el.size.width + p * 2,
                              height: el.size.height + p * 2,
                              child: _buildTrueSingleHandleNode(el, p),
                            );
                          }),

                          // 当前编辑层辅助层：只把“层号角标 + 细白灰虚线边界”置顶，
                          // 不改变模块本体层级，避免破坏真实预览。
                          ...sortedElements
                              .where((el) => el.layerIndex == _activeLayerIndex)
                              .map((el) {
                            final bool selected = el.id == _selectedTransformationId;
                            return Positioned(
                              // 辅助层不再外扩覆盖模块颜色；只在元素原始边界内绘制细虚线。
                              left: _workspaceOffset.dx + el.offset.dx,
                              top: _workspaceOffset.dy + el.offset.dy - 18,
                              width: el.size.width,
                              height: el.size.height + 18,
                              child: _buildActiveLayerLocatorOverlay(el, selected),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
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

          // 右上角：图层管理
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.92),
                foregroundColor: const Color(0xFF111116),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                elevation: 4,
              ),
              icon: const Icon(Icons.layers_rounded, size: 18),
              label: Text('图层 (Level $_activeLayerIndex)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => setState(() { _showLayerManager = true; _showConstructionManager = false; _showRightDrawer = false; }),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 68,
            right: 16,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.92),
                foregroundColor: const Color(0xFF111116),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                elevation: 4,
              ),
              icon: const Icon(Icons.view_list_rounded, size: 18),
              label: const Text('构造层', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => setState(() {
                _showConstructionManager = true;
                _showLayerManager = false;
                _showRightDrawer = false;
              }),
            ),
          ),

          if (_selectedTransformationId != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 120,
              right: 16,
              child: Column(
                children: [
                  _buildFloatingObjectAction(
                    icon: Icons.keyboard_arrow_up_rounded,
                    background: const Color(0xFF111116),
                    foreground: Colors.white,
                    onTap: () => _moveSelectedElementOrder(1),
                  ),
                  const SizedBox(height: 8),
                  _buildFloatingObjectAction(
                    icon: Icons.keyboard_arrow_down_rounded,
                    background: const Color(0xFF111116),
                    foreground: Colors.white,
                    onTap: () => _moveSelectedElementOrder(-1),
                  ),
                  const SizedBox(height: 8),
                  _buildFloatingObjectAction(
                    icon: Icons.delete_outline_rounded,
                    background: const Color(0xFFFF4081),
                    foreground: Colors.white,
                    onTap: _deleteSelectedElement,
                  ),
                ],
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

          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            right: _showConstructionManager ? 0 : -260,
            top: 120, bottom: 120,
            width: 240,
            child: _buildAtomicConstructionDrawer(),
          ),

          // 6. 左侧原材料抽屉
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
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomRight: Radius.circular(14)),
                    border: Border.all(color: Colors.black12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF111116)),
                ),
              ),
            ),

          // 7. 右侧已完成资产抽屉
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            right: _showRightDrawer ? 0 : -rightDrawerWidth,
            top: 120, bottom: 120,
            width: rightDrawerWidth,
            child: _buildRightCompletedAssetsDrawer(),
          ),

          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4081),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.22),
              ),
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              onPressed: _showSaveMenu,
            ),
          ),

          if (!_showRightDrawer && !_showLayerManager && !_showConstructionManager)
            Positioned(
              right: 0,
              top: MediaQuery.of(context).size.height / 2 - 24,
              child: GestureDetector(
                onTap: () => setState(() => _showRightDrawer = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                    border: Border.all(color: Colors.black12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF111116)),
                ),
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
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('原材料', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13)),
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
                    const Text('容器边界框', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'box', name: '容器边界框', type: 'base_box', properties: {}, color: Colors.cyan),
                      Container(height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: const Color(0xFF00ACC1).withValues(alpha: 0.08)), child: const Center(child: Text('📦 拖出边界框', style: TextStyle(color: Color(0xFF00ACC1), fontSize: 11, fontWeight: FontWeight.bold)))),
                    ),
                    const Divider(color: Colors.black12),

                    const Text('数据条原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'prog', name: '数据条原子', type: 'progress', properties: {'min': 0, 'max': 100, 'current': 75}, color: const Color(0xFFFF4081)),
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
                    const Text('面原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'surface', name: '面原子 / 胶囊', type: 'surface', properties: {}, color: const Color(0xFF651FFF), material: UIModuleMaterial.gradient, shape: UIModuleShape.capsule),
                      Container(height: 34, decoration: BoxDecoration(color: const Color(0xFF651FFF), borderRadius: BorderRadius.circular(999))),
                    ),

                    const SizedBox(height: 10),
                    const Text('点击热区原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'btn', name: '点击热区原子', type: 'button', properties: {'action': 'tap'}, color: Colors.transparent),
                      Container(height: 34, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFF4081), width: 1), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const Text('点击热区', style: TextStyle(color: Color(0xFFFF4081), fontSize: 10, fontWeight: FontWeight.bold))),
                    ),

                    const SizedBox(height: 10),
                    const Text('文本原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'txt', name: '文本原子', type: 'text', properties: {'text': '文本'}, color: const Color(0xFF00B0FF)),
                      const SizedBox(height: 30, child: Center(child: Text('文本', style: TextStyle(color: Color(0xFF00B0FF), fontSize: 12, fontWeight: FontWeight.bold)))),
                    ),

                    const SizedBox(height: 10),
                    const Text('滑块原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'slider', name: '滑块原子', type: 'slider', properties: {'min': 0, 'max': 100, 'current': 50}, color: const Color(0xFF00ACC1)),
                      SizedBox(
                        height: 34,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(height: 5, margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: const Color(0xFFE2E2E8), borderRadius: BorderRadius.circular(99))),
                            Container(height: 5, width: 62, margin: const EdgeInsets.only(left: 10), decoration: BoxDecoration(color: const Color(0xFF00ACC1), borderRadius: BorderRadius.circular(99))),
                            Positioned(left: 58, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: const Color(0xFF00ACC1), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    const Text('输入热区原子预览', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                    const SizedBox(height: 4),
                    _buildPreviewDraggableCard(
                      UIModule(id: 'inp', name: '输入热区原子', type: 'input', properties: {'variable': 'var.input'}, color: Colors.transparent),
                      Container(height: 34, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00ACC1), width: 1), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: const Text('输入热区', style: TextStyle(color: Color(0xFF00ACC1), fontSize: 10, fontWeight: FontWeight.bold))),
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
    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: visualPreview,
    );

    // LongPressDraggable：触摸短滑 → 列表滚动；长按后拖 → 生成到画布。
    // 鼠标仍可直接按下即拖。delay 调到 180ms 兼顾响应与防误触。
    return LongPressDraggable<_DragPayload>(
      data: _DragPayload(module: module),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.88,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: card,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: card,
      ),
    );
  }


  Widget _buildAtomicConstructionDrawer() {
    final bakeable = _currentElements.where(_isBakeableElement).length;
    final total = _currentElements.length;
    final notBakeable = total - bakeable;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                      onTap: () => setState(() => _showConstructionManager = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF00ACC1)),
                            Text(' 收回', style: TextStyle(fontSize: 10, color: Color(0xFF00ACC1), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const Text('元素列表', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                  ),
                  child: Text(
                    '可烘焙 $bakeable 层 · 不参与 $notBakeable 层',
                    style: TextStyle(
                      color: notBakeable > 0 ? const Color(0xFFFF8F00) : const Color(0xFF00A86B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(
                  '可将视觉层烘焙为新的面原子；文本/数据/交互层暂不参与烘焙。',
                  style: TextStyle(fontSize: 10, color: Color(0xFF888896), height: 1.25),
                ),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: _currentElements.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18.0),
                          child: Text(
                            '还没有构造层。\n从左侧拖入面、数据条、文本等原材料。',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Color(0xFF888896), height: 1.35),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        itemCount: _currentElements.length,
                        itemBuilder: (context, index) {
                          final el = _currentElements[index];
                          final selected = _selectedTransformationId == el.id;
                          final bake = _isBakeableElement(el);
                          final name = el.module?.name ?? el.composite?.name ?? '未命名层';
                          return Card(
                            color: selected ? const Color(0xFF111116) : const Color(0xFFF6F6F9),
                            elevation: selected ? 3 : 0,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: selected ? const Color(0xFF00E5FF) : Colors.black.withValues(alpha: 0.04),
                                width: selected ? 1.4 : 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _selectedTransformationId = el.id),
                              onLongPress: () => _showTailoredPrecisionEditorDialog(el),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: bake ? const Color(0xFF00C853) : const Color(0xFFFF8F00),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            bake ? '烘焙' : '跳过',
                                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: selected ? Colors.white : const Color(0xFF111116),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_elementTypeLabel(el)} · L${el.layerIndex} · ${el.size.width.toStringAsFixed(0)}×${el.size.height.toStringAsFixed(0)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected ? Colors.white70 : const Color(0xFF777783),
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        _buildLayerMiniButton(Icons.keyboard_arrow_up_rounded, () => _moveAtomicConstructionLayer(el.id, -1), selected),
                                        _buildLayerMiniButton(Icons.keyboard_arrow_down_rounded, () => _moveAtomicConstructionLayer(el.id, 1), selected),
                                        _buildLayerMiniButton(Icons.tune_rounded, () => _showTailoredPrecisionEditorDialog(el), selected),
                                        _buildLayerMiniButton(Icons.delete_outline_rounded, () => _deleteElement(el.id), selected, danger: true),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerMiniButton(IconData icon, VoidCallback onTap, bool selected, {bool danger = false}) {
    final color = danger ? const Color(0xFFFF4081) : (selected ? Colors.white : const Color(0xFF555562));
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildRightCompletedAssetsDrawer() {
    final modules = _assetService.getAllModules();
    final composites = _assetService.getAllComposites();
    final isEmpty = modules.isEmpty && composites.isEmpty;

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
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                child: isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18.0),
                          child: Text(
                            '还没有保存的资产。\n在工作台拖入积木后点「保存」即可入库。',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Color(0xFF888896), height: 1.35),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        children: [
                          ...modules.map(_buildAssetLibraryModuleCard),
                          if (composites.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 10, 4, 2),
                              child: Text('复合组件', style: TextStyle(color: Color(0xFF888896), fontSize: 10)),
                            ),
                            ...composites.map(_buildAssetLibraryCompositeCard),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetLibraryModuleCard(UIModule module) {
    final card = Card(
      color: const Color(0xFFF6F6F9),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: ListTile(
        title: Text(
          module.name,
          style: const TextStyle(color: Color(0xFF111116), fontSize: 11, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _elementTypeLabel(UIElement(id: 'preview_${module.id}', isComposite: false, module: module)),
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: const Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFF00E676)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return LongPressDraggable<_DragPayload>(
      data: _DragPayload(module: module),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 150,
          child: Opacity(opacity: 0.9, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: card,
    );
  }

  Widget _buildAssetLibraryCompositeCard(UIComposite composite) {
    final card = Card(
      color: const Color(0xFFF3E5F5),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        title: Text(
          composite.name,
          style: const TextStyle(color: Color(0xFF111116), fontSize: 11, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '复合组件 · ${composite.children.length} 个子元素',
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: const Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFF651FFF)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return LongPressDraggable<_DragPayload>(
      data: _DragPayload(composite: composite),
      delay: const Duration(milliseconds: 180),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 150,
          child: Opacity(opacity: 0.9, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.38, child: card),
      child: card,
    );
  }

  /// 当前编辑层的置顶定位辅助层。
  ///
  /// 未选中时只绘制层号小角标；选中时额外绘制元素边界内侧的白灰交替细虚线。
  /// 不加阴影、不加半透明蒙版、不重新渲染模块本体，避免影响原始颜色判断。
  /// 整体 IgnorePointer，避免遮挡原有拖拽、缩放、删除等交互命中。
  Widget _buildActiveLayerLocatorOverlay(UIElement el, bool selected) {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 18,
              width: el.size.width,
              height: el.size.height,
              child: Transform.rotate(
                // 选中虚线框与模块本体一起旋转，反馈与实际一致。
                // Transform.rotate 默认绕自身中心，此处即元素中心。
                angle: el.rotation * math.pi / 180.0,
                child: CustomPaint(
                  painter: StudioAlternatingDashedBorderPainter(
                    strokeWidth: 1.2,
                    shape: _outlineShapeOf(el),
                    borderRadius: _outlineBorderRadiusOf(el),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),

          // 未选中时只显示层号；选中时额外显示细白灰虚线外框。
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
        setState(() {
          if (_selectedTransformationId != el.id) {
            _transformHandleRotateMode = false;
          }
          _selectedTransformationId = el.id;
        });
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
            onTap: () {
              setState(() => _transformHandleRotateMode = !_transformHandleRotateMode);
            },
            onPanStart: (details) {
              _startTouchWidth = el.size.width;
              _startTouchHeight = el.size.height;
              _startTouchGlobalPos = details.globalPosition;
              if (_transformHandleRotateMode) {
                // 旋转中心 = 画布上元素的中心点。拖拽过程中 offset/size 不变，
                // 故中心恒定，按下时算一次即可。
                _rotationCenter = Offset(
                  _workspaceOffset.dx + el.offset.dx + el.size.width / 2,
                  _workspaceOffset.dy + el.offset.dy + el.size.height / 2,
                );
                _startHandleAngle =
                    (details.globalPosition - _rotationCenter).direction;
                _startRotation = el.rotation;
              }
            },
            onPanUpdate: (details) {
              if (_transformHandleRotateMode) {
                final currentAngle =
                    (details.globalPosition - _rotationCenter).direction;
                var delta = currentAngle - _startHandleAngle;
                // 角度差归一到 [-π, π]，避免跨过 ±π 时突然反转。
                while (delta > math.pi) {
                  delta -= 2 * math.pi;
                }
                while (delta < -math.pi) {
                  delta += 2 * math.pi;
                }
                var newRot = _startRotation + delta * 180 / math.pi;
                newRot = _snapRotation(newRot);
                _updateElementRotation(el.id, newRot);
                return;
              }
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
                decoration: BoxDecoration(
                  color: _transformHandleRotateMode ? const Color(0xFF00E5FF) : const Color(0xFFFF4081),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Icon(
                  _transformHandleRotateMode ? Icons.rotate_right_rounded : Icons.open_with,
                  size: 12,
                  color: _transformHandleRotateMode ? const Color(0xFF111116) : Colors.white,
                ),
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

    final greyPaint = Paint()
      ..color = const Color(0xFFB8B8C2).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
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
        canvas.drawPath(dashPath, drawWhite ? whitePaint : greyPaint);
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
