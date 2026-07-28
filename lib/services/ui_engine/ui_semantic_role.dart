import 'package:flutter/material.dart';

import 'ui_models.dart';

/// 组件的语义标记：声明「这个组件在运行时承担该 UI 的关键职责」。
///
/// 设计要点：
///   - **一种 mode 只有一个关键职责**，因此作者不需要从一堆选项里挑，
///     只要在按钮编辑页点亮一个标签即可（是 / 否）。
///   - 标记含义由所在 UI 的 mode 决定，同一个 `keyAction` 值
///     在 opening 下是「确认并关闭」，在 scene 下是「打开聊天页设置」。
///   - 不新增专用组件类型，作者用普通 button 表达意图，外观完全自定。
///   - 标记存在 `module.properties['keyAction']`，随实例保存，
///     不回写资产库模板。
class UISemanticRole {
  /// 属性键。值为 true 表示该组件承担所在 mode 的关键职责。
  static const String propKey = 'keyAction';

  /// 该 mode 是否需要关键职责按钮。
  ///
  /// 伴生 UI 嵌在消息流里，没有需要主动退出的状态，故不作要求。
  static bool requiresKeyAction(String mode) {
    return mode == 'opening' || mode == 'scene' || mode == 'extra_sticky';
  }

  /// 缺少标记时是否阻止该 UI 运行。
  ///
  /// opening / scene 会接管界面，没有出口就会把玩家卡死，必须拦截。
  /// 常驻 UI 缺折叠按钮只是少一个功能，仍可正常使用，因此只提示不拦截。
  static bool blocksWithoutKeyAction(String mode) {
    return mode == 'opening' || mode == 'scene';
  }

  /// 该 mode 下关键职责的名称，用于编辑页的标签文字。
  static String actionLabelOf(String mode) {
    switch (mode) {
      case 'opening':
        return '确认并关闭';
      case 'scene':
        return '打开聊天设置';
      case 'extra_sticky':
        return '折叠界面';
      default:
        return '关键操作';
    }
  }

  /// 缺少标记时给作者看的提示语。
  ///
  /// 用大白话讲清楚「会缺什么」，不用「语义角色未绑定」这类术语。
  static String missingHintOf(String mode) {
    switch (mode) {
      case 'opening':
        return '还没有指定关闭按钮，玩家将无法关闭这个开场白。';
      case 'scene':
        return '还没有指定设置按钮，玩家将无法打开聊天设置页。';
      case 'extra_sticky':
        return '还没有指定折叠按钮，玩家将无法收起这个界面。';
      default:
        return '';
    }
  }

  /// 各 mode 的主题色，用于点亮后的标签配色，
  /// 与 UI 方案列表里的模式配色保持一致。
  static Color colorOf(String mode) {
    switch (mode) {
      case 'opening':
        return const Color(0xFF7E57C2);
      case 'scene':
        return const Color(0xFF00897B);
      case 'extra_sticky':
        return const Color(0xFF5E35B1);
      case 'extra_companion':
        return const Color(0xFF00838F);
      default:
        return const Color(0xFF555562);
    }
  }

  /// 该组件是否被标记为关键职责按钮。
  static bool isKeyAction(UIModule? module) =>
      module?.properties[propKey] == true;

  /// 只有可点击的组件承担关键职责才有意义。
  static bool canMark(String type) => type == 'button';

  /// 在元素树中查找关键职责组件的 id（含复合组件内部）。
  /// 返回 null 表示作者尚未标记。
  static String? findKeyActionId(List<UIElement> elements) {
    for (final node in elements) {
      if (isKeyAction(node.module)) return node.id;
      if (node.isComposite && node.composite != null) {
        final inner = findKeyActionId(node.composite!.children);
        if (inner != null) return inner;
      }
    }
    return null;
  }

  static bool hasKeyAction(List<UIElement> elements) =>
      findKeyActionId(elements) != null;
}
