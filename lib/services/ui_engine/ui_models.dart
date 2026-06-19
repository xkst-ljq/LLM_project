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

/// UI 场景的运行时接管/渲染模式
enum UISceneRenderingMode {
  modalArchive, // 开屏全屏档案模式 (保存后销毁)
  appTakeover,  // 完全接管/软件模式 (替代普通聊天框)
  inlineHybrid  // 传统气泡共存模式
}

/// UI 模组-原子定义
class UIModule {
  final String id;
  final String name;
  final String type; // 'slider', 'button', 'text', 'progress', 'input', 'base_box' 等
  final UIModuleMaterial material;
  final UIModuleShape shape;
  final Color color;
  final double opacity;
  final double borderRadius;
  final Map<String, dynamic> properties; // 存储特定组件的属性
  final String? boundVariable; // 绑定到 SessionState 的变量名 (主动驱动 Prompt)
  final String? statusFieldMirrorKey; // 纯镜像映射置顶状态栏的字段名 (只读显示)

  UIModule({
    required this.id,
    required this.name,
    required this.type,
    UIModuleMaterial? material,
    UIModuleShape? shape,
    Color? color,
    double opacity = 1.0,
    double borderRadius = 12.0,
    required this.properties,
    this.boundVariable,
    this.statusFieldMirrorKey,
  })  : material = material ?? UIModuleMaterial.glass,
        shape = shape ?? UIModuleShape.rounded,
        color = color ?? Colors.white,
        this.opacity = opacity,
        this.borderRadius = borderRadius;

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
    'statusFieldMirrorKey': statusFieldMirrorKey,
  };

  factory UIModule.fromJson(Map<String, dynamic> json) => UIModule(
    id: json['id'] ?? 'unknown_id',
    name: json['name'] ?? '未命名组件',
    type: json['type'] ?? 'text',
    material: UIModuleMaterial.values[json['material'] ?? 0],
    shape: UIModuleShape.values[json['shape'] ?? 1],
    color: Color(json['color'] ?? Colors.white.toARGB32()),
    opacity: (json['opacity'] ?? 1.0).toDouble(),
    borderRadius: (json['borderRadius'] ?? 12.0).toDouble(),
    properties: Map<String, dynamic>.from(json['properties'] ?? {}),
    boundVariable: json['boundVariable'],
    statusFieldMirrorKey: json['statusFieldMirrorKey'],
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
    String? statusFieldMirrorKey,
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
      statusFieldMirrorKey: statusFieldMirrorKey ?? this.statusFieldMirrorKey,
    );
  }
}

/// UI 组合块定义 (Composite / 多重组件容器)
class UIComposite {
  final String id;
  final String name;
  final String layoutType; // 'column', 'row', 'stack', 'wrap', 'base_box'
  final List<UIElement> children;
  final UIModuleMaterial material;
  final double borderRadius;
  final Color color;
  final double opacity;
  final UISceneRenderingMode renderingMode; // 多形态场景模式

  UIComposite({
    required this.id,
    required this.name,
    required this.layoutType,
    required this.children,
    UIModuleMaterial? material,
    double borderRadius = 16.0,
    Color? color,
    double opacity = 1.0,
    UISceneRenderingMode? renderingMode,
  })  : material = material ?? UIModuleMaterial.glass,
        color = color ?? Colors.white,
        this.borderRadius = borderRadius,
        this.opacity = opacity,
        renderingMode = renderingMode ?? UISceneRenderingMode.inlineHybrid;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layoutType': layoutType,
    'children': children.map((e) => e.toJson()).toList(),
    'material': material.index,
    'borderRadius': borderRadius,
    'color': color.toARGB32(),
    'opacity': opacity,
    'renderingMode': renderingMode.index,
  };

  factory UIComposite.fromJson(Map<String, dynamic> json) => UIComposite(
    id: json['id'] ?? 'unknown_comp',
    name: json['name'] ?? '未命名组合块',
    layoutType: json['layoutType'] ?? 'column',
    children: (json['children'] as List?)?.map((e) => UIElement.fromJson(e)).toList() ?? [],
    material: UIModuleMaterial.values[json['material'] ?? 0],
    borderRadius: (json['borderRadius'] ?? 16.0).toDouble(),
    color: Color(json['color'] ?? Colors.white.toARGB32()),
    opacity: (json['opacity'] ?? 1.0).toDouble(),
    renderingMode: UISceneRenderingMode.values[json['renderingMode'] ?? 2],
  );

  UIComposite copyWith({
    String? name,
    String? layoutType,
    List<UIElement>? children,
    UIModuleMaterial? material,
    double? borderRadius,
    Color? color,
    double? opacity,
    UISceneRenderingMode? renderingMode,
  }) {
    return UIComposite(
      id: id,
      name: name ?? this.name,
      layoutType: layoutType ?? this.layoutType,
      children: children ?? this.children,
      material: material ?? this.material,
      borderRadius: borderRadius ?? this.borderRadius,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      renderingMode: renderingMode ?? this.renderingMode,
    );
  }
}

/// UI 元素统一封装 (承载在画布上的真实几何实例)
class UIElement {
  final String id;
  final bool isComposite;
  final UIModule? module;
  final UIComposite? composite;
  
  final Offset offset;
  final Size size;

  UIElement({
    required this.id,
    required this.isComposite,
    this.module,
    this.composite,
    this.offset = Offset.zero,
    this.size = const Size(100, 100),
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'isComposite': isComposite,
      'offset': {'x': offset.dx, 'y': offset.dy},
      'size': {'width': size.width, 'height': size.height},
    };
    if (isComposite) {
      map['composite'] = composite?.toJson();
    } else {
      map['module'] = module?.toJson();
    }
    return map;
  }

  factory UIElement.fromJson(Map<String, dynamic> json) {
    final isComposite = json['isComposite'] ?? false;
    final offsetData = json['offset'] as Map<String, dynamic>? ?? {};
    final sizeData = json['size'] as Map<String, dynamic>? ?? {};
    
    return UIElement(
      id: json['id'] ?? 'el_${DateTime.now().millisecondsSinceEpoch}',
      isComposite: isComposite,
      offset: Offset(
        (offsetData['x'] ?? 0).toDouble(),
        (offsetData['y'] ?? 0).toDouble(),
      ),
      size: Size(
        (sizeData['width'] ?? 100.0).toDouble(),
        (sizeData['height'] ?? 100.0).toDouble(),
      ),
      composite: (isComposite && json['composite'] != null) ? UIComposite.fromJson(json['composite']) : null,
      module: (!isComposite && json['module'] != null) ? UIModule.fromJson(json['module']) : null,
    );
  }

  UIElement copyWith({
    bool? isComposite,
    UIModule? module,
    UIComposite? composite,
    Offset? offset,
    Size? size,
  }) {
    return UIElement(
      id: id,
      isComposite: isComposite ?? this.isComposite,
      module: module ?? this.module,
      composite: composite ?? this.composite,
      offset: offset ?? this.offset,
      size: size ?? this.size,
    );
  }
}
