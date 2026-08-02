part of '../character_assembly_page.dart';

/// 跨 mixin 共享的常量。
///
/// ## 为什么放在顶层而不是某个 mixin 里
///
/// **静态成员不参与 mixin 继承**。`static const` 挂在 `_AssemblyLogic`
/// 上时，`_AssemblyCanvasLogic` 即便 `on _AssemblyLogic` 也**看不见它**
/// ——裸写 `_dragThreshold` 会报 `Undefined name`，
/// 写 `_AssemblyLogic._dragThreshold` 又只在同库内且名字对得上才行。
///
/// 拆分 `logic.dart` 时这批常量被多个分组同时引用，
/// 挂在任何一个 mixin 上都会让其余分组编译不过。
/// 提到库顶层后，所有 part 文件都能直接用。
///
/// 例外：`kResizeHandlePadding` / `kLinkerPortHotZone` /
/// `kMinCompositeScale` 仍留在 `_AssemblyLogic` 里，
/// 因为 `character_assembly_page.dart` 的 build 方法是以
/// `_AssemblyLogic.kXxx` 形式点名访问的。

const Size _defaultPcbSize = Size(360, 800);
const double _pcbMinHeight = UIAssemblyInfo.minPcbHeight;
const double _pcbMaxHeight = UIAssemblyInfo.maxPcbHeight;
const double _pcbMinWidth = UIAssemblyInfo.minPcbWidth;

/// 从资产抽屉拖出多远才算「开始放置」。
const double _dragThreshold = 24.0;

const String _pageRouterType = 'page_router';

