import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/ui_engine/ui_models.dart';

/// 角色卡 UI 组装方案的轻量快照
class UIAssemblyInfo {
  /// 设计坐标系的基准宽度。全屏类 UI 沿用它。
  static const double defaultPcbWidth = 360.0;

  /// PCB 尺寸可调范围。范围放宽，由作者自行决定；
  /// 运行时若超出屏幕会等比缩小，不会溢出。
  static const double minPcbWidth = 120.0;
  static const double maxPcbWidth = 600.0;
  static const double minPcbHeight = 64.0;
  static const double maxPcbHeight = 2000.0;

  /// PCB 圆角半径的默认值与上限。
  ///
  /// 默认 20 与早期布尔 `pcbRounded == true` 的观感保持一致，
  /// 旧卡迁移后外观不变。上限 40 是经验值——PCB 最窄 120，
  /// 再大圆角会把四角啃掉太多可用面积。
  static const double defaultPcbRadius = 20.0;
  static const double kMaxPcbRadius = 40.0;

  /// 伴生 UI 的宽度上限。
  ///
  /// 伴生内嵌在 AI 消息气泡里，宽度不能超出气泡的可显示区域，
  /// 否则运行时只能等比缩小——作者在编辑器里摆好的字号与间距全变样。
  /// 气泡宽度是 `屏宽 * 0.7 - 20`，再扣掉左右各 10 的内边距；
  /// 以设计基准宽 [defaultPcbWidth]（360）折算即 `360 * 0.7 - 40 = 212`。
  static const double companionMaxPcbWidth = 212.0;

  /// 按 mode 给出的宽度上限。
  ///
  /// 只有伴生有额外约束——它必须塞进气泡。
  /// 其余 mode 由作者自行决定，运行时超出屏幕会等比缩小。
  static double maxPcbWidthFor(String mode) =>
      mode == 'extra_companion' ? companionMaxPcbWidth : maxPcbWidth;

  /// 按 mode 给出的默认画布尺寸。
  ///
  /// 常驻 / 伴生这类挂件本来就不该占满屏宽，
  /// 用全屏尺寸起步会让作者一开始就把元件摆错位置。
  static Size defaultPcbSizeFor(String mode) {
    switch (mode) {
      case 'extra_sticky':
        return const Size(300, 120);
      case 'extra_companion':
        // 宽度贴着气泡上限；高度不做多大限制（用户设计），
        // 内容长了由气泡自身撑高，随聊天列表一起滚动。
        return const Size(companionMaxPcbWidth, 200);
      default:
        return const Size(defaultPcbWidth, 800);
    }
  }

  final String id;
  String name;
  String mode; // 'opening', 'scene', 'extra'
  String elementsJson; // 旧版存储字段，保留兼容
  String pagesJson; // 新版多页面结构 JSON
  double pcbWidth;
  double pcbHeight;
  int pcbColorValue;

  /// PCB 圆角半径（0~kMaxPcbRadius）。
  ///
  /// 取代早期的布尔 `pcbRounded`（只能在 20 与 0 之间二选一，
  /// 做不出「微圆角 8」这类效果）。旧卡按 true→20 / false→0 迁移，
  /// 见 `fromJson`。
  double pcbRadius;
  DateTime createdAt;

