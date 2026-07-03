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
          content: !isFullyConnected
              ? Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '⚠️ 请先连接【数据来源】与【目标端点】，系统将根据双方组件规格自动推导可用的方案。',
              style: TextStyle(fontSize: 13, color: Color(0xFFF57F17), height: 1.4),
            ),
          )
              : _buildAvailableSchemesList(ctx, el, sourceEl!, targetEl!, currentScheme),
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

    final options = <Map<String, String>>[];

    if (['surface', 'surface_art', 'primitive_art'].contains(sType)) {
      if (tType == 'text') {
        options.add({'id': 'name_to_text', 'label': '表头回写 (name → text)'});
        options.add({'id': 'bounds_to_text', 'label': '规格自测打印 (bounds → text)'});
        options.add({'id': 'color_to_text', 'label': '文字/底色着色 (color → text)'});
      } else if (['progress', 'slider'].contains(tType)) {
        options.add({'id': 'color_to_track', 'label': '同步轨道填充色 (color → track)'});
        options.add({'id': 'size_to_max', 'label': '宽度折算上限 (size → max)'});
        options.add({'id': 'surface_to_progress_enable', 'label': '区域激活使能/冻结'});
      } else if (tType == 'switch') {
        options.add({'id': 'color_to_switch', 'label': '同步开关高亮色 (color → switch)'});
        options.add({'id': 'surface_to_switch_enable', 'label': '开关触控使能锁定'});
      } else if (tType == 'select') {
        options.add({'id': 'color_to_select', 'label': '同步选框主题色 (color → select)'});
        options.add({'id': 'surface_to_select_enable', 'label': '选框触控使能锁定'});
      } else if (tType == 'indicator') {
        options.add({'id': 'color_to_indicator', 'label': '同步指示灯发光主题色'});
        options.add({'id': 'surface_to_indicator_state', 'label': '区域选中驱动点亮/熄灭'});
      } else if (tType == 'scroll_frame') {
        options.add({'id': 'adopt_into_frame', 'label': '📦 移交收容至视窗沙盘'});
        options.add({'id': 'color_to_viewport', 'label': '同步视窗底板背景色'});
        options.add({'id': 'size_to_viewport_content', 'label': '映射为视窗虚拟长画布尺寸'});
      } else if (['button', 'input'].contains(tType)) {
        options.add({'id': 'surface_to_button_enable', 'label': '隐形触控热区解锁/屏蔽'});
      } else if (['surface', 'surface_art', 'primitive_art'].contains(tType)) {
        options.add({'id': 'surface_to_surface_expansion', 'label': '🔗 面的扩充与全样式共生'});
      }
    } else if (['progress', 'slider'].contains(sType) && ['progress', 'slider'].contains(tType)) {
      options.add({'id': 'num_to_current', 'label': '数值驱动实时进度 (num → current)'});
    } else if (['progress', 'slider'].contains(sType) && tType == 'text') {
      options.add({'id': 'current_to_text', 'label': 'current → text (当前进度/数值转文本)'});
      options.add({'id': 'max_to_text', 'label': 'max → text (最大值转文本)'});
    } else if (sType == 'text' && ['input', 'button'].contains(tType)) {
      options.add({'id': 'text_to_text', 'label': '提示词动态变量传导 (text → text)'});
    } else if (['input', 'button'].contains(sType) && tType == 'text') {
      options.add({'id': 'to_string', 'label': '标准字面量实时回写 (to_string)'});
    } else if (tType == 'math_node') {
      options.add({'id': 'num_to_math', 'label': '数值流导算术节点 (num → math)'});
    } else if (sType == 'math_node' && ['progress', 'slider'].contains(tType)) {
      options.add({'id': 'math_to_current', 'label': '算术实时驱动进度 (math → current)'});
    } else if (sType == 'math_node' && tType == 'text') {
      options.add({'id': 'math_to_text', 'label': '算术结果回写文本 (math → text)'});
    } else if (sType == 'select' && tType == 'text') {
      options.add({'id': 'select_to_text', 'label': '单选选定项实时回写文本 (select → text)'});
    } else if (tType == 'select') {
      options.add({'id': 'str_to_select', 'label': '字面量流导驱动指针 (str → select)'});
    } else if (tType == 'indicator') {
      options.add({'id': 'str_to_indicator', 'label': '字面量匹配驱动状态灯 (str → indicator)'});
      options.add({'id': 'num_to_indicator', 'label': '数值区间驱动状态灯 (num → indicator)'});
      options.add({'id': 'bool_to_indicator', 'label': '开关状态驱动状态灯 (bool → indicator)'});
    } else if (tType == 'scroll_frame') {
      options.add({'id': 'adopt_into_frame', 'label': '📦 移交收容至局部滚动视窗 (Adopt into Scroll Frame)'});
    } else if (sType == 'timer' && ['progress', 'slider'].contains(tType)) {
      options.add({'id': 'num_to_current', 'label': '脉冲实时驱动进度条 (timer → current)'});
    } else if (sType == 'timer' && tType == 'indicator') {
      options.add({'id': 'num_to_indicator', 'label': '脉冲计数驱动状态指示灯 (timer → indicator)'});
    } else if (sType == 'timer' && tType == 'text') {
      options.add({'id': 'current_to_text', 'label': '脉冲计数值转为文本 (timer → text)'});
    } else {
      options.add({'id': 'to_string', 'label': '通用标准字面量流转 (to_string)'});
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options.map((opt) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildSchemeOptionTile(
            ctx,
            linkerEl,
            opt['id']!,
            opt['label']!,
            currentScheme ?? '',
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSchemeOptionTile(BuildContext ctx, UIElement el, String schemeValue, String label, String currentScheme) {
    final isSelected = schemeValue == currentScheme;
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
              newLinker['scheme'] = schemeValue;
              newProps['linker'] = newLinker;
              _currentElements[idx] = targetEl.copyWith(
                module: targetEl.module!.copyWith(properties: newProps),
              );

              if (schemeValue == 'adopt_into_frame') {
                final targetFrameId = newLinker['targetModuleId']?.toString();
                final sourceChildId = newLinker['sourceModuleId']?.toString();
                if (targetFrameId != null && sourceChildId != null) {
                  final frameIdx = _currentElements.indexWhere((e) => e.id == targetFrameId);
                  final childIdx = _currentElements.indexWhere((e) => e.id == sourceChildId);
                  if (frameIdx != -1 && childIdx != -1) {
                    final frameEl = _currentElements[frameIdx];
                    final childEl = _currentElements[childIdx];
                    final frameProps = Map<String, dynamic>.from(frameEl.module!.properties);
                    final adoptedList = (frameProps['adoptedChildElements'] as List?)
                            ?.map((e) => Map<String, dynamic>.from(e as Map))
                            .toList() ??
                        [];
                    if (!adoptedList.any((e) => e['id'] == childEl.id)) {
                      adoptedList.add(childEl.toJson());
                    }
                    frameProps['adoptedChildElements'] = adoptedList;
                    _currentElements[frameIdx] = frameEl.copyWith(
                      module: frameEl.module!.copyWith(properties: frameProps),
                    );
                    _currentElements.removeAt(childIdx);
                  }
                }
              }
            }
          }
        });
        _autoSave();
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
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: const Color(0xFF111116),
                ),
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
