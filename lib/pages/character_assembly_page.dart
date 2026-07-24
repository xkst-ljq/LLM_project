import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ui_assembly_info.dart';
import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

part 'character_assembly_page/logic.dart';

/// 拖拽载荷
class _AssemblyDragPayload {
  final UIComposite? composite;
  Offset anchorFraction = const Offset(0.5, 0.5);
  String? spawnedElementId;
  int? pointerId;
  Offset? lastPointerGlobalPosition;
  Offset? longPressOrigin;
  final ValueNotifier<bool> isLibraryDragging = ValueNotifier(false);

  _AssemblyDragPayload({this.composite});
}

class CharacterAssemblyPage extends StatefulWidget {
  final UIAssemblyInfo assemblyInfo;
  const CharacterAssemblyPage({super.key, required this.assemblyInfo});
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _info.toJsonString());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE8E8EC),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: _handlePlacementPointerMove2,
          onPointerUp: _finishPlacementPointer2,
          onPointerCancel: _finishPlacementPointer2,
          child: Stack(
            children: [
              // ===== 1. 无限画布 + PCB =====
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _showAssetDrawer || _showLayerPanel
                      ? null
                      : (details) => setState(() => _canvasOffset += details.delta),
                  onTap: () {
                    if (_showAssetDrawer) setState(() => _showAssetDrawer = false);
                    if (_showLayerPanel) setState(() => _showLayerPanel = false);
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
                                boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2))],
                              ),
                            ),
                          ),
                          ..._elements.map((el) {
                            const portPad = 6.0;
                            return Positioned(
                              left: _canvasOffset.dx + _pcbOffset.dx + el.offset.dx - portPad,
                              top: _canvasOffset.dy + _pcbOffset.dy + el.offset.dy - portPad,
                              width: el.size.width + portPad * 2,
                              height: el.size.height + portPad * 2,
                              child: _buildElementWidget(el),
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
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
                  ),
                  child: Row(children: [
                    _buildTopIconBtn(Icons.arrow_back_ios_rounded, () => Navigator.pop(context, _info.toJsonString())),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: _editName,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _modeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_info.name, style: TextStyle(color: _modeColor, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                          const SizedBox(width: 5),
                          Icon(Icons.edit_rounded, size: 13, color: _modeColor.withValues(alpha: 0.7)),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    _buildAssetBtn(),
                    const SizedBox(width: 4),
                    _buildTopIconBtn(Icons.layers_outlined, () => setState(() => _showLayerPanel = !_showLayerPanel)),
                    _buildTopIconBtn(Icons.save_rounded, () => Navigator.pop(context, _info.toJsonString()), color: const Color(0xFF00A86B)),
                  ]),
                ),
              ),

              // ===== 3. 图层弹出窗 =====
              if (_showLayerPanel)
                Positioned(top: 48, right: 8, child: _buildLayerPanel()),

              // ===== 4. 资产栏下拉 =====
              if (_showAssetDrawer)
                Positioned(top: 48, left: 0, bottom: 0, width: 160, child: _buildAssetDrawer()),

              // ===== 5. 右下角悬浮信息 =====
              Positioned(
                right: 12, bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111116).withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: _modeColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                      child: Text(_info.modeLabel, style: TextStyle(color: _modeColor, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Text('${_elements.length} 部件', style: const TextStyle(color: Colors.white54, fontSize: 9)),
                    const SizedBox(width: 8),
                    const Text('0 连线', style: TextStyle(color: Colors.white54, fontSize: 9)),
                    const SizedBox(width: 8),
                    const Text('0 变量', style: TextStyle(color: Colors.white54, fontSize: 9)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePlacementPointerMove2(PointerMoveEvent e) => _handlePlacementPointerMove(e, context);
  void _finishPlacementPointer2(PointerEvent e) => _finishPlacementPointer(e, context);

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

  Widget _buildAssetBtn() {
    return GestureDetector(
      onTap: () => setState(() => _showAssetDrawer = !_showAssetDrawer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _showAssetDrawer ? const Color(0xFF651FFF).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.dashboard_customize_rounded, size: 16, color: _showAssetDrawer ? const Color(0xFF651FFF) : const Color(0xFF555562)),
          const SizedBox(width: 4),
          Text('资产库', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _showAssetDrawer ? const Color(0xFF651FFF) : const Color(0xFF555562))),
          const SizedBox(width: 2),
          Icon(_showAssetDrawer ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, size: 16, color: _showAssetDrawer ? const Color(0xFF651FFF) : const Color(0xFF555562)),
        ]),
      ),
    );
  }

  // ========== 组件渲染 ==========
  Widget _buildElementWidget(UIElement el) {
    if (el.isComposite && el.composite != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) { _startTouchScreenPos = d.globalPosition; _startTouchElemOffset = el.offset; },
        onPanUpdate: (d) {
          final delta = d.globalPosition - _startTouchScreenPos;
          setState(() {
            final i = _elements.indexWhere((e) => e.id == el.id);
            if (i != -1) _elements[i] = el.copyWith(offset: _startTouchElemOffset + delta);
          });
        },
        child: SizedBox(
          width: el.size.width,
          height: el.size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                child: UISceneModeScope(
                  isStudioCreationMode: false,
                  child: Builder(builder: (ctx) => UIRenderer.render(ctx, el)),
                ),
              ),
              if (el.composite!.exposedPorts != null)
                ..._buildExposedPorts(el),
            ],
          ),
        ),
      );
    }
    if (el.module != null && const {'linker', 'math_node', 'timer'}.contains(el.module!.type)) {
      return Container(
        width: el.size.width, height: el.size.height,
        decoration: BoxDecoration(color: const Color(0xFF651FFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF651FFF).withValues(alpha: 0.25))),
        alignment: Alignment.center,
        child: Text(el.module!.type, style: const TextStyle(color: Color(0xFF651FFF), fontSize: 9)),
      );
    }
    return Container(width: el.size.width, height: el.size.height,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)));
  }

  List<Widget> _buildExposedPorts(UIElement el) {
    final ports = el.composite!.exposedPorts!
        .where((p) => el.composite!.children.any((c) => c.id == p.elementId))
        .toList();
    final bodyH = el.size.height;
    final widgets = <Widget>[];

    final leftPorts = ports.where((p) => p.exposeInput).toList();
    final rightPorts = ports.where((p) => p.exposeOutput).toList();

    // 左侧接收端口
    for (var i = 0; i < leftPorts.length; i++) {
      final child = el.composite!.children.firstWhere((c) => c.id == leftPorts[i].elementId);
      final color = _portColor(leftPorts[i], child.module?.type ?? '');
      final double centerY = (bodyH / (leftPorts.length + 1)) * (i + 1);
      widgets.add(Positioned(
        left: -6, top: centerY - 6,
        width: 12, height: 12,
        child: Container(
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
        ),
      ));
    }
    // 右侧输出端口
    for (var i = 0; i < rightPorts.length; i++) {
      final child = el.composite!.children.firstWhere((c) => c.id == rightPorts[i].elementId);
      final color = _portColor(rightPorts[i], child.module?.type ?? '');
      final double centerY = (bodyH / (rightPorts.length + 1)) * (i + 1);
      widgets.add(Positioned(
        left: el.size.width - 6, top: centerY - 6,
        width: 12, height: 12,
        child: Container(
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
        ),
      ));
    }
    return widgets;
  }

  Color _portColor(ExposedPort port, String type) {
    if (port.customColor != null) return Color(port.customColor!);
    switch (type) {
      case 'progress': case 'slider': return const Color(0xFF00E676);
      case 'text':   case 'select': case 'input': return const Color(0xFF651FFF);
      case 'switch': return const Color(0xFFFFA726);
      case 'button': return const Color(0xFFFFD740);
      default: return const Color(0xFF9E9E9E);
    }
  }

  Widget _buildLayerPanel() {
    return Container(
      width: 200,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 12)]),
      child: const Padding(padding: EdgeInsets.all(16),
        child: Text('图层列表（A6 实现）', style: TextStyle(color: Color(0xFF888896), fontSize: 12))),
    );
  }

  Widget _buildAssetDrawer() {
    final composites = _assetService.getAllComposites()
        .where((c) => c.exposedPorts != null && c.exposedPorts!.isNotEmpty).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: Border(right: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
      ),
      child: Column(children: [
        if (composites.isEmpty)
          const Expanded(child: Center(child: Text('暂无可用资产\n请先在工作室制作\n并暴露端口',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF888896), fontSize: 10, height: 1.4))))
        else
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: composites.length,
            itemBuilder: (ctx, i) {
              final c = composites[i];
              final payload = _AssemblyDragPayload(composite: c);
              return Listener(
                onPointerDown: (event) {
                  payload.pointerId = event.pointer;
                  payload.anchorFraction = const Offset(0.5, 0.5);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: (details) => _startLibraryPlacement(payload, details.globalPosition, context),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: payload.isLibraryDragging,
                    child: _buildAssetCard(c),
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
            },
          )),
      ]),
    );
  }

  Widget _buildAssetCard(UIComposite c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFF2F2F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: const TextStyle(color: Color(0xFF111116), fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text('${c.exposedPorts!.length} 端口', style: const TextStyle(color: Color(0xFF888896), fontSize: 9)),
      ]),
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
