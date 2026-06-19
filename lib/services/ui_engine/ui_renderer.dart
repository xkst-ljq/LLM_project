import 'dart:ui';

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
          children: composite.children.map((e) => render(context, e)).toList(),
        );
        break;
      default:
        content = Text('未知布局: ${composite.layoutType}');
    }

    return _buildGlassContainer(composite, content);
  }

  static Widget _buildGlassContainer(dynamic container, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(container.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: container.color.withValues(alpha: container.opacity * 0.3),
            borderRadius: BorderRadius.circular(container.borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.2),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ),
    );
  }

  static Widget _buildProgressBar(UIModule module) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.name,
            style: TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 6,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: 0.6,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: module.color,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: module.color.withValues(alpha: 0.5),
                        blurRadius: 4,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildButton(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(module.borderRadius),
          boxShadow: [
            BoxShadow(
              color: module.color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: module.color,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(module.borderRadius),
            ),
          ),
          onPressed: () {
            debugPrint('Triggered: ${module.id}');
          },
          child: Text(
            module.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ),
    );
  }

  static Widget _buildTextBlock(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        module.properties['text'] ?? module.name,
        style: TextStyle(
          color: module.color,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  static Widget _buildInputBlock(UIModule module) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        style: TextStyle(color: module.color, fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          labelText: module.name,
          labelStyle: TextStyle(color: module.color.withValues(alpha: 0.7), fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(module.borderRadius),
            borderSide: BorderSide(color: module.color.withValues(alpha: 0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(module.borderRadius),
            borderSide: BorderSide(color: module.color.withValues(alpha: 0.2)),
          ),
        ),
      ),
    );
  }
}
