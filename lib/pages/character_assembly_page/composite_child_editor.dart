part of '../character_assembly_page.dart';

/// 复合件**子件**的整页编辑器。
///
/// ## 这个文件解决什么
///
/// 改版前，复合件实例编辑器只能做一件事：给暴露项建一个「覆写槽位」，
/// 然后改 text / progress / switch 三种类型的**一个值**。
/// 用户的原话是「覆写本身就是一个改名字的功能」——确实如此。
///
/// 而画布上的独立原子，早就能改字段组、外观、动画、数据通道四大块。
/// 同一个 text 组件，放在画布上能配十几项，塞进复合件里就只剩一个输入框。
///
/// 这里把这道落差抹平：**复合件里的子件与外部原子编辑体验一致**。
///
/// | 区块 | 来源 | 说明 |
/// |---|---|---|
/// | 类型专属字段 | [AtomFieldGroup] | 与外部原子**复用同一批字段组**，13 种类型全支持 |
/// | 外观 + 动画 | 本文件 | 主色 / 材质 / 形状 / 圆角 / 透明度 / 触发动画 |
/// | 数据通道 | `_showExposedDataChannelEditor` | LLM 数据交换与状态栏联动 |
/// | 实例改名 | 本文件 | 与原子编辑器一样，直接在顶部改 |
///
/// ## 为什么字段组能直接复用
///
/// [AtomFieldGroup.applyTo] 的签名是 `void applyTo(Map<String, dynamic> props)`
/// ——它只认一张属性表，不关心这张表最终写进 `module.properties`
/// 还是 `PropertyOverride.overrides`。这正是上一轮把 13 种类型
/// 收敛成字段组的红利：这个编辑器几乎不用写类型分支。
///
/// ## 覆写语义：只存「改过的」
///
/// 字段组的 `applyTo` 会把**全部**字段都写进表里（它不知道哪些没动过）。
/// 若原样存进 overrides，等于把模板的默认值固化成实例覆写——
/// 之后模板更新了，这个实例也跟不上。
///
/// 所以保存时做一次**差异比对**（[_diffAgainstTemplate]）：
/// 只有与模板取值不同的键才留下。作者把值改回默认，覆写自动消失。
///
/// ## 外观键为什么要特殊处理
///
/// color / material / shape / borderRadius / opacity 是 [UIModule] 的
/// **独立字段**，不在 properties 里。直接往 overrides 塞 `color`
/// 不会报错、也确实存下了，但渲染时读的是 `module.color`，
/// **改了等于没改**（HANDOFF 3.5j 静默失效）。
/// 统一走 [AppearanceOverrideKeys] 的带前缀键，
/// 由编辑器端与运行时端两处 patch 逻辑共同识别。

