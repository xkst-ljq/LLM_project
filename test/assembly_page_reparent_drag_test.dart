import 'package:flutter_test/flutter_test.dart';

/// 灵感池 4.2：叠加页拖放换父级。
///
/// 复刻 `character_assembly_page/logic.dart` 里的
/// `_canDropPageInto` / `_applyPageReparent` / `_reparentCandidatesForPage`。
///
/// **手势冲突是这样消解的**（用户的观察）：
///
/// | 页面类型 | 有无父级 | 需要的操作 |
/// |---|---|---|
/// | 平级页 | 无父级 | 只需排序 |
/// | 叠加页 | 有父级 | 只需换父（同级顺序不影响打开） |
///
/// 每种页面只有一种拖动行为，因此不必在同一套手势里区分
/// 「排序」与「换父」——那正是原先判定「手势风险高」的根源。

class Page {
  Page(this.id, {this.parent, required this.overlay, this.sortOrder = 0});

  final String id;
  String? parent;
  final bool overlay;
  int sortOrder;

  bool get isBase => !overlay;
}

class PageTree {
  PageTree(List<Page> pages) {
    for (final p in pages) {
      _pages[p.id] = p;
    }
  }

  final Map<String, Page> _pages = {};

  Iterable<Page> get all => _pages.values;

  Page? operator [](String id) => _pages[id];

  /// 复刻 `_pageDepth`。visited 兜底防止成环时死循环。
  int depth(String id) {
    var d = 0;
    var parent = _pages[id]?.parent;
    final visited = <String>{id};
    while (parent != null && parent.isNotEmpty && visited.add(parent)) {
      final p = _pages[parent];
      if (p == null) break;
      d++;
      parent = p.parent;
    }
    return d;
  }

  /// 复刻 `_isDescendantPage`。
  bool isDescendant(String pageId, String ancestorId) {
    var current = pageId;
    final visited = <String>{};
    while (visited.add(current)) {
      final parent = _pages[current]?.parent;
      if (parent == null || parent.isEmpty) return false;
      if (parent == ancestorId) return true;
      current = parent;
    }
    return false;
  }

