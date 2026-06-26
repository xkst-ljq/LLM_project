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

      double fromX, toX;
      final fromY = _workspaceOffset.dy + fromEl.offset.dy + fromEl.size.height / 2;
      final toY = _workspaceOffset.dy + toEl.offset.dy + toEl.size.height / 2;

      if (lineType == 'input') {
        fromX = _workspaceOffset.dx + fromEl.offset.dx + fromEl.size.width;
        toX = _workspaceOffset.dx + toEl.offset.dx;
      } else {
        fromX = _workspaceOffset.dx + fromEl.offset.dx + fromEl.size.width;
        toX = _workspaceOffset.dx + toEl.offset.dx;
      }

      final lineColor = lineType == 'input'
          ? const Color(0xFF00ACC1)
          : const Color(0xFF66BB6A);

      widgets.add(
        CustomPaint(
          painter: LinkerConnectionPainter(
            start: Offset(fromX, fromY),
            end: Offset(toX, toY),
            color: lineColor,
          ),
        ),
      );
    }
    return widgets;
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
    final startX = _workspaceOffset.dx +
        (isLeftPort ? sourceEl.offset.dx : sourceEl.offset.dx + sourceEl.size.width);
    final startY = _workspaceOffset.dy + sourceEl.offset.dy + sourceEl.size.height / 2;

    final lineColor = _hoveringTargetId != null
        ? const Color(0xFF00E676)
        : const Color(0xFF00ACC1);

    return CustomPaint(
      painter: LinkerConnectionPainter(
        start: Offset(startX, startY),
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

      if (sourceId != null && targetId != null) {
        connections.add({
          'from': sourceId,
          'fromPort': sourcePort,
          'to': el.id,
          'toPort': 'input',
          'linkerId': el.id,
          'type': 'input',
        });
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

      final elLeft = _workspaceOffset.dx + el.offset.dx;
      final elRight = elLeft + el.size.width;
      final elTop = _workspaceOffset.dy + el.offset.dy;
      final elCenterY = elTop + el.size.height / 2;
      final elType = el.module?.type;
      const double hitRadius = 35.0;

      if (elType == 'linker' || elType == 'text') {
        final leftPortPos = Offset(elLeft, elCenterY);
        if ((globalPosition - leftPortPos).distance < hitRadius) {
          if (_canConnect(el, 'input')) {
            newHoverTargetId = el.id;
            newHoverTargetPort = 'input';
            break;
          }
        }
      }

      if (elType == 'linker' || elType == 'progress' || elType == 'slider') {
        final rightPortPos = Offset(elRight, elCenterY);
        if ((globalPosition - rightPortPos).distance < hitRadius) {
          if (_canConnect(el, 'output')) {
            newHoverTargetId = el.id;
            newHoverTargetPort = 'output';
            break;
          }
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

  bool _isPortConnected(UIElement linkerElement, String portDirection) {
    if (linkerElement.module?.type != 'linker') return false;
    final linkerData = linkerElement.module!.properties['linker'] as Map?;
    if (linkerData == null) return false;
    if (portDirection == 'input') {
      return linkerData['sourceModuleId'] != null;
    } else {
      return linkerData['targetModuleId'] != null;
    }
  }

  // ===== 端口 Widget =====
  Widget _buildInteractivePort({
    required UIElement element,
    required bool isInput,
    bool isHovered = false,
    bool isConnected = false,
  }) {
    return Listener(
      onPointerDown: (event) {
        setState(() => _selectedTransformationId = element.id);
        setState(() {
          _isDraggingConnection = true;
          _draggingSourceId = element.id;
          _draggingSourcePort = isInput ? 'input' : 'output';
          _draggingSourceType = isInput ? 'input' : 'output';
          _dragConnectionEnd = event.position;
        });
      },
      child: Container(
        width: 36,
        height: 36,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: isHovered ? 22 : 18,
          height: isHovered ? 22 : 18,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isHovered
                  ? const Color(0xFF00E676)
                  : isConnected
                  ? const Color(0xFF00ACC1)
                  : const Color(0xFF888896),
              width: isHovered ? 3 : 2,
            ),
            boxShadow: [
              if (isHovered)
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isHovered ? 10 : 8,
              height: isHovered ? 10 : 8,
              decoration: BoxDecoration(
                color: (isConnected || isHovered)
                    ? (isHovered
                    ? const Color(0xFF00E676)
                    : const Color(0xFF00ACC1))
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

}
