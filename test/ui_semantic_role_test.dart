import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_project/services/ui_engine/ui_semantic_role.dart';

UIElement _button(String id, {String? role}) {
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
        if (role != null) 'semanticRole': role,
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
  group('读取角色', () {
    test('未标记时为 none', () {
      expect(UISemanticRole.of(_button('a').module), UISemanticRole.none);
    });

    test('标记后能正确读出', () {
      expect(
        UISemanticRole.of(_button('a', role: UISemanticRole.dismiss).module),
        UISemanticRole.dismiss,
      );
    });

    test('非法值回落为 none，不影响运行时', () {
      expect(
        UISemanticRole.of(_button('a', role: 'nonsense').module),
        UISemanticRole.none,
      );
    });

    test('module 为空时安全返回', () {
      expect(UISemanticRole.of(null), UISemanticRole.none);
    });
  });

  group('closesUI', () {
    test('dismiss 与 confirm 都算关闭', () {
      for (final role in [UISemanticRole.dismiss, UISemanticRole.confirm]) {
        expect(
          UISemanticRole.closesUI(_button('a', role: role).module),
          isTrue,
          reason: role,
        );
      }
    });

    test('拖动把手不触发关闭', () {
      expect(
        UISemanticRole.closesUI(
            _button('a', role: UISemanticRole.dragHandle).module),
        isFalse,
      );
    });

    test('普通组件不触发关闭', () {
      expect(UISemanticRole.closesUI(_button('a').module), isFalse);
    });
  });

  group('查找角色', () {
    test('在顶层元素中找到', () {
      final elements = [
        _button('a'),
        _button('b', role: UISemanticRole.dismiss),
      ];
      expect(
        UISemanticRole.findElementId(elements, UISemanticRole.dismiss),
        'b',
      );
    });

    test('能深入复合组件内部查找', () {
      final elements = [
        _composite('comp', [
          _button('inner', role: UISemanticRole.dismiss),
        ]),
      ];
      expect(
        UISemanticRole.findElementId(elements, UISemanticRole.dismiss),
        'inner',
      );
    });

    test('找不到时返回 null，调用方据此回退到内置按钮', () {
      expect(
        UISemanticRole.findElementId([_button('a')], UISemanticRole.dismiss),
        isNull,
      );
    });

    test('hasRole 与 findElementId 结果一致', () {
      final elements = [_button('a', role: UISemanticRole.dragHandle)];
      expect(
        UISemanticRole.hasRole(elements, UISemanticRole.dragHandle),
        isTrue,
      );
      expect(
        UISemanticRole.hasRole(elements, UISemanticRole.dismiss),
        isFalse,
      );
    });

    test('空元素树安全返回', () {
      expect(
        UISemanticRole.hasRole(const [], UISemanticRole.dismiss),
        isFalse,
      );
    });
  });

  group('编辑器文案', () {
    test('每个角色都有名称与说明', () {
      for (final role in UISemanticRole.all) {
        expect(UISemanticRole.labelOf(role), isNotEmpty, reason: role);
        expect(UISemanticRole.hintOf(role), isNotEmpty, reason: role);
      }
    });

    test('未接入运行时的角色不出现在编辑器选项里', () {
      // 列出但不生效会让作者以为标了就有用。
      expect(UISemanticRole.all, isNot(contains(UISemanticRole.dragHandle)));
    });
  });
}
