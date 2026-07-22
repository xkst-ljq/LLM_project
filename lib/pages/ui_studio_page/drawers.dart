part of 'ui_studio_page.dart';

/// 侧边抽屉
mixin _UIStudioDrawers on _UIStudioLogic, _UIStudioDialogs {
  // ===== 左侧原材料抽屉 =====
  Widget _buildLeftCompactAssetPreviewDrawer() {
    final modules = _assetService.getFoundationModules();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 16, 8, 8),
                child: Center(child: Text('原材料', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13))),
              ),
              const Divider(color: Colors.black12),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: modules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final module = modules[index];
                    return Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4E4EA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCDCE4),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                module.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF555562),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildPreviewDraggableCard(module),
                        ],
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

  /// 左侧原材料预览与画布共用 UIRenderer，确保默认形态不再有两套实现。
  Widget _buildPreviewDraggableCard(UIModule module) {
    final payload = DragPayload(module: module);
    final previewSize = _initialSizeForModule(module);
    final previewElement = UIElement(
      id: 'asset_preview_${module.id}',
      module: module,
      size: previewSize,
      isComposite: false,
    );
    final visualPreview = LayoutBuilder(
      builder: (context, constraints) {
        const previewHeight = 66.0;
        final availableWidth = constraints.maxWidth;
        final scale = math.min(
          availableWidth / previewSize.width,
          previewHeight / previewSize.height,
        );
        final renderedWidth = previewSize.width * scale;
        final renderedHeight = previewSize.height * scale;
        final left = (availableWidth - renderedWidth) / 2;
        final top = (previewHeight - renderedHeight) / 2;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            // 将预览中的按下点换算为原组件尺寸比例，供进入画布后的真实元素沿用。
            payload.pointerId = event.pointer;
            payload.anchorFraction = Offset(
              ((event.localPosition.dx - left) / renderedWidth)
                  .clamp(0.0, 1.0),
              ((event.localPosition.dy - top) / renderedHeight)
                  .clamp(0.0, 1.0),
            );
          },
          child: SizedBox(
            height: previewHeight,
            width: double.infinity,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: previewSize.width,
                  height: previewSize.height,
                  child: IgnorePointer(
                    child: UISceneModeScope(
                      isStudioCreationMode: true,
                      child: Builder(
                        builder: (previewContext) =>
                            UIRenderer.render(previewContext, previewElement),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    // 原材料库不再给每个组件套额外展示卡片；只呈现组件的真实默认形态。
    final card = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: visualPreview,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) {
        _startLibraryPlacement(payload, details.globalPosition);
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: payload.isLibraryDragging,
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
        builder: (context, isDragging, child) => AnimatedScale(
          scale: isDragging ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isDragging ? 0.42 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: child,
          ),
        ),
      ),
    );
  }

  // ===== 构造层抽屉 =====
  Widget _buildAtomicConstructionDrawer() {
    final bakeable = _currentElements.where(_isBakeableElement).length;
    final total = _currentElements.length;
    final notBakeable = total - bakeable;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
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
                      onTap: () =>
                          setState(() => _showConstructionManager = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_forward_ios,
                                size: 10, color: Color(0xFF00ACC1)),
                            Text(
                              ' 收回',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF00ACC1),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text(
                      '元素列表',
                      style: TextStyle(
                        color: Color(0xFF111116),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
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
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Text(
                    '可烘焙 $bakeable 层 · 不参与 $notBakeable 层',
                    style: TextStyle(
                      color: notBakeable > 0
                          ? const Color(0xFFFF8F00)
                          : const Color(0xFF00A86B),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF888896),
                    height: 1.25,
                  ),
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
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888896),
                        height: 1.35,
                      ),
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  itemCount: _currentElements.length,
                  itemBuilder: (context, index) {
                    final el = _currentElements[index];
                    final selected = _selectedTransformationId == el.id;
                    final bake = _isBakeableElement(el);
                    final name =
                        el.module?.name ?? el.composite?.name ?? '未命名层';
                    return Card(
                      color: selected
                          ? const Color(0xFF111116)
                          : const Color(0xFFF6F6F9),
                      elevation: selected ? 3 : 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF00E5FF)
                              : Colors.black.withValues(alpha: 0.04),
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(
                                () => _selectedTransformationId = el.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: bake
                                          ? const Color(0xFF00C853)
                                          : const Color(0xFFFF8F00),
                                      borderRadius:
                                      BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      bake ? '烘焙' : '跳过',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF111116),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_elementTypeLabel(el)} · ${el.size.width.toStringAsFixed(0)}×${el.size.height.toStringAsFixed(0)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white70
                                      : const Color(0xFF777783),
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildLayerMiniButton(
                                    Icons.keyboard_arrow_up_rounded,
                                        () => _moveAtomicConstructionLayer(
                                        el.id, -1),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.keyboard_arrow_down_rounded,
                                        () => _moveAtomicConstructionLayer(
                                        el.id, 1),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.tune_rounded,
                                        () => _showTailoredPrecisionEditorDialog(
                                        el),
                                    selected,
                                  ),
                                  _buildLayerMiniButton(
                                    Icons.delete_outline_rounded,
                                        () => _deleteElement(el.id),
                                    selected,
                                    danger: true,
                                  ),
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

  Widget _buildLayerMiniButton(
      IconData icon,
      VoidCallback onTap,
      bool selected, {
        bool danger = false,
      }) {
    final color = danger
        ? const Color(0xFFFF4081)
        : (selected ? Colors.white : const Color(0xFF555562));
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  // ===== 右侧资产库抽屉 =====
  Widget _buildRightCompletedAssetsDrawer() {
    final modules = _assetService.getUserModules();
    final composites = _assetService.getAllComposites();
    final isEmpty = modules.isEmpty && composites.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 16, 14, 8),
                child: Center(child: Text('完成资产库', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold, fontSize: 13))),
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
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888896),
                        height: 1.35,
                      ),
                    ),
                  ),
                )
                    : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  children: [
                    ...modules.map(_buildAssetLibraryModuleCard),
                    if (composites.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 10, 4, 2),
                        child: Text(
                          '复合组件',
                          style: TextStyle(
                            color: Color(0xFF888896),
                            fontSize: 10,
                          ),
                        ),
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
    final payload = DragPayload(module: module);
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
          style: const TextStyle(
            color: Color(0xFF111116),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _elementTypeLabel(
            UIElement(id: 'preview_${module.id}', isComposite: false, module: module),
          ),
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFF00E676),
            ),
            GestureDetector(
              onTap: () => _confirmDeleteModule(module),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Color(0xFFFF4081),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return Listener(
      onPointerDown: (event) {
        payload.pointerId = event.pointer;
        // 右侧是资产清单卡片而非等比真实预览，采用稳定中心锚点。
        payload.anchorFraction = const Offset(0.5, 0.5);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) {
          _startLibraryPlacement(payload, details.globalPosition);
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: payload.isLibraryDragging,
          child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
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

  Widget _buildAssetLibraryCompositeCard(UIComposite composite) {
    final payload = DragPayload(composite: composite);
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
          style: const TextStyle(
            color: Color(0xFF111116),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '复合组件 · ${composite.children.length} 个子元素',
          style: const TextStyle(color: Color(0xFF888896), fontSize: 9),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFF651FFF),
            ),
            GestureDetector(
              onTap: () => _confirmDeleteComposite(composite),
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Color(0xFFFF4081),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return Listener(
      onPointerDown: (event) {
        payload.pointerId = event.pointer;
        // 右侧是资产清单卡片而非等比真实预览，采用稳定中心锚点。
        payload.anchorFraction = const Offset(0.5, 0.5);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) {
          _startLibraryPlacement(payload, details.globalPosition);
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: payload.isLibraryDragging,
          child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
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
}
