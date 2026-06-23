import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    if (element.isComposite && element.composite != null) {
      return _renderComposite(context, element.composite!, element.size);
    } else if (!element.isComposite && element.module != null) {
      return _renderModule(context, element.module!, element.size);
    }
    return const SizedBox();
  }

  static Widget _renderModule(BuildContext context, UIModule module, Size size) {
    // 原子部件只渲染自己的单一职责：
    // progress = 一根条；text = 一段文字；surface/base_box = 一个视觉表面；
    // button/input = 透明逻辑热区，不自带任何边框或底色。
    switch (module.type) {
      case 'progress':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildProgressBar(module, size),
        );
      case 'text':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildTextBlock(module),
        );
      case 'input':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildInputBlock(module),
        );
      case 'slider':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSlider(module),
        );
      case 'primitive_art':
      case 'surface_art':
      case 'light_effect':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(
            painter: UIPrimitiveArtPainter(module.properties),
          ),
        );
      case 'button':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildButton(module),
        );
      case 'surface':
      case 'base_box':
        return _applyMaterialAndShape(
          module.material,
          module.shape,
          module.color,
          module.opacity,
          module.borderRadius,
          _buildBaseBox(),
          size,
        );
      default:
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Center(
            child: Text(
              '未知控件: ${module.type}',
              style: const TextStyle(color: Color(0xFF111116), fontSize: 12),
            ),
          ),
        );
    }
  }

  static Widget _renderComposite(BuildContext context, UIComposite composite, Size size) {
    Widget content;
    switch (composite.layoutType) {
      case 'column':
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'row':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'stack':
        content = Stack(
          alignment: Alignment.center,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'wrap':
        content = Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'base_box':
      default:
        // 复合容器本体只负责承载子元素。空态提示属于编辑器 UI，
        // 不应进入最终渲染结果。
        content = Stack(
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
    }

    // opacity <= 0 且颜色透明的组合块视作“纯布局组”，不额外绘制容器壳。
    // 这让带文字按钮等复合模板可以只由内部原子决定视觉。
    if (composite.opacity <= 0.0 && composite.color == Colors.transparent) {
      return SizedBox(width: size.width, height: size.height, child: content);
    }

    return _applyMaterialAndShape(
      composite.material,
      UIModuleShape.rounded,
      composite.color,
      composite.opacity,
      composite.borderRadius,
      content,
      size,
    );
  }

  // 极其高雅通透的纯白/微光毛玻璃外壳封装，完美契合主 App 主题
  static Widget _applyMaterialAndShape(
    UIModuleMaterial material,
    UIModuleShape shape,
    Color color,
    double opacity,
    double rawRadius,
    Widget child,
    Size size,
  ) {
    BorderRadius radius;
    switch (shape) {
      case UIModuleShape.rectangle:
        radius = BorderRadius.zero;
        break;
      case UIModuleShape.capsule:
        radius = BorderRadius.circular(9999.0);
        break;
      case UIModuleShape.circle:
        // 这里的 circle 作为“椭圆/正圆”处理：宽高相等时是正圆，
        // 宽高不等时自然成为椭圆。不要与 capsule 胶囊混用。
        radius = BorderRadius.all(
          Radius.elliptical(size.width / 2, size.height / 2),
        );
        break;
      case UIModuleShape.rounded:
        radius = BorderRadius.circular(rawRadius);
        break;
    }

    BoxDecoration decoration;
    switch (material) {
      case UIModuleMaterial.solid:
        decoration = BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.black.withValues(alpha: 0.04), width: 0.5),
        );
        break;
      case UIModuleMaterial.gradient:
        decoration = BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: opacity * 0.5),
            ],
          ),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 0.5),
        );
        break;
      case UIModuleMaterial.outline:
        decoration = BoxDecoration(
          color: color.withValues(alpha: 0.05 * opacity),
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: opacity), width: 1.5),
        );
        break;
      case UIModuleMaterial.glass:
        // 高雅纯白物理毛玻璃模糊
        decoration = BoxDecoration(
          color: color.withValues(alpha: opacity * 0.75), // 明亮通透的底色
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
        );
        break;
    }

    Widget container = Container(
      width: size.width,
      height: size.height,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: child,
        ),
      ),
    );

    if (material == UIModuleMaterial.glass) {
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: container,
        ),
      );
    }

    return container;
  }

  static Widget _buildBaseBox() {
    // 原子容器只提供容器面，不带说明文字。说明文字属于编辑器预览。
    return const SizedBox.expand();
  }

  static Widget _buildProgressBar(UIModule module, Size size) {
    final double maxVal = (module.properties['max'] ?? 100.0).toDouble();
    final double curVal = (module.properties['current'] ?? 80.0).toDouble();
    final double ratio = maxVal > 0 ? (curVal / maxVal).clamp(0.0, 1.0) : 1.0;
    final Color fillColor =
        module.color == Colors.white ? const Color(0xFFFF4081) : module.color;

    // 原子进度条只负责显示“条本体”，不显示名称、数值或单位。
    // 方向固定为横向：竖向进度条以后交给旋转/变换系统处理，避免
    // 用户仅改变宽高比例时组件语义突然变化。
    //
    // 注意：轨道本身负责裁剪成胶囊形，填充块只是一块矩形色块。
    // 这样在特殊宽高比例下，填充边界不会因为自身也套胶囊圆角而
    // 和整体轨道/选中虚线边界产生视觉错位。
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: Color(0xFFE2E2E8),
        ),
        child: FractionallySizedBox(
          widthFactor: ratio,
          heightFactor: 1.0,
          alignment: Alignment.centerLeft,
          child: Container(color: fillColor),
        ),
      ),
    );
  }

  static Widget _buildSlider(UIModule module) {
    final double maxVal = (module.properties['max'] ?? 100.0).toDouble();
    final double curVal = (module.properties['current'] ?? 50.0).toDouble();
    final double ratio = maxVal > 0 ? (curVal / maxVal).clamp(0.0, 1.0) : 0.5;
    final Color fillColor =
        module.color == Colors.white ? const Color(0xFF00ACC1) : module.color;

    // 基础滑块原语：只提供轨道 + 滑块柄的通用数值控制外观。
    // 它不命名具体业务变量，变量绑定应在 UI 场景层完成。
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 160.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 28.0;
        final trackHeight = (h * 0.22).clamp(3.0, 10.0);
        final knobSize = (h * 0.72).clamp(10.0, 28.0);
        final knobLeft = (w - knobSize) * ratio;
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: knobSize / 2,
              right: knobSize / 2,
              top: (h - trackHeight) / 2,
              height: trackHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(color: const Color(0xFFE2E2E8)),
              ),
            ),
            Positioned(
              left: knobSize / 2,
              width: (w - knobSize) * ratio,
              top: (h - trackHeight) / 2,
              height: trackHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(color: fillColor.withValues(alpha: 0.72)),
              ),
            ),
            Positioned(
              left: knobLeft,
              top: (h - knobSize) / 2,
              width: knobSize,
              height: knobSize,
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildButton(UIModule module) {
    // 原子按钮只提供透明点击逻辑热区，不自带视觉外观。
    // 视觉按钮 = surface + text/icon + button 逻辑区的复合块。
    return const SizedBox.expand();
  }

  static Widget _buildTextBlock(UIModule module) {
    final text = module.properties['text']?.toString() ?? module.name;
    return Container(
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(color: module.color, fontSize: 14, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static Widget _buildInputBlock(UIModule module) {
    // 原子输入框只提供透明输入逻辑热区，不自带边框、底色或 placeholder。
    // 视觉输入框 = surface + placeholder text + input 逻辑区的复合块。
    return const SizedBox.expand();
  }

}


class UIPrimitiveArtPainter extends CustomPainter {
  final Map<String, dynamic> properties;

  UIPrimitiveArtPainter(this.properties);

  @override
  void paint(Canvas canvas, Size size) {
    final rawLayers = properties['layers'];
    if (rawLayers is! List || size.width <= 0 || size.height <= 0) return;

    final layers = <UIPrimitiveLayer>[];
    for (final raw in rawLayers) {
      if (raw is Map) {
        layers.add(UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (layers.isEmpty) return;

    for (final layer in layers) {
      _paintLayer(canvas, size, layer);
    }
  }

  Rect _layerRect(Size canvasSize, UIPrimitiveLayer layer) {
    return Rect.fromLTWH(
      layer.offset.dx * canvasSize.width,
      layer.offset.dy * canvasSize.height,
      layer.size.width * canvasSize.width,
      layer.size.height * canvasSize.height,
    );
  }

  void _paintLayer(Canvas canvas, Size canvasSize, UIPrimitiveLayer layer) {
    final rect = _layerRect(canvasSize, layer);
    if (rect.width <= 0 || rect.height <= 0) return;

    final color = layer.color.withValues(alpha: layer.opacity.clamp(0.0, 1.0).toDouble());
    final kind = layer.kind;
    final blendMode = _readBlendMode(
      layer.properties['blendMode']?.toString(),
      fallback: _defaultBlendModeForKind(kind),
    );

    if (kind == 'surface') {
      _paintSurfaceLayer(canvas, rect, layer, color, blendMode);
      return;
    }

    if (kind == 'glow') {
      final blur = (layer.properties['blur'] as num?)?.toDouble() ?? 18.0;
      final paint = Paint()
        ..color = color
        ..blendMode = blendMode
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur);
      _drawShape(canvas, rect, layer, paint);
      return;
    }

    if (kind == 'stroke') {
      final width = (layer.properties['width'] as num?)?.toDouble() ?? 1.5;
      final paint = Paint()
        ..color = color
        ..blendMode = blendMode
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      _drawShape(canvas, rect.deflate(width / 2), layer, paint);
      return;
    }

    if (kind == 'highlight') {
      final paint = Paint()
        ..blendMode = blendMode
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.0)],
        ).createShader(rect);
      _drawShape(canvas, rect, layer, paint);
      return;
    }

    if (kind == 'line') {
      final width = (layer.properties['width'] as num?)?.toDouble() ?? 1.0;
      final paint = Paint()
        ..color = color
        ..blendMode = blendMode
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(rect.centerLeft, rect.centerRight, paint);
      return;
    }

    final paint = Paint()
      ..color = color
      ..blendMode = blendMode
      ..style = PaintingStyle.fill;
    _drawShape(canvas, rect, layer, paint);
  }

  void _paintSurfaceLayer(
    Canvas canvas,
    Rect rect,
    UIPrimitiveLayer layer,
    Color color,
    BlendMode blendMode,
  ) {
    final material = _readMaterial(layer.properties['material']);
    if (material == UIModuleMaterial.gradient) {
      final paint = Paint()
        ..blendMode = blendMode
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.62)],
        ).createShader(rect);
      _drawShape(canvas, rect, layer, paint);
      return;
    }

    if (material == UIModuleMaterial.outline) {
      final width = (layer.properties['width'] as num?)?.toDouble() ?? 1.5;
      final paint = Paint()
        ..color = color
        ..blendMode = blendMode
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      _drawShape(canvas, rect.deflate(width / 2), layer, paint);
      return;
    }

    final paint = Paint()
      ..color = color
      ..blendMode = blendMode
      ..style = PaintingStyle.fill;
    _drawShape(canvas, rect, layer, paint);

    if (material == UIModuleMaterial.glass) {
      final stroke = Paint()
        ..color = Colors.white.withValues(alpha: 0.38)
        ..blendMode = BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      _drawShape(canvas, rect.deflate(0.5), layer, stroke);
    }
  }

  UIModuleMaterial _readMaterial(dynamic raw) {
    if (raw is int && raw >= 0 && raw < UIModuleMaterial.values.length) {
      return UIModuleMaterial.values[raw];
    }
    if (raw is num) {
      final index = raw.toInt();
      if (index >= 0 && index < UIModuleMaterial.values.length) {
        return UIModuleMaterial.values[index];
      }
    }
    return UIModuleMaterial.solid;
  }

  BlendMode _defaultBlendModeForKind(String kind) {
    switch (kind) {
      case 'glow':
        return BlendMode.plus;
      case 'highlight':
        return BlendMode.screen;
      default:
        return BlendMode.srcOver;
    }
  }

  BlendMode _readBlendMode(String? raw, {BlendMode fallback = BlendMode.srcOver}) {
    switch (raw) {
      case 'multiply':
        return BlendMode.multiply;
      case 'screen':
        return BlendMode.screen;
      case 'overlay':
        return BlendMode.overlay;
      case 'plus':
      case 'add':
        return BlendMode.plus;
      case 'darken':
        return BlendMode.darken;
      case 'lighten':
        return BlendMode.lighten;
      case 'softLight':
      case 'soft_light':
        return BlendMode.softLight;
      case 'normal':
      case 'srcOver':
        return BlendMode.srcOver;
      default:
        return fallback;
    }
  }

  void _drawShape(Canvas canvas, Rect rect, UIPrimitiveLayer layer, Paint paint) {
    switch (layer.shape) {
      case UIModuleShape.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case UIModuleShape.circle:
        canvas.drawOval(rect, paint);
        break;
      case UIModuleShape.capsule:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
          paint,
        );
        break;
      case UIModuleShape.rounded:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(layer.borderRadius)),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant UIPrimitiveArtPainter oldDelegate) {
    return oldDelegate.properties != properties;
  }
}
