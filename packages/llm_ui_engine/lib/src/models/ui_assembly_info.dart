import 'dart:convert';
import 'package:flutter/material.dart';

import '../engine/ui_models.dart';

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

  /// 各开场分支的页面变体：分支下标 -> 该分支专属的 `pagesJson`。
  ///
  /// ## 解决什么
  ///
  /// 一张卡有多条开场白时，各条是**平级分支**
  /// （「新人入狱」「狱警入职」…），作者可能希望不同开局
  /// 看到不同的界面——或者界面相同但初始数据不同。
  ///
  /// ## 与 [pagesJson] 的关系
  ///
  /// [pagesJson] 是**主支路（分支 0）**，同时充当兜底：
  /// 某分支没有变体时用它渲染。因此：
  ///
  /// - 单开场白的卡：这个 Map 恒为空，零影响；
  /// - 作者只改了分支 2：Map 里只有 `{'2': ...}`，其余照搬主支路。
  ///
  /// **不为每个分支都存一份**是刻意的：全量复制会让存档膨胀数倍，
  /// 而且主支路改版式后，未改动的分支应当自动跟随。
  ///
  /// 键用 String 是为了直接进 JSON。
  Map<String, String> branchVariants;

  UIAssemblyInfo({
    required this.id,
    this.name = '未命名 UI',
    this.mode = 'extra',
    this.elementsJson = '[]',
    this.pagesJson = '[]',
    Map<String, String>? branchVariants,
    this.pcbWidth = defaultPcbWidth,
    this.pcbHeight = 800,
    this.pcbColorValue = 0xFFFFFFFF,
    this.pcbRadius = defaultPcbRadius,
    DateTime? createdAt,
  })  : branchVariants = branchVariants ?? <String, String>{},
        createdAt = createdAt ?? DateTime.now();

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
    // 空表不落盘：单开场白的卡不该平白多一个空字段。
    if (branchVariants.isNotEmpty) 'branchVariants': branchVariants,
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
    branchVariants: _readBranchVariants(json['branchVariants']),
  );

  /// 读分支变体表。键必须是非负整数下标，脏数据一律丢弃。
  static Map<String, String> _readBranchVariants(dynamic raw) {
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      final idx = int.tryParse(k);
      if (idx == null || idx < 0) return;
      final v = value?.toString() ?? '';
      if (v.isNotEmpty && v != '[]') out[k] = v;
    });
    return out;
  }

  /// 取某分支实际生效的 `pagesJson`。
  ///
  /// 没有专属变体时回落主支路——即用户说的
  /// 「如果没有设计分支方案，所有的分支方案就照搬主方案」。
  String pagesJsonForBranch(int branch) =>
      branchVariants['$branch'] ?? pagesJson;

  /// 该分支是否有专属设计（而非照搬主支路）。
  ///
  /// 编辑器用它给分支切换器加标记，让作者一眼看出
  /// 哪些分支自己改过、哪些还在跟随主支路。
  bool hasBranchVariant(int branch) =>
      branch != 0 && branchVariants.containsKey('$branch');

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

/// 历史遗留的「挂载位绑定」(AssemblyBinding) 已删除。
///
/// 它想做的事——把复合件子件挂到状态栏字段上——
/// 已经被**数据通道**完整覆盖，而且数据通道是严格超集：
///
/// | 挂载位 | 数据通道 |
/// |---|---|
/// | `statusKey` 字符串名 | `targetKind: 'status_field'` + 真实字段 ID |
/// | `fieldType` | 从状态字段本身读取，不用手填 |
/// | `direction` 三态 | `llmReadPolicy` / `llmWritePolicy` 分开控制 |
/// | — | 另支持 session_var / card_entry / user_profile |
///
/// 决定性的一点：挂载位写进去的 `statusKey`
/// **全库没有任何读取方**，运行时与引擎层完全不消费，
/// 是数据通道体系建立之前的设计残留。留着只会让作者
/// 以为「配了就会生效」——正是 HANDOFF 3.5j 那类静默失效。

class PropertyOverride {
  String componentId;
  Map<String, dynamic> overrides;
  String? sourceCompositeId;
  String? sourceElementId;