  UIAssemblyInfo({
    required this.id,
    this.name = '未命名 UI',
    this.mode = 'extra',
    this.elementsJson = '[]',
    this.pagesJson = '[]',
    this.pcbWidth = defaultPcbWidth,
    this.pcbHeight = 800,
    this.pcbColorValue = 0xFFFFFFFF,
    this.pcbRadius = defaultPcbRadius,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get modeLabel {
    switch (mode) {
      case 'opening':        return '开场白弹窗';
      case 'scene':          return '场景 UI';
      case 'extra_sticky':   return '常驻 UI';
      case 'extra_companion':return '伴生 UI';
      default:               return '常驻/伴生';
    }
  }

  IconData get modeIcon {
    switch (mode) {
      case 'opening':        return Icons.auto_awesome_rounded;
      case 'scene':          return Icons.gamepad_rounded;
      case 'extra_companion':return Icons.chat_bubble_outline_rounded;
      default:               return Icons.widgets_rounded;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
    'elements': elementsJson,
    'pages': pagesJson,
    'pcbWidth': pcbWidth,
    'pcbHeight': pcbHeight,
    'pcbColorValue': pcbColorValue,
    'pcbRadius': pcbRadius,
    // 继续写出布尔字段：老版本读到新卡时仍能得到一个合理的圆角形态。
    'pcbRounded': pcbRadius > 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory UIAssemblyInfo.fromJson(Map<String, dynamic> json) => UIAssemblyInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '未命名 UI',
    mode: json['mode']?.toString() ?? 'extra',
    elementsJson: json['elements']?.toString() ?? '[]',
    pagesJson: json['pages']?.toString() ?? '[]',
    pcbWidth: (json['pcbWidth'] as num?)?.toDouble() ?? defaultPcbWidth,
    pcbHeight: (json['pcbHeight'] as num?)?.toDouble() ?? 800,
    pcbColorValue: (json['pcbColorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
    // 优先读新字段；旧卡没有它，则按布尔迁移（true→20 / false→0）。
    pcbRadius: (json['pcbRadius'] as num?)?.toDouble().clamp(
              0.0,
              kMaxPcbRadius,
            ) ??
        (json['pcbRounded'] != false ? defaultPcbRadius : 0.0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  String toJsonString() => jsonEncode(toJson());

  factory UIAssemblyInfo.fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return UIAssemblyInfo.fromJson(decoded);
      if (decoded is Map) return UIAssemblyInfo.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return UIAssemblyInfo(id: '', name: '损坏数据');
  }
}

class AssemblyPage {
  final String id;
  String name;
  String type; // 'base' | 'overlay'
  String? parentPageId;
  int sortOrder;
  List<UIElement> elements;
  List<AssemblyPageGesture> gestures;
  List<PropertyOverride> propertyOverrides;

  AssemblyPage({
    required this.id,
    required this.name,
    required this.type,
    this.parentPageId,
    this.sortOrder = 0,
    List<UIElement>? elements,
    List<AssemblyPageGesture>? gestures,
    List<PropertyOverride>? propertyOverrides,
  })  : elements = elements ?? <UIElement>[],
        gestures = gestures ?? <AssemblyPageGesture>[],
        propertyOverrides = propertyOverrides ?? <PropertyOverride>[];

  bool get isOverlay => type == 'overlay';
  bool get isBase => !isOverlay;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'parentPageId': parentPageId,
    'sortOrder': sortOrder,
    'elements': elements.map((element) => element.toJson()).toList(),
    'gestures': gestures.map((gesture) => gesture.toJson()).toList(),
    'propertyOverrides':
        propertyOverrides.map((override) => override.toJson()).toList(),
  };

  factory AssemblyPage.fromJson(Map<String, dynamic> json) => AssemblyPage(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '未命名页面',
    type: json['type']?.toString() == 'overlay' ? 'overlay' : 'base',
    parentPageId: json['parentPageId']?.toString(),
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    elements: (json['elements'] as List?)
            ?.whereType<Map>()
            .map((item) => UIElement.fromJson(Map<String, dynamic>.from(item)))
            .toList() ??
        <UIElement>[],
    gestures: (json['gestures'] as List?)
            ?.whereType<Map>()
            .map((item) =>
                AssemblyPageGesture.fromJson(Map<String, dynamic>.from(item)))
            .toList() ??
        <AssemblyPageGesture>[],
    propertyOverrides: (json['propertyOverrides'] as List?)
            ?.whereType<Map>()
            .map((item) =>
                PropertyOverride.fromJson(Map<String, dynamic>.from(item)))
            .toList() ??
        <PropertyOverride>[],
  );
}

class AssemblyPageGesture {
  final String direction;
  final String action;
  final String targetPageId;
  final String transition;
  final int durationMs;

  const AssemblyPageGesture({
    required this.direction,
    required this.action,
    required this.targetPageId,
    this.transition = '',
    this.durationMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'action': action,
    'targetPageId': targetPageId,
    'transition': transition,
    'durationMs': durationMs,
  };

  factory AssemblyPageGesture.fromJson(Map<String, dynamic> json) =>
      AssemblyPageGesture(
        direction: json['direction']?.toString() ?? 'swipe_left',
        action: json['action']?.toString() ?? 'switch_base_page',
        targetPageId: json['targetPageId']?.toString() ?? '',
        transition: json['transition']?.toString() ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );
}

class AssemblyBinding {
  String? statusKey;
  String? fieldType;
  String direction; // 'bidirectional' | 'upload_only' | 'none'

  AssemblyBinding({
    this.statusKey,
    this.fieldType,
    this.direction = 'none',
  });

  Map<String, dynamic> toJson() => {
    'statusKey': statusKey,
    'fieldType': fieldType,
    'direction': direction,
  };

  factory AssemblyBinding.fromJson(Map<String, dynamic> json) =>
      AssemblyBinding(
        statusKey: json['statusKey']?.toString(),
        fieldType: json['fieldType']?.toString(),
        direction: json['direction']?.toString() ?? 'none',
      );

  AssemblyBinding copyWith({
    String? statusKey,
    String? fieldType,
    String? direction,
  }) {
    return AssemblyBinding(
      statusKey: statusKey ?? this.statusKey,
      fieldType: fieldType ?? this.fieldType,
      direction: direction ?? this.direction,
    );
  }
}

class PropertyOverride {
  String componentId;
  Map<String, dynamic> overrides;
  AssemblyBinding? binding;
  String? sourceCompositeId;
  String? sourceElementId;

  PropertyOverride({
    required this.componentId,
    Map<String, dynamic>? overrides,
    this.binding,
    this.sourceCompositeId,
    this.sourceElementId,
  }) : overrides = overrides ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
    'componentId': componentId,
    'overrides': overrides,
    'binding': binding?.toJson(),
    'sourceCompositeId': sourceCompositeId,
    'sourceElementId': sourceElementId,
  };

  factory PropertyOverride.fromJson(Map<String, dynamic> json) => PropertyOverride(
        componentId: json['componentId']?.toString() ?? '',
        overrides: Map<String, dynamic>.from(json['overrides'] ?? const {}),
        binding: json['binding'] is Map
            ? AssemblyBinding.fromJson(
                Map<String, dynamic>.from(json['binding'] as Map),
              )
            : null,
        sourceCompositeId: json['sourceCompositeId']?.toString(),
        sourceElementId: json['sourceElementId']?.toString(),
      );

  PropertyOverride copyWith({
    String? componentId,
    Map<String, dynamic>? overrides,
    AssemblyBinding? binding,
    String? sourceCompositeId,
    String? sourceElementId,
    bool clearBinding = false,
  }) {
    return PropertyOverride(
      componentId: componentId ?? this.componentId,
      overrides: overrides ?? Map<String, dynamic>.from(this.overrides),
      binding: clearBinding ? null : (binding ?? this.binding?.copyWith()),
      sourceCompositeId: sourceCompositeId ?? this.sourceCompositeId,
      sourceElementId: sourceElementId ?? this.sourceElementId,
    );
  }
}
