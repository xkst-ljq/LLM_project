import 'package:flutter/material.dart';

class PageGuideTarget {
  final String id;
  final int order;
  final Rect rect;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const PageGuideTarget({
    required this.id,
    required this.order,
    required this.rect,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  bool get isGestureTarget => onSwipeLeft != null || onSwipeRight != null;
}

class PageGuideOverlay extends StatefulWidget {
  final String title;
  final String hint;
  final List<PageGuideTarget> targets;
  final VoidCallback onExit;

  const PageGuideOverlay({
    super.key,
    required this.title,
    required this.hint,
    required this.targets,
    required this.onExit,
  });

  @override
  State<PageGuideOverlay> createState() => _PageGuideOverlayState();
}

class _PageGuideOverlayState extends State<PageGuideOverlay>
    with SingleTickerProviderStateMixin {
  static const double _badgeSize = 30.0;
  static const double _expandedCardWidth = 260.0;

  /// 本次 App 运行期间记住提示图标位置。
  /// 这样进入不同页面时，提示图标不会每页乱跳。
  static Offset? _rememberedPanelOffset;

  PageGuideTarget? _selectedTarget;
  late final AnimationController _pulseController;
  double _dragDx = 0.0;

  bool _panelExpanded = false;
  bool _panelPositionInitialized = false;
  Offset _panelOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      setState(() {
        _panelOffset = Offset(size.width - 64, size.height * 0.62);
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleTarget(PageGuideTarget target) {
    setState(() {
      _selectedTarget = _selectedTarget?.id == target.id ? null : target;
    });
  }

  void _handleTargetTap(PageGuideTarget target) {
    if (target.isGestureTarget) {
      _toggleTarget(target);
      return;
    }

    if (target.onAction != null) {
      target.onAction!();
      return;
    }

    _toggleTarget(target);
  }

  void _ensurePanelPosition() {
    if (_panelPositionInitialized) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _panelPositionInitialized) return;

      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;

      final defaultOffset = Offset(
        size.width - 58,
        (size.height * 0.58).clamp(
          padding.top + 16,
          size.height - padding.bottom - 58,
        ),
      );

      final initialOffset = _rememberedPanelOffset ?? defaultOffset;

      setState(() {
        _panelOffset = _clampPanelOffset(initialOffset);
        _rememberedPanelOffset = _panelOffset;
        _panelPositionInitialized = true;
      });
    });
  }

  void _snapPanelToEdge() {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    final panelWidth = _panelExpanded ? 284.0 : 46.0;
    final panelHeight = _panelExpanded ? 190.0 : 46.0;

    final leftDistance = _panelOffset.dx;
    final rightDistance = size.width - (_panelOffset.dx + panelWidth);

    final snapLeft = leftDistance <= rightDistance;

    final nextOffset = Offset(
      snapLeft ? 8 : size.width - panelWidth - 8,
      _panelOffset.dy
          .clamp(
        padding.top + 8,
        size.height - padding.bottom - panelHeight - 8,
      )
          .toDouble(),
    );

    setState(() {
      _panelOffset = nextOffset;
    });

    // 记住吸附后的稳定位置。
    _rememberedPanelOffset = nextOffset;
  }

  void _handleDragStart(PageGuideTarget target) {
    if (!target.isGestureTarget) return;
    _dragDx = 0.0;
  }

  void _handleDragUpdate(PageGuideTarget target, DragUpdateDetails details) {
    if (!target.isGestureTarget) return;
    _dragDx += details.delta.dx;
  }

  void _handleDragEnd(PageGuideTarget target, DragEndDetails details) {
    if (!target.isGestureTarget) return;

    final velocity = details.primaryVelocity ?? 0.0;
    if ((_dragDx < -36 || velocity < -260) && target.onSwipeLeft != null) {
      target.onSwipeLeft!();
      return;
    }

    if ((_dragDx > 36 || velocity > 260) && target.onSwipeRight != null) {
      target.onSwipeRight!();
      return;
    }

    _toggleTarget(target);
  }

  Offset _clampPanelOffset(Offset offset) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    final panelWidth = _panelExpanded ? 284.0 : 46.0;
    final panelHeight = _panelExpanded ? 190.0 : 46.0;

    return Offset(
      offset.dx.clamp(8.0, size.width - panelWidth - 8).toDouble(),
      offset.dy
          .clamp(
        padding.top + 8,
        size.height - padding.bottom - panelHeight - 8,
      )
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensurePanelPosition();

    final targets = widget.targets;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _GuideMaskPainter(
                    targets: targets.map((e) => e.rect).toList(),
                    pulseValue: _pulseController.value,
                  ),
                );
              },
            ),
          ),
          for (final target in targets)
            Positioned.fromRect(
              rect: target.rect.inflate(3),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleTargetTap(target),
                onHorizontalDragStart: target.isGestureTarget
                    ? (_) => _handleDragStart(target)
                    : null,
                onHorizontalDragUpdate: target.isGestureTarget
                    ? (details) => _handleDragUpdate(target, details)
                    : null,
                onHorizontalDragEnd: target.isGestureTarget
                    ? (details) => _handleDragEnd(target, details)
                    : null,
                child: const SizedBox.expand(),
              ),
            ),

          for (final target in targets)
            Positioned.fromRect(
              rect: _badgeRect(context, target),
              child: GestureDetector(
                onTap: () => _toggleTarget(target),
                child: _GuideNumberBadge(number: target.order),
              ),
            ),

          if (_selectedTarget != null)
            _ExpandedBadgeInfo(
              target: _selectedTarget!,
              badgeRect: _badgeRect(context, _selectedTarget!),
              onClose: () => _toggleTarget(_selectedTarget!),
            ),
          _DraggableGuidePanel(
            title: widget.title,
            hint: widget.hint,
            expanded: _panelExpanded,
            offset: _panelOffset,
            onDragEnd: _snapPanelToEdge,
            onToggle: () {
              if (_panelExpanded) {
                setState(() {
                  _panelExpanded = false;
                });

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _snapPanelToEdge();
                });
              } else {
                _snapPanelToEdge();

                setState(() {
                  _panelExpanded = true;
                });
              }
            },
            onExit: widget.onExit,
            onDragUpdate: (delta) {
              final nextOffset = _clampPanelOffset(_panelOffset + delta);

              setState(() {
                _panelOffset = nextOffset;
              });

              // 拖动过程中也记录当前位置。
              // 松手后 _snapPanelToEdge 会再记录最终吸附位置。
              _rememberedPanelOffset = nextOffset;
            },
          ),
        ],
      ),
    );
  }

  Rect _badgeRect(BuildContext context, PageGuideTarget target) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final rect = target.rect;

    const gap = 8.0;

    final placeRight = rect.center.dx < screenWidth / 2;
    final rawLeft = placeRight
        ? rect.right + gap
        : rect.left - _badgeSize - gap;

    final left = rawLeft
        .clamp(8.0, screenWidth - _badgeSize - 8)
        .toDouble();

    final top = (rect.center.dy - _badgeSize / 2)
        .clamp(
      MediaQuery.of(context).padding.top + 56.0,
      screenHeight - _badgeSize - 56.0,
    )
        .toDouble();

    return Rect.fromLTWH(left, top, _badgeSize, _badgeSize);
  }
}

