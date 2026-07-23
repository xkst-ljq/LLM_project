import 'package:flutter/material.dart';

class UISceneModeScope extends InheritedWidget {
  final bool isStudioCreationMode;
  final String? selectedElementId;
  const UISceneModeScope({super.key, required this.isStudioCreationMode, this.selectedElementId, required super.child});

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UISceneModeScope>()?.isStudioCreationMode ?? false;
  }

  static String? selectedIdOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UISceneModeScope>()?.selectedElementId;
  }

  @override
  bool updateShouldNotify(UISceneModeScope old) => old.isStudioCreationMode != isStudioCreationMode || old.selectedElementId != selectedElementId;
}

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
  circle,     // 圆形
  heart,      // 心形
  star5,      // 五角星
  star4       // 四角星
}

/// UI 场景的运行时接管/渲染模式
enum UISceneRenderingMode {
  modalArchive, // 开屏全屏档案模式 (保存后销毁)
  appTakeover,  // 完全接管/软件模式 (替代普通聊天框)
  inlineHybrid  // 传统气泡共存模式
}

/// UI 独立图层定义 (支持动态新建无尽图层，默认只有一层)
class LayerScene {
  final int id;
  final String name;

  LayerScene({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory LayerScene.fromJson(Map<String, dynamic> json) =>
      LayerScene(id: json['id'] ?? 0, name: json['name'] ?? '图层 Level 0');
}

/// 基础工作台内部使用的“原材料构造层”。
///
/// 它不是复合组件里的运行时子元素，而是用于制造一个新基础模组的
/// 工艺层：多个 PrimitiveLayer 最终会被烘焙/保存进一个 UIModule 的
/// properties['layers'] 中，对外仍然表现为单个基础模组。
class UIPrimitiveLayer {
  final String id;
  final String kind; // surface, oval, stroke, glow, highlight, line, mask...
  final Offset offset; // 归一化坐标：0~1
  final Size size; // 归一化尺寸：0~1
  final Color color;
  final double opacity;
  final UIModuleShape shape;
  final double borderRadius;
  final Map<String, dynamic> properties;

  UIPrimitiveLayer({
    required this.id,
    required this.kind,
    this.offset = Offset.zero,
    this.size = const Size(1, 1),
    Color? color,
    this.opacity = 1.0,
    UIModuleShape? shape,
    this.borderRadius = 12.0,
    Map<String, dynamic>? properties,
  })  : color = color ?? Colors.white,
        shape = shape ?? UIModuleShape.rounded,
        properties = properties ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'offset': {'x': offset.dx, 'y': offset.dy},
    'size': {'width': size.width, 'height': size.height},
    'color': color.toARGB32(),
    'opacity': opacity,
    'shape': shape.index,
    'borderRadius': borderRadius,
    'properties': properties,
  };

  factory UIPrimitiveLayer.fromJson(Map<String, dynamic> json) {
    final offsetData = json['offset'] as Map<String, dynamic>? ?? {};
    final sizeData = json['size'] as Map<String, dynamic>? ?? {};
    return UIPrimitiveLayer(
      id: json['id']?.toString() ?? 'layer_${DateTime.now().millisecondsSinceEpoch}',
      kind: json['kind']?.toString() ?? 'surface',
      offset: Offset(
        (offsetData['x'] ?? 0).toDouble(),
        (offsetData['y'] ?? 0).toDouble(),
      ),
      size: Size(
        (sizeData['width'] ?? 1).toDouble(),
        (sizeData['height'] ?? 1).toDouble(),
      ),
      color: Color(json['color'] ?? Colors.white.toARGB32()),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      shape: UIModuleShape.values[json['shape'] ?? UIModuleShape.rounded.index],
      borderRadius: (json['borderRadius'] ?? 12.0).toDouble(),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
    );
  }
}

/// UI 模组-原子定义
class UIModule {
  final String id;
  final String name;
  final String type; // 'slider', 'button', 'text', 'progress', 'input', 'base_box', 'linker' 等
  //
  // === Linker（联动器）端口元数据建议结构（放在 properties['linker'] 中）===
// {
//   "linker": {
//     "sourceModuleId": "el_xxx",      // 源模块（progress）
//     "sourcePort": "current",
//     "sourceType": "number",
//     "targetModuleId": "el_yyy",      // 目标模块（text）
//     "targetPort": "text",
//     "targetType": "string",
//     "scheme": "progress_to_text",
//     "enabled": true,
//
//     // === 新增：中转连线结构 ===
//     "inputConnection": {
//       "from": "el_xxx",              // sourceModuleId
//       "fromPort": "current",
//       "to": "linker自身ID",
//       "toPort": "input"
//     },
//     "outputConnection": {
//       "from": "linker自身ID",
//       "fromPort": "output",
//       "to": "el_yyy",                // targetModuleId
//       "toPort": "text"
//     }
//   }
// }
  // 这是最高效且易扩展的扁平结构，后续可轻松增加 filter / transform 等字段。
  final UIModuleMaterial material;
  final UIModuleShape shape;
  final Color color;
  final double opacity;
  final double borderRadius;
  final Map<String, dynamic> properties; // 存储特定组件的属性
  final String? boundVariable; // 绑定到 SessionState 的变量名 (主动驱动 Prompt)
  final String? statusFieldMirrorKey; // 纯镜像映射置顶状态栏的字段名 (只读显示)
  final String? displayExpression; // 联动显示表达式 e.g. "{{current}} / {{max}} HP" 或 "{{progress.current}}"
  final List<String> linkedSources; // 联动源ID列表 (同组件内scope)

