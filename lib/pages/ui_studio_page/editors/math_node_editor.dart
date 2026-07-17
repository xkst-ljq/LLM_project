part of '../ui_studio_page.dart';

mixin _MathNodeEditorDialog on _UIStudioLogic, _StudioMenuDialogs {
  // ===== 紧凑型算术计算节点专属规格编辑器 (Math Node) =====
  void _showCompactMathNodeEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex)
          ? _activeLayerIndex
          : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    String operation = props['operation']?.toString() ?? '+';
    double value = (props['value'] as num?)?.toDouble() ?? 1.0;
    String extractMethod = props['extractMethod']?.toString() ?? 'first';
    String extractKey = props['extractKey']?.toString() ?? '';
    int extractIndex = (props['extractIndex'] as num?)?.toInt() ?? 0;
    String delimiter = props['delimiter']?.toString() ?? '/';
    String gateFallback = props['gateFallback']?.toString() ?? 'hold_last';

    final initialMod = mod.copyWith();
    bool isApplied = false;

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.module != null) {
          props['operation'] = operation;
          props['value'] = value;
          props['extractMethod'] = extractMethod;
          props['extractKey'] = extractKey;
          props['extractIndex'] = extractIndex;
          props['delimiter'] = delimiter;
          props['gateFallback'] = gateFallback;

          _currentElements[idx] = curEl.copyWith(
            module: curEl.module!.copyWith(
              name: name,
              properties: props,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)
      ..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))
      ..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))
      ..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);
    final valStrInitial = value == value.toInt() ? value.toInt().toString() : value.toString();
    final valCtrl = TextEditingController(text: valStrInitial)
      ..selection = TextSelection.collapsed(offset: valStrInitial.length);
    final keyCtrl = TextEditingController(text: extractKey)
      ..selection = TextSelection.collapsed(offset: extractKey.length);
    final idxCtrl = TextEditingController(text: extractIndex.toString())
      ..selection = TextSelection.collapsed(offset: extractIndex.toString().length);
    final delimCtrl = TextEditingController(text: delimiter)
      ..selection = TextSelection.collapsed(offset: delimiter.length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final String valStrCur = value == value.toInt() ? value.toInt().toString() : value.toString();
            final String opPreviewText = operation == 'set' ? '强制设定 = $valStrCur' : '清洗值 $operation $valStrCur';

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('算术节点设置',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 20, color: Color(0xFF888896)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              TextField(
                                controller: nameCtrl,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                                decoration: _softInputDecoration(),
                                onChanged: (v) {
                                  name = v;
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('绝对物理坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: offsetXCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: _softInputDecoration(label: 'X坐标'),
                                      onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: offsetYCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: _softInputDecoration(label: 'Y坐标'),
                                      onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(10)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('第一区：数据清洗方式',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF512DA8))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      initialValue: extractMethod,
                                      decoration: _softInputDecoration(),
                                      dropdownColor: Colors.white,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                      items: const [
                                        DropdownMenuItem(value: 'first', child: Text('粗暴取首数 (first)')),
                                        DropdownMenuItem(value: 'by_index', child: Text('按序号拿 (by_index)')),
                                        DropdownMenuItem(value: 'by_key', child: Text('按关键词抠 (by_key)')),
                                        DropdownMenuItem(value: 'by_delimiter', child: Text('按符号切 (by_delimiter)')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setDialogState(() => extractMethod = v);
                                          setState(() => syncLivePreview());
                                        }
                                      },
                                    ),
                                    if (extractMethod == 'by_index' || extractMethod == 'by_delimiter') ...[
                                      const SizedBox(height: 8),
                                      if (extractMethod == 'by_delimiter') ...[
                                        TextField(
                                          controller: delimCtrl,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: _softInputDecoration(label: '分割符 (默认 /)'),
                                          onChanged: (v) {
                                            delimiter = v.isEmpty ? '/' : v;
                                            setState(() => syncLivePreview());
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      TextField(
                                        controller: idxCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: _softInputDecoration(label: '切片序号 Index (0为第1项)'),
                                        onChanged: (v) {
                                          extractIndex = int.tryParse(v) ?? 0;
                                          setState(() => syncLivePreview());
                                        },
                                      ),
                                    ] else if (extractMethod == 'by_key') ...[
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: keyCtrl,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: _softInputDecoration(label: '键名关键词 (如 "敏捷")'),
                                        onChanged: (v) {
                                          extractKey = v;
                                          setState(() => syncLivePreview());
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDE7F6).withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD1C4E9)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('第二区：算式规格与操作数',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF512DA8))),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        {'+': '加 (+)'},
                                        {'-': '减 (-)'},
                                        {'*': '乘 (*)'},
                                        {'/': '除 (/)'},
                                        {'set': '设定为'},
                                      ].expand((map) => map.entries).map((item) {
                                        final sel = operation == item.key;
                                        return Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              setDialogState(() => operation = item.key);
                                              setState(() => syncLivePreview());
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 4),
                                              padding: const EdgeInsets.symmetric(vertical: 7),
                                              decoration: BoxDecoration(
                                                color: sel ? const Color(0xFF512DA8) : Colors.white,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: sel ? const Color(0xFF512DA8) : const Color(0xFFB39DDB)),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(item.value,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: sel ? Colors.white : const Color(0xFF512DA8),
                                                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: valCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                                      decoration: _softInputDecoration(label: '操作数值 (Value)'),
                                      onChanged: (v) {
                                        value = double.tryParse(v) ?? value;
                                        setState(() => syncLivePreview());
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Text('当前规则：$opPreviewText',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF673AB7), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFFE082)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('第三区：控制门关闭对策',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      initialValue: gateFallback,
                                      decoration: _softInputDecoration(),
                                      dropdownColor: Colors.white,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                      items: const [
                                        DropdownMenuItem(value: 'hold_last', child: Text('发送旧缓存值 (hold_last)')),
                                        DropdownMenuItem(value: 'fallback_zero', child: Text('回写数字0 (fallback_zero)')),
                                        DropdownMenuItem(value: 'drop_null', child: Text('断开传导静默 (drop_null)')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setDialogState(() => gateFallback = v);
                                          setState(() => syncLivePreview());
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('删除节点', style: TextStyle(fontSize: 13)),
                            onPressed: () {
                              isApplied = true;
                              Navigator.pop(ctx);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _deleteElement(el.id);
                              });
                            },
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                    if (idx != -1) _currentElements[idx] = el;
                                  });
                                  Navigator.pop(ctx);
                                },
                                child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF512DA8)),
                                onPressed: () {
                                  isApplied = true;
                                  Navigator.pop(ctx);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    setState(() {
                                      final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                      if (idx != -1) {
                                        final updatedMod = mod.copyWith(name: name, properties: props);
                                        _currentElements[idx] = el.copyWith(
                                          offset: Offset(offsetX, offsetY),
                                          layerIndex: selectedLayer,
                                          module: updatedMod,
                                        );
                                      }
                                    });
                                    _autoSave();
                                  });
                                },
                                child: const Text('保存配置'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (!isApplied) {
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) _currentElements[idx] = el.copyWith(module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
        valCtrl.dispose();
        keyCtrl.dispose();
        idxCtrl.dispose();
        delimCtrl.dispose();
      });
    });
  }
}