  /// 复刻 `_directChildPages`。
  List<Page> childrenOf(String? parentId) {
    final list = _pages.values.where((p) => p.parent == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// 复刻 `_reparentCandidatesForPage`（弹窗用）。
  List<String> reparentCandidates(String pageId) {
    final d = depth(pageId);
    if (d == 0) return const [];
    final out = <String>[];
    for (final c in _pages.values) {
      if (c.id == pageId) continue;
      if (isDescendant(c.id, pageId)) continue;
      final cd = depth(c.id);
      if (d == 1) {
        if (cd <= 1) out.add(c.id);
      } else {
        if (c.overlay && cd == 1) out.add(c.id);
      }
    }
    out.sort();
    return out;
  }

  /// 复刻 `_canDropPageInto`（拖放用）。
  bool canDrop(String pageId, String targetId) {
    final page = _pages[pageId];
    if (page == null) return false;
    if (!page.overlay) return false;
    if (targetId == pageId) return false;
    if (page.parent == targetId) return false;
    if (isDescendant(targetId, pageId)) return false;
    final target = _pages[targetId];
    if (target == null) return false;
    final d = depth(pageId);
    final td = depth(targetId);
    if (d == 1) return td <= 1;
    return target.overlay && td == 1;
  }

  /// 复刻 `_applyPageReparent`。返回是否真的改动了。
  bool reparent(String pageId, String newParentId) {
    final page = _pages[pageId];
    if (page == null) return false;
    final oldParent = page.parent;
    if (oldParent == newParentId) return false;
    if (newParentId == pageId || isDescendant(newParentId, pageId)) {
      return false;
    }

    final newSiblingCount =
        _pages.values.where((p) => p.parent == newParentId).length;
    page.parent = newParentId;
    page.sortOrder = newSiblingCount;

    final oldSiblings = _pages.values
        .where((p) => p.parent == oldParent && p.id != pageId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < oldSiblings.length; i++) {
      oldSiblings[i].sortOrder = i;
    }
    return true;
  }
}

PageTree buildTree() => PageTree([
      Page('root', overlay: false, sortOrder: 0),
      Page('base2', overlay: false, sortOrder: 1),
      Page('ovA', parent: 'root', overlay: true, sortOrder: 0),
      Page('ovB', parent: 'root', overlay: true, sortOrder: 1),
      Page('ovA1', parent: 'ovA', overlay: true, sortOrder: 0),
      Page('ovA2', parent: 'ovA', overlay: true, sortOrder: 1),
      Page('ovB1', parent: 'ovB', overlay: true, sortOrder: 0),
    ]);

void main() {
  group('页面深度', () {
    final t = buildTree();
    test('平级页 depth 0', () {
      expect(t.depth('root'), 0);
      expect(t.depth('base2'), 0);
    });
    test('一级叠加页 depth 1', () => expect(t.depth('ovA'), 1));
    test('二级叠加页 depth 2', () => expect(t.depth('ovA1'), 2));
  });

  group('拖放判据与弹窗候选必须一致', () {
    // 两份实现漂移的话，会出现「拖放能放进去、弹窗里却查不到这个候选」，
    // 作者会觉得规则是随机的。
    final t = buildTree();
    for (final id in ['ovA', 'ovB', 'ovA1', 'ovA2', 'ovB1']) {
      test('$id 的候选集与可落点集相同', () {
        final candidates = t.reparentCandidates(id).toSet()
          ..remove(t[id]!.parent);
        final droppable =
            t.all.map((p) => p.id).where((x) => t.canDrop(id, x)).toSet();
        expect(droppable, candidates);
      });
    }
  });

  group('谁可以被拖动', () {
    final t = buildTree();
    test('平级页不可被拖走换父（它没有父级，只需排序）', () {
      expect(t.canDrop('base2', 'root'), isFalse);
      expect(t.canDrop('root', 'base2'), isFalse);
    });
    test('叠加页可以被拖走', () {
      expect(t.canDrop('ovA', 'base2'), isTrue);
    });
  });

  group('防环', () {
    test('不能拖到自己身上', () {
      final t = buildTree();
      expect(t.canDrop('ovA', 'ovA'), isFalse);
    });

    test('不能拖到自己的直接子级', () {
      final t = buildTree();
      expect(t.canDrop('ovA', 'ovA1'), isFalse);
    });

    test('不能拖到自己的深层后代', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('a', parent: 'root', overlay: true),
        Page('b', parent: 'a', overlay: true),
        Page('c', parent: 'b', overlay: true),
      ]);
      expect(t.isDescendant('c', 'a'), isTrue);
      expect(t.reparent('a', 'c'), isFalse, reason: '成环会让整支从树上消失');
    });

    test('reparent 直接调用也拦得住成环', () {
      final t = buildTree();
      expect(t.reparent('ovA', 'ovA1'), isFalse);
      expect(t['ovA']!.parent, 'root', reason: '被拒绝后父级不该被改动');
    });

    test('成环时 depth 不死循环', () {
      // 人为构造环，验证 visited 兜底有效。
      final t = PageTree([
        Page('x', parent: 'y', overlay: true),
        Page('y', parent: 'x', overlay: true),
      ]);
      expect(() => t.depth('x'), returnsNormally);
    });
  });

  group('层级规则', () {
    final t = buildTree();
    test('一级叠加页可挂到任意平级页下', () {
      expect(t.canDrop('ovA', 'base2'), isTrue);
    });
    test('一级叠加页可挂到同级叠加页下', () {
      expect(t.canDrop('ovA', 'ovB'), isTrue);
    });
    test('二级叠加页只能挂到一级叠加页下', () {
      expect(t.canDrop('ovA1', 'ovB'), isTrue);
      expect(t.canDrop('ovA1', 'base2'), isFalse, reason: '会让它变成一级');
      expect(t.canDrop('ovA1', 'root'), isFalse);
    });
    test('拖到当前父级上是空操作', () {
      expect(t.canDrop('ovA', 'root'), isFalse);
      expect(t.canDrop('ovA1', 'ovA'), isFalse);
    });
  });

  group('换父后的 sortOrder 重排', () {
    test('移入新父级时排在末尾', () {
      final t = buildTree();
      expect(t.reparent('ovA1', 'ovB'), isTrue);
      expect(t['ovA1']!.parent, 'ovB');
      // ovB 原本只有 ovB1(0)，新来的应排在 1。
      expect(t['ovA1']!.sortOrder, 1);
    });

    test('离开后原父级下的兄弟补齐空位', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('p', parent: 'root', overlay: true),
        Page('c0', parent: 'p', overlay: true, sortOrder: 0),
        Page('c1', parent: 'p', overlay: true, sortOrder: 1),
        Page('c2', parent: 'p', overlay: true, sortOrder: 2),
        Page('other', parent: 'root', overlay: true),
      ]);
      // 把中间那个搬走。
      expect(t.reparent('c1', 'other'), isTrue);
      expect(t['c0']!.sortOrder, 0);
      expect(t['c2']!.sortOrder, 1, reason: '不补位会留下空洞');
    });

    test('搬走后原父级的子列表顺序稳定', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('p', parent: 'root', overlay: true),
        Page('c0', parent: 'p', overlay: true, sortOrder: 0),
        Page('c1', parent: 'p', overlay: true, sortOrder: 1),
        Page('c2', parent: 'p', overlay: true, sortOrder: 2),
        Page('other', parent: 'root', overlay: true),
      ]);
      t.reparent('c0', 'other');
      expect(t.childrenOf('p').map((e) => e.id).toList(), ['c1', 'c2']);
    });

    test('同一父级重复换父返回 false，不产生副作用', () {
      final t = buildTree();
      final before = t['ovA']!.sortOrder;
      expect(t.reparent('ovA', 'root'), isFalse);
      expect(t['ovA']!.sortOrder, before);
    });
  });

  group('整棵树保持有效', () {
    test('连续多次换父后不出现孤儿或环', () {
      final t = buildTree();
      t.reparent('ovA1', 'ovB');
      t.reparent('ovA2', 'ovB');
      t.reparent('ovA', 'base2');
      // 每个页面都应能沿父链走到某个根平级页。
      for (final p in t.all) {
        var cur = p.id;
        final visited = <String>{};
        while (true) {
          expect(visited.add(cur), isTrue, reason: '$p.id 所在链成环');
          final parent = t[cur]!.parent;
          if (parent == null) break;
          expect(t[parent], isNotNull, reason: '$cur 的父级 $parent 不存在');
          cur = parent;
        }
        expect(t[cur]!.isBase, isTrue, reason: '链尾必须是平级页');
      }
    });

    test('ovA 搬到 base2 后，它的子页跟着走', () {
      final t = buildTree();
      t.reparent('ovA', 'base2');
      expect(t['ovA1']!.parent, 'ovA', reason: '子页父级不变，整支跟着移动');
      expect(t.depth('ovA1'), 2);
    });
  });
}
