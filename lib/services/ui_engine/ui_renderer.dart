import 'dart:ui';

import 'package:flutter/material.dart';

import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    if (element.isComposite && element.composite != null) {
      return _renderComposite(context, element.composite!);
    } else if (!element.isComposite && element.module != null) {
      return _renderModule(context, element.module!);
    }
    return const SizedBox();
  }

  static Widget _renderModule(BuildContext context, UIModule module) {
    Widget content;
    switch (module.type) {
      case 'progress':
        content = _buildProgressBar(module);
        break;
      case 'button':
        content = _buildButton(module);
        break;
      case 'text':
        content = _buildTextBlock(module);
        break;
      case 'input':
        content = _buildInputBlock(module);
        break;
      default:
        content = Center(child: Text('未知控件: ${module.type}', style: const TextStyle(color: Colors.white)));
    }

    // 封装外层材质与形状
    return _applyMaterialAndShape(module.material, module.shape, module.color, module.opacity, module.borderRadius, content);
  }

  static Widget _renderComposite(BuildContext context, UIComposite composite) {
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
      default:
        content = Text('未知布局: ${composite.layoutType}', style: const TextStyle(color: Colors.white));
    }

    return _applyMaterialAndShape(composite.material, UIModuleShape.rounded, composite.color, composite.opacity, composite.borderRadius, content);
  }

  // 核心：统一应用材质与外框形状
  static Widget _applyMaterialAndShape(
    UIModuleMaterial material,
    UIModuleShape shape,
    Color color,
    double opacity,
    double rawRadius,
    Widget child,
  ) {
    // 1. 根据 Shape 计算具体的 BorderRadius
    BorderRadius radius;
    switch (shape) {
      case UIModuleShape.rectangle:
        radius = BorderRadius.zero;
        break;
      case UIModuleShape.capsule:
        radius = BorderRadius.circular(9999.0);
        break;
      case UIModuleShape.circle:
        radius = BorderRadius.circular(9999.0);
        break;
      case UIModuleShape.rounded:
      default:
        radius = BorderRadius.circular(rawRadius);
        break;
    }

    // 2. 根据 Material 构建具体的 Decoration 与 背景特效
    BoxDecoration decoration;
    switch (material) {
      case UIModuleMaterial.solid:
        decoration = BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: radius,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3 * opacity), blurRadius: 10, offset: const Offset(0, 4))],
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
              color.withValues(alpha: opacity * 0.4),
            ],
          ),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4 * opacity), blurRadius: 12, offset: const Offset(0, 4))],
        );
        break;
      case UIModuleMaterial.outline:
        decoration = BoxDecoration(
          color: color.withValues(alpha: 0.05 * opacity),
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: opacity), width: 2.0),
        );
        break;
      case UIModuleMaterial.glass:
      default:
        decoration = BoxDecoration(
          color: color.withValues(alpha: opacity * 0.25),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.0),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.2),
              Colors.white.withValues(alpha: 0.05),
            ],
          ),
        );
        break;
    }

    Widget container = Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: child,
    );

    // 如果是 Glass 材质，额外包裹 BackdropFilter 真正实现物理毛玻璃模糊
    if (material == UIModuleMaterial.glass) {
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: container,
        ),
      );
    }

    return container;
  }

  static Widget _buildProgressBar(UIModule module) {
    final double maxVal = (module.properties['max'] ?? 100.0).toDouble();
    final double curVal = (module.properties['current'] ?? maxVal).toDouble();
    final double ratio = maxVal > 0 ? (curVal / maxVal).clamp(0.0, 1.0) : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              module.name,
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Text(
              '${curVal.toInt()}/${maxVal.toInt()}',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8), fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              height: 8,
              width: 150,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: module.color,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: module.color.withValues(alpha: 0.6), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildButton(UIModule module) {
    final text = module.properties['text']?.toString() ?? module.name;
    // 按钮自身内容保持简洁，外层已有装饰
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
        ),
      ],
    );
  }

  static Widget _buildTextBlock(UIModule module) {
    final text = module.properties['text']?.toString() ?? module.name;
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      textAlign: TextAlign.center,
    );
  }

  static Widget _buildInputBlock(UIModule module) {
    final label = module.properties['label']?.toString() ?? module.name;
    return SizedBox(
      width: 180,
      child: TextField(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.black12,
          hintText: label,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
