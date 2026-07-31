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

  /// A14-1d：精确位移方向键是否展开。
  /// 跟着选中元素走——换个元素就收起，避免对着别的组件误按。
  bool _showNudgePad = false;
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
  late double _pcbRadius;
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

  // ===== A14-4：linker 连线可视化 =====
  //
  // 采用 Studio 的连线方式（用户明确要求）：操作性、可视性、
  // 与端口设计的匹配度都优于配置式。
  //
  // 画布拥挤的问题**不靠换配色解决**——连线颜色的语义必须与 Studio 一致，
  // 否则同一条线在两个编辑器里是两个颜色。改为减小线宽、降低不透明度。
  // 见 `_kAssemblyLineWidth` / `_kAssemblyLineOpacity`。

  /// Assembly 画布的连线线宽。Studio 用 2.5。
  ///
  /// PCB 最窄只有 212（伴生 UI），元件间距远比 Studio 紧，
  /// 2.5 的实色线会盖住元件本体。
  static const double _kAssemblyLineWidth = 1.4;

  /// Assembly 画布的连线不透明度。
  ///
  /// 淡到不抢视觉，但仍能分辨颜色语义（接收青 / 输出绿 / 控制橙 /
  /// 复合粉蓝）。拖拽中的临时线不适用此值——那条线需要看清。
  static const double _kAssemblyLineOpacity = 0.55;

  /// 箭头随线宽一起缩小，否则细线配大箭头很突兀。
  static const double _kAssemblyArrowSize = 6.0;

  /// 汇总当前页所有 linker 的连线。
  ///
  /// 与 Studio 的 `_getAllLinkerConnections` 同构：一个 linker 最多产生
  /// 两条线——来源→linker（input）与 linker→目标（output）。
  /// 只连了一半的 linker 也会画出已连的那半条，这正是作者需要看到的
  /// 「这条还没接完」。
  List<Map<String, dynamic>> _assemblyLinkerConnections() {
    final connections = <Map<String, dynamic>>[];
    for (final el in _elements) {
      if (el.isComposite || el.module?.type != 'linker') continue;
      final linkerData = el.module!.properties['linker'];
      if (linkerData is! Map) continue;

      final sourceId = linkerData['sourceModuleId']?.toString();
      final targetId = linkerData['targetModuleId']?.toString();
      final sourcePort = linkerData['sourcePort']?.toString() ?? 'current';
      final storedTargetPort = linkerData['targetPort']?.toString() ?? 'text';
      final scheme = linkerData['scheme']?.toString();
      // 兼容早期草稿：触发方案即使旧数据未写 gate_in，也按控制端口绘制。
      // 与 Studio 同样处理，否则同一张卡两边画出的线型不同。
      final targetPort = (scheme == 'click_to_math_trigger' ||
              scheme == 'timer_tick_to_math_trigger')
          ? 'gate_in'
          : storedTargetPort;

      if (sourceId != null && sourceId.isNotEmpty) {
        connections.add({
          'from': sourceId,
          'fromPort': sourcePort,
          'to': el.id,
          'toPort': 'input',
          'linkerId': el.id,
          'type': 'input',
        });
      }
      if (targetId != null && targetId.isNotEmpty) {
        connections.add({
          'from': el.id,
          'fromPort': 'output',
          'to': targetId,
          'toPort': targetPort,
          'linkerId': el.id,
          'type': 'output',
        });
      }
    }
    return connections;
  }

  UIElement? _assemblyElementById(String id) {
    for (final el in _elements) {
      if (el.id == id) return el;
    }
    return null;
  }

  /// 按 id 查找连线端点，含复合件内部的暴露子元素。
  ///
  /// 连线存的可能是复合件内部子元素的 id，它不在 `_elements` 顶层，
  /// 必须深入 `composite.children` 才找得到。
  /// 配置面板要显示端点名称与类型，靠 `_assemblyElementById` 会漏掉这类。
  UIElement? _wiringEndpointById(String id) {
    final top = _assemblyElementById(id);
    if (top != null) return top;
    for (final element in _elements) {
      final data = element.composite;
      if (data == null) continue;
      for (final child in data.children) {
        if (child.id == id) return child;
      }
    }
    return null;
  }

  /// 画线用的锚点元素。
  ///
  /// 连线存的可能是复合件**内部**子元素的 id（暴露端口）。
  /// 子元素的 offset 是相对复合件的，直接当画布坐标用会错位一整个
  /// 复合件的距离，因此回落到复合件外壳作为锚点。
  UIElement? _wireAnchorElementById(String id) {
    return _assemblyElementById(id) ?? _compositeOwnerOfChild(id);
  }

  /// 元素某个端口在画布坐标系中的位置。
  ///
  /// 注意与 Studio 的差异：Studio 用 `_workspaceOffset` 一个偏移量，
  /// Assembly 的元素坐标是相对 PCB 的，屏幕位置要叠加
  /// `_canvasOffset + _pcbOffset`（见画布里每个元素的 Positioned）。
  /// 这两个偏移不能漏，否则线会整体错位一个 PCB 的距离。
  Offset _assemblyPortOffset(UIElement el, bool isInput, [String? portName]) {
    final base = _canvasOffset + _pcbOffset;
    final elLeft = base.dx + el.offset.dx;
    final elTop = base.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;

    // math_node 的触发端口在顶部中央，不在左右两侧。
    if (portName == 'gate_in') {
      if (el.rotation == 0.0) return Offset(cx, elTop + 7.0);
      final rad = el.rotation * math.pi / 180.0;
      final distance = math.max(0.0, el.size.height / 2 - 7.0);
      return Offset(
        cx + distance * math.sin(rad),
        cy - distance * math.cos(rad),
      );
    }

    if (el.rotation == 0.0) {
      return Offset(isInput ? elLeft : elLeft + el.size.width, cy);
    }

    // 旋转后端口跟着转：把「中心 ± 半宽」这个向量按角度旋转。
    final rad = el.rotation * math.pi / 180.0;
    final sign = isInput ? -1.0 : 1.0;
    final halfWidth = el.size.width / 2;
    return Offset(
      cx + sign * halfWidth * math.cos(rad),
      cy + sign * halfWidth * math.sin(rad),
    );
  }

  // ===== A14-4 第二步：拖拽画线 =====
  //
  // 与 Studio 同构，但有两处按 Assembly 的实际情况调整：
  // 1. 热区左右各 24px（Studio 32px）。Assembly 的 linker 是 132×44，
  //    切 32 之后中间只剩 68px，手指拖动元件时容易偏进热区。
  //    24px 仍比手指宽，接线不会难点，中间留 84px 好按（用户选定）。
  // 2. 坐标要叠加 `_canvasOffset + _pcbOffset`（见 _assemblyPortOffset）。

  /// linker 两侧接线热区的宽度。
  static const double kLinkerPortHotZone = 24.0;

  // ===== A14-1g：形变把手 =====

  /// 选中可形变元件时四周撑出的边距。
  ///
  /// 把手是 22px 的圆，热区取 2×padding = 24，略大于圆本身好点。
  /// 与 Studio 的 p=20 同量级，但更紧凑——Assembly 画布本就挤。
  static const double kResizeHandlePadding = 12.0;

  Size _resizeStartSize = Size.zero;
  Offset _resizeStartGlobal = Offset.zero;

  /// 复合组件缩放后，内部文字仍可辨认的最小比例。
  ///
  /// 复合件内常见字号是 9~12，乘 0.45 后约 4~5.4px，
  /// 再小就完全糊成一团了。用户要求「最小不可让内部文字不可见」。
  static const double kMinCompositeScale = 0.45;

  /// 各类组件的最小尺寸。
  ///
  /// 与 Studio 的 clamp 口径一致：进度条可以做得很细（血条），
  /// 面板类允许铺满整页，其余控件保底 40×20 以免拉成看不见的一条。
  ///
  /// 复合件另有一套（用户要求更严格）：按内容包围盒 × 最小可读比例，
  /// 保证缩到底时内部文字仍能看清。
  Size _minResizeFor(String? type, {UIElement? element}) {
    if (element != null && element.isComposite && element.composite != null) {
      final natural = UIRenderer.compositeNaturalSize(element.composite!);
      return Size(
        natural.width * kMinCompositeScale,
        natural.height * kMinCompositeScale,
      );
    }
    if (type == 'progress') return const Size(12, 6);
    if (_isSurfaceLikeType(type)) return const Size(20, 20);
    return const Size(40, 20);
  }

  /// 各类组件的最大尺寸。
  ///
  /// 复合件不得超出 PCB（用户要求）：它是成品部件，
  /// 溢出画布的部分在运行时会被裁掉或触发等比缩小，
  /// 作者在编辑器里摆好的比例就白费了。
  Size _maxResizeFor(String? type, {UIElement? element}) {
    if (element != null && element.isComposite) {
      return Size(_pcbSize.width, _pcbSize.height);
    }
    if (_isSurfaceLikeType(type)) return const Size(4096, 4096);
    return const Size(600, 400);
  }

  bool _isSurfaceLikeType(String? type) => const {
        'surface',
        'surface_art',
        'primitive_art',
        'base_box',
      }.contains(type);

  /// 形变后修正 offset，让**把手的对角保持不动**。
  ///
  /// 这是旋转后「图形到处跑」的根因（首轮测试反馈）：
  /// `Transform.rotate` 绕**中心**旋转，而 `offset` 定义的是**左上角**。
  /// 改尺寸时若 offset 不动，中心就会跟着移动，
  /// 旋转后的图形等于绕着一个正在移动的中心转，视觉上四处乱窜。
  ///
  /// 未旋转时中心其实也在动，只是增长方向恰好与屏幕轴对齐、
  /// 左上角看着没变，所以一直没暴露。
  ///
  /// 推导：设锚点为局部左上角在屏幕上的位置
  /// ```
  /// anchor = offset + (w/2, h/2) + rot(-w/2, -h/2)
  /// ```
  /// 令新尺寸下 anchor 不变，解出
  /// ```
  /// newOffset = offset - (dW, dH) + rot(dW, dH)
  /// 其中 dW = (nw - w) / 2, dH = (nh - h) / 2
  /// ```
  /// 0° 时 rot 为恒等变换，两项抵消、offset 不变，向后兼容。
  Offset _offsetKeepingResizeAnchor({
    required Offset offset,
    required Size oldSize,
    required Size newSize,
    required double rotation,
  }) {
    final dW = (newSize.width - oldSize.width) / 2;
    final dH = (newSize.height - oldSize.height) / 2;
    if (rotation == 0.0) return offset;
    final rad = rotation * math.pi / 180.0;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);
    return Offset(
      offset.dx - dW + (dW * cosR - dH * sinR),
      offset.dy - dH + (dW * sinR + dH * cosR),
    );
  }

  /// 应用一次形变拖动。
  ///
  /// 两个关键点，缺一个都会让旋转后的形变不可用：
  ///
  /// 1. 把屏幕位移**投影到元件的局部轴**。把手随元件一起旋转，
  ///    若仍拿屏幕 dx/dy 当宽高增量，转 90° 后朝屏幕右边拖改的却是
  ///    width，视觉上元件在往下长——把手转了、数学没转。
  /// 2. 改完尺寸**修正 offset 保持把手对角不动**，
  ///    见 `_offsetKeepingResizeAnchor`。
  void _applyResizeDrag(UIElement element, Offset globalPosition) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    final current = _elements[index];
    if (current.layoutLocked || current.sealed) return;

    final rawDx = globalPosition.dx - _resizeStartGlobal.dx;
    final rawDy = globalPosition.dy - _resizeStartGlobal.dy;
    final rad = current.rotation * math.pi / 180.0;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);
    final localDx = rawDx * cosR + rawDy * sinR;
    final localDy = -rawDx * sinR + rawDy * cosR;

    final type = current.module?.type;
    final minSize = _minResizeFor(type, element: current);
    final maxSize = _maxResizeFor(type, element: current);

    double nextWidth;
    double nextHeight;
    if (current.isComposite && current.composite != null) {
      // 复合件**等比**缩放（用户要求）：它是搭好的成品，
      // 单独拉宽会让内部布局比例失真。
      // 以水平位移为主导——把手在右下角，横向拖拽的意图最明确。
      final natural = UIRenderer.compositeNaturalSize(current.composite!);
      final aspect = natural.height / natural.width;
      var w = _resizeStartSize.width + localDx;
      // 先夹宽度，再由宽度推高度，保证比例不被两次独立夹取破坏。
      w = w.clamp(minSize.width, maxSize.width).toDouble();
      var h = w * aspect;
      if (h > maxSize.height) {
        h = maxSize.height;
        w = h / aspect;
      } else if (h < minSize.height) {
        h = minSize.height;
        w = h / aspect;
      }
      nextWidth = w;
      nextHeight = h;
    } else {
      nextWidth = (_resizeStartSize.width + localDx)
          .clamp(minSize.width, maxSize.width)
          .toDouble();
      nextHeight = (_resizeStartSize.height + localDy)
          .clamp(minSize.height, maxSize.height)
          .toDouble();
    }

    final nextSize = Size(nextWidth, nextHeight);
    // 以**当前**尺寸为基准修正，而不是拖动起点的尺寸——
    // 这里每帧都在增量修正，用起点尺寸会把偏移重复累加。
    final nextOffset = _offsetKeepingResizeAnchor(
      offset: current.offset,
      oldSize: current.size,
      newSize: nextSize,
      rotation: current.rotation,
    );

    setState(() {
      final module = current.module;
      // 手动改过尺寸就关掉自适应，否则下一帧又被算回去。
      if (module != null && module.properties['autoFit'] == true) {
        final props = Map<String, dynamic>.from(
          _deepCloneValue(module.properties) as Map,
        );
        props['autoFit'] = false;
        _elements[index] = current.copyWith(
          size: nextSize,
          offset: nextOffset,
          module: module.copyWith(properties: props),
        );
        return;
      }
      _elements[index] = current.copyWith(
        size: nextSize,
        offset: nextOffset,
      );
    });
  }

  bool _isDraggingConnection = false;
  String? _draggingSourceId;

  /// 'input' = 从 linker 左侧拉出（找数据来源）；
  /// 'output' = 从右侧拉出（找作用目标）。
  String? _draggingSourcePort;
  Offset? _dragConnectionEnd;
  String? _hoveringTargetId;

  // ===== 待定起拖（按下先不算数）=====
  //
  // 起初把 `_beginConnectionDrag` 直接绑在 `onPointerDown` 上，
  // 结果**双击断开彻底不可用并且崩溃**：
  // 双击的第一次按下就会启动一轮拖拽 → setState → linker 子树重建
  // （配置徽标随连线状态增减，Stack 子节点位置错位）→ GestureDetector
  // 被 unmount → DoubleTapGestureRecognizer.dispose → 竞技场清扫 →
  // 画布的 onTap 意外获胜 → 在树锁定期间 setState → 断言崩溃。
  //
  // 根本矛盾：「按下即起拖」与「双击」互斥——双击的两次按下
  // 每次都会启动一轮拖拽状态。
  // 因此按下只**记下待定**，位移超过阈值才真正起拖；
  // 纯点击（无位移）全程不改状态，把手势干净地留给 tap / doubleTap。
  String? _pendingWireSourceId;
  String? _pendingWirePort;
  Offset? _pendingWireOrigin;

  /// 起拖位移阈值。略小于 kTouchSlop(18)，
  /// 让接线比「拖动元件」更早被判定，避免手指刚动就把 linker 拖走。
  static const double _kWireDragSlop = 6.0;

  /// 可作为连线一端的候选元素。
  ///
  /// 排除 linker 自身、
  /// 复合黑盒与全锁元素。全锁的语义就是「连线不可改」，
  /// 因此它既不能作为新连线的目标，也不该被拖拽命中。
  bool _canBeConnectionEndpoint(UIElement el) {
    if (el.sealed) return false;
    // 复合件本身没有 module，但只要暴露了端口就能作为连线目标——
    // 实际连的是它内部那个被暴露的子元素（见 _exposedPortTargetsOf）。
    if (el.isComposite) return _exposedPortTargetsOf(el).isNotEmpty;
    final module = el.module;
    if (module == null) return false;
    if (module.type == 'linker') return false;
    return true;
  }

  /// 复合件对外暴露的可连接子元素。
  ///
  /// 复合是黑盒，作者不该、也无法直接选中它内部的组件；
  /// 制作复合件时勾选的「暴露端口」就是它与外界的唯一接口。
  /// 连线连的是这些子元素，而不是复合件外壳——
  /// 外壳没有 module，方案矩阵拿它算不出任何东西。
  List<UIElement> _exposedPortTargetsOf(UIElement composite) {
    final data = composite.composite;
    if (data == null) return const [];
    final ports = data.exposedPorts;
    if (ports == null || ports.isEmpty) return const [];
    final result = <UIElement>[];
    for (final port in ports) {
      for (final child in data.children) {
        if (child.id != port.elementId) continue;
        // 后端逻辑件不作为可视连接点（与画布渲染的过滤口径一致）。
        if (child.module == null) continue;
        result.add(child);
        break;
      }
    }
    return result;
  }

  /// 找出某个 id 所属的复合件（若它是复合内部的子元素）。
  ///
  /// 连线存的是子元素 id，但画线时要以复合件外壳为锚点——
  /// 子元素在复合内部的坐标是相对复合件的，直接拿去当画布坐标会错位。
  UIElement? _compositeOwnerOfChild(String childId) {
    for (final element in _elements) {
      if (!element.isComposite) continue;
      final data = element.composite;
      if (data == null) continue;
      for (final child in data.children) {
        if (child.id == childId) return element;
      }
    }
    return null;
  }

  /// 命中检测：落点是否在元素（含旋转）的矩形内。
  ///
  /// 与 Studio 的 `_isPointInsideRotatedRect` 同构——把落点逆旋转回
  /// 元素的局部坐标系再做矩形包含判断。
  /// 额外留 12px 容差，手指没那么精准。
  bool _isPointInsideAssemblyElement(Offset point, UIElement el) {
    final base = _canvasOffset + _pcbOffset;
    final elLeft = base.dx + el.offset.dx;
    final elTop = base.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;
    const pad = 12.0;
    final rect = Rect.fromLTWH(
      elLeft - pad,
      elTop - pad,
      el.size.width + pad * 2,
      el.size.height + pad * 2,
    );

    if (el.rotation == 0.0) return rect.contains(point);

    final rad = -el.rotation * math.pi / 180.0;
    final dx = point.dx - cx;
    final dy = point.dy - cy;
    return rect.contains(
      Offset(
        cx + dx * math.cos(rad) - dy * math.sin(rad),
        cy + dx * math.sin(rad) + dy * math.cos(rad),
      ),
    );
  }

  /// 按下端口热区：只记下待定，**不改任何状态**。
  ///
  /// 一旦在这里 setState，双击就会被自身引发的重建打断（见上方说明）。
  void _armConnectionDrag(UIElement linkerElement, String port, Offset at) {
    if (linkerElement.sealed) return; // 提示留到真正起拖时再给
    _pendingWireSourceId = linkerElement.id;
    _pendingWirePort = port;
    _pendingWireOrigin = at;
  }

  void _clearPendingWire() {
    _pendingWireSourceId = null;
    _pendingWirePort = null;
    _pendingWireOrigin = null;
  }

  /// 位移达到阈值，把待定升级为真正的拖拽。
  void _beginConnectionDrag(Offset at) {
    final id = _pendingWireSourceId;
    final port = _pendingWirePort;
    if (id == null || port == null) return;
    final element = _assemblyElementById(id);
    _clearPendingWire();
    if (element == null) return;

    // 全锁的 linker 连线不可改（与配置式对话框同一条规则）。
    if (element.sealed) {
      _showSnack('该联动器已全锁定，需先解除全锁才能改接线');
      return;
    }
    _selectElement(id);
    setState(() {
      _isDraggingConnection = true;
      _draggingSourceId = id;
      _draggingSourcePort = port;
      _dragConnectionEnd = at;
      _hoveringTargetId = null;
    });
  }

  /// 指针移动：先判断待定是否该升级，再更新拖拽。
  ///
  /// 返回 true 表示这次移动被接线逻辑消费，调用方不应再做别的处理。
  bool _handleWirePointerMove(Offset position) {
    if (_isDraggingConnection) {
      _updateConnectionDrag(position);
      return true;
    }
    final origin = _pendingWireOrigin;
    if (origin == null) return false;
    if ((position - origin).distance < _kWireDragSlop) return true;
    _beginConnectionDrag(position);
    if (_isDraggingConnection) _updateConnectionDrag(position);
    return true;
  }

  /// 指针抬起。返回 true 表示被接线逻辑消费。
  bool _handleWirePointerUp(Offset position) {
    if (_isDraggingConnection) {
      _updateConnectionDrag(position);
      _completeConnectionDrag();
      return true;
    }
    // 没起拖 = 这是一次点击，交给 tap / doubleTap 识别器，
    // 这里必须什么状态都不改，否则又会打断双击。
    final hadPending = _pendingWireOrigin != null;
    _clearPendingWire();
    return hadPending;
  }

  void _updateConnectionDrag(Offset globalPosition) {
    if (!_isDraggingConnection) return;
    String? hit;
    // 逆序遍历：_elements 越靠后越上层，命中应优先取最上面那个，
    // 与作者看到的层级一致。
    for (var i = _elements.length - 1; i >= 0; i--) {
      final el = _elements[i];
      if (el.id == _draggingSourceId) continue;
      if (!_canBeConnectionEndpoint(el)) continue;
      // 无需再筛页面：_elements 本就只含当前页的元素。
      if (_isPointInsideAssemblyElement(globalPosition, el)) {
        hit = el.id;
        break;
      }
    }
    setState(() {
      _dragConnectionEnd = globalPosition;
      _hoveringTargetId = hit;
    });
  }

  /// 把命中的元素解析为真正要写入连线的那一端。
  ///
  /// 命中复合件时，实际连的是它暴露的子元素：
  /// 只有一个就直接用，多个则让作者选——
  /// 静默挑第一个会让「连错了端口」变成一个查不出来的问题。
  Future<UIElement?> _resolveWiringTarget(UIElement hit) async {
    if (!hit.isComposite) return hit;
    final candidates = _exposedPortTargetsOf(hit);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    return _showExposedPortPicker(hit, candidates);
  }

  Future<UIElement?> _showExposedPortPicker(
    UIElement composite,
    List<UIElement> candidates,
  ) async {
    return showDialog<UIElement>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('选择「${composite.composite?.name ?? '复合组件'}」的端口'),
        children: [
          for (final child in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, child),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${child.module?.name.trim().isNotEmpty == true
                      ? child.module!.name
                      : child.id} · ${child.module?.type ?? ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _cancelConnectionDrag() {
    _clearPendingWire();
    if (!_isDraggingConnection) return;
    setState(() {
      _isDraggingConnection = false;
      _draggingSourceId = null;
      _draggingSourcePort = null;
      _dragConnectionEnd = null;
      _hoveringTargetId = null;
    });
  }

  /// 落点成线。
  ///
  /// 只写入被拖动的那一端（左侧写 sourceModuleId、右侧写 targetModuleId），
  /// 另一端保持原样——作者可能是在改接一条已配好的连线。
  Future<void> _completeConnectionDrag() async {
    final linkerId = _draggingSourceId;
    final port = _draggingSourcePort;
    final targetId = _hoveringTargetId;
    if (linkerId == null || port == null || targetId == null) {
      _cancelConnectionDrag();
      return;
    }

    final linkerIndex = _elements.indexWhere((e) => e.id == linkerId);
    final hitElement = _assemblyElementById(targetId);
    if (linkerIndex == -1 || hitElement == null) {
      _cancelConnectionDrag();
      return;
    }
    // 命中复合件时解析到具体的暴露子元素（可能弹选择框）。
    final target = await _resolveWiringTarget(hitElement);
    if (!mounted || target == null) {
      _cancelConnectionDrag();
      return;
    }
    final resolvedTargetId = target.id;

    final linkerElement = _elements[linkerIndex];
    final linkerModule = linkerElement.module;
    if (linkerModule == null) {
      _cancelConnectionDrag();
      return;
    }

    final existing = _linkerDataOf(linkerModule);
    final otherEndId = port == 'input'
        ? existing['targetModuleId']?.toString() ?? ''
        : existing['sourceModuleId']?.toString() ?? '';

    // 自连没有意义：来源与目标是同一个元素时，方案矩阵也算不出东西。
    if (otherEndId.isNotEmpty && otherEndId == resolvedTargetId) {
      _cancelConnectionDrag();
      _showSnack('联动器的两端不能是同一个组件');
      return;
    }

    // 另一端已被全锁时，这条连线整体不可改。
    final otherEnd =
        otherEndId.isEmpty ? null : _assemblyElementById(otherEndId);
    if (otherEnd != null && otherEnd.sealed) {
      _cancelConnectionDrag();
      _showSnack(
        '「${otherEnd.module?.name ?? otherEnd.id}」已全锁定，'
        '需先解除全锁才能修改这条联动',
      );
      return;
    }

    setState(() {
      final props = Map<String, dynamic>.from(
        _deepCloneValue(linkerModule.properties) as Map,
      );
      final linkerData = Map<String, dynamic>.from(
        props['linker'] is Map ? props['linker'] as Map : const {},
      );
      if (port == 'input') {
        linkerData['sourceModuleId'] = resolvedTargetId;
      } else {
        linkerData['targetModuleId'] = resolvedTargetId;
      }
      // 换了端点，旧方案未必还适用；等下面的方案选择重新落定。
      // 这里先不清 scheme——若作者取消选择，保留原样比清空更不突兀。
      props['linker'] = linkerData;
      _elements[linkerIndex] = linkerElement.copyWith(
        module: linkerModule.copyWith(properties: props),
      );
    });

    _cancelConnectionDrag();
    _persistAssemblyElements();

    // 两端齐了才弹方案选择（用户选定）。
    //
    // 只接了一半时方案根本算不出来——可用方案取决于「来源类型 + 目标类型」
    // 的组合，缺一端就是空列表，弹出来也是空的。
    await _maybePromptSchemeAfterWiring(linkerId);
  }

  /// 接线后按需弹出方案选择。
  ///
  /// 与 Studio 同样处理：两端齐备后先查方案矩阵，
  /// 若这对类型之间根本没有可用方案，自动断开并提示——
  /// 留着一条永远不会生效的连线只会让作者困惑。
  Future<void> _maybePromptSchemeAfterWiring(String linkerId) async {
    if (!mounted) return;
    final index = _elements.indexWhere((e) => e.id == linkerId);
    if (index == -1) return;
    final element = _elements[index];
    final module = element.module;
    if (module == null) return;

    final data = _linkerDataOf(module);
    final sourceId = data['sourceModuleId']?.toString() ?? '';
    final targetId = data['targetModuleId']?.toString() ?? '';
    if (sourceId.isEmpty || targetId.isEmpty) return;

    final source = _assemblyElementById(sourceId);
    final target = _assemblyElementById(targetId);
    final schemes = LinkerMatrixEngine.getAvailableSchemes(
      source?.module?.type,
      target?.module?.type,
    );
    if (schemes.isEmpty) {
      _disconnectLinkerBothEnds(element);
      _showSnack('这两个组件之间没有可用的联动方案，已自动断开');
      return;
    }

    await _showAssemblyLinkerConfigDialog(element);
  }

  /// 断开 linker 两端。双击端口热区也走这里的单端版本。
  void _disconnectLinkerBothEnds(UIElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    final module = element.module;
    if (module == null) return;
    setState(() {
      final props = Map<String, dynamic>.from(
        _deepCloneValue(module.properties) as Map,
      );
      final linkerData = Map<String, dynamic>.from(
        props['linker'] is Map ? props['linker'] as Map : const {},
      );
      linkerData
        ..remove('sourceModuleId')
        ..remove('sourcePort')
        ..remove('sourceType')
        ..remove('sourceGesture')
        ..remove('targetModuleId')
        ..remove('targetPort')
        ..remove('targetType')
        ..remove('inputConnection')
        ..remove('outputConnection')
        ..remove('schemeParams');
      linkerData['scheme'] = '未配置';
      linkerData['enabled'] = false;
      props['linker'] = linkerData;
      _elements[index] =
          element.copyWith(module: module.copyWith(properties: props));
    });
    _persistAssemblyElements();
  }

  /// 断开 linker 的单侧端口（双击该侧热区）。
  void _disconnectLinkerPort(UIElement element, String port) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    final module = element.module;
    if (module == null) return;
    if (element.sealed) {
      _showSnack('该联动器已全锁定，需先解除全锁才能断开连线');
      return;
    }
    setState(() {
      final props = Map<String, dynamic>.from(
        _deepCloneValue(module.properties) as Map,
      );
      final linkerData = Map<String, dynamic>.from(
        props['linker'] is Map ? props['linker'] as Map : const {},
      );
      if (port == 'input') {
        linkerData
          ..remove('sourceModuleId')
          ..remove('sourcePort')
          ..remove('sourceType')
          ..remove('sourceGesture')
          ..remove('inputConnection');
      } else {
        linkerData
          ..remove('targetModuleId')
          ..remove('targetPort')
          ..remove('targetType')
          ..remove('outputConnection');
      }
      // 少了一端，方案必然不再成立。
      linkerData['scheme'] = '未配置';
      linkerData['enabled'] = false;
      linkerData.remove('schemeParams');
      props['linker'] = linkerData;
      _elements[index] =
          element.copyWith(module: module.copyWith(properties: props));
    });
    _persistAssemblyElements();
  }

  /// 拖拽中的临时线。
  ///
  /// 与已落定的连线不同，这条**不调淡**——正在操作的东西需要看清。
  Widget _buildDraggingConnectionLine() {
    final sourceId = _draggingSourceId;
    final end = _dragConnectionEnd;
    if (!_isDraggingConnection || sourceId == null || end == null) {
      return const SizedBox.shrink();
    }
    final sourceEl = _assemblyElementById(sourceId);
    if (sourceEl == null) return const SizedBox.shrink();

    final isInputSide = _draggingSourcePort == 'input';
    final start = _assemblyPortOffset(sourceEl, isInputSide);
    final startDirection = _assemblyPortDirection(sourceEl, isInputSide);

    var lineEnd = end;
    var endDirection = _freeEndDirectionOf(start, end);
    final hoverEl = _hoveringTargetId == null
        ? null
        : _wireAnchorElementById(_hoveringTargetId!);
    if (hoverEl != null) {
      // 吸附到目标：端点落到它对侧的端口上。
      // 从 linker 左侧拉出时，我们要的是目标的**输出**口。
      lineEnd = _assemblyPortOffset(hoverEl, !isInputSide);
      endDirection = _assemblyPortDirection(hoverEl, !isInputSide);
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: LinkerConnectionPainter(
            start: start,
            end: lineEnd,
            color: hoverEl != null
                ? LinkerLineColors.hitTarget
                : LinkerLineColors.resolve(isInput: isInputSide),
            strokeWidth: 2.0,
            arrowSize: 7.0,
            startDirection: startDirection,
            endDirection: endDirection,
          ),
        ),
      ),
    );
  }

  /// 自由端（跟着手指、尚未吸附）的入线方向：朝来路收束。
  Offset _freeEndDirectionOf(Offset start, Offset end) {
    final delta = start - end;
    final distance = delta.distance;
    if (distance < 1e-3) return LinkerConnectionPainter.defaultEndDirection;
    return delta / distance;
  }

  /// 端口的**朝向**（单位向量，指向元件外侧）。
  ///
  /// 与 `_assemblyPortOffset` 配套：那个算端口在哪，这个算线该往哪冒。
  /// 只算位置不算朝向的话，元件转了 90°，线仍会先水平窜出去再拐回来，
  /// 看着像从元件侧面漏出来的（首轮测试反馈）。
  Offset _assemblyPortDirection(UIElement el, bool isInput, [String? portName]) {
    final base = portName == 'gate_in'
        ? LinkerConnectionPainter.gateEndDirection
        : (isInput
            ? LinkerConnectionPainter.defaultEndDirection
            : LinkerConnectionPainter.defaultStartDirection);
    return LinkerConnectionPainter.rotateDirection(base, el.rotation);
  }

  /// 连线层。放在元素之下、PCB 之上——
  /// 压在元件上面会挡住内容，尤其是文本与消息流。
  List<Widget> _buildAssemblyConnectionsLayer() {
    final connections = _assemblyLinkerConnections();
    if (connections.isEmpty) return const [];

    final widgets = <Widget>[];
    for (final conn in connections) {
      final fromId = conn['from'] as String?;
      final toId = conn['to'] as String?;
      if (fromId == null || toId == null) continue;
      final fromEl = _wireAnchorElementById(fromId);
      final toEl = _wireAnchorElementById(toId);
      // 端点可能已被删除（删元素时 linker 里的引用未必同步清理），
      // 画不出来就跳过，不要抛异常。
      if (fromEl == null || toEl == null) continue;

      final lineType = conn['type'] as String? ?? 'input';
      final toPort = conn['toPort'] as String?;
      final isControlLine = toPort == 'gate_in';
      // 端点解析到复合外壳，说明这条连的是复合件的暴露端口，
      // 用粉/浅蓝配色与普通连线区分（与 Studio 一致）。
      final isCompositePort = fromEl.isComposite || toEl.isComposite;

      widgets.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: LinkerConnectionPainter(
                start: _assemblyPortOffset(
                  fromEl,
                  false,
                  conn['fromPort'] as String?,
                ),
                end: _assemblyPortOffset(toEl, true, toPort),
                // 切线跟随元件旋转，避免线从端口水平窜出。
                startDirection: _assemblyPortDirection(
                  fromEl,
                  false,
                  conn['fromPort'] as String?,
                ),
                endDirection: _assemblyPortDirection(toEl, true, toPort),
                color: LinkerLineColors.resolve(
                  isInput: lineType == 'input',
                  isControlLine: isControlLine,
                  isCompositePort: isCompositePort,
                ),
                isControlLine: isControlLine,
                strokeWidth: _kAssemblyLineWidth,
                opacity: _kAssemblyLineOpacity,
                arrowSize: _kAssemblyArrowSize,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// A14-1a：当前选中的元素（原子与复合共用）。
  ///
  /// 此前只有 `_selectedCompositeId`，且仅用于展开复合组件的覆写槽位——
  /// 原子组件根本没有选中态，导致「选中后弹出针对性工具」无从谈起。
  /// 这是补齐画布操作（删除 / 复制 / 层级…）的前提。
  String? get _selectedElementId => _selectedCompositeId;

  /// 选中的元素本体；未选中或已被删除时为 null。
  UIElement? get _selectedElement {
    final id = _selectedCompositeId;
    if (id == null) return null;
    for (final element in _elements) {
      if (element.id == id) return element;
    }
    return null;
  }

  void _selectElement(String id) {
    if (_selectedCompositeId == id) return;
    setState(() {
      _selectedCompositeId = id;
      // 换了元素就收起方向键：否则手指还停在原处，
      // 下一次点击会挪动刚选中的另一个组件。
      _showNudgePad = false;
    });
  }

  /// 兼容旧调用点：复合组件的选中语义与通用选中已合并。
  void _selectComposite(String id) => _selectElement(id);

  void _clearElementSelection() {
    if (_selectedCompositeId == null) return;
    // 兜底：这个回调可能在 widget 树锁定期间被触发——
    // 手势竞技场清扫（GestureArenaManager.sweep）发生在
    // BuildOwner.finalizeTree 卸载子树的过程中，
    // 此刻 setState 会抛「widget tree was locked」。
    // 实测路径：接线导致 linker 子树重建 → 其 GestureDetector 被 unmount
    // → DoubleTapGestureRecognizer.dispose → sweep → 画布 onTap 获胜。
    // 已在调用侧加了拦截，这里再兜一层，避免同类路径再次崩溃。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedCompositeId == null) return;
        setState(() {
          _selectedCompositeId = null;
          _showNudgePad = false;
        });
      });
      return;
    }
    setState(() {
      _selectedCompositeId = null;
      _showNudgePad = false;
    });
  }

  void _clearCompositeSelection() => _clearElementSelection();

  // ========== A14-1b：选中外框形状 ==========
  //
  // 与 Studio 共用同一套判定，保证同一个组件在两个编辑器里
  // 选中外框长得一样。直接照搬 `ui_studio_page/logic.dart` 的实现——
  // 这三个函数是纯查表，抽公共模块的收益不抵引入依赖的成本。

  /// 复合组件的容器面：选中外框以它为形状参考。
  ///
  /// 复合是黑盒，本身没有形状；但作者摆它时看到的就是那个容器面，
  /// 外框贴合容器面才不会出现「框是方的、组件是圆的」。
  UIElement? _compositeBoundaryOf(UIElement el) {
    if (!el.isComposite || el.composite == null) return null;
    for (final child in el.composite!.children) {
      if (!child.isComposite &&
          child.module?.properties['is_container_boundary'] == true) {
        return child;
      }
    }
    return null;
  }

  UIModuleShape _outlineShapeOf(UIElement el) {
    if (el.isComposite) {
      final boundary = _compositeBoundaryOf(el);
      if (boundary != null) return _outlineShapeOf(boundary);
      return UIModuleShape.rounded;
    }
    final mod = el.module;
    if (mod == null) return UIModuleShape.rounded;
    if (mod.type == 'progress') {
      final progShape = mod.properties['progressShape']?.toString();
      if (progShape == 'rectangle') return UIModuleShape.rectangle;
      if (progShape == 'heart') return UIModuleShape.heart;
      if (progShape == 'ring') return UIModuleShape.circle;
      return UIModuleShape.capsule;
    }
    if (mod.type == 'text' || mod.type == 'input' || mod.type == 'button' || mod.type == 'line') {
      return UIModuleShape.rectangle;
    }
    if (mod.type == 'switch') {
      return UIModuleShape.capsule;
    }
    if (mod.type == 'math_node' || mod.type == 'select') {
      return UIModuleShape.rectangle;
    }
    if (mod.type == 'timer') {
      return UIModuleShape.rounded;
    }
    if (mod.type == 'indicator') {
      return UIModuleShape.circle;
    }
    if (mod.type == 'image') {
      final shapeStr = mod.properties['shape']?.toString();
      if (shapeStr == 'circle') return UIModuleShape.circle;
      if (shapeStr == 'capsule') return UIModuleShape.capsule;
      return UIModuleShape.rounded;
    }
    return mod.shape;
  }

  /// 复合件内容相对其自然尺寸的缩放比。
  ///
  /// 与 `UIRenderer._renderComposite` 里的计算保持一致：等比取较小值。
  double _compositeContentScale(UIElement el) {
    final data = el.composite;
    if (data == null) return 1.0;
    final natural = UIRenderer.compositeNaturalSize(data);
    if (natural.width <= 0 || natural.height <= 0) return 1.0;
    return math.min(
      el.size.width / natural.width,
      el.size.height / natural.height,
    );
  }

  double _outlineBorderRadiusOf(UIElement el) {
    if (el.isComposite) {
      final boundary = _compositeBoundaryOf(el);
      if (boundary != null) {
        // 容器面被 Transform.scale 一起缩放了，它的**视觉**圆角是
        // 原始值 × 缩放比；而虚线框画在未缩放的外框上。
        // 不乘这个系数，放大/缩小后虚线框的圆角就与容器面对不上
        // （用户反馈：边框不贴合容器面）。
        //
        // 只有 rounded 形状受影响——rectangle / circle / capsule /
        // heart / star 的路径都由 rect 自适应推导，跟着盒子走。
        return _outlineBorderRadiusOf(boundary) *
            _compositeContentScale(el);
      }
      return 12;
    }
    final mod = el.module;
    if (mod == null) return 12;
    if (mod.type == 'progress') {
      final progShape = mod.properties['progressShape']?.toString();
      if (progShape == 'rectangle') return 0;
      return 999;
    }
    if (mod.type == 'text' || mod.type == 'input' || mod.type == 'button') {
      return 4;
    }
    if (mod.type == 'line') {
      return 0;
    }
    if (mod.type == 'switch') {
      return 999;
    }
    if (mod.type == 'timer') {
      return 12.0;
    }
    if (mod.type == 'math_node' || mod.type == 'select') {
      return 6.0;
    }
    if (mod.type == 'image') {
      return (mod.properties['borderRadius'] ?? 8.0).toDouble();
    }
    return mod.borderRadius;
  }

  bool _isPerfectCircleOutlineOf(UIElement el) {
    if (el.isComposite) {
      final boundary = _compositeBoundaryOf(el);
      if (boundary != null) return _isPerfectCircleOutlineOf(boundary);
      return false;
    }
    final mod = el.module;
    if (mod == null) return false;
    if (mod.type == 'indicator' || (mod.type == 'progress' && mod.properties['progressShape'] == 'ring')) {
      return true;
    }
    return false;
  }

  // ========== A14-1b：画布元素操作 ==========

  /// 找出指向某元素的所有 linker（作为源或目标都算）。
  List<UIElement> _linkersReferencing(String elementId) {
    return _elements.where((element) {
      final module = element.module;
      if (module == null || module.type != 'linker') return false;
      final data =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data == null) return false;
      return data['sourceModuleId']?.toString() == elementId ||
          data['targetModuleId']?.toString() == elementId;
    }).toList();
  }

  /// 删除元素，并连带清理指向它的联动器。
  ///
  /// 留着悬空连线比删掉更糟：`isSchemeSelectable` 仍判为合法，
  /// 运行端却找不到源/目标，表现为「配了但没反应」，极难排查。
  Future<void> _confirmDeleteElement(UIElement element) async {
    final orphans = _linkersReferencing(element.id);
    final name = element.module?.name ?? element.composite?.name ?? '该组件';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「$name」？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删除后无法撤销。'),
            if (orphans.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '还有 ${orphans.length} 个联动器连着它，会一并删除。\n'
                  '（保留悬空连线会导致运行时静默失效，比删掉更难排查）',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE65100),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removeIds = {element.id, ...orphans.map((e) => e.id)};
    setState(() {
      _elements.removeWhere((e) => removeIds.contains(e.id));
      // A14-1c：删掉的若是容器面，组员会指向一个不存在的父级，
      // 导致运行时 `isElementVisibleInSurfaceHierarchy` 判定失败而整组隐身。
      // 解除它们的归属，就地留在当前层级（与「出组保留显示层级」一致）。
      for (var i = 0; i < _elements.length; i++) {
        final parent = _elements[i].parentSurfaceId;
        if (parent != null && removeIds.contains(parent)) {
          _elements[i] = _elements[i].copyWith(clearParentSurface: true);
        }
      }
      // 覆写槽位随复合组件一起消失，否则会留下指向不存在组件的孤儿配置。
      _activePropertyOverrides
          .removeWhere((o) => removeIds.contains(o.componentId));
      _selectedCompositeId = null;
    });
    _setupEventBusListener();
    _persistAssemblyElements();
  }

  /// 复制元素。新元素稍作偏移，避免与原件完全重叠而看不出来。
  void _duplicateElement(UIElement element) {
    // 联动器不复制：它的源/目标指向具体元素，复制出来必然是重复连线，
    // 作者要的几乎总是「再连一条新的」而不是「同一条来两遍」。
    if (element.module?.type == 'linker') {
      _showSnack('联动器请重新拖入并配置，复制会产生重复连线');
      return;
    }

    final copy = _cloneElementWithNewIds(element);
    setState(() {
      _elements.add(copy.copyWith(
        offset: element.offset + const Offset(12, 12),
      ));
      _selectedCompositeId = copy.id;
    });
    _persistAssemblyElements();
  }

  /// 深拷贝元素并重新分配 id。
  ///
  /// `UIElement.copyWith` 不接受 id（它是 final、不可改），
  /// 因此在 JSON 层面替换后再反序列化。
  ///
  /// 用 `jsonEncode/Decode` 而不是 `_deepCloneValue`：后者对嵌套 Map
  /// 返回 `Map<dynamic, dynamic>`，而 `UIElement.fromJson` 里
  /// `json['offset'] as Map<String, dynamic>?` 是硬类型转换，会直接抛
  /// `_TypeError`（复制时崩溃）。JSON 往返能保证嵌套层的键类型。
  UIElement _cloneElementWithNewIds(UIElement source) {
    final json = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(source.toJson())) as Map,
    );
    json['id'] = _generateElementId();
    return UIElement.fromJson(json);
  }

  /// 调整元素在绘制顺序中的位置。
  ///
  /// `_elements` 的顺序即 Stack 的绘制顺序：**越靠后越上层**。
  /// 因此界面上的「上移一层」= 在列表里往后挪一位（delta = +1）。
  ///
  /// A14-1c 之后分三种情况：
  ///   - 组内成员 → 只在同组兄弟之间移动（规则 1）
  ///   - 父级面   → 整组一起移动（规则 2）
  ///   - 顶层元素 → 在顶层元素之间移动，跨组时整组跳过
  void _moveElementLayer(UIElement element, int delta) {
    final parentId = element.parentSurfaceId;
    if (parentId != null && parentId.isNotEmpty) {
      _moveMemberWithinGroup(element, parentId, delta);
      return;
    }
    if (_isSurfaceElement(element) && _surfaceGroupIds(element.id).length > 1) {
      _moveSurfaceGroupOrder(element.id, delta);
      return;
    }
    _moveTopLevelElement(element, delta);
  }

  /// 该元素在其所属层级里还能否朝指定方向移动。
  ///
  /// 与 `_moveElementLayer` 用同一套分支，避免按钮可点却没反应。
  bool _canMoveElementLayer(UIElement element, int delta) {
    final parentId = element.parentSurfaceId;
    if (parentId != null && parentId.isNotEmpty) {
      final siblings =
          _elements.where((e) => e.parentSurfaceId == parentId).toList();
      final i = siblings.indexWhere((e) => e.id == element.id);
      final t = i + delta;
      return i != -1 && t >= 0 && t < siblings.length;
    }

    if (_isSurfaceElement(element) && _surfaceGroupIds(element.id).length > 1) {
      final groupIds = _surfaceGroupIds(element.id);
      final others = _elements.where((e) => !groupIds.contains(e.id)).length;
      final firstIndex = _elements.indexWhere((e) => groupIds.contains(e.id));
      if (firstIndex == -1) return false;
      final blockStart = _elements
          .take(firstIndex)
          .where((e) => !groupIds.contains(e.id))
          .length;
      final target = blockStart + delta;
      return target >= 0 && target <= others;
    }

    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return false;
    return index + delta >= 0 && index + delta < _elements.length;
  }

  /// 规则 1：组内成员只与同组兄弟换位，不会窜出组外。
  void _moveMemberWithinGroup(UIElement element, String parentId, int delta) {
    final siblings = _elements
        .where((e) => e.parentSurfaceId == parentId)
        .toList();
    final memberIndex = siblings.indexWhere((e) => e.id == element.id);
    final targetMember = memberIndex + delta;
    if (memberIndex == -1 ||
        targetMember < 0 ||
        targetMember >= siblings.length) {
      return;
    }

    final fromIndex = _elements.indexWhere((e) => e.id == element.id);
    final toIndex =
        _elements.indexWhere((e) => e.id == siblings[targetMember].id);
    if (fromIndex == -1 || toIndex == -1) return;

    setState(() {
      final moved = _elements.removeAt(fromIndex);
      _elements.insert(toIndex, moved);
      // 换位后重整一次，保证父面仍在块首（规则 3）。
      _normalizeSurfaceGroupOrder(parentId);
    });
    _persistAssemblyElements();
  }

  /// 规则 2：父级面变换层级 = 整组一起变换。
  void _moveSurfaceGroupOrder(String surfaceId, int delta) {
    _normalizeSurfaceGroupOrder(surfaceId);
    final groupIds = _surfaceGroupIds(surfaceId);
    final grouped = _elements.where((e) => groupIds.contains(e.id)).toList();
    if (grouped.isEmpty) return;

    final others = _elements.where((e) => !groupIds.contains(e.id)).toList();
    final firstIndex = _elements.indexWhere((e) => groupIds.contains(e.id));
    final blockStart =
        _elements.take(firstIndex).where((e) => !groupIds.contains(e.id)).length;
    // 整块在 others 中的落点前后各挪一格。
    final target = blockStart + delta;
    if (target < 0 || target > others.length) return;

    setState(() {
      _elements
        ..clear()
        ..addAll(others.take(target))
        ..addAll(grouped)
        ..addAll(others.skip(target));
    });
    _persistAssemblyElements();
  }

  /// 顶层元素之间移动。跨越某个组时整组一起跳过，
  /// 避免顶层元素卡在别人的组中间把组切断。
  void _moveTopLevelElement(UIElement element, int delta) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;

    var target = index + delta;
    while (target >= 0 && target < _elements.length) {
      final crossed = _elements[target];
      final crossedRoot = _rootSurfaceOf(crossed) ??
          (_isSurfaceElement(crossed) ? crossed.id : null);
      if (crossedRoot == null) break;
      // 落点在某个组内部：继续往同方向跨，直到越过整组。
      final groupIds = _surfaceGroupIds(crossedRoot);
      if (groupIds.length <= 1) break;
      target += delta;
    }
    if (target < 0 || target >= _elements.length) return;

    setState(() {
      final moved = _elements.removeAt(index);
      _elements.insert(target, moved);
    });
    _persistAssemblyElements();
  }

  /// 切换半锁定（`layoutLocked`）：锁住位置 / 形变 / 旋转。
  ///
  /// 用模型上已有的 `layoutLocked` 字段而不是自造 `properties['locked']`——
  /// Studio 侧本来就用它，两边共用同一份数据，方案在两个编辑器间迁移时
  /// 锁定状态才不会丢。
  void _toggleElementLayoutLock(UIElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    setState(() {
      _elements[index] =
          element.copyWith(layoutLocked: !element.layoutLocked);
    });
    _persistAssemblyElements();
  }

  /// 切换全锁定（`sealed`）：在半锁定基础上额外锁死联动。
  ///
  /// 全锁定后：已有连线不能切换或断开，没有连线则连不上，
  /// 配置联动器时该元素会被跳过（与 Studio 的 `sealed` 语义一致）。
  void _toggleElementSealed(UIElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    final next = !element.sealed;
    setState(() {
      _elements[index] = element.copyWith(
        sealed: next,
        // 全锁定必然包含半锁定的约束，一起打开更符合直觉；
        // 解除全锁定时保留半锁定，让作者自己决定要不要一并解开。
        layoutLocked: next ? true : element.layoutLocked,
      );
    });
    _persistAssemblyElements();
  }

  /// 元素是否被任一档锁定禁止结构性改动（删除 / 复制 / 层级）。
  bool _isStructureLocked(UIElement element) =>
      element.layoutLocked || element.sealed;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                      llmReadPolicy: llmReadPolicy,
                      llmWritePolicy: llmWritePolicy,
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
          applyPolicy: applyPolicy,
          promptSection: promptSection,
          cardTarget: cardTarget,
        );
      }
      setState(() {
        _upsertPropertyOverride(
          propertyOverride.copyWith(overrides: nextOverrides),
        );
      });
    }
    nameController.dispose();
    cardCustomTitleController.dispose();
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

  Map<String, dynamic> _linkerDataOf(UIModule module) {
    final raw = module.properties['linker'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
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
    // A12 通用动画触发：目标端口是动画通道，不写任何数据字段。
    // 必须放在最前面——它以 `_to_animation` 结尾，
    // 不拦住会被后面的通配规则误判。
    if (scheme == 'event_to_animation') return 'anim';
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
  /// 该联动器是否因两端存在全锁元素而不可编辑。
  ///
  /// 已配好的连线若有一端后来被全锁，必须阻止改动——
  /// 否则「锁死连线」形同虚设。
  UIElement? _sealedEndpointOf(UIModule linkerModule) {
    final data = _linkerDataOf(linkerModule);
    final ids = <String?>[
      data['sourceModuleId']?.toString(),
      data['targetModuleId']?.toString(),
    ];
    for (final element in _elements) {
      if (!element.sealed) continue;
      if (ids.contains(element.id)) return element;
    }
    return null;
  }

  String _linkerCandidateLabel(UIElement element) {
    final module = element.module!;
    final name = module.name.trim();
    return name.isEmpty ? module.type : '$name · ${module.type}';
  }

  /// 连线端点的只读展示行。
  ///
  /// 取代原来的下拉选择器：两端由画线决定，这里只告诉作者
  /// 「现在连的是谁」，以及没连时该怎么连。
  Widget _buildLinkerEndpointRow({
    required String label,
    required UIElement? element,
    required Color color,
    required String emptyHint,
  }) {
    final connected = element != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: connected
            ? color.withValues(alpha: 0.08)
            : const Color(0xFFF3F3F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: connected
              ? color.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? color : const Color(0xFFBDBDBD),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF555562),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected ? _linkerCandidateLabel(element) : emptyHint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: connected
                    ? const Color(0xFF111116)
                    : const Color(0xFF9999A5),
                fontStyle: connected ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
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

    // 已连的两端若有一端被全锁，禁止改动这条连线。
    final sealedEnd = _sealedEndpointOf(module);
    if (sealedEnd != null) {
      _showSnack(
        '「${sealedEnd.module?.name ?? sealedEnd.id}」已全锁定，'
        '需先解除全锁才能修改这条联动',
      );
      return;
    }

    final existing = _linkerDataOf(module);
    // 两端只读：由画线写入，配置面板不再提供选择器。
    final sourceId = existing['sourceModuleId']?.toString() ?? '';
    final targetId = existing['targetModuleId']?.toString() ?? '';
    var scheme = existing['scheme']?.toString() ?? '';
    // 方案参数（如消息操作要执行哪个动作）。与 Studio 侧一致地按 key 存取，
    // 这样同一条 linker 在两边打开看到的配置完全相同。
    var schemeParams = <String, dynamic>{
      ...(existing['schemeParams'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    };
    // 来源为 button 时的触发手势（单击 / 双击 / 长按）。
    //
    // 不为「双击触发某某」单开方案 id——那会让方案矩阵翻三倍。
    // 手势只影响写出去的 sourcePort，运行端 LinkerService 本就按
    // 'tap' / 'double_tap' / 'long_press' 三个端口名分派，无需改动。
    // 好处是同一个按钮可以挂三条连线，三种触控各接各的目标。
    var sourceGesture = existing['sourceGesture']?.toString() ?? '';

    // 两端由画线决定，这里只做展示与校验。
    //
    // 端点可能已被删除，或是复合件内部的暴露子元素——
    // 后者不在 `_elements` 顶层，要走 `_wiringEndpointById` 深查。
    UIElement? byId(String id) => id.isEmpty ? null : _wiringEndpointById(id);

    final saved = await showDialog<String>(
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
          // 端点可能在画线时被改接到别的组件，旧方案未必还适用。
          if (schemes.every((def) => def.id != scheme)) {
            scheme = '';
            // 参数属于具体方案，方案没了就必须清掉——
            // 留着会把上一个方案的键带进新方案的配置里。
            schemeParams = <String, dynamic>{};
          }

          final canSave = source != null && target != null && scheme.isNotEmpty;

          return AlertDialog(
            title: const Text('配置联动器'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 两端只读展示。
                    //
                    // 来源 / 目标由**画线**决定，不再给下拉选择——
                    // 同一件事有两个入口时，作者会困惑「哪个才算数」，
                    // 而且下拉列表在元件一多时根本找不到目标。
                    // 画线是所见即所得的，端点关系一眼就能看清。
                    _buildLinkerEndpointRow(
                      label: '来源',
                      element: source,
                      color: LinkerLineColors.input,
                      emptyHint: '拖动联动器左侧接出',
                    ),
                    const SizedBox(height: 8),
                    _buildLinkerEndpointRow(
                      label: '目标',
                      element: target,
                      color: LinkerLineColors.output,
                      emptyHint: '拖动联动器右侧接出',
                    ),
                    const SizedBox(height: 16),
                    ...[
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
                          '两端都接好后才能选择联动方案。',
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
                      // 触发手势：仅当来源是 button 时才有意义。
                      if (source?.module?.type == 'button' &&
                          scheme.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '触发手势',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111116),
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: sourceGesture.isEmpty
                              ? 'tap'
                              : sourceGesture,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: const [
                            DropdownMenuItem(
                              value: 'tap',
                              child: Text('单击'),
                            ),
                            DropdownMenuItem(
                              value: 'double_tap',
                              child: Text('双击'),
                            ),
                            DropdownMenuItem(
                              value: 'long_press',
                              child: Text('长按'),
                            ),
                          ],
                          onChanged: (next) {
                            if (next == null) return;
                            setDialogState(() => sourceGesture = next);
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '同一个按钮可以建多条连线，'
                            '让单击 / 双击 / 长按分别触发不同的目标。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF777783),
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (sourceGesture != 'tap' &&
                            scheme == 'click_to_surface_press')
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              '提示：按压 / 涟漪属于即时视觉反馈，'
                              '改用双击或长按后要等判定时间结束才会播放，'
                              '手感会明显变迟钝。',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFE65100),
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
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
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消'),
              ),
              TextButton(
                // 直接断开并关闭，不再靠「清空下拉 + 保存」。
                //
                // 旧写法只把两个下拉设空，但 canSave 要求两端非空，
                // 保存按钮会立刻变灰、提交不了——清除等于失效
                // （移除下拉时才发现的既存 bug）。
                onPressed: (sourceId.isEmpty && targetId.isEmpty)
                    ? null
                    : () => Navigator.pop(ctx, 'clear'),
                child: const Text('清除连接'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(ctx, 'save') : null,
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == 'clear' && mounted) {
      _disconnectLinkerBothEnds(linkerElement);
      return;
    }

    if (saved == 'save' && mounted) {
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

        {
          // 两端由画线写入、此处只读，且 canSave 已保证三者非空，
          // 因此不再需要「清空」分支——断开一律走「清除连接」按钮，
          // 它直接调用 _disconnectLinkerBothEnds。
          final def = LinkerMatrixEngine.getSchemeDefinition(scheme);
          linkerData['sourceModuleId'] = sourceId;
          linkerData['targetModuleId'] = targetId;
          linkerData['scheme'] = scheme;
          linkerData['enabled'] = true;
          // 端口与类型由方案定义推导，保持与 Studio 侧一致。
          // button 来源额外允许用手势覆写端口（见 sourceGesture 的说明）。
          final basePort = _schemeSourcePort(scheme);
          final isButtonSource =
              byId(sourceId)?.module?.type == 'button' && basePort == 'tap';
          if (isButtonSource && sourceGesture.isNotEmpty) {
            linkerData['sourcePort'] = sourceGesture;
            linkerData['sourceGesture'] = sourceGesture;
          } else {
            linkerData['sourcePort'] = basePort;
            linkerData.remove('sourceGesture');
          }
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

        // A13-3：配额分配的目标连上即归零。
        //
        // 在这里做而不是在渲染时做，有两个原因：
        //   - 渲染时改属性需要一个「是否已初始化」的持久标记，
        //     而它会被 _persistAssemblyElements 存进角色卡；
        //   - 池子统计已分配量读的是各目标的 current，
        //     不落到属性上就会把 slider 模板默认的 50 继续计入
        //     （表现为「一连上线池子就少 50」）。
        if (scheme == 'pool_to_allocation') {
          final saved =
              (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
          _zeroAllocationTarget(
            targetId,
            (saved['initialValue'] as num?)?.toDouble() ?? 0.0,
          );
        }
      });
      _setupEventBusListener();
      _persistAssemblyElements();
    }
  }

  /// 把配额分配的目标组件归到初始值。
  void _zeroAllocationTarget(String targetElementId, double initialValue) {
    final index =
        _elements.indexWhere((element) => element.id == targetElementId);
    if (index == -1) return;
    final element = _elements[index];
    final module = element.module;
    if (module == null) return;

    final props = Map<String, dynamic>.from(
      _deepCloneValue(module.properties) as Map,
    );
    if (module.type == 'input') {
      // input 把值存在 text/value，没有 min/max 概念。
      final text = initialValue == initialValue.roundToDouble()
          ? initialValue.toInt().toString()
          : initialValue.toString();
      props['text'] = text;
      props['value'] = text;
      props['committedValue'] = text;
    } else {
      final min = (props['min'] as num?)?.toDouble() ?? 0.0;
      final max = (props['max'] as num?)?.toDouble() ?? 100.0;
      final value = initialValue.clamp(min, max).toDouble();
      props['current'] = value;
      // committedValue 也要跟上，否则数据通道读到的仍是旧值。
      props['committedValue'] = value;
    }
    _elements[index] = element.copyWith(
      module: module.copyWith(properties: props),
    );
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
      // 多源聚合与其他方案的用法完全不同：必须给每个来源各连一条到
      // 同一目标。不明说的话作者只会连一条然后以为方案坏了
      // （首轮测试反馈「看不懂怎么操作」）。
      if (scheme == 'pool_to_allocation')
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '来源 = 可分配总量，目标 = 参与分配的组件。\n'
            '总量直接读来源组件的内容：文本里写「10」就是 10 点，'
            '改文本即改总量，无需在下方填写。\n'
            '从同一个总量组件，给每个分配组件各连一条本方案的连线。\n'
            '分配组件会自动归零，并被限制在剩余额度内；'
            '来源是文本时会实时显示剩余可分配数。',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF2E7D32),
              height: 1.4,
            ),
          ),
        ),
      if (scheme == 'sum_to_display')
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '这个方案要连多条：给每个要参与求和的组件，都建一条本方案的连线，'
            '并且目标都选同一个组件。目标就会显示它们的总和。\n'
            '配额总量、模板等参数只需在其中一条上填写。',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF2E7D32),
              height: 1.4,
            ),
          ),
        ),
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
    // A13-3 求和汇总的超额策略。
    if (option == 'allow') return '允许超出（剩余显示为负数）';
    if (option == 'clamp') return '限制在总量内（不允许超出）';
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

  // ========== A14-1c：容器归属（分组）==========

  static const Set<String> _surfaceTypes = {
    'surface',
    'surface_art',
    'primitive_art',
    'base_box',
  };

  bool _isSurfaceElement(UIElement element) =>
      !element.isComposite && _surfaceTypes.contains(element.module?.type);

  /// 能否被指派归属。
  ///
  /// 纯逻辑件排除在外：它们运行时不渲染，谈不上「在某个面板里」。
  bool _canAssignSurfaceMembership(UIElement element) =>
      !_isLogicOnlyElement(element);

  /// 防环：不能把 A 挂到自己的后代下面。
  bool _wouldCreateSurfaceParentCycle(String childId, String parentId) {
    var currentId = parentId;
    final visited = <String>{};
    while (currentId.isNotEmpty && visited.add(currentId)) {
      if (currentId == childId) return true;
      final index = _elements.indexWhere((e) => e.id == currentId);
      if (index == -1) return false;
      currentId = _elements[index].parentSurfaceId ?? '';
    }
    return false;
  }

  /// 组内全部 id（父面 + 递归后代）。
  Set<String> _surfaceGroupIds(String surfaceId) {
    final ids = <String>{surfaceId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final element in _elements) {
        final parent = element.parentSurfaceId;
        if (parent != null && ids.contains(parent) && ids.add(element.id)) {
          grew = true;
        }
      }
    }
    return ids;
  }

  /// 组内元素按「父面在前、成员依次在后」排列。
  ///
  /// 这是规则 3 的落点：子组件恒高于父级面，
  /// 因为 `_elements` 越靠后越上层，父面排在块首即为最底。
  List<UIElement> _orderedSurfaceGroupElements(String surfaceId) {
    final byId = {for (final e in _elements) e.id: e};
    final ordered = <UIElement>[];
    void visit(String id) {
      final surface = byId[id];
      if (surface == null) return;
      ordered.add(surface);
      for (final child in _elements) {
        if (child.parentSurfaceId != id) continue;
        if (_isSurfaceElement(child)) {
          visit(child.id);
        } else {
          ordered.add(child);
        }
      }
    }

    visit(surfaceId);
    return ordered;
  }

  /// 把整组收拢成连续块并置于父面原位。
  ///
  /// 规则 4：进组 / 出组的**那一刻**就重整，而不是等作者手动切一次层级。
  /// Studio 是事后补救（`_moveMemberWithinSurfaceGroup` 里发现顺序颠倒才修），
  /// 导致必须多切一下才能真正进入组层级。
  void _normalizeSurfaceGroupOrder(String surfaceId) {
    final groupIds = _surfaceGroupIds(surfaceId);
    if (groupIds.length <= 1) return;
    final grouped = _orderedSurfaceGroupElements(surfaceId);
    if (grouped.isEmpty) return;

    final firstIndex =
        _elements.indexWhere((e) => groupIds.contains(e.id));
    if (firstIndex == -1) return;
    // 组块插回「原先第一个组成员之前有多少个非组成员」的位置，
    // 这样整组在画布上的相对高度不变。
    final insertAt =
        _elements.take(firstIndex).where((e) => !groupIds.contains(e.id)).length;
    final others =
        _elements.where((e) => !groupIds.contains(e.id)).toList();

    _elements
      ..clear()
      ..addAll(others.take(insertAt))
      ..addAll(grouped)
      ..addAll(others.skip(insertAt));
  }

  /// 元素所属组的根父面 id；无归属返回 null。
  String? _rootSurfaceOf(UIElement element) {
    var parent = element.parentSurfaceId;
    if (parent == null || parent.isEmpty) return null;
    final visited = <String>{element.id};
    while (true) {
      if (!visited.add(parent!)) return null;
      final index = _elements.indexWhere((e) => e.id == parent);
      if (index == -1) return null;
      final next = _elements[index].parentSurfaceId;
      if (next == null || next.isEmpty) return parent;
      parent = next;
    }
  }

  /// 设置 / 解除归属。
  Future<void> _showSurfaceMembershipDialog(UIElement element) async {
    if (!_canAssignSurfaceMembership(element)) {
      _showSnack('逻辑组件不参与容器归属');
      return;
    }

    final surfaces = _elements.where((candidate) {
      if (candidate.id == element.id) return false;
      if (!_isSurfaceElement(candidate)) return false;
      return !_wouldCreateSurfaceParentCycle(element.id, candidate.id);
    }).toList();

    var selected = element.parentSurfaceId;

    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('容器归属'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Radio 的 groupValue / onChanged 自 3.32 起废弃，
                  // 改由 RadioGroup 统一管理选中值与回调。
                  RadioGroup<String?>(
                    groupValue: selected,
                    onChanged: (v) => setDialogState(() => selected = v),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RadioListTile<String?>(
                          value: null,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('顶层元素（不属于任何面板）'),
                        ),
                        const Divider(height: 1),
                        if (surfaces.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              '当前页面还没有可作容器的面板。'
                              '请先从「基础显示」拖入一个面板。',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFE65100),
                                height: 1.35,
                              ),
                            ),
                          )
                        else
                          for (final surface in surfaces)
                            RadioListTile<String?>(
                              value: surface.id,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(surface.module?.name ?? surface.id),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '归属后：面板隐藏时组内组件一起隐藏；'
                    '调整面板层级会带动整组；'
                    '组内组件只能在面板之上调整层级。',
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );

    if (applied != true || !mounted) return;
    if (selected == element.parentSurfaceId) return;

    final previousParent = element.parentSurfaceId;
    setState(() {
      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index == -1) return;
      _elements[index] = _elements[index].copyWith(
        parentSurfaceId: selected,
        clearParentSurface: selected == null,
      );

      // 规则 4：进组立即重整，作者不用再手动切一次层级。
      if (selected != null) {
        _normalizeSurfaceGroupOrder(selected!);
      }
      // 出组时**不移动位置**（规则 5）：保留它在组内的显示层级，
      // 而不是弹回进组前的旧位置——所见即所得。
      // 但原组仍需重整，因为成员少了一个。
      if (previousParent != null && previousParent.isNotEmpty) {
        final stillExists =
            _elements.any((e) => e.id == previousParent);
        if (stillExists) _normalizeSurfaceGroupOrder(previousParent);
      }
    });
    _persistAssemblyElements();
  }

  // ========== A14-1d：精确几何 / 精确位移 ==========

  /// 纯逻辑件：运行时不渲染，只在编辑器里显形。
  ///
  /// 它们没有视觉尺寸与朝向可言，因此不提供精确几何编辑。
  /// 位置仍可拖动——作者会靠摆放位置给逻辑件分区归类。
  bool _isLogicOnlyElement(UIElement element) {
    final type = element.module?.type;
    if (type == null) return false;
    return const {'linker', 'page_router', 'math_node', 'timer'}
        .contains(type);
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

    final applied = await showDialog<bool>(
      context: context,
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

    // 延后到下一帧再释放：弹窗的退场动画期间 TextField 仍会重建，
    // 立即 dispose 会命中「controller used after disposed」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      xc.dispose();
      yc.dispose();
      wc.dispose();
      hc.dispose();
      rc.dispose();
    });
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

    final saved = await showDialog<bool>(
      context: context,
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtrl.dispose();
      intervalCtrl.dispose();
      delayCtrl.dispose();
      maxTicksCtrl.dispose();
      stepCtrl.dispose();
    });
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
    // button 的手势判定手感。默认值与渲染端 _ButtonGestureWidget 保持一致。
    final doubleTapIntervalController = TextEditingController(
      text: (_intProp(module.properties, 'doubleTapIntervalMs') ?? 300)
          .toString(),
    );
    final longPressThresholdController = TextEditingController(
      text: (_intProp(module.properties, 'longPressThresholdMs') ?? 500)
          .toString(),
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
    var channelPromptSection = existingChannel?['promptSection']?.toString() ??
        DataChannelPromptItem.sectionUiData;
    var channelCardTarget =
        CardEntryTarget.fromJson(existingChannel?['cardEntryTarget']) ??
            const CardEntryTarget(
                group: CardEntryTarget.groupIntro, entryId: '', fieldKey: '');
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '按钮是一块「点击热区」，运行时不显形。\n'
                          '想让玩家看到按下的反馈，请用联动器把它连到一个'
                          ' surface，选择按压或涟漪方案。',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF555562),
                            height: 1.4,
                          ),
                        ),
                      ),
                      // 手感参数只在真的用到双击 / 长按时才出现，
                      // 否则平白多两个数字框，作者还得猜它们干嘛用。
                      if (_buttonUsesNonTapGesture(element.id)) ...[
                        const SizedBox(height: 12),
                        numberField(
                          doubleTapIntervalController,
                          '双击判定间隔（毫秒，100~1000）',
                        ),
                        const SizedBox(height: 12),
                        numberField(
                          longPressThresholdController,
                          '长按判定时长（毫秒，150~3000）',
                        ),
                      ],
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
                                  final changed =
                                      await _openDataChannelPage(module);
                                  if (changed) setDialogState(() {});
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

    if (!mounted) {
      _disposeAtomEditorControllers([
        nameController,
        textController,
        fontSizeController,
        radiusController,
        minController,
        maxController,
        currentController,
        thicknessController,
        doubleTapIntervalController,
        longPressThresholdController,
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
            // 热区不再承载文案：清掉历史遗留键，
            // 否则旧卡里存着的 text 会在升级后继续被渲染端误读。
            props
              ..remove('text')
              ..remove('showTextOnRuntime')
              ..remove('active_gesture');
            final interval =
                int.tryParse(doubleTapIntervalController.text.trim());
            if (interval == null) {
              props.remove('doubleTapIntervalMs');
            } else {
              props['doubleTapIntervalMs'] = interval.clamp(100, 1000);
            }
            final threshold =
                int.tryParse(longPressThresholdController.text.trim());
            if (threshold == null) {
              props.remove('longPressThresholdMs');
            } else {
              props['longPressThresholdMs'] = threshold.clamp(150, 3000);
            }
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
          // A14-3：通道细节由专项页面直接写入 props，这里只管开关。
          //
          // 不能再从本对话框的状态变量重建 payload——专项页保存后，
          // 这些变量仍是打开实例编辑器那一刻的旧值，
          // 重建会把刚配好的内容覆盖掉。
          if (!channelEnabled) {
            props.remove('dataChannel');
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
              applyPolicy: channelApplyPolicy,
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
        _persistAssemblyElements();
      }
    }

    _disposeAtomEditorControllers([
      nameController,
      textController,
      fontSizeController,
      radiusController,
      minController,
      maxController,
      currentController,
      thicknessController,
      doubleTapIntervalController,
      longPressThresholdController,
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
    // AB 批只改表单 UI，这两个字段继续按原样存写：
    // visibility 已从 UI 删除（死字段），applyPolicy 的语义迁移留到 CD 批。
    // 现在断掉存写会让已有角色卡的通道配置在下次保存时丢字段。
    required String visibility,
    required String applyPolicy,
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
      'llmUpdateApplyPolicy': applyPolicy,
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

  // ========== A14-3：外观专项页 ==========

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

  /// A14-3：数据通道专项页。
  ///
  /// 从实例编辑器里抽出来单独成页——通道配置有十来项
  /// （语义来源 / 存放位置 / 卡片三级定位 / 读写策略 / 注入位置…），
  /// 内嵌会把对话框撑得又长又乱，此前「方案参数编辑器漏做」
  /// 与「三级选择器藏太深」都是这么来的。
  ///
  /// 内容先原样承接现有表单，后续再做优化（用户要求）。
  /// 返回 true 表示配置有改动。
  Future<bool> _openDataChannelPage(UIModule module) async {
    final elementIndex =
        _elements.indexWhere((e) => e.module?.id == module.id);
    final element = elementIndex == -1 ? null : _elements[elementIndex];
    if (element == null) return false;

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
    var applyPolicy =
        existing?['llmUpdateApplyPolicy']?.toString() ?? 'confirm';
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

    var changed = false;
    if (saved == true && mounted) {
      final name = _resolveDataChannelName(
        semanticSource: semanticSource,
        manualName: nameController.text,
        labelElementId: labelElementId,
        labels: labels,
        fallbackName: module.name,
      ).trim();

      final index = _elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        final current = _elements[index];
        final currentModule = current.module;
        if (currentModule != null) {
          final props = Map<String, dynamic>.from(
            _deepCloneValue(currentModule.properties) as Map,
          );
          if (name.isEmpty) {
            props.remove('dataChannel');
          } else {
            props['dataChannel'] = _buildDataChannelPayload(
              name: name,
              semanticSource: semanticSource,
              labelElementId: labelElementId,
              sourceComponentId: current.id,
              module: currentModule,
              targetKind: targetKind,
              visibility: visibility,
              llmReadPolicy: readPolicy,
              llmWritePolicy: writePolicy,
              applyPolicy: applyPolicy,
              promptSection: promptSection,
              cardTarget: cardTarget,
            );
          }
          setState(() {
            _elements[index] = current.copyWith(
              module: currentModule.copyWith(properties: props),
            );
          });
          _persistAssemblyElements();
          changed = true;
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      cardTitleController.dispose();
    });
    return changed;
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
    required String promptSection,
    required CardEntryTarget cardTarget,
    required TextEditingController cardCustomTitleController,
    required ValueChanged<CardEntryTarget> onCardTarget,
    required ValueChanged<String> onSemanticSource,
    required ValueChanged<String> onLabelElementId,
    required ValueChanged<String> onTargetKind,
    required ValueChanged<String> onReadPolicy,
    required ValueChanged<String> onWritePolicy,
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
      default:
        return '';
    }
  }

  void _createPage({required String type}) {
    _syncCanvasStateIntoActivePage();
    final pageType = type == 'overlay' ? 'overlay' : 'base';
    // 叠加页恒为平级页的直接子级，**不允许嵌套**（用户明确规则）。
    //
    // 旧实现允许在叠加页上再建叠加页（最深 3 层），
    // 那是错误前提：叠加层无论如何都不能变成子叠加层。
    // 因此当前页若本身是叠加页，新叠加页挂到它所属的平级页下，
    // 而不是挂到它自己下面。
    final String? parentPageId = pageType == 'overlay'
        ? (_baseAncestorOf(_activePage) ?? _rootBasePage).id
        : null;
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

  /// 叠加页的换父候选 = **其他平级页**。
  ///
  /// 换父级是「同一类型的父级之间切换」：叠加页永远挂在某个平级页下，
  /// 换的是挂在哪一个平级页。叠加层无论如何都不能变成子叠加层，
  /// 因此候选里不含任何叠加页。
  ///
  /// 平级页没有父级，不参与换父（返回空表）。
  List<AssemblyPage> _reparentCandidatesForPage(AssemblyPage page) {
    if (!page.isOverlay) return const <AssemblyPage>[];
    final candidates = _pages
        .where((candidate) =>
            candidate.isBase && candidate.id != page.parentPageId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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
    _applyPageReparent(page.id, selectedParentId);
  }

  /// 执行换父。弹窗与拖放共用同一条通路——
  /// 两份实现迟早会漂移（sortOrder 重排这种事最容易只改一边）。
  ///
  /// 返回是否真的改动了。
  bool _applyPageReparent(String pageId, String newParentId) {
    final pageIndex = _pages.indexWhere((candidate) => candidate.id == pageId);
    if (pageIndex == -1) return false;
    final oldParentId = _pages[pageIndex].parentPageId;
    if (oldParentId == newParentId) return false;

    // 叠加页恒为平级页的直接子级，所以新父级必须是平级页。
    // 这一条同时天然排除了成环：平级页没有父级，构不成环。
    final newParent = _pageById(newParentId);
    if (newParent == null || !newParent.isBase) return false;
    if (!_pages[pageIndex].isOverlay) return false;

    assert(
      _pageDepth(newParent) == 0,
      '平级页深度必须为 0，否则「叠加页不嵌套」的不变式已被破坏',
    );

    _pushHistory();

    final newSiblingCount =
        _pages.where((p) => p.parentPageId == newParentId).length;
    _pages[pageIndex].parentPageId = newParentId;
    _pages[pageIndex].sortOrder = newSiblingCount;

    // 原父级下的兄弟重排，补上离开留下的空位。
    final oldSiblings = _pages
        .where((p) => p.parentPageId == oldParentId && p.id != pageId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < oldSiblings.length; i++) {
      final index =
          _pages.indexWhere((candidate) => candidate.id == oldSiblings[i].id);
      if (index != -1) _pages[index].sortOrder = i;
    }

    setState(() {});
    _persistAssemblyElements();
    return true;
  }

  // ==========================================================================
  // 灵感池 4.2：叠加页拖放换父级
  // ==========================================================================
  //
  // 手势冲突是这样消解的（用户的观察）：
  //
  // | 页面类型 | 有无父级 | 需要的操作 |
  // |---|---|---|
  // | 平级页 | 无父级 | 只需排序 |
  // | 叠加页 | 有父级 | 只需换父（同级顺序不影响打开） |
  //
  // **每种页面只有一种拖动行为**，因此不需要在同一套手势里区分
  // 「排序」与「换父」两种意图——那正是当初判定「手势风险高」的根源。
  // 平级页保留 ReorderableListView，叠加页整体换成 Draggable/DragTarget。

  /// 正在被拖动的叠加页 id。null 表示没有拖放进行中。
  String? _draggingPageId;

  /// 当前悬停其上的候选父页 id。
  String? _dragHoverParentId;

  /// 某个页面能否作为 [pageId] 的新父级。
  ///
  /// 判据与 `_reparentCandidatesForPage` 保持一致——
  /// 拖放能放进去、弹窗里却查不到这个候选，会让作者觉得随机。
  /// 能否把 [pageId] 拖到 [targetId] 下。
  ///
  /// 规则极简：**被拖的必须是叠加页，落点必须是平级页**。
  /// 叠加层不能变成子叠加层，所以叠加页永远不是合法落点——
  /// 这一条同时天然消除了成环的可能（平级页没有父级，构不成环）。
  bool _canDropPageInto(String pageId, String targetId) {
    final pageIndex = _pages.indexWhere((p) => p.id == pageId);
    if (pageIndex == -1) return false;
    final page = _pages[pageIndex];
    if (!page.isOverlay) return false;
    if (page.parentPageId == targetId) return false;

    final targetIndex = _pages.indexWhere((p) => p.id == targetId);
    if (targetIndex == -1) return false;
    return _pages[targetIndex].isBase;
  }

  void _beginPageDrag(String pageId) {
    setState(() {
      _draggingPageId = pageId;
      _dragHoverParentId = null;
    });
  }

  void _endPageDrag() {
    if (_draggingPageId == null && _dragHoverParentId == null) return;
    setState(() {
      _draggingPageId = null;
      _dragHoverParentId = null;
    });
  }

  void _setPageDragHover(String? targetId) {
    if (_dragHoverParentId == targetId) return;
    setState(() => _dragHoverParentId = targetId);
  }

  /// 落下：执行换父并给出反馈。
  void _handlePageDrop(String pageId, String targetId) {
    final pageName = _displayPageNameById(pageId);
    final targetName = _displayPageNameById(targetId);
    final moved = _applyPageReparent(pageId, targetId);
    _endPageDrag();
    if (!moved || !mounted) return;
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF455A64),
        content: Text(
          '「$pageName」已移入「$targetName」',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  String _displayPageNameById(String pageId) {
    final index = _pages.indexWhere((p) => p.id == pageId);
    if (index == -1) return '页面';
    return _displayPageName(_pages[index]);
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

  // ===== 画布级撤销 =====
  //
  // 此前完全没有撤销机制，删除对话框只能写「删除后无法撤销」。
  //
  // 快照打在 `_persistAssemblyElements` 里而不是逐个操作点：
  // 所有改动最终都汇到这个函数，逐个改调用点必然漏。
  // 代价是连续拖动会产生大量快照，用时间去重解决（见 _pushHistory）。

  /// 历史栈。每项是一次 `_persistAssemblyElements` 之前的画布状态。
  final List<String> _history = <String>[];

  /// 栈深上限。角色卡的元素 JSON 可能不小，无限堆会吃内存。
  static const int _maxHistory = 40;

  /// 正在应用撤销，期间不记录新快照（否则撤销本身会入栈）。
  bool _applyingHistory = false;

  DateTime? _lastSnapshotAt;

  bool get _canUndo => _history.isNotEmpty;

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

  /// 撤销一步。
  void _undo() {
    if (_history.isEmpty) return;
    final snapshot = _history.removeLast();
    _applyingHistory = true;
    try {
      final decoded = jsonDecode(snapshot);
      if (decoded is! List) return;
      final restored = decoded
          .whereType<Map>()
          .map((e) => AssemblyPage.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (restored.isEmpty) return;

      setState(() {
        _pages
          ..clear()
          ..addAll(restored);
        // 当前页可能已被删掉，回落到第一页。
        if (!_pages.any((p) => p.id == _activePageId)) {
          _activePageId = _pages.first.id;
        }
        _selectedCompositeId = null;
        _showNudgePad = false;
        _loadActivePageState();
      });
      _setupEventBusListener();
      // 撤销结果要落盘，否则退出后又变回去了。
      _persistAssemblyElements();
    } catch (_) {
      // 快照损坏就放弃这一步，不要炸掉页面。
    } finally {
      _applyingHistory = false;
    }
  }

  // ===== 画布级操作 =====

  /// 批量删除模式：选中多个元件一次删掉。
  ///
  /// 与单选删除并存——单选走左侧操作栏的删除按钮，
  /// 批量走这里。两者都不碰锁定元件。
  bool _multiDeleteMode = false;
  final Set<String> _pendingDeleteIds = <String>{};

  void _toggleMultiDeleteMode() {
    setState(() {
      _multiDeleteMode = !_multiDeleteMode;
      _pendingDeleteIds.clear();
      if (_multiDeleteMode) {
        // 进入批量模式先取消单选，否则两套选中态会同时显示。
        _selectedCompositeId = null;
        _showNudgePad = false;
      }
    });
  }

  void _togglePendingDelete(UIElement element) {
    // 锁定的元件不参与批量删除——锁定的语义就是「别动它」。
    if (element.layoutLocked || element.sealed) {
      _showSnack('「${element.module?.name ?? element.id}」已锁定，请先解锁');
      return;
    }
    setState(() {
      if (!_pendingDeleteIds.remove(element.id)) {
        _pendingDeleteIds.add(element.id);
      }
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (_pendingDeleteIds.isEmpty) return;
    final count = _pendingDeleteIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('将删除选中的 $count 个组件。可用左侧「撤销」找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // 先记快照再改，撤销才能回到删除前。
    _pushHistory();
    final removeIds = Set<String>.from(_pendingDeleteIds);
    setState(() {
      _elements.removeWhere((e) => removeIds.contains(e.id));
      // A14-1c：删掉的若是容器面，组员会指向一个不存在的父级，
      // 导致运行时 `isElementVisibleInSurfaceHierarchy` 判定失败而整组隐身。
      // 解除它们的归属，就地留在当前层级。
      for (var i = 0; i < _elements.length; i++) {
        final parent = _elements[i].parentSurfaceId;
        if (parent != null && removeIds.contains(parent)) {
          _elements[i] = _elements[i].copyWith(clearParentSurface: true);
        }
      }
      // 覆写槽位随组件一起消失，否则会留下指向不存在组件的孤儿配置。
      _activePropertyOverrides
          .removeWhere((o) => removeIds.contains(o.componentId));
      _pendingDeleteIds.clear();
      _multiDeleteMode = false;
      _selectedCompositeId = null;
    });
    _setupEventBusListener();
    _persistAssemblyElements();
  }

  /// 清空当前页的所有元件。
  Future<void> _confirmClearCanvas() async {
    if (_elements.isEmpty) {
      _showSnack('当前页面还没有组件');
      return;
    }
    final count = _elements.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空画布'),
        content: Text(
          '将删除当前页面的全部 $count 个组件（含已锁定的）。\n'
          '只影响当前页，其他页面不变。可用左侧「撤销」找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    _pushHistory();
    setState(() {
      _elements.clear();
      _activePropertyOverrides.clear();
      _selectedCompositeId = null;
      _showNudgePad = false;
      _multiDeleteMode = false;
      _pendingDeleteIds.clear();
    });
    _persistAssemblyElements();
  }

  void _persistAssemblyElements() {
    _pushHistory();
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
    _info.pcbRadius = _pcbRadius;
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

  /// 元件出 PCB 的三态分类。
  ///
  /// | 类别 | 类型 | 规则 |
  /// |---|---|---|
  /// | 原生后台节点 | linker / math_node / timer / page_router | 随便摆 |
  /// | 可后台化白名单 | text / switch / progress / indicator / input | 走 4.1 双阈值 |
  /// | 其余原子 + 复合件 | button / slider / select / surface / ... | **必须留在 PCB 内** |
  ///
  /// 第三类此前完全没有约束，是个真缺口（用户发现）：
  /// 它们既不像后台节点那样运行时有存在意义，
  /// 也不在后台化白名单里，拖出去等于**静默丢失**——
  /// 编辑器里看得见，一进运行时就没了，作者根本不知道发生了什么。
  bool _requiresPcbContainment(UIElement element) {
    if (element.isComposite) return true;
    final type = element.module?.type;
    // 原生后台节点：运行时本就 `SizedBox.shrink`，摆哪都行。
    // 作者常特意把它们拖到 PCB 外当「后台机房」，别拦。
    if (_isNativeBackendNodeType(type)) return false;
    // 可后台化白名单：由 4.1 的双阈值滞回接管，不走硬夹取。
    if (_canUseBackgroundRuntimePlacement(element)) return false;
    return true;
  }

  /// 天生的后台逻辑节点类型。
  ///
  /// 与 `UIRenderer.render` 里非 Studio 模式直接 `SizedBox.shrink`
  /// 的那份清单对应；`timer` 在渲染器里走 `_renderComposite` 的
  /// `backendTypes`，同属此类。
  static bool _isNativeBackendNodeType(String? type) => const {
        'linker',
        'math_node',
        'timer',
        _pageRouterType,
      }.contains(type);

  // ==========================================================================
  // 灵感池 4.1：拖出 PCB 自动后台化（双阈值滞回）
  // ==========================================================================
  //
  // 目标是消灭「半进半出」这个尴尬状态：元件要么老实待在 PCB 里，
  // 要么明确变成后台逻辑节点，中间地带不允许长期停留。
  //
  // 两个阈值必须**不相等**，否则元件会在边界上来回抖：
  // 每帧越界一点点 → 被吸回内壁 → 下一帧手指还在外面 → 又越界。
  // 滞回（hysteresis）的意思就是「进」和「出」用两条不同的线。
  //
  //   |<-- PCB 内 -->|  吸附带  |   后台区
  //   ---------------+---------+------------→ 越界深度
  //                  0      _kBackstageDetach(56)
  //
  // - 越界深度 ∈ (0, 56)：吸附，元件被拉回内壁，显示"松手回到画布"提示
  // - 越界深度 ≥ 56：脱离吸附，跟手自由拖动，显示"松手转为后台"
  // - 从后台区往回拖，越界深度 ≤ 24 时才重新吸附（回吸阈值更小 = 滞回）

  /// 脱离吸附、切换为后台的阈值（元件边界越过 PCB 内壁的距离）。
  static const double _kBackstageDetachThreshold = 56.0;

  /// 从后台区拖回时重新吸附的阈值。必须 < 脱离阈值，这就是滞回。
  static const double _kBackstageReattachThreshold = 24.0;

  /// 本次拖动是否已脱离吸附（跨帧状态，onPanStart 重置）。
  bool _dragDetachedFromPcb = false;

  /// 当前拖动中的元件 id 与它的后台预判结果，仅用于画布提示。
  String? _backstageHintElementId;
  bool _backstageHintWillBackstage = false;

  /// 元件是否允许后台化。
  ///
  /// 白名单与 Studio 的 `_canUseBackgroundRuntimePlacement` 保持一致——
  /// 这是跨编辑器契约，两边不一致会出现「Studio 能标 Assembly 不能」的怪事。
  /// 复合件永远不许出 PCB（3.1 已确认的产品规则），因此直接排除。
  ///
  /// linker / math_node / timer / page_router 不在白名单里是**刻意的**：
  /// 它们天生就是后台节点（`UIRenderer.render` 里非 Studio 模式直接
  /// `SizedBox.shrink`），再给一个后台标记既多余又会让作者以为
  /// 「不标就会显示」。它们摆在 PCB 外也不受边界阈值约束。
  bool _canUseBackgroundRuntimePlacement(UIElement element) {
    const backgroundCapableTypes = {
      'text',
      'switch',
      'progress',
      'indicator',
      'input',
    };
    return !element.isComposite &&
        backgroundCapableTypes.contains(element.module?.type);
  }

  bool _isBackstageElement(UIElement element) =>
      element.module?.properties['runtimePlacement'] == 'background';

  /// 元件矩形越过 PCB 内壁的深度（PCB 局部坐标，不含 `_pcbOffset`）。
  ///
  /// 返回 0 表示完全在内。四个方向取最大值：只要有一边探出去了，
  /// 探得最远的那一边决定当前处于哪个带。
  ///
  /// 用轴对齐包围盒而非旋转后的真实四角：后台化是个粗判定，
  /// 旋转元件的精确外接框会让阈值手感随角度漂移，反而不好用。
  double _pcbOverflowDepth(Offset offset, Size size, {double rotation = 0.0}) {
    final bounds = _rotatedBounds(size, rotation);
    final origin = offset + bounds.delta;
    final double left = -origin.dx;
    final double top = -origin.dy;
    final double right = origin.dx + bounds.size.width - _pcbSize.width;
    final double bottom = origin.dy + bounds.size.height - _pcbSize.height;
    final double depth = math.max(
      math.max(left, top),
      math.max(right, bottom),
    );
    return depth <= 0 ? 0.0 : depth;
  }

  /// 拖动开始：重置本次拖动的滞回状态。
  ///
  /// **必须在每次 onPanStart 调用**，否则上一次拖动的「已脱离」
  /// 会泄漏到下一次，导致刚起手就直接判后台。
  void _beginBackstageDragTracking(UIElement element) {
    // 已经是后台的元件，起手就算脱离状态——它本来就在外面，
    // 不该一碰就被吸回画布里。
    _dragDetachedFromPcb = _isBackstageElement(element);
    _backstageHintElementId = null;
    _backstageHintWillBackstage = false;
  }

  /// 拖动中：按双阈值滞回决定最终 offset，并更新画布提示。
  ///
  /// 返回值是**修正后的** offset，调用方应当直接采用它。
  /// 不允许后台化的元件原样返回（它们可以随便摆在 PCB 外，
  /// 那是老早就有的行为：「位移不限制负坐标，逻辑件常被特意拖出 PCB」）。
  Offset _resolveBackstageDragOffset(UIElement element, Offset desired) {
    if (!_canUseBackgroundRuntimePlacement(element)) {
      _backstageHintElementId = null;
      _backstageHintWillBackstage = false;
      // 不可后台化的普通原子（button / slider / surface / image ...）
      // 必须留在 PCB 内：它们运行时照常渲染，拖出去等于静默丢失。
      // 原生后台节点（linker / math_node / timer / page_router）不在此列，
      // `_requiresPcbContainment` 已把它们放行。
      return _requiresPcbContainment(element)
          ? _clampOffsetInsidePcb(
              desired,
              element.size,
              rotation: element.rotation,
            )
          : desired;
    }

    final double depth = _pcbOverflowDepth(
      desired,
      element.size,
      rotation: element.rotation,
    );

    if (_dragDetachedFromPcb) {
      // 已脱离：只有拖回到「回吸阈值」以内才重新被吸附。
      if (depth <= _kBackstageReattachThreshold) {
        _dragDetachedFromPcb = false;
      }
    } else {
      // 未脱离：越过脱离阈值才放行。
      if (depth >= _kBackstageDetachThreshold) {
        _dragDetachedFromPcb = true;
        // 手感反馈：这一下是状态跳变，值得震一下。
        HapticFeedback.selectionClick();
      }
    }

    final bool willBackstage = _dragDetachedFromPcb;
    // 提示只在真的贴近/越过边界时出现。元件老老实实在 PCB 中间挪动时
    // 顶上挂个横条纯属干扰。
    if (depth > 0) {
      _backstageHintElementId = element.id;
      _backstageHintWillBackstage = willBackstage;
    } else {
      _backstageHintElementId = null;
      _backstageHintWillBackstage = false;
    }

    return willBackstage
        ? desired
        : _clampOffsetInsidePcb(
            desired,
            element.size,
            rotation: element.rotation,
          );
  }

  /// 拖动结束：按最终位置落定 `runtimePlacement`。
  ///
  /// 调用方在 `_persistAssemblyElements()` **之前**调用它，
  /// 这样标记变更和位置变更进同一次持久化，撤销时也是一步退回。
  void _commitBackstageDragResult(String elementId) {
    _backstageHintElementId = null;
    _backstageHintWillBackstage = false;

    final index = _elements.indexWhere((e) => e.id == elementId);
    if (index == -1) {
      _dragDetachedFromPcb = false;
      return;
    }
    final element = _elements[index];
    if (!_canUseBackgroundRuntimePlacement(element) || element.module == null) {
      _dragDetachedFromPcb = false;
      return;
    }

    final bool shouldBackstage = _dragDetachedFromPcb;
    _dragDetachedFromPcb = false;

    if (shouldBackstage == _isBackstageElement(element)) return;

    final props = Map<String, dynamic>.from(element.module!.properties);
    if (shouldBackstage) {
      props['runtimePlacement'] = 'background';
    } else {
      props.remove('runtimePlacement');
    }
    _elements[index] = element.copyWith(
      module: element.module!.copyWith(properties: props),
    );
    HapticFeedback.selectionClick();
    _showBackstageToggleToast(shouldBackstage);
  }

  void _showBackstageToggleToast(bool toBackstage) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            toBackstage ? const Color(0xFF546E7A) : const Color(0xFF37474F),
        content: Text(
          toBackstage
              ? '已转为后台节点：运行时不显示，仍参与数据与连线'
              : '已移回画布：运行时正常显示',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  /// 手动切换后台标记。拖动之外的兜底入口（比如元件被锁定不能拖）。
  void _toggleElementBackstage(UIElement element) {
    if (!_canUseBackgroundRuntimePlacement(element) || element.module == null) {
      return;
    }
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;

    _pushHistory();
    final bool toBackstage = !_isBackstageElement(element);
    final props = Map<String, dynamic>.from(element.module!.properties);
    if (toBackstage) {
      props['runtimePlacement'] = 'background';
    } else {
      props.remove('runtimePlacement');
      // 从后台移回时，元件很可能还停在 PCB 外面。
      // 不把它拉回来的话，作者会看到「已移回画布」但屏幕上啥也没多出来。
      _elements[index] = _elements[index].copyWith(
        offset: _clampOffsetInsidePcb(
          element.offset,
          element.size,
          rotation: element.rotation,
        ),
      );
    }
    setState(() {
      _elements[index] = _elements[index].copyWith(
        module: _elements[index].module!.copyWith(properties: props),
      );
    });
    HapticFeedback.selectionClick();
    _showBackstageToggleToast(toBackstage);
    _persistAssemblyElements();
  }

  Rect get _pcbLocalRect => Rect.fromLTWH(
    _pcbOffset.dx,
    _pcbOffset.dy,
    _pcbSize.width,
    _pcbSize.height,
  );

  /// A14-5：PCB 自定义面板。
  ///
  /// 补的是一个**真缺口**：`pcbColorValue` / 圆角这两个字段
  /// 数据结构、序列化、渲染全都齐了，但全局没有任何赋值点，
  /// 只在初始化时读一次——PCB 永远是白色圆角，作者根本改不了。
  /// 与 A14-3 之前「Assembly 一个取色器都没有」是同一类缺口。
  ///
  /// 尺寸虽然能拖手柄改，但拖不出精确值（想要正好 300 宽只能碰运气），
  /// 因此这里一并给出数值输入，与 A14-2 给元件补精确几何同理。
  Future<void> _showPcbSettingsDialog() async {
    var color = _pcbColor;
    var radius = _pcbRadius;
    final widthController = TextEditingController(
      text: _pcbSize.width.toStringAsFixed(0),
    );
    final heightController = TextEditingController(
      text: _pcbSize.height.toStringAsFixed(0),
    );

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
          title: const Text('画布设置'),
          // 带 TextField 的弹窗一律包滚动：键盘弹出时会 overflow。
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '底色',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  _buildColorPalette(
                    color,
                    (picked) => setDialogState(() => color = picked),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        '圆角',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        radius.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777783),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: radius.clamp(0.0, UIAssemblyInfo.kMaxPcbRadius),
                    min: 0,
                    max: UIAssemblyInfo.kMaxPcbRadius,
                    divisions: UIAssemblyInfo.kMaxPcbRadius.toInt(),
                    onChanged: (v) => setDialogState(() => radius = v),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '尺寸',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      '也可以直接拖画布右侧与底部的手柄；'
                      '这里用于填精确数值。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widthController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '宽',
                            isDense: true,
                            helperText: '${_pcbMinWidth.toStringAsFixed(0)}'
                                '~${_pcbMaxWidthForMode.toStringAsFixed(0)}',
                            helperStyle: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: heightController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '高',
                            isDense: true,
                            helperText: '${_pcbMinHeight.toStringAsFixed(0)}'
                                '~${_pcbMaxHeight.toStringAsFixed(0)}',
                            helperStyle: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_info.mode == 'extra_companion')
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        '伴生 UI 内嵌在 AI 消息气泡里，宽度上限比其余模式更窄；'
                        '超出会被运行时等比缩小，字号与间距都会变样。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          height: 1.35,
                        ),
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
      // 输入非法（空 / 非数字）时保留原值，不要跳回默认尺寸——
      // 作者辛苦拖出来的画布不该因为手滑清空输入框就没了。
      final nextWidth = _clampPcbWidth(
        double.tryParse(widthController.text.trim()) ?? _pcbSize.width,
      );
      final nextHeight = _clampPcbHeight(
        double.tryParse(heightController.text.trim()) ?? _pcbSize.height,
      );
      setState(() {
        _pcbColor = color;
        _pcbRadius = radius.clamp(0.0, UIAssemblyInfo.kMaxPcbRadius);
        _pcbSize = Size(nextWidth, nextHeight);
      });
      _persistAssemblyElements();
    }

    // 控制器延后释放：弹窗退场动画期间仍会读它。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widthController.dispose();
      heightController.dispose();
    });
  }

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

  /// 把 offset 夹进 PCB 内。
  ///
  /// 原名 `_clampCompositeOffsetInsidePcb`——现在约束对象不止复合件，
  /// 普通原子也要夹，名字里的 Composite 已经误导。
  /// 也用作 4.1 的「吸附回内壁」：贴边，不是塞回中心。
  Offset _clampOffsetInsidePcb(
    Offset desired,
    Size size, {
    double rotation = 0.0,
  }) {
    // 旋转元件按旋转后的包围盒夹取，否则与退出校验的四角判定打架。
    final bounds = _rotatedBounds(size, rotation);
    // 包围盒左上角 = desired + delta，先把 desired 换算到包围盒坐标系。
    final boxOrigin = desired + bounds.delta;
    // PCB 比元件还小时 max 会变负，clamp 会抛异常，所以先兜底。
    final maxX = math.max(0.0, _pcbSize.width - bounds.size.width);
    final maxY = math.max(0.0, _pcbSize.height - bounds.size.height);
    final clamped = Offset(
      boxOrigin.dx.clamp(0.0, maxX).toDouble(),
      boxOrigin.dy.clamp(0.0, maxY).toDouble(),
    );
    // 再换算回元件左上角。
    return clamped - bounds.delta;
  }

  Offset _applyPlacementConstraints(UIElement prototype, Offset desired) {
    if (!_requiresPcbContainment(prototype)) return desired;
    return _clampOffsetInsidePcb(
      desired,
      prototype.size,
      rotation: prototype.rotation,
    );
  }

  /// 旋转后四角的轴对齐包围盒（相对元件左上角的偏移量 + 尺寸）。
  ///
  /// 旋转元件不做这一步就会**死锁**：`_isElementInsidePcb` 按旋转后的
  /// 四角判定，而夹取若按未旋转的 w×h 来算，贴边后四角仍探在外面——
  /// 退出时被拦下「请先移回可视区域」，可作者已经拖到头了，移不动。
  ///
  /// `Transform.rotate` 绕**中心**旋转，所以先算出旋转后包围盒相对
  /// 中心的半宽半高，再换算回左上角。
  ({Offset delta, Size size}) _rotatedBounds(Size size, double rotation) {
    if (rotation == 0.0) {
      return (delta: Offset.zero, size: size);
    }
    final radians = rotation * math.pi / 180.0;
    final cosA = math.cos(radians).abs();
    final sinA = math.sin(radians).abs();
    final w = size.width * cosA + size.height * sinA;
    final h = size.width * sinA + size.height * cosA;
    // 包围盒与原盒共中心，左上角相对原左上角的偏移。
    return (
      delta: Offset((size.width - w) / 2, (size.height - h) / 2),
      size: Size(w, h),
    );
  }

  bool _validateAssemblyBeforeExit() {
    final illegalCount = _totalIllegalPcbElementCount;
    if (illegalCount == 0) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '当前有 $illegalCount 个组件超出 PCB 边界，请先移回可视区域后再保存。',
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
              '当前有组件超出 PCB 边界，无法保存。要放弃本次修改并返回吗？',
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
      // 与 Studio 保持一致（`ui_studio_page/logic.dart` 的同名表）：
      // 这两个逻辑件共用 UIRenderer 的同一套渲染，画的是一行公式 /
      // 一行状态文本，**宽而扁**才放得下。Assembly 原先给的
      // 120×56 / 112×52 偏窄偏高，公式会被 FittedBox 压得很小。
      'math_node' => const Size(180, 44),
      'timer' => const Size(140, 54),
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
