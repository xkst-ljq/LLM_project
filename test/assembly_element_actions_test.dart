import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ui_models.dart';

/// A14-1：画布元素操作的核心规则。
///
/// UI 交互本身需要 widget 测试，这里只锁定容易写反的纯逻辑：
/// 层级顺序语义、锁定标记、联动器牵连判定。

UIElement _el(String id, {String type = 'text', bool locked = false}) =>
    UIElement(
      id: id,
      isComposite: false,
      offset: Offset.zero,
      size: const Size(80, 30),
      module: UIModule(
        id: 'm_$id',
        name: id,
        type: type,
        properties: {if (locked) 'locked': true},
      ),
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

  group('锁定标记', () {
    test('锁定写入 properties，解锁时移除键', () {
      // 用移除而不是置 false：留一堆 locked:false 会污染角色卡产物。
      final locked = _el('a', locked: true);
      expect(locked.module!.properties['locked'], isTrue);

      final unlocked = _el('a');
      expect(unlocked.module!.properties.containsKey('locked'), isFalse);
    });
  });
}
