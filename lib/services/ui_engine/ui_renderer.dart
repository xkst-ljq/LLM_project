import 'dart:ui';

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
      case 'base_box':
        content = _buildBaseBox();
        break;
      default:
        content = Center(child: Text('未知控件: ${module.type}', style: const TextStyle(color: Color(0xFF111116), fontSize: 12)));
    }

    return _applyMaterialAndShape(
      module.material,
      module.shape,
      module.color,
      module.opacity,
      module.borderRadius,
      content,
      size,
    );
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
        content = Stack(
          children: [
            if (composite.children.isEmpty)
              const Positioned.fill(
                child: Center(
                  child: Text(
                    '📦 复合组块基本边界框\n(将原子组件拖入组合)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF888896), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ...composite.children.map((e) => render(context, e)),
          ],
        );
        break;
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
      case UIModuleShape.circle:
        radius = BorderRadius.circular(9999.0);
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
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: container,
        ),
      );
    }

    return container;
  }

  static Widget _buildBaseBox() {
    return const Center(
      child: Text('📦 基本边界框容器\n(多重组块的基础)', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF00ACC1), fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  static Widget _buildProgressBar(UIModule module) {
    final double maxVal = (module.properties['max'] ?? 100.0).toDouble();
    final double curVal = (module.properties['current'] ?? 80.0).toDouble();
    final double ratio = maxVal > 0 ? (curVal / maxVal).clamp(0.0, 1.0) : 1.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                module.name,
                style: const TextStyle(fontSize: 12, color: Color(0xFF111116), fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${curVal.toInt()}/${maxVal.toInt()}',
              style: TextStyle(fontSize: 11, color: const Color(0xFF555562), fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E2E8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: ratio,
            child: Container(
              decoration: BoxDecoration(
                color: module.color == Colors.white ? const Color(0xFFFF4081) : module.color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: (module.color == Colors.white ? const Color(0xFFFF4081) : module.color).withValues(alpha: 0.4), blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _buildButton(UIModule module) {
    final text = module.properties['text']?.toString() ?? module.name;
    return Container(
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(color: module.color == Colors.white ? const Color(0xFF111116) : Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static Widget _buildTextBlock(UIModule module) {
    final text = module.properties['text']?.toString() ?? module.name;
    return Container(
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(color: module.color == Colors.white ? const Color(0xFF111116) : module.color, fontSize: 14, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static Widget _buildInputBlock(UIModule module) {
    final label = module.properties['label']?.toString() ?? module.name;
    return Container(
      alignment: Alignment.center,
      child: TextField(
        style: const TextStyle(color: Color(0xFF111116), fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFEBEBF1),
          hintText: label,
          hintStyle: const TextStyle(color: Color(0xFF888896), fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