  UIModule({
    required this.id,
    required this.name,
    required this.type,
    UIModuleMaterial? material,
    UIModuleShape? shape,
    Color? color,
    this.opacity = 1.0,
    this.borderRadius = 12.0,
    required this.properties,
    this.boundVariable,
    this.statusFieldMirrorKey,
    this.displayExpression,
    List<String>? linkedSources,
  })  : material = material ?? UIModuleMaterial.glass,
        shape = shape ?? UIModuleShape.rounded,
        color = color ?? Colors.white,
        linkedSources = linkedSources ?? const [];

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
    'displayExpression': displayExpression,
    'linkedSources': linkedSources,
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
    displayExpression: json['displayExpression'],
    linkedSources: (json['linkedSources'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  UIModule copyWith({
    String? id,
    String? name,
    UIModuleMaterial? material,
    UIModuleShape? shape,
    Color? color,
    double? opacity,
    double? borderRadius,
    Map<String, dynamic>? properties,
    String? boundVariable,
    String? statusFieldMirrorKey,
    String? displayExpression,
    List<String>? linkedSources,
  }) {
    return UIModule(
      id: id ?? this.id,
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
      displayExpression: displayExpression ?? this.displayExpression,
      linkedSources: linkedSources ?? this.linkedSources,
    );
  }
}

/// 复合组件暴露端口定义（从 Studio 到 Assembly 页的接口契约）
class ExposedPort {
  final String elementId; // 内部子元素 ID
  final bool exposeInput; // 左侧边轨：接收端口
  final bool exposeOutput; // 右侧边轨：输出端口
  final int? customColor; // 自定义端口颜色，null 时使用类型默认色

  const ExposedPort({
    required this.elementId,
    this.exposeInput = true,
    this.exposeOutput = true,
    this.customColor,
  });

  Map<String, dynamic> toJson() => {
    'elementId': elementId,
    'exposeInput': exposeInput,
    'exposeOutput': exposeOutput,
    if (customColor != null) 'customColor': customColor,
  };

  factory ExposedPort.fromJson(Map<String, dynamic> json) => ExposedPort(
    elementId: json['elementId']?.toString() ?? '',
    exposeInput: json['exposeInput'] != false,
    exposeOutput: json['exposeOutput'] != false,
    customColor: json['customColor'] as int?,
  );

  ExposedPort copyWith({String? elementId, bool? exposeInput, bool? exposeOutput, int? customColor}) => ExposedPort(
    elementId: elementId ?? this.elementId,
    exposeInput: exposeInput ?? this.exposeInput,
    exposeOutput: exposeOutput ?? this.exposeOutput,
    customColor: customColor ?? this.customColor,
  );
}

/// UI 组合块定义 (Composite / 多重组件容器)
class UIComposite {
  final String id;
  final String name;
  final String layoutType;
  final List<UIElement> children;
  final UIModuleMaterial material;
  final double borderRadius;
  final Color color;
  final double opacity;
  final UISceneRenderingMode renderingMode;
  final List<ExposedPort>? exposedPorts;

  UIComposite({
    required this.id,
    required this.name,
    required this.layoutType,
    required this.children,
    UIModuleMaterial? material,
    this.borderRadius = 16.0,
    Color? color,
    this.opacity = 1.0,
    UISceneRenderingMode? renderingMode,
    this.exposedPorts,
  })  : material = material ?? UIModuleMaterial.glass,
        color = color ?? Colors.white,
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
    if (exposedPorts != null && exposedPorts!.isNotEmpty)
      'exposedPorts': exposedPorts!.map((p) => p.toJson()).toList(),
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
    exposedPorts: (json['exposedPorts'] as List?)
        ?.map((e) => ExposedPort.fromJson(e as Map<String, dynamic>))
        .toList(),
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
    List<ExposedPort>? exposedPorts,
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
      exposedPorts: exposedPorts ?? this.exposedPorts,
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
  final int layerIndex; // 动态所属的图层 ID
  final String? parentSurfaceId; // 显式所属面；为空表示顶层元素
  final double rotation; // 旋转角度（度），围绕元素自身中心
  final bool layoutLocked; // 编辑器布局锁：禁止移动 / 缩放 / 旋转
  final bool sealed; // 编辑器完全锁：禁止几何与 Linker 编辑，且命中穿透

  UIElement({
    required this.id,
    required this.isComposite,
    this.module,
    this.composite,
    this.offset = Offset.zero,
    this.size = const Size(100, 100),
    this.layerIndex = 0,
    this.parentSurfaceId,
    this.rotation = 0.0,
    this.layoutLocked = false,
    this.sealed = false,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'isComposite': isComposite,
      'offset': {'x': offset.dx, 'y': offset.dy},
      'size': {'width': size.width, 'height': size.height},
      'layerIndex': layerIndex,
      'parentSurfaceId': parentSurfaceId,
      'rotation': rotation,
      'layoutLocked': layoutLocked,
      'sealed': sealed,
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
    final String elemId = json['id'] ?? 'el_${DateTime.now().millisecondsSinceEpoch}';

    UIModule? parsedModule;
    if (!isComposite && json['module'] != null) {
      final m = UIModule.fromJson(json['module']);
      if (m.id.startsWith('atom_') || m.id != elemId) {
        parsedModule = m.copyWith(id: elemId);
      } else {
        parsedModule = m;
      }
    }

    return UIElement(
      id: elemId,
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
      module: parsedModule,
      layerIndex: json['layerIndex'] ?? 0,
      parentSurfaceId: json['parentSurfaceId']?.toString(),
      rotation: (json['rotation'] ?? 0.0).toDouble(),
      layoutLocked: json['layoutLocked'] == true,
      sealed: json['sealed'] == true,
    );
  }

  UIElement copyWith({
    bool? isComposite,
    UIModule? module,
    UIComposite? composite,
    Offset? offset,
    Size? size,
    int? layerIndex,
    String? parentSurfaceId,
    bool clearParentSurface = false,
    double? rotation,
    bool? layoutLocked,
    bool? sealed,
  }) {
    return UIElement(
      id: id,
      isComposite: isComposite ?? this.isComposite,
      module: module ?? this.module,
      composite: composite ?? this.composite,
      offset: offset ?? this.offset,
      size: size ?? this.size,
      layerIndex: layerIndex ?? this.layerIndex,
      parentSurfaceId: clearParentSurface
          ? null
          : parentSurfaceId ?? this.parentSurfaceId,
      rotation: rotation ?? this.rotation,
      layoutLocked: layoutLocked ?? this.layoutLocked,
      sealed: sealed ?? this.sealed,
    );
  }
}
