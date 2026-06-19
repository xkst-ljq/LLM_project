import 'package:flutter/material.dart';

/// UI 模块的材质类型
enum UIModuleMaterial {
  glass,      // 毛玻璃
  solid,      // 纯色
  gradient,   // 渐变
  outline     // 描边
}

/// UI 模块的形状类型
enum UIModuleShape {
  rectangle,  // 矩形
  rounded,    // 圆角矩形
  capsule,    // 胶囊形
  circle      // 圆形
}

/// UI 模组-原子定义
class UIModule {
  final String id;
  final String name;
  final String type; // 'slider', 'button', 'text', 'progress', 'input' 等
  final UIModuleMaterial material;
  final UIModuleShape shape;
  final Color color;
  final double opacity;
  final double borderRadius;
  final Map<String, dynamic> properties; // 存储特定组件的属性 (如: min, max, defaultText)
  final String? boundVariable; // 绑定到 SessionState 的变量名 (如: 'var.hp')

  UIModule({
    required this.id,
    required this.name,
    required this.type,
    this.material = UIModuleMaterial.glass,
    this.shape = UIModuleShape.rounded,
    this.color = Colors.white,
    this.opacity = 1.0,
    this.borderRadius = 12.0,
    required this.properties,
    this.boundVariable,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'material': material.index,
    'shape': shape.index,
    'color': color.toARGB32(),
    'opacity': opacity,
    'borderRadius': borderRadius,
    'properties': properties,
    'boundVariable': boundVariable,
  };

  factory UIModule.fromJson(Map<String, dynamic> json) => UIModule(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    material: UIModuleMaterial.values[json['material'] ?? 0],
    shape: UIModuleShape.values[json['shape'] ?? 1],
    color: Color(json['color'] ?? Colors.white.toARGB32()),
    opacity: (json['opacity'] ?? 1.0).toDouble(),
    borderRadius: (json['borderRadius'] ?? 12.0).toDouble(),
    properties: Map<String, dynamic>.from(json['properties'] ?? {}),
    boundVariable: json['boundVariable'],
  );

  UIModule copyWith({
    String? name,
    UIModuleMaterial? material,
    UIModuleShape? shape,
    Color? color,
    double? opacity,
    double? borderRadius,
    Map<String, dynamic>? properties,
    String? boundVariable,
  }) {
    return UIModule(
      id: id,
      name: name ?? this.name,
      type: type,
      material: material ?? this.material,
      shape: shape ?? this.shape,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      borderRadius: borderRadius ?? this.borderRadius,
      properties: properties ?? this.properties,
      boundVariable: boundVariable ?? this.boundVariable,
    );
  }
}

/// UI 组合块定义 (Composite)
class UIComposite {
  final String id;
  final String name;
  final String layoutType; // 'column', 'row', 'stack', 'wrap'
  final List<UIElement> children;
  final UIModuleMaterial material;
  final double borderRadius;
  final Color color;
  final double opacity;

  UIComposite({
    required this.id,
    required this.name,
    required this.layoutType,
    required this.children,
    this.material = UIModuleMaterial.glass,
    this.borderRadius = 16.0,
    this.color = Colors.white,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layoutType': layoutType,
    'children': children.map((e) => e.toJson()).toList(),
    'material': material.index,
    'borderRadius': borderRadius,
    'color': color.toARGB32(),
    'opacity': opacity,
  };

  factory UIComposite.fromJson(Map<String, dynamic> json) => UIComposite(
    id: json['id'],
    name: json['name'],
    layoutType: json['layoutType'],
    children: (json['children'] as List).map((e) => UIElement.fromJson(e)).toList(),
    material: UIModuleMaterial.values[json['material'] ?? 0],
    borderRadius: (json['borderRadius'] ?? 16.0).toDouble(),
    color: Color(json['color'] ?? Colors.white.toARGB32()),
    opacity: (json['opacity'] ?? 1.0).toDouble(),
  );
}

/// UI 元素统一封装 (可以是单个模组，也可以是组合块)
class UIElement {
  final String id;
  final bool isComposite;
  final UIModule? module;
  final UIComposite? composite;

  UIElement({
    required this.id,
    required this.isComposite,
    this.module,
    this.composite,
  });

  // 方便在 JSON 中统一表示
  Map<String, dynamic> toJson() {
    if (isComposite) {
      return {
        'id': id,
        'isComposite': true,
        'composite': composite?.toJson(),
      };
    } else {
      return {
        'id': id,
        'isComposite': false,
        'module': module?.toJson(),
      };
    }
  }

  factory UIElement.fromJson(Map<String, dynamic> json) {
    final isComposite = json['isComposite'] ?? false;
    if (isComposite) {
      return UIElement(
        id: json['id'],
        isComposite: true,
        composite: UIComposite.fromJson(json['composite']),
      );
    } else {
      return UIElement(
        id: json['id'],
        isComposite: false,
        module: UIModule.fromJson(json['module']),
      );
    }
  }
}
