import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// 灵感池 4.1：拖出 PCB 自动后台化（双阈值滞回）。
///
/// 复刻 `character_assembly_page/logic.dart` 里的：
///   `_pcbOverflowDepth` / `_snapOffsetInsidePcb` / `_resolveBackstageDragOffset`
///   / `_commitBackstageDragResult`
///
/// 核心是「滞回」：脱离阈值(56) 与回吸阈值(24) 必须不相等，
/// 否则元件会在边界上每帧来回抖——越界一点点被吸回内壁，
/// 下一帧手指还在外面又越界。

const double kDetach = 56.0;
const double kReattach = 24.0;

/// 复刻 `_pcbOverflowDepth`。
double overflowDepth(Offset offset, Size size, Size pcb) {
  final double left = -offset.dx;
  final double top = -offset.dy;
  final double right = offset.dx + size.width - pcb.width;
  final double bottom = offset.dy + size.height - pcb.height;
  final double depth = math.max(math.max(left, top), math.max(right, bottom));
  return depth <= 0 ? 0.0 : depth;
}

/// 复刻 `_snapOffsetInsidePcb`。
Offset snapInside(Offset desired, Size size, Size pcb) {
  final double maxX = math.max(0.0, pcb.width - size.width);
  final double maxY = math.max(0.0, pcb.height - size.height);
  return Offset(
    desired.dx.clamp(0.0, maxX).toDouble(),
    desired.dy.clamp(0.0, maxY).toDouble(),
  );
}

const Set<String> kBackgroundCapable = {
  'text',
  'switch',
  'progress',
  'indicator',
  'input',
};

bool canBackstage(String type, {bool isComposite = false}) =>
    !isComposite && kBackgroundCapable.contains(type);

/// 复刻一次完整拖动的状态机。
class BackstageDrag {
  BackstageDrag({
    required this.pcb,
    required this.size,
    required this.type,
    bool startsBackstage = false,
    this.isComposite = false,
  }) : detached = startsBackstage;

  final Size pcb;
  final Size size;
  final String type;
  final bool isComposite;

  /// 本次拖动是否已脱离吸附。
  bool detached;

  /// 最近一次 update 的提示状态。null 表示不显示提示。
  bool? hintWillBackstage;

  int hapticCount = 0;

  /// 复刻 `_resolveBackstageDragOffset`，返回修正后的 offset。
  Offset update(Offset desired) {
    if (!canBackstage(type, isComposite: isComposite)) {
      hintWillBackstage = null;
      return desired;
    }
    final double depth = overflowDepth(desired, size, pcb);
    if (detached) {
      if (depth <= kReattach) detached = false;
    } else {
      if (depth >= kDetach) {
        detached = true;
        hapticCount++;
      }
    }
    hintWillBackstage = depth > 0 ? detached : null;
    return detached ? desired : snapInside(desired, size, pcb);
  }

  /// 复刻 `_commitBackstageDragResult`，返回最终是否为后台。
  bool commit() {
    hintWillBackstage = null;
    if (!canBackstage(type, isComposite: isComposite)) return false;
    final result = detached;
    detached = false;
    return result;
  }
}

