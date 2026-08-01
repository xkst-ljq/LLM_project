part of '../character_assembly_page.dart';

/// 联动器：端口几何 · 拖拽接线 · 连线图层 · 方案与参数配置
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
mixin _AssemblyLinkerLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _AssemblyCanvasLogic, _AssemblyPageLogic {
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
}
