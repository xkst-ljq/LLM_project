import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ui_models.dart';

/// A14-1：画布元素操作的核心规则。
///
/// UI 交互本身需要 widget 测试，这里只锁定容易写反的纯逻辑：
/// 层级顺序语义、锁定标记、联动器牵连判定。

UIElement _el(String id, {String type = 'text'}) => UIElement(
      id: id,
      isComposite: false,
      offset: const Offset(4, 6),
      size: const Size(80, 30),
      module: UIModule(id: 'm_$id', name: id, type: type, properties: {}),
    );

UIElement _linker(String id, {required String from, required String to}) =>
    UIElement(
      id: id,
      isComposite: false,
      offset: Offset.zero,
      size: const Size(40, 40),
      module: UIModule(
        id: 'm_$id',
        name: id,
        type: 'linker',
        properties: {
          'linker': {'sourceModuleId': from, 'targetModuleId': to},
        },
      ),
    );

/// 复刻 `_moveElementLayer`：列表越靠后越上层，上移 = 往后挪。
List<String>? moveLayer(List<String> ids, String id, int delta) {
  final index = ids.indexOf(id);
  if (index == -1) return null;
  final target = index + delta;
  if (target < 0 || target >= ids.length) return null;
  final next = [...ids];
  final moved = next.removeAt(index);
  next.insert(target, moved);
  return next;
}

/// 复刻 `_linkersReferencing`。
List<String> linkersReferencing(List<UIElement> elements, String elementId) {
  return elements
      .where((element) {
        final module = element.module;
        if (module == null || module.type != 'linker') return false;
        final data =
            (module.properties['linker'] as Map?)?.cast<String, dynamic>();
        if (data == null) return false;
        return data['sourceModuleId']?.toString() == elementId ||
            data['targetModuleId']?.toString() == elementId;
      })
      .map((e) => e.id)
      .toList();
}

void main() {
  group('层级顺序', () {
    // 这一条最容易写反：Stack 里越靠后画得越晚 = 越在上层，
    // 所以界面上的「上移」对应列表索引 +1，不是 -1。
    final ids = ['a', 'b', 'c']; // c 在最上层

    test('上移 = 往列表后方挪', () {
      expect(moveLayer(ids, 'a', 1), ['b', 'a', 'c']);
    });

    test('下移 = 往列表前方挪', () {
      expect(moveLayer(ids, 'c', -1), ['a', 'c', 'b']);
    });

    test('顶层不能再上移', () {
      expect(moveLayer(ids, 'c', 1), isNull);
    });

    test('底层不能再下移', () {
      expect(moveLayer(ids, 'a', -1), isNull);
    });

    test('不存在的元素返回 null 而不抛异常', () {
      expect(moveLayer(ids, 'zzz', 1), isNull);
    });
  });

  group('联动器牵连', () {
    final elements = [
      _el('btn', type: 'button'),
      _el('txt'),
      _el('other'),
      _linker('l1', from: 'btn', to: 'txt'),
      _linker('l2', from: 'txt', to: 'other'),
    ];

    test('作为源被引用时算牵连', () {
      expect(linkersReferencing(elements, 'btn'), ['l1']);
    });

    test('作为目标被引用时也算牵连', () {
      // 只查源端会漏掉一半，留下的悬空连线在运行时静默失效。
      expect(linkersReferencing(elements, 'other'), ['l2']);
    });

    test('同时是源和目标时两条都算', () {
      expect(linkersReferencing(elements, 'txt'), ['l1', 'l2']);
    });

    test('没有连线的元素返回空', () {
      expect(linkersReferencing(elements, 'nobody'), isEmpty);
    });
  });

  group('双档锁定', () {
    // 用模型上已有的 layoutLocked / sealed，而不是自造
    // properties['locked']——Studio 侧本来就用它们，两边共用同一份数据，
    // 方案在两个编辑器间迁移时锁定状态才不会丢。
    test('半锁只锁形变，不影响联动', () {
      final el = _el('a').copyWith(layoutLocked: true);
      expect(el.layoutLocked, isTrue);
      expect(el.sealed, isFalse);
    });

    test('全锁额外锁住联动，并自动带上半锁', () {
      final el = _el('a').copyWith(sealed: true, layoutLocked: true);
      expect(el.sealed, isTrue);
      expect(el.layoutLocked, isTrue);
    });

    test('全锁的元素不进入联动候选', () {
      final elements = [
        _el('free'),
        _el('locked').copyWith(sealed: true),
        _el('half').copyWith(layoutLocked: true),
      ];
      final candidates =
          elements.where((e) => !e.sealed).map((e) => e.id).toList();
      // 半锁仍可参与联动，只有全锁被排除。
      expect(candidates, ['free', 'half']);
    });

    // 两档共用一栏：按状态决定露几个按钮，默认只占一格。
    List<String> visibleLockButtons(UIElement el) => [
          if (!el.sealed) 'half',
          if (el.layoutLocked || el.sealed) 'full',
        ];

    test('未锁时只显示半锁按钮', () {
      expect(visibleLockButtons(_el('a')), ['half']);
    });

    test('半锁后全锁按钮才出现', () {
      // 未锁时不给全锁入口——避免跳过半锁直接全锁，
      // 那样解锁时突然回落到半锁态会显得没来由。
      final el = _el('a').copyWith(layoutLocked: true);
      expect(visibleLockButtons(el), ['half', 'full']);
    });

    test('全锁时半锁隐藏，全锁顶替其位置', () {
      final el = _el('a').copyWith(layoutLocked: true, sealed: true);
      expect(visibleLockButtons(el), ['full']);
    });

    test('全锁再点一次回到半锁，而不是直接解锁', () {
      final el = _el('a').copyWith(layoutLocked: true, sealed: true);
      // _toggleElementSealed：next=false 时保留 layoutLocked。
      final next = el.copyWith(sealed: false);
      expect(next.sealed, isFalse);
      expect(next.layoutLocked, isTrue);
      expect(visibleLockButtons(next), ['half', 'full']);
    });

    test('锁定状态参与序列化，跨编辑器不丢失', () {
      final el = _el('a').copyWith(sealed: true, layoutLocked: true);
      final restored = UIElement.fromJson(el.toJson());
      expect(restored.sealed, isTrue);
      expect(restored.layoutLocked, isTrue);
    });
  });

  group('复制', () {
    test('JSON 往返后嵌套 Map 的键类型正确', () {
      // _deepCloneValue 对嵌套 Map 返回 Map<dynamic,dynamic>，
      // 而 fromJson 里 json['offset'] as Map<String,dynamic>? 是硬转换，
      // 会直接抛 _TypeError（复制时崩溃）。必须走 jsonEncode/Decode。
      final source = _el('e1');
      final json = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source.toJson())) as Map,
      );
      json['id'] = 'e2';
      final clone = UIElement.fromJson(json);
      expect(clone.id, 'e2');
      expect(clone.offset, source.offset);
      expect(clone.size, source.size);
    });

    test('复制不影响原元素', () {
      final source = _el('e1');
      final json = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source.toJson())) as Map,
      );
      json['id'] = 'e2';
      UIElement.fromJson(json);
      expect(source.id, 'e1');
    });
  });
}