void main() {
  const pcb = Size(360, 800);
  const size = Size(80, 30);

  group('越界深度计算', () {
    test('完全在内返回 0', () {
      expect(overflowDepth(const Offset(100, 100), size, pcb), 0.0);
    });

    test('刚好贴住右内壁返回 0', () {
      expect(overflowDepth(const Offset(280, 100), size, pcb), 0.0);
    });

    test('右侧越界取右边距离', () {
      expect(overflowDepth(const Offset(320, 100), size, pcb), 40.0);
    });

    test('左侧越界取负 offset', () {
      expect(overflowDepth(const Offset(-30, 100), size, pcb), 30.0);
    });

    test('上方越界', () {
      expect(overflowDepth(const Offset(100, -18), size, pcb), 18.0);
    });

    test('下方越界', () {
      expect(overflowDepth(const Offset(100, 790), size, pcb), 20.0);
    });

    test('两个方向同时越界取最深的那一边', () {
      // 左越界 30，上越界 70 —— 应取 70。
      expect(overflowDepth(const Offset(-30, -70), size, pcb), 70.0);
    });

    test('PCB 比元件还小时不抛异常', () {
      const tiny = Size(20, 20);
      expect(() => overflowDepth(const Offset(0, 0), size, tiny),
          returnsNormally);
      expect(() => snapInside(const Offset(50, 50), size, tiny),
          returnsNormally);
      expect(snapInside(const Offset(50, 50), size, tiny), Offset.zero);
    });
  });

  group('吸附带：未越过脱离阈值时被拉回内壁', () {
    test('越界 10px 被夹回右内壁', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      expect(d.update(const Offset(290, 100)), const Offset(280, 100));
      expect(d.detached, isFalse);
    });

    test('越界 55px（阈值下 1px）仍被夹住', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      expect(d.update(const Offset(335, 100)), const Offset(280, 100));
      expect(d.detached, isFalse);
    });

    test('越界正好 56px 脱离，跟手自由拖动', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      expect(d.update(const Offset(336, 100)), const Offset(336, 100));
      expect(d.detached, isTrue);
    });

    test('脱离瞬间震动一次，之后不重复震', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(336, 100));
      d.update(const Offset(360, 100));
      d.update(const Offset(400, 100));
      expect(d.hapticCount, 1);
    });

    test('左上方向同样吸附', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      expect(d.update(const Offset(-20, -20)), Offset.zero);
      expect(d.detached, isFalse);
    });
  });

  group('滞回：进出用两条不同的线', () {
    test('拖回时 depth=30 仍保持脱离（大于回吸阈值 24）', () {
      final d = BackstageDrag(
          pcb: pcb, size: size, type: 'text', startsBackstage: true);
      final result = d.update(const Offset(310, 100)); // depth = 30
      expect(d.detached, isTrue);
      expect(result, const Offset(310, 100), reason: '未回吸则跟手');
    });

    test('拖回到 depth=24 才重新吸附', () {
      final d = BackstageDrag(
          pcb: pcb, size: size, type: 'text', startsBackstage: true);
      final result = d.update(const Offset(304, 100)); // depth = 24
      expect(d.detached, isFalse);
      expect(result, const Offset(280, 100), reason: '回吸后夹到内壁');
    });

    test('脱离阈值必须大于回吸阈值，否则会抖', () {
      expect(kDetach, greaterThan(kReattach));
    });

    test('在脱离点附近来回抖动只翻转一次状态', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      int flips = 0;
      bool? prev;
      for (int i = 0; i < 200; i++) {
        // 围绕 depth=56 上下抖 ±8。
        final x = 336.0 + 8 * math.sin(i / 3);
        d.update(Offset(x, 100));
        if (prev != null && d.detached != prev) flips++;
        prev = d.detached;
      }
      expect(flips, 0, reason: '首帧就已脱离，之后 depth 最低 48 > 24，不该回弹');
    });

    test('完整来回：出去再回来，状态正确复位', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      for (double x = 280; x <= 420; x += 10) {
        d.update(Offset(x, 100));
      }
      expect(d.detached, isTrue);
      for (double x = 420; x >= 280; x -= 10) {
        d.update(Offset(x, 100));
      }
      expect(d.detached, isFalse);
      expect(d.commit(), isFalse);
    });
  });

  group('白名单', () {
    for (final t in kBackgroundCapable) {
      test('$t 允许后台化', () => expect(canBackstage(t), isTrue));
    }

    test('button 不在白名单，拖出去不受阈值约束', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'button');
      // 原样返回：逻辑件 / 普通件本来就允许摆在 PCB 外。
      expect(d.update(const Offset(600, 100)), const Offset(600, 100));
      expect(d.commit(), isFalse);
    });

    test('surface 不在白名单', () => expect(canBackstage('surface'), isFalse));

    test('复合件永远不许后台化（产品规则 3.1）', () {
      expect(canBackstage('text', isComposite: true), isFalse);
      final d = BackstageDrag(
          pcb: pcb, size: size, type: 'text', isComposite: true);
      d.update(const Offset(600, 100));
      expect(d.commit(), isFalse);
    });

    test('白名单与 Studio 完全一致', () {
      // 跨编辑器契约：两边不一致会出现「Studio 能标 Assembly 不能」。
      expect(kBackgroundCapable,
          {'text', 'switch', 'progress', 'indicator', 'input'});
    });
  });

  group('落定结果', () {
    test('拖到后台区松手 → 标记为后台', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(400, 100));
      expect(d.commit(), isTrue);
    });

    test('停在吸附带松手 → 不标记，且位置已被夹回内壁', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      final last = d.update(const Offset(320, 100));
      expect(last, const Offset(280, 100));
      expect(d.commit(), isFalse);
    });

    test('已是后台的元件轻微挪动仍保持后台', () {
      final d = BackstageDrag(
          pcb: pcb, size: size, type: 'text', startsBackstage: true);
      d.update(const Offset(500, 120));
      expect(d.commit(), isTrue);
    });

    test('已是后台的元件被拖回画布内 → 取消后台', () {
      final d = BackstageDrag(
          pcb: pcb, size: size, type: 'text', startsBackstage: true);
      d.update(const Offset(150, 200));
      expect(d.commit(), isFalse);
    });

    test('commit 后状态复位，不泄漏到下一次拖动', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(400, 100));
      expect(d.commit(), isTrue);
      expect(d.detached, isFalse, reason: '不复位会导致下次刚起手就判后台');
      // 第二次拖动只挪一点点，不该变后台。
      expect(d.update(const Offset(100, 100)), const Offset(100, 100));
      expect(d.commit(), isFalse);
    });
  });

  group('拖动提示', () {
    test('PCB 内部移动不显示提示', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(100, 100));
      expect(d.hintWillBackstage, isNull);
    });

    test('吸附带内提示「回到画布」', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(300, 100));
      expect(d.hintWillBackstage, isFalse);
    });

    test('后台区提示「转为后台」', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(400, 100));
      expect(d.hintWillBackstage, isTrue);
    });

    test('非白名单元件从不显示提示', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'button');
      d.update(const Offset(600, 100));
      expect(d.hintWillBackstage, isNull);
    });

    test('commit 后提示清空', () {
      final d = BackstageDrag(pcb: pcb, size: size, type: 'text');
      d.update(const Offset(400, 100));
      d.commit();
      expect(d.hintWillBackstage, isNull);
    });
  });

  group('手动切换入口（兜底）', () {
    test('从后台移回时必须吸附回内壁，否则作者看不到组件', () {
      // 元件停在 PCB 外 (500, 900)，取消后台后应被拉回可视范围。
      const outside = Offset(500, 900);
      final back = snapInside(outside, size, pcb);
      expect(back, const Offset(280, 770));
      expect(overflowDepth(back, size, pcb), 0.0);
    });

    test('本来就在内的元件取消后台时位置不变', () {
      const inside = Offset(100, 200);
      expect(snapInside(inside, size, pcb), inside);
    });
  });
}
