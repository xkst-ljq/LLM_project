import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui_models.dart';
import 'ui_renderer.dart';

/// 选中态虚线外框。
///
/// 灰白交替的短划线，**按组件自身形状描边**——圆形指示点画圆、
/// 开关画胶囊、心形进度条画心形，而不是一律套圆角矩形。
///
/// 从 `ui_studio_page/painters.dart` 提取为共享实现：
/// 那个文件是 `part of ui_studio_page.dart`，无法被 Assembly 导入，
/// 而两个编辑器的选中框必须长得一样。
class DashedSelectionBorderPainter extends CustomPainter {
  final double strokeWidth;
  final UIModuleShape shape;
  final double borderRadius;
  final bool isPerfectCircle;

  DashedSelectionBorderPainter({
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
  bool shouldRepaint(covariant DashedSelectionBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.shape != shape ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isPerfectCircle != isPerfectCircle;
  }
}
