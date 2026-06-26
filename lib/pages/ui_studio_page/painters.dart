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

  StudioAlternatingDashedBorderPainter({
    this.strokeWidth = 1.2,
    this.shape = UIModuleShape.rounded,
    this.borderRadius = 12,
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
        path.addOval(rect);
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
        oldDelegate.borderRadius != borderRadius;
  }
}

class LinkerConnectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  LinkerConnectionPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(start.dx, start.dy);

    final controlOffset = (end.dx - start.dx).abs() * 0.4;
    final cp1 = Offset(start.dx + controlOffset, start.dy);
    final cp2 = Offset(end.dx - controlOffset, end.dy);

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);

    final t = 0.5;
    final midX = _bezierPoint(start.dx, cp1.dx, cp2.dx, end.dx, t);
    final midY = _bezierPoint(start.dy, cp1.dy, cp2.dy, end.dy, t);

    final dx = _bezierDerivative(start.dx, cp1.dx, cp2.dx, end.dx, t);
    final dy = _bezierDerivative(start.dy, cp1.dy, cp2.dy, end.dy, t);
    final angle = math.atan2(dy, dx);

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowSize = 9.0;
    final arrowPath = Path();
    arrowPath.moveTo(midX, midY);
    arrowPath.lineTo(
      midX - arrowSize * math.cos(angle - 0.5),
      midY - arrowSize * math.sin(angle - 0.5),
    );
    arrowPath.lineTo(
      midX - arrowSize * math.cos(angle + 0.5),
      midY - arrowSize * math.sin(angle + 0.5),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  double _bezierPoint(double p0, double p1, double p2, double p3, double t) {
    final mt = 1 - t;
    return mt * mt * mt * p0 +
        3 * mt * mt * t * p1 +
        3 * mt * t * t * p2 +
        t * t * t * p3;
  }

  double _bezierDerivative(
      double p0, double p1, double p2, double p3, double t) {
    final mt = 1 - t;
    return 3 * mt * mt * (p1 - p0) +
        6 * mt * t * (p2 - p1) +
        3 * t * t * (p3 - p2);
  }

  @override
  bool shouldRepaint(covariant LinkerConnectionPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

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
