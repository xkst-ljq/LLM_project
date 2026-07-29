import 'package:flutter/material.dart';

import '../models/text_highlight_rule.dart';

/// 一段被着色的文本片段。
class HighlightSegment {
  final String text;

  /// 命中的规则；null 表示这段没有匹配任何规则（用基准样式）。
  final TextHighlightRule? rule;

  const HighlightSegment(this.text, this.rule);
}

/// 按作者配置的正则规则给文本着色。
///
/// 只做展示层的切分与着色，**不改写文本内容**——
/// 发给 LLM 的、存进数据库的始终是原文。
class TextHighlightEngine {
  /// 单条规则在一段文本里最多匹配多少次。
  ///
  /// 防御作者写出 `(a*)*` 这类灾难性回溯，或用 `.*` 之类在超长文本上
  /// 产生海量片段拖垮渲染。超出后剩余部分按普通文本处理。
  static const int maxMatchesPerRule = 500;

  /// 把文本切分成若干片段。
  ///
  /// 规则**按列表顺序决定优先级**：靠前的先占位，后面的规则不能与
  /// 已占用区间重叠。这样作者把「台词」放在「整句」之前，
  /// 就能得到「台词特殊、其余普通」而不是互相覆盖的结果。
  ///
  /// 返回的片段按原文顺序排列，拼起来等于原文（这一点有测试守着——
  /// 一旦漏字就是内容丢失，比着色错误严重得多）。
  static List<HighlightSegment> split(
    String text,
    List<TextHighlightRule> rules,
  ) {
    if (text.isEmpty) return const <HighlightSegment>[];

    // 记录每个字符位置是否已被更高优先级的规则占用。
    final owner = List<TextHighlightRule?>.filled(text.length, null);
    final taken = List<bool>.filled(text.length, false);

    for (final rule in rules) {
      if (!rule.enabled) continue;
      final pattern = rule.pattern;
      // 非法正则直接跳过：作者边写边预览时必然出现半成品状态，
      // 这里崩掉会让整个消息列表白屏。
      if (pattern == null) continue;

      var count = 0;
      for (final match in pattern.allMatches(text)) {
        if (++count > maxMatchesPerRule) break;
        if (match.start == match.end) continue; // 零宽匹配会导致死循环式空片段

        // 与已占区间重叠则整条丢弃，不做部分着色——
        // 半截着色的观感比不着色更糟。
        var overlaps = false;
        for (var i = match.start; i < match.end; i++) {
          if (taken[i]) {
            overlaps = true;
            break;
          }
        }
        if (overlaps) continue;

        for (var i = match.start; i < match.end; i++) {
          taken[i] = true;
          owner[i] = rule;
        }
      }
    }

    // 合并相邻同归属字符成片段。
    final segments = <HighlightSegment>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      final changed = i == text.length || !identical(owner[i], owner[start]);
      if (changed) {
        segments.add(HighlightSegment(text.substring(start, i), owner[start]));
        start = i;
      }
    }
    return segments;
  }

  /// 生成可直接交给 `Text.rich` / `SelectableText.rich` 的 span 树。
  static TextSpan buildSpan(
    String text,
    List<TextHighlightRule> rules,
    TextStyle baseStyle,
  ) {
    final segments = split(text, rules);
    if (segments.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    return TextSpan(
      style: baseStyle,
      children: [
        for (final seg in segments)
          TextSpan(
            text: seg.text,
            style: seg.rule == null ? null : styleFor(seg.rule!, baseStyle),
          ),
      ],
    );
  }

  /// 把规则的样式意图叠加到基准样式上。
  ///
  /// 只覆盖规则明确指定的属性：颜色留空就沿用基准色，
  /// 这样作者在深色 PCB 上调整基准色时，只设了粗体的规则会自动跟随。
  static TextStyle styleFor(TextHighlightRule rule, TextStyle baseStyle) {
    return baseStyle.copyWith(
      color: rule.colorValue == null ? null : Color(rule.colorValue!),
      fontWeight: rule.bold ? FontWeight.w700 : null,
      fontStyle: rule.italic ? FontStyle.italic : null,
      // 规则不该引入下划线：着色是排版辅助，加线会像可点击链接。
      decoration: TextDecoration.none,
    );
  }
}
