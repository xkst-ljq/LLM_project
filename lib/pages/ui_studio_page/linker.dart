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
      for (final el in _currentElements) {
        if (el.id == fromId) fromEl = el;
        if (el.id == toId) toEl = el;
      }
      if (fromEl == null || toEl == null) continue;

      final startOffset = _resolvePortGlobalOffset(fromEl, false, conn['fromPort'] as String?);
      final endOffset = _resolvePortGlobalOffset(toEl, true, conn['toPort'] as String?);

      final lineColor = lineType == 'input'
          ? const Color(0xFF00ACC1)
          : const Color(0xFF66BB6A);

      widgets.add(
        CustomPaint(
          painter: LinkerConnectionPainter(
            start: startOffset,
            end: endOffset,
            color: lineColor,
          ),
        ),
      );
    }
    return widgets;
  }

  Offset _resolvePortGlobalOffset(UIElement el, bool isInput, [String? portName]) {
    final elLeft = _workspaceOffset.dx + el.offset.dx;
    final elTop = _workspaceOffset.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;

    if (portName == 'gate_in') {
      if (el.rotation == 0.0) {
        return Offset(cx, elTop + 2.5);
      }
      final rad = el.rotation * math.pi / 180.0;
      final halfHeight = el.size.height / 2;
      return Offset(
        cx + halfHeight * math.sin(rad),
        cy - halfHeight * math.cos(rad),
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

    final sourceEl = _currentElements.firstWhere(
          (e) => e.id == _draggingSourceId,
      orElse: () => UIElement(id: '', isComposite: false),
    );
    if (sourceEl.id.isEmpty) return const SizedBox.shrink();

    final isLeftPort = _draggingSourcePort == 'input';
    final startOffset = _resolvePortGlobalOffset(sourceEl, isLeftPort);

    final dragColor = isLeftPort
        ? const Color(0xFF00ACC1)
        : const Color(0xFF66BB6A);
    final lineColor = _hoveringTargetId != null
        ? const Color(0xFF00E676)
        : dragColor;

    Offset endOffset = _dragConnectionEnd!;
    if (_hoveringTargetId != null) {
      final targetEl = _currentElements.firstWhere(
            (e) => e.id == _hoveringTargetId,
        orElse: () => UIElement(id: '', isComposite: false),
      );
      if (targetEl.id.isNotEmpty) {
        endOffset = _resolvePortGlobalOffset(targetEl, true, _hoveringTargetPort);
      }
    }

    return CustomPaint(
      painter: LinkerConnectionPainter(
        start: startOffset,
        end: endOffset,
        color: lineColor,
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
      final targetPort = linkerData['targetPort']?.toString() ?? 'text';

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
      if (el.layerIndex != _activeLayerIndex) continue;

      final elType = el.module?.type;
      final bool hitCard = _isPointInsideRotatedRect(globalPosition, el);

      if (hitCard && ['linker', 'text', 'progress', 'slider', 'input', 'button', 'switch', 'math_node', 'select', 'indicator', 'timer', 'surface', 'surface_art', 'primitive_art'].contains(elType)) {
        if (_canConnect(el, 'input')) {
          String assignedPort = 'input';
          if (elType == 'math_node' && _draggingSourceType == 'output') {
            final elLeft = _workspaceOffset.dx + el.offset.dx;
            final elTop = _workspaceOffset.dy + el.offset.dy;
            final double distLeft = (globalPosition - Offset(elLeft, elTop + el.size.height / 2)).distanceSquared;
            final double distTop = (globalPosition - Offset(elLeft + el.size.width / 2, elTop)).distanceSquared;
            if (distTop < distLeft) {
              assignedPort = 'gate_in';
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

    if (newHoverTargetId != _hoveringTargetId ||
        newHoverTargetPort != _hoveringTargetPort) {
      setState(() {
        _hoveringTargetId = newHoverTargetId;
        _hoveringTargetPort = newHoverTargetPort;
      });
    }
  }

  bool _canConnect(UIElement target, String portDirection) {
    if (_draggingSourceId == null || _draggingSourceType == null) return false;
    final sourceElement = _currentElements.firstWhere(
          (e) => e.id == _draggingSourceId,
      orElse: () => UIElement(id: '', isComposite: false),
    );
    if (sourceElement.id.isEmpty) return false;
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

    final sourceElement = _currentElements.firstWhere(
          (e) => e.id == _draggingSourceId,
      orElse: () => UIElement(id: '', isComposite: false),
    );
    final targetElement = _currentElements.firstWhere(
          (e) => e.id == _hoveringTargetId,
      orElse: () => UIElement(id: '', isComposite: false),
    );
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
        (_hoveringTargetPort == 'input' || _hoveringTargetPort == 'gate_in')) {
      final bool isGate = _hoveringTargetPort == 'gate_in';
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
    if (el.module?.type != 'linker') return;
    setState(() {
      final idx = _currentElements.indexWhere((e) => e.id == el.id);
      if (idx == -1) return;

      final currentEl = _currentElements[idx];
      final props = Map<String, dynamic>.from(currentEl.module!.properties);
      final linkerData = Map<String, dynamic>.from(props['linker'] ?? {});

      if (portDirection == 'input') {
        linkerData.remove('sourceModuleId');
        linkerData.remove('sourcePort');
        linkerData.remove('sourceType');
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
