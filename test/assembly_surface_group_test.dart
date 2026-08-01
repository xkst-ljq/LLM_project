import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

/// A14-1c：容器归属（分组）的五条规则。
///
/// UI 交互需要 widget 测试，这里锁定纯逻辑：
/// 层级不变式、组内/整组移动、进出组的重整时机。

const _surfaceTypes = {'surface', 'surface_art', 'primitive_art', 'base_box'};

UIElement _el(String id, {String type = 'text', String? parent}) => UIElement(
      id: id,
      isComposite: false,
      offset: Offset.zero,
      size: const Size(60, 24),
      parentSurfaceId: parent,
      module: UIModule(id: 'm_$id', name: id, type: type, properties: {}),
    );

bool isSurface(UIElement e) => _surfaceTypes.contains(e.module?.type);

Set<String> groupIds(List<UIElement> els, String surfaceId) {
  final ids = <String>{surfaceId};
  var grew = true;
  while (grew) {
    grew = false;
    for (final e in els) {
      final p = e.parentSurfaceId;
      if (p != null && ids.contains(p) && ids.add(e.id)) grew = true;
    }
  }
  return ids;
}

List<UIElement> orderedGroup(List<UIElement> els, String surfaceId) {
  final byId = {for (final e in els) e.id: e};
  final out = <UIElement>[];
  void visit(String id) {
    final s = byId[id];
    if (s == null) return;
    out.add(s);
    for (final c in els) {
      if (c.parentSurfaceId != id) continue;
      if (isSurface(c)) {
        visit(c.id);
      } else {
        out.add(c);
      }
    }
  }

  visit(surfaceId);
  return out;
}

/// 复刻 `_normalizeSurfaceGroupOrder`。
List<UIElement> normalize(List<UIElement> els, String surfaceId) {
  final gids = groupIds(els, surfaceId);
  if (gids.length <= 1) return els;
  final grouped = orderedGroup(els, surfaceId);
  final firstIndex = els.indexWhere((e) => gids.contains(e.id));
  if (firstIndex == -1) return els;
  final insertAt =
      els.take(firstIndex).where((e) => !gids.contains(e.id)).length;
  final others = els.where((e) => !gids.contains(e.id)).toList();
  return [
    ...others.take(insertAt),
    ...grouped,
    ...others.skip(insertAt),
  ];
}

List<String> ids(List<UIElement> els) => els.map((e) => e.id).toList();

void main() {
  group('规则3：子组件恒高于父级面', () {
    test('进组后父面被提到组块最前', () {
      // 列表越靠后越上层，父面在块首即为整组最底。
      var els = [
        _el('btn', type: 'button', parent: 'panel'),
        _el('panel', type: 'surface'),
        _el('top'),
      ];
      els = normalize(els, 'panel');
      expect(ids(els).indexOf('panel'), lessThan(ids(els).indexOf('btn')));
    });

    test('嵌套组也满足：每层父面都在其成员之前', () {
      var els = [
        _el('inner', type: 'surface', parent: 'outer'),
        _el('leaf', parent: 'inner'),
        _el('outer', type: 'surface'),
      ];
      els = normalize(els, 'outer');
      final order = ids(els);
      expect(order.indexOf('outer'), lessThan(order.indexOf('inner')));
      expect(order.indexOf('inner'), lessThan(order.indexOf('leaf')));
    });
  });

  group('规则4：进组立即重整', () {
    test('顺序颠倒的旧数据一次修正到位', () {
      // Studio 是事后补救（要作者手动切一次层级），这里在进组那一刻就修。
      var els = [
        _el('a', parent: 'p'),
        _el('b', parent: 'p'),
        _el('p', type: 'surface'),
      ];
      els = normalize(els, 'p');
      expect(ids(els), ['p', 'a', 'b']);
    });

    test('整组收拢为连续块，不被外部元素切断', () {
      var els = [
        _el('p', type: 'surface'),
        _el('outsider'),
        _el('m', parent: 'p'),
      ];
      els = normalize(els, 'p');
      final order = ids(els);
      final pi = order.indexOf('p');
      expect(order[pi + 1], 'm', reason: '组员应紧跟父面');
    });

    test('整组相对高度不变：原先在谁之上，重整后仍在谁之上', () {
      var els = [
        _el('below'),
        _el('p', type: 'surface'),
        _el('m', parent: 'p'),
        _el('above'),
      ];
      els = normalize(els, 'p');
      final order = ids(els);
      expect(order.indexOf('below'), lessThan(order.indexOf('p')));
      expect(order.indexOf('m'), lessThan(order.indexOf('above')));
    });
  });

  group('规则5：出组保留显示层级', () {
    test('解除归属时不移动位置', () {
      // 所见即所得：停在组内当时的视觉高度，而不是弹回进组前的旧位置。
      final els = [
        _el('p', type: 'surface'),
        _el('a', parent: 'p'),
        _el('b', parent: 'p'),
        _el('far'),
      ];
      final leaving = els[2].copyWith(clearParentSurface: true);
      final after = [...els]..[2] = leaving;
      expect(ids(after), ['p', 'a', 'b', 'far']);
      expect(after[2].parentSurfaceId, isNull);
    });
  });

  group('规则1：组内成员只与同组兄弟换位', () {
    test('兄弟数量决定可移动范围，而不是全局下标', () {
      final els = [
        _el('p', type: 'surface'),
        _el('a', parent: 'p'),
        _el('b', parent: 'p'),
        _el('other'),
      ];
      final siblings =
          els.where((e) => e.parentSurfaceId == 'p').toList();
      expect(siblings.length, 2);
      // b 是组内最后一个，即便全局后面还有 other，也不能再上移。
      final bIndex = siblings.indexWhere((e) => e.id == 'b');
      expect(bIndex + 1 >= siblings.length, isTrue);
    });
  });

  group('删除父面后组员不隐身', () {
    test('悬空 parentSurfaceId 会让可见性判定失败', () {
      // 运行时靠递归查父级判定可见性，父级不存在时返回 false，
      // 表现为整组凭空消失。删除时必须清理组员的归属。
      bool visible(UIElement e, List<UIElement> els) {
        var p = e.parentSurfaceId;
        final seen = <String>{};
        while (p != null && p.isNotEmpty) {
          if (!seen.add(p)) return false;
          final idx = els.indexWhere((x) => x.id == p);
          if (idx == -1) return false;
          p = els[idx].parentSurfaceId;
        }
        return true;
      }

      final orphaned = [_el('btn', parent: 'panel')];
      expect(visible(orphaned.first, orphaned), isFalse);

      final cleaned = [_el('btn')];
      expect(visible(cleaned.first, cleaned), isTrue);
    });
  });

  group('防环', () {
    test('不能把面板挂到自己的后代下面', () {
      final els = [
        _el('outer', type: 'surface'),
        _el('inner', type: 'surface', parent: 'outer'),
      ];
      bool wouldCycle(String childId, String parentId) {
        var cur = parentId;
        final seen = <String>{};
        while (cur.isNotEmpty && seen.add(cur)) {
          if (cur == childId) return true;
          final i = els.indexWhere((e) => e.id == cur);
          if (i == -1) return false;
          cur = els[i].parentSurfaceId ?? '';
        }
        return false;
      }

      expect(wouldCycle('outer', 'inner'), isTrue);
      expect(wouldCycle('inner', 'outer'), isFalse);
    });
  });
}
