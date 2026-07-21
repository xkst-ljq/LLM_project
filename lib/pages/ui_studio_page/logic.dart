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
  final Set<String> _elementRotateModes = <String>{};
  bool _isLinkingMode = false;
  bool _isPreviewMode = false;
  List<UIElement>? _previewElementsSnapshot;

  bool _showConstructionManager = false;
  bool _showLeftDrawer = false;
  bool _showRightDrawer = false;

  int _activeLayerIndex = 0;
  List<LayerScene> _sceneLayers = [];
  List<UIElement> _currentElements = [];

  // 工作区快照历史：保存完成态，最多保留 100 步。
  final List<String> _undoHistory = <String>[];
  final List<String> _redoHistory = <String>[];
  bool _isRestoringHistory = false;

  // 资产库 → 画布的统一放置会话：由根 Listener 的原始 PointerEvent 驱动。
  DragPayload? _activeLibraryPlacement;
  final List<StudioClipboardEntry> _clipboardHistory = <StudioClipboardEntry>[];
  StudioClipboardEntry? _pendingPaste;
  bool _isMultiDeleteMode = false;
  final Set<String> _pendingDeleteIds = <String>{};


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
        final sanitizedElements = _sanitizeLinkerElements(elements);

        setState(() {
          _sceneLayers = layers;
          _currentElements = sanitizedElements;
          _workspaceOffset = Offset(offsetX, offsetY);
          _activeLayerIndex = activeLayer;
        });
        _captureHistorySnapshot();
        _setupEventBusListener();
      } catch (_) {
        _initDefaultState();
      }
    } else {
      _initDefaultState();
    }
  }

  void _togglePreviewMode() {
    final enteringPreview = !_isPreviewMode;
    setState(() {
      if (enteringPreview) {
        _previewElementsSnapshot = _currentElements
            .map((element) => UIElement.fromJson(element.toJson()))
            .toList();
      } else if (_previewElementsSnapshot != null) {
        _currentElements = _previewElementsSnapshot!;
        _previewElementsSnapshot = null;
      }
      _isPreviewMode = enteringPreview;
      _selectedTransformationId = null;
      _showConstructionManager = false;
      _showLeftDrawer = false;
      _showRightDrawer = false;
    });
    if (!enteringPreview) _setupEventBusListener();
  }

  void _setupEventBusListener() {
    LinkerService.initEventBusListener(_currentElements, () {
      if (mounted) {
        setState(() {});
      }
    });
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
    _captureHistorySnapshot();
    _setupEventBusListener();
  }

  String _workspaceHistorySnapshot() => jsonEncode({
        'layers': _sceneLayers.map((element) => element.toJson()).toList(),
        'elements': _currentElements.map((element) => element.toJson()).toList(),
        'offsetX': _workspaceOffset.dx,
        'offsetY': _workspaceOffset.dy,
        'activeLayer': _activeLayerIndex,
      });

  void _captureHistorySnapshot() {
    if (_isRestoringHistory) return;
    final snapshot = _workspaceHistorySnapshot();
    if (_undoHistory.isNotEmpty && _undoHistory.last == snapshot) return;
    _undoHistory.add(snapshot);
    if (_undoHistory.length > 100) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  void _restoreHistorySnapshot(String snapshot) {
    try {
      final data = jsonDecode(snapshot) as Map<String, dynamic>;
      final layers = (data['layers'] as List?)
              ?.map((item) => LayerScene.fromJson(item as Map<String, dynamic>))
              .toList() ??
          <LayerScene>[];
      final elements = (data['elements'] as List?)
              ?.map((item) => UIElement.fromJson(item as Map<String, dynamic>))
              .toList() ??
          <UIElement>[];
      _isRestoringHistory = true;
      setState(() {
        _sceneLayers = layers.isEmpty ? [LayerScene(id: 0, name: '默认图层')] : layers;
        _currentElements = _sanitizeLinkerElements(elements);
        _workspaceOffset = Offset(
          (data['offsetX'] as num?)?.toDouble() ?? 0,
          (data['offsetY'] as num?)?.toDouble() ?? 0,
        );
        _activeLayerIndex = (data['activeLayer'] as num?)?.toInt() ?? 0;
        _selectedTransformationId = null;
      });
      _isRestoringHistory = false;
      _setupEventBusListener();
      _saveWorkspaceDraft(showMessage: false);
    } catch (_) {
      _isRestoringHistory = false;
    }
  }

  void _undoWorkspace() {
    if (_undoHistory.length <= 1) return;
    final current = _undoHistory.removeLast();
    _redoHistory.add(current);
    _restoreHistorySnapshot(_undoHistory.last);
  }

  void _redoWorkspace() {
    if (_redoHistory.isEmpty) return;
    final next = _redoHistory.removeLast();
    _undoHistory.add(next);
    _restoreHistorySnapshot(next);
  }

  void _showClearWorkspaceDialog() {
    var retainSurfaces = false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('清空画布'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('此操作会移除当前工作区元素，可通过撤销恢复。'),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('保留所有面板 / 容器面'),
                value: retainSurfaces,
                onChanged: (value) => setDialogState(() => retainSurfaces = value == true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B4B4B)),
              onPressed: () {
                setState(() {
                  _currentElements = retainSurfaces
                      ? _currentElements.where(_isSurfaceElement).toList()
                      : <UIElement>[];
                  _selectedTransformationId = null;
                });
                _autoSave();
                Navigator.pop(dialogContext);
              },
              child: const Text('确认清空'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWorkspaceDraft({bool showMessage = true}) async {
    _ensureContainerBoundaryMarker();
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
    _captureHistorySnapshot();
    _saveWorkspaceDraft(showMessage: false);
  }

  /// 清除断链，并将旧版或不再开放的协议重置为未配置。
  List<UIElement> _sanitizeLinkerElements(List<UIElement> elements) {
    final retainedElements = elements
        .where((element) => element.module?.type != 'scroll_frame')
        .toList();
    const surfaceTypes = {'surface', 'surface_art', 'primitive_art', 'base_box'};
    final surfaceIds = retainedElements
        .where((element) => surfaceTypes.contains(element.module?.type))
        .map((element) => element.id)
        .toSet();
    final normalizedElements = retainedElements.map((element) {
      final parentId = element.parentSurfaceId;
      if (parentId != null && !surfaceIds.contains(parentId)) {
        return element.copyWith(clearParentSurface: true);
      }
      return element;
    }).toList();
    final elementById = <String, UIElement>{
      for (final element in normalizedElements) element.id: element,
    };
    final sanitized = <UIElement>[];
    final acceptedEdges = <String, Set<String>>{};

    bool wouldCloseCycle(String sourceId, String targetId) {
      if (sourceId == targetId) return true;
      final visited = <String>{};
      bool reachesSource(String nodeId) {
        if (nodeId == sourceId) return true;
        if (!visited.add(nodeId)) return false;
        return acceptedEdges[nodeId]?.any(reachesSource) ?? false;
      }
      return reachesSource(targetId);
    }

    for (final element in normalizedElements) {
      if (element.isComposite || element.module?.type != 'linker') {
        sanitized.add(element);
        continue;
      }

      final props = Map<String, dynamic>.from(element.module!.properties);
      final linkerData = Map<String, dynamic>.from(props['linker'] ?? {});
      final sourceId = linkerData['sourceModuleId']?.toString();
      final targetId = linkerData['targetModuleId']?.toString();
      final hasSource = sourceId != null && sourceId.isNotEmpty;
      final hasTarget = targetId != null && targetId.isNotEmpty;

      if ((hasSource && !elementById.containsKey(sourceId)) ||
          (hasTarget && !elementById.containsKey(targetId))) {
        continue;
      }

      if (hasSource && hasTarget) {
        final sourceType = elementById[sourceId]?.module?.type;
        final targetType = elementById[targetId]?.module?.type;
        final scheme = linkerData['scheme']?.toString() ?? '';
        final isCompatible = LinkerMatrixEngine
            .getAvailableSchemes(sourceType, targetType)
            .any((definition) => definition.id == scheme);
        if (isCompatible && !wouldCloseCycle(sourceId, targetId)) {
          linkerData.remove('migrationNotice');
          linkerData.remove('retiredSchemeId');
          linkerData['enabled'] = true;
          acceptedEdges.putIfAbsent(sourceId, () => <String>{}).add(targetId);
        } else {
          linkerData.remove('migrationNotice');
          linkerData.remove('retiredSchemeId');
          linkerData['scheme'] = '未配置';
          linkerData.remove('schemeParams');
          linkerData['enabled'] = false;
        }
      } else {
        linkerData.remove('migrationNotice');
        linkerData.remove('retiredSchemeId');
        linkerData['scheme'] = '未配置';
        linkerData.remove('schemeParams');
        linkerData['enabled'] = false;
      }

      props['linker'] = linkerData;
      sanitized.add(
        element.copyWith(module: element.module!.copyWith(properties: props)),
      );
    }
    return sanitized;
  }

  // ============================================================
  //  元素增删改
  // ============================================================
  void _copySelectedToClipboard() {
    final id = _selectedTransformationId;
    if (id == null) {
      _showClipboardHistory();
      return;
    }
    final selected = _currentElements.where((element) => element.id == id).toList();
    if (selected.isEmpty || selected.first.sealed) return;
    final source = selected.first;
    final ids = _isSurfaceElement(source) ? _surfaceGroupIds(source.id) : <String>{source.id};
    final copied = _currentElements.where((element) => ids.contains(element.id)).where((element) {
      if (element.module?.type != 'linker') return true;
      final data = element.module!.properties['linker'] as Map?;
      return ids.contains(data?['sourceModuleId']) && ids.contains(data?['targetModuleId']);
    }).map((element) => element.toJson()).toList();
    final entry = StudioClipboardEntry(label: source.module?.name ?? source.composite?.name ?? '组件', elements: copied);
    setState(() {
      _clipboardHistory.insert(0, entry);
      if (_clipboardHistory.length > 20) _clipboardHistory.removeLast();
      _pendingPaste = entry;
    });
  }

  void _showClipboardHistory() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('复制历史'),
      content: SizedBox(width: 300, child: _clipboardHistory.isEmpty
          ? const Text('暂无复制记录')
          : ListView(shrinkWrap: true, children: _clipboardHistory.map((entry) => ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: Text(entry.label),
              subtitle: Text('${entry.elements.length} 个元素 · ${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}'),
              onTap: () { setState(() => _pendingPaste = entry); Navigator.pop(ctx); },
            )).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        if (_clipboardHistory.isNotEmpty) TextButton(onPressed: () { setState(_clipboardHistory.clear); Navigator.pop(ctx); }, child: const Text('清空历史'))],
    ));
  }

  void _pasteClipboardAt(Offset globalPosition) {
    final entry = _pendingPaste;
    final box = _canvasDropKey.currentContext?.findRenderObject() as RenderBox?;
    if (entry == null || box == null) return;
    final originals = entry.elements.map((json) => UIElement.fromJson(json)).toList();
    if (originals.isEmpty) return;
    var minX = originals.map((e) => e.offset.dx).reduce(math.min);
    var minY = originals.map((e) => e.offset.dy).reduce(math.min);
    var maxX = originals.map((e) => e.offset.dx + e.size.width).reduce(math.max);
    var maxY = originals.map((e) => e.offset.dy + e.size.height).reduce(math.max);
    final targetOrigin = box.globalToLocal(globalPosition) - _workspaceOffset - Offset((maxX - minX) / 2, (maxY - minY) / 2);
    final ids = <String, String>{};
    for (final element in originals) { ids[element.id] = 'elem_${DateTime.now().microsecondsSinceEpoch}_${ids.length}'; }
    final pasted = <UIElement>[];
    for (final old in originals) {
      final newId = ids[old.id]!;
      var module = old.module?.copyWith(id: newId);
      if (module?.type == 'linker') {
        final props = Map<String, dynamic>.from(module!.properties);
        final data = Map<String, dynamic>.from(props['linker'] ?? {});
        final src = data['sourceModuleId']?.toString(); final tgt = data['targetModuleId']?.toString();
        if (ids.containsKey(src) && ids.containsKey(tgt)) { data['sourceModuleId']=ids[src]; data['targetModuleId']=ids[tgt]; } else { continue; }
        props['linker']=data; module=module.copyWith(properties: props);
      }
      pasted.add(UIElement(id:newId,isComposite:old.isComposite,module:module,composite:old.composite,offset:targetOrigin + Offset(old.offset.dx-minX,old.offset.dy-minY),size:old.size,layerIndex:_activeLayerIndex,parentSurfaceId: old.parentSurfaceId == null ? null : ids[old.parentSurfaceId!],rotation:old.rotation,layoutLocked:old.layoutLocked,sealed:old.sealed));
    }
    // 同一复制组内始终先绘制父面，再绘制成员；保留原 copied 列表中的兄弟局部顺序。
    pasted.sort((a, b) {
      if (a.parentSurfaceId == b.id) return 1;
      if (b.parentSurfaceId == a.id) return -1;
      return 0;
    });
    setState(() { _currentElements.addAll(pasted); _selectedTransformationId = null; _pendingPaste=null; });
    _autoSave();
  }

  void _toggleMultiDeleteMode() {
    setState(() { _isMultiDeleteMode = !_isMultiDeleteMode; _pendingDeleteIds.clear(); });
  }

  void _togglePendingDelete(UIElement element) {
    if (element.sealed) return;
    setState(() { _pendingDeleteIds.contains(element.id) ? _pendingDeleteIds.remove(element.id) : _pendingDeleteIds.add(element.id); });
  }

  void _confirmPendingDelete() {
    if (_pendingDeleteIds.isEmpty) return;
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('删除 ${_pendingDeleteIds.length} 个组件？'),
      content: const Text('此操作可通过撤销恢复。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () { setState(() { _currentElements.removeWhere((e) => _pendingDeleteIds.contains(e.id) && !e.sealed); _pendingDeleteIds.clear(); _isMultiDeleteMode=false; _currentElements=_sanitizeLinkerElements(_currentElements); }); _autoSave(); Navigator.pop(ctx); }, child: const Text('确认删除'))],
    ));
  }

  void _startLibraryPlacement(DragPayload payload, Offset globalPosition) {
    _activeLibraryPlacement?.isLibraryDragging.value = false;
    payload.lastPointerGlobalPosition = globalPosition;
    payload.spawnedElementId = null;
    payload.isLibraryDragging.value = true;
    HapticFeedback.selectionClick();
    _activeLibraryPlacement = payload;
  }

  bool _isGlobalPositionInsideCanvas(Offset globalPosition) {
    final box = _canvasDropKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  /// 根 Listener 接收统一的原始 PointerMoveEvent；不再借助 DragAvatar / DragTarget 坐标。
  void _handleLibraryPlacementPointerMove(PointerMoveEvent event) {
    final payload = _activeLibraryPlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;
    if (_isGlobalPositionInsideCanvas(event.position)) {
      if (payload.spawnedElementId == null) {
        _beginDragPlacement(payload, event.position);
      } else {
        _updateDragPlacement(payload, event.position);
      }
    }
  }

  void _finishLibraryPlacementPointer(PointerEvent event) {
    final payload = _activeLibraryPlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;
    if (payload.spawnedElementId != null) {
      _finishDragPlacement(payload, event.position);
    }
    payload.isLibraryDragging.value = false;
    _activeLibraryPlacement = null;
  }

  Size _sizeForDragPayload(DragPayload payload) {
    if (payload.module != null) return _initialSizeForModule(payload.module!);
    if (payload.composite != null) {
      return _compositeBounds(payload.composite!) ?? const Size(200, 120);
    }
    return const Size(150, 68);
  }

  Offset? _canvasOffsetFromGlobalDragPosition(
    Offset globalPosition,
    DragPayload payload,
  ) {
    final box = _canvasDropKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    // DragTargetDetails.offset 可能受 Drag Avatar / feedback 锚点影响；
    // 组件定位优先使用 Draggable.onDragUpdate 记录的原始指针坐标。
    final rawPointerPosition = payload.lastPointerGlobalPosition ?? globalPosition;
    final local = box.globalToLocal(rawPointerPosition);
    final size = _sizeForDragPayload(payload);
    final anchor = Offset(
      size.width * payload.anchorFraction.dx.clamp(0.0, 1.0),
      size.height * payload.anchorFraction.dy.clamp(0.0, 1.0),
    );
    return local - _workspaceOffset - anchor;
  }

  /// 指针首次进入画布时创建真实元素；创建后不再依赖拖拽反馈位置。
  void _beginDragPlacement(DragPayload payload, Offset globalPosition) {
    if (payload.spawnedElementId != null) return;
    final offset = _canvasOffsetFromGlobalDragPosition(globalPosition, payload);
    if (offset == null) return;
    final uniqueId = 'elem_${DateTime.now().millisecondsSinceEpoch}_${_currentElements.length}';
    final size = _sizeForDragPayload(payload);
    setState(() {
      if (payload.module != null) {
        _currentElements.add(UIElement(
          id: uniqueId,
          module: payload.module!.copyWith(id: uniqueId),
          offset: offset,
          size: size,
          layerIndex: _activeLayerIndex,
          isComposite: false,
        ));
      } else if (payload.composite != null) {
        _currentElements.add(UIElement(
          id: uniqueId,
          composite: payload.composite,
          offset: offset,
          size: size,
          layerIndex: _activeLayerIndex,
          isComposite: true,
        ));
      } else {
        return;
      }
      payload.spawnedElementId = uniqueId;
      _selectedTransformationId = uniqueId;
    });
  }

  /// 已生成的元素跟随真实指针坐标，保留用户最初按住的相对位置。
  void _updateDragPlacement(DragPayload payload, Offset globalPosition) {
    final id = payload.spawnedElementId;
    if (id == null) {
      _beginDragPlacement(payload, globalPosition);
      return;
    }
    final offset = _canvasOffsetFromGlobalDragPosition(globalPosition, payload);
    if (offset == null) return;
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1) return;
    setState(() => _currentElements[index] =
        _currentElements[index].copyWith(offset: offset));
  }

  void _finishDragPlacement(DragPayload payload, Offset globalPosition) {
    _updateDragPlacement(payload, globalPosition);
    if (payload.spawnedElementId != null) _autoSave();
  }

  bool _canUseBackgroundRuntimePlacement(UIElement element) {
    // 明确白名单：只保留确有后台判断 / 状态传导价值的原子。
    const backgroundCapableTypes = {'text', 'switch', 'progress', 'indicator', 'input'};
    return !element.isComposite &&
        backgroundCapableTypes.contains(element.module?.type);
  }

  void _toggleSelectedRuntimePlacement() {
    final id = _selectedTransformationId;
    if (id == null) return;
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1) return;
    final element = _currentElements[index];
    if (!_canUseBackgroundRuntimePlacement(element) || element.module == null) return;
    final props = Map<String, dynamic>.from(element.module!.properties);
    final isBackground = props['runtimePlacement'] == 'background';
    if (isBackground) {
      props.remove('runtimePlacement');
    } else {
      props['runtimePlacement'] = 'background';
    }
    setState(() {
      _currentElements[index] = element.copyWith(
        module: element.module!.copyWith(properties: props),
      );
    });
    _autoSave();
  }

  bool _isGeometryLocked(UIElement element) =>
      element.layoutLocked || element.sealed;

  void _toggleSelectedLayoutLock() {
    final id = _selectedTransformationId;
    if (id == null) return;
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1) return;
    setState(() {
      final current = _currentElements[index];
      // 两种编辑锁互斥：布局锁 <-> 全局锁 <-> 未锁定。
      _currentElements[index] = current.layoutLocked
          ? current.copyWith(layoutLocked: false, sealed: false)
          : current.copyWith(layoutLocked: true, sealed: false);
    });
    _autoSave();
  }

  void _toggleSelectedSeal() {
    final id = _selectedTransformationId;
    if (id == null) return;
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1) return;
    setState(() {
      final current = _currentElements[index];
      _currentElements[index] = current.sealed
          ? current.copyWith(sealed: false, layoutLocked: false)
          : current.copyWith(sealed: true, layoutLocked: false);
    });
    _autoSave();
  }

  void _deleteSelectedElement() {
    if (_selectedTransformationId == null) return;
    _deleteElement(_selectedTransformationId!);
  }

  void _deleteElement(String id) {
    final existingIndex = _currentElements.indexWhere((element) => element.id == id);
    if (existingIndex != -1 && _currentElements[existingIndex].sealed) return;
    setState(() {
      _currentElements.removeWhere((e) => e.id == id);
      _currentElements = _sanitizeLinkerElements(_currentElements);
      _elementRotateModes.remove(id);
      if (_selectedTransformationId == id) {
        _selectedTransformationId = null;
      }
    });
    _autoSave();
  }

  bool _canAssignSurfaceMembership(UIElement element) {
    final type = element.module?.type;
    return !element.isComposite &&
        type != null &&
        !const {'linker', 'math_node', 'timer'}.contains(type);
  }

  bool _wouldCreateSurfaceParentCycle(String childId, String parentId) {
    var currentId = parentId;
    final visited = <String>{};
    while (currentId.isNotEmpty && visited.add(currentId)) {
      if (currentId == childId) return true;
      final index = _currentElements
          .indexWhere((element) => element.id == currentId);
      if (index == -1) return false;
      currentId = _currentElements[index].parentSurfaceId ?? '';
    }
    return false;
  }

  void _showSurfaceMembershipDialog() {
    final selectedId = _selectedTransformationId;
    if (selectedId == null) return;
    final elementIndex = _currentElements.indexWhere((element) => element.id == selectedId);
    if (elementIndex == -1) return;
    final element = _currentElements[elementIndex];
    if (!_canAssignSurfaceMembership(element)) return;

    final surfaces = _currentElements.where((candidate) {
      final type = candidate.module?.type;
      return candidate.layerIndex == element.layerIndex &&
          candidate.id != element.id &&
          const {'surface', 'surface_art', 'primitive_art', 'base_box'}
              .contains(type) &&
          !_wouldCreateSurfaceParentCycle(element.id, candidate.id);
    }).toList();
    String? selectedSurfaceId = element.parentSurfaceId;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('设置所属面'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<String?>(
                    groupValue: selectedSurfaceId,
                    onChanged: (value) =>
                        setDialogState(() => selectedSurfaceId = value),
                    child: Column(
                      children: [
                        const RadioListTile<String?>(
                          value: null,
                          title: Text('顶层元素（无所属面）'),
                        ),
                        const Divider(height: 1),
                        if (surfaces.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('当前图层没有可用的 Surface。'),
                          ),
                        ...surfaces.map(
                          (surface) => RadioListTile<String?>(
                            value: surface.id,
                            title: Text(surface.module?.name ?? surface.id),
                            subtitle: Text(_elementTypeLabel(surface)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  final index = _currentElements
                      .indexWhere((candidate) => candidate.id == element.id);
                  if (index == -1) return;
                  if (selectedSurfaceId == null) {
                    _currentElements[index] =
                        _currentElements[index].copyWith(clearParentSurface: true);
                  } else {
                    // 加入所属面时脱离原全局 Z 位置，直接排到父面组的最上层；
                    // 此后只通过组内局部排序改变与兄弟成员的前后关系。
                    final joined = _currentElements.removeAt(index)
                        .copyWith(parentSurfaceId: selectedSurfaceId);
                    final groupIds = _surfaceGroupIds(selectedSurfaceId!);
                    final lastGroupIndex = _currentElements.lastIndexWhere(
                      (candidate) => groupIds.contains(candidate.id),
                    );
                    _currentElements.insert(lastGroupIndex + 1, joined);
                  }
                });
                _autoSave();
                Navigator.pop(dialogContext);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSurfaceElement(UIElement element) =>
      const {'surface', 'surface_art', 'primitive_art', 'base_box'}
          .contains(element.module?.type);

  /// 返回一个 Surface 及其所有递归所属成员；保存成员在当前画布中的局部 Z 顺序。
  Set<String> _surfaceGroupIds(String surfaceId) {
    final ids = <String>{surfaceId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final element in _currentElements) {
        if (element.parentSurfaceId != null &&
            ids.contains(element.parentSurfaceId) &&
            ids.add(element.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  void _moveSelectedElementOrder(int direction) {
    final id = _selectedTransformationId;
    if (id == null) return;
    _moveElementWithGroupOrder(id, direction);
  }

  /// Surface 选中时移动整个所属面组；成员选中时只在自身组内局部排序。
  void _moveElementWithGroupOrder(String id, int direction) {
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1 || _currentElements[index].sealed) return;
    final selected = _currentElements[index];
    if (_isSurfaceElement(selected)) {
      _moveSurfaceGroupOrder(selected.id, direction);
    } else if (selected.parentSurfaceId != null) {
      _moveMemberWithinSurfaceGroup(selected, direction);
    } else {
      _moveStandaloneElementOrder(index, direction);
    }
  }

  void _moveStandaloneElementOrder(int index, int direction) {
    final target = (index + direction).clamp(0, _currentElements.length - 1);
    if (target == index) return;
    setState(() {
      final element = _currentElements.removeAt(index);
      _currentElements.insert(target, element);
    });
    _autoSave();
  }

  /// Surface 始终是所属面组的视觉底板，递归成员随后绘制，确保子组件位于父面上方。
  List<UIElement> _orderedSurfaceGroupElements(String surfaceId) {
    final byId = <String, UIElement>{
      for (final element in _currentElements) element.id: element,
    };
    final ordered = <UIElement>[];
    void visit(String id) {
      final surface = byId[id];
      if (surface == null) return;
      ordered.add(surface);
      for (final child in _currentElements.where((element) => element.parentSurfaceId == id)) {
        if (_isSurfaceElement(child)) {
          visit(child.id);
        } else {
          ordered.add(child);
        }
      }
    }
    visit(surfaceId);
    return ordered;
  }

  void _moveSurfaceGroupOrder(String surfaceId, int direction) {
    final groupIds = _surfaceGroupIds(surfaceId);
    final groupElements = _orderedSurfaceGroupElements(surfaceId);
    if (groupElements.isEmpty) return;
    final groupIndexes = <int>[
      for (var i = 0; i < _currentElements.length; i++)
        if (groupIds.contains(_currentElements[i].id)) i,
    ];
    final boundary = direction > 0 ? groupIndexes.last : groupIndexes.first;
    final candidateIndex = boundary + direction;
    if (candidateIndex < 0 || candidateIndex >= _currentElements.length) return;

    // 若历史草稿的组成员 Z 顺序不连续，本次组操作会将它们收拢为一个连续块。
    final others = _currentElements
        .where((element) => !groupIds.contains(element.id))
        .toList();
    final crossed = _currentElements[candidateIndex];
    final crossedIndex = others.indexWhere((element) => element.id == crossed.id);
    final insertIndex = direction > 0 ? crossedIndex + 1 : crossedIndex;
    setState(() {
      _currentElements
        ..clear()
        ..addAll(others.take(insertIndex))
        ..addAll(groupElements)
        ..addAll(others.skip(insertIndex));
    });
    _autoSave();
  }

  void _moveMemberWithinSurfaceGroup(UIElement selected, int direction) {
    final parentId = selected.parentSurfaceId;
    if (parentId == null) return;
    final parentIndex = _currentElements.indexWhere((element) => element.id == parentId);
    final selectedIndex = _currentElements.indexWhere((element) => element.id == selected.id);
    // 旧草稿中若成员被排到父面下方，第一次局部排序时先恢复“父面为底板”的基础关系。
    if (parentIndex != -1 && selectedIndex != -1 && selectedIndex < parentIndex) {
      setState(() {
        final element = _currentElements.removeAt(selectedIndex);
        _currentElements.insert(parentIndex, element);
      });
      _autoSave();
      return;
    }
    final members = _currentElements
        .where((element) => element.parentSurfaceId == parentId)
        .toList();
    final memberIndex = members.indexWhere((element) => element.id == selected.id);
    final targetMemberIndex = memberIndex + direction;
    if (memberIndex == -1 ||
        targetMemberIndex < 0 ||
        targetMemberIndex >= members.length) {
      return;
    }
    final targetId = members[targetMemberIndex].id;
    final sourceIndex = _currentElements.indexWhere((element) => element.id == selected.id);
    final targetIndex = _currentElements.indexWhere((element) => element.id == targetId);
    if (sourceIndex == -1 || targetIndex == -1) return;
    setState(() {
      final element = _currentElements.removeAt(sourceIndex);
      // removeAt 后，target 已经自然向前收缩；插入原 targetIndex 即可完成交换。
      _currentElements.insert(targetIndex, element);
    });
    _autoSave();
  }

  void _moveAtomicConstructionLayer(String id, int direction) {
    _moveElementWithGroupOrder(id, direction);
  }

  // ============================================================
  //  尺寸 / 边界辅助
  // ============================================================
  Size _initialSizeForModule(UIModule module) {
    switch (module.type) {
      case 'progress':
        return const Size(96, 16);
      case 'slider':
        return const Size(150, 34);
      case 'text':
        return const Size(120, 30);
      case 'button':
        return const Size(100, 34);
      case 'input':
        return const Size(140, 34);
      case 'switch':
        return const Size(100, 36);
      case 'line':
        return const Size(120, 20);
      case 'image':
        return const Size(80, 80);
      case 'math_node':
        return const Size(180, 44);
      case 'select':
        return const Size(140, 34);
      case 'indicator':
        return const Size(36, 36);
      case 'timer':
        return const Size(140, 54);
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
    final mod = el.module;
    if (mod == null) return UIModuleShape.rounded;
    if (mod.type == 'progress') {
      final progShape = mod.properties['progressShape']?.toString();
      if (progShape == 'rectangle') return UIModuleShape.rectangle;
      if (progShape == 'heart') return UIModuleShape.heart;
      if (progShape == 'ring') return UIModuleShape.circle;
      return UIModuleShape.capsule;
    }
    if (mod.type == 'text' || mod.type == 'input' || mod.type == 'button' || mod.type == 'line') {
      return UIModuleShape.rectangle;
    }
    if (mod.type == 'switch') {
      return UIModuleShape.capsule;
    }
    if (mod.type == 'math_node' || mod.type == 'select') {
      return UIModuleShape.rectangle;
    }
    if (mod.type == 'timer') {
      return UIModuleShape.rounded;
    }
    if (mod.type == 'indicator') {
      return UIModuleShape.circle;
    }
    if (mod.type == 'image') {
      final shapeStr = mod.properties['shape']?.toString();
      if (shapeStr == 'circle') return UIModuleShape.circle;
      if (shapeStr == 'capsule') return UIModuleShape.capsule;
      return UIModuleShape.rounded;
    }
    return mod.shape;
  }

  double _outlineBorderRadiusOf(UIElement el) {
    if (el.isComposite) return 12;
    final mod = el.module;
    if (mod == null) return 12;
    if (mod.type == 'progress') {
      final progShape = mod.properties['progressShape']?.toString();
      if (progShape == 'rectangle') return 0;
      return 999;
    }
    if (mod.type == 'text' || mod.type == 'input' || mod.type == 'button') {
      return 4;
    }
    if (mod.type == 'line') {
      return 0;
    }
    if (mod.type == 'switch') {
      return 999;
    }
    if (mod.type == 'timer') {
      return 12.0;
    }
    if (mod.type == 'math_node' || mod.type == 'select') {
      return 6.0;
    }
    if (mod.type == 'image') {
      return (mod.properties['borderRadius'] ?? 8.0).toDouble();
    }
    return mod.borderRadius;
  }

  bool _isPerfectCircleOutlineOf(UIElement el) {
    if (el.isComposite) return false;
    final mod = el.module;
    if (mod == null) return false;
    if (mod.type == 'indicator' || (mod.type == 'progress' && mod.properties['progressShape'] == 'ring')) {
      return true;
    }
    return false;
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
      case 'math_node':
        return '算术计算';
      case 'select':
        return '下拉单选';
      case 'indicator':
        return '状态指示点';
      case 'timer':
        return '定时脉冲';
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

  void _ensureContainerBoundaryMarker() {
    bool hasBoundary = false;
    for (final el in _currentElements) {
      if (el.module?.properties['is_container_boundary'] == true) {
        if (!hasBoundary) {
          hasBoundary = true;
        } else {
          el.module!.properties.remove('is_container_boundary');
        }
      }
    }
    if (!hasBoundary) {
      for (final el in _currentElements) {
        final t = el.module?.type;
        if (t == 'surface' || t == 'surface_art' || t == 'primitive_art') {
          el.module!.properties['is_container_boundary'] = true;
          break;
        }
      }
    }
  }

  UIElement? _findRootContainerSurface(List<UIElement> elements) {
    for (final el in elements) {
      if (el.module?.properties['is_container_boundary'] == true) {
        return el;
      }
    }
    for (final el in elements) {
      final t = el.module?.type;
      if (t == 'surface' || t == 'surface_art' || t == 'primitive_art') {
        return el;
      }
    }
    return null;
  }

  // ============================================================
  //  保存相关
  // ============================================================
  Future<void> _saveCurrentWorkspaceAsComposite() async {
    _ensureContainerBoundaryMarker();
    final rootSurface = _findRootContainerSurface(_currentElements);

    if (rootSurface == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存失败：当前工作台中未找到可作为组件边框底面的视觉面。'),
            backgroundColor: Color(0xFFFF8F00),
          ),
        );
      }
      return;
    }

    final rootOffset = rootSurface.offset;
    final children = _currentElements.map((el) {
      return el.copyWith(
        offset: Offset(el.offset.dx - rootOffset.dx, el.offset.dy - rootOffset.dy),
      );
    }).toList();

    final composite = UIComposite(
      id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
      name: '复合组件 ${_assetService.getAllComposites().length + 1}',
      layoutType: 'stack',
      children: children,
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
    _ensureContainerBoundaryMarker();
    final bakeableElements = _currentElements.where(_isBakeableElement).toList();
    if (bakeableElements.isEmpty) return;

    final rootSurface = _findRootContainerSurface(bakeableElements);
    if (rootSurface == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('烘焙失败：可烘焙队列中未找到作为标准外框的视觉面。'),
            backgroundColor: Color(0xFFFF8F00),
          ),
        );
      }
      return;
    }

    final rootOffset = rootSurface.offset;
    final normalizedElements = bakeableElements.map((el) {
      return el.copyWith(
        offset: Offset(el.offset.dx - rootOffset.dx, el.offset.dy - rootOffset.dy),
      );
    }).toList();

    final module = UIModule(
      id: 'baked_${DateTime.now().millisecondsSinceEpoch}',
      name: '烘焙面原子 ${_assetService.getAllModules().length + 1}',
      type: 'surface_art',
      properties: {
        'baked_from': normalizedElements.map((e) => e.toJson()).toList(),
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


}
