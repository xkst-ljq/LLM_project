part of '../ui_studio_page.dart';

mixin _ImageEditorDialog on _UIStudioLogic, _StudioMenuDialogs {
  // ===== 紧凑型静态位图占位插槽构件专属规格编辑器 (Image) =====
  void _showCompactImageEditorDialog(UIElement el) {
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
    String url = props['url']?.toString() ?? '';
    String assetPath = props['assetPath']?.toString() ?? '';
    String shapeStr = props['shape']?.toString() ?? 'rectangle';
    String fitStr = props['fit']?.toString() ?? 'cover';
    double radiusVal = (props['borderRadius'] ?? 8.0).toDouble().clamp(0.0, 48.0).toDouble();

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
    final urlCtrl = TextEditingController(text: url)..selection = TextSelection.collapsed(offset: url.length);

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
                          const Text('静态位图插槽规格编辑器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
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


                              const Text('网络图片连接 URL (支持 HTTP / DataURI)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 4),
                              TextField(
                                controller: urlCtrl,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                                decoration: _softInputDecoration(helperText: '例如 "https://example.com/avatar.png"'),
                                onChanged: (v) {
                                  url = v;
                                  props['url'] = v;
                                  setState(() => syncLivePreview());
                                },
                              ),
                              const SizedBox(height: 12),

                              const Text('本地位图素材文件插槽', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              if (assetPath.isEmpty) ...[
                                InkWell(
                                  onTap: () async {
                                    final picked = await ImagePickService.pickInsertImage(context);
                                    if (picked != null && picked.isNotEmpty) {
                                      setDialogState(() {
                                        assetPath = picked;
                                        props['assetPath'] = picked;
                                        props.remove('url');
                                        url = '';
                                        urlCtrl.clear();
                                      });
                                      setState(() => syncLivePreview());
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF64B5F6), width: 1.2),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF1976D2), size: 20),
                                        SizedBox(width: 6),
                                        Text('选择手机相册图片', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF81C784), width: 1.2),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('本地位图素材已就位', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                                            const SizedBox(height: 2),
                                            Text(assetPath.split('/').last.split('\\').last, style: const TextStyle(fontSize: 10, color: Color(0xFF388E3C)), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD32F2F), size: 20),
                                        onPressed: () {
                                          setDialogState(() {
                                            assetPath = '';
                                            props.remove('assetPath');
                                          });
                                          setState(() => syncLivePreview());
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),

                              const Text('外形轮廓剪裁规格', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6, runSpacing: 6,
                                children: [
                                  {'id': 'none', 'label': '原生抠图'},
                                  {'id': 'rectangle', 'label': '直角'},
                                  {'id': 'rounded', 'label': '圆角'},
                                  {'id': 'capsule', 'label': '药丸'},
                                  {'id': 'circle', 'label': '正圆头像'},
                                  {'id': 'heart', 'label': '心形相框'},
                                ].map((item) {
                                  final sel = shapeStr == item['id'];
                                  return GestureDetector(
                                    onTap: () {
                                      setDialogState(() {
                                        shapeStr = item['id']!;
                                        props['shape'] = shapeStr;
                                      });
                                      setState(() => syncLivePreview());
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF2979FF) : const Color(0xFFF5F5F7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(item['label']!, style: TextStyle(fontSize: 11, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              if (shapeStr == 'rounded') ...[
                                Text('圆角大小像素 (${radiusVal.round()}px)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                                Slider(
                                  value: radiusVal, min: 0.0, max: 48.0, activeColor: const Color(0xFF2979FF),
                                  onChanged: (v) {
                                    setDialogState(() {
                                      radiusVal = v;
                                      props['borderRadius'] = v;
                                    });
                                    setState(() => syncLivePreview());
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],

                              const Text('位图填充缩放模式 (Fit)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  {'id': 'cover', 'label': '充满裁切 (cover)'},
                                  {'id': 'contain', 'label': '等比适应 (contain)'},
                                  {'id': 'fill', 'label': '拉伸填满 (fill)'},
                                ].map((item) {
                                  final sel = fitStr == item['id'];
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          fitStr = item['id']!;
                                          props['fit'] = fitStr;
                                        });
                                        setState(() => syncLivePreview());
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: sel ? const Color(0xFF2979FF) : const Color(0xFFF5F5F7),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(item['label']!, style: TextStyle(fontSize: 11, color: sel ? Colors.white : const Color(0xFF111116), fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              const Text('占位区调色板', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: [
                                  const Color(0xFF2979FF), Colors.white, const Color(0xFFFF4081), const Color(0xFFFF6E40), const Color(0xFFFFD740), const Color(0xFF00E676), const Color(0xFF00E5FF), const Color(0xFF651FFF), const Color(0xFF37474F), Colors.black
                                ].map((c) {
                                  final sel = color == c;
                                  return GestureDetector(
                                    onTap: () { setDialogState(() => color = c); setState(() => syncLivePreview()); },
                                    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: sel ? const Color(0xFF2979FF) : Colors.black12, width: sel ? 2.5 : 1))),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              Text('占位透明度 (${(opacity * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF555562))),
                              Slider(
                                value: opacity, min: 0.0, max: 1.0, activeColor: const Color(0xFF2979FF),
                                onChanged: (v) { setDialogState(() => opacity = v); setState(() => syncLivePreview()); },
                              ),
                              const SizedBox(height: 12),

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
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2979FF)),
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
        urlCtrl.dispose();
      });
    });
  }
}
