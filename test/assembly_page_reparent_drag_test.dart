import 'package:flutter_test/flutter_test.dart';

/// 灵感池 4.2：叠加页拖放换父级。
///
/// 复刻 `character_assembly_page/logic.dart` 里的
/// `_canDropPageInto` / `_applyPageReparent` /
/// `_reparentCandidatesForPage` / `_flattenNestedOverlayPages`。
///
/// **核心规则（用户明确）**：
/// 叠加层无论如何都不能变成子叠加层。叠加页恒为平级页的直接子级，
/// 深度恒为 1。「换父级」= 在**不同平级页之间**切换挂靠，不是嵌套。
///
/// 由此推出两条：
/// - 落点只能是平级页 → 天然不可能成环（平级页没有父级）
/// - 平级页没有父级，不参与换父，只需同级排序

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

  /// 复刻 `_pageDepth`。
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

  /// 复刻 `_baseAncestorOf`。
  String? baseAncestorOf(String id) {
    final page = _pages[id];
    if (page == null) return null;
    if (page.isBase) return id;
    var parentId = page.parent;
    final visited = <String>{id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final parent = _pages[parentId];
      if (parent == null) return null;
      if (parent.isBase) return parent.id;
      parentId = parent.parent;
    }
    return null;
  }

  /// 复刻 `_directChildPages`。
  List<Page> childrenOf(String? parentId) {
    final list = _pages.values.where((p) => p.parent == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// 复刻 `_reparentCandidatesForPage`：叠加页的候选 = 其他平级页。
  List<String> reparentCandidates(String pageId) {
    final page = _pages[pageId];
    if (page == null || !page.overlay) return const [];
    final out = _pages.values
        .where((c) => c.isBase && c.id != page.parent)
        .map((c) => c.id)
        .toList()
      ..sort();
    return out;
  }

  /// 复刻 `_canDropPageInto`：被拖的必须是叠加页，落点必须是平级页。
  bool canDrop(String pageId, String targetId) {
    final page = _pages[pageId];
    if (page == null || !page.overlay) return false;
    if (page.parent == targetId) return false;
    final target = _pages[targetId];
    if (target == null) return false;
    return target.isBase;
  }

  /// 复刻 `_applyPageReparent`。
  bool reparent(String pageId, String newParentId) {
    final page = _pages[pageId];
    if (page == null) return false;
    final oldParent = page.parent;
    if (oldParent == newParentId) return false;
    final newParent = _pages[newParentId];
    if (newParent == null || !newParent.isBase) return false;
    if (!page.overlay) return false;

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

  /// 复刻 `_flattenNestedOverlayPages`。
  void flattenNestedOverlays(String rootId) {
    var changed = false;
    for (final page in _pages.values) {
      if (!page.overlay) continue;
      final parent = page.parent == null ? null : _pages[page.parent!];
      if (parent != null && parent.isBase) continue;
      page.parent = baseAncestorOf(page.id) ?? rootId;
      changed = true;
    }
    if (!changed) return;
    for (final base in _pages.values.where((p) => p.isBase)) {
      final children = _pages.values
          .where((p) => p.parent == base.id)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (var i = 0; i < children.length; i++) {
        children[i].sortOrder = i;
      }
    }
  }
}

PageTree buildTree() => PageTree([
      Page('root', overlay: false, sortOrder: 0),
      Page('base2', overlay: false, sortOrder: 1),
      Page('base3', overlay: false, sortOrder: 2),
      Page('ovA', parent: 'root', overlay: true, sortOrder: 0),
      Page('ovB', parent: 'root', overlay: true, sortOrder: 1),
      Page('ovC', parent: 'base2', overlay: true, sortOrder: 0),
    ]);

void main() {
  group('核心不变式：叠加页深度恒为 1', () {
    final t = buildTree();
    test('平级页深度 0', () {
      for (final id in ['root', 'base2', 'base3']) {
        expect(t.depth(id), 0);
      }
    });
    test('所有叠加页深度都是 1', () {
      for (final p in t.all.where((p) => p.overlay)) {
        expect(t.depth(p.id), 1, reason: '${p.id} 不该嵌套');
      }
    });
    test('每个叠加页的父级都是平级页', () {
      for (final p in t.all.where((p) => p.overlay)) {
        expect(t[p.parent!]!.isBase, isTrue);
      }
    });
  });

  group('叠加层不能变成子叠加层', () {
    final t = buildTree();
    test('叠加页不是合法落点', () {
      expect(t.canDrop('ovA', 'ovB'), isFalse);
      expect(t.canDrop('ovA', 'ovC'), isFalse);
      expect(t.canDrop('ovC', 'ovA'), isFalse);
    });

    test('换父候选里不含任何叠加页', () {
      for (final id in ['ovA', 'ovB', 'ovC']) {
        for (final c in t.reparentCandidates(id)) {
          expect(t[c]!.isBase, isTrue, reason: '$id 的候选 $c 是叠加页');
        }
      }
    });

    test('reparent 直接调用也拒绝叠加页作父级', () {
      final t2 = buildTree();
      expect(t2.reparent('ovA', 'ovB'), isFalse);
      expect(t2['ovA']!.parent, 'root', reason: '被拒后父级不该变');
    });

    test('拒绝后深度不变', () {
      final t2 = buildTree();
      t2.reparent('ovA', 'ovB');
      expect(t2.depth('ovA'), 1);
    });
  });

  group('换父 = 在平级页之间切换', () {
    test('叠加页可挂到其他任意平级页', () {
      final t = buildTree();
      expect(t.canDrop('ovA', 'base2'), isTrue);
      expect(t.canDrop('ovA', 'base3'), isTrue);
    });

    test('换父后仍挂在平级页下，深度不变', () {
      final t = buildTree();
      expect(t.reparent('ovA', 'base3'), isTrue);
      expect(t['ovA']!.parent, 'base3');
      expect(t.depth('ovA'), 1);
    });

    test('拖到当前父级是空操作', () {
      final t = buildTree();
      expect(t.canDrop('ovA', 'root'), isFalse);
      expect(t.reparent('ovA', 'root'), isFalse);
    });

    test('平级页不能被拖去换父（它没有父级）', () {
      final t = buildTree();
      expect(t.canDrop('base2', 'root'), isFalse);
      expect(t.canDrop('root', 'base2'), isFalse);
      expect(t.reparentCandidates('base2'), isEmpty);
    });
  });

  group('拖放判据与弹窗候选必须一致', () {
    // 两份实现漂移的话，会出现「拖放能放进去、弹窗里却查不到这个候选」。
    final t = buildTree();
    for (final id in ['ovA', 'ovB', 'ovC']) {
      test('$id 的候选集与可落点集相同', () {
        final candidates = t.reparentCandidates(id).toSet();
        final droppable =
            t.all.map((p) => p.id).where((x) => t.canDrop(id, x)).toSet();
        expect(droppable, candidates);
      });
    }
  });

  group('sortOrder 重排', () {
    test('移入新父级时排在末尾', () {
      final t = buildTree();
      // base2 下原有 ovC(0)，ovA 移入应为 1。
      expect(t.reparent('ovA', 'base2'), isTrue);
      expect(t['ovA']!.sortOrder, 1);
    });

    test('离开后原父级的兄弟补齐空位', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('other', overlay: false, sortOrder: 1),
        Page('c0', parent: 'root', overlay: true, sortOrder: 0),
        Page('c1', parent: 'root', overlay: true, sortOrder: 1),
        Page('c2', parent: 'root', overlay: true, sortOrder: 2),
      ]);
      expect(t.reparent('c1', 'other'), isTrue);
      expect(t['c0']!.sortOrder, 0);
      expect(t['c2']!.sortOrder, 1, reason: '不补位会留下空洞');
    });

    test('搬走后原父级的子列表顺序稳定', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('other', overlay: false, sortOrder: 1),
        Page('c0', parent: 'root', overlay: true, sortOrder: 0),
        Page('c1', parent: 'root', overlay: true, sortOrder: 1),
        Page('c2', parent: 'root', overlay: true, sortOrder: 2),
      ]);
      t.reparent('c0', 'other');
      expect(t.childrenOf('root').map((e) => e.id).toList(), ['c1', 'c2']);
    });
  });

  group('拍平早期实现产生的嵌套叠加页', () {
    // 这不是「兼容老卡」，是修正由错误实现（曾允许嵌套到 3 层）
    // 产生的非法结构。留着的话 canDrop 会拒绝一切落点，那些页面卡死。
    test('三层嵌套全部拍平到根平级页', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('a', parent: 'root', overlay: true),
        Page('b', parent: 'a', overlay: true),
        Page('c', parent: 'b', overlay: true),
      ]);
      t.flattenNestedOverlays('root');
      for (final id in ['a', 'b', 'c']) {
        expect(t[id]!.parent, 'root');
        expect(t.depth(id), 1);
      }
    });

    test('保留原本挂靠的平级页，不粗暴塞进根页', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('base2', overlay: false, sortOrder: 1),
        Page('a', parent: 'base2', overlay: true),
        Page('b', parent: 'a', overlay: true),
      ]);
      t.flattenNestedOverlays('root');
      expect(t['a']!.parent, 'base2');
      expect(t['b']!.parent, 'base2', reason: '应跟随 a 的平级祖先');
    });

    test('父级悬空的叠加页挂到根页，不丢页面', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('x', parent: 'ghost', overlay: true),
      ]);
      t.flattenNestedOverlays('root');
      expect(t['x']!.parent, 'root');
    });

    test('已合规的树不被改动', () {
      final t = buildTree();
      final before = {for (final p in t.all) p.id: p.parent};
      t.flattenNestedOverlays('root');
      for (final p in t.all) {
        expect(p.parent, before[p.id]);
      }
    });

    test('拍平后 sortOrder 无重复', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('a', parent: 'root', overlay: true, sortOrder: 0),
        Page('b', parent: 'a', overlay: true, sortOrder: 0),
        Page('c', parent: 'b', overlay: true, sortOrder: 0),
      ]);
      t.flattenNestedOverlays('root');
      final orders = t.childrenOf('root').map((e) => e.sortOrder).toList();
      expect(orders.toSet().length, orders.length, reason: '重复会让排序不稳定');
    });

    test('拍平后所有页面都能落点（不再卡死）', () {
      final t = PageTree([
        Page('root', overlay: false),
        Page('base2', overlay: false, sortOrder: 1),
        Page('a', parent: 'root', overlay: true),
        Page('b', parent: 'a', overlay: true),
      ]);
      t.flattenNestedOverlays('root');
      for (final p in t.all.where((p) => p.overlay)) {
        final droppable =
            t.all.map((x) => x.id).where((x) => t.canDrop(p.id, x));
        expect(droppable, isNotEmpty, reason: '${p.id} 无处可放');
      }
    });
  });

  group('整棵树保持有效', () {
    test('连续多次换父后深度恒为 1', () {
      final t = buildTree();
      t.reparent('ovA', 'base2');
      t.reparent('ovB', 'base3');
      t.reparent('ovC', 'root');
      for (final p in t.all.where((p) => p.overlay)) {
        expect(t.depth(p.id), 1);
        expect(t[p.parent!]!.isBase, isTrue);
      }
    });

    test('不可能成环（落点恒为无父级的平级页）', () {
      final t = buildTree();
      t.reparent('ovA', 'base2');
      for (final p in t.all) {
        var cur = p.id;
        final visited = <String>{};
        while (true) {
          expect(visited.add(cur), isTrue, reason: '$cur 所在链成环');
          final parent = t[cur]!.parent;
          if (parent == null) break;
          cur = parent;
        }
        expect(t[cur]!.isBase, isTrue, reason: '链尾必须是平级页');
      }
    });
  });
}
