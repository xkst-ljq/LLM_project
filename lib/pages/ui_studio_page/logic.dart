part of 'ui_studio_page.dart';

/// 业务逻辑：持久化、图层管理、元素 CRUD、烘焙
mixin _UIStudioLogic on State<UIStudioPage> {
  static const int _maxSceneLayerCount = 64;

  final UIAssetService _assetService = UIAssetService();
  final GlobalKey _canvasDropKey = GlobalKey();

  List<UIElement> _atomicWorkspaceElements = [];
  List<UIElement> _compositeWorkspaceElements = [];
  Offset _workspaceOffset = Offset.zero;

  List<LayerScene> _sceneLayers = [LayerScene(id: 0, name: '图层 Level 0')];
  int _activeLayerIndex = 0;

  // UI 交互状态（原在主文件中，为跨 mixin 共享移至此）
  bool _showLayerManager = false;
  bool _showConstructionManager = false;
  bool _showLeftDrawer = false;
  bool _showRightDrawer = false;
  String? _selectedTransformationId;
  bool _transformHandleRotateMode = false;
  bool _isLinkingMode = false;

  List<UIElement> get _currentElements => _compositeWorkspaceElements;

  // ===== 持久化 =====
  Future<void> _loadWorkspaces() async {
    final prefs = await SharedPreferences.getInstance();

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
        _atomicWorkspaceElements =
            list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    final compositeData = prefs.getString('ui_studio_composite_workspace_v4');
    if (compositeData != null) {
      try {
        final List list = jsonDecode(compositeData);
        _compositeWorkspaceElements =
            list.map((e) => UIElement.fromJson(e)).toList();
      } catch (_) {}
    }

    if (_compositeWorkspaceElements.isEmpty &&
        _atomicWorkspaceElements.isNotEmpty) {
      _compositeWorkspaceElements = List.from(_atomicWorkspaceElements);
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

      final atomicData =
          jsonEncode(_atomicWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_atomic_workspace_v4', atomicData);

      final compositeData =
          jsonEncode(_compositeWorkspaceElements.map((e) => e.toJson()).toList());
      await prefs.setString('ui_studio_composite_workspace_v4', compositeData);

      if (mounted && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('工作台草稿已保存 ✅'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  void _autoSave() => _saveWorkspaceDraft(showMessage: false);

  // ===== 图层管理 =====
  void _repairSceneLayerData() {
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '图层 Level 0')];
    }

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
          _sceneLayers.add(
            LayerScene(id: el.layerIndex, name: '图层 Level ${el.layerIndex}'),
          );
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
      _transformHandleRotateMode = false;
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
      _activeLayerIndex = newId;
      _selectedTransformationId = null;
      _transformHandleRotateMode = false;
    });
    _autoSave();
  }

  // ===== 元素几何与工具 =====
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
    if (module.type == 'linker') return const Size(170, 56);
    return const Size(150, 68);
  }

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
      _showLeftDrawer = false;
      _showRightDrawer = false;
      _showLayerManager = false;
      _showConstructionManager = false;
    });
    _autoSave();
  }

  Rect _childRotatedAABB(UIElement el) {
    if (el.rotation == 0.0) {
      return Rect.fromLTWH(
        el.offset.dx,
        el.offset.dy,
        el.size.width,
        el.size.height,
      );
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

  void _addCompositeAt(UIComposite composite, Offset canvasOffset) {
    setState(() {
      if (composite.children.length == 1) {
        final child = composite.children.first;
        final newElement = UIElement(
          id: 'el_${DateTime.now().millisecondsSinceEpoch}',
          isComposite: true,
          module: null,
          composite: composite.copyWith(
            children: [child.copyWith(rotation: 0.0)],
          ),
          offset: canvasOffset,
          size: child.size,
          rotation: child.rotation,
          layerIndex: _activeLayerIndex,
        );
        _compositeWorkspaceElements.add(newElement);
        _selectedTransformationId = newElement.id;
      } else {
        final baseTime = DateTime.now().millisecondsSinceEpoch;
        String? lastId;
        for (var i = 0; i < composite.children.length; i++) {
          final child = composite.children[i];
          final elOffset = Offset(
            canvasOffset.dx + child.offset.dx,
            canvasOffset.dy + child.offset.dy,
          );
          final newElement = UIElement(
            id: 'el_${baseTime}_$i',
            isComposite: child.isComposite,
            module: child.module?.copyWith(),
            composite: child.composite?.copyWith(
              children: child.composite!.children.map((c) => c.copyWith()).toList(),
            ),
            offset: elOffset,
            size: child.size,
            rotation: child.rotation,
            layerIndex: _activeLayerIndex,
          );
          _compositeWorkspaceElements.add(newElement);
          lastId = newElement.id;
        }
        _selectedTransformationId = lastId;
      }
      _transformHandleRotateMode = false;
      _showLeftDrawer = false;
      _showRightDrawer = false;
      _showLayerManager = false;
      _showConstructionManager = false;
    });
    _autoSave();
  }

  UIModuleShape _outlineShapeOf(UIElement el, [int depth = 0]) {
    if (el.isComposite && el.composite != null) {
      if (el.composite!.children.length == 1 && depth < 8) {
        return _outlineShapeOf(el.composite!.children.first, depth + 1);
      }
      return UIModuleShape.rounded;
    }
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

  double _outlineBorderRadiusOf(UIElement el, [int depth = 0]) {
    if (el.isComposite && el.composite != null) {
      if (el.composite!.children.length == 1 && depth < 8) {
        return _outlineBorderRadiusOf(el.composite!.children.first, depth + 1);
      }
      return 12;
    }
    final module = el.module;
    if (module == null) return 12;
    if (module.type == 'progress') return 999;
    return module.borderRadius;
  }

  void _deleteElement(String id) {
    setState(() {
      _compositeWorkspaceElements.removeWhere((e) => e.id == id);
      if (_selectedTransformationId == id) {
        _selectedTransformationId = null;
        _transformHandleRotateMode = false;
      }
    });
    _autoSave();
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
    _autoSave();
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
    _autoSave();
  }

  // ===== 烘焙与资产 =====
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
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          el.offset.dx,
          el.offset.dy,
          el.size.width,
          el.size.height,
        ),
      );
    }
    return bounds.width > 0 && bounds.height > 0 ? bounds : null;
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
      case 'linker':
        return '联动器';
      default:
        return type;
    }
  }

  Future<void> _saveCurrentWorkspaceAsComposite() async {
    if (_currentElements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前工作台没有可保存的元素。'),
          backgroundColor: Color(0xFFFF8F00),
        ),
      );
      return;
    }

    final assetName = await _askAssetName(
      title: '保存为复合组件',
      initialValue: '未命名复合组件',
    );
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
        SnackBar(
          content: Text('已保存为复合组件：$assetName ✅'),
          backgroundColor: const Color(0xFF00C853),
        ),
      );
    }
  }

  Future<void> _bakeCurrentWorkspaceAsAtom() async {
    if (_bakeAtomicWorkspaceToModule() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可烘焙的视觉层。'),
          backgroundColor: Color(0xFFFF8F00),
        ),
      );
      return;
    }

    final assetName = await _askAssetName(
      title: '烘焙为面原子',
      initialValue: '面原子 / 自定义',
    );
    if (assetName == null) return;
    final baked = _bakeAtomicWorkspaceToModule(name: assetName);
    if (baked == null) return;

    await _saveWorkspaceDraft(showMessage: false);
    _assetService.addModule(baked);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已烘焙为面原子：${baked.name} ✅'),
          backgroundColor: const Color(0xFF00C853),
        ),
      );
    }
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
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          el.offset.dx,
          el.offset.dy,
          el.size.width,
          el.size.height,
        ),
      );
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

  List<UIPrimitiveLayer> _bakeElementToPrimitiveLayers(
    UIElement el,
    Rect bounds,
  ) {
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

    Size normalizeSize(Size absolute) =>
        Size(absolute.width / bounds.width, absolute.height / bounds.height);

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
          out.add(
            normalizeLayer(
              UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw)),
            ),
          );
        }
      }
      return out;
    }

    return const [];
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
    if (type != 'surface_art' &&
        type != 'primitive_art' &&
        type != 'light_effect') {
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
      final shouldUpdate =
          !updatedOne &&
          ((type == 'surface_art' && layer.kind == 'surface') ||
              (type == 'light_effect' &&
                  (layer.kind == 'glow' || layer.kind == 'surface')) ||
              (type == 'primitive_art' &&
                  (layer.kind == 'line' ||
                      layer.kind == 'stroke' ||
                      layer.kind == 'surface')));
      if (!shouldUpdate) {
        updatedLayers.add(layer.toJson());
        continue;
      }

      final layerProps = Map<String, dynamic>.from(layer.properties);
      layerProps['material'] = material.index;
      updatedLayers.add(
        UIPrimitiveLayer(
          id: layer.id,
          kind: layer.kind,
          offset: layer.offset,
          size: layer.size,
          color: color,
          opacity: opacity,
          shape: shape,
          borderRadius: borderRadius,
          properties: layerProps,
        ).toJson(),
      );
      updatedOne = true;
    }

    props['layers'] = updatedLayers;
    return props;
  }

  // ===== 命名输入框（原在 dialogs.dart，为跨 mixin 共享移至此） =====
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF111116),
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFF111116)),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF2F2F6),
              hintText: initialValue,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '取消',
                style: TextStyle(color: Color(0xFF888896)),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4081),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(
                '保存',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  // ===== 联动器数据查询（原在 linker.dart，为跨 mixin 共享移至此） =====
  List<Map<String, String>> _getLinkableSourceModules() {
    return _currentElements
        .where((el) => !el.isComposite && el.module != null)
        .where((el) => ['progress', 'slider'].contains(el.module!.type))
        .map((el) => {
              'id': el.id,
              'name': el.module!.name,
              'type': el.module!.type,
            })
        .toList();
  }

  List<Map<String, String>> _getLinkableTargetModules() {
    return _currentElements
        .where((el) => !el.isComposite && el.module != null)
        .where((el) => ['text'].contains(el.module!.type))
        .map((el) => {
              'id': el.id,
              'name': el.module!.name,
              'type': el.module!.type,
            })
        .toList();
  }
}
