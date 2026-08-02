part of '../character_assembly_page.dart';

/// 元件专项编辑器：原子实例 · 外观与动画 · timer · math_node · 几何。
///
/// 从 `logic_canvas.dart` 再拆一层——画布的**交互逻辑**（拖拽、选中、
/// 吸附）与**编辑器面板**是两件事，混在一个 3400 行的文件里，
/// 改一个下拉框还要在拖拽代码里翻半天。
///
/// **纯搬运**：未改动任何一行逻辑与签名。
///
/// ## 为什么是独立 mixin
///
/// Dart 的 `part` 文件不能续写另一个 part 里打开的类体，
/// 每个 part 必须自成完整的顶层声明。私有成员在同一个库内
/// 仍互相可见，调用关系不受影响。
mixin _AssemblyEditorsLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _AssemblyPageLogic,
        _AssemblyCanvasLogic {
  /// 关键职责标签。点亮后配色与所属 UI 模式一致。
  Widget _buildKeyActionTag({
    required String mode,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = UISemanticRole.colorOf(mode);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? color : const Color(0xFFBDBDC6),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 13,
              color: active ? Colors.white : const Color(0xFF9E9EA8),
            ),
            const SizedBox(width: 4),
            Text(
              UISemanticRole.actionLabelOf(mode),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF777783),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「发送消息」标记标签。
  Widget _buildSendMessageTag({
    required bool active,
    required bool isInput,
    required VoidCallback onTap,
  }) {
    const color = Color(0xFF2E7D32);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? color : const Color(0xFFBDBDC6),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.send_rounded : Icons.send_outlined,
              size: 13,
              color: active ? Colors.white : const Color(0xFF9E9EA8),
            ),
            const SizedBox(width: 4),
            Text(
              isInput ? '回车发送' : '点击发送',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF777783),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _supportsAtomInstanceEditor(String type) {
    return const {
      'text',
      'surface',
      'base_box',
      'progress',
      'button',
      'line',
      'input',
      'switch',
      'slider',
      'select',
      'indicator',
      'image',
      'message_flow',
    }.contains(type);
  }

  /// 是否禁止改动几何（半锁与全锁都禁）。
  bool _isGeometryLocked(UIElement element) =>
      element.layoutLocked || element.sealed;

  /// 精确几何编辑器。与 Studio 的「精确几何」保持一致：
  /// X / Y / 宽 / 高 / 旋转五项，面类组件放宽尺寸上限。
  Future<void> _showGeometryEditorDialog(UIElement element) async {
    if (_isGeometryLocked(element)) {
      _showSnack('该组件已锁定，请先解除锁定');
      return;
    }

    const surfaceTypes = {'surface', 'surface_art', 'primitive_art', 'base_box'};
    final isSurface = surfaceTypes.contains(element.module?.type);
    // 面类是容器，允许远大于画布；其余组件限制在合理范围内，
    // 免得手滑输入 9999 把整个方案撑坏。
    final maxWidth = isSurface ? 4096.0 : 600.0;
    final maxHeight = isSurface ? 4096.0 : 400.0;
    final minWidth = element.module?.type == 'progress' ? 12.0 : 20.0;
    final minHeight = element.module?.type == 'progress' ? 6.0 : 20.0;

    var x = element.offset.dx;
    var y = element.offset.dy;
    var w = element.size.width;
    var h = element.size.height;
    var r = element.rotation;

    final xc = TextEditingController(text: x.toStringAsFixed(0));
    final yc = TextEditingController(text: y.toStringAsFixed(0));
    final wc = TextEditingController(text: w.toStringAsFixed(0));
    final hc = TextEditingController(text: h.toStringAsFixed(0));
    final rc = TextEditingController(text: r.toStringAsFixed(0));

    Widget field(
      TextEditingController controller,
      String label,
      ValueChanged<double> onChanged,
    ) {
      return TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          final parsed = double.tryParse(v.trim());
          if (parsed != null) onChanged(parsed);
        },
      );
    }

    // 输入法未确认时直接 pop，会让 TextField 在 dispose 后又被重建一帧。
    // 先摘掉焦点、等一帧再关，与本文件其余弹窗一致。
    Future<void> closeDialog(BuildContext ctx, bool value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    final applied = await showKeyboardSafeDialog<bool>(
      context: context,
      // controller 交给弹窗托管：await 返回时退场动画还要跑 ~150ms，
      // 期间 TextField 仍在重建，自行 dispose 会抛
      // 「A TextEditingController was used after being disposed」。
      disposables: [
        xc,
        yc,
        wc,
        hc,
        rc,
      ],
      builder: (ctx) => AlertDialog(
        title: const Text('精确几何'),
        content: SizedBox(
          width: 360,
          // 键盘弹出时对话框可用高度骤减，不滚动会直接 overflow。
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: field(xc, 'X', (v) => x = v)),
                  const SizedBox(width: 8),
                  Expanded(child: field(yc, 'Y', (v) => y = v)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: field(wc, '宽度', (v) => w = v)),
                  const SizedBox(width: 8),
                  Expanded(child: field(hc, '高度', (v) => h = v)),
                ],
              ),
              const SizedBox(height: 10),
              field(rc, '旋转角度', (v) => r = v),
              const SizedBox(height: 10),
              Text(
                '坐标以 PCB 左上角为原点。'
                '尺寸范围：宽 ${minWidth.toStringAsFixed(0)}~'
                '${maxWidth.toStringAsFixed(0)}，'
                '高 ${minHeight.toStringAsFixed(0)}~'
                '${maxHeight.toStringAsFixed(0)}。',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF777783),
                  height: 1.35,
                ),
              ),
            ],
          ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => closeDialog(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => closeDialog(ctx, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );

    if (applied == true && mounted) {
      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        setState(() {
          _elements[index] = _elements[index].copyWith(
            offset: Offset(x, y),
            size: Size(
              w.clamp(minWidth, maxWidth).toDouble(),
              h.clamp(minHeight, maxHeight).toDouble(),
            ),
            rotation: r,
          );
        });
        _persistAssemblyElements();
      }
    }

  }

  /// 精确位移：按方向键逐像素挪动。
  void _nudgeElement(UIElement element, Offset delta) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    if (_isGeometryLocked(_elements[index])) return;
    final current = _elements[index];
    // 方向键与拖动受同一套约束，否则「拖不出去但按方向键能挪出去」。
    final desired = current.offset + delta;
    setState(() {
      _elements[index] = current.copyWith(
        offset: _applyPlacementConstraints(current, desired),
      );
    });
    _persistAssemblyElements();
  }

  /// A14-2：定时器编辑器。
  ///
  /// 只做 Assembly 用得上的部分：Studio 版还带图层选择与坐标微调，
  /// 那两项在 Assembly 里分别由页面图层与直接拖动承担。
  Future<void> _showTimerEditorDialog(UIElement element) async {
    final module = element.module;
    if (module == null) return;
    final props = Map<String, dynamic>.from(
      _deepCloneValue(module.properties) as Map,
    );

    final nameCtrl = TextEditingController(text: module.name);
    final intervalCtrl = TextEditingController(
      text: ((props['interval'] as num?)?.toDouble() ?? 1.0).toStringAsFixed(1),
    );
    final delayCtrl = TextEditingController(
      text: ((props['initialDelay'] as num?)?.toDouble() ?? 0.0)
          .toStringAsFixed(1),
    );
    final maxTicksCtrl = TextEditingController(
      text: ((props['maxTicks'] as num?)?.toInt() ?? 0).toString(),
    );
    final stepCtrl = TextEditingController(
      text: ((props['stepValue'] as num?)?.toDouble() ?? 1.0).toString(),
    );
    var pulseType = props['pulseType']?.toString() ?? 'increment';
    var loop = props['loop'] != false;
    var autoStart = props['isRunning'] == true;

    Future<void> closeDialog(BuildContext ctx, bool value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    final saved = await showKeyboardSafeDialog<bool>(
      context: context,
      // controller 交给弹窗托管：await 返回时退场动画还要跑 ~150ms，
      // 期间 TextField 仍在重建，自行 dispose 会抛
      // 「A TextEditingController was used after being disposed」。
      disposables: [
        nameCtrl,
        intervalCtrl,
        delayCtrl,
        maxTicksCtrl,
        stepCtrl,
      ],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('定时器'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: intervalCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '触发间隔（秒）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: delayCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '首次延迟（秒）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxTicksCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '最多触发次数（0 = 不限）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: pulseType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '脉冲类型',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'increment', child: Text('递增计数（+步长）')),
                      DropdownMenuItem(
                          value: 'toggle', child: Text('0/1 翻转（开关）')),
                      DropdownMenuItem(
                          value: 'timestamp', child: Text('运行秒戳（时间）')),
                      DropdownMenuItem(
                          value: 'countdown', child: Text('倒计时（-步长）')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => pulseType = v);
                    },
                  ),
                  if (pulseType == 'increment' || pulseType == 'countdown') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: stepCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '每次脉冲的步长',
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('循环触发', style: TextStyle(fontSize: 13)),
                    value: loop,
                    onChanged: (v) => setDialogState(() => loop = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('初始为运行状态',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      '仅当有按钮连了「点击启停」时才生效；'
                      '没有这类连线时定时器一律自动运行',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: autoStart,
                    onChanged: (v) => setDialogState(() => autoStart = v),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '定时器在运行时不显形，只对外发出脉冲，'
                    '摆在 PCB 外也能正常工作。\n'
                    '启停方式由联动决定：接了开关组件则受其控制，'
                    '接了按钮的「点击启停」则由玩家操作，两者都没有就自动运行。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => closeDialog(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => closeDialog(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        // 间隔必须为正：0 会让定时器每帧触发，直接卡死界面。
        final interval =
            (double.tryParse(intervalCtrl.text.trim()) ?? 1.0).clamp(0.1, 3600.0);
        final delay =
            (double.tryParse(delayCtrl.text.trim()) ?? 0.0).clamp(0.0, 3600.0);
        final maxTicks = (int.tryParse(maxTicksCtrl.text.trim()) ?? 0)
            .clamp(0, 1000000);
        props['interval'] = interval.toDouble();
        props['initialDelay'] = delay.toDouble();
        props['maxTicks'] = maxTicks.toInt();
        props['pulseType'] = pulseType;
        props['stepValue'] = double.tryParse(stepCtrl.text.trim()) ?? 1.0;
        props['loop'] = loop;
        props['isRunning'] = autoStart;
        setState(() {
          _elements[index] = _elements[index].copyWith(
            module: module.copyWith(
              name: nameCtrl.text.trim().isEmpty ? module.name : nameCtrl.text.trim(),
              properties: props,
            ),
          );
        });
        _setupEventBusListener();
        _persistAssemblyElements();
      }
    }

  }

  /// A14-2：计算节点编辑器。
  ///
  /// 参数口 A/B/C 可各自启停：比较类运算固定用两个，
  /// `set` 只取第一个，加减乘除则对所有启用项依次运算。
  Future<void> _showMathNodeEditorDialog(UIElement element) async {
    final module = element.module;
    if (module == null) return;
    final props = Map<String, dynamic>.from(
      _deepCloneValue(module.properties) as Map,
    );

    const paramKeys = ['paramA', 'paramB', 'paramC'];
    final nameCtrl = TextEditingController(text: module.name);
    final ctrls = {
      for (final key in paramKeys)
        key: TextEditingController(
          text: ((props[key] as num?)?.toDouble() ?? 0.0).toString(),
        ),
    };
    var operation = props['operation']?.toString() ?? '+';
    final rawActive = props['activeParams'];
    final active = <String>{
      ...(rawActive is List
          ? rawActive.map((e) => e.toString()).where(paramKeys.contains)
          : const <String>['paramA', 'paramB']),
    };
    if (active.isEmpty) active.addAll(['paramA', 'paramB']);

    const comparisons = {'>', '<', '>=', '<=', '=='};

    Future<void> closeDialog(BuildContext ctx, bool value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isComparison = comparisons.contains(operation);
          final isSet = operation == 'set';
          return AlertDialog(
            title: const Text('计算节点'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: operation,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '运算方式',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'set', child: Text('设定值（取第 1 个启用参数）')),
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
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          operation = v;
                          // 比较运算固定两个参数口，切过去时收敛，
                          // 避免留下第三个参数却不参与运算的困惑。
                          if (comparisons.contains(v)) {
                            active
                              ..clear()
                              ..addAll(['paramA', 'paramB']);
                          } else if (v == 'set') {
                            active
                              ..clear()
                              ..add('paramA');
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    for (final key in paramKeys) ...[
                      Row(
                        children: [
                          Checkbox(
                            value: active.contains(key),
                            // 比较与设定值的参数口数量固定，不允许改。
                            onChanged: (isComparison || isSet)
                                ? null
                                : (v) => setDialogState(() {
                                      if (v == true) {
                                        active.add(key);
                                      } else if (active.length > 1) {
                                        active.remove(key);
                                      }
                                    }),
                          ),
                          Expanded(
                            child: TextField(
                              controller: ctrls[key],
                              enabled: active.contains(key),
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: '参数 ${key.substring(5)}',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      '这里填的是默认值。参数口可由联动器动态覆盖，'
                      '计算结果同样通过联动器输出给其他组件。'
                      '计算节点在运行时不显形，摆在 PCB 外也能工作。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => closeDialog(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => closeDialog(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        props['operation'] = operation;
        for (final key in paramKeys) {
          props[key] = double.tryParse(ctrls[key]!.text.trim()) ?? 0.0;
        }
        // 保持 A/B/C 的固定顺序，否则连续运算的结果会随勾选顺序变化。
        props['activeParams'] =
            paramKeys.where(active.contains).toList();
        setState(() {
          _elements[index] = _elements[index].copyWith(
            module: module.copyWith(
              name: nameCtrl.text.trim().isEmpty ? module.name : nameCtrl.text.trim(),
              properties: props,
            ),
          );
        });
        _setupEventBusListener();
        _persistAssemblyElements();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtrl.dispose();
      for (final c in ctrls.values) {
        c.dispose();
      }
    });
  }

  Future<void> _showAtomInstanceEditorDialog(UIElement element) async {
    final module = element.module;
    if (module == null) return;
    // linker / page_router 有各自的专属配置对话框。
    if (const {'linker', 'page_router'}.contains(module.type)) return;
    // A14-2：timer / math_node 是纯逻辑件，参数与显示类组件差别太大，
    // 塞进通用对话框会让两边都难用，各自开一个精简编辑器。
    if (module.type == 'timer') {
      await _showTimerEditorDialog(element);
      return;
    }
    if (module.type == 'math_node') {
      await _showMathNodeEditorDialog(element);
      return;
    }

    final nameController = TextEditingController(text: module.name);
    // 类型专属编辑逻辑全在字段组里（见 atom_field_groups.dart）。
    // 返回 null 表示该类型没有专属字段（如 surface），
    // 只出通用部分：名称 / 语义标记 / 外观 / 数据通道。
    final fieldGroup = AtomFieldGroupRegistry.of(module);

    final existingChannel = _dataChannelOf(module);
    // 打开这个对话框时**是否已经绑定**状态字段。
    //
    // 决定保存后要不要拉取状态字段的值：
    //   · 本来就绑着 → 作者这次是在**改数值**，
    //     必须保留他填的值，之后由离开页面时的
    //     `_buildStatusFieldWriteBack` 反写回状态栏；
    //   · 本来没绑、这次刚绑上 → 拉取一次，
    //     让组件立刻显示该字段的当前值与量程。
    final wasBoundOnOpen =
        DataChannelService.boundStatusFieldId(module) != null;
    final channelLabels = _textLabelCandidates();
    final channelNameController = TextEditingController(
      text: existingChannel?['semanticLabel']?.toString() ?? module.name,
    );
    var channelEnabled = existingChannel != null;
    // 专项页配好但尚未提交的通道。null 表示本次没经过专项页，
    // 保存时沿用 props 里已有的配置。
    Map<String, dynamic>? pendingChannel;
    var channelTouchedByPage = false;
    var channelSource =
        existingChannel?['semanticSource']?.toString() ?? 'manual';
    var channelLabelId = existingChannel?['labelElementId']?.toString() ?? '';
    var channelTargetKind =
        existingChannel?['targetKind']?.toString() ?? 'local_ui_state';
    var channelVisibility =
        existingChannel?['visibility']?.toString() ?? 'ui_only';
    var channelReadPolicy =
        existingChannel?['llmReadPolicy']?.toString() ?? 'none';
    var channelWritePolicy =
        existingChannel?['llmWritePolicy']?.toString() ?? 'none';
    var channelNotifyStyle =
        StatusNotifyStyle.parse(existingChannel?['notifyStyle']).storageValue;
    final channelNotifyTemplateController = TextEditingController(
      text: existingChannel?['notifyTemplate']?.toString() ?? '',
    );
    var channelPromptSection = existingChannel?['promptSection']?.toString() ??
        DataChannelPromptItem.sectionUiData;
    var channelCardTarget =
        CardEntryTarget.fromJson(existingChannel?['cardEntryTarget']) ??
            const CardEntryTarget(
                group: CardEntryTarget.groupIntro, entryId: '', fieldKey: '');
    var isKeyAction = UISemanticRole.isKeyAction(module);
    var sendsMessage = UISemanticRole.sendsMessage(module);
    var targetBranchIndex = module.properties['targetBranchIndex'] as int?;
    // 13 种组件类型的专属状态已全部迁入 atom_field_groups.dart，
    // 这里只剩跨类型共用的语义标记（上面的 isKeyAction / sendsMessage）。

    double readDouble(TextEditingController controller, double fallback) {
      return double.tryParse(controller.text.trim()) ?? fallback;
    }

    Widget numberField(
      TextEditingController controller,
      String label, {
      String? suffix,
    }) {
      return TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );
    }

    // 关闭交给 showKeyboardSafeDialog 统一处理，这里只负责 pop。
    //
    // 旧写法是 unfocus + 16ms 延迟，两个洞（见 HANDOFF 3.5h）：
    // 点遮罩/返回键绕过按钮；16ms 只有一帧而键盘收起要 200~300ms。
    void closeAtomDialog(BuildContext ctx, String value) {
      Navigator.pop(ctx, value);
    }

    // 所有 controller 交给弹窗托管。
    //
    // **不能在 await 之后自己 dispose**：future 在 pop 那一刻完成，
    // 但退场动画还要跑 ~150ms，期间 TextField 仍在重建，
    // 会抛「used after being disposed」并把整棵树塌成 RenderErrorBox
    // （用户实测：改文本后点空白处必现）。见 HANDOFF 3.5h。
    final result = await showKeyboardSafeDialog<String>(
      context: context,
      disposables: [
        nameController,
        channelNameController,
        channelNotifyTemplateController,
        ...?fieldGroup?.disposables,
      ],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final type = module.type;
          final channelPreviewName = _resolveDataChannelName(
            semanticSource: channelSource,
            manualName: channelNameController.text,
            labelElementId: channelLabelId,
            labels: channelLabels,
            fallbackName: module.name,
          );
          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text('编辑实例 · ${module.name}')),
                // 关键职责标签：一种 mode 只有一个职责，
                // 因此这里是「点亮 / 熄灭」而不是从列表里挑。
                if (UISemanticRole.canMark(module.type) &&
                    UISemanticRole.requiresKeyAction(_info.mode))
                  _buildKeyActionTag(
                    mode: _info.mode,
                    active: isKeyAction,
                    onTap: () =>
                        setDialogState(() => isKeyAction = !isKeyAction),
                  ),
                // 发送消息标记：仅 scene 需要（它禁用了原生输入框）。
                if (UISemanticRole.canMarkSend(module.type) &&
                    UISemanticRole.supportsSendMessage(_info.mode)) ...[
                  const SizedBox(width: 6),
                  _buildSendMessageTag(
                    active: sendsMessage,
                    isInput: module.type == 'input',
                    onTap: () =>
                        setDialogState(() => sendsMessage = !sendsMessage),
                  ),
                ],
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '类型：$type · 仅修改当前 Assembly 实例',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '实例名称'),
                    ),
                    if (_info.mode == 'opening' && type == 'button' && isKeyAction && widget.branchNames.length > 1) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF5FB), // 柔和的浅蓝背景
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF4FA3D1).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.link_rounded, size: 16, color: Color(0xFF2980B9)),
                                SizedBox(width: 6),
                                Text(
                                  '选项点击行为配置',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1B4F72),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              value: targetBranchIndex ?? 0,
                              decoration: const InputDecoration(
                                labelText: '点击后通往的开场白',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(widget.branchNames.length, (i) {
                                final label = widget.branchNames[i].isNotEmpty ? widget.branchNames[i] : '开场白 ${i + 1}';
                                return DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(label, style: const TextStyle(fontSize: 12)),
                                );
                              }),
                              onChanged: (val) {
                                setDialogState(() => targetBranchIndex = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    // A14-3：宽 / 高移交「精确几何」。
                    //
                    // 那里还能改 X / Y / 旋转，且带按类型的取值范围与
                    // clamp，比这里两个裸输入框完整。留在这里只是重复，
                    // 还把真正该突出的内容参数挤到了下面。
                    if (!_supportsAtomInstanceEditor(type)) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '该原子专属编辑器将在后续批次开放；'
                        '当前可编辑名称与数据通道，尺寸位置请用左侧「几何」。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          height: 1.35,
                        ),
                      ),
                    ],
                    // 已迁移的类型由字段组自己出表单。
                    if (fieldGroup != null)
                      ...fieldGroup.buildFields(AtomFieldContext(
                        setDialogState: setDialogState,
                        numberField: numberField,
                        readDouble: readDouble,
                        // 手感参数要查全页联动器才知道用不用得上，
                        // 字段组自己看不到，只能从这里传。
                        usesNonTapGesture:
                            type == 'button' &&
                                _buttonUsesNonTapGesture(element.id),
                        sendsMessage: sendsMessage,
                      )),
                    // 圆角 / 透明度 / 颜色 / 材质 / 形状 → 外观专项页。
                    if (_supportsAppearanceEditor(type)) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.palette_outlined, size: 16),
                          label: const Text('编辑外观'),
                          onPressed: () async {
                            final changed = await _openAppearancePage(element);
                            if (changed) setDialogState(() {});
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '数据通道',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111116),
                                  ),
                                ),
                              ),
                              Switch(
                                value: channelEnabled,
                                onChanged: (value) => setDialogState(
                                  () => channelEnabled = value,
                                ),
                              ),
                            ],
                          ),
                          if (!channelEnabled)
                            const Text(
                              '关闭时保存将清除该组件的数据通道配置。'
                              '开启后可进入专项页面配置语义、存放位置与 AI 读写策略。',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777783),
                                height: 1.35,
                              ),
                            )
                          else ...[
                            // A14-3：表单移到独立页面。
                            //
                            // 通道配置有十来项（语义来源 / 存放位置 / 三级
                            // 卡片定位 / 读写策略 / 注入位置…），内嵌在实例
                            // 编辑器里会把对话框撑得又长又乱，
                            // 也是此前「参数编辑器漏做」「三级选择器藏太深」
                            // 的根因。开关留在这里，细节进专项页。
                            Text(
                              '最终语义：'
                              '${channelPreviewName.isEmpty ? '未命名' : channelPreviewName}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00897B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.tune_rounded, size: 16),
                                label: const Text('配置数据通道'),
                                onPressed: () async {
                                  final res =
                                      await _openDataChannelPage(module);
                                  if (!res.saved) return;
                                  // 专项页只返回配置、不落盘。
                                  // 这里把它暂存进对话框状态，
                                  // 由本对话框的保存 / 取消统一裁决。
                                  pendingChannel = res.channel;
                                  channelTouchedByPage = true;
                                  final latest = res.channel;
                                  // 绑定状态字段后，值与量程要立刻反映到
                                  // 字段组的输入框里。
                                  //
                                  // 不刷新的话不只是「显示不同步」——
                                  // 保存时 applyTo 会用打开那一刻的旧值，
                                  // 把刚同步好的量程与数值整个覆盖回去。
                                  _fillControllersFromStatusField(
                                    channel: latest,
                                    moduleType: module.type,
                                    range: fieldGroup?.rangeControllers,
                                    content: fieldGroup?.contentController,
                                    onSwitchValue: (v) {
                                      if (fieldGroup is SwitchFieldGroup) {
                                        fieldGroup.value = v;
                                      }
                                    },
                                  );
                                  // 「双写覆盖」陷阱（HANDOFF 已记两次）：
                                  // 专项页写的是 _elements，而本对话框的
                                  // 这些变量仍是打开那一刻的旧值。
                                  // 不回读的话——
                                  //   1. 上面的「最终语义」预览不会变；
                                  //   2. 本对话框保存时会用旧值重建 payload，
                                  //      把专项页刚配好的内容整个盖掉。
                                  setDialogState(() {
                                    channelEnabled = latest != null;
                                    channelNameController.text =
                                        latest?['semanticLabel']?.toString() ??
                                            module.name;
                                    channelSource = latest?['semanticSource']
                                            ?.toString() ??
                                        'manual';
                                    channelLabelId = latest?['labelElementId']
                                            ?.toString() ??
                                        '';
                                    channelTargetKind =
                                        latest?['targetKind']?.toString() ??
                                            'local_ui_state';
                                    channelVisibility =
                                        latest?['visibility']?.toString() ??
                                            'ui_only';
                                    channelReadPolicy =
                                        latest?['llmReadPolicy']?.toString() ??
                                            'none';
                                    channelWritePolicy =
                                        latest?['llmWritePolicy']?.toString() ??
                                            'none';
                                    channelNotifyStyle =
                                        StatusNotifyStyle.parse(
                                      latest?['notifyStyle'],
                                    ).storageValue;
                                    channelNotifyTemplateController.text =
                                        latest?['notifyTemplate']
                                                ?.toString() ??
                                            '';
                                    channelPromptSection =
                                        latest?['promptSection']?.toString() ??
                                            DataChannelPromptItem
                                                .sectionUiData;
                                    channelCardTarget =
                                        CardEntryTarget.fromJson(
                                              latest?['cardEntryTarget'],
                                            ) ??
                                            const CardEntryTarget(
                                              group: CardEntryTarget.groupIntro,
                                              entryId: '',
                                              fieldKey: '',
                                            );
                                  });
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => closeAtomDialog(ctx, 'cancel'),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => closeAtomDialog(ctx, 'save'),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    // controller 由弹窗统一释放，这里不再手动 dispose。
    if (!mounted) return;

    if (result == 'save') {
      final index = _elements.indexWhere((candidate) => candidate.id == element.id);
      if (index != -1) {
        setState(() {
          final current = _elements[index];
          final currentModule = current.module;
          if (currentModule == null) return;
          final props = Map<String, dynamic>.from(
            _deepCloneValue(currentModule.properties) as Map,
          );
          // 类型专属字段由字段组统一写回；
          // 13 种类型全部迁完后，这里不再有 if(type=='xxx') 长链。
          if (fieldGroup != null) {
            fieldGroup.applyTo(props);
          }
          if (isKeyAction) {
            props[UISemanticRole.propKey] = true;
            if (_info.mode == 'opening' && currentModule.type == 'button') {
              if (targetBranchIndex != null) {
                props['targetBranchIndex'] = targetBranchIndex;
              } else {
                props.remove('targetBranchIndex');
              }
            }
          } else {
            props.remove(UISemanticRole.propKey);
            props.remove('targetBranchIndex');
          }
          if (sendsMessage) {
            props[UISemanticRole.sendKey] = true;
          } else {
            props.remove(UISemanticRole.sendKey);
          }

          final channelName = _resolveDataChannelName(
            semanticSource: channelSource,
            manualName: channelNameController.text,
            labelElementId: channelLabelId,
            labels: channelLabels,
            fallbackName: currentModule.name,
          ).trim();
          // A14-3：通道细节由专项页面直接写入 props，这里只管开关。
          //
          // 不能再从本对话框的状态变量重建 payload——专项页保存后，
          // 这些变量仍是打开实例编辑器那一刻的旧值，
          // 重建会把刚配好的内容覆盖掉。
          if (!channelEnabled) {
            props.remove('dataChannel');
          } else if (channelTouchedByPage) {
            // 本次经过了专项页：以它返回的配置为准。
            // 名称被清空时 channel 为 null，等同于移除通道。
            if (pendingChannel == null) {
              props.remove('dataChannel');
            } else {
              props['dataChannel'] =
                  Map<String, dynamic>.from(pendingChannel!);
            }
          } else if (props['dataChannel'] == null && channelName.isNotEmpty) {
            // 刚打开开关、还没进专项页配置：先落一份最小可用配置，
            // 免得开了开关却什么都没保存。
            props['dataChannel'] = _buildDataChannelPayload(
              name: channelName,
              semanticSource: channelSource,
              labelElementId: channelLabelId,
              sourceComponentId: current.id,
              module: currentModule,
              targetKind: channelTargetKind,
              visibility: channelVisibility,
              llmReadPolicy: channelReadPolicy,
              llmWritePolicy: channelWritePolicy,
              notifyStyle: channelNotifyStyle,
              notifyTemplate: channelNotifyTemplateController.text,
              promptSection: channelPromptSection,
              cardTarget: channelCardTarget,
            );
          }

          // 只碰内容：尺寸归「精确几何」，圆角 / 透明度 / 颜色归「外观」。
          //
          // 关键是**不能**在这里回写 borderRadius / opacity——
          // 外观页保存后，本对话框的 controller 仍是打开那一刻的旧值，
          // 回写会把刚调好的外观覆盖掉（与数据通道同一类陷阱）。
          _elements[index] = current.copyWith(
            module: currentModule.copyWith(
              name: nameController.text.trim().isEmpty
                  ? currentModule.name
                  : nameController.text.trim(),
              properties: props,
            ),
          );
        });
        // 只在「本次刚建立绑定」时拉取状态字段的值。
        //
        // 之前这里无条件同步，导致**已绑定的组件改不动**——
        // 字段组刚把新值写进 props，紧接着就被状态字段的旧值覆盖回去
        // （用户实测：「绑定了字段的组件就修改不动了」）。
        //
        // 已绑定时作者改的是「这个字段的整体数值」，
        // 保留他填的值，离开页面时由 _buildStatusFieldWriteBack 反写。
        if (!wasBoundOnOpen) {
          _syncStatusFieldForElement(_elements[index]);
        }
        _persistAssemblyElements();
      }
    }

  }

  /// 该组件类型有哪些外观字段可调。
  ///
  /// 分工上这些属于「这一个实例在这张卡里长什么样」——
  /// 同一个面板在 A 卡是深蓝、B 卡是暖橙很正常，因此归 Assembly。
  /// 与之相对，indicator 的状态映射规则那种「颜色怎么随数值变」
  /// 是零件自带行为，仍只在 Studio 编辑。
  /// 该 button 是否被某条连线用双击 / 长按方式触发。
  ///
  /// 只看画布上的 linker 元素，不依赖运行端快照——
  /// 编辑期 LinkerService 里未必装着当前这张卡的连线。
  bool _buttonUsesNonTapGesture(String buttonId) {
    for (final element in _elements) {
      final module = element.module;
      if (module == null || module.type != 'linker') continue;
      final data = _linkerDataOf(module);
      if (data['sourceModuleId']?.toString() != buttonId) continue;
      final port = data['sourcePort']?.toString() ?? '';
      if (port == 'double_tap' || port == 'long_press') return true;
    }
    return false;
  }

  bool _supportsAppearanceEditor(String type) => const {
        'surface',
        'base_box',
        'text',
        // button 不在此列：它运行期是纯热区、完全不显形，
        // 给它调颜色圆角只会让作者白忙一场（视觉反馈请连线到 surface）。
        'progress',
        'slider',
        'input',
        'switch',
        'select',
        'indicator',
        'line',
        'image',
        'message_flow',
      }.contains(type);

  /// 外观专项页。
  ///
  /// 统一一页而非每类组件一页：字段按类型显示，
  /// 共性部分（主色 / 圆角 / 透明度）所有组件通用，
  /// 拆成十几个页面反而让作者记不住入口在哪。
  Future<bool> _openAppearancePage(UIElement element) async {
    final module = element.module;
    if (module == null) return false;
    final type = module.type;

    final props = Map<String, dynamic>.from(
      _deepCloneValue(module.properties) as Map,
    );
    var color = module.color;
    var material = module.material;
    var shape = module.shape;
    var radius = module.borderRadius;
    var opacity = module.opacity;
    // A12：触发动画配置。null 表示不播放。
    var animation = ElementAnimation.readFrom(props);

    int? readColor(String key) => (props[key] as num?)?.toInt();

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            Widget colorRow(
              String label,
              Color current,
              ValueChanged<Color> onPick, {
              String? hint,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(hint,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF777783))),
                      ),
                    const SizedBox(height: 6),
                    _buildColorPalette(current, onPick),
                  ],
                ),
              );
            }

            Widget slider(
              String label,
              double value,
              double min,
              double max,
              ValueChanged<double> onChanged, {
              String? suffix,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(label,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        value: value.clamp(min, max),
                        min: min,
                        max: max,
                        onChanged: onChanged,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        suffix ?? value.toStringAsFixed(
                            max <= 1.0 ? 2 : 0),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget dropdown<T>(
              String label,
              T value,
              List<DropdownMenuItem<T>> items,
              ValueChanged<T> onChanged,
            ) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<T>(
                  initialValue: value,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: label, isDense: true),
                  items: items,
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: Text('外观 · ${module.name}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(pageContext, true),
                    child: const Text('保存'),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  colorRow('主色', color, (c) => setPageState(() => color = c)),

                  // 材质与形状：面类与装饰类才有意义，
                  // 文本 / 输入框这些自身没有底板可言。
                  if (const {'surface', 'base_box'}.contains(type)) ...[
                    dropdown<UIModuleMaterial>(
                      '材质',
                      material,
                      const [
                        DropdownMenuItem(
                            value: UIModuleMaterial.glass, child: Text('毛玻璃')),
                        DropdownMenuItem(
                            value: UIModuleMaterial.solid, child: Text('纯色')),
                        DropdownMenuItem(
                            value: UIModuleMaterial.gradient, child: Text('渐变')),
                        DropdownMenuItem(
                            value: UIModuleMaterial.outline, child: Text('描边')),
                      ],
                      (v) => setPageState(() => material = v),
                    ),
                    dropdown<UIModuleShape>(
                      '形状',
                      shape,
                      const [
                        DropdownMenuItem(
                            value: UIModuleShape.rectangle, child: Text('矩形')),
                        DropdownMenuItem(
                            value: UIModuleShape.rounded, child: Text('圆角矩形')),
                        DropdownMenuItem(
                            value: UIModuleShape.capsule, child: Text('胶囊')),
                        DropdownMenuItem(
                            value: UIModuleShape.circle, child: Text('圆形')),
                        DropdownMenuItem(
                            value: UIModuleShape.heart, child: Text('心形')),
                        DropdownMenuItem(
                            value: UIModuleShape.star5, child: Text('五角星')),
                        DropdownMenuItem(
                            value: UIModuleShape.star4, child: Text('四角星')),
                      ],
                      (v) => setPageState(() => shape = v),
                    ),
                  ],

                  if (type == 'progress') ...[
                    dropdown<String>(
                      '进度条形状',
                      props['progressShape']?.toString() ?? 'rounded',
                      const [
                        DropdownMenuItem(value: 'rounded', child: Text('圆角条')),
                        DropdownMenuItem(value: 'rectangle', child: Text('直角条')),
                        DropdownMenuItem(value: 'capsule', child: Text('胶囊条')),
                        DropdownMenuItem(value: 'ring', child: Text('环形')),
                        DropdownMenuItem(value: 'heart', child: Text('心形')),
                      ],
                      (v) => setPageState(() => props['progressShape'] = v),
                    ),
                    colorRow(
                      '轨道底色',
                      Color(readColor('trackColor') ?? 0xFFEEEEEE),
                      (c) => setPageState(
                          () => props['trackColor'] = c.toARGB32()),
                    ),
                  ],

                  if (type == 'slider')
                    dropdown<String>(
                      '滑块手柄形状',
                      props['knobShape']?.toString() ?? 'circle',
                      const [
                        DropdownMenuItem(value: 'circle', child: Text('圆形')),
                        DropdownMenuItem(
                            value: 'rectangle', child: Text('方形')),
                      ],
                      (v) => setPageState(() => props['knobShape'] = v),
                    ),

                  if (const {'input', 'select'}.contains(type)) ...[
                    dropdown<String>(
                      '外框样式',
                      props['visualMode']?.toString() ?? 'filled',
                      const [
                        DropdownMenuItem(value: 'filled', child: Text('填充')),
                        DropdownMenuItem(value: 'outline', child: Text('描边')),
                        DropdownMenuItem(
                            value: 'transparent', child: Text('透明')),
                      ],
                      (v) => setPageState(() => props['visualMode'] = v),
                    ),
                    colorRow(
                      '占位文字颜色',
                      Color(readColor('placeholderColor') ?? 0xFF888896),
                      (c) => setPageState(
                          () => props['placeholderColor'] = c.toARGB32()),
                    ),
                    if (type == 'input')
                      colorRow(
                        '输入文字颜色',
                        Color(readColor('inputTextColor') ?? 0xFF111116),
                        (c) => setPageState(
                            () => props['inputTextColor'] = c.toARGB32()),
                      ),
                  ],

                  if (type == 'message_flow') ...[
                    colorRow(
                      '玩家气泡底色',
                      Color(readColor('userBubbleColor') ?? 0xFFDCF8C6),
                      (c) => setPageState(
                          () => props['userBubbleColor'] = c.toARGB32()),
                    ),
                    colorRow(
                      '角色气泡底色',
                      Color(readColor('assistantBubbleColor') ?? 0xFFF1F1F4),
                      (c) => setPageState(
                          () => props['assistantBubbleColor'] = c.toARGB32()),
                    ),
                    slider(
                      '气泡圆角',
                      (props['bubbleRadius'] as num?)?.toDouble() ?? 12.0,
                      0,
                      32,
                      (v) => setPageState(() => props['bubbleRadius'] = v),
                    ),
                  ],

                  if (type == 'indicator')
                    colorRow(
                      '兜底底色',
                      Color(readColor('defaultColor') ?? 0xFF9E9E9E),
                      (c) => setPageState(
                          () => props['defaultColor'] = c.toARGB32()),
                      hint: '状态规则未命中时显示这个颜色。'
                          '规则本身请在创作工作室编辑。',
                    ),

                  // 圆角与透明度对绝大多数组件都有意义，放在最后作为通用项。
                  if (!const {'line', 'indicator'}.contains(type))
                    slider('圆角', radius, 0, 48,
                        (v) => setPageState(() => radius = v)),
                  slider('透明度', opacity, 0.1, 1.0,
                      (v) => setPageState(() => opacity = v)),

                  // A12：触发动画。
                  //
                  // 参数归元件而非连线——动画是「这个元件在这张卡里
                  // 怎么表现」，属于 Assembly 的元件配置；
                  // 连线只负责「什么时候触发」。
                  // 同一元件被多条连线驱动时也只需在这里配一次。
                  const SizedBox(height: 6),
                  const Divider(height: 20),
                  const Text('触发动画',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      '被联动器触发时播放（方案选「事件触发动画」）。'
                      '在这里配一次，所有指向它的连线都用这套参数。',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF777783), height: 1.35),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: animation?.type.storageKey ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: '动画类型', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('不播放')),
                      for (final t in ElementAnimationType.values)
                        DropdownMenuItem(
                          value: t.storageKey,
                          child: Text(t.label),
                        ),
                    ],
                    onChanged: (next) {
                      setPageState(() {
                        if (next == null || next.isEmpty) {
                          animation = null;
                          return;
                        }
                        final picked =
                            ElementAnimationTypeX.fromStorage(next)!;
                        // 换类型时套用该类型的建议时长：
                        // 按压 150ms 与粒子 700ms 的合适值差很多，
                        // 沿用上一个类型的时长往往不对。
                        animation = (animation ??
                                ElementAnimation(type: picked))
                            .copyWith(
                          type: picked,
                          durationMs: picked.defaultDurationMs,
                        );
                      });
                    },
                  ),
                  if (animation != null) ...[
                    const SizedBox(height: 12),
                    slider(
                      '时长',
                      animation!.durationMs.toDouble(),
                      80,
                      1500,
                      (v) => setPageState(() => animation =
                          animation!.copyWith(durationMs: v.round())),
                      suffix: 'ms',
                    ),
                    slider(
                      '幅度',
                      animation!.intensity,
                      0.1,
                      1.0,
                      (v) => setPageState(
                          () => animation = animation!.copyWith(intensity: v)),
                    ),
                    // 值驱动组件不接线也会在值变化时自动播——
                    // 这是数值跳动的自然语义，明确告知作者，
                    // 免得他再去接一条多余的线。
                    if (const {'progress', 'text', 'slider', 'select',
                            'input'}
                        .contains(type))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '这个组件的数值发生变化时会自动播放，无需接线。'
                          '若还想让按钮或定时器额外触发，再另接连线即可。',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2E7D32),
                            height: 1.35,
                          ),
                        ),
                      ),
                    DropdownButtonFormField<ElementAnimationCurve>(
                      initialValue: animation!.curve,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: '缓动曲线', isDense: true),
                      items: [
                        for (final c in ElementAnimationCurve.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (next) {
                        if (next == null) return;
                        setPageState(
                            () => animation = animation!.copyWith(curve: next));
                      },
                    ),
                    // 只有会用到附加色的动画才给取色器，
                    // 按压/跳动不吃颜色，给了反而让人以为能改。
                    if (const {
                      ElementAnimationType.flash,
                      ElementAnimationType.glowPulse,
                      ElementAnimationType.particleBurst,
                    }.contains(animation!.type)) ...[
                      const SizedBox(height: 12),
                      colorRow(
                        '动画颜色',
                        Color(animation!.colorValue ?? color.toARGB32()),
                        (c) => setPageState(() =>
                            animation = animation!.copyWith(
                                colorValue: c.toARGB32())),
                        hint: '留用主色时可直接选与组件同色。',
                      ),
                    ],
                  ],

                  const SizedBox(height: 8),
                  const Text(
                    '这里改的是「这一个实例在本张卡里长什么样」。'
                    '组件自身的行为规则（如状态指示灯的多态映射）'
                    '仍在创作工作室里编辑。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    if (saved != true || !mounted) return false;

    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return false;
    final current = _elements[index];
    final currentModule = current.module;
    if (currentModule == null) return false;

    // A12：动画配置写回统一通道。
    // writeConfig 会保留已有时间戳——保存外观不该顺手触发一次动画。
    ElementAnimation.writeConfig(props, animation);

    setState(() {
      _elements[index] = current.copyWith(
        module: currentModule.copyWith(
          color: color,
          material: material,
          shape: shape,
          borderRadius: radius,
          opacity: opacity,
          properties: props,
        ),
      );
    });
    _persistAssemblyElements();
    return true;
  }
}