/// ## 为什么是独立 mixin
///
/// Dart 的 `part` 文件不能续写别的 part 里打开的类体，
/// 每个 part 必须自成完整的顶层声明。因此本文件单独一个 mixin，
/// 由 `_CharacterAssemblyPageState` 一并 `with` 进去。
///
/// ## mixin 顺序：本文件必须排在 `_AssemblyCompositeLogic` **之前**
///
/// 两者互相调用——列表页要打开本编辑器，本编辑器又要调用
/// `_upsertPropertyOverride` / `_showExposedDataChannelEditor`。
/// 若两个 mixin 的 `on` 互相声明对方就成了循环依赖，Dart 不允许。
///
/// 打破循环的办法：本文件**只** `on _AssemblyLogic`（那些属性覆写的
/// 增删方法一并搬到了这里，见文件末尾），由
/// `_AssemblyCompositeLogic` 单向依赖本文件。
mixin _CompositeChildEditor on State<CharacterAssemblyPage>, _AssemblyLogic {
  /// 打开某个复合件子件的整页编辑器。
  ///
  /// 返回是否发生了改动（调用方据此决定要不要刷新列表）。
  Future<bool> _openCompositeChildEditor({
    required UIElement compositeElement,
    required UIElement child,
    required PropertyOverride propertyOverride,
  }) async {
    final module = child.module;
    if (module == null) return false;

    // ===== 起始状态：模板值叠加已有覆写 =====
    //
    // 编辑器里显示的必须是「作者现在实际看到的样子」，
    // 也就是模板默认值被已有覆写盖过之后的结果。
    // 只读模板会丢掉上次的编辑；只读覆写则大部分字段是空的。
    final templateProps = Map<String, dynamic>.from(
      _deepCloneValue(module.properties) as Map,
    );
    final existing = Map<String, dynamic>.from(
      _deepCloneValue(propertyOverride.overrides) as Map,
    );
    // dataChannel 由专项编辑器独立管理，不参与字段/外观的差异比对。
    final existingChannel = existing['dataChannel'];
    existing.remove('dataChannel');

    final mergedProps = Map<String, dynamic>.from(templateProps)
      ..addAll(AppearanceOverrideKeys.stripFrom(existing))
      ..remove(kCompositeChildNameOverrideKey);

    // 字段组吃的是一个 UIModule，这里拿合并后的属性伪造一个，
    // 好让它的构造函数读到「当前生效值」而不是模板原始值。
    final effectiveModule = AppearanceOverrideKeys.applyTo(
      module.copyWith(properties: mergedProps),
      existing,
    );
    final fieldGroup = AtomFieldGroupRegistry.of(effectiveModule);

    final nameController = TextEditingController(
      text: existing[kCompositeChildNameOverrideKey]?.toString() ?? module.name,
    );

    // 外观初值同样取「生效值」。
    var color = effectiveModule.color;
    var material = effectiveModule.material;
    var shape = effectiveModule.shape;
    var radius = effectiveModule.borderRadius;
    var opacity = effectiveModule.opacity;
    var animation = ElementAnimation.readFrom(mergedProps);

    // 数据通道在本页里改，退出时随其它改动一起提交。
    var pendingChannel = existingChannel;
    var channelTouched = false;

    final type = module.type;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            Widget sectionTitle(String text, {String? hint}) {
              return Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111116),
                      ),
                    ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          hint,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF777783),
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }

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
                    const SizedBox(height: 8),
                    _buildColorPalette(current, onPick),
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
                  onChanged: (next) {
                    if (next == null) return;
                    onChanged(next);
                  },
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label：${value.toStringAsFixed(suffix == 'ms' ? 0 : 2)}'
                      '${suffix ?? ''}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    Slider(
                      value: value.clamp(min, max),
                      min: min,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: Text('子件 · ${nameController.text.trim().isEmpty ? module.name : nameController.text.trim()}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(pageContext, true),
                    child: const Text('保存'),
                  ),
                ],
              ),
              // 不用 KeyboardAvoidingStage：那个组件是给**固定尺寸的**
              // 全屏运行时 UI 做整体平移用的（需要 stageHeight/keyboardInset）。
              // 本页是可滚动 ListView，Scaffold 默认的
              // resizeToAvoidBottomInset 会把它顶上去，行为与外观页一致。
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // ===== 归属提示 =====
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD1C4E9)),
                    ),
                    child: Text(
                      '所属复合件：'
                      '${compositeElement.composite?.name ?? compositeElement.id}\n'
                      '这里的改动**只作用于当前这一个实例**，不会回写资产库模板。',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A148C),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== 名称 =====
                  sectionTitle('名称', hint: '留空则回落模板名「${module.name}」。'),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '实例内显示名',
                      hintText: module.name,
                      isDense: true,
                    ),
                    onChanged: (_) => setPageState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '类型：$type · 子件 ID：${child.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                    ),
                  ),
                  const Divider(height: 28),

                  // ===== 类型专属字段（复用外部原子的字段组）=====
                  if (fieldGroup != null) ...[
                    sectionTitle(
                      '组件设置',
                      hint: '与画布上同类型组件的编辑项完全一致。',
                    ),
                    ...fieldGroup.buildFields(AtomFieldContext(
                      setDialogState: setPageState,
                      numberField: (controller, label, {suffix}) => TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: label, suffixText: suffix),
                      ),
                      readDouble: (controller, fallback) =>
                          double.tryParse(controller.text.trim()) ?? fallback,
                      // 复合件内部的 button 连线在模板里，
                      // 这里拿不到画布级联动器，一律给出手感参数。
                      usesNonTapGesture: type == 'button',
                      sendsMessage: UISemanticRole.sendsMessage(module),
                    )),
                    const Divider(height: 28),
                  ],

                  // ===== 外观 =====
                  sectionTitle('外观'),
                  colorRow('主色', color, (c) => setPageState(() => color = c)),
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
                            value: UIModuleMaterial.gradient,
                            child: Text('渐变')),
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
                  slider('圆角', radius, 0, 40,
                      (v) => setPageState(() => radius = v)),
                  slider('不透明度', opacity, 0.1, 1.0,
                      (v) => setPageState(() => opacity = v)),
                  const Divider(height: 28),

                  // ===== 动画 =====
                  sectionTitle(
                    '触发动画',
                    hint: '复合件内部的子件同样支持动画，'
                        '与画布上的独立组件用的是同一套引擎。',
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
                        // 换类型时套用该类型的建议时长，
                        // 沿用上一个类型的往往不合适。
                        animation =
                            (animation ?? ElementAnimation(type: picked))
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
                      (v) => setPageState(() =>
                          animation = animation!.copyWith(intensity: v)),
                    ),
                    if (const {'progress', 'text', 'slider', 'select', 'input'}
                        .contains(type))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '这个组件的数值发生变化时会自动播放，无需接线。',
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
                    if (const {
                      ElementAnimationType.flash,
                      ElementAnimationType.glowPulse,
                      ElementAnimationType.particleBurst,
                    }.contains(animation!.type)) ...[
                      const SizedBox(height: 12),
                      colorRow(
                        '动画颜色',
                        Color(animation!.colorValue ?? color.toARGB32()),
                        (c) => setPageState(() => animation =
                            animation!.copyWith(colorValue: c.toARGB32())),
                      ),
                    ],
                  ],
                  const Divider(height: 28),

                  // ===== 数据通道 =====
                  sectionTitle(
                    '数据通道',
                    hint: 'LLM 数据交换与状态栏联动。'
                        '与画布上的组件用同一套配置，'
                        '绑定后这个子件就能被 AI 读写、或与状态栏字段同步。',
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: pendingChannel != null
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFF6F6F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: pendingChannel != null
                            ? const Color(0xFFA5D6A7)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            pendingChannel is Map
                                ? '已配置：'
                                    '${(pendingChannel as Map)['semanticLabel'] ?? module.name}'
                                : '未配置数据通道',
                            style: TextStyle(
                              fontSize: 11,
                              color: pendingChannel != null
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFF777783),
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('配置'),
                          onPressed: () async {
                            // 专项编辑器直接写 PropertyOverride，
                            // 返回后必须重新回读（HANDOFF 3.5b 双写覆盖）。
                            await _showExposedDataChannelEditor(
                              compositeElement: compositeElement,
                              child: child,
                              propertyOverride: propertyOverride,
                            );
                            if (!pageContext.mounted) return;
                            final latest = _activePropertyOverrides
                                .where((o) => o.componentId == child.id)
                                .toList();
                            setPageState(() {
                              pendingChannel = latest.isEmpty
                                  ? null
                                  : latest.first.overrides['dataChannel'];
                              channelTouched = true;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '提示：把某一项改回模板默认值，该项的覆写会自动移除，'
                    '之后模板更新时这个实例会跟着变。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.45),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    // 控制器统一在这里释放。
    //
    // 与弹窗不同，整页路由 pop 之后不会再重建这棵树，
    // 因此 await 返回时释放是安全的（弹窗那条路必须交给
    // showKeyboardSafeDialog，见 HANDOFF 3.5h）。
    void releaseControllers() {
      nameController.dispose();
      for (final c in fieldGroup?.disposables ?? const <ChangeNotifier>[]) {
        c.dispose();
      }
    }

    if (saved != true || !mounted) {
      releaseControllers();
      // 数据通道是即时落盘的，即便这里取消也已经生效，
      // 需要让调用方刷新列表。
      return channelTouched;
    }

    // ===== 收集编辑结果 =====
    final edited = Map<String, dynamic>.from(templateProps);
    fieldGroup?.applyTo(edited);
    ElementAnimation.writeConfig(edited, animation);

    final result = _diffAgainstTemplate(
      template: templateProps,
      edited: edited,
    );

    // 外观差异单独比对，写成带前缀的键。
    if (color.toARGB32() != module.color.toARGB32()) {
      result[AppearanceOverrideKeys.color] = color.toARGB32();
    }
    if (material != module.material) {
      result[AppearanceOverrideKeys.material] = material.name;
    }
    if (shape != module.shape) {
      result[AppearanceOverrideKeys.shape] = shape.name;
    }
    if ((radius - module.borderRadius).abs() > 0.01) {
      result[AppearanceOverrideKeys.borderRadius] = radius;
    }
    if ((opacity - module.opacity).abs() > 0.01) {
      result[AppearanceOverrideKeys.opacity] = opacity;
    }

    // 名称：留空视为不覆写。
    final wantedName = nameController.text.trim();
    if (wantedName.isNotEmpty && wantedName != module.name) {
      result[kCompositeChildNameOverrideKey] = wantedName;
    }

    releaseControllers();

    if (!mounted) return channelTouched;

    setState(() {
      // dataChannel 由专项编辑器维护，这里原样保留。
      final latest = _activePropertyOverrides
          .where((o) => o.componentId == child.id)
          .toList();
      final keptChannel =
          latest.isNotEmpty ? latest.first.overrides['dataChannel'] : null;
      if (keptChannel != null) {
        result['dataChannel'] = keptChannel;
      }

      if (result.isEmpty) {
        // 全部改回默认 → 槽位没有存在意义，直接移除，
        // 让这个子件重新完全跟随模板。
        _removePropertyOverride(child.id);
      } else {
        _upsertPropertyOverride(
          propertyOverride.copyWith(overrides: result),
        );
      }
      _persistAssemblyElements();
    });
    return true;
  }

  /// 比对编辑结果与模板值，只留下真正改动过的键。
  ///
  /// 为什么必须做这一步：[AtomFieldGroup.applyTo] 会把**所有**字段
  /// 都写进表里（它无从知道作者动过哪些）。原样存下等于把模板当时的
  /// 默认值固化成实例覆写，日后模板更新，这个实例就跟不上了。
  Map<String, dynamic> _diffAgainstTemplate({
    required Map<String, dynamic> template,
    required Map<String, dynamic> edited,
  }) {
    final result = <String, dynamic>{};
    for (final entry in edited.entries) {
      final before = template[entry.key];
      if (!_deepEquals(before, entry.value)) {
        result[entry.key] = entry.value;
      }
    }
    // 模板里有、编辑后没有的键（字段组的 props.remove(...) 路径），
    // 需要显式写 null 才能盖住模板值，否则 addAll 时模板值会重新冒出来。
    for (final key in template.keys) {
      if (!edited.containsKey(key) && !key.startsWith('__')) {
        result[key] = null;
      }
    }
    return result;
  }

  /// 深比较，用于差异判定。
  ///
  /// 不能直接用 `==`：properties 里常有嵌套 Map / List
  /// （如 select 的 options、indicator 的 statusRules），
  /// 引用不同就会被判成「改过了」，导致覆写表塞满没动过的字段。
  bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    // 数值统一按 double 比：存档里 12 与 12.0 是同一个值。
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }

  // ===== 覆写槽位的增删查 =====
  //
  // 放在这里而不是 logic_composite.dart：本编辑器与那边的列表页
  // 都要用，而 mixin 不能互相 on（循环依赖）。放在依赖链下游的
  // 本文件里，两边都能拿到。

  PropertyOverride _ensurePropertyOverride({
    required String componentId,
    required String sourceElementId,
    String? sourceCompositeId,
  }) {
    final existingIndex = _activePropertyOverrides.indexWhere(
      (override) => override.componentId == componentId,
    );
    if (existingIndex != -1) {
      return _activePropertyOverrides[existingIndex];
    }
    final created = PropertyOverride(
      componentId: componentId,
      sourceElementId: sourceElementId,
      sourceCompositeId: sourceCompositeId,
    );
    _activePropertyOverrides.add(created);
    return created;
  }

  void _upsertPropertyOverride(PropertyOverride override) {
    final index = _activePropertyOverrides.indexWhere(
      (candidate) => candidate.componentId == override.componentId,
    );
    if (index == -1) {
      _activePropertyOverrides.add(_clonePropertyOverride(override));
    } else {
      _activePropertyOverrides[index] = _clonePropertyOverride(override);
    }
    _persistAssemblyElements();
  }

  void _removePropertyOverride(String componentId) {
    _activePropertyOverrides
        .removeWhere((override) => override.componentId == componentId);
    _persistAssemblyElements();
  }

  /// 复合组件暴露项的数据通道编辑器。
  ///
  /// 通道配置写入 `PropertyOverride.overrides['dataChannel']`，
  /// 属于当前 Assembly 实例覆写的一部分，不回写资产库模板。
  Future<void> _showExposedDataChannelEditor({
    required UIElement compositeElement,
    required UIElement child,
    required PropertyOverride propertyOverride,
  }) async {
    final module = child.module;
    if (module == null) return;

    final raw = propertyOverride.overrides['dataChannel'];
    final existing = raw is Map ? Map<String, dynamic>.from(raw) : null;
    // 与原子实例编辑器同理：本来就绑着状态字段时，
    // 保存后**不能**再拉取字段值，否则会把作者刚改的覆盖回去。
    final wasBoundOnOpen =
        DataChannelService.statusFieldIdOfChannel(existing) != null;
    final labels = _textLabelCandidates();
    final nameController = TextEditingController(
      text: existing?['semanticLabel']?.toString() ?? module.name,
    );
    var enabled = existing != null;
    var semanticSource = existing?['semanticSource']?.toString() ?? 'manual';
    var labelElementId = existing?['labelElementId']?.toString() ?? '';
    var targetKind = existing?['targetKind']?.toString() ?? 'local_ui_state';
    var visibility = existing?['visibility']?.toString() ?? 'ui_only';
    var llmReadPolicy = existing?['llmReadPolicy']?.toString() ?? 'none';
    var llmWritePolicy = existing?['llmWritePolicy']?.toString() ?? 'none';
    // notifyStyle 取代旧的 llmUpdateApplyPolicy。
    // 旧值里的 confirm 是「否决权」（勾掉就不写），语义已废除；
    // never 由「允许 AI 更新 = 不允许」承担。这里一律回落 silent。
    var notifyStyle =
        StatusNotifyStyle.parse(existing?['notifyStyle']).storageValue;
    final notifyTemplateController = TextEditingController(
      text: existing?['notifyTemplate']?.toString() ?? '',
    );
    var promptSection = existing?['promptSection']?.toString() ??
        DataChannelPromptItem.sectionUiData;
    var cardTarget = CardEntryTarget.fromJson(existing?['cardEntryTarget']) ??
        const CardEntryTarget(
            group: CardEntryTarget.groupIntro, entryId: '', fieldKey: '');
    final cardCustomTitleController =
        TextEditingController(text: cardTarget.isCustomEntry ? cardTarget.fieldKey : '');

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
        nameController,
        cardCustomTitleController,
        notifyTemplateController,
      ],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('数据通道 · ${module.name}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '所属复合实例：${compositeElement.composite?.name ?? compositeElement.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '启用数据通道',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111116),
                          ),
                        ),
                      ),
                      Switch(
                        value: enabled,
                        onChanged: (value) =>
                            setDialogState(() => enabled = value),
                      ),
                    ],
                  ),
                  if (!enabled)
                    const Text(
                      '关闭并应用后，将清除该暴露项的数据通道配置。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    )
                  else ...[
                    const Text(
                      '当前仅保存配置，不写入 SessionState、不注入 Prompt。',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFF777783)),
                    ),
                    const SizedBox(height: 10),
                    ..._buildDataChannelFormFields(
                      labels: labels,
                      fallbackName: module.name,
                      nameController: nameController,
                      semanticSource: semanticSource,
                      labelElementId: labelElementId,
                      targetKind: targetKind,
                      llmReadPolicy: llmReadPolicy,
                      llmWritePolicy: llmWritePolicy,
                      notifyStyle: notifyStyle,
                      notifyTemplateController: notifyTemplateController,
                      promptSection: promptSection,
                      cardTarget: cardTarget,
                      cardCustomTitleController: cardCustomTitleController,
                      onCardTarget: (value) =>
                          setDialogState(() => cardTarget = value),
                      onSemanticSource: (value) =>
                          setDialogState(() => semanticSource = value),
                      onLabelElementId: (value) =>
                          setDialogState(() => labelElementId = value),
                      onTargetKind: (value) =>
                          setDialogState(() => targetKind = value),
                      onReadPolicy: (value) =>
                          setDialogState(() => llmReadPolicy = value),
                      onWritePolicy: (value) =>
                          setDialogState(() => llmWritePolicy = value),
                      onNotifyStyle: (value) =>
                          setDialogState(() => notifyStyle = value),
                      onPromptSection: (value) =>
                          setDialogState(() => promptSection = value),
                      onNormalizeLabelId: (value) => labelElementId = value,
                      onNameChanged: () => setDialogState(() {}),
                    ),
                  ],
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
      ),
    );

    if (saved == true && mounted) {
      final name = _resolveDataChannelName(
        semanticSource: semanticSource,
        manualName: nameController.text,
        labelElementId: labelElementId,
        labels: labels,
        fallbackName: module.name,
      ).trim();
      final nextOverrides =
          Map<String, dynamic>.from(propertyOverride.overrides);
      if (!enabled || name.isEmpty) {
        nextOverrides.remove('dataChannel');
      } else {
        nextOverrides['dataChannel'] = _buildDataChannelPayload(
          name: name,
          semanticSource: semanticSource,
          labelElementId: labelElementId,
          sourceComponentId: child.id,
          module: module,
          targetKind: targetKind,
          visibility: visibility,
          llmReadPolicy: llmReadPolicy,
          llmWritePolicy: llmWritePolicy,
          notifyStyle: notifyStyle,
          notifyTemplate: notifyTemplateController.text,
          promptSection: promptSection,
          cardTarget: cardTarget,
        );
      }
      final nextOverride =
          propertyOverride.copyWith(overrides: nextOverrides);
      setState(() {
        _upsertPropertyOverride(nextOverride);
      });
      // 只在**刚建立**绑定时同步值与量程并登记基线。
      // 已绑定时作者改的是字段本身的数值，保留他填的。
      if (!wasBoundOnOpen) {
        _syncStatusFieldForOverride(nextOverride);
      }
      _persistAssemblyElements();
    }
  }
}
