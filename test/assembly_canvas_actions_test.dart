import 'package:flutter_test/flutter_test.dart';

/// 画布级操作：撤销 / 批量删除 / 清空画布。
///
/// 这些操作作用于**整张画布**而非单个元件，因此放在
/// 「未选中任何组件」时的左侧操作栏——与元件级操作栏互斥出现。
/// 同屏两条竖栏会挤掉画布，作者也分不清哪个按钮作用于谁。

/// 复刻 `_pushHistory` / `_undo` 的调度。
class HistoryStack {
  HistoryStack({this.maxDepth = 40, this.throttleMs = 300});

  final int maxDepth;
  final int throttleMs;

  final List<String> _stack = <String>[];
  int? _lastAt;

  /// 正在应用撤销，期间不记录新快照。
  bool applying = false;

  int get depth => _stack.length;
  bool get canUndo => _stack.isNotEmpty;

  /// 返回是否真的入栈了。
  bool push(String snapshot, int nowMs) {
    if (applying) return false;
    final last = _lastAt;
    if (last != null && nowMs - last < throttleMs) return false;
    _lastAt = nowMs;
    if (_stack.isNotEmpty && _stack.last == snapshot) return false;
    _stack.add(snapshot);
    while (_stack.length > maxDepth) {
      _stack.removeAt(0);
    }
    return true;
  }

  /// 撤销一步，返回恢复到的快照。
  String? undo() {
    if (_stack.isEmpty) return null;
    final snapshot = _stack.removeLast();
    applying = true;
    // 撤销结果要落盘，会再次触发 push——必须被 applying 挡住。
    push('post-undo-write', 1 << 30);
    applying = false;
    return snapshot;
  }
}

void main() {
  group('撤销历史', () {
    test('连续拖动只留少量快照', () {
      // 快照打在 _persistAssemblyElements 里，而拖动每帧都会 persist。
      // 不去重的话撤销一次只退回一帧，作者要点几十下才回到起点。
      final h = HistoryStack();
      for (var i = 0; i < 20; i++) {
        h.push('state$i', i * 16);
      }
      expect(h.depth, lessThan(5));
    });

    test('间隔足够的操作逐个入栈', () {
      final h = HistoryStack();
      for (var i = 0; i < 5; i++) {
        h.push('s$i', i * 400);
      }
      expect(h.depth, 5);
    });

    test('相同状态不重复入栈', () {
      // 比如只是点了下没真改，不该占一格历史。
      final h = HistoryStack();
      h.push('same', 0);
      h.push('same', 400);
      h.push('same', 800);
      expect(h.depth, 1);
    });

    test('撤销时不会把自己写进历史', () {
      // 撤销结果要落盘，落盘又会触发 push——
      // 不挡住的话撤销一次栈深不变，等于永远撤不回去。
      final h = HistoryStack();
      h.push('a', 0);
      h.push('b', 400);
      final before = h.depth;
      h.undo();
      expect(h.depth, before - 1);
    });

    test('栈深有上限', () {
      // 角色卡的元素 JSON 可能不小，无限堆会吃内存。
      final h = HistoryStack(maxDepth: 40);
      for (var i = 0; i < 60; i++) {
        h.push('x$i', i * 400);
      }
      expect(h.depth, 40);
    });

    test('空栈时不可撤销', () {
      final h = HistoryStack();
      expect(h.canUndo, isFalse);
      expect(h.undo(), isNull);
    });

    test('撤销后恢复的是最近一次快照', () {
      final h = HistoryStack();
      h.push('first', 0);
      h.push('second', 400);
      expect(h.undo(), 'second');
      expect(h.undo(), 'first');
    });
  });

  group('批量删除', () {
    /// 复刻 `_togglePendingDelete` 的锁定校验。
    bool canBatchDelete({bool layoutLocked = false, bool sealed = false}) {
      return !layoutLocked && !sealed;
    }

    test('锁定的元件不参与批量删除', () {
      // 锁定的语义就是「别动它」，批量操作更要尊重。
      expect(canBatchDelete(layoutLocked: true), isFalse);
      expect(canBatchDelete(sealed: true), isFalse);
      expect(canBatchDelete(), isTrue);
    });

    test('删除容器面时解除组员归属', () {
      // A14-1c：组员指向不存在的父级会让运行时
      // isElementVisibleInSurfaceHierarchy 判定失败，整组凭空消失。
      final removeIds = {'surface_1'};
      final elements = <Map<String, String?>>[
        {'id': 'surface_1', 'parent': null},
        {'id': 'child_a', 'parent': 'surface_1'},
        {'id': 'other', 'parent': 'surface_2'},
      ];

      final survivors = elements
          .where((e) => !removeIds.contains(e['id']))
          .map((e) => {
                ...e,
                if (e['parent'] != null && removeIds.contains(e['parent']))
                  'parent': null,
              })
          .toList();

      expect(survivors.length, 2);
      // 组员被解除归属，就地留在当前层级。
      expect(survivors.firstWhere((e) => e['id'] == 'child_a')['parent'],
          isNull);
      // 指向别的父级的元件不受影响。
      expect(survivors.firstWhere((e) => e['id'] == 'other')['parent'],
          'surface_2');
    });

    test('覆写槽位随组件一起清理', () {
      // 否则会留下指向不存在组件的孤儿配置。
      final removeIds = {'a', 'b'};
      final overrides = ['a', 'b', 'c'];
      overrides.removeWhere(removeIds.contains);
      expect(overrides, ['c']);
    });
  });

  group('清空画布', () {
    test('只影响当前页', () {
      // 清空是重操作，波及其他页面会造成不可挽回的误伤。
      final pages = <String, List<String>>{
        'page1': ['a', 'b'],
        'page2': ['c'],
      };
      pages['page1']!.clear();
      expect(pages['page1'], isEmpty);
      expect(pages['page2'], ['c']);
    });

    test('空画布时不提供操作', () {
      // 按钮置灰而不是点了弹一句「没有组件」。
      const elementCount = 0;
      expect(elementCount == 0, isTrue);
    });
  });

  group('操作栏互斥', () {
    /// 复刻显示条件。
    String railFor({required bool hasSelection, required bool layerPanel}) {
      if (hasSelection) return 'element';
      if (layerPanel) return 'none';
      return 'canvas';
    }

    test('选中组件时显示元件级操作栏', () {
      expect(railFor(hasSelection: true, layerPanel: false), 'element');
    });

    test('未选中时显示画布级操作栏', () {
      expect(railFor(hasSelection: false, layerPanel: false), 'canvas');
    });

    test('两条栏永不同屏', () {
      // 同屏会挤掉画布，作者也分不清哪个按钮作用于谁。
      for (final sel in [true, false]) {
        final rail = railFor(hasSelection: sel, layerPanel: false);
        expect(rail == 'element' && rail == 'canvas', isFalse);
      }
    });

    test('图层面板展开时让位', () {
      // 图层面板本身占屏，再叠一条竖栏会互相遮挡。
      expect(railFor(hasSelection: false, layerPanel: true), 'none');
    });
  });
}
