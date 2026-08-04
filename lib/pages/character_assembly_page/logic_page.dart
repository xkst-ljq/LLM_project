part of '../character_assembly_page.dart';

/// 页面与路由：层级 · 页面路由器 · 翻页手势 · 增删改与拖拽重排
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
mixin _AssemblyPageLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic {
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<AssemblyPage> _directChildPages(String? parentPageId) {
    final pages = _pages
        .where((page) => page.parentPageId == parentPageId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return pages;
  }



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

  /// 当前 mode 的运行时是否真的会响应页面手势。
  ///
  /// 常驻 / 伴生挂件在聊天页挂载时都传 `enablePageGestures: false`：
  ///   - 常驻浮在聊天内容之上，开启会抢走内部 slider / 输入框的拖动，
  ///     也会和聊天页左右滑出设置页打架；
  ///   - 伴生嵌在消息 ListView 里，全屏 Listener 会与垂直滚动打架。
  ///
  /// 这两种 mode 下配了手势也不会生效，必须在配置入口就讲清楚，
  /// 否则作者配完发现没反应，只能靠猜（同 3.5g 那类静默失效）。
  bool get _pageGesturesTakeEffect =>
      _info.mode != 'extra_sticky' && _info.mode != 'extra_companion';

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
                  // 常驻 / 伴生的运行时不响应滑动，配了也白配。
                  if (!_pageGesturesTakeEffect) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFB74D)),
                      ),
                      child: const Text(
                        '此类型 UI 不响应滑动换页：挂件浮在聊天内容上，'
                        '开启会抢走内部滑块与输入框的拖动，也会和聊天页的'
                        '左右滑动打架。需要多页面请改用「叠加页」。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
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
    // 用 showKeyboardSafeDialog：输入法还持有焦点时 pop 会抛
    // 「Duplicate GlobalKeys」（输入法的 OverlayEntry 与正在拆除的
    // 对话框争抢同一个 key）。用户路径是「改图层名时不点输入法的确认，
    // 直接点按钮/遮罩/返回键」。
    //
    // 原先在两个按钮里各贴了一次 unfocus + 16ms 延迟，有两个洞：
    // 点遮罩和返回键绕过按钮；16ms 只有一帧，键盘收起要 200~300ms。
    // 现在由对话框宿主在 dispose 里统一收焦点，覆盖所有出口。
    final renamed = await showKeyboardSafeDialog<String>(
      context: context,
      // controller 交给弹窗托管：await 返回时退场动画还要跑 ~150ms，
      // 期间 TextField 仍在重建，自行 dispose 会抛
      // 「A TextEditingController was used after being disposed」。
      disposables: [controller],
      builder: (ctx) => AlertDialog(
        title: const Text('重命名页面'),
        content: TextField(
          controller: controller,
          autofocus: true,
          // 键盘上的「完成」直接提交，省一次点击。
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          decoration: const InputDecoration(hintText: '页面名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
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

  /// 执行换父。
  ///
  /// 换父弹窗已随「拖放换父」上线而移除（两个入口做同一件事只是噪音），
  /// 现在唯一的调用方是拖放。逻辑仍单独成函数——
  /// 便于以后接入别的入口时不必重写 sortOrder 重排那段。
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

  /// 正在被拖动的叠加页 id。null 表示没有拖放进行中。
  String? _draggingPageId;

  /// 当前悬停其上的候选父页 id。
  String? _dragHoverParentId;

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
}


