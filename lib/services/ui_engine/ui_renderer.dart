import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'linker_service.dart';
import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    Widget widget;
    if (element.isComposite && element.composite != null) {
      widget = _renderComposite(context, element.composite!, element.size);
    } else if (!element.isComposite && element.module != null) {
      widget = _renderModule(context, element.module!, element.size);
    } else {
      widget = const SizedBox();
    }
    // 围绕元素自身中心旋转。工作室拖拽与运行时聊天渲染共用此入口，
    // 因此两处表现一致；rotation == 0 时不套 Transform，零开销。
    if (element.rotation != 0.0) {
      return Transform.rotate(
        angle: element.rotation * math.pi / 180.0,
        child: widget,
      );
    }
    return widget;
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
      case 'linker':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildLinkerNode(module, size),
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
    // 复合组件渲染其子元素（当前简化实现：stack 布局）
    final children = <Widget>[];
    for (final child in composite.children) {
      final childWidget = render(context, child);
      children.add(
        Positioned(
          left: child.offset.dx,
          top: child.offset.dy,
          width: child.size.width,
          height: child.size.height,
          child: childWidget,
        ),
      );
    }

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: children,
      ),
    );
  }

  static Widget _applyMaterialAndShape(
    UIModuleMaterial material,
    UIModuleShape shape,
    Color color,
    double opacity,
    double borderRadius,
    Widget child,
    Size size,
  ) {
    Widget content = child;

    switch (material) {
      case UIModuleMaterial.glass:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity * 0.25),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.solid:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.gradient:
        content = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: opacity), color.withValues(alpha: opacity * 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.outline:
        content = Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: opacity), width: 2),
          ),
          child: child,
        );
        break;
    }

    // 形状裁剪
    switch (shape) {
      case UIModuleShape.circle:
        return ClipOval(child: content);
      case UIModuleShape.capsule:
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: content,
        );
      case UIModuleShape.rounded:
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        );
      case UIModuleShape.rectangle:
        return content;
    }
  }

  static Widget _buildBaseBox() {
    return Container(); // 纯视觉表面，内容由外部决定
  }

  static Widget _buildProgressBar(UIModule module, Size size) {
    final min = (module.properties['min'] ?? 0).toDouble();
    final max = (module.properties['max'] ?? 100).toDouble();
    final current = (module.properties['current'] ?? min).toDouble().clamp(min, max);
    final progress = max > min ? (current - min) / (max - min) : 0.0;

    final fillColor = module.color;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  static Widget _buildSlider(UIModule module) {
    final min = (module.properties['min'] ?? 0).toDouble();
    final max = (module.properties['max'] ?? 100).toDouble();
    final current = (module.properties['current'] ?? min).toDouble().clamp(min, max);

    final fillColor = module.color;
    final h = 32.0;
    final knobSize = 18.0;
    final knobLeft = ((current - min) / (max - min)).clamp(0.0, 1.0) * (100.0 - knobSize) + 5;

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: (h - 5) / 2,
            height: 5,
            child: Container(color: Colors.grey.shade300),
          ),
          Positioned(
            left: 10,
            top: (h - 5) / 2,
            width: knobLeft - 5 + knobSize / 2,
            height: 5,
            child: Container(color: fillColor.withValues(alpha: 0.72)),
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
      ),
    );
  }

  static Widget _buildButton(UIModule module) {
    // 原子按钮只提供透明点击逻辑热区，不自带视觉外观。
    // 视觉按钮 = surface + text/icon + button 逻辑区的复合块。
    return const SizedBox.expand();
  }

  /// 简单显示表达式求值（{{key}} 模板替换）
  /// 当前阶段使用 module.properties 模拟；后续可扩展为跨元素实时订阅。
  static String _evaluateDisplayExpression(UIModule module, [Map<String, dynamic>? extraContext]) {
    final expr = module.displayExpression?.trim() ?? '';
    if (expr.isEmpty) {
      return module.properties['text']?.toString() ?? module.name;
    }

    String result = expr;
    final context = <String, dynamic>{
      ...module.properties,
      if (extraContext != null) ...extraContext,
    };

    // 标准 {{key}} 替换
    context.forEach((key, value) {
      if (value == null) return;
      final pattern = RegExp(r'\{\{\s*' + RegExp.escape(key) + r'\s*\}\}');
      result = result.replaceAllMapped(pattern, (_) => value.toString());
    });

    // 常见进度别名支持：{{current}}、{{max}}、{{progress.current}} 等
    final cur = context['current'] ?? context['progress']?['current'];
    final mx = context['max'] ?? context['progress']?['max'];
    if (cur != null) {
      result = result.replaceAll(RegExp(r'\{\{\s*current\s*\}\}'), cur.toString());
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.current\s*\}\}'), cur.toString());
    }
    if (mx != null) {
      result = result.replaceAll(RegExp(r'\{\{\s*max\s*\}\}'), mx.toString());
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.max\s*\}\}'), mx.toString());
    }

    // 兜底：如果表达式未被替换且有原始 text，则回退
    if (result == expr) {
      final fallback = module.properties['text']?.toString();
      if (fallback != null && fallback.isNotEmpty) {
        result = fallback;
      }
    }

    return result.isEmpty ? module.name : result;
  }

  static Widget _buildTextBlock(UIModule module) {
    // 支持 displayExpression 联动显示
    String displayText = (module.displayExpression != null && module.displayExpression!.trim().isNotEmpty)
        ? _evaluateDisplayExpression(module)
        : (module.properties['text']?.toString() ?? module.name);

    // === Linker MVP 联动支持：如果该 text 被 linker 指向，则尝试显示联动后的值 ===
    // 注意：当前为简单实现，后续会接入真正的 LinkerService
    // 目前仅支持 progress.current → text.text 的场景
    final linkedValue = _resolveLinkerValueForText(module);
    if (linkedValue != null) {
      displayText = linkedValue;
    }

    return Container(
      alignment: Alignment.center,
      child: Text(
        displayText,
        style: TextStyle(color: module.color, fontSize: 14, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Linker MVP：尝试解析当前 text 是否被 linker 指向，并返回联动后的值
  /// 目前仅支持 progress.current → text.text
  static String? _resolveLinkerValueForText(UIModule textModule) {
    // 调用 LinkerService 进行解析
    return LinkerService.resolveLinkedTextValue(textModule);
  }

  static Widget _buildInputBlock(UIModule module) {
    // 原子输入框只提供透明输入逻辑热区，不自带边框、底色或 placeholder。
    // 视觉输入框 = surface + placeholder text + input 逻辑区的复合块。
    return const SizedBox.expand();
  }

  /// 联动器节点渲染（MVP）
  /// 样式：圆角矩形 + 左右端口原点（垂直居中）+ 端口旁标签 + 中间传输方案
  /// 端口已放大并移至中点，方便后续拖拽接线
  static Widget _buildLinkerNode(UIModule module, Size size) {
    final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>() ?? {};
    
    final sourcePort = linkerData['sourcePort']?.toString() ?? '—';
    final targetPort = linkerData['targetPort']?.toString() ?? '—';
    final scheme = linkerData['scheme']?.toString() ?? '未配置';

    final portColor = module.color.withValues(alpha: 0.95);
    final borderColor = module.color.withValues(alpha: 0.35);
    const double portSize = 15.0; // 放大端口，方便接线交互

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 左上角端口标签
          Positioned(
            left: 8,
            top: 6,
            child: Text(
              sourcePort,
              style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
            ),
          ),

          // 左侧端口（垂直居中）
          Positioned(
            left: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 右上角端口标签
          Positioned(
            right: 8,
            top: 6,
            child: Text(
              targetPort,
              style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
            ),
          ),

          // 右侧端口（垂直居中）
          Positioned(
            right: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 中间传输方案
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
              child: Text(
                scheme,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF111116),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // 底部提示
          Positioned(
            bottom: 3,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '联动器',
                style: TextStyle(
                  fontSize: 8,
                  color: module.color.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    final x = layer.offset.dx * canvasSize.width;
    final y = layer.offset.dy * canvasSize.height;
    final w = layer.size.width * canvasSize.width;
    final h = layer.size.height * canvasSize.height;
    return Rect.fromLTWH(x, y, w, h);
  }

  void _paintLayer(Canvas canvas, Size size, UIPrimitiveLayer layer) {
    final rect = _layerRect(size, layer);
    if (rect.width <= 0 || rect.height <= 0) return;

    final paint = Paint()
      ..color = layer.color.withValues(alpha: layer.opacity)
      ..style = PaintingStyle.fill;

    final r = layer.borderRadius;

    switch (layer.shape) {
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
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), paint);
        break;
      case UIModuleShape.rectangle:
        canvas.drawRect(rect, paint);
        break;
    }

    // 额外描边支持
    if (layer.properties['stroke'] == true) {
      final strokePaint = Paint()
        ..color = (layer.properties['strokeColor'] != null
                ? Color(layer.properties['strokeColor'])
                : Colors.black)
            .withValues(alpha: layer.opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (layer.properties['strokeWidth'] ?? 1.5).toDouble();
      switch (layer.shape) {
        case UIModuleShape.circle:
          canvas.drawOval(rect, strokePaint);
          break;
        case UIModuleShape.capsule:
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
            strokePaint,
          );
          break;
        case UIModuleShape.rounded:
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), strokePaint);
          break;
        case UIModuleShape.rectangle:
          canvas.drawRect(rect, strokePaint);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant UIPrimitiveArtPainter oldDelegate) {
    return oldDelegate.properties != properties;
  }
}
