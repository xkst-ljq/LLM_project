library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/image_pick_service.dart';
import '../../services/ui_engine/linker_service.dart';
import '../../services/ui_engine/ui_asset_service.dart';
import '../../services/ui_engine/ui_models.dart';
import '../../services/ui_engine/ui_renderer.dart';
import 'editors/indicator_editor.dart';
import 'editors/select_editor.dart';

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
  DragPayload({this.module, this.composite});
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

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) _saveWorkspaceDraft(showMessage: false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F9),
        body: Stack(
          children: [
            // ===== 1. 无限画布 =====
            Positioned.fill(
              child: DragTarget<DragPayload>(
                key: _canvasDropKey,
                onAcceptWithDetails: (details) {
                  final box = _canvasDropKey.currentContext?.findRenderObject()
                  as RenderBox?;
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
                      onTap: () {
                        if (_isLinkingMode) {
                          setState(() => _isLinkingMode = false);
                        } else {
                          setState(() => _selectedTransformationId = null);
                        }
                      },
                      child: ClipRect(
                        child: UISceneModeScope(
                          isStudioCreationMode: true,
                          selectedElementId: _selectedTransformationId,
                          child: CustomPaint(
                            painter: StudioWarmGridPainter(_workspaceOffset),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ..._buildLinkerConnectionsLayer(),
                                if (_isDraggingConnection &&
                                    _dragConnectionEnd != null)
                                  _buildTemporaryConnectionLine(),
                              ...() {
                                LinkerService.updateElementSnapshot(sortedElements);
                                return sortedElements.map((el) {
                                  final double p =
                                  (el.id == _selectedTransformationId &&
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

            // ===== 2. 左上角返回 =====
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: _buildGlassIconButton(
                icon: Icons.reply_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),

            // ===== 3. 右上角控制 =====
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: FilledButton.icon(
                style: _glassButtonStyle,
                icon: const Icon(Icons.layers_rounded, size: 18),
                label: Text(
                  '图层 (Level $_activeLayerIndex)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                onPressed: () => setState(() {
                  _showLayerManager = true;
                  _showConstructionManager = false;
                  _showRightDrawer = false;
                }),
              ),
            ),

            Positioned(
              top: MediaQuery.of(context).padding.top + 68,
              right: 16,
              child: FilledButton.icon(
                style: _glassButtonStyle,
                icon: const Icon(Icons.view_list_rounded, size: 18),
                label: const Text(
                  '构造层',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => setState(() {
                  _showConstructionManager = true;
                  _showLayerManager = false;
                  _showRightDrawer = false;
                }),
              ),
            ),

            // ===== 4. 选中元素操作按钮 =====
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

            // ===== 5. 抽屉 =====
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: _showLayerManager ? 0 : -260,
              top: 100,
              bottom: 100,
              width: 240,
              child: _buildDedicatedLayerManagerDrawer(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: _showConstructionManager ? 0 : -260,
              top: 120,
              bottom: 120,
              width: 240,
              child: _buildAtomicConstructionDrawer(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              left: _showLeftDrawer ? 0 : -150,
              top: 100,
              bottom: 100,
              width: 150,
              child: _buildLeftCompactAssetPreviewDrawer(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              right: _showRightDrawer ? 0 : -rightDrawerWidth,
              top: 120,
              bottom: 120,
              width: rightDrawerWidth,
              child: _buildRightCompletedAssetsDrawer(),
            ),

            // ===== 6. 侧边展开按钮 =====
            if (!_showLeftDrawer)
              Positioned(
                left: 0,
                top: MediaQuery.of(context).size.height / 2 - 24,
                child: _buildEdgeOpenButton(
                  icon: Icons.arrow_forward_ios,
                  onTap: () => setState(() => _showLeftDrawer = true),
                  left: true,
                ),
              ),
            if (!_showRightDrawer &&
                !_showLayerManager &&
                !_showConstructionManager)
              Positioned(
                right: 0,
                top: MediaQuery.of(context).size.height / 2 - 24,
                child: _buildEdgeOpenButton(
                  icon: Icons.arrow_back_ios,
                  onTap: () => setState(() => _showRightDrawer = true),
                  left: false,
                ),
              ),

            // ===== 7. 保存按钮 =====
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
    );
  }

  // ============================================================
  //  节点构建（与手势、Linker、旋转把手高度耦合，保留在主文件）
  // ============================================================
  Widget _buildTrueSingleHandleNode(BuildContext nodeCtx, UIElement el, double p) {
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
    Widget layerBadge = Positioned(
      left: p + 4,
      top: p - 14,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: isContainerBoundary ? const Color(0xFFE65100) : Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.88),
              width: 0.7,
            ),
          ),
          child: Text(
            isContainerBoundary ? '容器面 (L${el.layerIndex})' : 'L${el.layerIndex}',
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
    );

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
                      onLongPress: () {
                        setState(() => _selectedTransformationId = el.id);
                        _showTailoredPrecisionEditorDialog(el);
                      },
                      onPanStart: (details) {
                        if (_isDraggingConnection) _cancelConnection();
                        _startTouchScreenPos = details.globalPosition;
                        _startTouchElemOffset = el.offset;
                        setState(() => _selectedTransformationId = el.id);
                      },
                      onPanUpdate: (details) {
                        if (_isDraggingConnection) return;
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
        onTap: () => setState(() => _selectedTransformationId = el.id),
        onLongPress: () {
          setState(() => _selectedTransformationId = el.id);
          _showTailoredPrecisionEditorDialog(el);
        },
        onPanStart: (details) {
          if (_isDraggingConnection) return;
          _startTouchScreenPos = details.globalPosition;
          _startTouchElemOffset = el.offset;
          setState(() => _selectedTransformationId = el.id);
        },
        onPanUpdate: (details) {
          if (_isDraggingConnection) return;
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
    ];

    final bool isMathNode = el.module?.type == 'math_node';
    final bool isIndicator = el.module?.type == 'indicator';
    if (isTransformationActive && !isLinker && !isMathNode && !isIndicator) {
      stackChildren.add(
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _transformHandleRotateMode =
            !_transformHandleRotateMode),
            onPanStart: (details) {
              _startTouchWidth = el.size.width;
              _startTouchHeight = el.size.height;
              _startTouchGlobalPos = details.globalPosition;
              if (el.module?.type == 'linker') {
                _transformHandleRotateMode = false;
              }
              if (_transformHandleRotateMode) {
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
                _transformHandleRotateMode = false;
              }
              if (_transformHandleRotateMode) {
                final currentAngle =
                    (details.globalPosition - _rotationCenter).direction;
                var delta = currentAngle - _startHandleAngle;
                while (delta > math.pi) { delta -= 2 * math.pi; }
                while (delta < -math.pi) { delta += 2 * math.pi; }
                final newRotation = _startRotation + delta * 180 / math.pi;
                setState(() {
                  final idx = _currentElements.indexWhere((e) => e.id == el.id);
                  if (idx != -1) {
                    _currentElements[idx] = el.copyWith(rotation: newRotation);
                  }
                });
              } else {
                final dx = details.globalPosition.dx - _startTouchGlobalPos.dx;
                final dy = details.globalPosition.dy - _startTouchGlobalPos.dy;
                final newWidth = (_startTouchWidth + dx).clamp(40.0, 600.0);
                final newHeight = (_startTouchHeight + dy).clamp(20.0, 400.0);
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
                color: _transformHandleRotateMode
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
                _transformHandleRotateMode
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

    if (el.rotation != 0.0) {
      rootTree = Transform.rotate(
        angle: el.rotation * math.pi / 180.0,
        alignment: Alignment.center,
        child: rootTree,
      );
    }

    return rootTree;
  }

  // ============================================================
  //  小型 UI 辅助组件
  // ============================================================
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
