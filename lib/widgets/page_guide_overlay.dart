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

  PageGuideTarget? _selectedTarget;
  late final AnimationController _pulseController;
  double _dragDx = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
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

  @override
  Widget build(BuildContext context) {
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
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 8,
            child: _GuideTopBar(title: widget.title, onExit: widget.onExit),
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
          if (_selectedTarget == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: _GuideHintCard(hint: widget.hint),
            ),
        ],
      ),
    );
  }

  Rect _badgeRect(BuildContext context, PageGuideTarget target) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final rect = target.rect;

    final placeRight = rect.center.dx < screenWidth / 2;
    final rawLeft = placeRight ? rect.right + 8 : rect.left - _badgeSize - 8;
    final left = rawLeft.clamp(8.0, screenWidth - _badgeSize - 8).toDouble();
    final top = (rect.center.dy - _badgeSize / 2)
        .clamp(
          MediaQuery.of(context).padding.top + 56.0,
          screenHeight - _badgeSize - 56.0,
        )
        .toDouble();

    return Rect.fromLTWH(left, top, _badgeSize, _badgeSize);
  }
}

class _GuideTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onExit;

  const _GuideTopBar({required this.title, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.tips_and_updates_outlined,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: onExit,
              child: const Text('退出', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideHintCard extends StatelessWidget {
  final String hint;

  const _GuideHintCard({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.touch_app_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(hint, style: const TextStyle(height: 1.35))),
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

    // 说明框固定放在序号上方，水平中心对齐序号。
    // 如果顶部空间不足，再自动放到序号下方，避免被顶部导览栏挡住。
    final centeredLeft = badgeRect.center.dx -
        _PageGuideOverlayState._expandedCardWidth / 2;
    final left = centeredLeft
        .clamp(
          12.0,
          screenSize.width - _PageGuideOverlayState._expandedCardWidth - 12,
        )
        .toDouble();

    final topAbove = badgeRect.top - estimatedHeight - 10;
    final topBelow = badgeRect.bottom + 10;
    final hasEnoughSpaceAbove = topAbove >= safeTop + 62;
    final rawTop = hasEnoughSpaceAbove ? topAbove : topBelow;
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
