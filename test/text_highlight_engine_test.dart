import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/character_meta.dart';
import 'package:llm_project/models/text_highlight_rule.dart';
import 'package:llm_project/services/text_highlight_engine.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

void main() {
  const base = TextStyle(fontSize: 14, color: Colors.black87);

  String joined(List<HighlightSegment> segs) => segs.map((s) => s.text).join();

  group('规则模型', () {
    test('非法正则不抛异常，pattern 返回 null', () {
      const rule = TextHighlightRule(name: 'x', regex: '([unclosed');
      expect(rule.pattern, isNull);
      expect(rule.isValid, isFalse);
    });

    test('空正则视为无效', () {
      expect(const TextHighlightRule(name: 'x', regex: '   ').isValid, isFalse);
    });

    test('JSON 往返保真', () {
      const rule = TextHighlightRule(
        name: '台词',
        regex: r'“[^”]*”',
        colorValue: 0xFF112233,
        bold: true,
        italic: true,
        enabled: false,
      );
      expect(TextHighlightRule.fromJson(rule.toJson()), rule);
    });

    test('旧数据缺 enabled 字段时默认启用', () {
      final rule = TextHighlightRule.fromJson({'name': 'a', 'regex': 'x'});
      expect(rule.enabled, isTrue);
    });

    test('clearColor 能把颜色清成沿用正文色', () {
      const rule = TextHighlightRule(name: 'a', regex: 'x', colorValue: 1);
      expect(rule.copyWith(clearColor: true).colorValue, isNull);
    });
  });

  group('切分不丢字', () {
    test('拼回原文与输入完全一致', () {
      const text = '她说“你好”，（然后笑了）。剩下的普通文字。';
      final segs = TextHighlightEngine.split(text, TextHighlightRule.defaults());
      expect(joined(segs), text);
    });

    test('无规则命中时整段作为一个片段', () {
      const text = '完全普通的一句话';
      final segs = TextHighlightEngine.split(text, TextHighlightRule.defaults());
      expect(joined(segs), text);
      expect(segs.every((s) => s.rule == null), isTrue);
    });

    test('空文本返回空列表', () {
      expect(TextHighlightEngine.split('', TextHighlightRule.defaults()), isEmpty);
    });
  });

  group('优先级与重叠', () {
    test('靠前的规则先占位，靠后的不覆盖', () {
      const first = TextHighlightRule(name: '整句', regex: r'“[^”]*”');
      const second = TextHighlightRule(name: '任意字', regex: r'.');
      final segs = TextHighlightEngine.split('“喂”', [first, second]);
      // 整句被 first 吃掉，second 无处可放。
      expect(segs.length, 1);
      expect(segs.single.rule?.name, '整句');
    });

    test('部分重叠的后续规则整条丢弃，不做半截着色', () {
      const a = TextHighlightRule(name: 'a', regex: 'abc');
      const b = TextHighlightRule(name: 'b', regex: 'bcd');
      final segs = TextHighlightEngine.split('abcd', [a, b]);
      expect(joined(segs), 'abcd');
      expect(segs.first.rule?.name, 'a');
      // 'd' 未被 b 着色，因为 b 的匹配区间与 a 重叠。
      expect(segs.last.rule, isNull);
    });

    test('停用的规则不参与', () {
      const rule =
          TextHighlightRule(name: 'a', regex: 'abc', enabled: false);
      final segs = TextHighlightEngine.split('abc', [rule]);
      expect(segs.single.rule, isNull);
    });

    test('非法正则被跳过而不是崩溃', () {
      const bad = TextHighlightRule(name: 'bad', regex: '([');
      const good = TextHighlightRule(name: 'good', regex: 'abc');
      final segs = TextHighlightEngine.split('abc', [bad, good]);
      expect(segs.single.rule?.name, 'good');
    });

    test('零宽匹配不产生空片段', () {
      const rule = TextHighlightRule(name: 'empty', regex: 'x*');
      final segs = TextHighlightEngine.split('abc', [rule]);
      expect(joined(segs), 'abc');
      expect(segs.any((s) => s.text.isEmpty), isFalse);
    });
  });

  group('样式合成', () {
    test('未指定颜色时沿用基准色', () {
      const rule = TextHighlightRule(name: 'a', regex: 'x', bold: true);
      final style = TextHighlightEngine.styleFor(rule, base);
      expect(style.color, base.color);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('指定颜色时覆盖基准色', () {
      const rule = TextHighlightRule(name: 'a', regex: 'x', colorValue: 0xFFFF0000);
      expect(TextHighlightEngine.styleFor(rule, base).color,
          const Color(0xFFFF0000));
    });

    test('buildSpan 的子 span 数量与片段数一致', () {
      final span = TextHighlightEngine.buildSpan(
        '她说“你好”。',
        TextHighlightRule.defaults(),
        base,
      );
      final segs = TextHighlightEngine.split('她说“你好”。', TextHighlightRule.defaults());
      expect(span.children!.length, segs.length);
    });
  });

  group('CharacterMeta 集成', () {
    test('未配置时回落到内置默认', () {
      final meta = CharacterMeta();
      expect(meta.textHighlightRules, isEmpty);
      expect(meta.effectiveHighlightRules, TextHighlightRule.defaults());
    });

    test('配置后以作者规则为准', () {
      final meta = CharacterMeta(textHighlightRules: const [
        TextHighlightRule(name: '自定义', regex: 'x'),
      ]);
      expect(meta.effectiveHighlightRules.single.name, '自定义');
    });

    test('随 meta_json 序列化往返', () {
      final meta = CharacterMeta(textHighlightRules: const [
        TextHighlightRule(
            name: '旁白', regex: r'\[[^\]]*\]', colorValue: 0xFF445566),
      ]);
      final restored = CharacterMeta.fromJsonString(meta.toJsonString());
      expect(restored.textHighlightRules, meta.textHighlightRules);
    });
  });
}
