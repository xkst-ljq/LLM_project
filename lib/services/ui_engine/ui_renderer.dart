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
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
