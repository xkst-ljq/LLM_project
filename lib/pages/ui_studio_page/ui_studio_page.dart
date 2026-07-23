library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/image_pick_service.dart';
import '../../services/ui_engine/linker_matrix_engine.dart';
import '../../services/ui_engine/linker_service.dart';
import '../../services/ui_engine/ui_asset_service.dart';
import '../../services/ui_engine/ui_models.dart';
import '../../services/ui_engine/ui_renderer.dart';
import 'editors/indicator_editor.dart';
import 'editors/select_editor.dart';
import 'editors/timer_editor.dart';

part 'dialogs.dart';
part 'dialogs/compact_editors_dialogs.dart';
part 'dialogs/studio_menu_dialogs.dart';
part 'drawers.dart';
part 'editors/image_editor.dart';
part 'editors/line_editor.dart';
part 'editors/math_node_editor.dart';
part 'editors/switch_editor.dart';
part 'linker.dart';
part 'logic.dart';
part 'painters.dart';

/// 拖拽统一载荷：原子模组 或 复合组件（二选一）
class DragPayload {
  final UIModule? module;
  final UIComposite? composite;

  /// 按下点相对于原组件真实尺寸的比例锚点。
  /// 进入画布后以它维持“按住哪里，哪里就跟随指针”。
  Offset anchorFraction;
  String? spawnedElementId;
  int? pointerId;

  /// 统一放置状态机直接记录的原始全局指针坐标。
  Offset? lastPointerGlobalPosition;

  /// 长按触发时的原始全局坐标，用于计算拖移距离阈值。
  Offset? longPressOrigin;

  /// 资产库源组件的按住 / 拖动视觉状态。
  final ValueNotifier<bool> isLibraryDragging = ValueNotifier(false);

  DragPayload({
    this.module,
    this.composite,
    this.anchorFraction = const Offset(0.5, 0.5),
  });
}

class UIStudioPage extends StatefulWidget {
  const UIStudioPage({super.key});
  @override
  State<UIStudioPage> createState() => _UIStudioPageState();
}

