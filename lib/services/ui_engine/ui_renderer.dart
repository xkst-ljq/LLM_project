import 'package:flutter/material.dart';

import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    if (element.isComposite) {
      return _renderComposite(context, element.composite!);
    } else {
      return _renderModule(context, element.module!);
    }
  }

  static Widget _renderModule(BuildContext context, UIModule module) {
    // 根据 type 分发渲染不同的原子组件
    switch (module.type) {
      case 'progress':
        return _buildProgressBar(module);
      case 'button':
        return _buildButton(module);
      case 'text':
        return _buildTextBlock(module);
      case 'input':
        return _buildInputBlock(module);
      default:
        return Center(child: Text('未知组件: ${module.type}'));
    }
  }

  static Widget _renderComposite(BuildContext context, UIComposite composite) {
    Widget content;
    
    // 根据 layoutType 决定布局
    switch (composite.layoutType) {
      case 'column':
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'row':
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'stack':
        content = Stack(
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      case 'wrap':
        content = Wrap(
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      default:
        content = Text('未知布局: ${composite.layoutType}');
    }

    // 包裹在材质容器中
    return _buildGlassContainer(composite, content);
  }

  static Widget _buildGlassContainer(dynamic container, Widget child) {
    // 这里实现你想要的毛玻璃、圆角、颜色等效果
    return Container(
      decoration: BoxDecoration(
        color: container.color.withOpacity(container.opacity),
        borderRadius: BorderRadius.circular(container.borderRadius),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(container.borderRadius),
        child: child,
      ),
    );
  }

  // --- 原子组件实现 (暂定基础样式) ---

  static Widget _buildProgressBar(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(module.name, style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: 0.5, // 暂时硬编码，后续接变量绑定
            backgroundColor: Colors.grey[300],
            color: module.color,
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  static Widget _buildButton(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: module.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(module.borderRadius)),
        ),
        onPressed: () {
          debugPrint('Triggered: ${module.id}');
        },
        child: Text(module.name),
      ),
    );
  }

  static Widget _buildTextBlock(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        module.properties['text'] ?? module.name,
        style: TextStyle(color: module.color, fontSize: 14),
      ),
    );
  }

  static Widget _buildInputBlock(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: module.name,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(module.borderRadius)),
        ),
      ),
    );
  }
}
