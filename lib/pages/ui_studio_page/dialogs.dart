part of 'ui_studio_page.dart';

/// 所有对话框与底部弹窗
mixin _UIStudioDialogs on _UIStudioLogic {
  // ===== 保存菜单 =====
  void _showSaveMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bakeable = _currentElements.where(_isBakeableElement).length;
        final skipped = _currentElements.length - bakeable;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '保存成果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111116),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前工作台元素：${_currentElements.length} 个 · 可烘焙视觉层：$bakeable 个 · 跳过：$skipped 个',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777783),
                  ),
                ),
                const SizedBox(height: 14),
                _buildSaveMenuTile(
                  icon: Icons.save_alt_rounded,
                  title: '保存工作台草稿',
                  subtitle: '只保存当前画布，方便下次继续编辑；不加入资产库。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveWorkspaceDraft();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.dashboard_customize_rounded,
                  title: '保存为复合组件',
                  subtitle: '把当前画布元素保存为一个通用组件，子元素运行时仍独立存在。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveCurrentWorkspaceAsComposite();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.layers_clear_rounded,
                  title: '烘焙为面原子',
                  subtitle: '只合成可烘焙视觉层，文本/数据/交互热区会被跳过。',
                  onTap: bakeable == 0
                      ? null
                      : () {
                    Navigator.pop(ctx);
                    _bakeCurrentWorkspaceAsAtom();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Card(
      elevation: 0,
      color: enabled ? const Color(0xFFF6F6F9) : const Color(0xFFE9E9EF),
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        enabled: enabled,
        leading: Icon(
          icon,
          color: enabled ? const Color(0xFFFF4081) : const Color(0xFFAAAAB4),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Color(0xFF777783)),
        ),
        onTap: onTap,
      ),
    );
  }

  // ===== 元素编辑器 =====
  void _showTailoredPrecisionEditorDialog(UIElement el) {
    if (!el.isComposite && ['surface', 'surface_art', 'primitive_art'].contains(el.module?.type)) {
      _showCompactSurfaceEditorDialog(el);
      return;
    }
    if (!el.isComposite && el.module?.type == 'text') {
      _showCompactTextEditorDialog(el);
      return;
    }
    if (!el.isComposite && ['progress', 'slider'].contains(el.module?.type)) {
      _showCompactNumericEditorDialog(el);
      return;
    }
    if (!el.isComposite && ['input', 'button'].contains(el.module?.type)) {
      _showCompactLogicEditorDialog(el);
      return;
    }
    if (!el.isComposite && el.module?.type == 'linker') {
      _showCompactLinkerEditorDialog(el);
      return;
    }
    final bool isComp = el.isComposite;
    String name = isComp ? (el.composite?.name ?? '') : (el.module?.name ?? '');
    Color color =
        (isComp ? el.composite?.color : el.module?.color) ?? Colors.white;
    UIModuleShape shape =
        (!isComp ? el.module?.shape : null) ?? UIModuleShape.rounded;
    UIModuleMaterial material =
        (isComp ? el.composite?.material : el.module?.material) ??
            UIModuleMaterial.glass;
    double opacity =
    ((isComp ? el.composite?.opacity : el.module?.opacity) ?? 1.0)
        .clamp(0.0, 1.0)
        .toDouble();
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }
    int selectedLayer = el.layerIndex;
    if (!_sceneLayers.any((ly) => ly.id == selectedLayer)) {
      selectedLayer = _sceneLayers.any((ly) => ly.id == _activeLayerIndex)
          ? _activeLayerIndex
          : _sceneLayers.first.id;
    }

    Map<String, dynamic> props = Map.from(
      !isComp ? (el.module?.properties ?? {}) : {},
    );
    double rotation = ((el.rotation + 180) % 360 + 360) % 360 - 180;
    String textProp = props['text']?.toString() ?? '';
    String labelProp =
        props['label']?.toString() ?? props['variable']?.toString() ?? '';
    double maxProp = (props['max'] ?? 100.0).toDouble();
    double curProp = (props['current'] ?? 75.0).toDouble();
    String displayExpr = (!isComp && el.module?.type == 'text')
        ? (el.module!.displayExpression ?? '')
        : '';

    final nameCtrl = TextEditingController(text: name)..selection = TextSelection.collapsed(offset: name.length);
    final maxCtrl = TextEditingController(text: maxProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: maxProp.toStringAsFixed(0).length);
    final curCtrl = TextEditingController(text: curProp.toStringAsFixed(0))..selection = TextSelection.collapsed(offset: curProp.toStringAsFixed(0).length);
    final textCtrl = TextEditingController(text: textProp)..selection = TextSelection.collapsed(offset: textProp.length);
    final displayCtrl = TextEditingController(text: displayExpr)..selection = TextSelection.collapsed(offset: displayExpr.length);
    final labelCtrl = TextEditingController(text: labelProp)..selection = TextSelection.collapsed(offset: labelProp.length);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '全局模组资产规格配置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111116),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF888896),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 名称 ---
                    const Text('模块标识名称',
                        style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                      decoration: _softInputDecoration(),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 16),

                    // --- 图层 ---
                    const Text('模块所属独立 Z 轴图层（控制大层级显示顺序）',
                        style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: selectedLayer,
                      decoration: _softInputDecoration(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                      items: _sceneLayers.map((ly) {
                        return DropdownMenuItem<int>(
                          value: ly.id,
                          child: Text(
                            '${ly.name}${ly.id == _activeLayerIndex ? " (当前创作层)" : ""}',
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setDialogState(
                            () => selectedLayer = v ?? _activeLayerIndex,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- progress / slider 配置 ---
                    if (!isComp && ['progress', 'slider'].contains(el.module?.type)) ...[
                      const Text('范围与初值设定 (最大值 / 当前预览值)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: maxCtrl,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF111116)),
                              keyboardType: TextInputType.number,
                              decoration: _softInputDecoration(label: '最大值'),
                              onChanged: (v) => maxProp = double.tryParse(v) ?? 100.0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: curCtrl,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF111116)),
                              keyboardType: TextInputType.number,
                              decoration: _softInputDecoration(label: '预览值'),
                              onChanged: (v) => curProp = double.tryParse(v) ?? 75.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- text 配置 ---
                    if (!isComp && el.module?.type == 'text') ...[
                      const Text('文本显示内容',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: textCtrl,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(),
                        onChanged: (v) => textProp = v,
                      ),
                      const SizedBox(height: 16),
                      const Text('显示联动表达式（可选）',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: displayCtrl,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(
                          helperText:
                          '示例："{{current}} / {{max}} HP"  或  "{{progress.current}}/{{max}}"',
                        ),
                        onChanged: (v) => setDialogState(() => displayExpr = v),
                      ),
                      if (displayExpr.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '实时预览（属性模拟）：${displayExpr.replaceAllMapped(RegExp(r'\{\{\s*(current|progress\.current)\s*\}\}'), (_) => '75').replaceAllMapped(RegExp(r'\{\{\s*(max|progress\.max)\s*\}\}'), (_) => '100')}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF00ACC1),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    // --- input 配置 ---
                    if (!isComp && el.module?.type == 'input') ...[
                      const Text('输入逻辑变量名（可选）',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: labelCtrl,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(),
                        onChanged: (v) => labelProp = v,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- linker 配置 ---
                    if (!isComp && el.module?.type == 'linker') ...[
                      const Text(
                        '联动器配置',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF555562),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('数据源模块（输出方）',
                          style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      _buildSourceModuleDropdown(el, setDialogState, props),
                      const SizedBox(height: 12),
                      const Text('目标模块（接收方）',
                          style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      _buildTargetModuleDropdown(el, setDialogState, props),
                      const SizedBox(height: 12),
                      const Text('传输方案',
                          style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue:
                        el.module!.properties['linker']?['scheme']?.toString() ??
                            'current_to_text',
                        decoration: _softInputDecoration(),
                        items: const [
                          DropdownMenuItem(
                            value: 'current_to_text',
                            child: Text('current → text',
                                style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'max_to_text',
                            child: Text('max → text', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            final linkerData = Map<String, dynamic>.from(
                              el.module!.properties['linker'] ?? {},
                            );
                            linkerData['scheme'] = value;
                            props['linker'] = linkerData;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '提示：选择源模块和目标模块后，端口会自动填充。后续版本将支持可视化拖拽连线。',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // --- 容器边界框标识配置 ---
                    if (!isComp && ['surface', 'surface_art', 'primitive_art'].contains(el.module?.type)) ...[
                      SwitchListTile(
                        title: const Text('设为复合组件边框底面', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                        subtitle: const Text('开启后，该面元素的外框将作为复合组件的标准轮廓', style: TextStyle(fontSize: 10, color: Color(0xFF888896))),
                        value: props['is_container_boundary'] == true,
                        activeThumbColor: const Color(0xFFE65100),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDialogState(() {
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
                    ],

                    // --- 外观 ---
                    const Text('外观调色板',
                        style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Colors.white,
                        const Color(0xFFFF4081),
                        const Color(0xFFFF6E40),
                        const Color(0xFFFFD740),
                        const Color(0xFF00E676),
                        const Color(0xFF00E5FF),
                        const Color(0xFF2979FF),
                        const Color(0xFF651FFF),
                        const Color(0xFF37474F),
                      ].map((c) {
                        return GestureDetector(
                          onTap: () => setDialogState(() => color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c
                                    ? const Color(0xFF111116)
                                    : Colors.black12,
                                width: color == c ? 2.5 : 1,
                              ),
                              boxShadow: [
                                if (color == c)
                                  const BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // --- 透明度 ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('透明度 / 融合强度',
                            style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                        Text(
                          '${(opacity * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888896),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: opacity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) => setDialogState(() => opacity = v),
                    ),
                    const Text(
                      '提示：当前不再提供自动重叠融合；如需柔和过渡，请通过透明度或颜色渐变设计实现。',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF888896),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- 材质 & 形状 ---
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('渲染材质皮肤',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF555562))),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<UIModuleMaterial>(
                                initialValue: material,
                                decoration: _softInputDecoration(),
                                dropdownColor: Colors.white,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF111116)),
                                items: const [
                                  DropdownMenuItem(
                                      value: UIModuleMaterial.glass,
                                      child: Text('毛玻璃质感')),
                                  DropdownMenuItem(
                                      value: UIModuleMaterial.solid,
                                      child: Text('纯色实心')),
                                  DropdownMenuItem(
                                      value: UIModuleMaterial.gradient,
                                      child: Text('科技渐变')),
                                  DropdownMenuItem(
                                      value: UIModuleMaterial.outline,
                                      child: Text('极简描边')),
                                ],
                                onChanged: (v) => setDialogState(
                                        () => material = v ?? UIModuleMaterial.glass),
                              ),
                            ],
                          ),
                        ),
                        if (!isComp) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('几何外延',
                                    style: TextStyle(
                                        fontSize: 12, color: Color(0xFF555562))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<UIModuleShape>(
                                  initialValue: shape,
                                  decoration: _softInputDecoration(),
                                  dropdownColor: Colors.white,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF111116)),
                                  items: const [
                                    DropdownMenuItem(
                                        value: UIModuleShape.rectangle,
                                        child: Text('直角')),
                                    DropdownMenuItem(
                                        value: UIModuleShape.rounded,
                                        child: Text('圆角')),
                                    DropdownMenuItem(
                                        value: UIModuleShape.capsule,
                                        child: Text('胶囊')),
                                    DropdownMenuItem(
                                        value: UIModuleShape.circle,
                                        child: Text('椭圆 / 正圆')),
                                  ],
                                  onChanged: (v) => setDialogState(
                                          () => shape = v ?? UIModuleShape.rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),
                    // --- 旋转 ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('旋转角度 (绕中心)',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF555562))),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${rotation.round()}°',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF888896),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => setDialogState(() => rotation = 0.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4081)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '复位',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFFF4081),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: rotation.clamp(-180.0, 180.0),
                      min: -180,
                      max: 180,
                      divisions: 360,
                      activeColor: const Color(0xFFFF4081),
                      onChanged: (v) => setDialogState(() => rotation = v),
                    ),
                    const Text(
                      '提示：画布上拖右下角把手(青色旋转模式)可自由旋转，接近水平/垂直会自动吸附。',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF888896),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF888896))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4081),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        final list = _currentElements;
                        final index = list.indexWhere((e) => e.id == el.id);
                        if (index != -1) {
                          if (!isComp) {
                            Map<String, dynamic> updatedProps =
                            Map.from(el.module!.properties);
                            updatedProps['text'] = textProp;
                            if (el.module!.type == 'input') {
                              updatedProps['variable'] = labelProp;
                              updatedProps.remove('label');
                            } else {
                              updatedProps['label'] = labelProp;
                            }
                            updatedProps['max'] = maxProp;
                            updatedProps['current'] = curProp;
                            updatedProps = _syncArtModuleProperties(
                              module: el.module!,
                              props: updatedProps,
                              color: color,
                              opacity: opacity,
                              shape: shape,
                              material: material,
                              borderRadius: el.module!.borderRadius,
                            );
                            final newMod = el.module!.copyWith(
                              name: name,
                              color: color,
                              shape: shape,
                              material: material,
                              opacity: opacity,
                              properties: updatedProps,
                              displayExpression: (el.module!.type == 'text')
                                  ? (displayExpr.trim().isNotEmpty
                                  ? displayExpr.trim()
                                  : null)
                                  : el.module!.displayExpression,
                            );
                            list[index] = el.copyWith(
                              module: newMod,
                              layerIndex: selectedLayer,
                              rotation: rotation,
                            );
                          } else {
                            final newComp = el.composite!.copyWith(
                              name: name,
                              color: color,
                              material: material,
                              opacity: opacity,
                            );
                            list[index] = el.copyWith(
                              composite: newComp,
                              layerIndex: selectedLayer,
                              rotation: rotation,
                            );
                          }
                        }
                      });
                      _autoSave();
                    });
                  },
                  child: const Text(
                    '确定应用',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        maxCtrl.dispose();
        curCtrl.dispose();
        textCtrl.dispose();
        displayCtrl.dispose();
        labelCtrl.dispose();
      });
    });
  }

  InputDecoration _softInputDecoration({String? label, String? helperText}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF2F2F6),
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF888896)),
      helperText: helperText,
      helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF888896)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _buildSourceModuleDropdown(
      UIElement el,
      void Function(void Function()) setDialogState,
      Map<String, dynamic> props,
      ) {
    final sourceModules = _getLinkableSourceModules();
    final currentSourceId = el.module!.properties['linker']?['sourceModuleId']?.toString();
    final validSourceValue =
    sourceModules.any((m) => m['id'] == currentSourceId) ? currentSourceId : null;

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('无 (断开连接)', style: TextStyle(fontSize: 12, color: Color(0xFF888896))),
      ),
      ...sourceModules.map((moduleInfo) {
        return DropdownMenuItem<String?>(
          value: moduleInfo['id'],
          child: Text(
            '${moduleInfo['name']} (${moduleInfo['type']})',
            style: const TextStyle(fontSize: 12),
          ),
        );
      }),
    ];

    return DropdownButtonFormField<String?>(
      initialValue: validSourceValue,
      decoration: _softInputDecoration(),
      items: items,
      onChanged: (value) {
        setDialogState(() {
          final linkerData = Map<String, dynamic>.from(
            el.module!.properties['linker'] ?? {},
          );
          if (value == null) {
            linkerData.remove('sourceModuleId');
            linkerData.remove('sourcePort');
            linkerData.remove('sourceType');
          } else {
            linkerData['sourceModuleId'] = value;
            final sourceType = sourceModules.firstWhere((m) => m['id'] == value)['type'];
            if (sourceType == 'progress' || sourceType == 'slider') {
              linkerData['sourcePort'] = 'current';
              linkerData['sourceType'] = 'number';
            } else if (sourceType == 'text') {
              linkerData['sourcePort'] = 'text';
              linkerData['sourceType'] = 'string';
              linkerData['scheme'] = 'text_to_text';
            }
          }
          props['linker'] = linkerData;
        });
      },
    );
  }

  Widget _buildTargetModuleDropdown(
      UIElement el,
      void Function(void Function()) setDialogState,
      Map<String, dynamic> props,
      ) {
    final targetModules = _getLinkableTargetModules();
    final currentTargetId = el.module!.properties['linker']?['targetModuleId']?.toString();
    final validTargetValue =
    targetModules.any((m) => m['id'] == currentTargetId) ? currentTargetId : null;

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('无 (断开连接)', style: TextStyle(fontSize: 12, color: Color(0xFF888896))),
      ),
      ...targetModules.map((moduleInfo) {
        return DropdownMenuItem<String?>(
          value: moduleInfo['id'],
          child: Text(
            '${moduleInfo['name']} (${moduleInfo['type']})',
            style: const TextStyle(fontSize: 12),
          ),
        );
      }),
    ];

    return DropdownButtonFormField<String?>(
      initialValue: validTargetValue,
      decoration: _softInputDecoration(),
      items: items,
      onChanged: (value) {
        setDialogState(() {
          final linkerData = Map<String, dynamic>.from(
            el.module!.properties['linker'] ?? {},
          );
          if (value == null) {
            linkerData.remove('targetModuleId');
            linkerData.remove('targetPort');
            linkerData.remove('targetType');
          } else {
            linkerData['targetModuleId'] = value;
            final targetType = targetModules.firstWhere((m) => m['id'] == value)['type'];
            if (targetType == 'text') {
              linkerData['targetPort'] = 'text';
              linkerData['targetType'] = 'string';
            } else if (targetType == 'input') {
              linkerData['targetPort'] = 'variable';
              linkerData['targetType'] = 'string';
              if (linkerData['sourceType'] == 'string') {
                linkerData['scheme'] = 'text_to_text';
              }
            }
          }
          props['linker'] = linkerData;
        });
      },
    );
  }

  // ===== 删除确认 =====
  void _confirmDeleteModule(UIModule module) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '删除资产',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        content: Text(
          '确定删除「${module.name}」吗？',
          style: const TextStyle(fontSize: 13, color: Color(0xFF555562)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4081),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _assetService.removeModule(module.id));
              _autoSave();
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteComposite(UIComposite composite) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '删除资产',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        content: Text(
          '确定删除「${composite.name}」吗？',
          style: const TextStyle(fontSize: 13, color: Color(0xFF555562)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4081),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _assetService.removeComposite(composite.id));
              _autoSave();
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
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
      });
    });
  }

  // ===== 紧凑型逻辑输入控件专属规格编辑器 (Input & Button) =====
  void _showCompactLogicEditorDialog(UIElement el) {
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
                    const Text('节点标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    TextField(controller: nameCtrl, style: const TextStyle(fontSize: 13, color: Color(0xFF111116)), decoration: _softInputDecoration(), onChanged: (v) => name = v),
                    const SizedBox(height: 12),

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

                    const Text('传导关系与清洗方案', style: TextStyle(fontSize: 13, color: Color(0xFF111116), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    const Text('数据输出源模组 (Out)', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    _buildSourceModuleDropdown(el, setDialogState, props),
                    const SizedBox(height: 12),

                    const Text('接收数据目标模组 (In)', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    _buildTargetModuleDropdown(el, setDialogState, props),
                    const SizedBox(height: 12),

                    const Text('传输方案规则 (Scheme)', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                    const SizedBox(height: 4),
                    Builder(builder: (bCtx) {
                      final lkMap = (props['linker'] as Map?)?.cast<String, dynamic>();
                      final srcId = lkMap?['sourceModuleId']?.toString();
                      final tgtId = lkMap?['targetModuleId']?.toString();
                      final srcElem = _currentElements.any((e) => e.id == srcId) ? _currentElements.firstWhere((e) => e.id == srcId) : null;
                      final tgtElem = _currentElements.any((e) => e.id == tgtId) ? _currentElements.firstWhere((e) => e.id == tgtId) : null;
                      final sType = srcElem?.module?.type;
                      final tType = tgtElem?.module?.type;

                      List<DropdownMenuItem<String>> allowedItems = [];
                      if (['progress', 'slider'].contains(sType) && ['progress', 'slider'].contains(tType)) {
                        allowedItems = [const DropdownMenuItem(value: 'num_to_current', child: Text('num → current (数值同步)'))];
                      } else if (['progress', 'slider'].contains(sType) && tType == 'text') {
                        allowedItems = [
                          const DropdownMenuItem(value: 'current_to_text', child: Text('current → text (数值驱动)')),
                          const DropdownMenuItem(value: 'max_to_text', child: Text('max → text (上限驱动)')),
                        ];
                      } else if (sType == 'text' && ['input', 'button'].contains(tType)) {
                        allowedItems = [const DropdownMenuItem(value: 'text_to_text', child: Text('text → text (提示词语义赋权)'))];
                      } else if (['input', 'button'].contains(sType) && tType == 'text') {
                        allowedItems = [const DropdownMenuItem(value: 'to_string', child: Text('to_string (实时回写展示)'))];
                      } else {
                        allowedItems = const [
                          DropdownMenuItem(value: 'current_to_text', child: Text('current → text (数值驱动)')),
                          DropdownMenuItem(value: 'max_to_text', child: Text('max → text (上限驱动)')),
                          DropdownMenuItem(value: 'num_to_current', child: Text('num → current (数值同步)')),
                          DropdownMenuItem(value: 'to_string', child: Text('to_string (强转字符串)')),
                          DropdownMenuItem(value: 'text_to_text', child: Text('text → text (提示词语义赋权)')),
                        ];
                      }

                      final curScheme = lkMap?['scheme']?.toString() ?? allowedItems.first.value!;
                      final validInitialScheme = allowedItems.any((it) => it.value == curScheme) ? curScheme : allowedItems.first.value!;

                      return DropdownButtonFormField<String>(
                        key: ValueKey('${srcId}_$tgtId'),
                        initialValue: validInitialScheme,
                        decoration: _softInputDecoration(),
                        dropdownColor: Colors.white,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF111116)),
                        items: allowedItems,
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            final linkerData = Map<String, dynamic>.from(el.module!.properties['linker'] ?? {});
                            linkerData['scheme'] = value;
                            props['linker'] = linkerData;
                          });
                        },
                      );
                    }),
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
                      onChanged: (v) {
                        setDialogState(() => rotation = v);
                        setState(() {
                          final idx = _currentElements.indexWhere((e) => e.id == el.id);
                          if (idx != -1) _currentElements[idx] = _currentElements[idx].copyWith(rotation: v);
                        });
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
}
