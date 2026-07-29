part of '../character_assembly_page.dart';

mixin _AssemblyLogic on State<CharacterAssemblyPage> {
  final UIAssetService _assetService = UIAssetService();
  late UIAssemblyInfo _info;
  late TextEditingController _nameCtrl;
  final List<UIElement> _elements = [];
  final List<PropertyOverride> _activePropertyOverrides =
      <PropertyOverride>[];
  final List<AssemblyPage> _pages = <AssemblyPage>[];
  String? _activePageId;
  String? _selectedCompositeId;
  bool _runtimePreviewMode = false;
  String? _runtimePreviewPageId;
  UIAssemblyInfo? _runtimePreviewInfo;
  Offset _canvasOffset = Offset.zero;
  bool _showLayerPanel = false;
  bool _showAssetDrawer = false;
  String _activeAssetCategory = 'logic';
  int _generatedElementIdSeed = 0;

  static const Size _defaultPcbSize = Size(360, 800);
  static const double _pcbMinHeight = UIAssemblyInfo.minPcbHeight;
  static const double _pcbMaxHeight = UIAssemblyInfo.maxPcbHeight;
  static const double _pcbMinWidth = UIAssemblyInfo.minPcbWidth;
  late Size _pcbSize;
  late Offset _pcbOffset;
  late Color _pcbColor;
  late bool _pcbRounded;
  bool _didInitialViewportCenter = false;
  double _pcbResizeStartHeight = _defaultPcbSize.height;
  double _pcbResizeStartWidth = _defaultPcbSize.width;
  double _pcbResizeStartGlobalDy = 0.0;
  double _pcbResizeStartGlobalDx = 0.0;

  // 拖放状态
  _AssemblyDragPayload? _activePlacement;
  static const double _dragThreshold = 24.0;
  static const String _pageRouterType = 'page_router';

  UIModule get _pageRouterTemplate => UIModule(
        id: 'atom_logic_page_router',
        name: '页面路由器',
        type: _pageRouterType,
        color: const Color(0xFF00897B),
        properties: {
          'route': {
            'action': 'switch_base_page',
            'targetPageId': '',
            'transition': 'base_slide',
            'durationMs': 220,
          },
        },
      );

  UIModule _assetModuleTemplate(String id) {
    if (id == 'atom_logic_button_tap') {
      return UIModule(
        id: id,
        name: '按钮',
        type: 'button',
        color: const Color(0xFF757575),
        properties: {
          'text': '',
          'action': 'tap',
          'doubleTapIntervalMs': 300,
          'longPressThresholdMs': 500,
        },
      );
    }

    final loaded = _assetService.getModule(id);
    if (loaded != null) return loaded;

    return switch (id) {
      'atom_linker_basic' => UIModule(
          id: id,
          name: '联动器',
          type: 'linker',
          color: const Color(0xFF00ACC1),
          properties: {
            'linker': {
              'sourceModuleId': '',
              'sourcePort': '',
              'sourceType': '',
              'targetModuleId': '',
              'targetPort': '',
              'targetType': '',
              'scheme': '未配置',
              'enabled': false,
              'priority': 5,
              'cooldownMs': 0,
              'maxTriggerCount': 0,
            },
          },
        ),
      'atom_text' => UIModule(
          id: id,
          name: '文本',
          type: 'text',
          color: const Color(0xFF111116),
          properties: {'text': '文本'},
        ),
      'atom_data_bar' => UIModule(
          id: id,
          name: '进度条',
          type: 'progress',
          color: const Color(0xFFFF4081),
          properties: {'min': 0, 'max': 100, 'current': 65},
        ),
      'atom_message_flow' => UIModule(
          id: id,
          name: '消息流',
          type: 'message_flow',
          color: const Color(0xFF3949AB),
          material: UIModuleMaterial.solid,
          shape: UIModuleShape.rounded,
          borderRadius: 12,
          properties: {
            // 0 表示显示全部历史；大于 0 则只显示最近 N 条。
            'historyLimit': 0,
            'showUser': true,
            'showAssistant': true,
            // A11-2：LLM 回复常带 Markdown，默认按富文本渲染。
            'richText': true,
            'fontSize': 12.5,
            'userBubbleColor': 0xFFDCF8C6,
            'assistantBubbleColor': 0xFFF1F1F4,
            'bubbleRadius': 12.0,
          },
        ),
      'atom_surface_base' => UIModule(
          id: id,
          name: '面板',
          type: 'surface',
          color: const Color(0xFF651FFF),
          material: UIModuleMaterial.solid,
          shape: UIModuleShape.rounded,
          borderRadius: 16,
          properties: {},
        ),
      _ => _pageRouterTemplate,
    };
  }

  void _initFromInfo(UIAssemblyInfo info) {
    _info = info;
    _nameCtrl = TextEditingController(text: info.name);
    _pcbSize = Size(
      info.pcbWidth
          .clamp(_pcbMinWidth, UIAssemblyInfo.maxPcbWidthFor(info.mode))
          .toDouble(),
      info.pcbHeight.clamp(_pcbMinHeight, _pcbMaxHeight).toDouble(),
    );
    _pcbColor = Color(info.pcbColorValue);
    _pcbRounded = info.pcbRounded;
    _pcbOffset = Offset.zero;
    _canvasOffset = Offset.zero;
    _restoreAssemblyPages();
    _reconcileStatusChannelBindings();
    _setupEventBusListener();
    _scheduleInitialViewportCenter();
    _assetService.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _restoreAssemblyPages() {
    _pages.clear();
    final rawPages = _info.pagesJson.trim();
    if (rawPages.isNotEmpty && rawPages != '[]') {
      try {
        final decoded = jsonDecode(rawPages);
        if (decoded is List) {
          _pages.addAll(
            decoded
                .whereType<Map>()
                .map((item) => AssemblyPage.fromJson(Map<String, dynamic>.from(item))),
          );
        }
      } catch (_) {
        _pages.clear();
      }
    }

    if (_pages.isEmpty) {
      final legacyElements = <UIElement>[];
      final raw = _info.elementsJson.trim();
      if (raw.isNotEmpty && raw != '[]') {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            legacyElements.addAll(
              decoded
                  .whereType<Map>()
                  .map((item) => UIElement.fromJson(Map<String, dynamic>.from(item))),
            );
          }
        } catch (_) {
          // 忽略损坏旧数据，退回空白默认页。
        }
      }
      _pages.add(
        AssemblyPage(
          id: 'page_${DateTime.now().millisecondsSinceEpoch}',
          name: '主菜单',
          type: 'base',
          sortOrder: 0,
          elements: legacyElements,
        ),
      );
    }

    _pages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _activePageId = _pages.first.id;
    _loadActivePageState();
  }

  /// 打开 Assembly 时重新对齐状态字段通道。
  ///
  /// 场景：用户先在数据通道里写了状态字段名（记为 pendingName），
  /// 之后才去角色卡状态栏编辑页创建同名字段。这里在进入页面时补绑 targetId；
  /// 反之字段被删除时，回退为 pendingName 待创建状态。
  void _reconcileStatusChannelBindings() {
    var changed = false;

    Map<String, dynamic>? reconcile(Map<String, dynamic> channel) {
      if (channel['targetKind']?.toString() != 'status_field') return null;
      final name = (channel['semanticLabel']?.toString() ??
              channel['pendingName']?.toString() ??
              '')
          .trim();
      if (name.isEmpty) return null;
      final resolved = _resolveStatusTarget(name);
      final nextTargetId = resolved.targetId;
      final nextPending = resolved.pending ? name : '';
      final nextFieldType = resolved.fieldType ?? channel['fieldType'];
      if (channel['targetId']?.toString() == nextTargetId &&
          channel['pendingName']?.toString() == nextPending &&
          channel['fieldType'] == nextFieldType) {
        return null;
      }
      return Map<String, dynamic>.from(channel)
        ..['targetId'] = nextTargetId
        ..['pendingName'] = nextPending
        ..['fieldType'] = nextFieldType;
    }

    void visitElements(List<UIElement> nodes) {
      for (final node in nodes) {
        final module = node.module;
        if (module != null) {
          final raw = module.properties['dataChannel'];
          if (raw is Map) {
            final next = reconcile(Map<String, dynamic>.from(raw));
            if (next != null) {
              module.properties['dataChannel'] = next;
              changed = true;
            }
          }
        }
        if (node.isComposite && node.composite != null) {
          visitElements(node.composite!.children);
        }
      }
    }

    for (final page in _pages) {
      visitElements(page.elements);
      for (final override in page.propertyOverrides) {
        final raw = override.overrides['dataChannel'];
        if (raw is Map) {
          final next = reconcile(Map<String, dynamic>.from(raw));
          if (next != null) {
            override.overrides['dataChannel'] = next;
            changed = true;
          }
        }
      }
    }

    if (changed) {
      _loadActivePageState();
      _persistAssemblyElements();
    }
  }

  AssemblyPage get _activePage {
    return _pages.firstWhere(
      (page) => page.id == _activePageId,
      orElse: () => _pages.first,
    );
  }

  PropertyOverride _clonePropertyOverride(PropertyOverride override) {
    return override.copyWith(
      overrides: Map<String, dynamic>.from(
        _deepCloneValue(override.overrides) as Map,
      ),
      binding: override.binding?.copyWith(),
    );
  }

  void _syncCanvasStateIntoActivePage() {
    final targetIndex = _pages.indexWhere((page) => page.id == _activePageId);
    if (targetIndex == -1) return;
    _pages[targetIndex].elements = _elements
        .map((element) => UIElement.fromJson(element.toJson()))
        .toList();
    _pages[targetIndex].propertyOverrides = _activePropertyOverrides
        .map(_clonePropertyOverride)
        .toList();
  }

  void _loadActivePageState() {
    _elements
      ..clear()
      ..addAll(
        _activePage.elements
            .map((element) => UIElement.fromJson(element.toJson())),
      );
    _activePropertyOverrides
      ..clear()
      ..addAll(
        _activePage.propertyOverrides.map(_clonePropertyOverride),
      );
    _sanitizeActivePropertyOverrides();
  }

  int get _activePropertyOverrideCount => _activePropertyOverrides.length;

  void _sanitizeActivePropertyOverrides() {
    final validIds = <String>{};
    final compositeIds = <String>{};

    void visit(List<UIElement> nodes, {String? rootCompositeId}) {
      for (final node in nodes) {
        validIds.add(node.id);
        if (node.isComposite && node.composite != null) {
          compositeIds.add(node.id);
          visit(node.composite!.children, rootCompositeId: node.id);
        }
      }
    }

    visit(_elements);
    _activePropertyOverrides.removeWhere((override) {
      if (override.componentId.isEmpty || !validIds.contains(override.componentId)) {
        return true;
      }
      final sourceId = override.sourceElementId;
      if (sourceId != null && sourceId.isNotEmpty && !compositeIds.contains(sourceId)) {
        return true;
      }
      return false;
    });
  }

  List<PropertyOverride> _propertyOverridesForComposite(String sourceElementId) {
    return _activePropertyOverrides
        .where((override) => override.sourceElementId == sourceElementId)
        .map(_clonePropertyOverride)
        .toList();
  }

  List<UIElement> _exposedChildrenOfComposite(UIElement compositeElement) {
    final composite = compositeElement.composite;
    if (!compositeElement.isComposite || composite == null) return const [];
    final exposedIds = (composite.exposedPorts ?? const <ExposedPort>[])
        .map((port) => port.elementId)
        .toSet();
    return composite.children
        .where((child) => exposedIds.contains(child.id))
        .toList();
  }

  void _selectComposite(String id) {
    if (_selectedCompositeId == id) return;
    setState(() => _selectedCompositeId = id);
  }

  void _clearCompositeSelection() {
    if (_selectedCompositeId == null) return;
    setState(() => _selectedCompositeId = null);
  }

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

    await showDialog<void>(
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
    var applyPolicy =
        existing?['llmUpdateApplyPolicy']?.toString() ?? 'confirm';

    Future<void> closeDialog(BuildContext ctx, bool value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    final saved = await showDialog<bool>(
      context: context,
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
                      visibility: visibility,
                      llmReadPolicy: llmReadPolicy,
                      llmWritePolicy: llmWritePolicy,
                      applyPolicy: applyPolicy,
                      onSemanticSource: (value) =>
                          setDialogState(() => semanticSource = value),
                      onLabelElementId: (value) =>
                          setDialogState(() => labelElementId = value),
                      onTargetKind: (value) =>
                          setDialogState(() => targetKind = value),
                      onVisibility: (value) =>
                          setDialogState(() => visibility = value),
                      onReadPolicy: (value) =>
                          setDialogState(() => llmReadPolicy = value),
                      onWritePolicy: (value) =>
                          setDialogState(() => llmWritePolicy = value),
                      onApplyPolicy: (value) =>
                          setDialogState(() => applyPolicy = value),
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
          applyPolicy: applyPolicy,
        );
      }
      setState(() {
        _upsertPropertyOverride(
          propertyOverride.copyWith(overrides: nextOverrides),
        );
      });
    }
    nameController.dispose();
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

    final saved = await showDialog<bool>(
      context: context,
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
    statusKeyController.dispose();
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

  List<AssemblyPage> _orderedPages() {
    final bases = _pages.where((page) => page.isBase).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final ordered = <AssemblyPage>[];

    void appendChildren(String parentId) {
      final children = _pages
          .where((page) => page.parentPageId == parentId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (final child in children) {
        ordered.add(child);
        appendChildren(child.id);
      }
    }

    for (final base in bases) {
      ordered.add(base);
      appendChildren(base.id);
    }
    return ordered;
  }

  List<AssemblyPage> _directChildPages(String? parentPageId) {
    final pages = _pages
        .where((page) => page.parentPageId == parentPageId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return pages;
  }

  AssemblyPage get _rootBasePage {
    final bases = _pages.where((page) => page.isBase).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return bases.first;
  }

  bool _isRootBasePage(AssemblyPage page) => page.id == _rootBasePage.id;

  String _displayPageName(AssemblyPage page) =>
      _isRootBasePage(page) ? '主菜单' : page.name;

  int _pageDepth(AssemblyPage page) {
    var depth = 0;
    var parentId = page.parentPageId;
    final visited = <String>{page.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final index = _pages.indexWhere((candidate) => candidate.id == parentId);
      if (index == -1) break;
      depth++;
      parentId = _pages[index].parentPageId;
    }
    return depth;
  }

  List<AssemblyPage> _ancestorPagesForActivePage() {
    final ancestors = <AssemblyPage>[];
    var parentId = _activePage.parentPageId;
    final visited = <String>{_activePage.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final index = _pages.indexWhere((page) => page.id == parentId);
      if (index == -1) break;
      final page = _pages[index];
      ancestors.insert(0, page);
      parentId = page.parentPageId;
    }
    return ancestors;
  }

  void _activatePage(String pageId) {
    if (_activePageId == pageId) return;
    _syncCanvasStateIntoActivePage();
    _activePageId = pageId;
    _loadActivePageState();
    _selectedCompositeId = null;
    _setupEventBusListener();
    _persistAssemblyElements();
    setState(() {});
  }

  AssemblyPage? _pageById(String pageId) {
    for (final page in _pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  AssemblyPage? _baseAncestorOf(AssemblyPage page) {
    if (page.isBase) return page;
    var parentId = page.parentPageId;
    final visited = <String>{page.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final parent = _pageById(parentId);
      if (parent == null) return null;
      if (parent.isBase) return parent;
      parentId = parent.parentPageId;
    }
    return null;
  }

  Map<String, dynamic> _routeDataOf(UIModule module) {
    final raw = module.properties['route'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  String _routeActionOf(UIModule module) {
    final action = _routeDataOf(module)['action']?.toString();
    if (action == 'open_overlay') return 'open_overlay';
    return 'switch_base_page';
  }

  String _routeTargetPageIdOf(UIModule module) {
    return _routeDataOf(module)['targetPageId']?.toString() ?? '';
  }

  String _routeActionLabel(String action) {
    return action == 'open_overlay' ? '打开叠加页' : '切换平级页';
  }

  List<AssemblyPage> _routeTargetCandidates(String action) {
    if (action == 'open_overlay') {
      return _directChildPages(_activePage.id)
          .where((page) => page.isOverlay)
          .toList();
    }

    final currentBase = _baseAncestorOf(_activePage) ?? _activePage;
    return _pages
        .where((page) => page.isBase && page.id != currentBase.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  String _defaultRouteTransition(String action) {
    return action == 'open_overlay' ? 'overlay_fade' : 'base_slide';
  }

  int _defaultRouteDurationMs(String action) {
    return action == 'open_overlay' ? 180 : 220;
  }

  UIModule _updatePageRouterModule(
    UIModule module, {
    required String action,
    required String targetPageId,
  }) {
    final props = Map<String, dynamic>.from(_deepCloneValue(module.properties) as Map);
    final existingRoute = _routeDataOf(module);
    props['route'] = {
      ...existingRoute,
      'action': action,
      'targetPageId': targetPageId,
      'transition': _defaultRouteTransition(action),
      'durationMs': _defaultRouteDurationMs(action),
    };
    return module.copyWith(properties: props);
  }

  String _pageRouterSubtitle(UIModule module) {
    final action = _routeActionOf(module);
    final targetId = _routeTargetPageIdOf(module);
    final target = targetId.isEmpty ? null : _pageById(targetId);
    if (target == null) return '${_routeActionLabel(action)} · 未配置';
    return '${_routeActionLabel(action)} · ${_displayPageName(target)}';
  }

  Future<void> _showPageRouterConfigDialog(UIElement element) async {
    final module = element.module;
    if (module == null || module.type != _pageRouterType) return;

    var action = _routeActionOf(module);
    var targetPageId = _routeTargetPageIdOf(module);

    List<AssemblyPage> candidatesForCurrentAction() =>
        _routeTargetCandidates(action);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final candidates = candidatesForCurrentAction();
          final hasTarget = candidates.any((page) => page.id == targetPageId);
          final selectedTargetId = hasTarget ? targetPageId : null;

          return AlertDialog(
            title: const Text('配置页面路由器'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A7 最小版只保存路由配置，并支持编辑态点击测试跳转；动画和 linker 触发后续再接。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: action,
                    decoration: const InputDecoration(labelText: '路由动作'),
                    items: const [
                      DropdownMenuItem(
                        value: 'switch_base_page',
                        child: Text('切换平级页'),
                      ),
                      DropdownMenuItem(
                        value: 'open_overlay',
                        child: Text('打开叠加页'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        action = value;
                        targetPageId = '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (candidates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFECB3)),
                      ),
                      child: Text(
                        action == 'open_overlay'
                            ? '当前页面没有直接叠加子页。请先在图层面板创建叠加页。'
                            : '当前没有可切换的其他平级页。请先在图层面板创建平级页。',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8D6E00),
                          height: 1.35,
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetId,
                      decoration: const InputDecoration(labelText: '目标页'),
                      items: candidates
                          .map(
                            (page) => DropdownMenuItem(
                              value: page.id,
                              child: Text(_displayPageName(page)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => targetPageId = value);
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: candidates.isEmpty || targetPageId.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final index = _elements.indexWhere((candidate) => candidate.id == element.id);
      if (index == -1) return;
      setState(() {
        final current = _elements[index];
        final currentModule = current.module;
        if (currentModule == null) return;
        _elements[index] = current.copyWith(
          module: _updatePageRouterModule(
            currentModule,
            action: action,
            targetPageId: targetPageId,
          ),
        );
      });
      _persistAssemblyElements();
    }
  }

  List<UIElement> _topLevelModulesOfType(String type) {
    return _elements
        .where((element) =>
            !element.isComposite && element.module?.type == type)
        .toList();
  }

  Map<String, dynamic> _linkerDataOf(UIModule module) {
    final raw = module.properties['linker'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  String _moduleNodeLabel(UIElement element) {
    final module = element.module;
    if (module == null) return element.id;
    return '${module.name} · ${element.id.split('_').last}';
  }

  /// 由方案 id 推导来源端口。
  ///
  /// Studio 侧的端口来自拖拽连线的落点，Assembly 没有连线交互，
  /// 因此改为按方案约定推导——运行端 `LinkerService` 正是按这些
  /// 端口名做匹配的（见其 `initEventBusListener` 中的 srcPort 判断）。
  String _schemeSourcePort(String scheme) {
    if (scheme.startsWith('click_') || scheme.startsWith('event_')) {
      return 'tap';
    }
    if (scheme.startsWith('double_click_')) return 'double_tap';
    if (scheme.startsWith('long_press_')) return 'long_press';
    if (scheme.startsWith('timer_tick_')) return 'timer_tick';
    if (scheme.startsWith('input_submit_')) return 'committedValue';
    if (scheme.startsWith('slider_commit_')) return 'committedValue';
    if (scheme.startsWith('input_value_')) return 'text';
    if (scheme.startsWith('text_extract_')) return 'text';
    return 'current';
  }

  /// 由方案 id 推导目标端口。
  String _schemeTargetPort(String scheme) {
    if (scheme.endsWith('_to_text')) return 'text';
    if (scheme.contains('_to_progress')) return 'current';
    if (scheme.contains('_to_slider')) return 'current';
    if (scheme.contains('_to_switch')) return 'value';
    if (scheme.contains('_to_indicator')) return 'currentValue';
    if (scheme.contains('_to_input')) return 'text';
    if (scheme.contains('_to_select')) return 'current';
    // surface 的可见性方案写的是 visible 属性，不是动画端口。
    if (scheme.contains('_to_surface_visible')) return 'visible';
    if (scheme.contains('_to_surface')) return 'anim';
    if (scheme.contains('_to_image')) return 'assetPath';
    if (scheme.contains('_to_math_trigger')) return 'gate_in';
    if (scheme.contains('_to_math_param')) return 'data_in';
    if (scheme.contains('_to_timer')) return 'value';
    if (scheme.contains('_to_page_route') || scheme.contains('_page_route')) {
      return 'trigger';
    }
    return 'value';
  }

  /// 可作为 linker 来源 / 目标的候选组件。
  ///
  /// 排除 linker 自身（不支持 linker 串 linker）。
  /// 复合组件内部的暴露项后续再接，当前只取顶层原子。
  List<UIElement> _linkerCandidates() {
    return _elements
        .where((element) =>
            !element.isComposite &&
            element.module != null &&
            element.module!.type != 'linker')
        .toList();
  }

  String _linkerCandidateLabel(UIElement element) {
    final module = element.module!;
    final name = module.name.trim();
    return name.isEmpty ? module.type : '$name · ${module.type}';
  }

  /// 配置 Assembly 联动器。
  ///
  /// 与 Studio 共用 `LinkerMatrixEngine` 的方案矩阵，
  /// 因此这里能选到的方案与创作工作室完全一致，运行端也已全部支持。
  /// 此前只硬编码了 button → page_router 一条通路，
  /// 导致 button 无法联动 surface 做按压反馈等（button 本身不显形）。
  Future<void> _showAssemblyLinkerConfigDialog(UIElement linkerElement) async {
    final module = linkerElement.module;
    if (module == null || module.type != 'linker') return;

    final candidates = _linkerCandidates();
    final existing = _linkerDataOf(module);
    var sourceId = existing['sourceModuleId']?.toString() ?? '';
    var targetId = existing['targetModuleId']?.toString() ?? '';
    var scheme = existing['scheme']?.toString() ?? '';
    // 方案参数（如消息操作要执行哪个动作）。与 Studio 侧一致地按 key 存取，
    // 这样同一条 linker 在两边打开看到的配置完全相同。
    var schemeParams = <String, dynamic>{
      ...(existing['schemeParams'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    };
    if (!candidates.any((element) => element.id == sourceId)) sourceId = '';
    if (!candidates.any((element) => element.id == targetId)) targetId = '';

    UIElement? byId(String id) {
      for (final element in candidates) {
        if (element.id == id) return element;
      }
      return null;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final source = byId(sourceId);
          final target = byId(targetId);
          // 源与目标都选定后才能算出可用方案。
          final schemes = (source != null && target != null)
              ? LinkerMatrixEngine.getAvailableSchemes(
                  source.module!.type,
                  target.module!.type,
                )
              : const <SchemeDefinition>[];
          // 换了源/目标后，旧方案可能不再适用。
          if (schemes.every((def) => def.id != scheme)) {
            scheme = '';
            // 参数属于具体方案，方案没了就必须清掉——
            // 留着会把上一个方案的键带进新方案的配置里。
            schemeParams = <String, dynamic>{};
          }

          final canSave = source != null && target != null && scheme.isNotEmpty;

          Widget picker({
            required String label,
            required String value,
            required ValueChanged<String> onChanged,
          }) {
            return DropdownButtonFormField<String>(
              initialValue: value.isEmpty ? null : value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label, isDense: true),
              items: candidates
                  .map(
                    (element) => DropdownMenuItem(
                      value: element.id,
                      child: Text(
                        _linkerCandidateLabel(element),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (next) {
                if (next == null) return;
                setDialogState(() => onChanged(next));
              },
            );
          }

          return AlertDialog(
            title: const Text('配置联动器'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (candidates.length < 2)
                      const Text(
                        '至少需要两个非联动器组件才能建立连接。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                        ),
                      )
                    else ...[
                      picker(
                        label: '来源组件',
                        value: sourceId,
                        onChanged: (v) => sourceId = v,
                      ),
                      const SizedBox(height: 12),
                      picker(
                        label: '目标组件',
                        value: targetId,
                        onChanged: (v) => targetId = v,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '联动方案',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111116),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (source == null || target == null)
                        const Text(
                          '请先选择来源与目标组件。',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF777783),
                          ),
                        )
                      else if (schemes.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${source.module!.type} 与 ${target.module!.type} '
                            '之间没有可用的联动方案。',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC62828),
                              height: 1.35,
                            ),
                          ),
                        )
                      else
                        ...schemes.map(
                          (def) => _buildAssemblySchemeTile(
                            def: def,
                            selected: def.id == scheme,
                            onTap: () => setDialogState(() {
                              if (scheme == def.id) return;
                              scheme = def.id;
                              // 换方案即重置参数，理由同上。
                              schemeParams = <String, dynamic>{};
                            }),
                          ),
                        ),
                      // 方案参数编辑器。
                      //
                      // 此前漏了这一块，导致带参数的方案（如消息操作要选
                      // 执行哪个动作）保存后只能吃默认值，作者无从配置。
                      ..._buildAssemblySchemeParamEditors(
                        scheme: scheme,
                        params: schemeParams,
                        onChanged: (key, value) =>
                            setDialogState(() => schemeParams[key] = value),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    sourceId = '';
                    targetId = '';
                    scheme = '';
                  });
                },
                child: const Text('清除连接'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(ctx, true) : null,
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final index =
          _elements.indexWhere((element) => element.id == linkerElement.id);
      if (index == -1) return;
      setState(() {
        final current = _elements[index];
        final currentModule = current.module;
        if (currentModule == null) return;
        final props = Map<String, dynamic>.from(
          _deepCloneValue(currentModule.properties) as Map,
        );
        final linkerData = Map<String, dynamic>.from(
          props['linker'] is Map ? props['linker'] as Map : const {},
        );

        if (sourceId.isEmpty || targetId.isEmpty || scheme.isEmpty) {
          linkerData
            ..remove('sourceModuleId')
            ..remove('sourcePort')
            ..remove('sourceType')
            ..remove('targetModuleId')
            ..remove('targetPort')
            ..remove('targetType')
            ..remove('inputConnection')
            ..remove('outputConnection')
            ..remove('schemeParams');
          linkerData['scheme'] = '未配置';
          linkerData['enabled'] = false;
        } else {
          final def = LinkerMatrixEngine.getSchemeDefinition(scheme);
          linkerData['sourceModuleId'] = sourceId;
          linkerData['targetModuleId'] = targetId;
          linkerData['scheme'] = scheme;
          linkerData['enabled'] = true;
          // 端口与类型由方案定义推导，保持与 Studio 侧一致。
          linkerData['sourcePort'] = _schemeSourcePort(scheme);
          linkerData['targetPort'] = _schemeTargetPort(scheme);
          linkerData['sourceType'] = (def?.isPulse ?? false) ? 'pulse' : 'value';
          // 参数缺省时补上方案声明的默认值，运行端就不必各自兜底。
          final resolvedParams = <String, dynamic>{};
          for (final field in def?.params ?? const <SchemeParamField>[]) {
            final value = schemeParams[field.key] ?? field.defaultValue;
            if (value != null) resolvedParams[field.key] = value;
          }
          if (resolvedParams.isEmpty) {
            linkerData.remove('schemeParams');
          } else {
            linkerData['schemeParams'] = resolvedParams;
          }
          linkerData['priority'] ??= 5;
          linkerData['cooldownMs'] ??= 0;
          linkerData['maxTriggerCount'] ??= 0;
          linkerData['inputConnection'] = {
            'from': sourceId,
            'fromPort': linkerData['sourcePort'],
            'to': current.id,
            'toPort': 'input',
          };
          linkerData['outputConnection'] = {
            'from': current.id,
            'fromPort': 'output',
            'to': targetId,
            'toPort': linkerData['targetPort'],
          };
        }
        props['linker'] = linkerData;
        _elements[index] = current.copyWith(
          module: currentModule.copyWith(properties: props),
        );
      });
      _setupEventBusListener();
      _persistAssemblyElements();
    }
  }

  /// 方案参数编辑器。
  ///
  /// 只实现方案矩阵实际用到的类型（choice / number / doubleVal / text /
  /// boolean）。Studio 侧还有 color，Assembly 目前没有带颜色参数的方案，
  /// 等真的出现再补——提前写一个用不到的取色器只会增加维护面。
  List<Widget> _buildAssemblySchemeParamEditors({
    required String scheme,
    required Map<String, dynamic> params,
    required void Function(String key, dynamic value) onChanged,
  }) {
    if (scheme.isEmpty) return const <Widget>[];
    final def = LinkerMatrixEngine.getSchemeDefinition(scheme);
    if (def == null || def.params.isEmpty) return const <Widget>[];

    return [
      const SizedBox(height: 14),
      const Text(
        '方案参数',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111116),
        ),
      ),
      const SizedBox(height: 6),
      for (final field in def.params)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildAssemblySchemeParamField(
            field: field,
            value: params[field.key] ?? field.defaultValue,
            onChanged: (v) => onChanged(field.key, v),
          ),
        ),
    ];
  }

  Widget _buildAssemblySchemeParamField({
    required SchemeParamField field,
    required dynamic value,
    required ValueChanged<dynamic> onChanged,
  }) {
    switch (field.type) {
      case SchemeParamType.choice:
        final options = field.options ?? const <String>[];
        if (options.isEmpty) return const SizedBox.shrink();
        final current = options.contains(value?.toString())
            ? value!.toString()
            : options.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: current,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: field.label,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final opt in options)
                  DropdownMenuItem(
                    value: opt,
                    child: Text(
                      _assemblyParamOptionLabel(opt),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
            if (_assemblyParamOptionHint(current) != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _assemblyParamOptionHint(current)!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF777783),
                    height: 1.35,
                  ),
                ),
              ),
          ],
        );

      case SchemeParamType.boolean:
        final on = value is bool
            ? value
            : value?.toString().toLowerCase() == 'true';
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(field.label, style: const TextStyle(fontSize: 13)),
          subtitle: field.description == null
              ? null
              : Text(field.description!,
                  style: const TextStyle(fontSize: 11, height: 1.3)),
          value: on,
          onChanged: onChanged,
        );

      case SchemeParamType.number:
      case SchemeParamType.doubleVal:
        final isInt = field.type == SchemeParamType.number;
        return TextFormField(
          initialValue: value?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.description,
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          // 只在解析成功时回写：输入中途的空串 / 半个负号不该覆盖已有值。
          onChanged: (raw) {
            final parsed =
                isInt ? int.tryParse(raw.trim()) : double.tryParse(raw.trim());
            if (parsed != null) onChanged(parsed);
          },
        );

      case SchemeParamType.text:
      case SchemeParamType.color:
        return TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.description,
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        );
    }
  }

  /// 参数取值的显示名。
  ///
  /// 方案里存的是英文 key（要序列化进角色卡），但作者看到的应该是中文。
  String _assemblyParamOptionLabel(String option) {
    final action = MessageAction.fromKey(option);
    if (action != null) return action.label;
    if (option == 'ratio') return '比例归一化（0~100% 折算）';
    if (option == 'absolute') return '绝对数值透传（超出截断）';
    return option;
  }

  /// 参数取值的补充说明。
  String? _assemblyParamOptionHint(String option) =>
      MessageAction.fromKey(option)?.description;

  Widget _buildAssemblySchemeTile({
    required SchemeDefinition def,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEDE7F6) : const Color(0xFFF6F6F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF7E57C2)
                  : Colors.black.withValues(alpha: 0.06),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected
                    ? const Color(0xFF7E57C2)
                    : const Color(0xFF9E9EA8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111116),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      def.description,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑态点击组件时的提示。
  ///
  /// 制作与预览严格分离：编辑器里不执行任何联动效果，包括页面跳转。
  /// 原因是编辑时的点击 / 拖动极易误触发，而组件状态会被
  /// `_persistAssemblyElements` 一并保存，污染最终产物。
  void _showEditModeHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('编辑态不执行联动；切页请用图层面板，效果请进运行时预览'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _gestureDirectionLabel(String direction) {
    return switch (direction) {
      'swipe_right' => '右滑',
      'swipe_up' => '上滑',
      'swipe_down' => '下滑',
      _ => '左滑',
    };
  }

  List<AssemblyPage> _gestureTargetCandidates(
    AssemblyPage page,
    String action,
  ) {
    if (action == 'open_overlay') {
      return _directChildPages(page.id).where((candidate) => candidate.isOverlay).toList();
    }

    final currentBase = _baseAncestorOf(page) ?? page;
    return _pages
        .where((candidate) => candidate.isBase && candidate.id != currentBase.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  AssemblyPageGesture? _gestureForDirection(
    List<AssemblyPageGesture> gestures,
    String direction,
  ) {
    for (final gesture in gestures) {
      if (gesture.direction == direction) return gesture;
    }
    return null;
  }

  Future<void> _showPageGestureDialog(AssemblyPage page) async {
    const directions = ['swipe_left', 'swipe_right', 'swipe_up', 'swipe_down'];
    var localGestures = page.gestures
        .map(
          (gesture) => AssemblyPageGesture(
            direction: gesture.direction,
            action: gesture.action,
            targetPageId: gesture.targetPageId,
            transition: gesture.transition,
            durationMs: gesture.durationMs,
          ),
        )
        .toList();
    var direction = directions.first;
    var existing = _gestureForDirection(localGestures, direction);
    var action = existing?.action == 'open_overlay' ? 'open_overlay' : 'switch_base_page';
    var targetPageId = existing?.targetPageId ?? '';

    void loadDirection(String nextDirection) {
      direction = nextDirection;
      existing = _gestureForDirection(localGestures, direction);
      action = existing?.action == 'open_overlay' ? 'open_overlay' : 'switch_base_page';
      targetPageId = existing?.targetPageId ?? '';
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final candidates = _gestureTargetCandidates(page, action);
          final selectedTarget = candidates.any((candidate) => candidate.id == targetPageId)
              ? targetPageId
              : null;
          final canSave = candidates.isNotEmpty && selectedTarget != null;
          return AlertDialog(
            title: Text('页面手势 · ${_displayPageName(page)}'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A9 MVP：手势作用于当前页面整块 PCB。局部手势热区与更多动画后续再做。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('gesture_direction_$direction'),
                    initialValue: direction,
                    decoration: const InputDecoration(labelText: '手势方向'),
                    items: directions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_gestureDirectionLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => loadDirection(value));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('gesture_action_${direction}_$action'),
                    initialValue: action,
                    decoration: const InputDecoration(labelText: '动作'),
                    items: const [
                      DropdownMenuItem(
                        value: 'switch_base_page',
                        child: Text('切换平级页'),
                      ),
                      DropdownMenuItem(
                        value: 'open_overlay',
                        child: Text('打开叠加页'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        action = value;
                        targetPageId = '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (candidates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFECB3)),
                      ),
                      child: Text(
                        action == 'open_overlay'
                            ? '当前页面没有直接叠加子页。'
                            : '当前没有可切换的其他平级页。',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8D6E00),
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('gesture_target_${direction}_${action}_${selectedTarget ?? 'none'}'),
                      initialValue: selectedTarget,
                      decoration: const InputDecoration(labelText: '目标页'),
                      items: candidates
                          .map(
                            (candidate) => DropdownMenuItem(
                              value: candidate.id,
                              child: Text(_displayPageName(candidate)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => targetPageId = value);
                      },
                    ),
                  if (localGestures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: localGestures
                          .map(
                            (gesture) => Chip(
                              label: Text(
                                '${_gestureDirectionLabel(gesture.direction)} → ${_displayPageName(_pageById(gesture.targetPageId) ?? page)}',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () {
                  localGestures.removeWhere((gesture) => gesture.direction == direction);
                  Navigator.pop(ctx, true);
                },
                child: const Text('删除此方向'),
              ),
              FilledButton(
                onPressed: canSave
                    ? () {
                        localGestures.removeWhere((gesture) => gesture.direction == direction);
                        localGestures.add(
                          AssemblyPageGesture(
                            direction: direction,
                            action: action,
                            targetPageId: targetPageId,
                            transition: _defaultRouteTransition(action),
                            durationMs: _defaultRouteDurationMs(action),
                          ),
                        );
                        Navigator.pop(ctx, true);
                      }
                    : null,
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final index = _pages.indexWhere((candidate) => candidate.id == page.id);
      if (index == -1) return;
      setState(() {
        _pages[index].gestures = localGestures;
      });
      _persistAssemblyElements();
    }
  }

  /// 宽容读取数值属性。
  ///
  /// 组件属性里同一个键在不同类型下语义不同：例如 select 的 `current`
  /// 存的是选项 value（String），而 progress / slider 的 `current` 是数值。
  /// 直接 `as num?` 会在 select 上抛 type cast 异常，因此统一走这里。
  double? _numProp(Map<String, dynamic> props, String key) {
    final raw = props[key];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  int? _intProp(Map<String, dynamic> props, String key) {
    return _numProp(props, key)?.toInt();
  }

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

  Future<void> _showAtomInstanceEditorDialog(UIElement element) async {
    final module = element.module;
    if (module == null) return;
    if (const {'linker', 'page_router', 'math_node', 'timer'}.contains(module.type)) {
      return;
    }

    final nameController = TextEditingController(text: module.name);
    final widthController = TextEditingController(
      text: element.size.width.toStringAsFixed(0),
    );
    final heightController = TextEditingController(
      text: element.size.height.toStringAsFixed(0),
    );
    final textController = TextEditingController(
      text: module.properties['text']?.toString() ?? '',
    );
    final fontSizeController = TextEditingController(
      text: (_numProp(module.properties, 'fontSize') ?? 14.0)
          .toStringAsFixed(0),
    );
    final radiusController = TextEditingController(
      text: (module.type == 'image'
              ? (_numProp(module.properties, 'borderRadius') ??
                  module.borderRadius)
              : module.borderRadius)
          .toStringAsFixed(0),
    );
    final opacityController = TextEditingController(
      text: module.opacity.toStringAsFixed(2),
    );
    final minController = TextEditingController(
      text: (_numProp(module.properties, 'min') ?? 0.0).toStringAsFixed(0),
    );
    final maxController = TextEditingController(
      text: (_numProp(module.properties, 'max') ?? 100.0).toStringAsFixed(0),
    );
    final currentController = TextEditingController(
      // select 的 current 是选项 value（字符串），这里解析失败会回落 0，
      // 且 select 分支实际使用 selectDefaultController，不受影响。
      text: (_numProp(module.properties, 'current') ?? 0.0)
          .toStringAsFixed(0),
    );
    final thicknessController = TextEditingController(
      text: (_numProp(module.properties, 'thickness') ?? 2.0)
          .toStringAsFixed(0),
    );
    final placeholderController = TextEditingController(
      text: module.properties['placeholder']?.toString() ?? '',
    );
    final maxLengthController = TextEditingController(
      text: _intProp(module.properties, 'maxLength')?.toString() ?? '',
    );
    final stepController = TextEditingController(
      text: (_numProp(module.properties, 'step') ?? 1.0).toStringAsFixed(2),
    );
    final optionsController = TextEditingController(
      text: SelectOption.parseList(module.properties['options'])
          .map((option) => option.label == option.value
              ? option.label
              : '${option.label}|${option.value}')
          .join('\n'),
    );
    final historyLimitController = TextEditingController(
      text: (_intProp(module.properties, 'historyLimit') ?? 0) == 0
          ? ''
          : '${_intProp(module.properties, 'historyLimit')}',
    );
    var flowShowUser = module.properties['showUser'] != false;
    var flowShowAssistant = module.properties['showAssistant'] != false;
    // A11-2 富文本开关（message_flow 用）。默认开——
    // LLM 回复里带 Markdown 是常态，关掉会看到满屏的 ** 和 #。
    var flowRichText = module.properties['richText'] != false;
    final dotSizeController = TextEditingController(
      text: (_numProp(module.properties, 'dotSize') ?? 14.0)
          .toStringAsFixed(0),
    );
    final imageUrlController = TextEditingController(
      text: module.properties['url']?.toString() ?? '',
    );
    final imageAssetController = TextEditingController(
      text: module.properties['assetPath']?.toString() ?? '',
    );
    final selectDefaultController = TextEditingController(
      text: module.properties['current']?.toString() ??
          module.properties['defaultValue']?.toString() ??
          '',
    );
    final existingChannel = _dataChannelOf(module);
    final channelLabels = _textLabelCandidates();
    final channelNameController = TextEditingController(
      text: existingChannel?['semanticLabel']?.toString() ?? module.name,
    );
    var channelEnabled = existingChannel != null;
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
    var channelApplyPolicy =
        existingChannel?['llmUpdateApplyPolicy']?.toString() ?? 'confirm';
    var isKeyAction = UISemanticRole.isKeyAction(module);
    var sendsMessage = UISemanticRole.sendsMessage(module);
    var textOverflow = switch (module.properties['overflow']?.toString()) {
      'scroll' => 'scroll',
      'clip' => 'clip',
      _ => 'ellipsis',
    };
    // A11-2 富文本开关（text 用）。默认值随显示模式而定：
    //   滚动模式   → 开。readme / 道具说明几乎都带标题和列表。
    //   其余模式   → 关。这类 text 多被 linker 指向来显示数值或短标签，
    //                解析反而会把「HP<50」误判成 HTML 标签。
    // 作者显式设过就以存档为准，不再按模式推断。
    var textRichText = module.properties.containsKey('richText')
        ? module.properties['richText'] == true
        : textOverflow == 'scroll';
    var textAlignMode = switch (module.properties['textAlign']?.toString()) {
      'left' => 'left',
      'right' => 'right',
      _ => 'center',
    };
    var switchValue = module.properties['value'] != false;
    var indicatorGlow = module.properties['defaultGlow'] == true;
    // A11-2：图片来源。选了头像时路径由运行时提供，作者填的静态值被忽略。
    var imageSource = switch (module.properties['imageSource']?.toString()) {
      AvatarScope.sourceCharacter => AvatarScope.sourceCharacter,
      AvatarScope.sourceUser => AvatarScope.sourceUser,
      _ => AvatarScope.sourceCustom,
    };
    var imageFit = switch (module.properties['fit']?.toString()) {
      'contain' => 'contain',
      'fill' => 'fill',
      _ => 'cover',
    };
    var lineAxis = module.properties['axis']?.toString() == 'vertical'
        ? 'vertical'
        : 'horizontal';
    var lineStyle = module.properties['lineStyle']?.toString() == 'dashed'
        ? 'dashed'
        : 'solid';

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

    Future<void> closeAtomDialog(BuildContext ctx, String value) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ctx.mounted) return;
      Navigator.pop(ctx, value);
    }

    final result = await showDialog<String>(
      context: context,
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: numberField(widthController, '宽度')),
                        const SizedBox(width: 10),
                        Expanded(child: numberField(heightController, '高度')),
                      ],
                    ),
                    if (!_supportsAtomInstanceEditor(type)) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '该原子专属编辑器将在后续批次开放；当前可编辑名称、尺寸与数据通道。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (type == 'text') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        // 长文说明可能很长，给足编辑空间。
                        maxLines: textOverflow == 'scroll' ? 10 : 3,
                        minLines: textOverflow == 'scroll' ? 6 : 1,
                        decoration: const InputDecoration(labelText: '文本内容'),
                      ),
                      const SizedBox(height: 12),
                      numberField(fontSizeController, '字号'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: textOverflow,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '超出显示区时',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'ellipsis', child: Text('省略号截断')),
                          DropdownMenuItem(
                              value: 'clip', child: Text('直接裁切')),
                          DropdownMenuItem(
                              value: 'scroll', child: Text('可滚动（长文说明）')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => textOverflow = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: textAlignMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '对齐方式',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'left', child: Text('左对齐')),
                          DropdownMenuItem(
                              value: 'center', child: Text('居中')),
                          DropdownMenuItem(
                              value: 'right', child: Text('右对齐')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => textAlignMode = v);
                        },
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('富文本渲染',
                            style: TextStyle(fontSize: 13)),
                        subtitle: const Text(
                          '识别 Markdown 标题 / 列表 / 表格与 HTML 排版。'
                          '显示纯数值或短标签时建议关闭。',
                          style: TextStyle(fontSize: 11, height: 1.3),
                        ),
                        value: textRichText,
                        onChanged: (v) =>
                            setDialogState(() => textRichText = v),
                      ),
                      if (textOverflow == 'scroll')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '滚动模式：内容从顶部开始、可选中复制、带滚动条。'
                            '适合角色说明、道具描述等长文；'
                            '内容也可由联动器或数据通道动态注入。'
                            '富文本默认开启——readme 与道具说明几乎都带标题和列表。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF777783),
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                    if (type == 'surface' || type == 'base_box') ...[
                      const SizedBox(height: 12),
                      numberField(radiusController, '圆角'),
                      const SizedBox(height: 12),
                      numberField(opacityController, '透明度', suffix: '0~1'),
                    ],
                    if (type == 'progress') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: numberField(minController, '最小值')),
                          const SizedBox(width: 10),
                          Expanded(child: numberField(maxController, '最大值')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      numberField(currentController, '当前值'),
                    ],
                    if (type == 'button') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        decoration: const InputDecoration(
                          labelText: '按钮文字（可留空）',
                        ),
                      ),
                    ],
                    if (type == 'line') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: lineAxis,
                        decoration: const InputDecoration(labelText: '方向'),
                        items: const [
                          DropdownMenuItem(value: 'horizontal', child: Text('横向')),
                          DropdownMenuItem(value: 'vertical', child: Text('纵向')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => lineAxis = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: lineStyle,
                        decoration: const InputDecoration(labelText: '线型'),
                        items: const [
                          DropdownMenuItem(value: 'solid', child: Text('实线')),
                          DropdownMenuItem(value: 'dashed', child: Text('虚线')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => lineStyle = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      numberField(thicknessController, '粗细'),
                    ],
                    if (type == 'input') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: placeholderController,
                        decoration: const InputDecoration(labelText: '占位提示'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        decoration: const InputDecoration(labelText: '默认文本（可留空）'),
                      ),
                      const SizedBox(height: 12),
                      numberField(maxLengthController, '最大字数（留空不限制）'),
                    ],
                    if (type == 'switch') ...[
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('默认开启', style: TextStyle(fontSize: 13)),
                        value: switchValue,
                        onChanged: (value) =>
                            setDialogState(() => switchValue = value),
                      ),
                    ],
                    if (type == 'slider') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: numberField(minController, '最小值')),
                          const SizedBox(width: 10),
                          Expanded(child: numberField(maxController, '最大值')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: numberField(currentController, '当前值')),
                          const SizedBox(width: 10),
                          Expanded(child: numberField(stepController, '步长')),
                        ],
                      ),
                    ],
                    if (type == 'select') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: optionsController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '选项列表',
                          helperText: '每行一个：显示文本 或 显示文本|值',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: selectDefaultController,
                        decoration: const InputDecoration(
                          labelText: '默认选中值（留空取第一项）',
                        ),
                      ),
                    ],
                    if (type == 'indicator') ...[
                      const SizedBox(height: 12),
                      numberField(dotSizeController, '状态点直径', suffix: '8~28'),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('默认发光', style: TextStyle(fontSize: 13)),
                        value: indicatorGlow,
                        onChanged: (value) =>
                            setDialogState(() => indicatorGlow = value),
                      ),
                    ],
                    if (type == 'message_flow') ...[
                      const SizedBox(height: 12),
                      numberField(
                        historyLimitController,
                        '显示条数（留空显示全部）',
                      ),
                      const SizedBox(height: 12),
                      numberField(fontSizeController, '字号'),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('显示玩家消息',
                            style: TextStyle(fontSize: 13)),
                        value: flowShowUser,
                        onChanged: (v) =>
                            setDialogState(() => flowShowUser = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('显示角色消息',
                            style: TextStyle(fontSize: 13)),
                        value: flowShowAssistant,
                        onChanged: (v) =>
                            setDialogState(() => flowShowAssistant = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('富文本渲染',
                            style: TextStyle(fontSize: 13)),
                        subtitle: const Text(
                          '识别 Markdown 与 HTML。默认开启——'
                          '关闭后 LLM 回复里的 ** 和 # 会原样显示。',
                          style: TextStyle(fontSize: 11, height: 1.3),
                        ),
                        value: flowRichText,
                        onChanged: (v) =>
                            setDialogState(() => flowRichText = v),
                      ),
                      const Text(
                        '窗口内可滚动；新消息自动滚到底，向上翻看历史时不会被拽回。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF777783),
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (type == 'image') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: imageSource,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '图片来源',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: AvatarScope.sourceCustom,
                              child: Text('自定义（下方填写）')),
                          DropdownMenuItem(
                              value: AvatarScope.sourceCharacter,
                              child: Text('角色头像')),
                          DropdownMenuItem(
                              value: AvatarScope.sourceUser,
                              child: Text('用户头像')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => imageSource = value);
                        },
                      ),
                      if (AvatarScope.isDynamic(imageSource))
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '头像路径在运行时才确定，下面的地址与路径会被忽略。'
                            '玩家没设置头像时这里显示为空。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF777783),
                              height: 1.35,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imageUrlController,
                        enabled: !AvatarScope.isDynamic(imageSource),
                        decoration: const InputDecoration(labelText: '网络图片地址（可留空）'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imageAssetController,
                        enabled: !AvatarScope.isDynamic(imageSource),
                        decoration: const InputDecoration(
                          labelText: '本地/内部资产路径（可留空）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: imageFit,
                        decoration: const InputDecoration(labelText: '填充方式'),
                        items: const [
                          DropdownMenuItem(value: 'cover', child: Text('裁剪填满 cover')),
                          DropdownMenuItem(value: 'contain', child: Text('完整显示 contain')),
                          DropdownMenuItem(value: 'fill', child: Text('拉伸铺满 fill')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => imageFit = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      numberField(radiusController, '圆角'),
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
                              '关闭时保存将清除该组件的数据通道配置。开启后可命名语义、选择存放位置与 AI 读写策略。',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777783),
                                height: 1.35,
                              ),
                            )
                          else ...[
                            const Text(
                              '当前仅保存配置，不写入 SessionState、不注入 Prompt。',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777783),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ..._buildDataChannelFormFields(
                              labels: channelLabels,
                              fallbackName: module.name,
                              nameController: channelNameController,
                              semanticSource: channelSource,
                              labelElementId: channelLabelId,
                              targetKind: channelTargetKind,
                              visibility: channelVisibility,
                              llmReadPolicy: channelReadPolicy,
                              llmWritePolicy: channelWritePolicy,
                              applyPolicy: channelApplyPolicy,
                              onSemanticSource: (value) =>
                                  setDialogState(() => channelSource = value),
                              onLabelElementId: (value) =>
                                  setDialogState(() => channelLabelId = value),
                              onTargetKind: (value) => setDialogState(
                                  () => channelTargetKind = value),
                              onVisibility: (value) => setDialogState(
                                  () => channelVisibility = value),
                              onReadPolicy: (value) => setDialogState(
                                  () => channelReadPolicy = value),
                              onWritePolicy: (value) => setDialogState(
                                  () => channelWritePolicy = value),
                              onApplyPolicy: (value) => setDialogState(
                                  () => channelApplyPolicy = value),
                              onNormalizeLabelId: (value) =>
                                  channelLabelId = value,
                              onNameChanged: () => setDialogState(() {}),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '最终语义：${channelPreviewName.isEmpty ? '未命名' : channelPreviewName}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00897B),
                                fontWeight: FontWeight.w700,
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

    if (!mounted) {
      _disposeAtomEditorControllers([
        nameController,
        widthController,
        heightController,
        textController,
        fontSizeController,
        radiusController,
        opacityController,
        minController,
        maxController,
        currentController,
        thicknessController,
        placeholderController,
        maxLengthController,
        stepController,
        optionsController,
        selectDefaultController,
        dotSizeController,
        imageUrlController,
        imageAssetController,
        historyLimitController,
        channelNameController,
      ]);
      return;
    }

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
          final type = currentModule.type;
          if (type == 'text') {
            props['text'] = textController.text;
            props['fontSize'] = readDouble(fontSizeController, 14.0);
            props['overflow'] = textOverflow;
            props['textAlign'] = textAlignMode;
            props['richText'] = textRichText;
          } else if (type == 'progress') {
            props['min'] = readDouble(minController, 0.0);
            props['max'] = readDouble(maxController, 100.0);
            props['current'] = readDouble(currentController, 0.0);
          } else if (type == 'button') {
            props['text'] = textController.text;
            props['showTextOnRuntime'] = textController.text.trim().isNotEmpty;
          } else if (type == 'line') {
            props['axis'] = lineAxis;
            props['lineStyle'] = lineStyle;
            props['thickness'] = readDouble(thicknessController, 2.0);
          } else if (type == 'input') {
            props['placeholder'] = placeholderController.text.trim();
            props['text'] = textController.text;
            final maxLen = int.tryParse(maxLengthController.text.trim());
            if (maxLen == null || maxLen <= 0) {
              props.remove('maxLength');
            } else {
              props['maxLength'] = maxLen;
            }
          } else if (type == 'switch') {
            props['value'] = switchValue;
          } else if (type == 'slider') {
            final minVal = readDouble(minController, 0.0);
            var maxVal = readDouble(maxController, 100.0);
            if (maxVal < minVal) maxVal = minVal;
            props['min'] = minVal;
            props['max'] = maxVal;
            props['current'] = readDouble(currentController, minVal)
                .clamp(minVal, maxVal)
                .toDouble();
            final step = readDouble(stepController, 1.0).abs();
            props['step'] = step <= 0 ? 1.0 : step;
          } else if (type == 'select') {
            final parsed = <Map<String, dynamic>>[];
            for (final rawLine in optionsController.text.split('\n')) {
              final line = rawLine.trim();
              if (line.isEmpty) continue;
              final parts = line.split('|');
              final label = parts.first.trim();
              if (label.isEmpty) continue;
              final value = parts.length > 1 && parts[1].trim().isNotEmpty
                  ? parts[1].trim()
                  : label;
              parsed.add({'label': label, 'value': value});
            }
            if (parsed.isNotEmpty) {
              props['options'] = parsed;
            }
            final options = SelectOption.parseList(props['options']);
            final wanted = selectDefaultController.text.trim();
            final valid = options.any((option) => option.value == wanted);
            props['current'] = valid ? wanted : options.first.value;
            props['defaultValue'] = props['current'];
          } else if (type == 'indicator') {
            props['dotSize'] =
                readDouble(dotSizeController, 14.0).clamp(8.0, 28.0).toDouble();
            props['defaultGlow'] = indicatorGlow;
          } else if (type == 'message_flow') {
            final limit = int.tryParse(historyLimitController.text.trim());
            // 留空或非正数一律视为「显示全部」。
            props['historyLimit'] = (limit == null || limit <= 0) ? 0 : limit;
            props['fontSize'] = readDouble(fontSizeController, 12.5);
            props['showUser'] = flowShowUser;
            props['showAssistant'] = flowShowAssistant;
            props['richText'] = flowRichText;
          } else if (type == 'image') {
            props['imageSource'] = imageSource;
            // 静态地址照常保存：作者切回「自定义」时不用重填。
            props['url'] = imageUrlController.text.trim();
            props['assetPath'] = imageAssetController.text.trim();
            props['fit'] = imageFit;
            props['borderRadius'] =
                readDouble(radiusController, 8.0).clamp(0.0, 999.0).toDouble();
          }

          final nextWidth = readDouble(widthController, current.size.width)
              .clamp(8.0, 2000.0)
              .toDouble();
          final nextHeight = readDouble(heightController, current.size.height)
              .clamp(8.0, 2000.0)
              .toDouble();
          final nextRadius = readDouble(radiusController, currentModule.borderRadius)
              .clamp(0.0, 999.0)
              .toDouble();
          final nextOpacity = readDouble(opacityController, currentModule.opacity)
              .clamp(0.0, 1.0)
              .toDouble();

          if (isKeyAction) {
            props[UISemanticRole.propKey] = true;
          } else {
            props.remove(UISemanticRole.propKey);
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
          if (!channelEnabled || channelName.isEmpty) {
            props.remove('dataChannel');
          } else {
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
              applyPolicy: channelApplyPolicy,
            );
          }

          _elements[index] = current.copyWith(
            size: Size(nextWidth, nextHeight),
            module: currentModule.copyWith(
              name: nameController.text.trim().isEmpty
                  ? currentModule.name
                  : nameController.text.trim(),
              properties: props,
              borderRadius: nextRadius,
              opacity: nextOpacity,
            ),
          );
        });
        _persistAssemblyElements();
      }
    }

    _disposeAtomEditorControllers([
      nameController,
      widthController,
      heightController,
      textController,
      fontSizeController,
      radiusController,
      opacityController,
      minController,
      maxController,
      currentController,
      thicknessController,
      placeholderController,
      maxLengthController,
      stepController,
      optionsController,
      selectDefaultController,
      dotSizeController,
      imageUrlController,
      imageAssetController,
      historyLimitController,
      channelNameController,
    ]);
  }

  void _disposeAtomEditorControllers(List<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Map<String, dynamic>? _dataChannelOf(UIModule? module) {
    final raw = module?.properties['dataChannel'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String _sourcePortForModule(UIModule module) {
    return switch (module.type) {
      'input' => 'text',
      'select' => 'current',
      'switch' => 'value',
      'slider' => 'current',
      'progress' => 'current',
      'text' => 'text',
      _ => 'value',
    };
  }

  String _fieldTypeForModule(UIModule module) {
    return switch (module.type) {
      'slider' || 'progress' => 'number',
      'switch' => 'bool',
      _ => 'string',
    };
  }

  String _dataChannelSummary(Map<String, dynamic> channel) {
    final name = channel['semanticLabel']?.toString().trim();
    final label = name == null || name.isEmpty ? '未命名' : name;
    final read = channel['llmReadPolicy']?.toString() != 'none';
    final write = channel['llmWritePolicy']?.toString() != 'none';
    final targetKind = channel['targetKind']?.toString();
    final pending = targetKind == 'status_field' &&
        (channel['targetId']?.toString().trim().isEmpty ?? true);
    final prefix = switch (targetKind) {
      'status_field' => pending ? '状态待建' : '状态',
      'session_var' => '变量',
      _ => 'UI',
    };
    final ai = read && write
        ? 'AI↕'
        : read
            ? 'AI↑'
            : write
                ? 'AI↓'
                : '';
    return ai.isEmpty ? '$prefix · $label' : '$prefix · $label · $ai';
  }

  Color _dataChannelChipColor(Map<String, dynamic> channel) {
    final pendingStatus = channel['targetKind']?.toString() == 'status_field' &&
        (channel['targetId']?.toString().trim().isEmpty ?? true);
    if (pendingStatus) return const Color(0xFFE65100);
    final read = channel['llmReadPolicy']?.toString() != 'none';
    final write = channel['llmWritePolicy']?.toString() != 'none';
    if (read && write) return const Color(0xFF7E57C2);
    if (read) return const Color(0xFF00897B);
    if (write) return const Color(0xFFE65100);
    return const Color(0xFF546E7A);
  }

  List<UIElement> _textLabelCandidates() {
    return _elements
        .where((element) =>
            !element.isComposite && element.module?.type == 'text')
        .toList();
  }

  String _textValueOf(UIElement textElement) {
    return textElement.module?.properties['text']?.toString().trim() ??
        textElement.module?.name ??
        textElement.id;
  }

  String _resolveDataChannelName({
    required String semanticSource,
    required String manualName,
    required String labelElementId,
    required List<UIElement> labels,
    required String fallbackName,
  }) {
    if (semanticSource == 'text_label' && labelElementId.isNotEmpty) {
      final matched =
          labels.where((candidate) => candidate.id == labelElementId);
      if (matched.isNotEmpty) return _textValueOf(matched.first);
    }
    if (semanticSource == 'component_name') return fallbackName;
    return manualName.trim();
  }

  List<StatusBarField> get _statusFields => widget.statusFields;

  /// 按名称在角色卡状态栏字段里查找匹配项（忽略大小写与首尾空白）。
  StatusBarField? _matchStatusFieldByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final field in _statusFields) {
      if (field.name.trim().toLowerCase() == key) return field;
    }
    return null;
  }

  /// 状态字段解析结果：命中则返回 targetId 与字段类型，未命中则记 pendingName。
  ({String targetId, String? fieldType, bool pending}) _resolveStatusTarget(
    String name,
  ) {
    final matched = _matchStatusFieldByName(name);
    if (matched == null) {
      return (targetId: '', fieldType: null, pending: true);
    }
    return (
      targetId: matched.id,
      fieldType: matched.isNumber ? 'number' : 'string',
      pending: false,
    );
  }

  Map<String, dynamic> _buildDataChannelPayload({
    required String name,
    required String semanticSource,
    required String labelElementId,
    required String sourceComponentId,
    required UIModule module,
    required String targetKind,
    required String visibility,
    required String llmReadPolicy,
    required String llmWritePolicy,
    required String applyPolicy,
  }) {
    final isStatus = targetKind == 'status_field';
    final resolved = isStatus
        ? _resolveStatusTarget(name)
        : (targetId: '', fieldType: null, pending: false);
    return {
      'semanticLabel': name,
      'semanticPath': name,
      'semanticSource': semanticSource,
      'labelElementId': semanticSource == 'text_label' ? labelElementId : '',
      'sourceComponentId': sourceComponentId,
      'sourcePort': _sourcePortForModule(module),
      'targetKind': targetKind,
      // 状态字段命中角色卡定义时预绑定内部 id；未命中保持空并靠 pendingName 等待创建。
      'targetId': resolved.targetId,
      'pendingName': isStatus && !resolved.pending ? '' : name,
      'displayNameSnapshot': name,
      'visibility': visibility,
      'llmReadPolicy': llmReadPolicy,
      'llmWritePolicy': llmWritePolicy,
      'llmUpdateApplyPolicy': applyPolicy,
      // 命中状态字段时以卡片端字段类型为准，避免 UI 组件类型与状态字段类型冲突。
      'fieldType': resolved.fieldType ?? _fieldTypeForModule(module),
    };
  }

  /// 状态字段匹配提示：命中显示已绑定的字段 id 与类型，未命中提示将记为待创建。
  Widget _buildStatusFieldMatchHint(String name) {
    final trimmed = name.trim();
    final matched = _matchStatusFieldByName(trimmed);
    final hasFields = _statusFields.isNotEmpty;
    final String text;
    final Color color;
    if (trimmed.isEmpty) {
      text = '请先填写数据名称，再匹配角色卡状态字段。';
      color = const Color(0xFF777783);
    } else if (matched != null) {
      text = '已匹配状态字段：${matched.name} · id=${matched.id} · '
          '${matched.isNumber ? '数值' : '文本'}';
      color = const Color(0xFF00897B);
    } else if (!hasFields) {
      text = '角色卡当前没有状态栏字段。保存后记为待创建字段「$trimmed」，'
          '需在角色卡状态栏编辑页手动创建同名字段后才会自动绑定。';
      color = const Color(0xFFE65100);
    } else {
      text = '未匹配到同名状态字段。保存后记为待创建字段「$trimmed」，'
          '可用名称：${_statusFields.map((field) => field.name).join(' / ')}';
      color = const Color(0xFFE65100);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: color, height: 1.35),
      ),
    );
  }

  /// 数据通道表单字段，供原子实例编辑器与复合暴露项实例编辑器共用。
  List<Widget> _buildDataChannelFormFields({
    required List<UIElement> labels,
    required String fallbackName,
    required TextEditingController nameController,
    required String semanticSource,
    required String labelElementId,
    required String targetKind,
    required String visibility,
    required String llmReadPolicy,
    required String llmWritePolicy,
    required String applyPolicy,
    required ValueChanged<String> onSemanticSource,
    required ValueChanged<String> onLabelElementId,
    required ValueChanged<String> onTargetKind,
    required ValueChanged<String> onVisibility,
    required ValueChanged<String> onReadPolicy,
    required ValueChanged<String> onWritePolicy,
    required ValueChanged<String> onApplyPolicy,
    required ValueChanged<String> onNormalizeLabelId,
    VoidCallback? onNameChanged,
  }) {
    final hasLabels = labels.isNotEmpty;
    var effectiveLabelId = labelElementId;
    if (semanticSource == 'text_label' && hasLabels) {
      final hasSelected =
          labels.any((candidate) => candidate.id == effectiveLabelId);
      if (!hasSelected) {
        effectiveLabelId = labels.first.id;
        onNormalizeLabelId(effectiveLabelId);
      }
    }

    Widget dropdown(
      String value,
      String label,
      List<DropdownMenuItem<String>> items,
      ValueChanged<String> onChanged,
    ) {
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: (next) {
          if (next == null) return;
          onChanged(next);
        },
      );
    }

    return [
      dropdown(
        semanticSource,
        '数据名称来源',
        const [
          DropdownMenuItem(value: 'manual', child: Text('手动填写')),
          DropdownMenuItem(value: 'text_label', child: Text('使用文本标签')),
          DropdownMenuItem(value: 'component_name', child: Text('使用组件名称')),
        ],
        onSemanticSource,
      ),
      const SizedBox(height: 10),
      if (semanticSource == 'manual')
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '数据名称', isDense: true),
          onChanged: (_) => onNameChanged?.call(),
        )
      else if (semanticSource == 'text_label')
        hasLabels
            ? dropdown(
                effectiveLabelId,
                '标签文本',
                labels
                    .map(
                      (label) => DropdownMenuItem(
                        value: label.id,
                        child: Text(
                          _textValueOf(label),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onLabelElementId,
              )
            : const Text(
                '当前页面没有可用文本标签，请先放置 Text 或改为手动填写。',
                style: TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
              )
      else
        Text(
          '将使用组件名称：$fallbackName',
          style: const TextStyle(fontSize: 12, color: Color(0xFF555562)),
        ),
      const SizedBox(height: 10),
      dropdown(
        targetKind,
        '保存到',
        const [
          DropdownMenuItem(value: 'local_ui_state', child: Text('UI 内部状态')),
          DropdownMenuItem(value: 'session_var', child: Text('会话变量')),
          DropdownMenuItem(value: 'status_field', child: Text('状态字段')),
        ],
        onTargetKind,
      ),
      if (targetKind == 'status_field') ...[
        const SizedBox(height: 8),
        _buildStatusFieldMatchHint(
          _resolveDataChannelName(
            semanticSource: semanticSource,
            manualName: nameController.text,
            labelElementId: effectiveLabelId,
            labels: labels,
            fallbackName: fallbackName,
          ),
        ),
      ],
      const SizedBox(height: 10),
      dropdown(
        visibility,
        '玩家可见性',
        const [
          DropdownMenuItem(value: 'ui_only', child: Text('只控制界面')),
          DropdownMenuItem(value: 'player_visible', child: Text('玩家可见')),
          DropdownMenuItem(value: 'system_hidden', child: Text('系统隐藏')),
        ],
        onVisibility,
      ),
      const SizedBox(height: 10),
      dropdown(
        llmReadPolicy,
        '发送当前值给 AI',
        const [
          DropdownMenuItem(value: 'none', child: Text('不发送')),
          DropdownMenuItem(value: 'prompt', child: Text('发送到 Prompt')),
          DropdownMenuItem(value: 'hidden_context', child: Text('隐藏上下文')),
        ],
        onReadPolicy,
      ),
      const SizedBox(height: 10),
      dropdown(
        llmWritePolicy,
        '允许 AI 更新',
        const [
          DropdownMenuItem(value: 'none', child: Text('不允许')),
          DropdownMenuItem(value: 'suggest_delta', child: Text('建议增量 +N/-N')),
          DropdownMenuItem(value: 'suggest_replace', child: Text('建议替换新值')),
        ],
        onWritePolicy,
      ),
      const SizedBox(height: 10),
      dropdown(
        applyPolicy,
        'AI 更新应用方式',
        const [
          DropdownMenuItem(value: 'confirm', child: Text('用户确认后应用')),
          DropdownMenuItem(value: 'auto_low_risk', child: Text('低风险自动应用')),
          DropdownMenuItem(value: 'never', child: Text('永不应用')),
        ],
        onApplyPolicy,
      ),
    ];
  }

  void _createPage({required String type}) {
    _syncCanvasStateIntoActivePage();
    final pageType = type == 'overlay' ? 'overlay' : 'base';
    if (pageType == 'overlay' && _pageDepth(_activePage) >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已达到最大叠加深度（3 层）')),
      );
      return;
    }
    final parentPageId = pageType == 'overlay' ? _activePage.id : null;
    final siblingCount = _pages.where((page) => page.parentPageId == parentPageId).length;
    final page = AssemblyPage(
      id: 'page_${DateTime.now().millisecondsSinceEpoch}_${_pages.length}',
      name: pageType == 'overlay'
          ? '叠加层 ${siblingCount + 1}'
          : '页面 ${_pages.where((candidate) => candidate.isBase).length + 1}',
      type: pageType,
      parentPageId: parentPageId,
      sortOrder: siblingCount,
    );
    _pages.add(page);
    _activePageId = page.id;
    _elements.clear();
    _setupEventBusListener();
    _persistAssemblyElements();
    setState(() {});
  }

  Future<void> _renamePage(AssemblyPage page) async {
    if (_isRootBasePage(page)) return;
    final controller = TextEditingController(text: page.name);
    final renamed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名页面'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '页面名称'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(const Duration(milliseconds: 16));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(const Duration(milliseconds: 16));
              if (!ctx.mounted) return;
              Navigator.pop(ctx, name);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || renamed == null || renamed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _pages.indexWhere((candidate) => candidate.id == page.id);
      if (index != -1) {
        setState(() => _pages[index].name = renamed);
        _persistAssemblyElements();
      }
    });
  }

  void _reorderPageGroup(
    String? parentPageId,
    int oldIndex,
    int newIndex, {
    bool excludeRoot = false,
  }) {
    final siblings = _directChildPages(parentPageId)
        .where((page) => !excludeRoot || !_isRootBasePage(page))
        .toList();
    if (oldIndex < 0 || oldIndex >= siblings.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= siblings.length) return;
    final moved = siblings.removeAt(oldIndex);
    siblings.insert(newIndex, moved);
    for (var i = 0; i < siblings.length; i++) {
      final index = _pages.indexWhere((page) => page.id == siblings[i].id);
      if (index != -1) _pages[index].sortOrder = excludeRoot ? i + 1 : i;
    }
    setState(() {});
    _persistAssemblyElements();
  }

  bool _isDescendantPage(String pageId, String ancestorId) {
    var currentId = pageId;
    final visited = <String>{};
    while (visited.add(currentId)) {
      final index = _pages.indexWhere((page) => page.id == currentId);
      if (index == -1) return false;
      final parentId = _pages[index].parentPageId;
      if (parentId == null || parentId.isEmpty) return false;
      if (parentId == ancestorId) return true;
      currentId = parentId;
    }
    return false;
  }

  List<AssemblyPage> _reparentCandidatesForPage(AssemblyPage page) {
    final depth = _pageDepth(page);
    if (depth == 0) return const <AssemblyPage>[];
    final candidates = <AssemblyPage>[];
    for (final candidate in _pages) {
      if (candidate.id == page.id) continue;
      if (_isDescendantPage(candidate.id, page.id)) continue;
      final candidateDepth = _pageDepth(candidate);
      if (depth == 1) {
        if (candidateDepth <= 1) candidates.add(candidate);
      } else {
        if (candidate.isOverlay && candidateDepth == 1) candidates.add(candidate);
      }
    }
    candidates.sort((a, b) {
      final depthCompare = _pageDepth(a).compareTo(_pageDepth(b));
      if (depthCompare != 0) return depthCompare;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return candidates;
  }

  Future<void> _showReparentPageDialog(AssemblyPage page) async {
    final candidates = _reparentCandidatesForPage(page);
    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前没有可用的目标父层')),
        );
      }
      return;
    }
    final selectedParentId = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择新的父层级'),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              final isBase = candidate.isBase;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                tileColor: const Color(0xFFF6F6F9),
                leading: Icon(
                  isBase ? Icons.crop_square_rounded : Icons.layers_outlined,
                  size: 18,
                  color: isBase
                      ? const Color(0xFF651FFF)
                      : const Color(0xFF546E7A),
                ),
                title: Text(
                  _displayPageName(candidate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  isBase ? '平级页' : '叠加页',
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () => Navigator.pop(ctx, candidate.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted || selectedParentId == null) return;
    final pageIndex = _pages.indexWhere((candidate) => candidate.id == page.id);
    if (pageIndex == -1) return;
    final oldParentId = _pages[pageIndex].parentPageId;
    final newParentId = selectedParentId;
    final newSiblingCount = _pages.where((p) => p.parentPageId == newParentId).length;
    _pages[pageIndex].parentPageId = newParentId;
    _pages[pageIndex].sortOrder = newSiblingCount;

    final oldSiblings = _pages
        .where((p) => p.parentPageId == oldParentId && p.id != page.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < oldSiblings.length; i++) {
      final index = _pages.indexWhere((candidate) => candidate.id == oldSiblings[i].id);
      if (index != -1) _pages[index].sortOrder = i;
    }

    setState(() {});
    _persistAssemblyElements();
  }

  void _scheduleInitialViewportCenter() {
    if (_didInitialViewportCenter) return;
    _didInitialViewportCenter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final centeredX = math.max(0.0, (size.width - _pcbSize.width) / 2);
      final centeredY = math.max(0.0, (size.height - _pcbSize.height) / 2);
      setState(() {
        _canvasOffset = Offset(centeredX, centeredY);
        _pcbOffset = Offset.zero;
      });
    });
  }

  void _setupEventBusListener() {
    LinkerService.initEventBusListener(_elements, () {
      if (!mounted) return;
      _persistAssemblyElements();
      setState(() {});
    });
  }

  void _persistAssemblyElements() {
    _sanitizeActivePropertyOverrides();
    _syncCanvasStateIntoActivePage();
    _info.elementsJson = jsonEncode(
      _elements.map((element) => element.toJson()).toList(),
    );
    _info.pagesJson = jsonEncode(
      _orderedPages().map((page) => page.toJson()).toList(),
    );
    _info.pcbWidth = _pcbSize.width;
    _info.pcbHeight = _pcbSize.height;
    _info.pcbColorValue = _pcbColor.toARGB32();
    _info.pcbRounded = _pcbRounded;
  }

  String _exportAssemblyInfoJson() {
    _persistAssemblyElements();
    return _info.toJsonString();
  }

  void _enterRuntimePreview() {
    _persistAssemblyElements();
    setState(() {
      _runtimePreviewInfo = UIAssemblyInfo.fromJsonString(_info.toJsonString());
      _runtimePreviewPageId = _activePage.id;
      _runtimePreviewMode = true;
      _showAssetDrawer = false;
      _showLayerPanel = false;
      _selectedCompositeId = null;
    });
  }

  void _exitRuntimePreview() {
    if (!_runtimePreviewMode) return;
    setState(() {
      _runtimePreviewMode = false;
      _runtimePreviewInfo = null;
      _runtimePreviewPageId = null;
    });
  }

  String _generateElementId() {
    _generatedElementIdSeed++;
    return 'elem_${DateTime.now().microsecondsSinceEpoch}_$_generatedElementIdSeed';
  }

  dynamic _deepCloneValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key, _deepCloneValue(entry)),
      );
    }
    if (value is List) {
      return value.map(_deepCloneValue).toList();
    }
    return value;
  }

  UIComposite _instantiateComposite(UIComposite template) {
    final idMap = <String, String>{};

    void collectIds(List<UIElement> elements) {
      for (final element in elements) {
        idMap.putIfAbsent(element.id, _generateElementId);
        if (element.isComposite && element.composite != null) {
          collectIds(element.composite!.children);
        }
      }
    }

    Set<String> collectElementIds(List<UIElement> elements) {
      final ids = <String>{};
      void visit(List<UIElement> nodes) {
        for (final node in nodes) {
          ids.add(node.id);
          if (node.isComposite && node.composite != null) {
            visit(node.composite!.children);
          }
        }
      }

      visit(elements);
      return ids;
    }

    Map<String, dynamic> remapModuleProperties(
      String type,
      Map<String, dynamic> original,
    ) {
      final props = Map<String, dynamic>.from(_deepCloneValue(original) as Map);
      if (type == 'linker' && props['linker'] is Map) {
        final linkerData =
            Map<String, dynamic>.from(props['linker'] as Map);
        final sourceId = linkerData['sourceModuleId']?.toString();
        final targetId = linkerData['targetModuleId']?.toString();
        if (sourceId != null && idMap.containsKey(sourceId)) {
          linkerData['sourceModuleId'] = idMap[sourceId];
        }
        if (targetId != null && idMap.containsKey(targetId)) {
          linkerData['targetModuleId'] = idMap[targetId];
        }
        props['linker'] = linkerData;
      }
      return props;
    }

    UIElement cloneElement(UIElement element) {
      final newId = idMap[element.id] ?? _generateElementId();
      final clonedModule = element.module?.copyWith(
        id: newId,
        properties: remapModuleProperties(
          element.module!.type,
          element.module!.properties,
        ),
        linkedSources: element.module!.linkedSources
            .map((sourceId) => idMap[sourceId] ?? sourceId)
            .toList(),
      );

      UIComposite? clonedComposite;
      if (element.isComposite && element.composite != null) {
        final clonedChildren =
            element.composite!.children.map(cloneElement).toList();
        final validIds = collectElementIds(clonedChildren);
        final clonedPorts = element.composite!.exposedPorts
            ?.map(
              (port) => port.copyWith(
                elementId: idMap[port.elementId] ?? port.elementId,
              ),
            )
            .where((port) => validIds.contains(port.elementId))
            .toList();
        clonedComposite = element.composite!.copyWith(
          children: clonedChildren,
          exposedPorts: clonedPorts == null || clonedPorts.isEmpty
              ? null
              : clonedPorts,
        );
      }

      return UIElement(
        id: newId,
        isComposite: element.isComposite,
        module: clonedModule,
        composite: clonedComposite,
        offset: element.offset,
        size: element.size,
        layerIndex: element.layerIndex,
        parentSurfaceId: element.parentSurfaceId == null
            ? null
            : idMap[element.parentSurfaceId!],
        rotation: element.rotation,
        layoutLocked: element.layoutLocked,
        sealed: element.sealed,
      );
    }

    collectIds(template.children);
    final clonedChildren = template.children.map(cloneElement).toList();
    final validIds = collectElementIds(clonedChildren);
    final clonedPorts = template.exposedPorts
        ?.map(
          (port) => port.copyWith(
            elementId: idMap[port.elementId] ?? port.elementId,
          ),
        )
        .where((port) => validIds.contains(port.elementId))
        .toList();
    return template.copyWith(
      children: clonedChildren,
      exposedPorts: clonedPorts == null || clonedPorts.isEmpty
          ? null
          : clonedPorts,
    );
  }

  bool _isGlobalPositionInsideCanvas(Offset globalPosition, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  bool _requiresPcbContainment(UIElement element) => element.isComposite;

  Rect get _pcbLocalRect => Rect.fromLTWH(
    _pcbOffset.dx,
    _pcbOffset.dy,
    _pcbSize.width,
    _pcbSize.height,
  );

  double _clampPcbHeight(double value) =>
      value.clamp(_pcbMinHeight, _pcbMaxHeight).toDouble();

  /// 宽度上限按 mode 取：伴生必须塞进消息气泡，比其余 mode 更窄。
  double get _pcbMaxWidthForMode => UIAssemblyInfo.maxPcbWidthFor(_info.mode);

  double _clampPcbWidth(double value) =>
      value.clamp(_pcbMinWidth, _pcbMaxWidthForMode).toDouble();

  Offset _rotatePoint(Offset point, Offset center, double degrees) {
    if (degrees == 0.0) return point;
    final radians = degrees * math.pi / 180.0;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * math.cos(radians) - dy * math.sin(radians),
      center.dy + dx * math.sin(radians) + dy * math.cos(radians),
    );
  }

  bool _isElementInsidePcb(UIElement element) {
    if (!_requiresPcbContainment(element)) return true;
    final pcbRect = _pcbLocalRect;
    bool containsInclusive(Offset point) {
      const epsilon = 0.001;
      return point.dx >= pcbRect.left - epsilon &&
          point.dx <= pcbRect.right + epsilon &&
          point.dy >= pcbRect.top - epsilon &&
          point.dy <= pcbRect.bottom + epsilon;
    }

    final center = Offset(
      _pcbOffset.dx + element.offset.dx + element.size.width / 2,
      _pcbOffset.dy + element.offset.dy + element.size.height / 2,
    );
    final corners = <Offset>[
      Offset(_pcbOffset.dx + element.offset.dx, _pcbOffset.dy + element.offset.dy),
      Offset(
        _pcbOffset.dx + element.offset.dx + element.size.width,
        _pcbOffset.dy + element.offset.dy,
      ),
      Offset(
        _pcbOffset.dx + element.offset.dx + element.size.width,
        _pcbOffset.dy + element.offset.dy + element.size.height,
      ),
      Offset(
        _pcbOffset.dx + element.offset.dx,
        _pcbOffset.dy + element.offset.dy + element.size.height,
      ),
    ].map((point) => _rotatePoint(point, center, element.rotation)).toList();
    return corners.every(containsInclusive);
  }

  bool get _hasIllegalPcbElements =>
      _elements.any((element) => !_isElementInsidePcb(element));

  int get _illegalPcbElementCount =>
      _elements.where((element) => !_isElementInsidePcb(element)).length;

  int get _totalIllegalPcbElementCount {
    _syncCanvasStateIntoActivePage();
    return _pages.fold<int>(
      0,
      (sum, page) =>
          sum + page.elements.where((element) => !_isElementInsidePcb(element)).length,
    );
  }

  Offset _clampCompositeOffsetInsidePcb(Offset desired, Size size) {
    final minX = 0.0;
    final minY = 0.0;
    final maxX = math.max(0.0, _pcbSize.width - size.width);
    final maxY = math.max(0.0, _pcbSize.height - size.height);
    return Offset(
      desired.dx.clamp(minX, maxX).toDouble(),
      desired.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _applyPlacementConstraints(UIElement prototype, Offset desired) {
    if (!_requiresPcbContainment(prototype)) return desired;
    return _clampCompositeOffsetInsidePcb(desired, prototype.size);
  }

  bool _validateAssemblyBeforeExit() {
    final illegalCount = _totalIllegalPcbElementCount;
    if (illegalCount == 0) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '当前有 $illegalCount 个复合组件超出 PCB 边界，请先移回可视区域后再保存。',
        ),
        backgroundColor: const Color(0xFF8B4B4B),
      ),
    );
    return false;
  }

  Future<void> _handleBackNavigation() async {
    if (_validateAssemblyBeforeExit()) {
      if (mounted) Navigator.pop(context, _exportAssemblyInfoJson());
      return;
    }
    if (!mounted) return;
    final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('存在未保存的非法布局'),
            content: const Text(
              '当前有复合组件超出 PCB 边界，无法保存。要放弃本次修改并返回吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B4B4B),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃并返回'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) {
      Navigator.pop(context);
    }
  }

  void _startLibraryPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    _activePlacement?.isLibraryDragging.value = false;
    payload.longPressOrigin = globalPosition;
    payload.lastPointerGlobalPosition = globalPosition;
    payload.spawnedElementId = null;
    payload.isLibraryDragging.value = true;
    HapticFeedback.selectionClick();
    _activePlacement = payload;
  }

  void _handlePlacementPointerMove(PointerMoveEvent event, BuildContext context) {
    final payload = _activePlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;

    if (payload.spawnedElementId == null) {
      final origin = payload.longPressOrigin;
      if (origin != null) {
        if (payload.verticalDragToSpawn) {
          final upwardDy = origin.dy - event.position.dy;
          if (upwardDy < _dragThreshold) return;
        } else {
          final dx = (event.position.dx - origin.dx).abs();
          if (dx < _dragThreshold) return;
        }
      }
    }

    if (_isGlobalPositionInsideCanvas(event.position, context)) {
      if (payload.spawnedElementId == null) {
        _beginDragPlacement(payload, event.position, context);
      } else {
        _updateDragPlacement(payload, event.position, context);
      }
    }
  }

  void _finishPlacementPointer(PointerEvent event, BuildContext context) {
    final payload = _activePlacement;
    if (payload == null || payload.pointerId != event.pointer) return;
    payload.lastPointerGlobalPosition = event.position;
    if (payload.spawnedElementId != null) {
      _finishDragPlacement(payload, event.position, context);
    }
    payload.isLibraryDragging.value = false;
    _activePlacement = null;
  }

  bool _isSurfaceModule(UIModule? module) {
    final type = module?.type;
    return type == 'surface' || type == 'surface_art' || type == 'primitive_art' || type == 'base_box';
  }

  bool _activePageHasOverlayContainerSurface() {
    if (!_activePage.isOverlay) return true;
    return _elements.any(
      (element) => !element.isComposite && _isSurfaceModule(element.module),
    );
  }

  UIModule _prepareModuleForAssemblyPlacement(UIModule template, String id) {
    final module = _instantiateModule(template, id);
    if (_activePage.isOverlay &&
        _isSurfaceModule(module) &&
        !_activePageHasOverlayContainerSurface()) {
      final props = Map<String, dynamic>.from(_deepCloneValue(module.properties) as Map);
      props['is_overlay_container'] = true;
      return module.copyWith(properties: props);
    }
    return module;
  }

  void _beginDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    if (payload.spawnedElementId != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final composite = payload.composite;
    final module = payload.module;
    if (composite == null && module == null) return;
    final size = composite != null
        ? _compositeDefaultSize(composite)
        : _moduleDefaultSize(module!);
    final local = box.globalToLocal(globalPosition) -
        _canvasOffset -
        _pcbOffset -
        Offset(size.width / 2, size.height / 2);
    final id = _generateElementId();
    final prototype = composite != null
        ? UIElement(
            id: id,
            isComposite: true,
            composite: _instantiateComposite(composite),
            offset: local,
            size: size,
            layerIndex: 0,
          )
        : UIElement(
            id: id,
            isComposite: false,
            module: _prepareModuleForAssemblyPlacement(module!, id),
            offset: local,
            size: size,
            layerIndex: 0,
          );
    setState(() {
      _elements.add(
        prototype.copyWith(
          offset: _applyPlacementConstraints(prototype, local),
        ),
      );
      payload.spawnedElementId = id;
    });
  }

  void _updateDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    final id = payload.spawnedElementId;
    if (id == null) { _beginDragPlacement(payload, globalPosition, context); return; }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final i = _elements.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final sz = _elements[i].size;
    final local = box.globalToLocal(globalPosition) -
        _canvasOffset -
        _pcbOffset -
        Offset(sz.width / 2, sz.height / 2);
    final element = _elements[i];
    setState(() {
      _elements[i] = element.copyWith(
        offset: _applyPlacementConstraints(element, local),
      );
    });
  }

  void _finishDragPlacement(_AssemblyDragPayload payload, Offset globalPosition, BuildContext context) {
    _updateDragPlacement(payload, globalPosition, context);
    _persistAssemblyElements();
  }

  UIModule _instantiateModule(UIModule template, String id) {
    return template.copyWith(
      id: id,
      properties: Map<String, dynamic>.from(
        _deepCloneValue(template.properties) as Map,
      ),
    );
  }

  Size _moduleDefaultSize(UIModule module) {
    return switch (module.type) {
      _pageRouterType => const Size(124, 56),
      'linker' => const Size(132, 44),
      'button' => const Size(88, 32),
      'text' => const Size(96, 28),
      'progress' => const Size(120, 16),
      'slider' => const Size(150, 34),
      'input' => const Size(140, 34),
      'switch' => const Size(100, 36),
      'select' => const Size(140, 34),
      'indicator' => const Size(36, 36),
      'image' => const Size(80, 80),
      'line' => const Size(120, 20),
      'surface' => const Size(160, 80),
      'base_box' => const Size(160, 80),
      'math_node' => const Size(120, 56),
      'timer' => const Size(112, 52),
      _ => const Size(96, 48),
    };
  }

  Size _compositeDefaultSize(UIComposite c) {
    if (c.children.isEmpty) return const Size(200, 120);
    for (final child in c.children) {
      if (!child.isComposite &&
          child.module?.properties['is_container_boundary'] == true) {
        return child.size;
      }
    }
    double mx = 0, my = 0;
    for (final ch in c.children) {
      final cx = ch.offset.dx + ch.size.width;
      final cy = ch.offset.dy + ch.size.height;
      if (cx > mx) mx = cx;
      if (cy > my) my = cy;
    }
    return Size(mx + 20, my + 20);
  }
}