class _UIStudioPageState extends State<UIStudioPage>
    with _UIStudioLogic, _UIStudioLinker, _StudioMenuDialogs, _CompactEditorsDialogs, _SwitchEditorDialog, _LineEditorDialog, _ImageEditorDialog, _MathNodeEditorDialog, _UIStudioDialogs, _UIStudioDrawers {
  // ============================================================
  //  手势临时锚定状态（仅与手势交互相关，保留在主文件）
  // ============================================================
  Offset _startTouchScreenPos = Offset.zero;
  Offset _startTouchElemOffset = Offset.zero;
  double _startTouchWidth = 150.0;
  double _startTouchHeight = 70.0;
  Offset _startTouchGlobalPos = Offset.zero;
  Offset _rotationCenter = Offset.zero;
  double _startHandleAngle = 0.0;
  double _startRotation = 0.0;
  final Set<String> _fineTuneOpenIds = <String>{};
  Offset _lastCanvasTapGlobalPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  @override
  void dispose() {
    _saveWorkspaceDraft(showMessage: false);
    super.dispose();
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
    _compositePortPositions.clear();
    _precomputeCompositePortPositions();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) _saveWorkspaceDraft(showMessage: false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F9),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: _handleLibraryPlacementPointerMove,
          onPointerUp: _finishLibraryPlacementPointer,
          onPointerCancel: _finishLibraryPlacementPointer,
          child: Stack(
            children: [
            // ===== 1. 无限画布 =====
            Positioned.fill(
              child: DragTarget<DragPayload>(
                key: _canvasDropKey,
                builder: (context, candidateData, rejectedData) {
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerMove: (event) {
                      if (_isDraggingConnection) {
                        setState(() => _dragConnectionEnd = event.position);
                        _updateConnectionHover(event.position);
                      }
                    },
                    onPointerUp: (event) {
                      if (_isDraggingConnection) {
                        _updateConnectionHover(event.position);
                        if (_hoveringTargetId != null) _completeConnection();
                        _cancelConnection();
                      }
                    },
                    onPointerCancel: (_) {
                      if (_isDraggingConnection) _cancelConnection();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        if (_isDraggingConnection) return;
                        setState(() => _workspaceOffset += details.delta);
                      },
                      onTapDown: (details) => _lastCanvasTapGlobalPosition = details.globalPosition,
                      onTap: () {
                        if (_pendingPaste != null) {
                          _pasteClipboardAt(_lastCanvasTapGlobalPosition);
                          return;
                        }
                        if (_isLinkingMode) {
                          setState(() => _isLinkingMode = false);
                        } else {
                          setState(() => _selectedTransformationId = null);
                        }
                      },
                      child: ClipRect(
                        child: UISceneModeScope(
                          isStudioCreationMode: !_isPreviewMode,
                          selectedElementId: _isPreviewMode ? null : _selectedTransformationId,
                          child: CustomPaint(
                            painter: _isPreviewMode
                                ? const _PreviewBlankPainter()
                                : StudioWarmGridPainter(_workspaceOffset),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ..._buildLinkerConnectionsLayer(),
                                if (!_isPreviewMode &&
                                    _isDraggingConnection &&
                                    _dragConnectionEnd != null)
                                  _buildTemporaryConnectionLine(),
                              ...() {
                                LinkerService.updateElementSnapshot(sortedElements);
                                return sortedElements.map((el) {
                                  final double p =
                                  (!_isPreviewMode &&
                                      el.id == _selectedTransformationId &&
                                      el.module?.type != 'linker')
                                      ? 20.0
                                      : 0.0;
                                  return Positioned(
                                    left: _workspaceOffset.dx + el.offset.dx - p,
                                    top: _workspaceOffset.dy + el.offset.dy - p,
                                    width: el.size.width + p * 2,
                                    height: el.size.height + p * 2,
                                    child: Builder(builder: (nCtx) => _buildTrueSingleHandleNode(nCtx, el, p)),
                                  );
                                });
                              }(),
                            ],
                          ),
                        ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ===== 2. 左上角返回 & 模式切换 =====
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 16,
              child: _isPreviewMode
                  ? FilledButton.icon(
                      style: _glassButtonStyle,
                      icon: const Icon(Icons.close_fullscreen_rounded, size: 18),
                      label: const Text(
                        '退出预览',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _togglePreviewMode,
                    )
                  : Row(
                      children: [
                        _buildGlassIconButton(
                          icon: Icons.reply_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: _glassButtonStyle,
                          icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                          label: const Text(
                            '模拟预览',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: _togglePreviewMode,
                        ),
                      ],
                    ),
            ),

            // ===== 3. 右上角控制 =====
            if (!_isPreviewMode)
              Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              right: 16,
              child: FilledButton.icon(
                style: _glassButtonStyle,
                icon: Icon(
                  _showConstructionManager ? Icons.close_rounded : Icons.view_list_rounded,
                  size: 18,
                ),
                label: Text(
                  _showConstructionManager ? '收起' : '构造层',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => setState(() {
                  _showConstructionManager = !_showConstructionManager;
                  _showRightDrawer = false;
                }),
              ),
            ),

            // ===== 画布级历史与清空（仅未选中元素时显示） =====
            if (!_isPreviewMode && _selectedTransformationId == null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 112,
                right: 16,
                child: _buildFloatingObjectAction(
                  icon: Icons.delete_sweep_rounded,
                  background: const Color(0xFF8B4B4B),
                  foreground: Colors.white,
                  onTap: _showClearWorkspaceDialog,
                ),
              ),
            if (!_isPreviewMode && _selectedTransformationId == null)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 84,
                child: Row(
                  children: [
                    _buildFloatingObjectAction(
                      icon: Icons.undo_rounded,
                      background: const Color(0xFF37474F),
                      foreground: Colors.white,
                      onTap: _undoWorkspace,
                    ),
                    const SizedBox(width: 8),
                    _buildFloatingObjectAction(
                      icon: Icons.redo_rounded,
                      background: const Color(0xFF37474F),
                      foreground: Colors.white,
                      onTap: _redoWorkspace,
                    ),
                  ],
                ),
              ),

            // ===== 4. 选中元素操作按钮（左侧：编辑 + 锁定 / 右侧：排序 + 删除）=====
            if (!_isPreviewMode && _selectedTransformationId != null) ...[
              // ----- 左列：编辑类 + 状态锁定类 -----
              Positioned(
                top: MediaQuery.of(context).padding.top + 112,
                left: 16,
                child: Column(
                  children: [
                    if (_currentElements.any((element) =>
                        element.id == _selectedTransformationId &&
                        _canUseBackgroundRuntimePlacement(element))) ...[
                      _buildFloatingObjectAction(
                        icon: _currentElements.any((element) =>
                                element.id == _selectedTransformationId &&
                                element.module?.properties['runtimePlacement'] == 'background')
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        background: const Color(0xFF546E7A),
                        foreground: Colors.white,
                        onTap: _toggleSelectedRuntimePlacement,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildFloatingObjectAction(
                      icon: Icons.straighten_rounded,
                      background: const Color(0xFF37474F), foreground: Colors.white,
                      onTap: () { final items=_currentElements.where((e)=>e.id==_selectedTransformationId).toList(); if(items.isNotEmpty) _showGeometryEditorDialog(items.first); },
                    ),
                    const SizedBox(height: 8),
                    if (_currentElements.any((element) => element.id == _selectedTransformationId && !_isGeometryLocked(element))) ...[
                      _buildFloatingObjectAction(
                        icon: Icons.control_camera_rounded,
                        background: const Color(0xFF37474F), foreground: Colors.white,
                        onTap: () => setState(() { final id=_selectedTransformationId; if(id!=null) _fineTuneOpenIds.contains(id) ? _fineTuneOpenIds.remove(id) : _fineTuneOpenIds.add(id); }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildFloatingObjectAction(
                      icon: Icons.tune_rounded,
                      background: const Color(0xFF37474F),
                      foreground: Colors.white,
                      onTap: () {
                        final element = _currentElements.where((item) =>
                            item.id == _selectedTransformationId).toList();
                        if (element.isNotEmpty) {
                          _showTailoredPrecisionEditorDialog(element.first);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildFloatingObjectAction(
                      iconWidget: _buildLockModeGlyph(
                        sealed: true,
                        locked: _currentElements.any((element) =>
                            element.id == _selectedTransformationId && element.sealed),
                      ),
                      background: const Color(0xFFFFB300),
                      foreground: const Color(0xFF424242),
                      onTap: _toggleSelectedSeal,
                    ),
                    const SizedBox(height: 8),
                    _buildFloatingObjectAction(
                      iconWidget: _buildLockModeGlyph(
                        sealed: false,
                        locked: _currentElements.any((element) =>
                            element.id == _selectedTransformationId && element.layoutLocked),
                      ),
                      background: const Color(0xFF4FC3F7),
                      foreground: const Color(0xFF424242),
                      onTap: _toggleSelectedLayoutLock,
                    ),
                  ],
                ),
              ),
              // ----- 右列：排序类 + 危险操作 -----
              Positioned(
                top: MediaQuery.of(context).padding.top + 112,
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
                    if (_currentElements.any(
                      (element) =>
                          element.id == _selectedTransformationId &&
                          _canAssignSurfaceMembership(element),
                    )) ...[
                      _buildFloatingObjectAction(
                        icon: Icons.layers_outlined,
                        background: const Color(0xFF7E57C2),
                        foreground: Colors.white,
                        onTap: _showSurfaceMembershipDialog,
                      ),
                      const SizedBox(height: 8),
                    ],
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
            ],

            // ===== 5. 抽屉 =====
            if (!_isPreviewMode)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                right: _showConstructionManager ? 0 : -190,
              top: 120,
              bottom: 120,
              width: 180,
              child: _buildAtomicConstructionDrawer(),
            ),
            if (!_isPreviewMode)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                left: _showLeftDrawer ? 0 : -150,
                top: MediaQuery.of(context).padding.top + 100,
                bottom: 100,
                width: 150,
                child: _buildLeftCompactAssetPreviewDrawer(),
            ),
            if (!_isPreviewMode)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                right: _showRightDrawer ? 0 : -rightDrawerWidth,
                top: MediaQuery.of(context).padding.top + 100,
                bottom: 120,
                width: rightDrawerWidth,
                child: _buildRightCompletedAssetsDrawer(),
            ),

            // ===== 6. 侧边展开按钮 =====
            if (!_isPreviewMode)
              Positioned(
                left: 0,
                top: MediaQuery.of(context).padding.top + 54,
                child: _buildEdgeOpenButton(
                  icon: _showLeftDrawer ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                  onTap: () => setState(() => _showLeftDrawer = !_showLeftDrawer),
                  left: true,
                ),
              ),
            if (!_isPreviewMode && !_showConstructionManager)
              Positioned(
                right: 0,
                top: MediaQuery.of(context).padding.top + 54,
                child: _buildEdgeOpenButton(
                  icon: _showRightDrawer ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
                  onTap: () => setState(() => _showRightDrawer = !_showRightDrawer),
                  left: false,
                ),
              ),

            // ===== 左下编辑工具 =====
            if (!_isPreviewMode)
              Positioned(
                left: 16,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: _pendingPaste != null
                    ? Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF37474F), borderRadius: BorderRadius.circular(18)), child: Text('正在放置「${_pendingPaste!.label}」', style: const TextStyle(color: Colors.white, fontSize: 11))),
                        const SizedBox(width: 8),
                        _buildFloatingObjectAction(icon: Icons.close_rounded, background: const Color(0xFF8B4B4B), foreground: Colors.white, onTap: () => setState(() => _pendingPaste = null)),
                      ])
                    : _isMultiDeleteMode
                        ? Row(children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF8B4B4B), borderRadius: BorderRadius.circular(18)), child: Text('已选 ${_pendingDeleteIds.length} 项', style: const TextStyle(color: Colors.white, fontSize: 11))),
                            const SizedBox(width: 8),
                            _buildFloatingObjectAction(icon: Icons.close_rounded, background: const Color(0xFF546E7A), foreground: Colors.white, onTap: _toggleMultiDeleteMode),
                            const SizedBox(width: 8),
                            _buildFloatingObjectAction(icon: Icons.delete_rounded, background: const Color(0xFF8B4B4B), foreground: Colors.white, onTap: _confirmPendingDelete),
                          ])
                        : Row(children: [
                            _buildFloatingObjectAction(icon: Icons.content_copy_rounded, background: const Color(0xFF37474F), foreground: Colors.white, onTap: _copySelectedToClipboard),
                            if (_selectedTransformationId == null) ...[
                              const SizedBox(width: 8),
                              _buildFloatingObjectAction(icon: Icons.playlist_remove_rounded, background: const Color(0xFF8B4B4B), foreground: Colors.white, onTap: _toggleMultiDeleteMode),
                            ],
                          ]),
              ),

            // ===== 固定精调手柄 =====
            if (!_isPreviewMode && _selectedTransformationId != null && _fineTuneOpenIds.contains(_selectedTransformationId))
              Positioned(
                // 3×3 标准 D-Pad：总宽 40×3 + 16×2 = 152，严格以屏幕中轴居中。
                left: MediaQuery.of(context).size.width / 2 - 76,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 56),
                    _buildFineTuneButton(Icons.keyboard_arrow_up_rounded, () => _nudgeElement(_selectedTransformationId!, const Offset(0, -1))),
                    const SizedBox(width: 56),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    _buildFineTuneButton(Icons.keyboard_arrow_left_rounded, () => _nudgeElement(_selectedTransformationId!, const Offset(-1, 0))),
                    const SizedBox(width: 16),
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF546E7A), borderRadius: BorderRadius.circular(10))),
                    const SizedBox(width: 16),
                    _buildFineTuneButton(Icons.keyboard_arrow_right_rounded, () => _nudgeElement(_selectedTransformationId!, const Offset(1, 0))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    const SizedBox(width: 56),
                    _buildFineTuneButton(Icons.keyboard_arrow_down_rounded, () => _nudgeElement(_selectedTransformationId!, const Offset(0, 1))),
                    const SizedBox(width: 56),
                  ]),
                ]),
              ),

            // ===== 7. 保存按钮 =====
            if (!_isPreviewMode)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4081),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.22),
                ),
                icon: const Icon(Icons.save_rounded, size: 20),
                label: const Text(
                  '保存',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _showSaveMenu,
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  //  节点构建（与手势、Linker、旋转把手高度耦合，保留在主文件）
  // ============================================================
  Widget _buildTrueSingleHandleNode(BuildContext nodeCtx, UIElement el, double p) {
    if (_isPreviewMode) {
      // 模拟预览不再要求交互原子必须位于 Surface 内。
      // Surface 仅负责视觉布局，所有工作区控件均可直接测试交互与 Linker 协议。
      return SizedBox(
        width: el.size.width,
        height: el.size.height,
        child: UIRenderer.render(nodeCtx, el),
      );
    }

    final bool isTransformationActive = _selectedTransformationId == el.id;
    final bool isCurrentLayerActive = el.layerIndex == _activeLayerIndex;

    if (!isCurrentLayerActive) {
      return IgnorePointer(
        ignoring: true,
        child: Center(
          child: SizedBox(
            width: el.size.width,
            height: el.size.height,
            child: UIRenderer.render(nodeCtx, el),
          ),
        ),
      );
    }

    final elNoRot = el.copyWith(rotation: 0.0);
    final bool isLinker = el.module?.type == 'linker';

    Widget contentArea = SizedBox(
      width: el.size.width,
      height: el.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UIRenderer.render(nodeCtx, elNoRot),
          if (_isMultiDeleteMode && _pendingDeleteIds.contains(el.id))
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE53935), width: 2),
                    color: const Color(0xFFE53935).withValues(alpha: 0.14),
                  ),
                ),
              ),
            ),
          if (isTransformationActive && !isLinker)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: StudioAlternatingDashedBorderPainter(
                    strokeWidth: 1.2,
                    shape: _outlineShapeOf(el),
                    borderRadius: _outlineBorderRadiusOf(el),
                    isPerfectCircle: _isPerfectCircleOutlineOf(el),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final bool isContainerBoundary = el.module?.properties['is_container_boundary'] == true;
    Widget layerBadge = isContainerBoundary
        ? Positioned(
            left: p + 4,
            top: p - 14,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 0.7,
                  ),
                ),
                child: const Text(
                  '容器面',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    Widget touchableContent;
    if (isLinker) {
      touchableContent = SizedBox(
        width: el.size.width,
        height: el.size.height,
        child: Stack(
          children: [
            contentArea,
            Positioned.fill(
              child: Row(
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      setState(() => _selectedTransformationId = el.id);
                      setState(() {
                        _isDraggingConnection = true;
                        _draggingSourceId = el.id;
                        _draggingSourcePort = 'input';
                        _draggingSourceType = 'input';
                        _dragConnectionEnd = event.position;
                      });
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => _disconnectLinkerPort(el, 'input'),
                      child: Container(
                        width: 32,
                        height: double.infinity,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _selectedTransformationId = el.id);
                        _showLinkerSchemeQuickSelectDialog(el);
                      },
                      onPanStart: (details) {
                        if (_isGeometryLocked(el)) return;
                        if (_isDraggingConnection) _cancelConnection();
                        _startTouchScreenPos = details.globalPosition;
                        _startTouchElemOffset = el.offset;
                        setState(() => _selectedTransformationId = el.id);
                      },
                      onPanUpdate: (details) {
                        if (_isDraggingConnection || _isGeometryLocked(el)) return;
                        final delta = details.globalPosition - _startTouchScreenPos;
                        setState(() {
                          final idx = _currentElements.indexWhere((e) => e.id == el.id);
                          if (idx != -1) {
                            _currentElements[idx] = el.copyWith(
                              offset: _startTouchElemOffset + delta,
                            );
                          }
                        });
                      },
                      onPanEnd: (_) {
                        if (_isDraggingConnection) return;
                        _autoSave();
                      },
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      setState(() => _selectedTransformationId = el.id);
                      setState(() {
                        _isDraggingConnection = true;
                        _draggingSourceId = el.id;
                        _draggingSourcePort = 'output';
                        _draggingSourceType = 'output';
                        _dragConnectionEnd = event.position;
                      });
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => _disconnectLinkerPort(el, 'output'),
                      child: Container(
                        width: 32,
                        height: double.infinity,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      touchableContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_isMultiDeleteMode) { _togglePendingDelete(el); } else { setState(() => _selectedTransformationId = el.id); }
        },
        onDoubleTap: () {
          setState(() => _selectedTransformationId = el.id);
          _showTailoredPrecisionEditorDialog(el);
        },
        onPanStart: (details) {
          if (_isDraggingConnection || _isGeometryLocked(el)) return;
          _startTouchScreenPos = details.globalPosition;
          _startTouchElemOffset = el.offset;
          setState(() => _selectedTransformationId = el.id);
        },
        onPanUpdate: (details) {
          if (_isDraggingConnection || _isGeometryLocked(el)) return;
          final delta = details.globalPosition - _startTouchScreenPos;
          setState(() {
            final idx = _currentElements.indexWhere((e) => e.id == el.id);
            if (idx != -1) {
              _currentElements[idx] = el.copyWith(
                offset: _startTouchElemOffset + delta,
              );
            }
          });
        },
        onPanEnd: (_) {
          if (_isDraggingConnection) return;
          _autoSave();
        },
        child: contentArea,
      );
    }

    final stackChildren = <Widget>[
      Positioned(left: p, top: p, child: touchableContent),
      layerBadge,
      if (el.module?.properties['runtimePlacement'] == 'background')
        Positioned(
          left: p + 4,
          bottom: p + 3,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF546E7A),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text('后台', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
    ];



    // ===== 暴露端口渲染（复合件边框引脚） =====
    if (el.isComposite && el.composite?.exposedPorts != null) {
      final ports = el.composite!.exposedPorts!.where((p) =>
        el.composite!.children.any((c) => c.id == p.elementId)
      ).toList();
      final bodyH = el.size.height;
      final gx = _workspaceOffset.dx + el.offset.dx;
      final gy = _workspaceOffset.dy + el.offset.dy;
      // 左侧接收端口
      final leftPorts = ports.where((p) => p.exposeInput).toList();
      for (var i = 0; i < leftPorts.length; i++) {
        final port = leftPorts[i];
        final dataType = el.composite!.children.firstWhere((c) => c.id == port.elementId).module?.type ?? '';
        final dotColor = _exposedPortColor(port, dataType);
        final y = p + (bodyH / (leftPorts.length + 1)) * (i + 1);
        // 记录端口全局位置供连线使用
        _compositePortPositions["${port.elementId}::input"] = Offset(gx, gy - p + y);
        stackChildren.add(
          Positioned(
            left: p - 6,
            top: y - 6,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
              ),
            ),
          ),
        );
      }
      // 右侧输出端口
      final rightPorts = ports.where((p) => p.exposeOutput).toList();
      for (var i = 0; i < rightPorts.length; i++) {
        final port = rightPorts[i];
        final dataType = el.composite!.children.firstWhere((c) => c.id == port.elementId).module?.type ?? '';
        final dotColor = _exposedPortColor(port, dataType);
        final y = p + (bodyH / (rightPorts.length + 1)) * (i + 1);
        _compositePortPositions["${port.elementId}::output"] = Offset(gx + el.size.width, gy - p + y);
        stackChildren.add(
          Positioned(
            left: el.size.width + p * 2 - (p - 6) - 12,
            top: y - 6,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
              ),
            ),
          ),
        );
      }
    }

    final bool isMathNode = el.module?.type == 'math_node';
    final bool isIndicator = el.module?.type == 'indicator';
    final bool isTimer = el.module?.type == 'timer';
    if (isTransformationActive && !_isGeometryLocked(el) && !isLinker && !isMathNode && !isIndicator && !isTimer) {
      // 复合件只支持旋转，形变由未来 Assembly 页 FittedBox 统一处理
      final bool isRotateMode = el.isComposite || _elementRotateModes.contains(el.id);
      stackChildren.add(
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (el.isComposite) return;
              setState(() {
                if (_elementRotateModes.contains(el.id)) {
                  _elementRotateModes.remove(el.id);
                } else {
                  _elementRotateModes.add(el.id);
                }
              });
            },
            onPanStart: (details) {
              _startTouchWidth = el.size.width;
              _startTouchHeight = el.size.height;
              _startTouchGlobalPos = details.globalPosition;
              if (el.module?.type == 'linker') {
                _elementRotateModes.remove(el.id);
              }
              if (_elementRotateModes.contains(el.id)) {
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
              if (_isDraggingConnection) return;
              if (el.module?.type == 'linker') {
                _elementRotateModes.remove(el.id);
              }
              if (_elementRotateModes.contains(el.id)) {
                final currentAngle =
                    (details.globalPosition - _rotationCenter).direction;
                var delta = currentAngle - _startHandleAngle;
                while (delta > math.pi) { delta -= 2 * math.pi; }
                while (delta < -math.pi) { delta += 2 * math.pi; }
                double newRotation = _startRotation + delta * 180 / math.pi;
                final double remainder = (newRotation % 90.0).abs();
                if (remainder <= 4.0 || remainder >= 86.0) {
                  final double snappedRotation = (newRotation / 90.0).round() * 90.0;
                  if (el.rotation != snappedRotation) {
                    HapticFeedback.lightImpact();
                  }
                  newRotation = snappedRotation;
                }
                setState(() {
                  final idx = _currentElements.indexWhere((e) => e.id == el.id);
                  if (idx != -1) {
                    _currentElements[idx] = el.copyWith(rotation: newRotation);
                  }
                });
              } else {
                final dx = details.globalPosition.dx - _startTouchGlobalPos.dx;
                final dy = details.globalPosition.dy - _startTouchGlobalPos.dy;
                final isProgress = el.module?.type == 'progress';
                final isSurface = const {'surface', 'surface_art', 'primitive_art', 'base_box'}
                    .contains(el.module?.type);
                final newWidth = (_startTouchWidth + dx).clamp(isProgress ? 12.0 : (isSurface ? 20.0 : 40.0), isSurface ? 4096.0 : 600.0);
                final newHeight = (_startTouchHeight + dy).clamp(isProgress ? 6.0 : 20.0, isSurface ? 4096.0 : 400.0);
                setState(() {
                  final idx = _currentElements.indexWhere((e) => e.id == el.id);
                  if (idx != -1) {
                    final curEl = _currentElements[idx];
                    if (curEl.module != null && curEl.module!.properties['autoFit'] == true) {
                      curEl.module!.properties['autoFit'] = false;
                    }
                    _currentElements[idx] = el.copyWith(
                      size: Size(newWidth, newHeight),
                    );
                  }
                });
              }
            },
            onPanEnd: (_) => _autoSave(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isRotateMode
                    ? const Color(0xFF651FFF)
                    : const Color(0xFFFF4081),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                isRotateMode
                    ? Icons.rotate_right_rounded
                    : Icons.open_in_full_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }


    Widget rootTree = SizedBox(
      width: el.size.width + p * 2,
      height: el.size.height + p * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: stackChildren,
      ),
    );

    final shouldPassThrough = el.sealed ||
        (el.layoutLocked && !isLinker && !_isMultiDeleteMode);
    final transformedNode = IgnorePointer(
      ignoring: shouldPassThrough,
      child: Transform.rotate(
        angle: el.rotation * math.pi / 180.0,
        alignment: Alignment.center,
        child: rootTree,
      ),
    );

    // 锁定主体保持命中穿透；右上角只保留一个极小的解锁入口。
    // 它不拦截元素主体区域，因此仍可操作下层元素与连线。
    if (!el.layoutLocked && !el.sealed) return transformedNode;
    return SizedBox(
      width: el.size.width + p * 2,
      height: el.size.height + p * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: transformedNode),
          Positioned(
            right: p + 2,
            top: p + 2,
            child: Material(
              color: el.sealed ? const Color(0xFFFFB300) : const Color(0xFF4FC3F7),
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _selectedTransformationId = el.id),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: _buildLockModeGlyph(sealed: el.sealed, locked: true, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //  小型 UI 辅助组件
  // ============================================================
  Color _exposedPortColor(ExposedPort port, String type) {
    if (port.customColor != null) return Color(port.customColor!);
    return _exposedPortVisualColor(type);
  }

  Color _exposedPortVisualColor(String type) {
    switch (type) {
      case 'progress':
      case 'slider':
        return const Color(0xFF00E676);
      case 'text':
      case 'select':
      case 'input':
        return const Color(0xFF651FFF);
      case 'switch':
        return const Color(0xFFFFA726);
      case 'button':
        return const Color(0xFFFFD740);
      default:
        return const Color(0xFF9E9E9E);
    }
  }



  void _nudgeElement(String id, Offset delta) {
    final index = _currentElements.indexWhere((element) => element.id == id);
    if (index == -1 || _isGeometryLocked(_currentElements[index])) return;
    setState(() => _currentElements[index] = _currentElements[index]
        .copyWith(offset: _currentElements[index].offset + delta));
    _autoSave();
  }

  Widget _buildFineTuneButton(IconData icon, VoidCallback onTap) => Material(
    color: const Color(0xFF37474F), shape: const CircleBorder(), elevation: 3,
    child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 28))),
  );

  Widget _buildLockModeGlyph({
    required bool sealed,
    required bool locked,
    double size = 20,
  }) {
    return Icon(
      locked
          ? Icons.lock_rounded
          : (sealed ? Icons.brightness_1 : Icons.brightness_2),
      size: locked ? size * 0.74 : size,
      color: const Color(0xFF424242),
    );
  }


  Widget _buildFloatingObjectAction({
    IconData? icon,
    Widget? iconWidget,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    assert(icon != null || iconWidget != null);
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
          child: iconWidget ?? Icon(icon, color: foreground, size: 24),
        ),
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
      ),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(
            icon,
            color: const Color(0xFF111116),
            size: 26,
          ),
        ),
      ),
    );
  }

  ButtonStyle get _glassButtonStyle => FilledButton.styleFrom(
    backgroundColor: Colors.white.withValues(alpha: 0.92),
    foregroundColor: const Color(0xFF111116),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: Colors.black.withValues(alpha: 0.06),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    elevation: 4,
  );

  Widget _buildEdgeOpenButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool left,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.only(
            topRight: left ? const Radius.circular(14) : Radius.zero,
            bottomRight: left ? const Radius.circular(14) : Radius.zero,
            topLeft: left ? Radius.zero : const Radius.circular(14),
            bottomLeft: left ? Radius.zero : const Radius.circular(14),
          ),
          border: Border.all(color: Colors.black12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 8),
          ],
        ),
        child: Icon(
          icon,
          size: 14,
          color: const Color(0xFF111116),
        ),
      ),
    );
  }
}

// Clipboard entry is declared in the UI Studio library so logic/drawers can share it.
class StudioClipboardEntry {
  final String label;
  final List<Map<String, dynamic>> elements;
  final DateTime createdAt;
  StudioClipboardEntry({required this.label, required this.elements})
      : createdAt = DateTime.now();
}
