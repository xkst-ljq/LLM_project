part of '../character_assembly_page.dart';

/// 复合组件（composite）在 Assembly 编辑器里的全部逻辑。
///
/// ## 为什么单独成文件
///
/// 这些成员原本和画布拖拽、页面路由、联动器、数据通道一起挤在
/// `logic.dart` 里。那个文件不是「有一个巨型方法」，而是
/// **一个 mixin 装了七八件不相干的事**——304 个成员 7896 行，
/// 找一个复合件相关的函数要在整份文件里 grep。
///
/// 这里是按职责切分的第一刀。**纯搬运**：没有改动任何一行逻辑、
/// 没有改任何签名。仍是 `mixin _AssemblyLogic` 的一部分，
/// 通过 `part` 拼回去，私有成员照常互相可见。
///
/// ## 装了什么
///
/// | 区块 | 成员 |
/// |---|---|
/// | 覆写摘要文案 | `_propertyOverrideStatusText` / `_bindingSummary` 等 |
/// | 覆写项主列表 | `_showCompositeOverrideEntryDialog`（323 行，最大） |
/// | 暴露数据通道 | `_showExposedDataChannelEditor` |
/// | 挂载位绑定 | `_showCompositeOverrideBindingEditor` |
/// | 覆写值编辑 | `_showCompositeOverrideValueEditor` |
/// | 覆写增删查 | `_ensurePropertyOverride` / `_upsertPropertyOverride` 等 |
///
/// ## 改这里之前务必知道
///
/// - **HANDOFF 3.5b「双写覆盖」**：从对话框进子页面，返回后必须
///   重新回读**全部**相关状态，且不能用闭包捕获的 `module`。
/// - 复合件是黑盒，外部只能连到 `exposedPorts` 声明的子元素。
/// - 实例覆写**不回写资产库模板**（模板≠实例快照，见 HANDOFF 3.5k）。
/// - `_syncStatusFieldForOverride` 只在**刚建立绑定**时拉取状态字段值，
///   否则会覆盖作者刚改的数值（见 commit `98af02e`）。
///
/// 待办：TRACKER 4.7「复合组件编辑页重做」——用户已反馈交互别扭。

  String _propertyOverrideStatusText(PropertyOverride override) {
    final parts = <String>[];
    final fieldKeys = override.overrides.keys
        .where((key) => key != 'dataChannel')
        .toList();
    if (fieldKeys.isNotEmpty) parts.add('字段覆写');
    if (override.binding != null) parts.add('已绑定');
    if (override.overrides['dataChannel'] is Map) parts.add('已配通道');
    if (parts.isEmpty) return '空槽位';
    return parts.join(' + ');
  }

  String _bindingSummary(AssemblyBinding binding) {
    final key = binding.statusKey?.trim();
    final fieldType = _bindingFieldTypeLabel(binding.fieldType ?? 'string');
    final direction = _bindingDirectionLabel(binding.direction);
    if (key == null || key.isEmpty) {
      return 'Binding：未指定状态键 · $fieldType · $direction';
    }
    return 'Binding：$key · $fieldType · $direction';
  }

  String _bindingFieldTypeLabel(String type) {
    return switch (type) {
      'number' => '数值',
      'bool' => '布尔',
      _ => '文本',
    };
  }

  String _bindingDirectionLabel(String direction) {
    return switch (direction) {
      'bidirectional' => '双向',
      'upload_only' => '仅写入',
      _ => '未启用',
    };
  }

  String _defaultBindingFieldType(UIElement child) {
    return switch (child.module?.type) {
      'progress' || 'slider' => 'number',
      'switch' => 'bool',
      _ => 'string',
    };
  }

  Widget _buildCompositeEditorSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111116),
        ),
      ),
    );
  }

  Widget _buildCompositeInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF777783),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF33333A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCompositeOverrideEntryDialog(UIElement compositeElement) async {
    if (!compositeElement.isComposite || compositeElement.composite == null) return;
    final exposedChildren = _exposedChildrenOfComposite(compositeElement);

    await showKeyboardSafeDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          List<PropertyOverride> overridesOf(UIElement child) {
            return _propertyOverridesForComposite(compositeElement.id)
                .where((override) => override.componentId == child.id)
                .toList();
          }

          final hasEditableChildren = exposedChildren.any(_supportsBasicOverrideEditor);

          return AlertDialog(
            title: const Text('复合组件实例编辑器'),
            content: SizedBox(
              width: 430,
              // AlertDialog 内部使用 IntrinsicWidth 测量内容，
              // 因此这里必须给定确定宽度；高度只限制上限，超出由外层滚动。
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompositeEditorSectionTitle('实例信息'),
                  _buildCompositeInfoLine(
                    '模板名',
                    compositeElement.composite?.name ?? '未命名复合组件',
                  ),
                  _buildCompositeInfoLine('实例 ID', compositeElement.id),
                  _buildCompositeInfoLine('所在页面', _displayPageName(_activePage)),
                  _buildCompositeInfoLine(
                    '尺寸 / 位置',
                    '${compositeElement.size.width.toStringAsFixed(0)}×${compositeElement.size.height.toStringAsFixed(0)} · '
                    '(${compositeElement.offset.dx.toStringAsFixed(0)}, ${compositeElement.offset.dy.toStringAsFixed(0)})',
                  ),
                  const SizedBox(height: 10),
                  _buildCompositeEditorSectionTitle('暴露项覆写 / Binding'),
                  Text(
                    exposedChildren.isEmpty
                        ? '该复合组件实例当前没有暴露项。可在 Studio / 资产库模板端编辑暴露端口；Assembly 里不会回写模板。'
                        : hasEditableChildren
                            ? '这里管理当前页面内这个复合组件实例的覆写槽位，只影响当前实例。已支持 text / progress / switch 的基础字段覆写。'
                            : '这里管理当前页面内这个复合组件实例的覆写槽位，只影响当前实例。当前暴露项尚无已支持的字段类型。',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (exposedChildren.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFECB3)),
                      ),
                      child: const Text(
                        '没有可覆写的暴露项。当前实例仍可移动、缩放和参与页面布局。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8D6E00),
                          height: 1.35,
                        ),
                      ),
                    )
                  else
                    // 用 Column 而非 ListView：AlertDialog 会对内容做 intrinsic 测量，
                    // 而 ListView 不支持 intrinsic 尺寸，会触发 hasSize 断言。
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      for (var index = 0; index < exposedChildren.length; index++)
                        Builder(builder: (context) {
                        final child = exposedChildren[index];
                        final type = child.module?.type ?? 'unknown';
                        final overrides = overridesOf(child);
                        final hasSlot = overrides.isNotEmpty;
                        final canEdit = _supportsBasicOverrideEditor(child);
                        final statusText = hasSlot
                            ? _propertyOverrideStatusText(overrides.first)
                            : '未创建覆写槽位';
                        return Container(
                          margin: EdgeInsets.only(
                            bottom:
                                index == exposedChildren.length - 1 ? 0 : 8,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasSlot
                                ? const Color(0xFFF3E5F5)
                                : const Color(0xFFF6F6F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasSlot
                                  ? const Color(0xFFD1C4E9)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _compositeChildAccentColor(type),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          child.module?.name ?? child.id,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF111116),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$type · $statusText',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF777783),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!hasSlot)
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        final created = _ensurePropertyOverride(
                                          componentId: child.id,
                                          sourceElementId: compositeElement.id,
                                          sourceCompositeId:
                                              compositeElement.composite?.id,
                                        );
                                        setState(() {
                                          _persistAssemblyElements();
                                        });
                                        setDialogState(() {});
                                        if (canEdit) {
                                          await _showCompositeOverrideValueEditor(
                                            compositeElement: compositeElement,
                                            child: child,
                                            propertyOverride: created,
                                          );
                                          setDialogState(() {});
                                        }
                                      },
                                      child: const Text('创建'),
                                    ),
                                ],
                              ),
                              // 覆写槽位的操作按钮独占一行并允许换行，
                              // 避免与名称同行时在窄弹窗里挤压导致溢出。
                              if (hasSlot)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: -8,
                                  children: [
                                    if (canEdit)
                                      TextButton(
                                        onPressed: () async {
                                          final override = overrides.first;
                                          await _showCompositeOverrideValueEditor(
                                            compositeElement: compositeElement,
                                            child: child,
                                            propertyOverride: override,
                                          );
                                          setDialogState(() {});
                                        },
                                        child: const Text('编辑'),
                                      ),
                                    TextButton(
                                      onPressed: () async {
                                        final override = overrides.first;
                                        await _showCompositeOverrideBindingEditor(
                                          child: child,
                                          propertyOverride: override,
                                        );
                                        setDialogState(() {});
                                      },
                                      child: const Text('绑定'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final override = overrides.first;
                                        await _showExposedDataChannelEditor(
                                          compositeElement: compositeElement,
                                          child: child,
                                          propertyOverride: override,
                                        );
                                        setDialogState(() {});
                                      },
                                      child: const Text('通道'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _removePropertyOverride(child.id);
                                        });
                                        setDialogState(() {});
                                      },
                                      child: const Text('移除'),
                                    ),
                                  ],
                                ),
                              if (hasSlot &&
                                  overrides.first.overrides['dataChannel']
                                      is Map)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '数据通道：${_dataChannelSummary(Map<String, dynamic>.from(overrides.first.overrides['dataChannel'] as Map))}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF00897B),
                                    ),
                                  ),
                                ),
                              if (hasSlot && overrides.first.binding != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _bindingSummary(overrides.first.binding!),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF5E35B1),
                                    ),
                                  ),
                                ),
                              if (hasSlot && !canEdit)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    '该暴露类型的字段编辑将在后续步骤开放。',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF777783),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                        }),
                      ],
                    ),
                  const SizedBox(height: 12),
                  _buildCompositeEditorSectionTitle('数据通道'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: const Text(
                      '每个已创建覆写槽位的暴露项都可以通过“通道”按钮配置数据通道与 AI 读写策略。通道配置随实例覆写保存，不回写资产库模板。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCompositeEditorSectionTitle('高级'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFECB3)),
                    ),
                    child: const Text(
                      '重置覆写、查看模板来源、另存为新模板等高级操作后续开放。本编辑器默认只修改当前实例，不回写资产库模板。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8D6E00),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
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

  Future<void> _showCompositeOverrideBindingEditor({
    required UIElement child,
    required PropertyOverride propertyOverride,
  }) async {
    final existing = propertyOverride.binding;
    final statusKeyController = TextEditingController(
      text: existing?.statusKey ?? '',
    );
    var fieldType = existing?.fieldType ?? _defaultBindingFieldType(child);
    if (!const {'string', 'number', 'bool'}.contains(fieldType)) {
      fieldType = _defaultBindingFieldType(child);
    }
    var direction = existing?.direction ?? 'none';
    if (!const {'none', 'upload_only', 'bidirectional'}.contains(direction)) {
      direction = 'none';
    }
    var clearBinding = false;

    Future<void> closeDialog(BuildContext ctx, bool? value) async {
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
      disposables: [statusKeyController],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Binding 挂载位 · ${child.module?.name ?? child.id}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A3-4 先保存实例级 binding 配置；后续状态栏 / SSOT 接入后，将从这里读取状态键。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF777783),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: statusKeyController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '状态键',
                    hintText: '例如 session.vars.affection',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: fieldType,
                  decoration: const InputDecoration(labelText: '字段类型'),
                  items: const [
                    DropdownMenuItem(value: 'string', child: Text('文本 string')),
                    DropdownMenuItem(value: 'number', child: Text('数值 number')),
                    DropdownMenuItem(value: 'bool', child: Text('布尔 bool')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => fieldType = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: const InputDecoration(labelText: '同步方向'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('暂不启用')),
                    DropdownMenuItem(value: 'upload_only', child: Text('仅写入状态')),
                    DropdownMenuItem(value: 'bidirectional', child: Text('双向同步')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => direction = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => closeDialog(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                clearBinding = true;
                await closeDialog(ctx, true);
              },
              child: const Text('清除绑定'),
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
      final statusKey = statusKeyController.text.trim();
      final shouldClear = clearBinding || statusKey.isEmpty || direction == 'none';
      final updated = shouldClear
          ? propertyOverride.copyWith(clearBinding: true)
          : propertyOverride.copyWith(
              binding: AssemblyBinding(
                statusKey: statusKey,
                fieldType: fieldType,
                direction: direction,
              ),
            );
      setState(() => _upsertPropertyOverride(updated));
    }
  }

  bool _supportsBasicOverrideEditor(UIElement child) {
    final type = child.module?.type;
    return type == 'text' || type == 'progress' || type == 'switch';
  }

  UIElement _applyPropertyOverridesToElement(
    UIElement element,
    List<PropertyOverride> overrides,
  ) {
    if (!element.isComposite || element.composite == null || overrides.isEmpty) {
      return element;
    }

    UIElement patchNode(UIElement node) {
      if (!node.isComposite && node.module != null) {
        final matched = overrides
            .where((override) => override.componentId == node.id)
            .toList();
        if (matched.isEmpty) return node;
        final props = Map<String, dynamic>.from(
          _deepCloneValue(node.module!.properties) as Map,
        );
        for (final override in matched) {
          final patch = Map<String, dynamic>.from(
            _deepCloneValue(override.overrides) as Map,
          )..remove('dataChannel');
          props.addAll(patch);
        }
        return node.copyWith(module: node.module!.copyWith(properties: props));
      }
      if (node.isComposite && node.composite != null) {
        return node.copyWith(
          composite: node.composite!.copyWith(
            children: node.composite!.children.map(patchNode).toList(),
          ),
        );
      }
      return node;
    }

    return element.copyWith(
      composite: element.composite!.copyWith(
        children: element.composite!.children.map(patchNode).toList(),
      ),
    );
  }

  Future<void> _showCompositeOverrideValueEditor({
    required UIElement compositeElement,
    required UIElement child,
    required PropertyOverride propertyOverride,
  }) async {
    final type = child.module?.type;
    if (!_supportsBasicOverrideEditor(child)) return;

    Future<void> closeDialog(BuildContext ctx, bool? value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    if (type == 'text') {
      final controller = TextEditingController(
        text: propertyOverride.overrides['text']?.toString() ??
            child.module?.properties['text']?.toString() ??
            '',
      );
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('覆写文本 · ${child.module?.name ?? child.id}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '输入实例专属文本',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => closeDialog(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                controller.clear();
              },
              child: const Text('恢复默认'),
            ),
            FilledButton(
              onPressed: () => closeDialog(ctx, true),
              child: const Text('应用'),
            ),
          ],
        ),
      );
      if (saved == true && mounted) {
        final nextOverrides =
            Map<String, dynamic>.from(propertyOverride.overrides);
        final text = controller.text.trim();
        if (text.isEmpty) {
          nextOverrides.remove('text');
        } else {
          nextOverrides['text'] = text;
        }
        final updated = propertyOverride.copyWith(overrides: nextOverrides);
        setState(() => _upsertPropertyOverride(updated));
      }
      controller.dispose();
      return;
    }

    if (type == 'switch') {
      var currentValue = propertyOverride.overrides['value'] is bool
          ? propertyOverride.overrides['value'] as bool
          : (child.module?.properties['value'] == true);
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('覆写开关 · ${child.module?.name ?? child.id}'),
            content: SwitchListTile(
              value: currentValue,
              title: Text(currentValue ? '开启' : '关闭'),
              onChanged: (value) => setDialogState(() => currentValue = value),
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
        final updated = propertyOverride.copyWith(
          overrides: {
            ...propertyOverride.overrides,
            'value': currentValue,
          },
        );
        setState(() => _upsertPropertyOverride(updated));
      }
      return;
    }

    if (type == 'progress') {
      final childProps = child.module?.properties ?? const <String, dynamic>{};
      final min = _numProp(childProps, 'min') ?? 0.0;
      final max = _numProp(childProps, 'max') ?? 100.0;
      final actualMin = math.min(min, max);
      final actualMax = math.max(min, max);
      double current = _numProp(propertyOverride.overrides, 'current') ??
          _numProp(childProps, 'current') ??
          actualMin;
      current = current.clamp(actualMin, actualMax).toDouble();
      final controller = TextEditingController(text: current.toStringAsFixed(0));
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('覆写进度值 · ${child.module?.name ?? child.id}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('范围：${actualMin.toStringAsFixed(0)} ~ ${actualMax.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                Slider(
                  value: current,
                  min: actualMin,
                  max: actualMax,
                  onChanged: (value) {
                    setDialogState(() {
                      current = value;
                      controller.text = value.toStringAsFixed(0);
                    });
                  },
                ),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '输入当前值',
                  ),
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed == null) return;
                    setDialogState(() {
                      current = parsed.clamp(actualMin, actualMax).toDouble();
                    });
                  },
                ),
              ],
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
        final updated = propertyOverride.copyWith(
          overrides: {
            ...propertyOverride.overrides,
            'current': current,
          },
        );
        setState(() => _upsertPropertyOverride(updated));
      }
      controller.dispose();
    }
  }

  Color _compositeChildAccentColor(String type) {
    switch (type) {
      case 'progress':
      case 'slider':
        return const Color(0xFF00E676);
      case 'text':
      case 'input':
      case 'select':
        return const Color(0xFF651FFF);
      case 'switch':
        return const Color(0xFFFFA726);
      case 'button':
        return const Color(0xFFFFD740);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

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
