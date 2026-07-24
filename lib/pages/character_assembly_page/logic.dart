part of '../character_assembly_page.dart';

mixin _AssemblyLogic on State<CharacterAssemblyPage> {
  final UIAssetService _assetService = UIAssetService();
  late UIAssemblyInfo _info;
  late TextEditingController _nameCtrl;
  final List<UIElement> _elements = [];
  Offset _canvasOffset = Offset.zero;
  bool _showLayerPanel = false;
  bool _showAssetDrawer = false;

  static const Size _defaultPcbSize = Size(360, 800);
  late Size _pcbSize;
  late Offset _pcbOffset;
  Color _pcbColor = Colors.white;
  bool _pcbRounded = true;

  // 拖放状态
  _AssemblyDragPayload? _activePlacement;
  static const double _dragThreshold = 24.0;

  void _initFromInfo(UIAssemblyInfo info) {
    _info = info;
    _nameCtrl = TextEditingController(text: info.name);
    _pcbSize = _defaultPcbSize;
    _pcbOffset = const Offset(20, 20);
    _canvasOffset = const Offset(80, 60);
  }

  bool _isGlobalPositionInsideCanvas(Offset globalPosition, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  void _startLibraryPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    _activePlacement?.isLibraryDragging.value = false;
    payload.longPressOrigin = globalPosition;
    payload.lastPointerGlobalPosition = globalPosition;
    payload.spawnedElementId = null;
    payload.isLibraryDragging.value = true;
    HapticFeedback.selectionClick();
    _activePlacement = payload;
  }

  void _handlePlacementPointerMove(PointerMoveEvent event, BuildContext context) {
    final payload = _activePlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;

    if (payload.spawnedElementId == null) {
      final origin = payload.longPressOrigin;
      if (origin != null) {
        final dx = (event.position.dx - origin.dx).abs();
        if (dx < _dragThreshold) return;
      }
    }

    if (_isGlobalPositionInsideCanvas(event.position, context)) {
      if (payload.spawnedElementId == null) {
        _beginDragPlacement(payload, event.position, context);
      } else {
        _updateDragPlacement(payload, event.position, context);
      }
    }
  }

  void _finishPlacementPointer(PointerEvent event, BuildContext context) {
    final payload = _activePlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;
    if (payload.spawnedElementId != null) {
      _finishDragPlacement(payload, event.position, context);
    }
    payload.isLibraryDragging.value = false;
    _activePlacement = null;
  }

  void _beginDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    if (payload.spawnedElementId != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = _compositeDefaultSize(payload.composite!);
    final local = box.globalToLocal(globalPosition) - _canvasOffset - _pcbOffset - Offset(size.width / 2, size.height / 2);
    final id = 'elem_${DateTime.now().millisecondsSinceEpoch}';
    if (payload.composite != null) {
      setState(() {
        _elements.add(UIElement(
          id: id, isComposite: true, composite: payload.composite,
          offset: local, size: size, layerIndex: 0,
        ));
        payload.spawnedElementId = id;
      });
    }
  }

  void _updateDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    final id = payload.spawnedElementId;
    if (id == null) { _beginDragPlacement(payload, globalPosition, context); return; }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final i = _elements.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final sz = _elements[i].size;
    final local = box.globalToLocal(globalPosition) - _canvasOffset - _pcbOffset - Offset(sz.width / 2, sz.height / 2);
    setState(() => _elements[i] = _elements[i].copyWith(offset: local));
  }

  void _finishDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    _updateDragPlacement(payload, globalPosition, context);
  }

  Size _compositeDefaultSize(UIComposite c) {
    if (c.children.isEmpty) return const Size(200, 120);
    double mx = 0, my = 0;
    for (final ch in c.children) {
      final cx = ch.offset.dx + ch.size.width;
      final cy = ch.offset.dy + ch.size.height;
      if (cx > mx) mx = cx;
      if (cy > my) my = cy;
    }
    return Size(mx + 20, my + 20);
  }
}
