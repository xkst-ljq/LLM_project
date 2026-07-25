import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/ui_engine/ui_models.dart';

/// 角色卡 UI 组装方案的轻量快照
class UIAssemblyInfo {
  final String id;
  String name;
  String mode; // 'opening', 'scene', 'extra'
  String elementsJson; // 旧版存储字段，保留兼容
  String pagesJson; // 新版多页面结构 JSON
  double pcbHeight;
  int pcbColorValue;
  bool pcbRounded;
  DateTime createdAt;

  UIAssemblyInfo({
    required this.id,
    this.name = '未命名 UI',
    this.mode = 'extra',
    this.elementsJson = '[]',
    this.pagesJson = '[]',
    this.pcbHeight = 800,
    this.pcbColorValue = 0xFFFFFFFF,
    this.pcbRounded = true,
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
    'pcbHeight': pcbHeight,
    'pcbColorValue': pcbColorValue,
    'pcbRounded': pcbRounded,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory UIAssemblyInfo.fromJson(Map<String, dynamic> json) => UIAssemblyInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '未命名 UI',
    mode: json['mode']?.toString() ?? 'extra',
    elementsJson: json['elements']?.toString() ?? '[]',
    pagesJson: json['pages']?.toString() ?? '[]',
    pcbHeight: (json['pcbHeight'] as num?)?.toDouble() ?? 800,
    pcbColorValue: (json['pcbColorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
    pcbRounded: json['pcbRounded'] != false,
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

  AssemblyPage({
    required this.id,
    required this.name,
    required this.type,
    this.parentPageId,
    this.sortOrder = 0,
    List<UIElement>? elements,
    List<AssemblyPageGesture>? gestures,
  })  : elements = elements ?? <UIElement>[],
        gestures = gestures ?? <AssemblyPageGesture>[];

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
  );
}

class AssemblyPageGesture {
  final String direction;
  final String action;
  final String targetPageId;

  const AssemblyPageGesture({
    required this.direction,
    required this.action,
    required this.targetPageId,
  });

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'action': action,
    'targetPageId': targetPageId,
  };

  factory AssemblyPageGesture.fromJson(Map<String, dynamic> json) =>
      AssemblyPageGesture(
        direction: json['direction']?.toString() ?? 'swipe_left',
        action: json['action']?.toString() ?? 'switch_page',
        targetPageId: json['targetPageId']?.toString() ?? '',
      );
}
