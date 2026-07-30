part of 'ui_studio_page.dart';

class StudioWarmGridPainter extends CustomPainter {
  final Offset offset;
  StudioWarmGridPainter(this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFFD0D0D8)
      ..strokeWidth = 1.0;

    const double step = 40.0;

    double x = offset.dx % step;
    if (x < 0) x += step;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintLine);
      x += step;
    }

    double y = offset.dy % step;
    if (y < 0) y += step;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLine);
      y += step;
    }
  }

  @override
  bool shouldRepaint(covariant StudioWarmGridPainter oldDelegate) =>
      oldDelegate.offset != offset;
}

class StudioAlternatingDashedBorderPainter extends CustomPainter {
  final double strokeWidth;
  final UIModuleShape shape;
  final double borderRadius;
  final bool isPerfectCircle;

  StudioAlternatingDashedBorderPainter({
    this.strokeWidth = 1.2,
    this.shape = UIModuleShape.rounded,
    this.borderRadius = 12,
    this.isPerfectCircle = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path();
    switch (shape) {
      case UIModuleShape.rectangle:
        path.addRect(rect);
        break;
      case UIModuleShape.circle:
        if (isPerfectCircle) {
          final side = math.min(rect.width, rect.height);
          path.addOval(Rect.fromCenter(center: rect.center, width: side, height: side));
        } else {
          path.addOval(rect);
        }
        break;
      case UIModuleShape.capsule:
        path.addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
        );
        break;
      case UIModuleShape.rounded:
        path.addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
        );
        break;
      case UIModuleShape.heart:
        path.addPath(getHeartPath(rect), Offset.zero);
        break;
      case UIModuleShape.star5:
        path.addPath(getStarPath(rect, 5, 0.45), Offset.zero);
        break;
      case UIModuleShape.star4:
        path.addPath(getStarPath(rect, 4, 0.4), Offset.zero);
        break;
    }

    final greyPaint = Paint()
      ..color = const Color(0xFFB8B8C2).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dashLength = 6.0;
    const gapLength = 2.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var drawWhite = false;
      while (distance < metric.length) {
        final next =
        (distance + dashLength).clamp(0.0, metric.length).toDouble();
        final dashPath = metric.extractPath(distance, next);
        canvas.drawPath(dashPath, drawWhite ? whitePaint : greyPaint);
        distance = next + gapLength;
        drawWhite = !drawWhite;
      }
    }
  }

  @override
  bool shouldRepaint(covariant StudioAlternatingDashedBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.shape != shape ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isPerfectCircle != isPerfectCircle;
  }
}

// LinkerConnectionPainter 已提取到
// `services/ui_engine/linker_connection_painter.dart`，
// 由 Studio 与 Assembly 共用——两边各留一份实现必然漂移，
// 而连线配色的语义一致性是作者建立肌肉记忆的前提。

class ConnectionLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final bool isDashed;

  ConnectionLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.isDashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midX = (start.dx + end.dx) / 2;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);

    if (isDashed) {
      _drawDashedPath(canvas, path, paint, 8, 4);
    } else {
      canvas.drawPath(path, paint);
    }

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 5, dotPaint);
    canvas.drawCircle(end, 5, dotPaint);
  }

  void _drawDashedPath(
      Canvas canvas, Path path, Paint paint, double dashWidth, double dashGap) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final len = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        canvas.drawPath(
            metric.extractPath(distance, distance + len), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(ConnectionLinePainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color ||
        oldDelegate.isDashed != isDashed;
  }
}



/// 模拟预览不绘制工作室网格的空画笔。
class _PreviewBlankPainter extends CustomPainter {
  const _PreviewBlankPainter();

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant _PreviewBlankPainter oldDelegate) => false;
}