  PropertyOverride({
    required this.componentId,
    Map<String, dynamic>? overrides,
    this.sourceCompositeId,
    this.sourceElementId,
  }) : overrides = overrides ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
    'componentId': componentId,
    'overrides': overrides,
    'sourceCompositeId': sourceCompositeId,
    'sourceElementId': sourceElementId,
  };

  factory PropertyOverride.fromJson(Map<String, dynamic> json) => PropertyOverride(
        componentId: json['componentId']?.toString() ?? '',
        overrides: Map<String, dynamic>.from(json['overrides'] ?? const {}),
        sourceCompositeId: json['sourceCompositeId']?.toString(),
        sourceElementId: json['sourceElementId']?.toString(),
      );

  PropertyOverride copyWith({
    String? componentId,
    Map<String, dynamic>? overrides,
    String? sourceCompositeId,
    String? sourceElementId,
  }) {
    return PropertyOverride(
      componentId: componentId ?? this.componentId,
      overrides: overrides ?? Map<String, dynamic>.from(this.overrides),
      sourceCompositeId: sourceCompositeId ?? this.sourceCompositeId,
      sourceElementId: sourceElementId ?? this.sourceElementId,
    );
  }
}

/// 复合件子件的「实例改名」覆写键。
///
/// 和外观键同理：`name` 是 [UIModule] 的独立字段而非 properties 条目，
/// 必须走 `copyWith(name:)` 才生效。
///
/// 留空 / 全空白视为「不覆写」，回落模板名——
/// 这样作者清空输入框就能恢复默认，不需要额外的「重置」按钮。
const String kCompositeChildNameOverrideKey = '__ovr_name';

/// 复合件子件「外观覆写」的键名与套用规则。
///
/// ## 为什么需要这一层
///
/// [PropertyOverride.overrides] 是个 `Map<String, dynamic>`，
/// 原本只会被 `addAll` 进 `UIModule.properties`。
/// 但外观五项（color / material / shape / borderRadius / opacity）
/// **不在 properties 里**，它们是 [UIModule] 的独立字段。
///
/// 于是出现一个隐蔽的坑：往 overrides 里写 `color` 不会报错，
/// 也确实进了 properties，但渲染时读的是 `module.color`，
/// **改了等于没改**——正是 HANDOFF 3.5j 记的那类「静默失效」。
///
/// 这里把外观键单独拎出来，套用时改走 `copyWith` 的具名参数。
/// 编辑器端与运行时端都必须用这份规则，否则画布和实际运行两个样。
class AppearanceOverrideKeys {
  const AppearanceOverrideKeys._();

  static const String color = '__ovr_color';
  static const String material = '__ovr_material';
  static const String shape = '__ovr_shape';
  static const String borderRadius = '__ovr_borderRadius';
  static const String opacity = '__ovr_opacity';

  /// 双下划线前缀：与作者可见的普通属性区分，
  /// 和 `ElementAnimation.propsKey`（`__anim`）同一套约定。
  ///
  /// 动画**不在这里**——它本来就存在 properties 的 `__anim` 键里，
  /// 走普通 `addAll` 路径就能生效，不需要特殊套用。
  static const Set<String> all = {
    color,
    material,
    shape,
    borderRadius,
    opacity,
  };

  static bool isAppearanceKey(String key) => all.contains(key);

  /// 把 overrides 里的外观键套到 [module] 上。
  ///
  /// [patch] 应当是已经合并好的覆写表；不含外观键时原样返回。
  static UIModule applyTo(UIModule module, Map<String, dynamic> patch) {
    if (patch.isEmpty) return module;

    UIModuleMaterial? material;
    final rawMaterial = patch[AppearanceOverrideKeys.material]?.toString();
    if (rawMaterial != null) {
      for (final value in UIModuleMaterial.values) {
        if (value.name == rawMaterial) {
          material = value;
          break;
        }
      }
    }

    UIModuleShape? shape;
    final rawShape = patch[AppearanceOverrideKeys.shape]?.toString();
    if (rawShape != null) {
      for (final value in UIModuleShape.values) {
        if (value.name == rawShape) {
          shape = value;
          break;
        }
      }
    }

    // 宽松读数值：历史存档里可能存成字符串形式（"12"）。
    // 只写 `as num?` 会让它静默回落，等于打开编辑器就把值改了。
    double? readNum(String key) {
      final raw = patch[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim());
      return null;
    }

    final rawColor = patch[AppearanceOverrideKeys.color];
    final colorValue = rawColor is num
        ? rawColor.toInt()
        : (rawColor is String ? int.tryParse(rawColor.trim()) : null);

    return module.copyWith(
      color: colorValue == null ? null : Color(colorValue),
      material: material,
      shape: shape,
      borderRadius: readNum(AppearanceOverrideKeys.borderRadius),
      opacity: readNum(AppearanceOverrideKeys.opacity),
    );
  }

  /// 从覆写表里剔除外观键，剩下的才是要并进 properties 的部分。
  static Map<String, dynamic> stripFrom(Map<String, dynamic> patch) {
    final result = Map<String, dynamic>.from(patch);
    for (final key in all) {
      result.remove(key);
    }
    return result;
  }
}
