import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/card_entry_target.dart';
import '../models/character_entry.dart';
import '../models/status_bar_field.dart';
import '../models/ui_assembly_info.dart';
import '../services/ui_engine/dashed_selection_border_painter.dart';
import '../services/ui_engine/data_channel_prompt_builder.dart';
import '../services/ui_engine/linker_connection_painter.dart';
import '../services/ui_engine/linker_matrix_engine.dart';
import '../services/ui_engine/message_action.dart';
import '../services/ui_engine/linker_service.dart';
import '../services/ui_engine/select_option.dart';
import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';
import '../services/ui_engine/avatar_scope.dart';
import '../services/ui_engine/ui_semantic_role.dart';
import '../widgets/ui_assembly_runtime_view.dart';

part 'character_assembly_page/logic.dart';

/// 拖拽载荷
class _AssemblyDragPayload {
  final UIComposite? composite;
  final UIModule? module;
  final bool verticalDragToSpawn;
  Offset anchorFraction = const Offset(0.5, 0.5);
  String? spawnedElementId;
  int? pointerId;
  Offset? lastPointerGlobalPosition;
  Offset? longPressOrigin;
  final ValueNotifier<bool> isLibraryDragging = ValueNotifier(false);

  _AssemblyDragPayload({
    this.composite,
    this.module,
    this.verticalDragToSpawn = false,
  });
}

class _AssemblyAssetItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _AssemblyDragPayload payload;

  _AssemblyAssetItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.payload,
  });

  factory _AssemblyAssetItem.module({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required UIModule module,
  }) {
    return _AssemblyAssetItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      payload: _AssemblyDragPayload(
        module: module,
        verticalDragToSpawn: true,
      ),
    );
  }

  factory _AssemblyAssetItem.composite(UIComposite composite) {
    return _AssemblyAssetItem(
      title: composite.name,
      subtitle: '${composite.exposedPorts?.length ?? 0} 端口',
      icon: Icons.dashboard_customize_rounded,
      color: const Color(0xFF651FFF),
      payload: _AssemblyDragPayload(
        composite: composite,
        verticalDragToSpawn: true,
      ),
    );
  }
}

class CharacterAssemblyPage extends StatefulWidget {
  final UIAssemblyInfo assemblyInfo;

  /// 角色卡当前的状态栏字段定义（只读参考）。
  ///
  /// 数据通道选择「状态字段」时用于名称匹配与目标 id 预绑定；
  /// Assembly 不修改角色卡字段本体，未匹配到的名称记为 pendingName。
  final List<StatusBarField> statusFields;

  /// 角色卡设定条目（只读参考）。
  ///
  /// 数据通道选择「角色卡设定」时，用于列出可填写的条目与子字段。
  /// Assembly 不修改条目本体——玩家填的值写会话副本，注入时覆盖母版。
  final List<CharacterEntry> cardEntries;

  /// 卡类型（`character` / `system`）。人物卡与系统卡的条目集合不同。
  final String cardType;

  const CharacterAssemblyPage({
    super.key,
    required this.assemblyInfo,
    this.statusFields = const <StatusBarField>[],
    this.cardEntries = const <CharacterEntry>[],
    this.cardType = 'character',
  });
  @override
  State<CharacterAssemblyPage> createState() => _CharacterAssemblyPageState();
}

