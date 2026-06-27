part of 'ui_studio_page.dart';

// ignore_for_file: use_build_context_synchronously

/// 核心逻辑：状态字段、工作区管理、元素增删改
mixin _UIStudioLogic on State<UIStudioPage> {
  // ============================================================
  //  状态字段
  // ============================================================
  final GlobalKey _canvasDropKey = GlobalKey();
  final UIAssetService _assetService = UIAssetService();

  Offset _workspaceOffset = Offset.zero;
  String? _selectedTransformationId;
  bool _transformHandleRotateMode = false;
  bool _isLinkingMode = false;

  bool _showLayerManager = false;
  bool _showConstructionManager = false;
  bool _showLeftDrawer = false;
  bool _showRightDrawer = false;

  int _activeLayerIndex = 0;
  List<LayerScene> _sceneLayers = [];
  List<UIElement> _currentElements = [];

  // ============================================================
  //  工作区持久化
  // ============================================================
  Future<void> _loadWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ui_studio_workspace');
    if (saved != null && saved.isNotEmpty) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        final layers = (data['layers'] as List?)
                ?.map((e) => LayerScene.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        final elements = (data['elements'] as List?)
                ?.map((e) => UIElement.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        final offsetX = (data['offsetX'] as num?)?.toDouble() ?? 0.0;
        final offsetY = (data['offsetY'] as num?)?.toDouble() ?? 0.0;
        final activeLayer = (data['activeLayer'] as num?)?.toInt() ?? 0;

        setState(() {
          _sceneLayers = layers;
          _currentElements = elements;
          _workspaceOffset = Offset(offsetX, offsetY);
          _activeLayerIndex = activeLayer;
        });
      } catch (_) {
        _initDefaultState();
      }
    } else {
      _initDefaultState();
    }
  }

  void _initDefaultState() {
    setState(() {
      _sceneLayers = [
        LayerScene(id: 0, name: '默认图层'),
      ];
      _activeLayerIndex = 0;
      _currentElements = [];
      _workspaceOffset = Offset.zero;
    });
  }

  Future<void> _saveWorkspaceDraft({bool showMessage = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'layers': _sceneLayers.map((e) => e.toJson()).toList(),
      'elements': _currentElements.map((e) => e.toJson()).toList(),
      'offsetX': _workspaceOffset.dx,
      'offsetY': _workspaceOffset.dy,
      'activeLayer': _activeLayerIndex,
    };
    await prefs.setString('ui_studio_workspace', jsonEncode(data));
    if (showMessage) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('草稿已保存'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _autoSave() {
    _saveWorkspaceDraft(showMessage: false);
  }

  // ============================================================
  //  元素增删改
  // ============================================================
  void _addElementAt(UIModule module, Offset canvasOffset) {
    setState(() {
      _currentElements.add(UIElement(
        id: 'elem_${DateTime.now().millisecondsSinceEpoch}_${_currentElements.length}',
        module: module,
        offset: canvasOffset,
        size: _initialSizeForModule(module),
        layerIndex: _activeLayerIndex,
        isComposite: false,
      ));
    });
    _autoSave();
  }

  void _addCompositeAt(UIComposite composite, Offset canvasOffset) {
    final bounds = _compositeBounds(composite) ?? const Size(200, 120);
    setState(() {
      _currentElements.add(UIElement(
        id: 'comp_${DateTime.now().millisecondsSinceEpoch}_${_currentElements.length}',
        composite: composite,
        offset: canvasOffset,
        size: bounds,
        layerIndex: _activeLayerIndex,
        isComposite: true,
      ));
    });
    _autoSave();
  }

  void _deleteSelectedElement() {
    if (_selectedTransformationId == null) return;
    _deleteElement(_selectedTransformationId!);
  }

  void _deleteElement(String id) {
    setState(() {
      _currentElements.removeWhere((e) => e.id == id);
      if (_selectedTransformationId == id) {
        _selectedTransformationId = null;
      }
    });
    _autoSave();
  }

  void _moveSelectedElementOrder(int direction) {
    if (_selectedTransformationId == null) return;
    final idx = _currentElements.indexWhere((e) => e.id == _selectedTransformationId);
    if (idx == -1) return;
    final newIdx = (idx + direction).clamp(0, _currentElements.length - 1);
    if (newIdx == idx) return;
    setState(() {
      final el = _currentElements.removeAt(idx);
      _currentElements.insert(newIdx, el);
    });
    _autoSave();
  }

  void _moveAtomicConstructionLayer(String id, int direction) {
    final idx = _currentElements.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final newIdx = (idx + direction).clamp(0, _currentElements.length - 1);
    if (newIdx == idx) return;
    setState(() {
      final el = _currentElements.removeAt(idx);
      _currentElements.insert(newIdx, el);
    });
    _autoSave();
  }

  // ============================================================
  //  图层管理
  // ============================================================
  void _createNewSceneLayer() {
    setState(() {
      final newId = _sceneLayers.isEmpty
          ? 0
          : _sceneLayers.map((l) => l.id).reduce((a, b) => a > b ? a : b) + 1;
      _sceneLayers.add(LayerScene(id: newId, name: '图层 $newId'));
      _activeLayerIndex = newId;
    });
    _autoSave();
  }

  void _switchActiveSceneLayer(int layerId) {
    setState(() {
      _activeLayerIndex = layerId;
      _selectedTransformationId = null;
    });
  }

  // ============================================================
  //  尺寸 / 边界辅助
  // ============================================================
  Size _initialSizeForModule(UIModule module) {
    switch (module.type) {
      case 'progress':
        return const Size(150, 28);
      case 'slider':
        return const Size(150, 34);
      case 'text':
        return const Size(120, 30);
      case 'button':
        return const Size(100, 34);
      case 'input':
        return const Size(140, 34);
      case 'linker':
        return const Size(120, 42);
      case 'surface':
      case 'surface_art':
      case 'primitive_art':
        return const Size(160, 80);
      default:
        return const Size(150, 68);
    }
  }

  Size? _compositeBounds(UIComposite composite) {
    if (composite.children.isEmpty) return null;
    double maxX = 0, maxY = 0;
    for (final child in composite.children) {
      final cx = child.offset.dx + child.size.width;
      final cy = child.offset.dy + child.size.height;
      if (cx > maxX) maxX = cx;
      if (cy > maxY) maxY = cy;
    }
    return Size(maxX + 20, maxY + 20);
  }

  UIModuleShape _outlineShapeOf(UIElement el) {
    if (el.isComposite) return UIModuleShape.rounded;
    return el.module?.shape ?? UIModuleShape.rounded;
  }

  double _outlineBorderRadiusOf(UIElement el) {
    if (el.isComposite) return 12;
    return el.module?.borderRadius ?? 12;
  }

  // ============================================================
  //  元素类型标签
  // ============================================================
  String _elementTypeLabel(UIElement el) {
    if (el.isComposite) return '复合组件';
    switch (el.module?.type) {
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
      case 'linker':
        return '联动器';
      case 'surface':
      case 'surface_art':
        return '面原子';
      case 'primitive_art':
        return '基础面';
      default:
        return el.module?.type ?? '未知';
    }
  }

  bool _isBakeableElement(UIElement el) {
    if (el.isComposite) return false;
    final type = el.module?.type;
    return type == 'surface' ||
        type == 'surface_art' ||
        type == 'primitive_art' ||
        type == 'progress' ||
        type == 'slider';
  }

  // ============================================================
  //  保存相关
  // ============================================================
  Future<void> _saveCurrentWorkspaceAsComposite() async {
    final composite = UIComposite(
      id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
      name: '复合组件 ${_assetService.getAllComposites().length + 1}',
      layoutType: 'stack',
      children: List.from(_currentElements),
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.glass,
      opacity: 1.0,
    );
    _assetService.addComposite(composite);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存为复合组件')),
      );
    }
    _autoSave();
  }

  Future<void> _bakeCurrentWorkspaceAsAtom() async {
    final bakeableElements =
        _currentElements.where(_isBakeableElement).toList();
    if (bakeableElements.isEmpty) return;

    final module = UIModule(
      id: 'baked_${DateTime.now().millisecondsSinceEpoch}',
      name: '烘焙面原子 ${_assetService.getAllModules().length + 1}',
      type: 'surface_art',
      properties: {
        'baked_from': bakeableElements.map((e) => e.toJson()).toList(),
      },
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.rounded,
      opacity: 1.0,
    );
    _assetService.addModule(module);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已烘焙为面原子 (${bakeableElements.length} 层)')),
      );
    }
    _autoSave();
  }

  // ============================================================
  //  联动器数据查询
  // ============================================================
  List<Map<String, dynamic>> _getLinkableSourceModules() {
    final sources = <Map<String, dynamic>>[];
    for (final el in _currentElements) {
      if (el.isComposite) continue;
      final type = el.module?.type;
      if (type == 'progress' || type == 'slider' || type == 'input' || type == 'button') {
        sources.add({
          'id': el.id,
          'name': el.module?.name ?? '未命名',
          'type': type,
        });
      }
    }
    return sources;
  }

  List<Map<String, dynamic>> _getLinkableTargetModules() {
    final targets = <Map<String, dynamic>>[];
    for (final el in _currentElements) {
      if (el.isComposite) continue;
      final type = el.module?.type;
      if (type == 'text' || type == 'progress' || type == 'slider') {
        targets.add({
          'id': el.id,
          'name': el.module?.name ?? '未命名',
          'type': type,
        });
      }
    }
    return targets;
  }

  // ============================================================
  //  属性同步
  // ============================================================
  Map<String, dynamic> _syncArtModuleProperties({
    required UIModule module,
    required Map<String, dynamic> props,
    required Color color,
    required double opacity,
    required UIModuleShape shape,
    required UIModuleMaterial material,
    required double borderRadius,
  }) {
    return props;
  }
}
