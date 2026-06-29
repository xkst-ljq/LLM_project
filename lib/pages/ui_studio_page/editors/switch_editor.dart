part of '../ui_studio_page.dart';

mixin _SwitchEditorDialog on _UIStudioLogic, _StudioMenuDialogs {
  // ===== 紧凑型布尔开关控件专属规格编辑器 (Switch) =====
  void _showCompactSwitchEditorDialog(UIElement el) {
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
    bool isOn = props['value'] != false;
    String varName = props['variable']?.toString() ?? 'switch_var';
    final int? inactiveVal = props['inactiveTrackColor'] as int?;
    Color inactiveColor = inactiveVal != null ? Color(inactiveVal) : Colors.grey.shade300;
    final int? thumbVal = props['thumbColor'] as int?;
    Color thumbColor = thumbVal != null ? Color(thumbVal) : Colors.white;

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
                          const Text('布尔开关规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
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

                              const Text('初始默认开关位状态', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  {'id': true, 'label': '默认开启 (ON)'},
                                  {'id': false, 'label': '默认关闭 (OFF)'},
                                ].map((item) {
                                  final sel = isOn == item['id'];
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          isOn = item['id'] as bool;
                                          props['value'] = isOn;
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
                                        child: Text(item['label']!.toString(), style: TextStyle(fontSize: 12, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              const Text('绑定逻辑变量名 (同步 SessionState 词典)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              TextField(
                                controller: varCtrl,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                                decoration: _softInputDecoration(helperText: '提示：实际对话中点击切换，实时同步 true 或 false 字面量。'),
                                onChanged: (v) {
                                  varName = v;
                                  props['variable'] = v;
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('开关开启高亮色调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  const Color(0xFF00E676), const Color(0xFF00ACC1), const Color(0xFF2979FF), const Color(0xFF651FFF), const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF37474F), Colors.black
                                ].map((c) {
                                  final sel = color == c;
                                  return GestureDetector(
                                    onTap: () { setDialogState(() => color = c); setState(() => syncLivePreview()); },
                                    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1))),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              const Text('未激活关闭位底槽调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  Colors.grey.shade300, Colors.grey.shade400, Colors.white, const Color(0xFF37474F), Colors.black, const Color(0xFFFF80AB), const Color(0xFF80D8FF)
                                ].map((c) {
                                  final sel = inactiveColor.toARGB32() == c.toARGB32();
                                  return GestureDetector(
                                    onTap: () { setDialogState(() { inactiveColor = c; props['inactiveTrackColor'] = c.toARGB32(); }); setState(() => syncLivePreview()); },
                                    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF00ACC1) : Colors.black12, width: sel ? 2.5 : 1))),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              const Text('拨动把手头填充调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  Colors.white, Colors.grey.shade100, const Color(0xFFFFD740), const Color(0xFF00E5FF), const Color(0xFFFF4081), Colors.black
                                ].map((c) {
                                  final sel = thumbColor.toARGB32() == c.toARGB32();
                                  return GestureDetector(
                                    onTap: () { setDialogState(() { thumbColor = c; props['thumbColor'] = c.toARGB32(); }); setState(() => syncLivePreview()); },
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
        varCtrl.dispose();
      });
    });
  }
}