mixin _AssemblyLogic on State<CharacterAssemblyPage> {
  /// 当前正在编辑哪个开场分支（0 = 主支路）。
  ///
  /// 放在依赖链根部而非 `_AssemblyBranchLogic`：
  /// `_persistAssemblyElements`（本文件）要靠它决定把画布内容
  /// 写进 `pagesJson` 还是 `branchVariants`，
  /// 而那个 mixin 在依赖链下游，上游看不到它的成员。
  int _editingBranch = 0;

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
  /// A14-1d：精确位移方向键是否展开。
  /// 跟着选中元素走——换个元素就收起，避免对着别的组件误按。
  bool _showNudgePad = false;
  bool _showAssetDrawer = false;
  String _activeAssetCategory = 'logic';
  int _generatedElementIdSeed = 0;
  late Size _pcbSize;
  late Offset _pcbOffset;
  late Color _pcbColor;
  late double _pcbRadius;
  bool _didInitialViewportCenter = false;
  double _pcbResizeStartHeight = _defaultPcbSize.height;
  double _pcbResizeStartWidth = _defaultPcbSize.width;
  double _pcbResizeStartGlobalDy = 0.0;
  double _pcbResizeStartGlobalDx = 0.0;
  // 拖放状态
  _AssemblyDragPayload? _activePlacement;
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
          // 不再放 'text'：button 是纯热区，运行期不显形。
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
    _pcbRadius = info.pcbRadius;
    _pcbOffset = Offset.zero;
    _canvasOffset = Offset.zero;
    _restoreAssemblyPages();
    _reconcileStatusChannelBindings();
    // 补绑之后再同步初始值：顺序不能反。
    // 反了的话本次刚补上 targetId 的通道拿不到字段值，
    // 要等下次进页面才同步，表现为「改了状态栏，回 UI 没变，再进一次才变」。
    _syncStatusFieldInitialValues();
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
    _flattenNestedOverlayPages();
    _activePageId = _pages.first.id;
    _loadActivePageState();
  }
  /// 把嵌套的叠加页拍平到它所属的平级页下。
  ///
  /// 叠加层不能变成子叠加层（用户明确规则），但早期实现允许嵌套建到 3 层。
  /// 这不是「兼容老卡」——是**修正由错误实现产生的非法结构**：
  /// 留着的话 `_canDropPageInto` 会拒绝一切落点，那些页面卡在原地拖不动。
  ///
  /// 找不到平级祖先的（父级悬空）挂到根平级页，不丢页面。
  void _flattenNestedOverlayPages() {
    if (_pages.isEmpty) return;
    final root = _rootBasePage;
    var changed = false;
    for (final page in _pages) {
      if (!page.isOverlay) continue;
      final parent = page.parentPageId == null
          ? null
          : _pageById(page.parentPageId!);
      if (parent != null && parent.isBase) continue;
      page.parentPageId = (_baseAncestorOf(page) ?? root).id;
      changed = true;
    }
    if (!changed) return;
    // 拍平后同一父级下可能出现重复 sortOrder，重排一遍。
    for (final base in _pages.where((p) => p.isBase)) {
      final children = _pages
          .where((p) => p.parentPageId == base.id)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (var i = 0; i < children.length; i++) {
        children[i].sortOrder = i;
      }
    }
  }
  /// 把状态栏字段的初始值同步到绑定它的组件上。
  ///
  /// 用户要的效果：「绑定好双方后，无论修改谁的初始值，
  /// 保存切换到另一个页面也会跟着同步，采用一样的数据。」
  ///
  /// 这一侧负责「状态栏 → UI」。反向的「UI → 状态栏」发生在
  /// 状态栏编辑页新建字段时（见 `collectPendingStatusBindings`）。
  ///
  /// 只同步**已绑定**的通道；预绑定（targetId 为空）保持组件自己的值，
  /// 因为那个值正是将来创建字段时要用的初始值。
  void _syncStatusFieldInitialValues() {
    if (_statusFields.isEmpty) return;
    var changed = false;
    for (final page in _pages) {
      if (DataChannelService.applyStatusFieldInitialValues(
        page.elements,
        _statusFields,
      )) {
        changed = true;
      }
      // 复合组件暴露项的通道配置在 propertyOverrides 里，不在 elements 上。
      // 首版只遍历 elements，复合件里的绑定完全没被同步到——
      // 表现就是「数值和上下限没跟着变」。
      if (DataChannelService.applyStatusFieldsToOverrides(
        page.propertyOverrides,
        _statusFields,
      )) {
        changed = true;
      }
    }
    // 同步完成后记快照，作为反写的基线。
    //
    // **必须在同步之后记**：在之前记的话，同步本身造成的改动
    // 会被当成「作者改的」，退出时又原样写回状态栏，
    // 形成「打开就同步、退出就回写」的自激循环。
    _statusFieldBaseline
      ..clear()
      ..addAll(_collectStatusFieldSnapshot());

    if (changed) {
      // 只把结果读进画布，**不调 _persistAssemblyElements**。
      //
      // 那个函数第一步是 _pushHistory()：在 initState 阶段调用会往
      // 撤销栈里塞一条「未同步」的快照，作者一进页面点撤销就把
      // 刚同步好的值退回去了。
      //
      // 也不需要在这里持久化——_pages 已经是最新的，
      // 退出时 _exportAssemblyInfoJson 会统一序列化。
      _loadActivePageState();
    }
  }
  /// 把通道绑定的状态字段同步进实例编辑器的各个输入框。
  ///
  /// **必须覆盖全部承载值的 controller**，不能只管数值那几个：
  /// 保存时 `props['text'] = textController.text` 之类的赋值
  /// 会用打开对话框那一刻的旧值回写，把同步结果整个盖掉。
  /// 数值型漏了会看到「量程不变」，文本型漏了会看到「文字不变」，
  /// 是同一个「双写覆盖」病根的不同表现。
  ///
  /// 返回是否真的改动了什么，调用方据此决定要不要提示。
  bool _fillControllersFromStatusField({
    required Map<String, dynamic>? channel,
    required String moduleType,
    required RangeControllers? range,
    required TextEditingController? content,
    required void Function(bool) onSwitchValue,
  }) {
    final fieldId = DataChannelService.statusFieldIdOfChannel(channel);
    if (fieldId == null) return false;
    final matched = _statusFields.where((f) => f.id == fieldId);
    if (matched.isEmpty) return false;
    final field = matched.first;
    final raw = field.initialValue.trim();

    if (field.isNumber) {
      // 数值型：量程 + 当前值。没有量程概念的类型（text）只写内容。
      final min = field.minValue ?? 0.0;
      final max = field.maxValue ?? 100.0;
      if (range != null) {
        range.min.text = min.toStringAsFixed(0);
        range.max.text = max.toStringAsFixed(0);
        final parsed = double.tryParse(raw);
        if (parsed != null) {
          range.current.text = parsed.clamp(min, max).toStringAsFixed(0);
        }
      }
      // 数值字段绑到 text 组件上是合法的（用文字显示数值）。
      if (moduleType == 'text' && double.tryParse(raw) != null) {
        content?.text = raw;
      }
      return range != null || moduleType == 'text';
    }

    // 文本型：写进该类型承载内容的那个 controller。
    if (raw.isEmpty) return false;
    switch (moduleType) {
      case 'text':
      case 'input':
      case 'select':
        // select 填进去但**不保证生效**：保存时有一道
        // `valid ? wanted : options.first.value` 的校验，
        // 状态字段的值不在选项列表里就会被打回第一项。
        // 这是 select 的固有约束（当前值必须是合法选项），
        // 不是同步的 bug——作者需要自己保证选项覆盖了字段可能的取值。
        if (content == null) return false;
        content.text = raw;
        return true;
      case 'switch':
        onSwitchValue(raw == 'true' || raw == '1' || raw == '开启');
        return true;
      default:
        return false;
    }
  }
  /// 单个元素刚建立/变更状态字段绑定后的即时同步。
  ///
  /// 与 `_syncStatusFieldInitialValues`（进页面时全量跑）互补：
  /// 那个只在 initState 跑一次，而绑定往往是在页面运行中才建立的。
  ///
  /// 同步后**必须登记基线**，否则这个新绑定在反写时会命中
  /// `base == null` 分支，被当成「作者改的」——
  /// 结果是刚同步进来的值又被写回状态栏，把作者设的初始值冲掉。
  void _syncStatusFieldForElement(UIElement element) {
    if (_statusFields.isEmpty) return;
    final module = element.module;
    if (module == null) return;
    final fieldId = DataChannelService.boundStatusFieldId(module);
    if (fieldId == null) return;

    DataChannelService.applyStatusFieldInitialValues(
      [element],
      _statusFields,
    );
    // 用同步后的值刷新基线，覆盖进页面时记的旧条目。
    _statusFieldBaseline.addAll(
      DataChannelService.snapshotBoundValues([element]),
    );
  }
  /// 覆写项（复合件暴露项）刚建立绑定后的即时同步。
  void _syncStatusFieldForOverride(PropertyOverride override) {
    if (_statusFields.isEmpty) return;
    final fieldId =
        DataChannelService.statusFieldIdOfChannel(override.overrides['dataChannel']);
    if (fieldId == null) return;

    DataChannelService.applyStatusFieldsToOverrides(
      [override],
      _statusFields,
    );
    _statusFieldBaseline.addAll(
      DataChannelService.snapshotBoundValues(const [], [override]),
    );
  }
  /// 反写基线：进入编辑器（且完成一次同步）那一刻的值与量程。
  final Map<String, StatusFieldSnapshot> _statusFieldBaseline = {};

  Map<String, StatusFieldSnapshot> _collectStatusFieldSnapshot() {
    final merged = <String, StatusFieldSnapshot>{};
    for (final page in _pages) {
      merged.addAll(DataChannelService.snapshotBoundValues(
        page.elements,
        page.propertyOverrides,
      ));
    }
    return merged;
  }
  /// 把作者在 UI 里改过的初始值与量程写回状态栏字段。
  ///
  /// 返回被改动过的字段副本；没有改动时返回 null，
  /// 调用方据此决定要不要把结果带回上一页。
  ///
  /// 只回写与基线有差异的组件——没碰过的一律跳过。
  List<StatusBarField>? _buildStatusFieldWriteBack() {
    if (_statusFields.isEmpty) return null;
    _syncCanvasStateIntoActivePage();

    // 在副本上改：直接改 widget.statusFields 会让「放弃修改并返回」
    // 这条路径也把状态栏改掉。
    final draft = _statusFields.map((f) => f.copyWith()).toList();
    var changed = false;
    for (final page in _pages) {
      if (DataChannelService.writeBackToStatusFields(
        page.elements,
        draft,
        _statusFieldBaseline,
        page.propertyOverrides,
      )) {
        changed = true;
      }
    }
    return changed ? draft : null;
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

  AssemblyPage get _rootBasePage {
    final bases = _pages.where((page) => page.isBase).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return bases.first;
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

  Map<String, dynamic> _linkerDataOf(UIModule module) {
    final raw = module.properties['linker'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
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
  List<CharacterEntry> get _cardEntries => widget.cardEntries;
  String get _cardType => widget.cardType;
  /// 该一级分组下作者**已启用**的条目。
  ///
  /// 只列启用的：作者关掉的条目不参与 Prompt，让玩家填了也不会生效，
  /// 摆出来只会造成「填了没用」的困惑。
  List<CharacterEntry> _entriesOfGroup(String group) {
    final fixedIds = CardEntryTarget.fixedEntryIdsOf(_cardType, group);
    final out = <CharacterEntry>[];
    for (final id in fixedIds) {
      final hit = _cardEntries.where((e) => e.id == id && e.enabled);
      if (hit.isNotEmpty) out.add(hit.first);
    }
    // 自定义条目一律归入「详细设定」，与角色卡编辑页的分区一致。
    if (group == CardEntryTarget.groupDetail) {
      out.addAll(_cardEntries.where((e) => e.isCustom && e.enabled));
    }
    return out;
  }

  CharacterEntry? _cardEntryById(String id) {
    final hit = _cardEntries.where((e) => e.id == id);
    return hit.isEmpty ? null : hit.first;
  }
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
    // visibility 已从 UI 删除（死字段），但继续按原样存写，
    // 断掉会让已有角色卡的通道配置在下次保存时丢字段。
    required String visibility,
    required String notifyStyle,
    required String notifyTemplate,
    required String llmReadPolicy,
    required String llmWritePolicy,
    required String promptSection,
    required CardEntryTarget cardTarget,
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
      // 取代 llmUpdateApplyPolicy：值一律写入，这里只决定要不要通知玩家。
      'notifyStyle': notifyStyle,
      if (notifyTemplate.trim().isNotEmpty)
        'notifyTemplate': notifyTemplate.trim(),
      // A13-1：注入到 [界面数据] 还是 [玩家档案]。
      'promptSection': promptSection,
      // A13-2：指向角色卡设定条目时的三级定位。
      if (targetKind == 'card_entry' && cardTarget.isValid)
        'cardEntryTarget': cardTarget.toJson(),
      // 命中状态字段时以卡片端字段类型为准，避免 UI 组件类型与状态字段类型冲突。
      'fieldType': resolved.fieldType ?? _fieldTypeForModule(module),
    };
  }
  /// 状态栏字段的名称建议列表。
  ///
  /// 只列**状态栏已有字段**——这个建议的价值就在于「照着现有的选，
  /// 保证能绑上」。列别的来源反而会让作者选到一个绑不上的名字。
  ///
  /// 排序：与当前输入前缀匹配的排前面，其余按状态栏原顺序。
  /// 完全一致的标记 matched，在列表里打勾。
  List<NameSuggestion> _statusFieldNameSuggestions(String current) {
    if (_statusFields.isEmpty) return const [];
    final key = current.trim().toLowerCase();

    String ownerLabel(String owner) {
      switch (owner) {
        case 'player':
          return '玩家';
        case 'char':
          return '角色';
        case 'neutral':
          return '环境';
        default:
          return '';
      }
    }

    final items = <NameSuggestion>[];
    for (final field in _statusFields) {
      final name = field.name.trim();
      if (name.isEmpty) continue;
      final owner = ownerLabel(field.owner);
      items.add(
        NameSuggestion(
          name: name,
          detail: [
            field.isNumber ? '数值' : '文本',
            if (owner.isNotEmpty) owner,
          ].join(' · '),
          matched: key.isNotEmpty && name.toLowerCase() == key,
        ),
      );
    }

    if (key.isEmpty) return items;
    // 前缀命中的提到前面：作者打了几个字再点开，想找的多半在那几个字里。
    final hit = <NameSuggestion>[];
    final rest = <NameSuggestion>[];
    for (final item in items) {
      (item.name.toLowerCase().startsWith(key) ? hit : rest).add(item);
    }
    return [...hit, ...rest];
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
  /// A13-2：角色卡设定的三级选择器。
  ///
  /// 一级「简单介绍 / 详细设定」→ 二级条目 → 三级子字段。
  /// 自定义条目的第三级是**标题输入**（默认名都是「新条目」，
  /// 靠标题区分才能同时存在多个），且只在详细设定下可选。
  List<Widget> _buildCardEntryTargetFields({
    required CardEntryTarget target,
    required TextEditingController customTitleController,
    required ValueChanged<CardEntryTarget> onChanged,
  }) {
    if (_cardEntries.isEmpty) {
      return const [
        Text(
          '角色卡还没有设定条目，或条目都未启用。请先在角色卡编辑页填写并启用条目。',
          style: TextStyle(fontSize: 11, color: Color(0xFFE65100), height: 1.35),
        ),
      ];
    }

    final group = target.group.isEmpty ? CardEntryTarget.groupIntro : target.group;
    final entries = _entriesOfGroup(group);

    Widget dropdown(
      String value,
      String label,
      List<DropdownMenuItem<String>> items,
      ValueChanged<String> onPick,
    ) {
      return DropdownButtonFormField<String>(
        initialValue: value.isEmpty ? null : value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: (next) {
          if (next == null) return;
          onPick(next);
        },
      );
    }

    final widgets = <Widget>[
      dropdown(
        group,
        '设定分组',
        const [
          DropdownMenuItem(
              value: CardEntryTarget.groupIntro, child: Text('简单介绍')),
          DropdownMenuItem(
              value: CardEntryTarget.groupDetail, child: Text('详细设定')),
        ],
        // 换分组时清空二三级：旧条目多半不属于新分组。
        (value) => onChanged(CardEntryTarget(
          group: value,
          entryId: '',
          fieldKey: '',
        )),
      ),
      const SizedBox(height: 10),
    ];

    if (entries.isEmpty && group == CardEntryTarget.groupIntro) {
      widgets.add(const Text(
        '「简单介绍」下没有已启用的条目。',
        style: TextStyle(fontSize: 11, color: Color(0xFFE65100), height: 1.35),
      ));
      return widgets;
    }

    widgets.add(dropdown(
      target.entryId,
      '设定条目',
      [
        for (final entry in entries)
          DropdownMenuItem(value: entry.id, child: Text(entry.title)),
        // 自定义条目只在详细设定下允许——与角色卡编辑页的规则一致。
        if (group == CardEntryTarget.groupDetail)
          const DropdownMenuItem(
            value: CardEntryTarget.customEntryMarker,
            child: Text('＋ 添加自定义条目'),
          ),
      ],
      (value) => onChanged(target.copyWith(
        group: group,
        entryId: value,
        // 换条目后子字段必然失效。
        fieldKey: '',
      )),
    ));

    if (target.entryId.isEmpty) return widgets;

    widgets.add(const SizedBox(height: 10));

    if (target.entryId == CardEntryTarget.customEntryMarker) {
      // 第三级 = 条目标题。此时才真正决定「是哪一个自定义条目」。
      widgets.add(TextField(
        controller: customTitleController,
        decoration: const InputDecoration(
          labelText: '自定义条目标题',
          hintText: '例如：职业、天赋、随身物品',
          isDense: true,
        ),
        onChanged: (value) => onChanged(target.copyWith(
          group: group,
          fieldKey: value,
        )),
      ));
      widgets.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          '玩家输入并提交后才会真正产生这个条目，留空则不生效。'
          '标题相同视为同一条目，重复填写是覆盖而非新增。',
          style: TextStyle(fontSize: 11, color: Color(0xFF777783), height: 1.35),
        ),
      ));
      return widgets;
    }

    final entry = _cardEntryById(target.entryId);
    final fieldKeys =
        entry == null ? const <String>[] : CardEntryTarget.fieldKeysOf(entry);

    if (fieldKeys.isEmpty) {
      // 纯文本条目（如「与用户关系」）没有子字段，整条即目标。
      widgets.add(const Text(
        '该条目是整段文本，没有更细的子项，玩家填写的内容会覆盖整条。',
        style: TextStyle(fontSize: 11, color: Color(0xFF777783), height: 1.35),
      ));
      if (target.fieldKey != '__whole__') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onChanged(target.copyWith(group: group, fieldKey: '__whole__'));
        });
      }
      return widgets;
    }

    widgets.add(dropdown(
      target.fieldKey == '__whole__' ? '' : target.fieldKey,
      '具体子项',
      [
        for (final key in fieldKeys)
          DropdownMenuItem(
            value: key,
            child: Text(CardEntryTarget.fieldLabelOf(target.entryId, key)),
          ),
      ],
      (value) => onChanged(target.copyWith(group: group, fieldKey: value)),
    ));
    return widgets;
  }
  /// A14-3：数据通道专项页。
  ///
  /// 从实例编辑器里抽出来单独成页——通道配置有十来项
  /// （语义来源 / 存放位置 / 卡片三级定位 / 读写策略 / 注入位置…），
  /// 内嵌会把对话框撑得又长又乱，此前「方案参数编辑器漏做」
  /// 与「三级选择器藏太深」都是这么来的。
  ///
  /// **不直接落盘**：把配好的通道返回给调用方，由实例编辑器的
  /// 保存 / 取消统一裁决。专项页自己写库的话，作者点了外层「取消」
  /// 也收不回来，与「先改，再决定确认还是退回」的常识相悖。
  Future<DataChannelPageResult> _openDataChannelPage(UIModule module) async {
    final elementIndex =
        _elements.indexWhere((e) => e.module?.id == module.id);
    final element = elementIndex == -1 ? null : _elements[elementIndex];
    if (element == null) {
      return const DataChannelPageResult(saved: false);
    }

    final existing = _dataChannelOf(module);
    final labels = _textLabelCandidates();

    final nameController = TextEditingController(
      text: existing?['semanticLabel']?.toString() ?? module.name,
    );
    var semanticSource = existing?['semanticSource']?.toString() ?? 'manual';
    var labelElementId = existing?['labelElementId']?.toString() ?? '';
    var targetKind = existing?['targetKind']?.toString() ?? 'local_ui_state';
    var visibility = existing?['visibility']?.toString() ?? 'ui_only';
    var readPolicy = existing?['llmReadPolicy']?.toString() ?? 'none';
    var writePolicy = existing?['llmWritePolicy']?.toString() ?? 'none';
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
    final cardTitleController = TextEditingController(
      text: cardTarget.isCustomEntry ? cardTarget.fieldKey : '',
    );

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            // 预览由表单内部自算（见段②），这里不再重复计算。
            return Scaffold(
              appBar: AppBar(
                title: Text('数据通道 · ${module.name}'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      await Future<void>.delayed(
                          const Duration(milliseconds: 16));
                      if (!pageContext.mounted) return;
                      Navigator.pop(pageContext, true);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
              // 浅灰底：三张白卡片需要底色衬托才有「分组」的观感，
              // 纯白底上卡片边框几乎看不见。
              backgroundColor: const Color(0xFFF2F2F6),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                children: [
                  // 预览条已移入段②「叫什么」，紧跟它服务的名称字段。
                  // 旧版挂在页顶，与真正相关的两项隔着六个下拉。
                  ..._buildDataChannelFormFields(
                    labels: labels,
                    fallbackName: module.name,
                    nameController: nameController,
                    semanticSource: semanticSource,
                    labelElementId: labelElementId,
                    targetKind: targetKind,
                    llmReadPolicy: readPolicy,
                    llmWritePolicy: writePolicy,
                    notifyStyle: notifyStyle,
                    notifyTemplateController: notifyTemplateController,
                    promptSection: promptSection,
                    cardTarget: cardTarget,
                    cardCustomTitleController: cardTitleController,
                    onCardTarget: (v) => setPageState(() => cardTarget = v),
                    onSemanticSource: (v) =>
                        setPageState(() => semanticSource = v),
                    onLabelElementId: (v) =>
                        setPageState(() => labelElementId = v),
                    onTargetKind: (v) => setPageState(() => targetKind = v),
                    onReadPolicy: (v) => setPageState(() => readPolicy = v),
                    onWritePolicy: (v) => setPageState(() => writePolicy = v),
                    onNotifyStyle: (v) => setPageState(() => notifyStyle = v),
                    onPromptSection: (v) =>
                        setPageState(() => promptSection = v),
                    onNormalizeLabelId: (v) => labelElementId = v,
                    onNameChanged: () => setPageState(() {}),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    Map<String, dynamic>? result;
    if (saved == true && mounted) {
      final name = _resolveDataChannelName(
        semanticSource: semanticSource,
        manualName: nameController.text,
        labelElementId: labelElementId,
        labels: labels,
        fallbackName: module.name,
      ).trim();

      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index != -1 && name.isNotEmpty) {
        final currentModule = _elements[index].module;
        if (currentModule != null) {
          result = _buildDataChannelPayload(
            name: name,
            semanticSource: semanticSource,
            labelElementId: labelElementId,
            sourceComponentId: _elements[index].id,
            module: currentModule,
            targetKind: targetKind,
            visibility: visibility,
            llmReadPolicy: readPolicy,
            llmWritePolicy: writePolicy,
            notifyStyle: notifyStyle,
            notifyTemplate: notifyTemplateController.text,
            promptSection: promptSection,
            cardTarget: cardTarget,
          );
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      cardTitleController.dispose();
      notifyTemplateController.dispose();
    });
    return DataChannelPageResult(saved: saved == true, channel: result);
  }
  /// 数据通道表单字段，供原子实例编辑器与复合暴露项实例编辑器共用。
  List<Widget> _buildDataChannelFormFields({
    required List<UIElement> labels,
    required String fallbackName,
    required TextEditingController nameController,
    required String semanticSource,
    required String labelElementId,
    required String targetKind,
    required String llmReadPolicy,
    required String llmWritePolicy,
    required String notifyStyle,
    required TextEditingController notifyTemplateController,
    required String promptSection,
    required CardEntryTarget cardTarget,
    required TextEditingController cardCustomTitleController,
    required ValueChanged<CardEntryTarget> onCardTarget,
    required ValueChanged<String> onSemanticSource,
    required ValueChanged<String> onLabelElementId,
    required ValueChanged<String> onTargetKind,
    required ValueChanged<String> onReadPolicy,
    required ValueChanged<String> onWritePolicy,
    required ValueChanged<String> onNotifyStyle,
    required ValueChanged<String> onPromptSection,
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

    // 三段的顺序是「存哪里 → 叫什么 → 怎么交互」（用户确定）。
    //
    // 先问存放位置，是因为**它决定了后面所有项的含义**：
    // 存进角色卡设定和存进会话变量，「名称」的作用完全不同
    // （前者是卡片条目标题，后者只是个键名）。
    // 旧版把「数据名称来源」放在第一项，作者得先给一个还不知道
    // 要用在哪的东西起名字。
    const accentWhere = Color(0xFF5E35B1);
    const accentName = Color(0xFF00897B);
    const accentAi = Color(0xFFEF6C00);

    final previewName = _resolveDataChannelName(
      semanticSource: semanticSource,
      manualName: nameController.text,
      labelElementId: effectiveLabelId,
      labels: labels,
      fallbackName: fallbackName,
    ).trim();

    return [
      // ================= ① 存在哪里 =================
      DataChannelSection(
        index: 1,
        title: '数据归属',
        subtitle: '这个值存在哪里',
        accent: accentWhere,
        children: [
          SegmentedField(
            label: '存放位置',
            value: targetKind,
            accent: accentWhere,
            options: const [
              SegmentedFieldOption(
                value: 'local_ui_state',
                label: 'UI 内部状态',
                icon: Icons.widgets_outlined,
              ),
              SegmentedFieldOption(
                value: 'session_var',
                label: '会话变量',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              SegmentedFieldOption(
                value: 'status_field',
                label: '状态字段',
                icon: Icons.speed_rounded,
              ),
              SegmentedFieldOption(
                value: 'card_entry',
                label: '角色卡设定',
                icon: Icons.badge_outlined,
              ),
              SegmentedFieldOption(
                value: 'user_profile',
                label: '玩家档案',
                icon: Icons.account_circle_outlined,
              ),
            ],
            helper: _targetKindHelper(targetKind),
            onChanged: onTargetKind,
          ),
          if (targetKind == 'card_entry') ...[
            const SizedBox(height: 12),
            ..._buildCardEntryTargetFields(
              target: cardTarget,
              customTitleController: cardCustomTitleController,
              onChanged: onCardTarget,
            ),
          ],
        ],
      ),

      // ================= ② 叫什么 =================
      DataChannelSection(
        index: 2,
        title: '数据标识',
        subtitle: 'AI 与卡片里看到的名称',
        accent: accentName,
        children: [
          SegmentedField(
            label: '名称来源',
            value: semanticSource,
            accent: accentName,
            options: const [
              SegmentedFieldOption(value: 'manual', label: '手动填写'),
              SegmentedFieldOption(value: 'text_label', label: '取文本标签'),
              SegmentedFieldOption(value: 'component_name', label: '用组件名'),
            ],
            onChanged: onSemanticSource,
          ),
          const SizedBox(height: 12),
          if (semanticSource == 'manual')
            // 输入框始终可自由输入；右侧按钮才拉出状态栏字段建议。
            // 建议不随聚焦/输入自动弹出——那会在作者正打字时挡住视线。
            SuggestibleNameField(
              controller: nameController,
              label: '数据名称',
              accent: accentName,
              suggestions: _statusFieldNameSuggestions(nameController.text),
              emptyHint: '角色卡还没有状态栏字段',
              onChanged: (_) => onNameChanged?.call(),
            )
          else if (semanticSource == 'text_label')
            hasLabels
                // 标签数量取决于画布上有几个 Text，项数不定 → 用下拉。
                ? RoundedDropdownField(
                    label: '标签文本',
                    value: effectiveLabelId,
                    accent: accentName,
                    options: labels
                        .map(
                          (label) => RoundedDropdownOption(
                            value: label.id,
                            label: _textValueOf(label),
                          ),
                        )
                        .toList(),
                    onChanged: onLabelElementId,
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
          const SizedBox(height: 12),
          // 预览紧跟在名称字段后面。
          // 旧版把它孤零零挂在页顶，与它真正服务的两项隔着六个下拉。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accentName.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '最终语义：${previewName.isEmpty ? '未命名' : previewName}',
              style: const TextStyle(
                fontSize: 12,
                color: accentName,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 状态字段匹配提示：告诉作者这个名字有没有对上角色卡里
          // 已有的状态字段，没对上会被记为「待创建」。
          //
          // 放在段②而不是段①「存放位置」旁边——它校验的是**名称**，
          // 名称还没填时提示也无从谈起。
          if (targetKind == 'status_field') ...[
            const SizedBox(height: 10),
            _buildStatusFieldMatchHint(previewName),
          ],
        ],
      ),

      // ================= ③ 怎么交互 =================
      DataChannelSection(
        index: 3,
        title: 'AI 读写',
        subtitle: '与模型之间的数据流向',
        accent: accentAi,
        children: [
          SegmentedField(
            label: '发送当前值给 AI',
            value: llmReadPolicy,
            accent: accentAi,
            options: const [
              SegmentedFieldOption(value: 'none', label: '不发送'),
              SegmentedFieldOption(value: 'prompt', label: '发送到 Prompt'),
              SegmentedFieldOption(value: 'hidden_context', label: '隐藏上下文'),
            ],
            onChanged: onReadPolicy,
          ),
          if (llmReadPolicy != 'none') ...[
            const SizedBox(height: 12),
            SegmentedField(
              label: '注入位置',
              value: promptSection,
              accent: accentAi,
              options: const [
                SegmentedFieldOption(
                  value: DataChannelPromptItem.sectionUiData,
                  label: '界面数据',
                ),
                SegmentedFieldOption(
                  value: DataChannelPromptItem.sectionCoreSetting,
                  label: '玩家档案',
                ),
              ],
              helper: promptSection == DataChannelPromptItem.sectionCoreSetting
                  ? '与「核心角色设定」并列注入，权重更高、全程有效。'
                      '适合开场白里填写的姓名、职业、属性；'
                      '随会话保存，清空聊天记录后需要重新填写。'
                  : '作为运行时状态注入，随每轮对话更新。',
              onChanged: onPromptSection,
            ),
          ],
          const SizedBox(height: 12),
          SegmentedField(
            label: '允许 AI 更新',
            value: llmWritePolicy,
            accent: accentAi,
            options: const [
              SegmentedFieldOption(value: 'none', label: '不允许'),
              SegmentedFieldOption(value: 'suggest_delta', label: '增量 +N/-N'),
              SegmentedFieldOption(value: 'suggest_replace', label: '替换新值'),
            ],
            onChanged: onWritePolicy,
          ),
          // 通知方式只在「AI 能改这个值」时才有意义。
          if (llmWritePolicy != 'none') ...[
            const SizedBox(height: 12),
            StatusLampField(
              label: '变化时提醒玩家',
              value: notifyStyle,
              options: const [
                StatusLampOption(
                  value: 'silent',
                  label: '静默',
                  color: Color(0xFF9E9E9E),
                  description: '值照常写入，不打扰玩家。适合频繁的小幅变化。',
                ),
                StatusLampOption(
                  value: 'toast',
                  label: '浮窗',
                  color: Color(0xFF29B6F6),
                  description: '顶部浮出几秒后自消，不打断操作。适合「知道就行」的变化。',
                ),
                StatusLampOption(
                  value: 'dialog',
                  label: '弹窗',
                  color: Color(0xFFEF6C00),
                  description: '需要玩家点确认。适合升级这类玩家要据此做决策的大事。'
                      '同一轮里多条会堆叠，逐个查看。',
                ),
              ],
              onChanged: onNotifyStyle,
            ),
            if (notifyStyle != 'silent') ...[
              const SizedBox(height: 12),
              TextField(
                controller: notifyTemplateController,
                decoration: const InputDecoration(
                  labelText: '提醒文案（可留空）',
                  hintText: '恭喜升到 {new} 级',
                  helperText: '可用 {name} {old} {new}；留空则显示「等级：3 → 4」',
                  helperMaxLines: 2,
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ],
      ),
    ];
  }
  /// 存放位置的一句话说明。
  ///
  /// 四个选项的差别不看说明根本猜不出来——
  /// 「UI 内部状态」和「会话变量」从字面看几乎是同义词。
  String _targetKindHelper(String targetKind) {
    switch (targetKind) {
      case 'local_ui_state':
        return '只存在这张界面里，切页或重开会话即丢失。适合纯展示用的临时值。';
      case 'session_var':
        return '跟着当前会话走，清空聊天记录才消失。适合剧情进度、临时标记。';
      case 'status_field':
        return '写进角色卡状态栏，玩家能在状态栏看到。适合等级、好感度这类长期数值。';
      case 'card_entry':
        return '写进角色卡设定条目，作为长期设定的一部分。需要在下面指定写到哪一条。';
      case 'user_profile':
        return '写进本卡的「用户设定」。名称里含「名/称呼」写昵称，'
            '其余写玩家设定详述。只影响这张卡，不改全局用户。';
      default:
        return '';
    }
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
  /// 历史栈。每项是一次 `_persistAssemblyElements` 之前的画布状态。
  final List<String> _history = <String>[];
  /// 栈深上限。角色卡的元素 JSON 可能不小，无限堆会吃内存。
  static const int _maxHistory = 40;
  /// 正在应用撤销，期间不记录新快照（否则撤销本身会入栈）。
  bool _applyingHistory = false;
  DateTime? _lastSnapshotAt;
  /// 记录当前状态。
  ///
  /// 在**改动写入之前**调用，存的是「改之前」的样子。
  void _pushHistory() {
    if (_applyingHistory) return;

    // 连续拖动每帧都会 persist，300ms 内的连续改动只留第一张。
    // 否则撤销一次只退回一帧，作者要点几十下才回到起点。
    final now = DateTime.now();
    final last = _lastSnapshotAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastSnapshotAt = now;

    final snapshot = jsonEncode(
      _orderedPages().map((page) => page.toJson()).toList(),
    );
    // 与栈顶相同就不重复入栈（比如只是点了下没真改）。
    if (_history.isNotEmpty && _history.last == snapshot) return;

    _history.add(snapshot);
    while (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  void _persistAssemblyElements() {
    _pushHistory();
    _sanitizeActivePropertyOverrides();
    _syncCanvasStateIntoActivePage();
    _info.elementsJson = jsonEncode(
      _elements.map((element) => element.toJson()).toList(),
    );
    // 页面数据要落到**当前正在编辑的分支**上。
    //
    // 无条件写 `pagesJson` 会把分支 2 的内容盖到主支路——
    // 作者在分支里改了半天，回主线一看全变了，而且主线原样已丢失。
    // 见 logic_branch.dart 的分支体系。
    final pagesEncoded = jsonEncode(
      _orderedPages().map((page) => page.toJson()).toList(),
    );
    if (_editingBranch == 0) {
      _info.pagesJson = pagesEncoded;
    } else {
      _info.branchVariants['$_editingBranch'] = pagesEncoded;
    }
    _info.pcbWidth = _pcbSize.width;
    _info.pcbHeight = _pcbSize.height;
    _info.pcbColorValue = _pcbColor.toARGB32();
    _info.pcbRadius = _pcbRadius;
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

  // ===== 被多个分组共用的小工具 =====
  //
  // 放在依赖链根部：下游各 mixin 都要用，
  // 留在任何一个下游文件里都会形成循环依赖。

  String _displayPageName(AssemblyPage page) =>
      _isRootBasePage(page) ? '主菜单' : page.name;

  /// 固定色板。
  ///
  /// 用色板而非全色域取色器：作者要的是「几个协调的颜色」，
  /// 全色域反而容易挑出一堆相近色，且在小屏上难精确操作。
  Widget _buildColorPalette(Color current, ValueChanged<Color> onPick) {
    const palette = <int>[
      0xFFFFFFFF, 0xFFF5F5F7, 0xFFBDBDBD, 0xFF616161, 0xFF111116,
      0xFFE53935, 0xFFE8833A, 0xFFFFC107, 0xFF4CAF50, 0xFF00897B,
      0xFF2979FF, 0xFF3949AB, 0xFF7E57C2, 0xFFAD1457, 0xFF6D4C41,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in palette)
          InkWell(
            onTap: () => onPick(Color(value)),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(value),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: current.toARGB32() == value
                      ? const Color(0xFF111116)
                      : Colors.black26,
                  width: current.toARGB32() == value ? 2.4 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isRootBasePage(AssemblyPage page) => page.id == _rootBasePage.id;

  // ===== 被 build 方法以 `_AssemblyLogic.xxx` 形式引用的公开常量 =====
  //
  // 必须留在这个 mixin 里：这几个是**静态**成员，
  // 而静态成员不会随 mixin 继承——`character_assembly_page.dart`
  // 里写的是 `_AssemblyLogic.kResizeHandlePadding`，
  // 搬到别的 mixin 就会「找不到 getter」。

  /// linker 两侧接线热区的宽度。
  static const double kLinkerPortHotZone = 24.0;

  /// 选中可形变元件时四周撑出的边距。
  ///
  /// 把手是 22px 的圆，热区取 2×padding = 24，略大于圆本身好点。
  /// 与 Studio 的 p=20 同量级，但更紧凑——Assembly 画布本就挤。
  static const double kResizeHandlePadding = 12.0;

  /// 复合组件缩放后，内部文字仍可辨认的最小比例。
  ///
  /// 复合件内常见字号是 9~12，乘 0.45 后约 4~5.4px，
  /// 再小就完全糊成一团了。用户要求「最小不可让内部文字不可见」。
  static const double kMinCompositeScale = 0.45;
}
