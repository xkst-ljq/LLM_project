import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

UIElement _button(String id, {bool keyAction = false}) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(80, 32),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: 'button',
      properties: {
        if (keyAction) UISemanticRole.propKey: true,
      },
    ),
  );
}

UIElement _composite(String id, List<UIElement> children) {
  return UIElement(
    id: id,
    isComposite: true,
    offset: Offset.zero,
    size: const Size(200, 100),
    composite: UIComposite(
      id: 'tpl_$id',
      name: id,
      layoutType: 'free',
      children: children,
    ),
  );
}

void main() {
  group('标记读取', () {
    test('未标记时为 false', () {
      expect(UISemanticRole.isKeyAction(_button('a').module), isFalse);
    });

    test('标记后能读出', () {
      expect(
        UISemanticRole.isKeyAction(_button('a', keyAction: true).module),
        isTrue,
      );
    });

    test('module 为空时安全返回', () {
      expect(UISemanticRole.isKeyAction(null), isFalse);
    });

    test('只有 button 可以承担关键职责', () {
      expect(UISemanticRole.canMark('button'), isTrue);
      for (final type in ['text', 'slider', 'progress', 'surface']) {
        expect(UISemanticRole.canMark(type), isFalse, reason: type);
      }
    });
  });

  group('各 mode 的职责定义', () {
    test('伴生 UI 不要求关键职责', () {
      expect(UISemanticRole.requiresKeyAction('extra_companion'), isFalse);
    });

    test('其余三种都要求', () {
      for (final mode in ['opening', 'scene', 'extra_sticky']) {
        expect(UISemanticRole.requiresKeyAction(mode), isTrue, reason: mode);
      }
    });

    test('只有接管型 UI 会因缺标记而被拦截', () {
      // 常驻缺折叠只是少个功能，仍可用；接管型缺出口会把玩家卡死。
      expect(UISemanticRole.blocksWithoutKeyAction('opening'), isTrue);
      expect(UISemanticRole.blocksWithoutKeyAction('scene'), isTrue);
      expect(UISemanticRole.blocksWithoutKeyAction('extra_sticky'), isFalse);
      expect(
        UISemanticRole.blocksWithoutKeyAction('extra_companion'),
        isFalse,
      );
    });

    test('每种 mode 有各自的职责名与提示语', () {
      const modes = ['opening', 'scene', 'extra_sticky'];
      final labels = modes.map(UISemanticRole.actionLabelOf).toSet();
      // 三种职责名互不相同，避免作者混淆。
      expect(labels.length, 3);
      for (final mode in modes) {
        expect(UISemanticRole.missingHintOf(mode), isNotEmpty, reason: mode);
      }
    });

    test('提示语用大白话说明后果', () {
      expect(UISemanticRole.missingHintOf('opening'), contains('无法关闭'));
      expect(UISemanticRole.missingHintOf('scene'), contains('无法打开'));
      expect(UISemanticRole.missingHintOf('extra_sticky'), contains('无法收起'));
    });

    test('不同 mode 的标签配色不同', () {
      final colors = ['opening', 'scene', 'extra_sticky']
          .map(UISemanticRole.colorOf)
          .toSet();
      expect(colors.length, 3);
    });
  });

  group('查找标记', () {
    test('在顶层元素中找到', () {
      final elements = [_button('a'), _button('b', keyAction: true)];
      expect(UISemanticRole.findKeyActionId(elements), 'b');
    });

    test('能深入复合组件内部查找', () {
      final elements = [
        _composite('comp', [_button('inner', keyAction: true)]),
      ];
      expect(UISemanticRole.findKeyActionId(elements), 'inner');
    });

    test('找不到时返回 null', () {
      expect(UISemanticRole.findKeyActionId([_button('a')]), isNull);
    });

    test('空元素树安全返回', () {
      expect(UISemanticRole.hasKeyAction(const []), isFalse);
    });
  });
}
