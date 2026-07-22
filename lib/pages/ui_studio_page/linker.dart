part of 'ui_studio_page.dart';

/// 联动器连线逻辑与端口交互
mixin _UIStudioLinker on _UIStudioLogic {
  void _showLinkerSchemeQuickSelectDialog(UIElement el);

  bool _isDraggingConnection = false;
  String? _draggingSourceId;
  String? _draggingSourcePort;
  String? _draggingSourceType;
  Offset? _dragConnectionEnd;
  String? _hoveringTargetId;
  String? _hoveringTargetPort;

  // ===== 连线渲染 =====
  List<Widget> _buildLinkerConnectionsLayer() {
    if (_isPreviewMode) return const [];
    final connections = _getAllLinkerConnections();
    if (connections.isEmpty) return const [];

    final widgets = <Widget>[];
    for (final conn in connections) {
      final fromId = conn['from'] as String?;
      final toId = conn['to'] as String?;
      final lineType = conn['type'] as String? ?? 'input';
      if (fromId == null || toId == null) continue;

      UIElement? fromEl;
      UIElement? toEl;
      fromEl = _findElementById(fromId);
      toEl = _findElementById(toId);
      if (fromEl == null || toEl == null) continue;

      final startOffset = _resolvePortGlobalOffset(fromEl, false, conn['fromPort'] as String?);
      final endOffset = _resolvePortGlobalOffset(toEl, true, conn['toPort'] as String?);

      // 检查端点是否在复合件内部（复合件端口连线用粉红/浅蓝）
      final isCompositePort = fromEl != null && toEl != null &&
          (_isInsideComposite(fromEl!.id) || _isInsideComposite(toEl!.id));
      final isControlLine = conn['toPort'] == 'gate_in';
      final lineColor = isControlLine
          ? const Color(0xFFFFB300)
          : isCompositePort
              ? (lineType == 'input' ? const Color(0xFFFF4081) : const Color(0xFF4FC3F7))
              : lineType == 'input'
                  ? const Color(0xFF00ACC1)
                  : const Color(0xFF66BB6A);

      widgets.add(
        CustomPaint(
          painter: LinkerConnectionPainter(
            start: startOffset,
            end: endOffset,
            color: lineColor,
            isControlLine: isControlLine,
          ),
        ),
      );
    }
    return widgets;
  }

  /// 计算复合件内部子元素端口在全局坐标系下的位置
  Offset? _resolveCompositeChildGlobalOffset(String childId) {
    for (final el in _currentElements) {
      if (!el.isComposite || el.composite == null) continue;
      final portIndex = el.composite!.exposedPorts?.indexWhere((p) => p.elementId == childId) ?? -1;
      if (portIndex == -1) {
        // also search nested composites
        final found = _searchChildPortInComposite(el.composite!.children, childId, el.offset, el.size);
        if (found != null) return found;
        continue;
      }
      // Found - calculate port position relative to the composite's global position
      final child = el.composite!.children.firstWhere((c) => c.id == childId, orElse: () => el.composite!.children.first);
      final ports = el.composite!.exposedPorts!
          .where((p) => el.composite!.children.any((c) => c.id == p.elementId))
          .toList();
      final leftPorts = ports.where((p) => p.exposeInput).toList();
      final rightPorts = ports.where((p) => p.exposeOutput).toList();
      final p = (el.id == _selectedTransformationId) ? 20.0 : 0.0;
      final bodyH = el.size.height;
      final gx = _workspaceOffset.dx + el.offset.dx;
      final gy = _workspaceOffset.dy + el.offset.dy;
      
      // p offsets cancel out in the centered diagonal layout — port global positions are independent of selection padding
      int idx;
      if ((idx = leftPorts.indexWhere((p) => p.elementId == childId)) != -1) {
        final py = (bodyH / (leftPorts.length + 1)) * (idx + 1);
        return Offset(gx, gy + py);
      }
      if ((idx = rightPorts.indexWhere((p) => p.elementId == childId)) != -1) {
        final py = (bodyH / (rightPorts.length + 1)) * (idx + 1);
        return Offset(gx + el.size.width, gy + py);
      }
      return null;
    }
    return null;
  }

  Offset? _searchChildPortInComposite(List<UIElement> kids, String childId, Offset parentOffset, Size parentSize) {
    for (final child in kids) {
      if (child.isComposite && child.composite != null) {
        final nestedOffset = parentOffset + child.offset;
        final found = _searchChildPortInComposite(child.composite!.children, childId, nestedOffset, child.size);
        if (found != null) return found;
      }
    }
    return null;
  }

  Offset _resolvePortGlobalOffset(UIElement el, bool isInput, [String? portName]) {
    // 优先检查是否指向复合件内部子元素
    final compositeChildOffset = _resolveCompositeChildGlobalOffset(el.id);
    if (compositeChildOffset != null) return compositeChildOffset;

    final elLeft = _workspaceOffset.dx + el.offset.dx;
    final elTop = _workspaceOffset.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;

    if (portName == 'gate_in') {
      if (el.rotation == 0.0) {
        return Offset(cx, elTop + 7.0);
      }
      final rad = el.rotation * math.pi / 180.0;
      final distanceToGateCenter = math.max(0.0, el.size.height / 2 - 7.0);
      return Offset(
        cx + distanceToGateCenter * math.sin(rad),
        cy - distanceToGateCenter * math.cos(rad),
      );
    }

    if (el.rotation == 0.0) {
      return Offset(isInput ? elLeft : elLeft + el.size.width, cy);
    }

    final rad = el.rotation * math.pi / 180.0;
    final sign = isInput ? -1.0 : 1.0;
    final halfWidth = el.size.width / 2;

    return Offset(
      cx + sign * halfWidth * math.cos(rad),
      cy + sign * halfWidth * math.sin(rad),
    );
  }

  bool _isPointInsideRotatedRect(Offset point, UIElement el) {
    final elLeft = _workspaceOffset.dx + el.offset.dx;
    final elTop = _workspaceOffset.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;
    final pad = el.module?.type == 'indicator' ? 25.0 : 15.0;

    if (el.rotation == 0.0) {
      final rect = Rect.fromLTWH(elLeft - pad, elTop - pad, el.size.width + pad * 2, el.size.height + pad * 2);
      return rect.contains(point);
    }

    final rad = -el.rotation * math.pi / 180.0;
    final dx = point.dx - cx;
    final dy = point.dy - cy;

    final unrotatedX = cx + dx * math.cos(rad) - dy * math.sin(rad);
    final unrotatedY = cy + dx * math.sin(rad) + dy * math.cos(rad);

    final rect = Rect.fromLTWH(elLeft - pad, elTop - pad, el.size.width + pad * 2, el.size.height + pad * 2);
    return rect.contains(Offset(unrotatedX, unrotatedY));
  }

  Widget _buildTemporaryConnectionLine() {
    if (_dragConnectionEnd == null || _draggingSourceId == null) {
      return const SizedBox.shrink();
    }

    final sourceEl = _findElementById(_draggingSourceId!) ?? UIElement(id: '', isComposite: false);
    if (sourceEl.id.isEmpty) return const SizedBox.shrink();

    final isLeftPort = _draggingSourcePort == 'input';
    final startOffset = _resolvePortGlobalOffset(
      sourceEl,
      isLeftPort,
      _draggingSourcePort,
    );

    final srcIsComposite = _isInsideComposite(sourceEl.id);
    final tgtIsComposite = _hoveringTargetId != null && _isInsideComposite(_hoveringTargetId!);
    final isCompositePort = srcIsComposite || tgtIsComposite;
    final isControlLine = _hoveringTargetPort == 'gate_in' ||
        _draggingSourcePort == 'gate_in';
    final dragColor = isControlLine
        ? const Color(0xFFFFB300)
        : isCompositePort
            ? (isLeftPort ? const Color(0xFFFF4081) : const Color(0xFF4FC3F7))
            : isLeftPort
                ? const Color(0xFF00ACC1)
                : const Color(0xFF66BB6A);
    final lineColor = _hoveringTargetId != null && !isControlLine
        ? (isCompositePort ? (_draggingSourceType == 'input' ? const Color(0xFFFF4081) : const Color(0xFF4FC3F7)) : const Color(0xFF00E676))
        : dragColor;

    Offset endOffset = _dragConnectionEnd!;
    if (_hoveringTargetId != null) {
      final targetEl = _findElementById(_hoveringTargetId!) ?? UIElement(id: '', isComposite: false);
      if (targetEl.id.isNotEmpty) {
        endOffset = _resolvePortGlobalOffset(targetEl, true, _hoveringTargetPort);
      }
    }

    return CustomPaint(
      painter: LinkerConnectionPainter(
        start: startOffset,
        end: endOffset,
        color: lineColor,
        isControlLine: isControlLine,
      ),
    );
  }

  // ===== 数据查询 =====
  List<Map<String, dynamic>> _getAllLinkerConnections() {
    final connections = <Map<String, dynamic>>[];
    for (final el in _currentElements) {
      if (el.isComposite || el.module?.type != 'linker') continue;
      final linkerData = el.module!.properties['linker'] as Map?;
      if (linkerData == null) continue;

      final sourceId = linkerData['sourceModuleId']?.toString();
      final targetId = linkerData['targetModuleId']?.toString();
      final sourcePort = linkerData['sourcePort']?.toString() ?? 'current';
      final storedTargetPort = linkerData['targetPort']?.toString() ?? 'text';
      final scheme = linkerData['scheme']?.toString();
      // 兼容早期草稿：触发方案即使旧数据未写 gate_in，也按控制端口绘制。
      final targetPort =
          scheme == 'click_to_math_trigger' || scheme == 'timer_tick_to_math_trigger'
              ? 'gate_in'
              : storedTargetPort;

      if (sourceId != null) {
        connections.add({
          'from': sourceId,
          'fromPort': sourcePort,
          'to': el.id,
          'toPort': 'input',
          'linkerId': el.id,
          'type': 'input',
        });
      }
      if (targetId != null) {
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

  // ===== 悬停检测 =====
  void _updateConnectionHover(Offset globalPosition) {
    if (!_isDraggingConnection) return;

    String? newHoverTargetId;
    String? newHoverTargetPort;

    for (final el in _currentElements) {
      if (el.id == _draggingSourceId) continue;
      if (el.sealed) continue;
      if (el.layerIndex != _activeLayerIndex) continue;

      final elType = el.module?.type;
      final bool hitCard = _isPointInsideRotatedRect(globalPosition, el);

      if (hitCard && ['linker', 'text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(elType)) {
        if (_canConnect(el, 'input')) {
          String assignedPort = 'input';
          if (elType == 'math_node' && _draggingSourceType == 'output') {
            final sourceKind = _effectiveConnectionSourceType();
            // Math 的目标端口取决于来源语义，因此先完成 Linker 左侧来源连接，
            // 才允许连接 Math，避免“未知来源”绕过控制/数据端口约束。
            if (sourceKind == null) continue;
            final isControlSource = sourceKind == 'button' || sourceKind == 'timer';
            final gateOffset = _resolvePortGlobalOffset(el, true, 'gate_in');
            final dataOffset = _resolvePortGlobalOffset(el, true, 'data_in');
            final isNearGate = (globalPosition - gateOffset).distanceSquared <= 34 * 34;
            final isNearData = (globalPosition - dataOffset).distanceSquared <= 34 * 34;

            // 触发源只能进入顶部控制端口；数值源只能进入左侧数据口。
            // 节点卡片的其他区域不再作为 Math 的模糊落点。
            if (isControlSource && isNearGate) {
              assignedPort = 'gate_in';
            } else if (!isControlSource && isNearData) {
              assignedPort = 'data_in';
            } else {
              continue;
            }
          }
          newHoverTargetId = el.id;
          newHoverTargetPort = assignedPort;
          break;
        }
      }

      if (hitCard && ['linker', 'text', 'progress', 'slider', 'input', 'button', 'math_node', 'switch', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(elType)) {
        if (_canConnect(el, 'output')) {
          newHoverTargetId = el.id;
          newHoverTargetPort = 'output';
          break;
        }
      }
    }

    // 如果未命中普通元素，检查复合件的暴露端口
    if (newHoverTargetId == null) {
      for (final el in _currentElements) {
        if (!el.isComposite || el.composite?.exposedPorts == null) continue;
        if (el.sealed || el.layerIndex != _activeLayerIndex) continue;

        final ports = el.composite!.exposedPorts!
            .where((p) => el.composite!.children.any((c) => c.id == p.elementId))
            .toList();
        if (ports.isEmpty) continue;

        final elemGlobal = _workspaceOffset + el.offset;
        final bodyH = el.size.height;

        // Linker「输出端」拖出 → 可接复合件「左侧接收端口」
        if (_draggingSourceType == 'output') {
          final leftPorts = ports.where((p) => p.exposeInput).toList();
          for (var i = 0; i < leftPorts.length; i++) {
            final py = elemGlobal.dy + (bodyH / (leftPorts.length + 1)) * (i + 1);
            final px = elemGlobal.dx;
            if ((globalPosition - Offset(px, py)).distance < 24) {
              newHoverTargetId = leftPorts[i].elementId;
              newHoverTargetPort = 'input';
              break;
            }
          }
        }

        // Linker「输入端」朝外拖 → 可接复合件「右侧输出端口」
        if (newHoverTargetId == null && _draggingSourceType == 'input') {
          final rightPorts = ports.where((p) => p.exposeOutput).toList();
          for (var i = 0; i < rightPorts.length; i++) {
            final py = elemGlobal.dy + (bodyH / (rightPorts.length + 1)) * (i + 1);
            final px = elemGlobal.dx + el.size.width;
            if ((globalPosition - Offset(px, py)).distance < 24) {
              newHoverTargetId = rightPorts[i].elementId;
              newHoverTargetPort = 'output';
              break;
            }
          }
        }
        if (newHoverTargetId != null) break;
      }
    }

    if (newHoverTargetId != _hoveringTargetId ||
        newHoverTargetPort != _hoveringTargetPort) {
      setState(() {
        _hoveringTargetId = newHoverTargetId;
        _hoveringTargetPort = newHoverTargetPort;
      });
    }
  }

  /// 递归搜索元素（含复合件内部），返回 [element, ownerList, index] 或 null

  /// 当前拖出 Linker 输出端所代表的原始组件类型。
  /// Math Node 用它将 Button / Timer 的触发通路与数值数据通路严格分开。
  String? _effectiveConnectionSourceType() {
    if (_draggingSourceId == null) return null;
    final source = _findElementById(_draggingSourceId!) ?? UIElement(id: '', isComposite: false);
    if (source.id.isEmpty) return null;
    if (source.module?.type != 'linker') return source.module?.type;
    final data =
        (source.module?.properties['linker'] as Map?)?.cast<String, dynamic>();
    final sourceId = data?['sourceModuleId']?.toString();
    if (sourceId == null) return null;
    final origin = _findElementById(sourceId) ?? UIElement(id: '', isComposite: false);
    return origin.module?.type;
  }

  bool _canConnect(UIElement target, String portDirection) {
    if (_draggingSourceId == null || _draggingSourceType == null) return false;
    final sourceElement = _findElementById(_draggingSourceId!) ?? UIElement(id: '', isComposite: false);
    if (sourceElement.id.isEmpty || sourceElement.sealed || target.sealed) {
      return false;
    }
    final sourceType = sourceElement.module?.type;
    final targetType = target.module?.type;
    final dragType = _draggingSourceType;
    if (sourceType == null || targetType == null) return false;

    if (sourceType == 'linker' && dragType == 'input') {
      return ['text', 'progress', 'slider', 'input', 'button', 'math_node', 'switch', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(targetType) &&
          portDirection == 'output';
    }
    if (sourceType == 'linker' && dragType == 'output') {
      return ['text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(targetType) &&
          portDirection == 'input';
    }
    if (['text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) &&
        dragType == 'output') {
      if (['surface', 'surface_art', 'primitive_art'].contains(sourceType) && ['math_node', 'timer', 'line', 'image'].contains(targetType)) {
        return false;
      }
      return targetType == 'linker' && portDirection == 'input';
    }
    if (['text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) &&
        dragType == 'input') {
      if (['surface', 'surface_art', 'primitive_art'].contains(sourceType) && ['math_node', 'timer', 'line', 'image'].contains(targetType)) {
        return false;
      }
      return targetType == 'linker' && portDirection == 'output';
    }
    return false;
  }

  bool _wouldCreateLinkerCycle(String sourceId, String targetId) {
    if (sourceId == targetId) return true;
    final graph = <String, Set<String>>{};
    for (final element in _currentElements) {
      if (element.module?.type != 'linker') continue;
      final data = (element.module!.properties['linker'] as Map?)
          ?.cast<String, dynamic>();
      final from = data?['sourceModuleId']?.toString();
      final to = data?['targetModuleId']?.toString();
      if (from == null || to == null) continue;
      graph.putIfAbsent(from, () => <String>{}).add(to);
    }

    final visited = <String>{};
    bool reachesSource(String nodeId) {
      if (nodeId == sourceId) return true;
      if (!visited.add(nodeId)) return false;
      return graph[nodeId]?.any(reachesSource) ?? false;
    }

    return reachesSource(targetId);
  }

  // ===== 连接完成 =====
  void _completeConnection() {
    if (_hoveringTargetId == null || _draggingSourceId == null) return;

    final sourceElement = _findElementById(_draggingSourceId!) ?? UIElement(id: '', isComposite: false);
    final targetElement = _findElementById(_hoveringTargetId!) ?? UIElement(id: '', isComposite: false);
    if (sourceElement.id.isEmpty || targetElement.id.isEmpty) return;

    final sourceType = sourceElement.module?.type;
    final targetType = targetElement.module?.type;
    final sourceLinkData = sourceElement.module?.properties['linker'];
    final targetLinkData = targetElement.module?.properties['linker'];
    String? prospectiveSourceId;
    String? prospectiveTargetId;
    if (sourceType == 'linker' && sourceLinkData is Map) {
      prospectiveSourceId = sourceLinkData['sourceModuleId']?.toString();
    } else {
      prospectiveSourceId = sourceElement.id;
    }
    if (targetType == 'linker' && targetLinkData is Map) {
      prospectiveTargetId = targetLinkData['targetModuleId']?.toString();
    } else {
      prospectiveTargetId = targetElement.id;
    }
    if (prospectiveSourceId != null &&
        prospectiveTargetId != null &&
        _wouldCreateLinkerCycle(prospectiveSourceId, prospectiveTargetId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不允许创建联动器环依赖')),
      );
      return;
    }

    if (sourceType == 'linker' &&
        _draggingSourceType == 'output' &&
        ['text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(targetType) &&
        (_hoveringTargetPort == 'input' ||
            _hoveringTargetPort == 'data_in' ||
            _hoveringTargetPort == 'gate_in')) {
      final bool isGate = _hoveringTargetPort == 'gate_in';
      if (targetType == 'math_node') {
        final sourceKind = _effectiveConnectionSourceType();
        final requiresGate = sourceKind == 'button' || sourceKind == 'timer';
        if (isGate != requiresGate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('触发通路只能接入计算触发端口；数值通路只能接入左侧数据端口')),
          );
          return;
        }
      }
      _updateLinkerConnection(
        linkerId: sourceElement.id,
        targetModuleId: targetElement.id,
        targetPort: ['text', 'surface', 'surface_art', 'primitive_art']
                .contains(targetType)
            ? 'text'
            : (targetType == 'input' ||
                    targetType == 'select' ||
                    targetType == 'indicator')
                ? 'currentValue'
                : targetType == 'switch'
                    ? 'value'
                    : targetType == 'math_node'
                        ? (isGate ? 'gate_in' : 'data_in')
                        : targetType == 'timer'
                            ? 'control'
                            : 'current',
        targetType: targetType == 'timer'
            ? 'event'
            : (targetType == 'text' ||
                    targetType == 'input' ||
                    targetType == 'select' ||
                    targetType == 'indicator' ||
                    ['surface', 'surface_art', 'primitive_art'].contains(targetType))
                ? 'string'
                : (targetType == 'switch' || isGate ? 'boolean' : 'number'),
        connectionType: 'output',
      );
    } else if (sourceType == 'linker' &&
        _draggingSourceType == 'input' &&
        ['text', 'progress', 'slider', 'input', 'button', 'math_node', 'switch', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(targetType) &&
        _hoveringTargetPort == 'output') {
      _updateLinkerConnection(
        linkerId: sourceElement.id,
        sourceModuleId: targetElement.id,
        sourcePort: ['text', 'input', 'button', 'select', 'indicator', 'surface', 'surface_art', 'primitive_art'].contains(targetType) ? 'output' : (targetType == 'switch' ? 'value' : (targetType == 'math_node' ? 'data_out' : (targetType == 'timer' ? 'currentVal' : 'current'))),
        sourceType: targetType == 'switch' ? 'boolean' : (['text', 'input', 'button', 'select', 'indicator', 'surface', 'surface_art', 'primitive_art'].contains(targetType) ? 'string' : 'number'),
        connectionType: 'input',
      );
    } else if (['text', 'progress', 'slider', 'input', 'button', 'math_node', 'switch', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) &&
        _draggingSourceType == 'output' &&
        targetType == 'linker' &&
        _hoveringTargetPort == 'input') {
      _updateLinkerConnection(
        linkerId: targetElement.id,
        sourceModuleId: sourceElement.id,
        sourcePort: ['text', 'input', 'button', 'select', 'indicator', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) ? 'output' : (sourceType == 'switch' ? 'value' : (sourceType == 'math_node' ? 'data_out' : (sourceType == 'timer' ? 'currentVal' : 'current'))),
        sourceType: sourceType == 'switch' ? 'boolean' : (['text', 'input', 'button', 'select', 'indicator', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) ? 'string' : 'number'),
        connectionType: 'input',
      );
    } else if (['text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) &&
        _draggingSourceType == 'input' &&
        targetType == 'linker' &&
        (_hoveringTargetPort == 'output' || _hoveringTargetPort == 'gate_in')) {
      final bool isGate = _hoveringTargetPort == 'gate_in';
      _updateLinkerConnection(
        linkerId: targetElement.id,
        targetModuleId: sourceElement.id,
        targetPort: ['text', 'surface', 'surface_art', 'primitive_art'].contains(sourceType) ? 'text' : (sourceType == 'input' || sourceType == 'select' || sourceType == 'indicator' ? 'currentValue' : (sourceType == 'switch' ? 'value' : (sourceType == 'math_node' ? (isGate ? 'gate_in' : 'data_in') : (sourceType == 'timer' ? 'input' : 'current')))),
        targetType: (sourceType == 'text' || sourceType == 'input' || sourceType == 'select' || sourceType == 'indicator' || ['surface', 'surface_art', 'primitive_art'].contains(sourceType)) ? 'string' : (sourceType == 'switch' || isGate ? 'boolean' : 'number'),
        connectionType: 'output',
      );
    }

    UIElement? activeLinkerEl;
    if (sourceType == 'linker') activeLinkerEl = sourceElement;
    if (targetType == 'linker') activeLinkerEl = targetElement;

    if (activeLinkerEl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final idx = _currentElements.indexWhere((e) => e.id == activeLinkerEl!.id);
        if (idx != -1) {
          final el = _currentElements[idx];
          final lkData = (el.module?.properties['linker'] as Map?)?.cast<String, dynamic>();
          if (lkData != null && lkData['sourceModuleId'] != null && lkData['targetModuleId'] != null) {
            _showLinkerSchemeQuickSelectDialog(el);
          }
        }
      });
    }

    _autoSave();
  }

  void _cancelConnection() {
    setState(() {
      _isDraggingConnection = false;
      _draggingSourceId = null;
      _draggingSourcePort = null;
      _draggingSourceType = null;
      _dragConnectionEnd = null;
      _hoveringTargetId = null;
      _hoveringTargetPort = null;
    });
  }

  void _updateLinkerConnection({
    required String linkerId,
    String? sourceModuleId,
    String? sourcePort,
    String? sourceType,
    String? targetModuleId,
    String? targetPort,
    String? targetType,
    required String connectionType,
  }) {
    setState(() {
      final index = _currentElements.indexWhere((e) => e.id == linkerId);
      if (index == -1) return;

      final linkerElement = _currentElements[index];
      if (linkerElement.module?.type != 'linker') return;

      final linkerData = Map<String, dynamic>.from(
        linkerElement.module!.properties['linker'] ?? {},
      );
      linkerData['priority'] ??= 5;
      linkerData['cooldownMs'] ??= 0;
      linkerData['maxTriggerCount'] ??= 0;

      final previousSourceId = linkerData['sourceModuleId']?.toString();
      final previousTargetId = linkerData['targetModuleId']?.toString();

      if (connectionType == 'input' && sourceModuleId != null) {
        linkerData['sourceModuleId'] = sourceModuleId;
        linkerData['sourcePort'] = sourcePort ?? 'current';
        linkerData['sourceType'] = sourceType ?? 'number';

        // Linker 已经挂在 Math 上时，更换来源也必须重新校验端口语义。
        // 不能让“原 Button → gate_in”残留为一个可被数值来源复用的间接控制连接。
        final existingTargetId = linkerData['targetModuleId']?.toString();
        final existingTarget = existingTargetId == null
            ? null
            : _findElementById(existingTargetId) ?? UIElement(id: '', isComposite: false);
        if (existingTarget?.module?.type == 'math_node') {
          final newSourceElement = _findElementById(sourceModuleId) ?? UIElement(id: '', isComposite: false);
          final newSourceKind = newSourceElement.module?.type;
          final isControlSource =
              newSourceKind == 'button' || newSourceKind == 'timer';
          final isGateTarget = linkerData['targetPort'] == 'gate_in';
          if (isControlSource != isGateTarget) {
            linkerData.remove('targetModuleId');
            linkerData.remove('targetPort');
            linkerData.remove('targetType');
          }
        }
      } else if (connectionType == 'output' && targetModuleId != null) {
        linkerData['targetModuleId'] = targetModuleId;
        linkerData['targetPort'] = targetPort ?? 'text';
        linkerData['targetType'] = targetType ?? 'string';
      }

      final endpointChanged =
          previousSourceId != linkerData['sourceModuleId']?.toString() ||
          previousTargetId != linkerData['targetModuleId']?.toString();
      if (endpointChanged) {
        linkerData['scheme'] = '未配置';
        linkerData.remove('schemeParams');
        linkerData.remove('migrationNotice');
        linkerData.remove('retiredSchemeId');
      }

      final isFullyConnected =
          linkerData['sourceModuleId'] != null && linkerData['targetModuleId'] != null;
      linkerData['enabled'] = isFullyConnected &&
          LinkerMatrixEngine.isSchemeSelectable(
            linkerData['scheme']?.toString() ?? '',
          );

      final updatedProps =
          Map<String, dynamic>.from(linkerElement.module!.properties);
      updatedProps['linker'] = linkerData;

      final updatedModule =
          linkerElement.module!.copyWith(properties: updatedProps);
      _currentElements[index] = linkerElement.copyWith(module: updatedModule);
    });
  }

  void _disconnectLinkerPort(UIElement el, String portDirection) {
    if (el.module?.type != 'linker' || el.sealed) return;
    setState(() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx == -1) return;

      final currentEl = _currentElements[idx];
      final props = Map<String, dynamic>.from(currentEl.module!.properties);
      final linkerData = Map<String, dynamic>.from(props['linker'] ?? {});

      if (portDirection == 'input') {
        // gate_in 是严格的控制边：来源断开后连同目标一起断开，
        // 防止之后接入其他类型来源时遗留间接控制端口。
        final wasMathGate = linkerData['targetPort'] == 'gate_in';
        linkerData.remove('sourceModuleId');
        linkerData.remove('sourcePort');
        linkerData.remove('sourceType');
        if (wasMathGate) {
          linkerData.remove('targetModuleId');
          linkerData.remove('targetPort');
          linkerData.remove('targetType');
        }
      } else {
        linkerData.remove('targetModuleId');
        linkerData.remove('targetPort');
        linkerData.remove('targetType');
      }
      linkerData['scheme'] = '未配置';
      linkerData.remove('schemeParams');
      linkerData.remove('migrationNotice');
      linkerData.remove('retiredSchemeId');
      linkerData['enabled'] = false;

      props['linker'] = linkerData;
      _currentElements[idx] = currentEl.copyWith(
        module: currentEl.module!.copyWith(properties: props),
      );
    });
    _cancelConnection();
    _autoSave();
  }
}
