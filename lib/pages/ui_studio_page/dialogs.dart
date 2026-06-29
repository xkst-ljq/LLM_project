part of 'ui_studio_page.dart';

/// 所有对话框与底部弹窗
mixin _UIStudioDialogs on _UIStudioLogic, _StudioMenuDialogs, _CompactEditorsDialogs {
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
    } else if (type == 'linker') {
      _showCompactLinkerEditorDialog(el);
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

    if (['progress', 'slider'].contains(sType) && ['progress', 'slider'].contains(tType)) {
      options.add({'id': 'num_to_current', 'label': '数值驱动实时进度 (num → current)'});
    } else if (['progress', 'slider'].contains(sType) && tType == 'text') {
      options.add({'id': 'current_to_text', 'label': 'current → text (当前进度/数值转文本)'});
      options.add({'id': 'max_to_text', 'label': 'max → text (最大值转文本)'});
    } else if (sType == 'text' && ['input', 'button'].contains(tType)) {
      options.add({'id': 'text_to_text', 'label': '提示词动态变量传导 (text → text)'});
    } else if (['input', 'button'].contains(sType) && tType == 'text') {
      options.add({'id': 'to_string', 'label': '标准字面量实时回写 (to_string)'});
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

}
