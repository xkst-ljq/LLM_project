part of '../ui_studio_page.dart';

mixin _CompactEditorsDialogs on _UIStudioLogic, _StudioMenuDialogs {
  static const _inputColorChoices = [
    _InputColorChoice('深灰', 0xFF111116), _InputColorChoice('灰色', 0xFF888896),
    _InputColorChoice('浅灰', 0xFFB8B8C2), _InputColorChoice('白色', 0xFFFFFFFF),
    _InputColorChoice('黑色', 0xFF000000), _InputColorChoice('浅蓝', 0xFF4FC3F7),
    _InputColorChoice('深蓝', 0xFF1565C0), _InputColorChoice('紫色', 0xFF7E57C2),
    _InputColorChoice('粉色', 0xFFFF4081), _InputColorChoice('橙色', 0xFFFF9800),
    _InputColorChoice('红色', 0xFFE53935), _InputColorChoice('绿色', 0xFF43A047),
    _InputColorChoice('青色', 0xFF00ACC1),
  ];
  // ===== 紧凑型数值控件专属规格编辑器 (Progress & Slider) =====
  void _showCompactNumericEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    double minVal = (props['min'] ?? 0.0).toDouble();
    double maxVal = (props['max'] ?? 100.0).toDouble();
    double curVal = (props['current'] ?? 75.0).toDouble().clamp(minVal <= maxVal ? minVal : maxVal, minVal <= maxVal ? maxVal : minVal).toDouble();
    double stepVal = ((props['step'] as num?)?.toDouble() ?? 1.0).abs();
    if (stepVal == 0) stepVal = 1.0;

    final int? trackColorVal = props['trackColor'] as int?;
    Color trackColor = trackColorVal != null ? Color(trackColorVal) : Colors.grey.shade200;
    String shapeStr = props['progressShape']?.toString() ?? 'rounded';
    final double shortestSide = math.min(el.size.width, el.size.height);
    double strokeWidth = (props['strokeWidth'] ?? (shortestSide * 0.12)).toDouble().clamp(2.0, shortestSide * 0.42).toDouble();
    double knobSize = (props['knobSize'] ?? 18.0).toDouble().clamp(12.0, 36.0).toDouble();
    String knobShape = props['knobShape']?.toString() ?? 'circle';

    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    bool isApplied = false;

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.module != null) {
          _currentElements[idx] = curEl.copyWith(
            rotation: rotation,
            module: curEl.module!.copyWith(
              color: color,
              opacity: opacity,
              properties: props,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);
    final minCtrl = TextEditingController(text: minVal.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: minVal.toStringAsFixed(0).length);
    final maxCtrl = TextEditingController(text: maxVal.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: maxVal.toStringAsFixed(0).length);
    final stepCtrl = TextEditingController(text: stepVal.toString());
    final currentCtrl = TextEditingController(text: curVal.toString());

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final double actualMin = minVal <= maxVal ? minVal : maxVal;
            final double actualMax = minVal <= maxVal ? maxVal : minVal;
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(mod.type == 'slider' ? '滑块控件编辑器' : '数据条控件编辑器', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                    const SizedBox(height: 12),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    const Text('数值范围极限 (最小值 / 最大值)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: '最小值'), onChanged: (v) {
                          minVal = double.tryParse(v) ?? minVal;
                          props['min'] = minVal;
                          if (curVal < actualMin) { curVal = actualMin; props['current'] = curVal; }
                          setState(() => syncLivePreview());
                        })),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: '最大值'), onChanged: (v) {
                          maxVal = double.tryParse(v) ?? maxVal;
                          props['max'] = maxVal;
                          if (curVal > actualMax) { curVal = actualMax; props['current'] = curVal; }
                          setState(() => syncLivePreview());
                        })),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (mod.type == 'slider') ...[
                      const Text('滑动步长', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: stepCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _softInputDecoration(label: '步长，例如 1 / 0.1 / 5'),
                        onChanged: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed == null || parsed <= 0) return;
                          stepVal = parsed;
                          props['step'] = stepVal;
                          setState(() => syncLivePreview());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (mod.type == 'progress') ...[
                      const Text('当前数值', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: currentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: _softInputDecoration(label: '输入当前数值'),
                        onChanged: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed == null) return;
                          setDialogState(() {
                            curVal = parsed.clamp(actualMin, actualMax).toDouble();
                            props['current'] = curVal;
                          });
                          setState(() => syncLivePreview());
                        },
                      ),
                    ] else ...[
                      Text('当前刻度初值 (${curVal.round()})', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      Slider(
                        value: curVal.clamp(actualMin, actualMax).toDouble(),
                        min: actualMin,
                        max: actualMax,
                        activeColor: const Color(0xFF00ACC1),
                        onChanged: (v) {
                          setDialogState(() {
                            curVal = v;
                            props['current'] = v;
                          });
                          setState(() => syncLivePreview());
                        },
                      ),
                    ],
                    const SizedBox(height: 12),

                    if (mod.type == 'progress') ...[
                      const Text('进度条轮廓形状选择', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          {'id': 'rounded', 'label': '圆角'},
                          {'id': 'rectangle', 'label': '直角'},
                          {'id': 'heart', 'label': '心形'},
                          {'id': 'ring', 'label': '圆环'},
                        ].map((item) {
                          final sel = shapeStr == item['id'];
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  shapeStr = item['id']!;
                                  props['progressShape'] = shapeStr;
                                });
                                setState(() => syncLivePreview());
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0xFF00ACC1) : const Color(0xFFF5F5F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(item['label']!, style: TextStyle(fontSize: 12, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      if (shapeStr == 'ring') ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('圆环笔触宽度 (${strokeWidth.round()}px)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  strokeWidth = shortestSide * 0.12;
                                  props.remove('strokeWidth');
                                });
                                setState(() => syncLivePreview());
                              },
                              child: const Text('自适应比例(12%)', style: TextStyle(fontSize: 11, color: Color(0xFF00ACC1), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        Slider(
                          value: strokeWidth.clamp(2.0, math.max(48.0, shortestSide * 0.42)).toDouble(),
                          min: 2.0,
                          max: math.max(48.0, shortestSide * 0.42).toDouble(),
                          activeColor: const Color(0xFF00ACC1),
                          onChanged: (v) {
                            setDialogState(() {
                              strokeWidth = v;
                              props['strokeWidth'] = v;
                            });
                            setState(() => syncLivePreview());
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],

                    const Text('底槽与背景调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        Colors.grey.shade200, Colors.white, const Color(0xFF37474F), const Color(0xFF263238), Colors.black, const Color(0xFFFF80AB), const Color(0xFFFFCC80), const Color(0xFF80D8FF), const Color(0xFFB9F6CA)
                      ].map((c) {
                        final sel = trackColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              trackColor = c;
                              props['trackColor'] = c.toARGB32();
                            });
                            setState(() => syncLivePreview());
                          },
                          child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1))),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    if (mod.type == 'slider') ...[
                      const Text('滑块把手轮廓外形', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          {'id': 'circle', 'label': '圆形把手'},
                          {'id': 'rectangle', 'label': '方形把手'},
                        ].map((item) {
                          final sel = knobShape == item['id'];
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  knobShape = item['id']!;
                                  props['knobShape'] = knobShape;
                                });
                                setState(() => syncLivePreview());
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0xFF00ACC1) : const Color(0xFFF5F5F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(item['label']!, style: TextStyle(fontSize: 12, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      Text('把手像素大小 (${knobSize.round()}px)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      Slider(
                        value: knobSize, min: 12.0, max: 36.0, activeColor: const Color(0xFF00ACC1),
                        onChanged: (v) {
                          setDialogState(() {
                            knobSize = v;
                            props['knobSize'] = v;
                          });
                          setState(() => syncLivePreview());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    const Text('颜色调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
                      ].map((c) {
                        final sel = color == c;
                        return GestureDetector(
                          onTap: () { setDialogState(() => color = c); setState(() => syncLivePreview()); },
                          child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1))),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    Text('透明度 (${(opacity * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    Slider(
                      value: opacity, min: 0.0, max: 1.0, activeColor: const Color(0xFFFF4081),
                      onChanged: (v) { setDialogState(() => opacity = v); setState(() => syncLivePreview()); },
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        InkWell(
                          onTap: () {
                            setDialogState(() => rotation = 0.0);
                            setState(() {
                              final idx = _currentElements.indexWhere((e) => e.id == el.id);
                              if (idx != -1) _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                            });
                          },
                          child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0).toDouble(), min: -180, max: 180, activeColor: const Color(0xFFFF4081),
                      onChanged: (v) { setDialogState(() => rotation = v); setState(() => syncLivePreview()); },
                    ),
                  ],
                ),
              ),
              actions: [
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
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                  onPressed: () {
                    isApplied = true;
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          final updatedMod = mod.copyWith(name: name, color: color, opacity: opacity, properties: props);
                          _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (!isApplied) {
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) _currentElements[idx] = el.copyWith(rotation: initialRot, module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
        minCtrl.dispose();
        maxCtrl.dispose();
        stepCtrl.dispose();
        currentCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型输入热区控件专属规格编辑器 (Input) =====
  void _showCompactInputEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    String varName = props['variable']?.toString() ?? props['label']?.toString() ?? '';
    String placeholder = props['placeholder']?.toString() ?? '请输入...';
    bool required = props['required'] == true;
    int? maxLength = (props['maxLength'] as num?)?.toInt();
    String visualMode = props['visualMode']?.toString() ?? 'filled';
    String placeholderColorHex = ((props['placeholderColor'] as num?)?.toInt() ?? 0xFF888896).toRadixString(16).padLeft(8, '0');
    String inputTextColorHex = ((props['inputTextColor'] as num?)?.toInt() ?? 0xFF111116).toRadixString(16).padLeft(8, '0');

    String? linkedSourceText;
    for (final elem in _currentElements) {
      if (elem.module?.type == 'linker') {
        final lk = (elem.module?.properties['linker'] as Map?)?.cast<String, dynamic>();
        if (lk?['targetModuleId'] == el.id) {
          final srcId = lk?['sourceModuleId']?.toString();
          final srcElem = _currentElements.any((e) => e.id == srcId) ? _currentElements.firstWhere((e) => e.id == srcId) : null;
          if (srcElem != null) {
            linkedSourceText = srcElem.module?.properties['text']?.toString() ?? srcElem.module?.name;
          }
        }
      }
    }

    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    bool isApplied = false;

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.module != null) {
          _currentElements[idx] = curEl.copyWith(
            rotation: rotation,
            module: curEl.module!.copyWith(
              color: color,
              opacity: opacity,
              properties: props,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);
    final varCtrl = TextEditingController(text: varName)..selection = TextSelection.collapsed(offset: varName.length);
    final phCtrl = TextEditingController(text: placeholder)..selection = TextSelection.collapsed(offset: placeholder.length);
    final maxLengthCtrl = TextEditingController(text: maxLength?.toString() ?? '');

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(mod.type == 'input' ? '输入热区编辑器' : '点击热区编辑器', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                    const SizedBox(height: 12),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (mod.type == 'input') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: linkedSourceText != null ? const Color(0xFFE8F5E9) : const Color(0xFFE0F7FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: linkedSourceText != null ? const Color(0xFFA5D6A7) : const Color(0xFF80DEEA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              linkedSourceText != null ? '当前拓扑：连线语义驱动' : '当前性质：直接发言主对话框',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: linkedSourceText != null ? const Color(0xFF2E7D32) : const Color(0xFF006064)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              linkedSourceText != null ? '连线来源文本："$linkedSourceText"\n实际聊天时，输入的文字将存入 SessionState.vars["$linkedSourceText"] 词典。' : '当前未连接任何连线。输入的文字将直接向 AI 角色发送对话指令。',
                              style: TextStyle(fontSize: 11, color: linkedSourceText != null ? const Color(0xFF388E3C) : const Color(0xFF00838F), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Text('空提示语占位符 (Placeholder)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: phCtrl,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(),
                        onChanged: (v) {
                          placeholder = v;
                          props['placeholder'] = v;
                          setState(() => syncLivePreview());
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('输入视觉模式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      DropdownButtonFormField<String>(initialValue: visualMode, decoration: _softInputDecoration(), items: const [DropdownMenuItem(value:'filled',child:Text('填充背景')),DropdownMenuItem(value:'transparent',child:Text('透明无背景')),DropdownMenuItem(value:'outline',child:Text('透明描边'))], onChanged:(v){if(v!=null){visualMode=v;props['visualMode']=v;setState(()=>syncLivePreview());}}),
                      const SizedBox(height: 8),
                      const Text('提示文字颜色', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      DropdownButtonFormField<int>(initialValue: int.tryParse(placeholderColorHex, radix: 16), decoration: _softInputDecoration(), items: _inputColorChoices.map((c)=>DropdownMenuItem(value:c.value,child:Row(children:[Container(width:14,height:14,decoration:BoxDecoration(color:Color(c.value),shape:BoxShape.circle)),const SizedBox(width:8),Text(c.label)]))).toList(), onChanged:(v){if(v!=null)props['placeholderColor']=v;}),
                      const SizedBox(height: 8),
                      const Text('输入文字颜色', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      DropdownButtonFormField<int>(initialValue: int.tryParse(inputTextColorHex, radix: 16), decoration: _softInputDecoration(), items: _inputColorChoices.map((c)=>DropdownMenuItem(value:c.value,child:Row(children:[Container(width:14,height:14,decoration:BoxDecoration(color:Color(c.value),shape:BoxShape.circle)),const SizedBox(width:8),Text(c.label)]))).toList(), onChanged:(v){if(v!=null)props['inputTextColor']=v;}),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('必填校验', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        subtitle: const Text('为空时 Input 校验状态为 invalid', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
                        value: required,
                        activeThumbColor: const Color(0xFF00ACC1),
                        onChanged: (value) {
                          setDialogState(() => required = value);
                          props['required'] = value;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: maxLengthCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(label: '最大字符数（留空表示不限）'),
                        onChanged: (value) {
                          maxLength = int.tryParse(value);
                          if (maxLength == null || maxLength! <= 0) {
                            props.remove('maxLength');
                          } else {
                            props['maxLength'] = maxLength;
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (mod.type == 'button' || (mod.type == 'input' && linkedSourceText == null)) ...[
                      const Text('绑定逻辑变量名 (连通 SessionState 词典)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: varCtrl,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(helperText: '提示：实际聊天时存入词典，在提示词编写 {{var.xxx}} 即可动态解包。'),
                        onChanged: (v) {
                          varName = v;
                          props['variable'] = v;
                          props.remove('label');
                          setState(() => syncLivePreview());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        InkWell(
                          onTap: () {
                            setDialogState(() => rotation = 0.0);
                            setState(() {
                              final idx = _currentElements.indexWhere((e) => e.id == el.id);
                              if (idx != -1) _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                            });
                          },
                          child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0).toDouble(), min: -180, max: 180, activeColor: const Color(0xFFFF4081),
                      onChanged: (v) { setDialogState(() => rotation = v); setState(() => syncLivePreview()); },
                    ),
                  ],
                ),
              ),
              actions: [
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
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                  onPressed: () {
                    isApplied = true;
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          final updatedMod = mod.copyWith(name: name, color: color, opacity: opacity, properties: props);
                          _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (!isApplied) {
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) _currentElements[idx] = el.copyWith(rotation: initialRot, module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
        varCtrl.dispose();
        phCtrl.dispose();
        maxLengthCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型点击按钮控件专属规格编辑器 (Button) =====
  void _showCompactButtonEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    String btnText = props['text']?.toString() ?? '点击热区';
    bool showOnRuntime = props['showTextOnRuntime'] == true;

    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    bool isApplied = false;

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.module != null) {
          _currentElements[idx] = curEl.copyWith(
            rotation: rotation,
            module: curEl.module!.copyWith(
              color: color,
              opacity: opacity,
              properties: props,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);
    final txtCtrl = TextEditingController(text: btnText)..selection = TextSelection.collapsed(offset: btnText.length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('点击按钮规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
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
                              TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                              const SizedBox(height: 12),

                              const Text('绝对物理坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                                ],
                              ),
                              const SizedBox(height: 12),

                              const Text('按钮展示文案 (创作排版期可见)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              TextField(
                                controller: txtCtrl,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                                decoration: _softInputDecoration(),
                                onChanged: (v) {
                                  btnText = v;
                                  props['text'] = v;
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('手势触发模式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: props['active_gesture']?.toString() ?? 'tap',
                                decoration: _softInputDecoration(),
                                dropdownColor: Colors.white,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                items: const [
                                  DropdownMenuItem(value: 'tap', child: Text('🟢 单击触发 (Tap)')),
                                  DropdownMenuItem(value: 'double_tap', child: Text('🔵 双击触发 (Double Tap)')),
                                  DropdownMenuItem(value: 'long_press', child: Text('🔴 长按触发 (Long Press)')),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setDialogState(() {
                                    props['active_gesture'] = v;
                                  });
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('手势通道连接状态', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F6F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          LinkerService.hasConnectedPort(el.id, 'tap')
                                              ? '🟢 单击通道 (Tap)：已建立连线'
                                              : '⚪ 单击通道 (Tap)：未连线',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Color(0xFF29B6F6), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          LinkerService.hasConnectedPort(el.id, 'double_tap')
                                              ? '🔵 双击通道 (Double Tap)：已建立连线'
                                              : '⚪ 双击通道 (Double Tap)：未连线',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Color(0xFFFF5252), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          LinkerService.hasConnectedPort(el.id, 'long_press')
                                              ? '🔴 长按通道 (Long Press)：已建立连线'
                                              : '⚪ 长按通道 (Long Press)：未连线',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              SwitchListTile(
                                title: const Text('运行对话期依然显现纯字', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                                subtitle: const Text('默认仅排版创作对齐显现，聊天中消隐为热区', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
                                value: showOnRuntime,
                                activeThumbColor: const Color(0xFF00ACC1),
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  setDialogState(() {
                                    showOnRuntime = val;
                                    props['showTextOnRuntime'] = val;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() => rotation = 0.0);
                                      setState(() {
                                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                        if (idx != -1) _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                                      });
                                    },
                                    child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              Slider(
                                value: rotation.clamp(-180.0, 180.0).toDouble(), min: -180, max: 180, activeColor: const Color(0xFFFF4081),
                                onChanged: (v) { setDialogState(() => rotation = v); setState(() => syncLivePreview()); },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
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
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                            onPressed: () {
                              isApplied = true;
                              Navigator.pop(ctx);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() {
                                  final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                  if (idx != -1) {
                                    final updatedMod = mod.copyWith(name: name, color: color, opacity: opacity, properties: props);
                                    _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                                  }
                                });
                                _autoSave();
                              });
                            },
                            child: const Text('应用配置'),
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
          if (idx != -1) _currentElements[idx] = el.copyWith(rotation: initialRot, module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
        txtCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型连通器路由节点专属规格编辑器 (Linker) =====
  void _showCompactLinkerEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    bool isApplied = false;

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('连通器节点编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('所属独立图层', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int>(
                      initialValue: selectedLayer,
                      decoration: _softInputDecoration(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: _sceneLayers.map((ly) => DropdownMenuItem<int>(value: ly.id, child: Text(ly.name))).toList(),
                      onChanged: (v) => setDialogState(() => selectedLayer = v ?? _activeLayerIndex),
                    ),
                    const SizedBox(height: 12),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text('传输协议与方案详细配置', style: TextStyle(fontSize: 13, color: Color(0xFF111116), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    _buildSchemeDetailedConfigSection(el, setDialogState, props),
                  ],
                ),
              ),
              actions: [
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
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                  onPressed: () {
                    isApplied = true;
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          final updatedMod = mod.copyWith(name: name, properties: props);
                          _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (!isApplied) {
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) _currentElements[idx] = el.copyWith(rotation: initialRot, module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型文本专属规格编辑器 =====
  void _showCompactTextEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    String textProp = props['text']?.toString() ?? '';
    double fontSize = (props['fontSize'] ?? 14.0).toDouble().clamp(10.0, 72.0).toDouble();
    String overflowMode = props['overflow']?.toString() ?? 'ellipsis';
    String textAlignStr = props['textAlign']?.toString() ?? 'center';
    bool autoFit = props['autoFit'] == true;

    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    final initialSize = el.size;
    bool isApplied = false;

    double calcAutoWidth(String txt, double fs) {
      final actualTxt = txt.isEmpty ? name : txt;
      final tp = TextPainter(
        text: TextSpan(text: actualTxt, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      return (tp.width + 32.0).clamp(40.0, 800.0).toDouble();
    }

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.module != null) {
          final newSize = autoFit ? Size(calcAutoWidth(textProp, fontSize), curEl.size.height) : curEl.size;
          _currentElements[idx] = curEl.copyWith(
            size: newSize,
            rotation: rotation,
            module: curEl.module!.copyWith(
              color: color,
              opacity: opacity,
              properties: props,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);
    final textCtrl = TextEditingController(text: textProp)..selection = TextSelection.collapsed(offset: textProp.length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('文本卡片编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                    const SizedBox(height: 12),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    const Text('默认展示文本内容', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: textCtrl,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                      decoration: _softInputDecoration(),
                      onChanged: (v) {
                        textProp = v;
                        props['text'] = v;
                        setState(() => syncLivePreview());
                      },
                    ),
                    const SizedBox(height: 12),

                    const Text('文字水平排版对齐', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        {'id': 'left', 'label': '靠左'},
                        {'id': 'center', 'label': '居中'},
                        {'id': 'right', 'label': '靠右'},
                      ].map((item) {
                        final sel = textAlignStr == item['id'];
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                textAlignStr = item['id']!;
                                props['textAlign'] = textAlignStr;
                              });
                              setState(() => syncLivePreview());
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFF00ACC1) : const Color(0xFFF5F5F7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(item['label']!, style: TextStyle(fontSize: 12, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      title: const Text('边界宽度自适应文字数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                      subtitle: const Text('动态测量单行长度与字号，预留16px留白间距', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
                      value: autoFit,
                      activeThumbColor: const Color(0xFF00ACC1),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() {
                          autoFit = val;
                          props['autoFit'] = val;
                        });
                        setState(() => syncLivePreview());
                      },
                    ),
                    const SizedBox(height: 12),

                    const Text('文字超出高度时显示逻辑', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: overflowMode,
                      decoration: _softInputDecoration(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: const [
                        DropdownMenuItem(value: 'ellipsis', child: Text('末尾截断并显示省略号 (...)')),
                        DropdownMenuItem(value: 'scroll', child: Text('隐藏在框内，手指按住上下滚动阅读')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          overflowMode = v;
                          props['overflow'] = v;
                        });
                        setState(() => syncLivePreview());
                      },
                    ),
                    const SizedBox(height: 12),

                    Text('单字字号大小 (${fontSize.round()}px)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    Slider(
                      value: fontSize,
                      min: 10.0,
                      max: 72.0,
                      activeColor: const Color(0xFF00ACC1),
                      onChanged: (v) {
                        setDialogState(() {
                          fontSize = v;
                          props['fontSize'] = v;
                        });
                        setState(() => syncLivePreview());
                      },
                    ),
                    const SizedBox(height: 12),

                    const Text('字体颜色调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
                      ].map((c) {
                        final sel = color == c;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => color = c);
                            setState(() => syncLivePreview());
                          },
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    Text('透明度 (${(opacity * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    Slider(
                      value: opacity,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) {
                        setDialogState(() => opacity = v);
                        setState(() => syncLivePreview());
                      },
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        InkWell(
                          onTap: () {
                            setDialogState(() => rotation = 0.0);
                            setState(() {
                              final idx = _currentElements.indexWhere((e) => e.id == el.id);
                              if (idx != -1) {
                                _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                              }
                            });
                          },
                          child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0).toDouble(),
                      min: -180,
                      max: 180,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) {
                        setDialogState(() => rotation = v);
                        setState(() => syncLivePreview());
                      },
                    ),
                  ],
                ),
              ),
              actions: [
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
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                  onPressed: () {
                    isApplied = true;
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          final updatedMod = mod.copyWith(name: name, color: color, opacity: opacity, properties: props);
                          final newSize = autoFit ? Size(calcAutoWidth(textProp, fontSize), el.size.height) : el.size;
                          _currentElements[idx] = el.copyWith(size: newSize, offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (!isApplied) {
        setState(() {
          final idx = _currentElements.indexWhere((e) => e.id == el.id);
          if (idx != -1) {
            _currentElements[idx] = el.copyWith(size: initialSize, rotation: initialRot, module: initialMod);
          }
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
        textCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型视觉面专属参数设置界面 =====
  void _showCompactSurfaceEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final mod = el.module!;
    String name = mod.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    final props = Map<String, dynamic>.from(mod.properties);
    bool isContainer = props['is_container_boundary'] == true;

    UIModuleShape shape = mod.shape;
    UIModuleMaterial material = mod.material;
    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('视觉面规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF888896)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                    const SizedBox(height: 12),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),

                    const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      title: const Text('设为复合组件容器底面', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                      subtitle: const Text('开启后，外框锁定为标准边框轮廓', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
                      value: isContainer,
                      activeThumbColor: const Color(0xFFE65100),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() {
                          isContainer = val;
                          if (val) {
                            for (final elem in _currentElements) {
                              elem.module?.properties.remove('is_container_boundary');
                            }
                            props['is_container_boundary'] = true;
                          } else {
                            props.remove('is_container_boundary');
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    const Text('外延几何形状', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<UIModuleShape>(
                      initialValue: shape,
                      decoration: _softInputDecoration(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: const [
                        DropdownMenuItem(value: UIModuleShape.rectangle, child: Text('直角')),
                        DropdownMenuItem(value: UIModuleShape.rounded, child: Text('圆角')),
                        DropdownMenuItem(value: UIModuleShape.capsule, child: Text('胶囊')),
                        DropdownMenuItem(value: UIModuleShape.circle, child: Text('正圆/椭圆')),
                        DropdownMenuItem(value: UIModuleShape.heart, child: Text('心形')),
                        DropdownMenuItem(value: UIModuleShape.star5, child: Text('五角星')),
                        DropdownMenuItem(value: UIModuleShape.star4, child: Text('四角星')),
                      ],
                      onChanged: (v) => setDialogState(() => shape = v ?? UIModuleShape.rounded),
                    ),
                    const SizedBox(height: 12),

                    const Text('视觉质感材质', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<UIModuleMaterial>(
                      initialValue: material,
                      decoration: _softInputDecoration(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: const [
                        DropdownMenuItem(value: UIModuleMaterial.glass, child: Text('毛玻璃')),
                        DropdownMenuItem(value: UIModuleMaterial.solid, child: Text('纯色磨砂')),
                        DropdownMenuItem(value: UIModuleMaterial.gradient, child: Text('科技渐变')),
                        DropdownMenuItem(value: UIModuleMaterial.outline, child: Text('极简描边')),
                      ],
                      onChanged: (v) => setDialogState(() => material = v ?? UIModuleMaterial.glass),
                    ),
                    const SizedBox(height: 12),

                    const Text('外观调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
                      ].map((c) {
                        final sel = color == c;
                        return GestureDetector(
                          onTap: () => setDialogState(() => color = c),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    Text('透明度 (${(opacity * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    Slider(
                      value: opacity,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) {
                        setDialogState(() => opacity = v);
                        setState(() {
                          final idx = _currentElements.indexWhere((e) => e.id == el.id);
                          if (idx != -1) {
                            _currentElements[idx] = _currentElements[idx].copyWith(
                              module: _currentElements[idx].module!.copyWith(opacity: v),
                            );
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        InkWell(
                          onTap: () {
                            setDialogState(() => rotation = 0.0);
                            setState(() {
                              final idx = _currentElements.indexWhere((e) => e.id == el.id);
                              if (idx != -1) {
                                _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                              }
                            });
                          },
                          child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0).toDouble(),
                      min: -180,
                      max: 180,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) {
                        setDialogState(() => rotation = v);
                        setState(() {
                          final idx = _currentElements.indexWhere((e) => e.id == el.id);
                          if (idx != -1) {
                            _currentElements[idx] = _currentElements[idx].copyWith(rotation: v);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          _currentElements[idx] = el;
                        }
                      });
                    });
                  },
                  child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                        if (idx != -1) {
                          final updatedMod = mod.copyWith(name: name, color: color, shape: shape, material: material, opacity: opacity, properties: props);
                          _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, module: updatedMod);
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
      });
    });
  }

  // ===== 紧凑型复合组合件专属规格编辑器 (Composite) =====
  void _showCompactCompositeEditorDialog(UIElement el) {
    if (!el.isComposite || el.composite == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    final comp = el.composite!;
    String name = comp.name;
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex) ? _activeLayerIndex : _sceneLayers.first.id;
    }
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;

    Color color = comp.color;
    UIModuleMaterial material = comp.material;
    double opacity = comp.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialComp = comp.copyWith();
    final initialRot = el.rotation;
    bool isApplied = false;

    void syncLivePreview() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx != -1) {
        final curEl = _currentElements[idx];
        if (curEl.composite != null) {
          _currentElements[idx] = curEl.copyWith(
            rotation: rotation,
            composite: curEl.composite!.copyWith(
              color: color,
              material: material,
              opacity: opacity,
            ),
          );
        }
      }
    }

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final offsetXCtrl = TextEditingController(text: offsetX.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetX.toStringAsFixed(0).length);
    final offsetYCtrl = TextEditingController(text: offsetY.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: offsetY.toStringAsFixed(0).length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('复合组合件规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
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
                              const Text('复合件组合标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                              const SizedBox(height: 12),

                              const Text('绝对物理坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(child: TextField(controller: offsetXCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (v) => offsetX = double.tryParse(v) ?? offsetX)),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(controller: offsetYCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (v) => offsetY = double.tryParse(v) ?? offsetY)),
                                ],
                              ),
                              const SizedBox(height: 12),

                              const Text('外框材质渲染模式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<UIModuleMaterial>(
                                initialValue: material,
                                decoration: _softInputDecoration(),
                                dropdownColor: Colors.white,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                                items: const [
                                  DropdownMenuItem(value: UIModuleMaterial.glass, child: Text('毛玻璃底框')),
                                  DropdownMenuItem(value: UIModuleMaterial.solid, child: Text('纯色实心框')),
                                  DropdownMenuItem(value: UIModuleMaterial.gradient, child: Text('科技风渐变')),
                                  DropdownMenuItem(value: UIModuleMaterial.outline, child: Text('极简描边')),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setDialogState(() => material = v);
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('外框调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
                                ].map((c) {
                                  final sel = color == c;
                                  return GestureDetector(
                                    onTap: () { setDialogState(() => color = c); setState(() => syncLivePreview()); },
                                    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1))),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              Text('透明度 (${(opacity * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              Slider(
                                value: opacity, min: 0.0, max: 1.0, activeColor: const Color(0xFFFF4081),
                                onChanged: (v) { setDialogState(() => opacity = v); setState(() => syncLivePreview()); },
                              ),
                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('整体旋转角度 (${rotation.round()}°)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() => rotation = 0.0);
                                      setState(() {
                                        final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                        if (idx != -1) _currentElements[idx] = _currentElements[idx].copyWith(rotation: 0.0);
                                      });
                                    },
                                    child: const Text('复位', style: TextStyle(fontSize: 11, color: Color(0xFFFF4081), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              Slider(
                                value: rotation.clamp(-180.0, 180.0).toDouble(), min: -180, max: 180, activeColor: const Color(0xFFFF4081),
                                onChanged: (v) { setDialogState(() => rotation = v); setState(() => syncLivePreview()); },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
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
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                            onPressed: () {
                              isApplied = true;
                              Navigator.pop(ctx);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() {
                                  final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                  if (idx != -1) {
                                    final updatedComp = comp.copyWith(name: name, color: color, material: material, opacity: opacity);
                                    _currentElements[idx] = el.copyWith(offset: Offset(offsetX, offsetY), layerIndex: selectedLayer, rotation: rotation, composite: updatedComp);
                                  }
                                });
                                _autoSave();
                              });
                            },
                            child: const Text('应用配置'),
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
          if (idx != -1) _currentElements[idx] = el.copyWith(rotation: initialRot, composite: initialComp);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
      });
    });
  }

  Widget _buildSchemeDetailedConfigSection(
      UIElement el,
      StateSetter setDialogState,
      Map<String, dynamic> props,
      ) {
    final linkerData = Map<String, dynamic>.from(props['linker'] ?? {});
    final srcId = linkerData['sourceModuleId']?.toString();
    final tgtId = linkerData['targetModuleId']?.toString();
    final schemeId = linkerData['scheme']?.toString();

    UIElement? srcElem = _currentElements.any((e) => e.id == srcId)
        ? _currentElements.firstWhere((e) => e.id == srcId)
        : null;
    UIElement? tgtElem = _currentElements.any((e) => e.id == tgtId)
        ? _currentElements.firstWhere((e) => e.id == tgtId)
        : null;

    final schemeDef = (schemeId != null && schemeId.isNotEmpty && schemeId != '未配置')
        ? LinkerMatrixEngine.getSchemeDefinition(schemeId)
        : null;

    final bool isFullyConnected = srcElem != null && tgtElem != null;

    final Map<String, dynamic> schemeParams =
        Map<String, dynamic>.from(linkerData['schemeParams'] ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 通路拓扑快照
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F6F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hub, size: 16, color: Color(0xFF00ACC1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFullyConnected
                      ? '${srcElem.module?.name ?? srcElem.id} ➔ ${tgtElem.module?.name ?? tgtElem.id}'
                      : '⚠️ 处于未完全连通状态',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isFullyConnected
                        ? const Color(0xFF111116)
                        : const Color(0xFFF57F17),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        const Text('通路优先级（数值 / 文本多源时优先级高者先取）', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          initialValue: ((linkerData['priority'] as num?)?.toInt() ?? 5).clamp(1, 10).toInt(),
          decoration: _softInputDecoration(),
          items: List.generate(
            10,
            (index) => DropdownMenuItem<int>(
              value: index + 1,
              child: Text('优先级 ${index + 1}${index == 4 ? '（默认）' : ''}'),
            ),
          ),
          onChanged: (value) {
            if (value == null) return;
            setDialogState(() {
              linkerData['priority'] = value;
              props['linker'] = linkerData;
            });
          },
        ),
        const SizedBox(height: 12),

        if (schemeDef?.isPulse == true) ...[
          const Text('脉冲安全限制（0 = 不限制）', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: ((linkerData['cooldownMs'] as num?)?.toInt() ?? 0).toString(),
                  keyboardType: TextInputType.number,
                  decoration: _softInputDecoration(label: '冷却毫秒'),
                  onChanged: (value) {
                    linkerData['cooldownMs'] = int.tryParse(value) ?? 0;
                    props['linker'] = linkerData;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: ((linkerData['maxTriggerCount'] as num?)?.toInt() ?? 0).toString(),
                  keyboardType: TextInputType.number,
                  decoration: _softInputDecoration(label: '最大触发次数'),
                  onChanged: (value) {
                    linkerData['maxTriggerCount'] = int.tryParse(value) ?? 0;
                    props['linker'] = linkerData;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        if (tgtElem != null &&
            ['button', 'input', 'slider', 'switch', 'select', 'indicator']
                .contains(tgtElem.module?.type)) ...[
          const Text('目标交互使能合并方式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: tgtElem.module!.properties['enabledCombineMode']?.toString() == 'or' ? 'or' : 'and',
            decoration: _softInputDecoration(),
            items: const [
              DropdownMenuItem(value: 'and', child: Text('AND：所有控制通路满足才启用')),
              DropdownMenuItem(value: 'or', child: Text('OR：任一控制通路满足即可启用')),
            ],
            onChanged: (value) {
              if (value == null) return;
              final targetIndex = _currentElements.indexWhere((element) => element.id == tgtElem.id);
              if (targetIndex == -1) return;
              final target = _currentElements[targetIndex];
              final targetProps = Map<String, dynamic>.from(target.module!.properties);
              targetProps['enabledCombineMode'] = value;
              _currentElements[targetIndex] = target.copyWith(
                module: target.module!.copyWith(properties: targetProps),
              );
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 12),
        ],

        if (tgtElem != null &&
            ['surface', 'surface_art', 'primitive_art', 'text', 'progress', 'slider', 'input', 'button', 'switch', 'select', 'indicator']
                .contains(tgtElem.module?.type)) ...[
          const Text('目标可见性合并方式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: tgtElem.module!.properties['visibleCombineMode']?.toString() == 'or' ? 'or' : 'and',
            decoration: _softInputDecoration(),
            items: const [
              DropdownMenuItem(value: 'and', child: Text('AND：所有控制通路满足才显示')),
              DropdownMenuItem(value: 'or', child: Text('OR：任一控制通路满足即可显示')),
            ],
            onChanged: (value) {
              if (value == null) return;
              final targetIndex = _currentElements.indexWhere((element) => element.id == tgtElem.id);
              if (targetIndex == -1) return;
              final target = _currentElements[targetIndex];
              final targetProps = Map<String, dynamic>.from(target.module!.properties);
              targetProps['visibleCombineMode'] = value;
              _currentElements[targetIndex] = target.copyWith(
                module: target.module!.copyWith(properties: targetProps),
              );
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 12),
        ],

        // 2. 当前关联的 Scheme Label & 描述
        if (schemeDef != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00ACC1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00ACC1).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route, size: 14, color: Color(0xFF00ACC1)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        schemeDef.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00ACC1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  LinkerMatrixEngine.userFacingDescription(schemeDef),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF555562)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 3. 详细参数表单区域
        if (!isFullyConnected || schemeDef == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '⚠️ 无通路或未选择传输方案。请在画布上连接端口或点击联动节点选择方案。',
              style: TextStyle(fontSize: 12, color: Color(0xFFF57F17), height: 1.4),
            ),
          )
        else ...[
          if (srcElem.module?.type == 'button') ...[
            const Text('触发手势端口 (Gesture Port)', style: TextStyle(fontSize: 12, color: Color(0xFF555562), fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: linkerData['sourcePort']?.toString() == 'double_tap'
                  ? 'double_tap'
                  : (linkerData['sourcePort']?.toString() == 'long_press' ? 'long_press' : 'tap'),
              decoration: _softInputDecoration(),
              dropdownColor: Colors.white,
              style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
              items: const [
                DropdownMenuItem(value: 'tap', child: Text('🟢 单击端口 (Tap)')),
                DropdownMenuItem(value: 'double_tap', child: Text('🔵 双击端口 (Double Tap)')),
                DropdownMenuItem(value: 'long_press', child: Text('🔴 长按端口 (Long Press)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setDialogState(() {
                  linkerData['sourcePort'] = v;
                  props['linker'] = linkerData;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          if (schemeDef.params.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: Color(0xFF2E7D32)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ 纯脉冲/动作触发协议，连通即生效，无需额外配置参数。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )
          else
            ...schemeDef.params.map((field) {
              return _buildDynamicParamControl(
                field: field,
                currentParams: schemeParams,
                onParamChanged: (newVal) {
                  setDialogState(() {
                    schemeParams[field.key] = newVal;
                    linkerData['schemeParams'] = schemeParams;
                    props['linker'] = linkerData;
                  });
                },
                onParamChangedSilently: (newVal) {
                  schemeParams[field.key] = newVal;
                  linkerData['schemeParams'] = schemeParams;
                  props['linker'] = linkerData;
                },
              );
            }),
        ],
      ],
    );
  }

  Widget _buildDynamicParamControl({
    required SchemeParamField field,
    required Map<String, dynamic> currentParams,
    required ValueChanged<dynamic> onParamChanged,
    ValueChanged<dynamic>? onParamChangedSilently,
  }) {
    final curVal = currentParams[field.key] ?? field.defaultValue;

    Widget controlWidget;

    switch (field.type) {
      case SchemeParamType.text:
        controlWidget = TextField(
          controller: TextEditingController(text: curVal?.toString() ?? '')
            ..selection = TextSelection.collapsed(offset: (curVal?.toString() ?? '').length),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
          decoration: _softInputDecoration(hintText: field.description),
          onChanged: (v) => onParamChanged(v),
        );
        break;
      case SchemeParamType.number:
      case SchemeParamType.doubleVal:
        final numericController = TextEditingController(
          text: curVal?.toString() ?? '',
        )..selection = TextSelection.collapsed(
            offset: (curVal?.toString() ?? '').length,
          );
        void commitNumericValue(String value) {
          final numVal = field.type == SchemeParamType.number
              ? int.tryParse(value)
              : double.tryParse(value);
          if (numVal != null) onParamChanged(numVal);
        }
        controlWidget = TextField(
          controller: numericController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
          decoration: _softInputDecoration(hintText: field.description),
          onChanged: (value) {
            final numVal = field.type == SchemeParamType.number
                ? int.tryParse(value)
                : double.tryParse(value);
            if (numVal != null) {
              (onParamChangedSilently ?? onParamChanged)(numVal);
            }
          },
          onSubmitted: commitNumericValue,
          onEditingComplete: () => commitNumericValue(numericController.text),
        );
        break;
      case SchemeParamType.boolean:
        final bool boolVal = (curVal is bool) ? curVal : (curVal.toString().toLowerCase() == 'true');
        controlWidget = Row(
          children: [
            Switch(
              value: boolVal,
              activeTrackColor: const Color(0xFF00ACC1),
              onChanged: (val) => onParamChanged(val),
            ),
            const SizedBox(width: 8),
            Text(boolVal ? '已开启' : '已关闭', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
          ],
        );
        break;
      case SchemeParamType.choice:
        final options = field.options ?? [];
        final String selectedChoice = options.contains(curVal?.toString())
            ? curVal!.toString()
            : (options.isNotEmpty ? options.first : '');

        String choiceLabel(String opt) {
          if (opt == 'ratio') return '📐 比例归一化 (0~100% 相对比例折算)';
          if (opt == 'absolute') return '📏 绝对物理数值透传 (超出自动截断)';
          return opt;
        }

        controlWidget = DropdownButtonFormField<String>(
          initialValue: selectedChoice,
          decoration: _softInputDecoration(),
          dropdownColor: Colors.white,
          style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
          items: options
              .map((opt) => DropdownMenuItem<String>(value: opt, child: Text(choiceLabel(opt))))
              .toList(),
          onChanged: (v) {
            if (v != null) onParamChanged(v);
          },
        );
        break;
      case SchemeParamType.color:
        final int argb = (curVal is num) ? curVal.toInt() : 0xFF4CAF50;
        const channelColors = <int>[
          0xFF4CAF50, // 绿色
          0xFFEF5350, // 红色
          0xFFFFA726, // 橙黄
          0xFF29B6F6, // 蓝色
          0xFFAB47BC, // 紫色
          0xFF9E9E9E, // 灰色
          0xFF26A69A, // 青色
          0xFFEC407A, // 粉色
        ];
        controlWidget = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...channelColors.map((colorValue) {
              final isSelected = colorValue == argb;
              return Tooltip(
                message: '#${colorValue.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onParamChanged(colorValue),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: isSelected ? 2.5 : 0,
                      ),
                      boxShadow: isSelected
                          ? const [BoxShadow(color: Colors.black26, blurRadius: 3)]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 17, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }),
            Tooltip(
              message: '输入自定义 HEX ARGB',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  final hexCtrl = TextEditingController(
                    text: '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                  );
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('自定义颜色通道'),
                      content: TextField(
                        controller: hexCtrl,
                        autofocus: true,
                        decoration: _softInputDecoration(label: 'HEX ARGB，例如 #FF4CAF50'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final parsed = int.tryParse(
                              hexCtrl.text.replaceAll('#', '').trim(),
                              radix: 16,
                            );
                            if (parsed != null) onParamChanged(parsed);
                            Navigator.pop(dialogContext);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ).whenComplete(hexCtrl.dispose);
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(argb),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF555562), width: 1.5),
                  ),
                  child: const Icon(Icons.edit, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: const TextStyle(fontSize: 12, color: Color(0xFF555562), fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          controlWidget,
        ],
      ),
    );
  }
}

class _InputColorChoice { final String label; final int value; const _InputColorChoice(this.label, this.value); }
