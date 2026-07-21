part of '../ui_studio_page.dart';

mixin _MathNodeEditorDialog on _UIStudioLogic, _StudioMenuDialogs {
  static const _paramKeys = ['paramA', 'paramB', 'paramC'];

  void _showCompactMathNodeEditorDialog(UIElement el) {
    if (el.module == null) return;
    if (_sceneLayers.isEmpty) {
      _sceneLayers = [LayerScene(id: 0, name: '默认图层 Level 0')];
    }

    final mod = el.module!;
    final props = Map<String, dynamic>.from(mod.properties);
    String name = mod.name;
    int selectedLayer = _sceneLayers.any((layer) => layer.id == el.layerIndex)
        ? el.layerIndex
        : _activeLayerIndex;
    double offsetX = el.offset.dx;
    double offsetY = el.offset.dy;
    String operation = props['operation']?.toString() ?? '+';
    double paramA = (props['paramA'] as num?)?.toDouble() ??
        (props['value'] as num?)?.toDouble() ??
        0;
    double paramB = (props['paramB'] as num?)?.toDouble() ?? 0;
    double paramC = (props['paramC'] as num?)?.toDouble() ?? 0;
    double fallbackValue = (props['fallbackValue'] as num?)?.toDouble() ?? 0;
    bool frozen = props['frozen'] == true;
    final hasControlLink = _currentElements.any((candidate) {
      if (candidate.module?.type != 'linker') return false;
      final data = (candidate.module!.properties['linker'] as Map?)?.cast<String, dynamic>();
      return data?['targetModuleId'] == el.id &&
          (data?['targetPort'] == 'gate_in' ||
              data?['scheme'] == 'click_to_math_trigger' ||
              data?['scheme'] == 'timer_tick_to_math_trigger');
    });
    final storedActive = props['activeParams'];
    final activeParams = storedActive is List
        ? storedActive
            .map((value) => value.toString())
            .where(_paramKeys.contains)
            .toSet()
            .toList()
        : <String>[];
    if (activeParams.isEmpty) activeParams.addAll(['paramA', 'paramB']);

    final nameCtrl = TextEditingController(text: name);
    final xCtrl = TextEditingController(text: offsetX.toStringAsFixed(0));
    final yCtrl = TextEditingController(text: offsetY.toStringAsFixed(0));
    final aCtrl = TextEditingController(text: paramA.toString());
    final bCtrl = TextEditingController(text: paramB.toString());
    final cCtrl = TextEditingController(text: paramC.toString());
    final fallbackCtrl = TextEditingController(text: fallbackValue.toString());

    void dismissEditor(BuildContext dialogContext) {
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      });
    }

    bool isOperationValid() {
      if (operation == 'set') return activeParams.length == 1;
      if (['>', '<', '>=', '<=', '=='].contains(operation)) {
        return activeParams.length == 2;
      }
      return activeParams.length >= 2;
    }

    void updateProperties() {
      props
        ..['operation'] = operation
        ..['paramA'] = paramA
        ..['paramB'] = paramB
        ..['paramC'] = paramC
        ..['activeParams'] = List<String>.from(activeParams)
        ..['fallbackValue'] = fallbackValue
        ..['calculationMode'] = 'auto'
        ..['frozen'] = frozen
        ..remove('value')
        ..remove('extractMethod')
        ..remove('extractKey')
        ..remove('extractIndex')
        ..remove('delimiter')
        ..remove('gateFallback');
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isComparison = ['>', '<', '>=', '<=', '=='].contains(operation);
          final requirement = operation == 'set'
              ? '设定值需要且只能启用 1 个参数口'
              : isComparison
                  ? '比较运算需要且只能启用 2 个参数口'
                  : '四则运算至少启用 2 个参数口；顺序即运算顺序';
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
                      children: [
                        const Expanded(
                          child: Text('算术计算节点', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => dismissEditor(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('模块标识名称', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                            const SizedBox(height: 4),
                            TextField(controller: nameCtrl, decoration: _softInputDecoration(), onChanged: (value) => name = value),
                            const SizedBox(height: 12),
                            const Text('绝对像素坐标 (X, Y)', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: TextField(controller: xCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'X坐标'), onChanged: (value) => offsetX = double.tryParse(value) ?? offsetX)),
                                const SizedBox(width: 10),
                                Expanded(child: TextField(controller: yCtrl, keyboardType: TextInputType.number, decoration: _softInputDecoration(label: 'Y坐标'), onChanged: (value) => offsetY = double.tryParse(value) ?? offsetY)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (!isOperationValid()) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFEF5350)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 18,
                                      color: Color(0xFFC62828),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '当前式子无效：$requirement',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFC62828),
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDE7F6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD1C4E9)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasControlLink) ...[
                                    const Text('控制端口状态', style: TextStyle(fontSize: 12, color: Color(0xFF555562))),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '顶部金色“计算触发”端口已连通，运行时会自动采用手动计算模式。',
                                      style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  const Text('运算规则与有序操作数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF512DA8))),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: operation,
                                    decoration: _softInputDecoration(),
                                    items: const [
                                      DropdownMenuItem(value: 'set', child: Text('设定值（取第 1 个启用参数）')),
                                      DropdownMenuItem(value: '+', child: Text('连续加法')),
                                      DropdownMenuItem(value: '-', child: Text('连续减法')),
                                      DropdownMenuItem(value: '*', child: Text('连续乘法')),
                                      DropdownMenuItem(value: '/', child: Text('连续除法')),
                                      DropdownMenuItem(value: '>', child: Text('大于')),
                                      DropdownMenuItem(value: '<', child: Text('小于')),
                                      DropdownMenuItem(value: '>=', child: Text('大于等于')),
                                      DropdownMenuItem(value: '<=', child: Text('小于等于')),
                                      DropdownMenuItem(value: '==', child: Text('等于')),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) setDialogState(() => operation = value);
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Text(requirement, style: const TextStyle(fontSize: 11, color: Color(0xFF555562), height: 1.3)),
                                  const SizedBox(height: 8),
                                  _buildMathOperandRow('参数 A', 'paramA', aCtrl, activeParams, setDialogState, (value) => paramA = double.tryParse(value) ?? paramA),
                                  const SizedBox(height: 6),
                                  _buildMathOperandRow('参数 B', 'paramB', bCtrl, activeParams, setDialogState, (value) => paramB = double.tryParse(value) ?? paramB),
                                  const SizedBox(height: 6),
                                  _buildMathOperandRow('参数 C', 'paramC', cCtrl, activeParams, setDialogState, (value) => paramC = double.tryParse(value) ?? paramC),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('冻结计算', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('冻结时保留 fallbackValue，忽略上游参数变化', style: TextStyle(fontSize: 11, color: Color(0xFF555562))),
                              value: frozen,
                              activeThumbColor: const Color(0xFF512DA8),
                              onChanged: (value) => setDialogState(() => frozen = value),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: fallbackCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              decoration: _softInputDecoration(label: '冻结 / 运算失败回退值'),
                              onChanged: (value) => fallbackValue = double.tryParse(value) ?? fallbackValue,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                            '左侧青色“数值”端口只接收参数 A/B/C 的数值通路；顶部金色“计算触发”端口只接收 Button 或 Timer 触发通路。前方编号代表参与顺序。点击灰色圆点可加入序列；点击编号圆点可移除；使用上下箭头调整顺序。未启用参数的 Linker 连接会保留，但不会参与当前计算。触发端口连通时，输出会等待 Button 或 Timer 触发。',
                            style: TextStyle(fontSize: 11, color: Color(0xFF555562), height: 1.35),
                          ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('删除'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
                          onPressed: () {
                            dismissEditor(ctx);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _deleteElement(el.id);
                            });
                          },
                        ),
                        const Spacer(),
                        TextButton(onPressed: () => dismissEditor(ctx), child: const Text('取消')),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF512DA8)),
                          onPressed: () {
                            if (!isOperationValid()) return;
                            updateProperties();
                            dismissEditor(ctx);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                final index = _currentElements.indexWhere((element) => element.id == el.id);
                                if (index != -1) {
                                  _currentElements[index] = _currentElements[index].copyWith(
                                    offset: Offset(offsetX, offsetY),
                                    layerIndex: selectedLayer,
                                    module: _currentElements[index].module!.copyWith(name: name, properties: props),
                                  );
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
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        xCtrl.dispose();
        yCtrl.dispose();
        aCtrl.dispose();
        bCtrl.dispose();
        cCtrl.dispose();
        fallbackCtrl.dispose();
      });
    });
  }

  Widget _buildMathOperandRow(
    String label,
    String paramKey,
    TextEditingController controller,
    List<String> activeParams,
    StateSetter setDialogState,
    ValueChanged<String> onChanged,
  ) {
    final order = activeParams.indexOf(paramKey);
    final active = order != -1;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setDialogState(() {
              if (active) {
                activeParams.remove(paramKey);
              } else {
                activeParams.add(paramKey);
              }
            });
          },
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF512DA8) : const Color(0xFFE0E0E6),
              shape: BoxShape.circle,
            ),
            child: Text(
              active ? '${order + 1}' : '○',
              style: TextStyle(color: active ? Colors.white : const Color(0xFF777783), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: _softInputDecoration(label: label),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: IconButton(
                  tooltip: '前移',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  onPressed: active && order > 0
                      ? () => setDialogState(() {
                            final previous = activeParams[order - 1];
                            activeParams[order - 1] = paramKey;
                            activeParams[order] = previous;
                          })
                      : null,
                ),
              ),
              SizedBox(
                width: 30,
                child: IconButton(
                  tooltip: '后移',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  onPressed: active && order < activeParams.length - 1
                      ? () => setDialogState(() {
                            final next = activeParams[order + 1];
                            activeParams[order + 1] = paramKey;
                            activeParams[order] = next;
                          })
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
