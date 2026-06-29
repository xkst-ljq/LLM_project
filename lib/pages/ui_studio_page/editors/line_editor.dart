part of '../ui_studio_page.dart';

mixin _LineEditorDialog on _UIStudioLogic, _StudioMenuDialogs {
  // ===== 紧凑型多功能线段构件专属规格编辑器 (Line) =====
  void _showCompactLineEditorDialog(UIElement el) {
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
    double thickness = (props['thickness'] ?? 2.0).toDouble().clamp(1.0, 32.0).toDouble();
    String lineStyle = props['lineStyle']?.toString() ?? 'solid';
    String axis = props['axis']?.toString() ?? 'horizontal';

    Color color = mod.color;
    double opacity = mod.opacity.clamp(0.0, 1.0).toDouble();
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;

    final initialMod = mod.copyWith();
    final initialRot = el.rotation;
    final initialSize = el.size;
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
                          const Text('多功能线段规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
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

                              const Text('归属独立图层', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
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

                              const Text('轴向排版方向', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  {'id': 'horizontal', 'label': '横向水平'},
                                  {'id': 'vertical', 'label': '垂向垂直'},
                                ].map((item) {
                                  final sel = axis == item['id'];
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          axis = item['id']!;
                                          props['axis'] = axis;
                                          final curEl = _currentElements.firstWhere((e) => e.id == el.id);
                                          final sz = curEl.size;
                                          if ((axis == 'vertical' && sz.width > sz.height) || (axis == 'horizontal' && sz.height > sz.width)) {
                                            final idx = _currentElements.indexWhere((e) => e.id == el.id);
                                            if (idx != -1) _currentElements[idx] = curEl.copyWith(size: Size(sz.height, sz.width));
                                          }
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

                              const Text('线条视觉规格样式', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  {'id': 'solid', 'label': '实线'},
                                  {'id': 'dashed', 'label': '虚线'},
                                  {'id': 'dotted', 'label': '点线'},
                                  {'id': 'double', 'label': '双线'},
                                  {'id': 'curve', 'label': '曲线'},
                                ].map((item) {
                                  final sel = lineStyle == item['id'];
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          lineStyle = item['id']!;
                                          props['lineStyle'] = lineStyle;
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

                              Text('线条笔触粗细 (${thickness.round()}px)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              Slider(
                                value: thickness, min: 1.0, max: 32.0, activeColor: const Color(0xFF00ACC1),
                                onChanged: (v) {
                                  setDialogState(() {
                                    thickness = v;
                                    props['thickness'] = v;
                                  });
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('颜色调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  const Color(0xFFB0BEC5), Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
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
          if (idx != -1) _currentElements[idx] = el.copyWith(size: initialSize, rotation: initialRot, module: initialMod);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        offsetXCtrl.dispose();
        offsetYCtrl.dispose();
      });
    });
  }
}
