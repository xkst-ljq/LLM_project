import 'package:flutter/widgets.dart';

import '../models/text_highlight_rule.dart';

/// 向 UI 引擎子树传递角色卡的正则着色规则。
///
/// 与 `MessageFlowScope` 同样的理由走 InheritedWidget 而非 properties：
/// 规则属于角色卡级配置，不是组件配置，写进 `module.properties` 会被
/// `_persistAssemblyElements` 复制进每个组件，改一次规则要改一堆地方。
///
/// 未提供时组件回落到 [TextHighlightRule.defaults]。
class TextHighlightScope extends InheritedWidget {
  final List<TextHighlightRule> rules;

  const TextHighlightScope({
    super.key,
    required this.rules,
    required super.child,
  });

  /// 取规则。注意：读取方必须处在本作用域**之下**的 context——
  /// 用外层 build 的 context 会拿不到（这个坑在 MessageFlowScope 上踩过）。
  static List<TextHighlightRule>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TextHighlightScope>()
        ?.rules;
  }

  @override
  bool updateShouldNotify(TextHighlightScope oldWidget) {
    if (oldWidget.rules.length != rules.length) return true;
    for (var i = 0; i < rules.length; i++) {
      if (oldWidget.rules[i] != rules[i]) return true;
    }
    return false;
  }
}
