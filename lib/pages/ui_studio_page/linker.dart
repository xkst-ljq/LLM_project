part of 'ui_studio_page.dart';

/// 联动器连线逻辑与端口交互
mixin _UIStudioLinker on _UIStudioLogic {
  bool _isDraggingConnection = false;
  String? _draggingSourceId;
  String? _draggingSourcePort;
  String? _draggingSourceType;
  Offset? _dragConnectionEnd;
  String? _hoveringTargetId;
  String? _hoveringTargetPort;

  // ===== 连线渲染 =====
  List<Widget> _buildLinkerConnectionsLayer() {
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

      final startOffset = _resolvePortGlobalOffset(fromEl, false);
      final endOffset = _resolvePortGlobalOffset(toEl, true);

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

  Offset _resolvePortGlobalOffset(UIElement el, bool isInput) {
    final elLeft = _workspaceOffset.dx + el.offset.dx;
    final elTop = _workspaceOffset.dy + el.offset.dy;
    final cx = elLeft + el.size.width / 2;
    final cy = elTop + el.size.height / 2;

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

    if (el.rotation == 0.0) {
      final rect = Rect.fromLTWH(elLeft - 15, elTop - 15, el.size.width + 30, el.size.height + 30);
      return rect.contains(point);
    }

    final rad = -el.rotation * math.pi / 180.0;
    final dx = point.dx - cx;
    final dy = point.dy - cy;

    final unrotatedX = cx + dx * math.cos(rad) - dy * math.sin(rad);
    final unrotatedY = cy + dx * math.sin(rad) + dy * math.cos(rad);

    final rect = Rect.fromLTWH(elLeft - 15, elTop - 15, el.size.width + 30, el.size.height + 30);
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

    return CustomPaint(
      painter: LinkerConnectionPainter(
        start: startOffset,
        end: _dragConnectionEnd!,
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

      if (hitCard && (elType == 'linker' || elType == 'text')) {
        if (_canConnect(el, 'input')) {
          newHoverTargetId = el.id;
          newHoverTargetPort = 'input';
          break;
        }
      }

      if (hitCard && (elType == 'linker' || elType == 'progress' || elType == 'slider')) {
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
      return (targetType == 'progress' || targetType == 'slider') &&
          portDirection == 'output';
    }
    if (sourceType == 'linker' && dragType == 'output') {
      return targetType == 'text' && portDirection == 'input';
    }
    if ((sourceType == 'progress' || sourceType == 'slider') &&
        dragType == 'output') {
      return targetType == 'linker' && portDirection == 'input';
    }
    if (sourceType == 'text' && dragType == 'input') {
      return targetType == 'linker' && portDirection == 'output';
    }
    return false;
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

    if (sourceType == 'linker' &&
        _draggingSourceType == 'output' &&
        targetType == 'text' &&
        _hoveringTargetPort == 'input') {
      _updateLinkerConnection(
        linkerId: sourceElement.id,
        targetModuleId: targetElement.id,
        targetPort: 'text',
        targetType: 'string',
        connectionType: 'output',
      );
    } else if (sourceType == 'linker' &&
        _draggingSourceType == 'input' &&
        (targetType == 'progress' || targetType == 'slider') &&
        _hoveringTargetPort == 'output') {
      _updateLinkerConnection(
        linkerId: sourceElement.id,
        sourceModuleId: targetElement.id,
        sourcePort: 'current',
        sourceType: 'number',
        connectionType: 'input',
      );
    } else if ((sourceType == 'progress' || sourceType == 'slider') &&
        _draggingSourceType == 'output' &&
        targetType == 'linker' &&
        _hoveringTargetPort == 'input') {
      _updateLinkerConnection(
        linkerId: targetElement.id,
        sourceModuleId: sourceElement.id,
        sourcePort: 'current',
        sourceType: 'number',
        connectionType: 'input',
      );
    } else if (sourceType == 'text' &&
        _draggingSourceType == 'input' &&
        targetType == 'linker' &&
        _hoveringTargetPort == 'output') {
      _updateLinkerConnection(
        linkerId: targetElement.id,
        targetModuleId: sourceElement.id,
        targetPort: 'text',
        targetType: 'string',
        connectionType: 'output',
      );
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

      if (connectionType == 'input' && sourceModuleId != null) {
        linkerData['sourceModuleId'] = sourceModuleId;
        linkerData['sourcePort'] = sourcePort ?? 'current';
        linkerData['sourceType'] = sourceType ?? 'number';
      } else if (connectionType == 'output' && targetModuleId != null) {
        linkerData['targetModuleId'] = targetModuleId;
        linkerData['targetPort'] = targetPort ?? 'text';
        linkerData['targetType'] = targetType ?? 'string';
      }

      if (linkerData['sourceModuleId'] != null &&
          linkerData['targetModuleId'] != null) {
        linkerData['scheme'] ??= 'current_to_text';
        linkerData['enabled'] = true;
      }

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

      props['linker'] = linkerData;
      _currentElements[idx] = currentEl.copyWith(
        module: currentEl.module!.copyWith(properties: props),
      );
    });
    _cancelConnection();
    _autoSave();
  }
}