class _CharacterAssemblyPageState extends State<CharacterAssemblyPage>
    with _AssemblyLogic {
  Offset _startTouchScreenPos = Offset.zero;
  Offset _startTouchElemOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _initFromInfo(widget.assemblyInfo);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_runtimePreviewMode) {
      final previewInfo = _runtimePreviewInfo ?? _info;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _exitRuntimePreview();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF202026),
          body: Stack(
            children: [
              Positioned.fill(
                child: UIAssemblyRuntimeView(
                  assemblyInfo: previewInfo,
                  activePageId: _runtimePreviewPageId,
                  showBlurredBackdrop: true,
                  // 预览用本地临时会话副本：可验证数据通道写入，
                  // 但不落盘、不影响真实角色卡会话状态。
                  statusFields: widget.statusFields,
                  showDataChannelDebug: true,
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.36),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _exitRuntimePreview,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ancestorPages = _ancestorPagesForActivePage();
    final renderedElements = <UIElement>[
      ...ancestorPages.expand((page) => page.elements),
      ..._elements,
    ];
    final linkerSnapshot = LinkerSnapshot.fromElements(renderedElements);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE8E8EC),
        body: UILinkerSnapshotScope(
          snapshot: linkerSnapshot,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            // 接线的移动/抬起要在**最外层**接，而不是挂在 linker 上：
            // 手指一旦离开 linker 本体，挂在它身上的监听就收不到事件了。
            onPointerMove: (event) {
              if (_isDraggingConnection) {
                _updateConnectionDrag(event.position);
                return;
              }
              _handlePlacementPointerMove2(event);
            },
            onPointerUp: (event) {
              if (_isDraggingConnection) {
                _updateConnectionDrag(event.position);
                _completeConnectionDrag();
                return;
              }
              _finishPlacementPointer2(event);
            },
            onPointerCancel: (event) {
              if (_isDraggingConnection) {
                _cancelConnectionDrag();
                return;
              }
              _finishPlacementPointer2(event);
            },
            child: Stack(
              children: [
                // ===== 1. 无限画布 + PCB =====
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 接线进行中时画布不跟着平移，否则线和底图一起动，
                    // 根本瞄不准目标（Studio 同样处理）。
                    onPanUpdate: (_showLayerPanel || _isDraggingConnection)
                        ? null
                        : (details) => setState(() => _canvasOffset += details.delta),
                    onTap: () {
                      if (_showAssetDrawer) setState(() => _showAssetDrawer = false);
                      if (_showLayerPanel) setState(() => _showLayerPanel = false);
                      _clearCompositeSelection();
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        painter: _AssemblyGridPainter(_canvasOffset),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: _canvasOffset.dx + _pcbOffset.dx,
                              top: _canvasOffset.dy + _pcbOffset.dy,
                              width: _pcbSize.width,
                              height: _pcbSize.height,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _pcbColor,
                                  borderRadius: BorderRadius.circular(_pcbRounded ? 20 : 0),
                                  border: Border.all(
                                    color: _hasIllegalPcbElements
                                        ? const Color(0xFFE53935)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: _hasIllegalPcbElements ? 2.0 : 1.0,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x18000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: _canvasOffset.dx + _pcbOffset.dx +
                                  _pcbSize.width / 2 - 22,
                              top: _canvasOffset.dy + _pcbOffset.dy +
                                  _pcbSize.height - 12,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  _pcbResizeStartHeight = _pcbSize.height;
                                  _pcbResizeStartGlobalDy =
                                      details.globalPosition.dy;
                                },
                                onPanUpdate: (details) {
                                  final nextHeight = _clampPcbHeight(
                                    _pcbResizeStartHeight +
                                        (details.globalPosition.dy -
                                            _pcbResizeStartGlobalDy),
                                  );
                                  setState(() {
                                    _pcbSize = Size(_pcbSize.width, nextHeight);
                                  });
                                },
                                onPanEnd: (_) => _persistAssemblyElements(),
                                child: Container(
                                  width: 44,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111116)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 18,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF555562),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 右侧宽度手柄。常驻 / 伴生 UI 的宽度需要可调，
                            // 固定 360 会让作者按错误比例摆放元件。
                            Positioned(
                              left: _canvasOffset.dx + _pcbOffset.dx +
                                  _pcbSize.width - 12,
                              top: _canvasOffset.dy + _pcbOffset.dy +
                                  _pcbSize.height / 2 - 22,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  _pcbResizeStartWidth = _pcbSize.width;
                                  _pcbResizeStartGlobalDx =
                                      details.globalPosition.dx;
                                },
                                onPanUpdate: (details) {
                                  final nextWidth = _clampPcbWidth(
                                    _pcbResizeStartWidth +
                                        (details.globalPosition.dx -
                                            _pcbResizeStartGlobalDx),
                                  );
                                  setState(() {
                                    _pcbSize =
                                        Size(nextWidth, _pcbSize.height);
                                  });
                                },
                                onPanEnd: (_) => _persistAssemblyElements(),
                                child: Container(
                                  width: 24,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111116)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 4,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF555562),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ...ancestorPages.expand((page) {
                              return page.elements.map(
                                (el) => Positioned(
                                  left: _canvasOffset.dx + _pcbOffset.dx + el.offset.dx,
                                  top: _canvasOffset.dy + _pcbOffset.dy + el.offset.dy,
                                  width: el.size.width,
                                  height: el.size.height,
                                  child: _buildReadonlyPageElement(
                                    el,
                                    overrides: page.propertyOverrides,
                                  ),
                                ),
                              );
                            }),
                            if (_activePage.isOverlay)
                              Positioned(
                                left: _canvasOffset.dx + _pcbOffset.dx,
                                top: _canvasOffset.dy + _pcbOffset.dy,
                                width: _pcbSize.width,
                                height: _pcbSize.height,
                                child: IgnorePointer(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      _pcbRounded ? 20 : 0,
                                    ),
                                    child: Container(
                                      color: const Color(0xFF000000)
                                          .withValues(alpha: 0.28),
                                    ),
                                  ),
                                ),
                              ),
                            if (_activePage.isOverlay &&
                                !_activePageHasOverlayContainerSurface())
                              Positioned(
                                left: _canvasOffset.dx + _pcbOffset.dx + 12,
                                top: _canvasOffset.dy + _pcbOffset.dy + 12,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA000)
                                          .withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.86),
                                      ),
                                    ),
                                    child: const Text(
                                      '当前叠加层缺少容器面，请拖入“面板”作为弹层容器',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // A14-4：linker 连线层。
                            //
                            // 位置很关键：必须在元素**之下**、PCB 之上。
                            // 压在元件上面会挡住文本与消息流内容；
                            // 放到 PCB 之下则会被 PCB 底色整块盖掉。
                            ..._buildAssemblyConnectionsLayer(),
                            // 拖拽中的临时线要盖在元素**之上**——
                            // 正在操作的东西必须看得见，被元件挡住就没法瞄准。
                            if (_isDraggingConnection)
                              _buildDraggingConnectionLine(),
                            ..._elements.map((el) {
                              return Positioned(
                                left: _canvasOffset.dx + _pcbOffset.dx + el.offset.dx,
                                top: _canvasOffset.dy + _pcbOffset.dy + el.offset.dy,
                                width: el.size.width,
                                height: el.size.height,
                                // A14-1d：旋转整个节点，选中虚线框与徽标
                                // 都在其内部，会一起转——只转内容会让
                                // 边框与组件错位（首轮测试反馈）。
                                child: el.rotation == 0.0
                                    ? _buildElementWidget(el)
                                    : Transform.rotate(
                                        angle: el.rotation * math.pi / 180.0,
                                        alignment: Alignment.center,
                                        child: _buildElementWidget(el),
                                      ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ===== 2. 顶栏 =====
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTopIconBtn(
                          Icons.arrow_back_ios_rounded,
                          _handleBackNavigation,
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: _editName,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _modeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _info.name,
                                  style: TextStyle(
                                    color: _modeColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.edit_rounded,
                                  size: 13,
                                  color: _modeColor.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _activePage.isOverlay
                                ? const Color(0xFF37474F).withValues(alpha: 0.12)
                                : const Color(0xFF651FFF).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            _displayPageName(_activePage),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _activePage.isOverlay
                                  ? const Color(0xFF37474F)
                                  : const Color(0xFF651FFF),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        _buildTopIconBtn(
                          Icons.visibility_rounded,
                          _enterRuntimePreview,
                        ),
                        _buildTopIconBtn(
                          Icons.layers_outlined,
                          () => setState(
                            () => _showLayerPanel = !_showLayerPanel,
                          ),
                        ),
                        _buildTopIconBtn(
                          Icons.save_rounded,
                          () {
                            if (!_validateAssemblyBeforeExit()) return;
                            Navigator.pop(context, _exportAssemblyInfoJson());
                          },
                          color: const Color(0xFF00A86B),
                        ),
                      ],
                    ),
                  ),
                ),

                // ===== 2.5 选中元素的左侧操作栏（A14-1b）=====
                //
                // 放左侧而不是像 Studio 那样分列两侧：
                // PCB 的形变把手在右侧与下侧，左边是唯一没被占用的边。
                // 且 Assembly 的 PCB 有固定边界、作者要频繁贴边摆元件，
                // 两侧都放会直接压住最需要精确操作的区域。
                if (_selectedElement != null)
                  Positioned(
                    left: 8,
                    top: 104,
                    bottom: 160,
                    child: _buildElementActionRail(_selectedElement!),
                  ),

                // ===== 2.6 精确位移方向键（A14-1d）=====
                //
                // 底部居中的 3×3 D-Pad，与 Studio 一致。
                // 抬高到资产栏之上：资产栏约 150 高，压在它上面点不到。
                if (_selectedElement != null && _showNudgePad)
                  Positioned(
                    left: MediaQuery.of(context).size.width / 2 - 72,
                    // 贴近资产栏：抽屉展开时会取消选中，两者不会同框，
                    // 因此不需要为抽屉预留高度。
                    bottom: 96,
                    child: _buildNudgePad(_selectedElement!),
                  ),

                // ===== 3. 图层弹出窗 =====
                if (_showLayerPanel)
                  Positioned(top: 48, right: 8, child: _buildLayerPanel()),

                // ===== 4. 底部资产栏 =====
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildAssetDock(),
                ),

                // ===== 5. 顶部下方轻量状态栏 =====
                if (!_showLayerPanel)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 54,
                    // 参数栏与警告条并排：警告独立成块才够醒目，
                    // 混在参数里会被当成又一个数值读数而被忽略。
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(child: _buildCompactStatusHud()),
                        if (_missingKeyActionHint != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: _buildKeyActionWarning(
                              _missingKeyActionHint!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePlacementPointerMove2(PointerMoveEvent e) => _handlePlacementPointerMove(e, context);
  void _finishPlacementPointer2(PointerEvent e) => _finishPlacementPointer(e, context);

  Widget _buildCompactStatusHud() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          // 宽度由外层 Row 的 Flexible 分配：
          // 此处再设 maxWidth 会与并排的警告条争抢空间。
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.46)),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 8),
            ],
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildHudChip(_info.modeLabel, color: _modeColor),
              _buildHudText('${_elements.length} 部件'),
              _buildHudText('PCB ${_pcbSize.width.toStringAsFixed(0)}'
                  '×${_pcbSize.height.toStringAsFixed(0)}'),
              _buildHudText(
                '越界 $_illegalPcbElementCount',
                color: _illegalPcbElementCount > 0
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF555562),
              ),
              _buildHudText('覆写 $_activePropertyOverrideCount'),
            ],
          ),
        ),
      ),
    );
  }

  /// 缺少关键职责按钮的警告条。
  ///
  /// 与参数栏并排的独立胶囊：橙底 + 图标，比混在参数里显眼，
  /// 但仍不打断编辑流程（不弹窗、不遮挡画布）。
  Widget _buildKeyActionWarning(String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFB74D)),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 8),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 11,
                color: Color(0xFFE65100),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 该 UI 缺少关键职责按钮时的提示语；不需要提示时为 null。
  ///
  /// 用大白话说清「会缺什么」，不用「语义角色未绑定」这类术语。
  String? get _missingKeyActionHint {
    if (!UISemanticRole.requiresKeyAction(_info.mode)) return null;
    for (final page in _pages) {
      if (UISemanticRole.hasKeyAction(page.elements)) return null;
    }
    return UISemanticRole.missingHintOf(_info.mode);
  }

  Widget _buildHudChip(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildHudText(String text, {Color color = const Color(0xFF555562)}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// A14-1b：选中元素的左侧操作栏。
  ///
  /// 竖列可滚动——左侧整条边都可用，但小屏 + 未来继续加按钮时
  /// 仍可能溢出，滚动比裁切安全。
  Widget _buildElementActionRail(UIElement element) {
    final layoutLocked = element.layoutLocked;
    final sealed = element.sealed;
    final locked = _isStructureLocked(element);
    // 能否上/下移要按「同层邻居」判断，不能看全局下标——
    // 组内成员只与同组兄弟换位，看全局会误判为还能移动。
    final canMoveUp = _canMoveElementLayer(element, 1);
    final canMoveDown = _canMoveElementLayer(element, -1);

    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 靠左对齐：锁定那一行在展开时会变宽，
          // 不指定的话其余按钮会跟着居中，整列看起来在左右晃。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 锁定：两档共用一格，全锁**向右展开**而非向下。
            //
            //   未锁   → 只有「半锁定」
            //   半锁   → 「已半锁」+ 右侧追加「全锁定」
            //   全锁   → 只有「已全锁」（顶替到半锁的位置）
            //
            // 向右而不是向下的两个理由：
            //   - 并排更能体现「同一组的两个档位」，向下会被当成
            //     与复制 / 删除并列的独立功能；
            //   - 向下插入会把下方所有按钮推移一格，
            //     手指刚点完半锁，复制键就跑到了原本删除键的位置。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!sealed)
                  _buildRailButton(
                    icon: layoutLocked
                        ? Icons.lock_outline_rounded
                        : Icons.lock_open_rounded,
                    label: layoutLocked ? '已半锁' : '半锁定',
                    color: layoutLocked
                        ? const Color(0xFF0288D1)
                        : const Color(0xFF546E7A),
                    onTap: () => _toggleElementLayoutLock(element),
                  ),
                // 全锁按钮只在「已半锁」或「已全锁」时出现。
                // 未锁状态下不显示——避免作者跳过半锁直接全锁，
                // 那样解锁时会突然回落到半锁态，显得没来由。
                if (layoutLocked || sealed) ...[
                  // 间距收到 4：展开态会临时压住 PCB 左缘，
                  // 能省一点是一点（它只在半锁时出现，不是常驻）。
                  if (!sealed) const SizedBox(width: 4),
                  _buildRailButton(
                    icon:
                        sealed ? Icons.lock_rounded : Icons.lock_person_rounded,
                    label: sealed ? '已全锁' : '全锁定',
                    color: sealed
                        ? const Color(0xFFE65100)
                        : const Color(0xFF546E7A),
                    onTap: () => _toggleElementSealed(element),
                  ),
                ],
              ],
            ),
            // 容器归属：把组件放进某个面板，或移出到顶层。
            if (_canAssignSurfaceMembership(element))
              _buildRailButton(
                icon: element.parentSurfaceId != null
                    ? Icons.folder_rounded
                    : Icons.folder_open_rounded,
                label: element.parentSurfaceId != null ? '已归属' : '归属',
                color: element.parentSurfaceId != null
                    ? const Color(0xFF6A1B9A)
                    : const Color(0xFF546E7A),
                onTap:
                    locked ? null : () => _showSurfaceMembershipDialog(element),
              ),
            // 精确几何：X / Y / 宽 / 高 / 旋转，与 Studio 同一套表单。
            //
            // 逻辑件不给这个按钮：它们运行时不渲染，画布上的位置只是
            // 作者自己的归类摆放，拖一下就够了；宽高与旋转对它们更是
            // 没有意义（用户判断）。
            if (!_isLogicOnlyElement(element))
              _buildRailButton(
                icon: Icons.straighten_rounded,
                label: '几何',
                color: const Color(0xFF00838F),
                onTap: locked ? null : () => _showGeometryEditorDialog(element),
              ),
            // 精确位移：展开屏幕底部的方向键盘。
            _buildRailButton(
              icon: Icons.open_with_rounded,
              label: _showNudgePad ? '收起' : '微调',
              color: _showNudgePad
                  ? const Color(0xFF00838F)
                  : const Color(0xFF546E7A),
              onTap: locked
                  ? null
                  : () => setState(() => _showNudgePad = !_showNudgePad),
            ),
            // 锁定后禁止改动结构：这正是锁定的目的。
            _buildRailButton(
              icon: Icons.copy_rounded,
              label: '复制',
              color: const Color(0xFF00897B),
              onTap: locked ? null : () => _duplicateElement(element),
            ),
            _buildRailButton(
              icon: Icons.arrow_upward_rounded,
              label: '上移',
              color: const Color(0xFF3949AB),
              onTap: locked || !canMoveUp
                  ? null
                  : () => _moveElementLayer(element, 1),
            ),
            _buildRailButton(
              icon: Icons.arrow_downward_rounded,
              label: '下移',
              color: const Color(0xFF3949AB),
              onTap: locked || !canMoveDown
                  ? null
                  : () => _moveElementLayer(element, -1),
            ),
            _buildRailButton(
              icon: Icons.delete_outline_rounded,
              label: '删除',
              color: const Color(0xFFC62828),
              onTap: locked ? null : () => _confirmDeleteElement(element),
            ),
          ],
        ),
      ),
    );
  }

  /// A14-1d：精确位移方向键（3×3 D-Pad）。
  ///
  /// 中心按钮显示当前坐标，兼作「这是哪个组件」的确认。
  Widget _buildNudgePad(UIElement element) {
    Widget arrow(IconData icon, Offset delta) => Material(
          color: const Color(0xFF37474F),
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _nudgeElement(element, delta),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        );

    const gap = SizedBox(width: 12, height: 12);
    // 占位宽 = 箭头 40 + 间距 12，才能让上下行的箭头与中间行对齐。
    const blank = SizedBox(width: 52, height: 40);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            blank,
            arrow(Icons.keyboard_arrow_up_rounded, const Offset(0, -1)),
            blank,
          ],
        ),
        gap,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow(Icons.keyboard_arrow_left_rounded, const Offset(-1, 0)),
            gap,
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF546E7A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${element.offset.dx.toStringAsFixed(0)}\n'
                '${element.offset.dy.toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            gap,
            arrow(Icons.keyboard_arrow_right_rounded, const Offset(1, 0)),
          ],
        ),
        gap,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            blank,
            arrow(Icons.keyboard_arrow_down_rounded, const Offset(0, 1)),
            blank,
          ],
        ),
      ],
    );
  }

  Widget _buildRailButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: disabled
            ? const Color(0xFFBDBDBD).withValues(alpha: 0.55)
            : color.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopIconBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: color ?? const Color(0xFF111116))),
      ),
    );
  }

  // ========== 组件渲染 ==========
  Widget _buildElementWidget(UIElement el) {
    final isInsidePcb = _isElementInsidePcb(el);
    if (el.isComposite && el.composite != null) {
      final isSelected = _selectedCompositeId == el.id;
      final displayElement = _applyPropertyOverridesToElement(
        el,
        _propertyOverridesForComposite(el.id),
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectComposite(el.id),
        onDoubleTap: () {
          _selectComposite(el.id);
          _showCompositeOverrideEntryDialog(el);
        },
        onPanStart: (d) {
          _selectComposite(el.id);
          _startTouchScreenPos = d.globalPosition;
          _startTouchElemOffset = el.offset;
        },
        onPanUpdate: (d) {
          final delta = d.globalPosition - _startTouchScreenPos;
          setState(() {
            final i = _elements.indexWhere((e) => e.id == el.id);
            if (i != -1) {
              final desired = _startTouchElemOffset + delta;
              _elements[i] = el.copyWith(
                offset: _applyPlacementConstraints(el, desired),
              );
            }
          });
        },
        onPanEnd: (_) => _persistAssemblyElements(),
        child: SizedBox(
          width: el.size.width,
          height: el.size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                child: UISceneModeScope(
                  isStudioCreationMode: true,
                  // 传去掉旋转的副本：外层 Positioned 已经套了
                  // Transform.rotate，而 UIRenderer.render 内部**也会**
                  // 按 element.rotation 转一次，不剥离就会转两倍
                  // （输入 30° 实际变成 60°）。与 Studio 的 elNoRot 同理。
                  child: Builder(
                    builder: (ctx) => UIRenderer.render(
                      ctx,
                      displayElement.copyWith(rotation: 0.0),
                    ),
                  ),
                ),
              ),
              if (!isInsidePcb)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFE53935),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFE53935)
                            .withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
              if (el.composite!.exposedPorts != null)
                ..._buildExposedPorts(el),
              // 选中外框：与原子组件同一套虚线框。
              //
              // 原先是左上角一枚「实例黑盒」文字标签——它既占地方，
              // 又和其他标签抢位置，且没有指示实际边界。
              // 形状参考复合内部的容器面（见 `_compositeBoundaryOf`）。
              if (isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: DashedSelectionBorderPainter(
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
        ),
      );
    }
    if (el.module != null && el.module!.type == _AssemblyLogic._pageRouterType) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _showPageRouterConfigDialog(el),
        onPanStart: (d) {
          _startTouchScreenPos = d.globalPosition;
          _startTouchElemOffset = el.offset;
        },
        onPanUpdate: (d) {
          final delta = d.globalPosition - _startTouchScreenPos;
          setState(() {
            final i = _elements.indexWhere((e) => e.id == el.id);
            if (i != -1) {
              _elements[i] = el.copyWith(offset: _startTouchElemOffset + delta);
            }
          });
        },
        onPanEnd: (_) => _persistAssemblyElements(),
        child: Container(
          width: el.size.width,
          height: el.size.height,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00897B).withValues(alpha: 0.45)),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.alt_route_rounded, size: 15, color: Color(0xFF00897B)),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '页面路由器',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF00695C),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _pageRouterSubtitle(el.module!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF33695F),
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // A14-4 第二步：linker 有专属的三段式交互——
    // 左右两侧是接线热区（拖出连线 / 双击断开），中间才是点击与拖动。
    // linker 是唯一可以拉出接线的组件（用户明确约束）。
    if (el.module != null && el.module!.type == 'linker') {
      return _buildLinkerElementWidget(el);
    }
    if (el.module != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 编辑态不执行任何联动效果（含页面跳转）。
        // 制作与预览分离：编辑时的点击 / 拖动很容易误触发，
        // 且组件状态会被 _persistAssemblyElements 一并存下，污染保存结果。
        // 切页请用图层面板，联动效果请进运行时预览。
        // A14-1a：点击即选中，左侧操作栏据此显示。
        // button 仍要给出编辑态提示，避免作者以为点击没反应。
        onTap: () {
          _selectElement(el.id);
          if (el.module!.type == 'button') _showEditModeHint();
        },
        // linker 已在上面提前返回，这里不会再遇到它。
        onDoubleTap: () {
          _selectElement(el.id);
          _showAtomInstanceEditorDialog(el);
        },
        onPanStart: (d) {
          _selectElement(el.id);
          _startTouchScreenPos = d.globalPosition;
          _startTouchElemOffset = el.offset;
        },
        // A14-1b：半锁 / 全锁都禁止拖动。仍允许选中与双击编辑——
        // 锁定针对的是「误拖走位」，不是「不让改配置」。
        onPanUpdate: (el.layoutLocked || el.sealed)
            ? null
            : (d) {
                final delta = d.globalPosition - _startTouchScreenPos;
                setState(() {
                  final i = _elements.indexWhere((e) => e.id == el.id);
                  if (i != -1) {
                    _elements[i] =
                        el.copyWith(offset: _startTouchElemOffset + delta);
                  }
                });
              },
        onPanEnd: (_) => _persistAssemblyElements(),
        child: SizedBox(
          width: el.size.width,
          height: el.size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: UISceneModeScope(
                    isStudioCreationMode: true,
                    // 同上：旋转由外层统一负责，这里必须剥离。
                    child: Builder(
                      builder: (ctx) =>
                          UIRenderer.render(ctx, el.copyWith(rotation: 0.0)),
                    ),
                  ),
                ),
              ),
              // A14-1a：选中外框。
              //
              // 与 Studio 共用 `StudioAlternatingDashedBorderPainter`：
              // 虚线框会**按组件自身形状**描边（圆形指示点画圆、开关画胶囊、
              // 心形进度条画心形），而不是一律套圆角矩形。
              //
              // 用 Positioned.fill + CustomPaint 而非给容器加 border——
              // 后者会改变布局尺寸，让组件在选中/取消时跳动。
              if (_selectedElementId == el.id)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: DashedSelectionBorderPainter(
                        strokeWidth: 1.2,
                        shape: _outlineShapeOf(el),
                        borderRadius: _outlineBorderRadiusOf(el),
                        isPerfectCircle: _isPerfectCircleOutlineOf(el),
                      ),
                    ),
                  ),
                ),
              // A14-1e：标签流式排列。
              //
              // 原先四个标签各写死一组坐标，锁定（left:2）与容器面（left:4）
              // 直接重叠；每加一个新标签都要重找空位。
              // 改为顶部一行、底部一行，新标签往后接即可。
              if (_topBadgesOf(el).isNotEmpty)
                Positioned(
                  left: 2,
                  right: 2,
                  top: -14,
                  child: IgnorePointer(
                    child: _buildBadgeRow(_topBadgesOf(el)),
                  ),
                ),
              if (_bottomBadgesOf(el).isNotEmpty)
                Positioned(
                  left: 2,
                  right: 2,
                  bottom: -14,
                  child: IgnorePointer(
                    child: _buildBadgeRow(_bottomBadgesOf(el)),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: el.size.width,
      height: el.size.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  /// linker 的三段式交互节点。
  ///
  /// 布局（与 Studio 同构，热区宽度按 Assembly 收窄）：
  ///
  /// ```
  /// ┌──────┬──────────────┬──────┐
  /// │ 24px │   中间区域    │ 24px │
  /// │ 接线 │ 点击弹方案    │ 接线 │
  /// │ 左侧 │ 拖动挪位置    │ 右侧 │
  /// └──────┴──────────────┴──────┘
  /// ```
  ///
  /// 热区用 `Listener.onPointerDown` 而非 `GestureDetector.onPanStart`：
  /// pan 需要先跨过 kTouchSlop 才触发，那段距离里手指已经移开，
  /// 起点会不准；而且会与外层的画布平移进入手势竞技场互相抢。
  Widget _buildLinkerElementWidget(UIElement el) {
    final isSelected = _selectedElementId == el.id;

    Widget portZone(String port) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) =>
            _beginConnectionDrag(el, port, event.position),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 双击该侧热区断开这一端，与 Studio 一致。
          onDoubleTap: () => _disconnectLinkerPort(el, port),
          child: SizedBox(
            width: _AssemblyLogic.kLinkerPortHotZone,
            height: double.infinity,
          ),
        ),
      );
    }

    return SizedBox(
      width: el.size.width,
      height: el.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: UISceneModeScope(
                isStudioCreationMode: true,
                child: Builder(
                  builder: (ctx) =>
                      UIRenderer.render(ctx, el.copyWith(rotation: 0.0)),
                ),
              ),
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DashedSelectionBorderPainter(
                    strokeWidth: 1.2,
                    shape: _outlineShapeOf(el),
                    borderRadius: _outlineBorderRadiusOf(el),
                    isPerfectCircle: _isPerfectCircleOutlineOf(el),
                  ),
                ),
              ),
            ),
          // 接线端点提示：让作者一眼看出「这两侧能拉线」。
          // 已连上的一侧实心，未连的空心。
          Positioned.fill(
            child: IgnorePointer(
              child: _buildLinkerPortHints(el),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                portZone('input'),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 点击 linker 弹方案选择（用户明确约束）。
                    onTap: () {
                      _selectElement(el.id);
                      _showAssemblyLinkerConfigDialog(el);
                    },
                    onPanStart: (d) {
                      if (_isDraggingConnection) return;
                      _selectElement(el.id);
                      _startTouchScreenPos = d.globalPosition;
                      _startTouchElemOffset = el.offset;
                    },
                    onPanUpdate: (el.layoutLocked || el.sealed)
                        ? null
                        : (d) {
                            // 接线进行中不挪元件，否则线的起点跟着跑。
                            if (_isDraggingConnection) return;
                            final delta =
                                d.globalPosition - _startTouchScreenPos;
                            setState(() {
                              final i = _elements
                                  .indexWhere((e) => e.id == el.id);
                              if (i != -1) {
                                _elements[i] = el.copyWith(
                                  offset: _startTouchElemOffset + delta,
                                );
                              }
                            });
                          },
                    onPanEnd: (_) {
                      if (_isDraggingConnection) return;
                      _persistAssemblyElements();
                    },
                  ),
                ),
                portZone('output'),
              ],
            ),
          ),
          if (_topBadgesOf(el).isNotEmpty)
            Positioned(
              left: 2,
              right: 2,
              top: -14,
              child: IgnorePointer(child: _buildBadgeRow(_topBadgesOf(el))),
            ),
          if (_bottomBadgesOf(el).isNotEmpty)
            Positioned(
              left: 2,
              right: 2,
              bottom: -14,
              child: IgnorePointer(child: _buildBadgeRow(_bottomBadgesOf(el))),
            ),
        ],
      ),
    );
  }

  /// linker 两侧的接线端点提示。
  ///
  /// 实心 = 该端已连；空心 = 未连。作者不必打开对话框就能看出
  /// 「这条还差哪一端」，配合连线本身形成完整反馈。
  Widget _buildLinkerPortHints(UIElement el) {
    final data = el.module?.properties['linker'];
    final map = data is Map ? data : const {};
    final hasSource =
        (map['sourceModuleId']?.toString() ?? '').isNotEmpty;
    final hasTarget =
        (map['targetModuleId']?.toString() ?? '').isNotEmpty;

    Widget dot(bool filled, Color color) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: filled ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        // 垂直居中：端口在元件的左中 / 右中，与连线端点位置对应
        // （见 _assemblyPortOffset）。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          dot(hasSource, LinkerLineColors.input),
          dot(hasTarget, LinkerLineColors.output),
        ],
      ),
    );
  }

  List<Widget> _buildExposedPorts(UIElement el) {
    final ports = el.composite!.exposedPorts!
        .where((p) => el.composite!.children.any((c) => c.id == p.elementId))
        .toList();
    final bodyH = el.size.height;
    final widgets = <Widget>[];

    Offset rotatePortCenter(Offset point) {
      if (el.rotation == 0.0) return point;
      final radians = el.rotation * 3.1415926535897932 / 180.0;
      final center = Offset(el.size.width / 2, el.size.height / 2);
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      return Offset(
        center.dx + dx * math.cos(radians) - dy * math.sin(radians),
        center.dy + dx * math.sin(radians) + dy * math.cos(radians),
      );
    }

    final leftPorts = ports.where((p) => p.exposeInput).toList();
    final rightPorts = ports.where((p) => p.exposeOutput).toList();

    for (var i = 0; i < leftPorts.length; i++) {
      final child =
          el.composite!.children.firstWhere((c) => c.id == leftPorts[i].elementId);
      final color = _portColor(leftPorts[i], child.module?.type ?? '');
      final double centerY = (bodyH / (leftPorts.length + 1)) * (i + 1);
      final center = rotatePortCenter(Offset(0, centerY));
      widgets.add(
        _buildSimpleExposedPort(
          center: center,
          color: color,
          tooltip: '输入端口 · ${child.module?.name ?? child.id}',
        ),
      );
    }

    for (var i = 0; i < rightPorts.length; i++) {
      final child =
          el.composite!.children.firstWhere((c) => c.id == rightPorts[i].elementId);
      final color = _portColor(rightPorts[i], child.module?.type ?? '');
      final double centerY = (bodyH / (rightPorts.length + 1)) * (i + 1);
      final center = rotatePortCenter(Offset(el.size.width, centerY));
      widgets.add(
        _buildSimpleExposedPort(
          center: center,
          color: color,
          tooltip: '输出端口 · ${child.module?.name ?? child.id}',
        ),
      );
    }
    return widgets;
  }

  Widget _buildSimpleExposedPort({
    required Offset center,
    required Color color,
    required String tooltip,
  }) {
    return Positioned(
      left: center.dx - 6,
      top: center.dy - 6,
      width: 12,
      height: 12,
      child: Tooltip(
        message: tooltip,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }

  Color _portColor(ExposedPort port, String type) {
    if (port.customColor != null) return Color(port.customColor!);
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

  Widget _buildReadonlyPageElement(
    UIElement el, {
    List<PropertyOverride> overrides = const <PropertyOverride>[],
  }) {
    final displayElement = _applyPropertyOverridesToElement(el, overrides);
    return IgnorePointer(
      child: Opacity(
        opacity: 0.35,
        child: SizedBox(
          width: el.size.width,
          height: el.size.height,
          child: UIRenderer.render(context, displayElement),
        ),
      ),
    );
  }

  Widget _buildLayerPanel() {
    final rootPage = _rootBasePage;
    final rootOverlays = _directChildPages(rootPage.id);
    final siblingBasePages = _directChildPages(null)
        .where((page) => page.id != rootPage.id)
        .toList();

    return Container(
      width: 248,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '页面图层',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111116),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _createPage(type: 'base'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF651FFF).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '+ 平级',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF651FFF),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _createPage(type: 'overlay'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF37474F).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '+ 叠加',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPageTile(
                    rootPage,
                    depth: 0,
                    draggable: false,
                    showMenuBadge: true,
                  ),
                  if (rootOverlays.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildPageGroup(
                        rootPage.id,
                        1,
                      ),
                    ),
                  if (siblingBasePages.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Text(
                        '其他平级页',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF888896),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildPageGroup(null, 0, excludeRoot: true),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageGroup(
    String? parentPageId,
    int depth, {
    bool excludeRoot = false,
  }) {
    final children = _directChildPages(parentPageId)
        .where((page) => !excludeRoot || !_isRootBasePage(page))
        .toList();
    if (children.isEmpty) return const SizedBox.shrink();

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) => _reorderPageGroup(
        parentPageId,
        oldIndex,
        newIndex,
        excludeRoot: excludeRoot,
      ),
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Transform.scale(
          scale: 1.0 + animation.value * 0.04,
          child: Material(
            color: Colors.transparent,
            elevation: 6 * animation.value,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        ),
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final page = children[index];
        return Container(
          key: ValueKey('page_${page.id}'),
          margin: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPageTile(
                page,
                depth: depth,
                draggable: !_isRootBasePage(page),
                dragIndex: index,
              ),
              if (_directChildPages(page.id).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildPageGroup(page.id, depth + 1),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageTile(
    AssemblyPage page, {
    required int depth,
    required bool draggable,
    bool showMenuBadge = false,
    int? dragIndex,
  }) {
    final selected = page.id == _activePage.id;
    final bool isOverlay = page.isOverlay;
    final background = selected
        ? (isOverlay
            ? const Color(0xFF455A64)
            : const Color(0xFF5E35B1))
        : (isOverlay
            ? const Color(0xFFF2F4F7)
            : const Color(0xFFF8F7FC));
    final foreground = selected ? Colors.white : const Color(0xFF111116);
    final accent = isOverlay
        ? const Color(0xFF546E7A)
        : const Color(0xFF651FFF);

    Widget tile = Container(
      margin: EdgeInsets.only(left: depth * 16.0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? const Color(0xFFB2EBF2)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: ListTile(
        dense: true,
        minLeadingWidth: 18,
        visualDensity: const VisualDensity(vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Icon(
          isOverlay ? Icons.layers_outlined : Icons.crop_square_rounded,
          size: 16,
          color: selected ? Colors.white : accent,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _displayPageName(page),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
            if (showMenuBadge)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : const Color(0xFF651FFF).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '主菜单',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : const Color(0xFF651FFF),
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _showPageGestureDialog(page),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.swipe_rounded,
                  size: 14,
                  color: selected ? Colors.white : const Color(0xFF555562),
                ),
              ),
            ),
            if (!_isRootBasePage(page))
              InkWell(
                onTap: () => _renamePage(page),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: selected ? Colors.white : const Color(0xFF555562),
                  ),
                ),
              ),
            if (page.isOverlay)
              InkWell(
                onTap: () => _showReparentPageDialog(page),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.drive_file_move_rounded,
                    size: 15,
                    color: selected ? Colors.white : const Color(0xFF555562),
                  ),
                ),
              ),
            if (draggable)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF555562),
                ),
              ),
          ],
        ),
        onTap: () => _activatePage(page.id),
      ),
    );

    if (draggable && dragIndex != null) {
      return ReorderableDelayedDragStartListener(
        index: dragIndex,
        child: tile,
      );
    }
    return tile;
  }

  Widget _buildAssetDock() {
    final panelHeight = _showAssetDrawer ? 124.0 : 40.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: panelHeight,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.46)),
                boxShadow: const [
                  BoxShadow(color: Color(0x16000000), blurRadius: 12),
                ],
              ),
              child: Column(
                children: [
                  if (_showAssetDrawer)
                    SizedBox(
                      height: 82,
                      child: _buildAssetDrawerContent(_activeAssetCategory),
                    ),
                  if (_showAssetDrawer)
                    Divider(
                      height: 1,
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  SizedBox(
                    height: _showAssetDrawer ? 39 : 38,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          _buildAssetCategoryTab('logic', Icons.account_tree_rounded, '逻辑组件'),
                          _buildAssetCategoryTab('interaction', Icons.touch_app_rounded, '基础交互'),
                          _buildAssetCategoryTab('display', Icons.text_fields_rounded, '基础显示'),
                          _buildAssetCategoryTab('composite', Icons.dashboard_customize_rounded, '复合组件'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssetCategoryTab(String id, IconData icon, String label) {
    final selected = _showAssetDrawer && _activeAssetCategory == id;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            if (selected) {
              _showAssetDrawer = false;
            } else {
              _activeAssetCategory = id;
              _showAssetDrawer = true;
              _showLayerPanel = false;
              // A14-1d：打开资产抽屉即取消选中。
              // 微调键盘紧贴资产栏，抽屉展开时两者必然重叠；
              // 取消选中比做避让逻辑更干净——作者要拖新组件了，
              // 本来也不再关心上一个选中项。
              _selectedCompositeId = null;
              _showNudgePad = false;
            }
          });
        },
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: selected
                ? _modeColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? _modeColor : const Color(0xFF555562),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _modeColor : const Color(0xFF555562),
                  fontSize: 8,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetDrawerContent(String category) {
    final items = _assetItemsForCategory(category);
    if (items.isEmpty) {
      return Center(
        child: Text(
          category == 'composite'
              ? '暂无可用复合资产\n请先在工作室制作并暴露端口'
              : '该分类暂无可用资产',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF888896),
            fontSize: 10,
            height: 1.35,
          ),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => _buildDraggableAsset(
        payload: items[index].payload,
        child: _buildDockAssetCard(items[index]),
      ),
    );
  }

  List<_AssemblyAssetItem> _assetItemsForCategory(String category) {
    switch (category) {
      case 'logic':
        return [
          _AssemblyAssetItem.module(
            title: '页面路由器',
            subtitle: '切页 / 叠加',
            icon: Icons.alt_route_rounded,
            color: const Color(0xFF00897B),
            module: _pageRouterTemplate,
          ),
          _AssemblyAssetItem.module(
            title: '联动器',
            subtitle: '连接事件',
            icon: Icons.hub_rounded,
            color: const Color(0xFF00ACC1),
            module: _assetModuleTemplate('atom_linker_basic'),
          ),
          // A14-2：这两个是纯逻辑件，运行时隐形。
          // 渲染、尺寸预设、linker 方案早就齐了，只是一直没有资产栏入口，
          // 导致「定时触发剧情」「属性公式计算」这两类玩法做不了。
          _AssemblyAssetItem.module(
            title: '定时器',
            subtitle: '周期脉冲',
            icon: Icons.timer_rounded,
            color: const Color(0xFFFF9100),
            module: _assetModuleTemplate('atom_timer_basic'),
          ),
          _AssemblyAssetItem.module(
            title: '计算节点',
            subtitle: '数值运算',
            icon: Icons.calculate_rounded,
            color: const Color(0xFF7E57C2),
            module: _assetModuleTemplate('atom_logic_math_node'),
          ),
        ];
      case 'interaction':
        return [
          _AssemblyAssetItem.module(
            title: '按钮',
            subtitle: '点击事件源',
            icon: Icons.smart_button_rounded,
            color: const Color(0xFF757575),
            module: _assetModuleTemplate('atom_logic_button_tap'),
          ),
          _AssemblyAssetItem.module(
            title: '输入框',
            subtitle: '文本输入',
            icon: Icons.input_rounded,
            color: const Color(0xFF2979FF),
            module: _assetModuleTemplate('atom_logic_input_text'),
          ),
          _AssemblyAssetItem.module(
            title: '开关',
            subtitle: '布尔状态',
            icon: Icons.toggle_on_rounded,
            color: const Color(0xFF00E676),
            module: _assetModuleTemplate('atom_logic_switch_bool'),
          ),
          _AssemblyAssetItem.module(
            title: '滑块',
            subtitle: '数值输入',
            icon: Icons.tune_rounded,
            color: const Color(0xFF00ACC1),
            module: _assetModuleTemplate('atom_slider_basic'),
          ),
          _AssemblyAssetItem.module(
            title: '下拉',
            subtitle: '选项选择',
            icon: Icons.list_alt_rounded,
            color: const Color(0xFF7E57C2),
            module: _assetModuleTemplate('atom_select_basic'),
          ),
        ];
      case 'display':
        return [
          _AssemblyAssetItem.module(
            title: '面板',
            subtitle: '叠加容器',
            icon: Icons.crop_square_rounded,
            color: const Color(0xFF651FFF),
            module: _assetModuleTemplate('atom_surface_base'),
          ),
          _AssemblyAssetItem.module(
            title: '文本',
            subtitle: '显示文字',
            icon: Icons.text_fields_rounded,
            color: const Color(0xFF5E35B1),
            module: _assetModuleTemplate('atom_text'),
          ),
          _AssemblyAssetItem.module(
            title: '消息流',
            subtitle: '对话历史窗口',
            icon: Icons.forum_rounded,
            color: const Color(0xFF3949AB),
            module: _assetModuleTemplate('atom_message_flow'),
          ),
          _AssemblyAssetItem.module(
            title: '进度条',
            subtitle: '数值显示',
            icon: Icons.stacked_line_chart_rounded,
            color: const Color(0xFFFF4081),
            module: _assetModuleTemplate('atom_data_bar'),
          ),
          _AssemblyAssetItem.module(
            title: '图片',
            subtitle: '图片槽位',
            icon: Icons.image_rounded,
            color: const Color(0xFF2979FF),
            module: _assetModuleTemplate('atom_image_holder'),
          ),
          _AssemblyAssetItem.module(
            title: '状态点',
            subtitle: '状态指示',
            icon: Icons.circle_rounded,
            color: const Color(0xFF4CAF50),
            module: _assetModuleTemplate('atom_indicator_basic'),
          ),
          _AssemblyAssetItem.module(
            title: '分割线',
            subtitle: '线条分隔',
            icon: Icons.horizontal_rule_rounded,
            color: const Color(0xFFB0BEC5),
            module: _assetModuleTemplate('atom_line_multi'),
          ),
        ];
      case 'composite':
        return _assetService
            .getAllComposites()
            .where((c) => c.exposedPorts != null && c.exposedPorts!.isNotEmpty)
            .map(_AssemblyAssetItem.composite)
            .toList();
      default:
        return const <_AssemblyAssetItem>[];
    }
  }

  Widget _buildDraggableAsset({
    required _AssemblyDragPayload payload,
    required Widget child,
  }) {
    return Listener(
      onPointerDown: (event) {
        payload.pointerId = event.pointer;
        payload.anchorFraction = const Offset(0.5, 0.5);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) =>
            _startLibraryPlacement(payload, details.globalPosition, context),
        child: ValueListenableBuilder<bool>(
          valueListenable: payload.isLibraryDragging,
          child: child,
          builder: (context, isDragging, child) => AnimatedScale(
            scale: isDragging ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isDragging ? 0.48 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockAssetCard(_AssemblyAssetItem item) {
    return SizedBox(
      width: 92,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: item.color.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 16, color: item.color),
            const SizedBox(height: 5),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111116),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF777783),
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A14-1e：顶部标签（锁定 / 容器面 / 数据通道）。
  ///
  /// 顺序即优先级：状态类在前、配置类在后。
  /// 新增标签直接往列表里加，不用再找空位。
  List<Widget> _topBadgesOf(UIElement el) {
    final badges = <Widget>[];

    if (el.layoutLocked || el.sealed) {
      // 全锁橙色实心锁，半锁蓝色空心锁，一眼区分档位。
      badges.add(_buildIconBadge(
        icon: el.sealed ? Icons.lock_rounded : Icons.lock_outline_rounded,
        color: el.sealed ? const Color(0xFFE65100) : const Color(0xFF0288D1),
      ));
    }

    if (el.module?.properties['is_overlay_container'] == true) {
      badges.add(_buildTextBadge('容器面', const Color(0xFFE65100)));
    }

    final channel = _dataChannelOf(el.module);
    if (channel != null) {
      badges.add(_buildDataChannelChip(channel));
    }

    return badges;
  }

  /// 底部标签（关键职责）。
  List<Widget> _bottomBadgesOf(UIElement el) {
    final badges = <Widget>[];
    if (UISemanticRole.isKeyAction(el.module)) {
      badges.add(_buildTextBadge(
        UISemanticRole.actionLabelOf(_info.mode),
        UISemanticRole.colorOf(_info.mode),
      ));
    }
    return badges;
  }

  /// 标签行：横向排列，超出组件宽度时换行而不是被裁掉。
  Widget _buildBadgeRow(List<Widget> badges) {
    return Wrap(
      spacing: 3,
      runSpacing: 2,
      children: badges,
    );
  }

  Widget _buildTextBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          height: 1.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildIconBadge({required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 9, color: Colors.white),
    );
  }

  Widget _buildDataChannelChip(Map<String, dynamic> channel) {
    final summary = _dataChannelSummary(channel);
    final color = _dataChannelChipColor(channel);
    return Container(
      constraints: const BoxConstraints(maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86), width: 0.7),
      ),
      child: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          height: 1.0,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _editName() {
    final ctrl = TextEditingController(text: _info.name);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('编辑名称', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold)),
      content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Color(0xFF111116)),
        decoration: const InputDecoration(hintText: 'UI 名称', hintStyle: TextStyle(color: Color(0xFF888896)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD0D0D8))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF651FFF))))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Color(0xFF888896)))),
        TextButton(onPressed: () {
          final n = ctrl.text.trim();
          if (n.isNotEmpty) setState(() => _info.name = n);
          Navigator.pop(ctx);
        }, child: const Text('确定', style: TextStyle(color: Color(0xFF651FFF), fontWeight: FontWeight.bold))),
      ],
    ));
  }

  Color get _modeColor => switch (_info.mode) {
    'opening' => const Color(0xFF7E57C2),
    'scene' => const Color(0xFFE65100),
    'extra_sticky' => const Color(0xFF00838F),
    'extra_companion' => const Color(0xFF00ACC1),
    _ => const Color(0xFF651FFF),
  };
}

class _AssemblyGridPainter extends CustomPainter {
  final Offset offset;
  _AssemblyGridPainter(this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x28A0A0B0)
      ..strokeWidth = 0.6;
    const g = 40.0;
    for (double x = offset.dx % g; x < size.width; x += g) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), p); }
    for (double y = offset.dy % g; y < size.height; y += g) { canvas.drawLine(Offset(0, y), Offset(size.width, y), p); }
  }

  @override
  bool shouldRepaint(covariant _AssemblyGridPainter old) => old.offset != offset;
}
