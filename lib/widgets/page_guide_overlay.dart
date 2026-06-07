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

  const PageGuideTarget({
    required this.id,
    required this.order,
    required this.rect,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.onSwipeLeft,
  });
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
  PageGuideTarget? _selectedTarget;
  late final AnimationController _pulseController;

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

  void _showTarget(PageGuideTarget target) {
    setState(() {
      _selectedTarget = target;
    });
  }

  void _hideTargetCard() {
    setState(() {
      _selectedTarget = null;
    });
  }

  void _handleTargetTap(PageGuideTarget target) {
    if (target.onSwipeLeft != null) {
      _showTarget(target);
      return;
    }

    if (target.onAction != null) {
      target.onAction!();
      return;
    }

    _showTarget(target);
  }

  double _dragDx = 0.0;

  void _handleDragStart(PageGuideTarget target) {
    if (target.onSwipeLeft == null) return;
    _dragDx = 0.0;
  }

  void _handleDragUpdate(PageGuideTarget target, DragUpdateDetails details) {
    if (target.onSwipeLeft == null) return;
    _dragDx += details.delta.dx;
  }

  void _handleDragEnd(PageGuideTarget target, DragEndDetails details) {
    if (target.onSwipeLeft == null) return;

    final velocity = details.primaryVelocity ?? 0.0;
    if (_dragDx < -36 || velocity < -260) {
      target.onSwipeLeft!();
    } else {
      _showTarget(target);
    }
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
          for (final target in targets) ...[
            Positioned.fromRect(
              rect: target.rect.inflate(4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleTargetTap(target),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: _badgeLeft(context, target.rect),
              top: _badgeTop(context, target.rect),
              child: GestureDetector(
                onTap: () => _showTarget(target),
                child: _GuideNumberBadge(number: target.order),
              ),
            ),
          ],
          if (_selectedTarget == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: _GuideHintCard(hint: widget.hint),
            )
          else
            _PositionedTargetCard(
              target: _selectedTarget!,
              onClose: _hideTargetCard,
            ),
        ],
      ),
    );
  }

  double _badgeLeft(BuildContext context, Rect rect) {
    final width = MediaQuery.of(context).size.width;
    return (rect.left - 12).clamp(8.0, width - 48.0).toDouble();
  }

  double _badgeTop(BuildContext context, Rect rect) {
    final height = MediaQuery.of(context).size.height;
    return (rect.top - 12)
        .clamp(MediaQuery.of(context).padding.top + 58.0, height - 64.0)
        .toDouble();
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

class _PositionedTargetCard extends StatelessWidget {
  final PageGuideTarget target;
  final VoidCallback onClose;

  const _PositionedTargetCard({required this.target, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final cardWidth = screenSize.width - 32;
    const estimatedCardHeight = 210.0;

    final preferBelow = target.rect.center.dy < screenSize.height * 0.48;
    final left = 16.0;
    final topIfBelow = target.rect.bottom + 14;
    final topIfAbove = target.rect.top - estimatedCardHeight - 14;
    final minTop = safeTop + 70;
    final maxTop = screenSize.height - safeBottom - estimatedCardHeight - 16;
    final top = (preferBelow ? topIfBelow : topIfAbove)
        .clamp(minTop, maxTop)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: _GuideTargetCard(target: target, onClose: onClose),
    );
  }
}

class _GuideTargetCard extends StatelessWidget {
  final PageGuideTarget target;
  final VoidCallback onClose;

  const _GuideTargetCard({required this.target, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭说明',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(target.description, style: const TextStyle(height: 1.45)),
            if (target.actionLabel != null && target.onAction != null) ...[
              const SizedBox(height: 12),
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
    );
  }
}

class _GuideNumberBadge extends StatelessWidget {
  final int number;
  final bool small;

  const _GuideNumberBadge({required this.number, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 30.0 : 40.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: small ? 13 : 17,
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
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(14)),
      );
    }

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 + pulseValue * 1.2
      ..color = Colors.white.withValues(alpha: 0.9);

    for (final rect in targets) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(14)),
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
