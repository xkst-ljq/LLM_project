part of '../character_assembly_page.dart';

/// 画布：缩放手柄 · 选中轮廓 · 面组 · PCB · 后台位 · 落件 · 各类专项编辑器
///
/// 从 `logic.dart` 按职责拆出。**纯搬运**：未改动任何一行逻辑与签名。
///
/// ## 为什么是独立 mixin
///
/// Dart 的 `part` 文件**不能续写另一个 part 里打开的类体**——
/// 每个 part 必须自成完整的顶层声明。因此本文件独立成一个 mixin，
/// 由 `_CharacterAssemblyPageState` 一并 `with` 进去；
/// 私有成员在同一个库内仍互相可见，调用关系不受影响。
///
/// `on` 子句的依赖由脚本按实际引用算出，并已验证整个依赖图无环。
/// 被多个分组共用的成员留在 `logic.dart`（依赖链根部），避免形成环。
mixin _AssemblyCanvasLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _AssemblyPageLogic {


  Size _resizeStartSize = Size.zero;

  Offset _resizeStartGlobal = Offset.zero;


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

    final applied = await showKeyboardSafeDialog<bool>(
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










  bool get _canUndo => _history.isNotEmpty;

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

  String _exportAssemblyInfoJson() {
    _persistAssemblyElements();
    return _info.toJsonString();
  }

  /// 组装退出时的返回值：UI 数据 + 需要反写的状态字段。
  AssemblyEditResult _buildEditResult() {
    // 反写要在导出之前算：导出会 persist，
    // 之后再读组件值拿到的是同一份数据，但顺序固定更不易出错。
    final writeBack = _buildStatusFieldWriteBack();
    return AssemblyEditResult(
      assemblyJson: _exportAssemblyInfoJson(),
      statusFields: writeBack,
    );
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

    final saved = await showKeyboardSafeDialog<bool>(
      context: context,
      // controller 交给弹窗托管：await 返回时退场动画还要跑 ~150ms，
      // 期间 TextField 仍在重建，自行 dispose 会抛
      // 「A TextEditingController was used after being disposed」。
      disposables: [
        widthController,
        heightController,
      ],
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
      if (mounted) Navigator.pop(context, _buildEditResult());
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



