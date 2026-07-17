part of 'ui_studio_page.dart';

/// 所有对话框与底部弹窗
mixin _UIStudioDialogs on _UIStudioLogic, _StudioMenuDialogs, _CompactEditorsDialogs, _SwitchEditorDialog, _LineEditorDialog, _ImageEditorDialog, _MathNodeEditorDialog {
  // ===== 元素编辑器主调度分流入口 =====
  void _showTailoredPrecisionEditorDialog(UIElement el) {
    if (el.isComposite) {
      _showCompactCompositeEditorDialog(el);
      return;
    }
    final type = el.module?.type;
    if (type == null) return;
    if (['surface', 'surface_art', 'primitive_art'].contains(type)) {
      _showCompactSurfaceEditorDialog(el);
    } else if (type == 'text') {
      _showCompactTextEditorDialog(el);
    } else if (['progress', 'slider'].contains(type)) {
      _showCompactNumericEditorDialog(el);
    } else if (type == 'input') {
      _showCompactInputEditorDialog(el);
    } else if (type == 'button') {
      _showCompactButtonEditorDialog(el);
    } else if (type == 'switch') {
      _showCompactSwitchEditorDialog(el);
    } else if (type == 'line') {
      _showCompactLineEditorDialog(el);
    } else if (type == 'image') {
      _showCompactImageEditorDialog(el);
    } else if (type == 'linker') {
      _showCompactLinkerEditorDialog(el);
    } else if (type == 'math_node') {
      _showCompactMathNodeEditorDialog(el);
    } else if (type == 'select') {
      _showCompactSelectEditorDialog(el);
    } else if (type == 'indicator') {
      _showCompactIndicatorEditorDialog(el);
    } else if (type == 'scroll_frame') {
      _showCompactScrollFrameEditorDialog(el);
    } else if (type == 'timer') {
      _showCompactTimerEditorDialog(el);
    }
  }

  // ===== Linker 快捷传输方案选择弹窗 =====
  void _showLinkerSchemeQuickSelectDialog(UIElement el) {
    if (el.module?.type != 'linker') return;
    final props = Map<String, dynamic>.from(el.module!.properties);
    final linkerData = Map<String, dynamic>.from(props['linker'] ?? {});
    final currentScheme = linkerData['scheme']?.toString();

    final sourceId = linkerData['sourceModuleId']?.toString();
    final targetId = linkerData['targetModuleId']?.toString();

    UIElement? sourceEl, targetEl;
    for (final e in _currentElements) {
      if (e.id == sourceId) sourceEl = e;
      if (e.id == targetId) targetEl = e;
    }

    final bool isFullyConnected = sourceEl != null && targetEl != null;

    if (!isFullyConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已连通单侧端口，请继续拉线连接另一端'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '选择联动器传输类型',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116)),
          ),
          content: _buildAvailableSchemesList(ctx, el, sourceEl!, targetEl!, currentScheme),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭', style: TextStyle(color: Color(0xFF888896))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvailableSchemesList(
    BuildContext ctx,
    UIElement linkerEl,
    UIElement sourceEl,
    UIElement targetEl,
    String? currentScheme,
  ) {
    final sType = sourceEl.module?.type;
    final tType = targetEl.module?.type;

    final schemes = LinkerMatrixEngine.getAvailableSchemes(sType, tType);

    if (schemes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '🚫 [${sourceEl.module?.name ?? sType}] 与 [${targetEl.module?.name ?? tType}] 属于屏蔽互斥范畴，不支持建立传输协议。',
          style: const TextStyle(fontSize: 13, color: Color(0xFFC62828), height: 1.4),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: schemes.map((def) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildSchemeOptionTile(
            ctx,
            linkerEl,
            def,
            currentScheme ?? '',
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSchemeOptionTile(
      BuildContext ctx, UIElement el, SchemeDefinition schemeDef, String currentScheme) {
    final isSelected = schemeDef.id == currentScheme;
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) {
            final targetEl = _currentElements[idx];
            if (targetEl.module != null) {
              final newProps = Map<String, dynamic>.from(targetEl.module!.properties);
              final newLinker = Map<String, dynamic>.from(newProps['linker'] ?? {});
              newLinker['scheme'] = schemeDef.id;
              newProps['linker'] = newLinker;
              _currentElements[idx] = targetEl.copyWith(
                module: targetEl.module!.copyWith(properties: newProps),
              );
            }
          }
        });
        _autoSave();

        if (schemeDef.params.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final updatedIdx = _currentElements.indexWhere((e) => e.id == el.id);
              if (updatedIdx != -1) {
                _showCompactLinkerEditorDialog(_currentElements[updatedIdx]);
              }
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已关联协议: ${schemeDef.label}（连通即生效）'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00ACC1).withValues(alpha: 0.1) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF00ACC1) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected ? const Color(0xFF00ACC1) : const Color(0xFF888896),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schemeDef.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: const Color(0xFF111116),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    schemeDef.description,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888896)),
                  ),
                ],
              ),
            ),
            if (schemeDef.params.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4081).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '含配置项',
                  style: TextStyle(fontSize: 10, color: Color(0xFFFF4081), fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== 紧凑型下拉单选框控件专属规格编辑器 (Select) =====
  void _showCompactSelectEditorDialog(UIElement el) {
    if (el.module == null) return;
    final mod = el.module!;
    showDialog(
      context: context,
      builder: (ctx) => SelectEditor(
        initialProperties: Map<String, dynamic>.from(mod.properties),
        moduleName: mod.name,
        layerId: el.layerIndex,
        initialPosition: el.offset,
        onDelete: () {
          _deleteElement(el.id);
        },
        onSave: (newProps) {
          setState(() {
            final idx = _currentElements.indexWhere((e) => e.id == el.id);
            if (idx != -1) {
              final newName = newProps['name']?.toString() ?? mod.name;
              final updatedMod = mod.copyWith(
                name: newName,
                properties: newProps,
                color: Color((newProps['accentColor'] as int?) ?? mod.color.toARGB32()),
              );
              _currentElements[idx] = el.copyWith(module: updatedMod);
            }
          });
          _autoSave();
        },
      ),
    );
  }

  // ===== 紧凑型多态状态指示点控件专属规格编辑器 (Indicator) =====
  void _showCompactIndicatorEditorDialog(UIElement el) {
    if (el.module == null) return;
    final mod = el.module!;
    showDialog(
      context: context,
      builder: (ctx) => IndicatorEditor(
        initialProperties: Map<String, dynamic>.from(mod.properties),
        moduleName: mod.name,
        layerId: el.layerIndex,
        initialPosition: el.offset,
        onDelete: () {
          _deleteElement(el.id);
        },
        onSave: (newProps) {
          setState(() {
            final idx = _currentElements.indexWhere((e) => e.id == el.id);
            if (idx != -1) {
              final newName = newProps['name']?.toString() ?? mod.name;
              final updatedMod = mod.copyWith(
                name: newName,
                properties: newProps,
                color: Color((newProps['defaultColor'] as int?) ?? mod.color.toARGB32()),
              );
              _currentElements[idx] = el.copyWith(module: updatedMod);
            }
          });
          _autoSave();
        },
      ),
    );
  }

  // ===== 紧凑型局部滚动视窗控件专属规格编辑器 (Scroll Frame) =====
  void _showCompactScrollFrameEditorDialog(UIElement el) {
    if (el.module == null) return;
    final mod = el.module!;
    showDialog(
      context: context,
      builder: (ctx) => ScrollFrameEditor(
        initialProperties: Map<String, dynamic>.from(mod.properties),
        moduleName: mod.name,
        layerId: el.layerIndex,
        initialPosition: el.offset,
        onDelete: () {
          _deleteElement(el.id);
        },
        onSave: (newProps) {
          setState(() {
            final oldAdopted = (mod.properties['adoptedChildElements'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            final newAdopted = (newProps['adoptedChildElements'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            final newIds = newAdopted.map((e) => e['id']?.toString()).toSet();
            for (final oldChild in oldAdopted) {
              if (!newIds.contains(oldChild['id']?.toString())) {
                _currentElements.add(UIElement.fromJson(oldChild));
              }
            }

            final idx = _currentElements.indexWhere((e) => e.id == el.id);
            if (idx != -1) {
              final newName = newProps['name']?.toString() ?? mod.name;
              final updatedMod = mod.copyWith(
                name: newName,
                properties: newProps,
                color: Color((newProps['backgroundColor'] as int?) ?? mod.color.toARGB32()),
              );
              _currentElements[idx] = el.copyWith(module: updatedMod);
            }
          });
          _autoSave();
        },
      ),
    );
  }

  // ===== 紧凑型定时脉冲发生器专属规格编辑器 (Timer) =====
  void _showCompactTimerEditorDialog(UIElement el) {
    if (el.module == null) return;
    final mod = el.module!;
    showDialog(
      context: context,
      builder: (ctx) => TimerEditor(
        initialProperties: Map<String, dynamic>.from(mod.properties),
        moduleName: mod.name,
        layerId: el.layerIndex,
        initialPosition: el.offset,
        onDelete: () {
          _deleteElement(el.id);
        },
        onSave: (newProps) {
          setState(() {
            final idx = _currentElements.indexWhere((e) => e.id == el.id);
            if (idx != -1) {
              final newName = newProps['name']?.toString() ?? mod.name;
              final updatedMod = mod.copyWith(
                name: newName,
                properties: newProps,
              );
              _currentElements[idx] = el.copyWith(module: updatedMod);
            }
          });
          _autoSave();
        },
      ),
    );
  }

}