class _DraggableGuidePanel extends StatelessWidget {
  final String title;
  final String hint;
  final bool expanded;
  final Offset offset;
  final VoidCallback onToggle;
  final VoidCallback onExit;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableGuidePanel({
    required this.title,
    required this.hint,
    required this.expanded,
    required this.offset,
    required this.onToggle,
    required this.onExit,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    const expandedWidth = 284.0;
    const expandedHeight = 190.0;

    final attachedLeft = offset.dx < screenSize.width / 2;

    final left = expanded
        ? (attachedLeft ? 8.0 : screenSize.width - expandedWidth - 8)
        : offset.dx;

    final top = expanded
        ? offset.dy
        .clamp(
      padding.top + 8,
      screenSize.height - padding.bottom - expandedHeight - 8,
    )
        .toDouble()
        : offset.dy;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: expanded
            ? null
            : (details) => onDragUpdate(details.delta),
        onPanEnd: expanded ? null : (_) => onDragEnd(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: expanded
              ? _buildExpanded(context)
              : _buildCollapsed(context),
        ),
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('guide_collapsed'),
      onTap: onToggle,
      child: Material(
        elevation: 10,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
            ),
          ),
          child: const Icon(
            Icons.tips_and_updates_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Material(
      key: const ValueKey('guide_expanded'),
      elevation: 12,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 284,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '缩小',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggle,
                  icon: const Icon(Icons.remove),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onExit,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('退出教程'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedBadgeInfo extends StatelessWidget {
  final PageGuideTarget target;
  final Rect badgeRect;
  final VoidCallback onClose;

  const _ExpandedBadgeInfo({
    required this.target,
    required this.badgeRect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final estimatedHeight = target.actionLabel == null ? 150.0 : 196.0;

// 从点击的序号位置展开。
// 序号在屏幕左侧时，说明框向右展开；
// 序号在屏幕右侧时，说明框向左展开。
    final expandToRight = badgeRect.center.dx < screenSize.width / 2;
    final rawLeft = expandToRight
        ? badgeRect.left
        : badgeRect.right - _PageGuideOverlayState._expandedCardWidth;

    final left = rawLeft
        .clamp(
      12.0,
      screenSize.width - _PageGuideOverlayState._expandedCardWidth - 12,
    )
        .toDouble();

    final rawTop = badgeRect.top - 6;
    final top = rawTop
        .clamp(
      safeTop + 62.0,
      screenSize.height - safeBottom - estimatedHeight - 16,
    )
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: _PageGuideOverlayState._expandedCardWidth,
      child: GestureDetector(
        onTap: onClose,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Card(
            key: ValueKey(target.id),
            elevation: 12,
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.90),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _GuideNumberBadge(number: target.order, small: true),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          target.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(Icons.close, size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(target.description, style: const TextStyle(height: 1.4)),
                  if (target.actionLabel != null && target.onAction != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: target.onAction,
                        child: Text(target.actionLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideNumberBadge extends StatelessWidget {
  final int number;
  final bool small;

  const _GuideNumberBadge({required this.number, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 24.0 : 30.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 7, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: small ? 11 : 13,
        ),
      ),
    );
  }
}

class _GuideMaskPainter extends CustomPainter {
  final List<Rect> targets;
  final double pulseValue;

  const _GuideMaskPainter({required this.targets, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);

    for (final rect in targets) {
      overlayPath.addRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(14)),
      );
    }

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 + pulseValue * 1.1
      ..color = Colors.white.withValues(alpha: 0.9);

    for (final rect in targets) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(14)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuideMaskPainter oldDelegate) {
    return oldDelegate.targets != targets ||
        oldDelegate.pulseValue != pulseValue;
  }
}
