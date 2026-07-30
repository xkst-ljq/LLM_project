import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 联动器连线的配色。
///
/// Studio 与 Assembly **必须共用同一套颜色**，否则同一条连线
/// 在两个编辑器里是两个颜色，作者无从建立肌肉记忆。
/// 这里把原先散落在 `ui_studio_page/linker.dart` 里的字面量收拢成常量。
class LinkerLineColors {
  const LinkerLineColors._();

  /// 接收线：外部组件 → 联动器左侧输入口。
  static const Color input = Color(0xFF00ACC1);

  /// 输出线：联动器右侧输出口 → 目标组件。
  static const Color output = Color(0xFF66BB6A);

  /// 算数操控线：接入 math_node 顶部 `gate_in` 的触发通路。
  /// 与数值线区分开，避免作者把触发源接到数据口。
  static const Color control = Color(0xFFFFB300);

  /// 复合组件的接收线。
  static const Color compositeInput = Color(0xFFFF4081);

  /// 复合组件的输出线。
  static const Color compositeOutput = Color(0xFF4FC3F7);

  /// 拖拽中命中合法目标时的高亮色。
  static const Color hitTarget = Color(0xFF00E676);

  /// 按连线属性挑选颜色。
  ///
  /// 优先级：控制线 > 复合件 > 普通输入 / 输出。
  /// 这个顺序不能调换——接入 `gate_in` 的线即使一端在复合件里，
  /// 也应当显示为控制线，因为「这是触发通路」比「这一端在复合件里」
  /// 更需要被一眼看出。
  static Color resolve({
    required bool isInput,
    bool isControlLine = false,
    bool isCompositePort = false,
  }) {
    if (isControlLine) return control;
    if (isCompositePort) return isInput ? compositeInput : compositeOutput;
    return isInput ? input : output;
  }
}

/// 联动器连线画笔。
///
/// 从 `ui_studio_page/painters.dart` 提取为共享组件，供 Assembly 复用。
/// 曲线形态、箭头位置与 Studio 完全一致，仅额外开放 [strokeWidth] 与
/// [opacity] 两个参数：
///
/// Assembly 的画布比 Studio 挤得多（PCB 宽度最小 212），
/// 同样粗细的实色连线会盖住元件。因此 Assembly 侧传入更细、更淡的值，
/// 而**不是**换一套配色——颜色语义必须与 Studio 匹配。
class LinkerConnectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final bool isControlLine;

  /// 线宽。Studio 用 2.5，Assembly 画布更挤，用更细的值弱化视觉压迫。
  final double strokeWidth;

  /// 整体不透明度。同上，Assembly 侧调淡以免盖住元件。
  final double opacity;

  /// 箭头尺寸。随线宽一起缩小，否则细线配大箭头会很突兀。
  final double arrowSize;

  /// 起点处的**出线方向**（单位向量，指向元件外侧）。
  ///
  /// 端口位置会随元件旋转，但曲线的切线方向如果不跟着转，
  /// 线从端口冒出来的那一小截永远朝右，元件转 90° 时线会先横着窜出去
  /// 再拐回来，看着像从元件侧面「漏」出来。
  ///
  /// 默认 (1, 0)：未旋转元件的输出口朝右，与历史行为一致。
  final Offset startDirection;

  /// 终点处的**入线方向**（单位向量，指向元件外侧）。
  ///
  /// 注意是「外侧」而非「行进方向」：线要从端口的正前方切进去，
  /// 所以控制点落在 `end + endDirection * offset`。
  /// 默认 (-1, 0)：未旋转元件的输入口朝左，与历史行为一致。
  final Offset endDirection;

  const LinkerConnectionPainter({
    required this.start,
    required this.end,
    required this.color,
    this.isControlLine = false,
    this.strokeWidth = 2.5,
    this.opacity = 1.0,
    this.arrowSize = 9.0,
    this.startDirection = const Offset(1, 0),
    this.endDirection = const Offset(-1, 0),
  });

  /// 未旋转元件的默认出线方向（输出口朝右）。
  static const Offset defaultStartDirection = Offset(1, 0);

  /// 未旋转元件的默认入线方向（输入口朝左）。
  static const Offset defaultEndDirection = Offset(-1, 0);

  /// 顶部 `gate_in` 在未旋转时的入线方向（朝上）。
  static const Offset gateEndDirection = Offset(0, -1);

  /// 把一个方向向量按角度旋转，用于让端口切线跟随元件旋转。
  static Offset rotateDirection(Offset direction, double degrees) {
    if (degrees == 0.0) return direction;
    final rad = degrees * math.pi / 180.0;
    final cos = math.cos(rad);
    final sin = math.sin(rad);
    return Offset(
      direction.dx * cos - direction.dy * sin,
      direction.dx * sin + direction.dy * cos,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveColor =
        opacity >= 1.0 ? color : color.withValues(alpha: opacity);

    final paint = Paint()
      ..color = effectiveColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(start.dx, start.dy);

    // 控制点臂长。
    //
    // 历史公式只取水平分量 `|dx| * 0.4`——那是「切线恒为水平」时的合理近似。
    // 一旦端口因元件旋转而朝向别的方向，两端垂直对齐时 dx 趋近 0，
    // 曲线会塌成一条直线段，连弧度都没有。
    // 因此只在两端切线都是默认水平方向时沿用旧公式（保持 Studio 观感不变），
    // 其余情况改用两点直线距离，曲率才跟得上朝向。
    final bool isAxisAligned = startDirection == defaultStartDirection &&
        (endDirection == defaultEndDirection ||
            endDirection == gateEndDirection);
    final controlOffset = isAxisAligned
        ? (end.dx - start.dx).abs() * 0.4
        : (end - start).distance * 0.4;

    // 起点顺着端口朝向出线，终点从端口正前方入线。
    final cp1 = start + startDirection * controlOffset;
    // 顶部 Gate 的引导段保底 24，避免短距离连线看不出「从上方接入」。
    final cp2 = isControlLine
        ? end + endDirection * math.max(24.0, controlOffset * 0.55)
        : end + endDirection * controlOffset;
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    const t = 0.5;
    final arrowCenter = Offset(
      _bezierPoint(start.dx, cp1.dx, cp2.dx, end.dx, t),
      _bezierPoint(start.dy, cp1.dy, cp2.dy, end.dy, t),
    );
    final dx = _bezierDerivative(start.dx, cp1.dx, cp2.dx, end.dx, t);
    final dy = _bezierDerivative(start.dy, cp1.dy, cp2.dy, end.dy, t);
    final arrowAngle = math.atan2(dy, dx);
    canvas.drawPath(path, paint);

    final arrowPaint = Paint()
      ..color = effectiveColor
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(arrowCenter.dx, arrowCenter.dy)
      ..lineTo(
        arrowCenter.dx - arrowSize * math.cos(arrowAngle - 0.5),
        arrowCenter.dy - arrowSize * math.sin(arrowAngle - 0.5),
      )
      ..lineTo(
        arrowCenter.dx - arrowSize * math.cos(arrowAngle + 0.5),
        arrowCenter.dy - arrowSize * math.sin(arrowAngle + 0.5),
      )
      ..close();
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
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color ||
        oldDelegate.isControlLine != isControlLine ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.opacity != opacity ||
        oldDelegate.arrowSize != arrowSize ||
        oldDelegate.startDirection != startDirection ||
        oldDelegate.endDirection != endDirection;
  }
}
