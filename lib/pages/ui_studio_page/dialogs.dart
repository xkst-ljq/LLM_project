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

  // ===== 元素编辑器（最大对话框，原样迁移） =====
  void _showTailoredPrecisionEditorDialog(UIElement el) {
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

    showDialog(
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
                      controller: TextEditingController(text: name)
                        ..selection = TextSelection.collapsed(offset: name.length),
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

                    // --- progress 配置 ---
                    if (!isComp && el.module?.type == 'progress') ...[
                      const Text('进度条范围设定 (最大值 / 当前预览值)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(
                                  text: maxProp.toStringAsFixed(0))
                                ..selection = TextSelection.collapsed(
                                    offset: maxProp.toStringAsFixed(0).length),
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
                              controller: TextEditingController(
                                  text: curProp.toStringAsFixed(0))
                                ..selection = TextSelection.collapsed(
                                    offset: curProp.toStringAsFixed(0).length),
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
                        controller: TextEditingController(text: textProp)
                          ..selection = TextSelection.collapsed(offset: textProp.length),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111116)),
                        decoration: _softInputDecoration(),
                        onChanged: (v) => textProp = v,
                      ),
                      const SizedBox(height: 16),
                      const Text('显示联动表达式（可选）',
                          style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                      const SizedBox(height: 4),
                      TextField(
                        controller: TextEditingController(text: displayExpr)
                          ..selection =
                          TextSelection.collapsed(offset: displayExpr.length),
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
                        controller: TextEditingController(text: labelProp)
                          ..selection = TextSelection.collapsed(offset: labelProp.length),
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
    );
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
            }
            if (linkerData['targetModuleId'] != null) {
              linkerData['scheme'] = 'current_to_text';
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
            }
            if (linkerData['sourceModuleId'] != null) {
              linkerData['scheme'] = 'current_to_text';
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
    final currentScheme = linkerData['scheme']?.toString() ?? 'current_to_text';

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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSchemeOptionTile(ctx, el, 'current_to_text', 'current → text (当前数值转文本)', currentScheme),
              const SizedBox(height: 8),
              _buildSchemeOptionTile(ctx, el, 'max_to_text', 'max → text (最大数值转文本)', currentScheme),
            ],
          ),
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
