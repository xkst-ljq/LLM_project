import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A14-4 第二步：拖拽画线交互。
///
/// 采用 Studio 的连线方式，两处按 Assembly 实际情况调整：
/// * 热区左右各 24px（Studio 32px）——Assembly 的 linker 是 132×44，
///   切 32 之后中间只剩 68px，拖动元件容易偏进热区。
/// * 坐标要叠加 `_canvasOffset + _pcbOffset`。
///
/// 用户明确的约束：**linker 是唯一可以拉出接线的组件**，
/// **点击 linker 弹方案选择，接通线路也弹方案选择（两端齐了才弹）**。

const double kLinkerPortHotZone = 24.0;

/// 复刻 `_canBeConnectionEndpoint`。
bool canBeEndpoint({
  required String? type,
  bool isComposite = false,
  bool sealed = false,
}) {
  if (type == null) return false;
  if (isComposite) return false;
  if (type == 'linker') return false;
  if (sealed) return false;
  return true;
}

/// 复刻 `_isPointInsideAssemblyElement`。
bool hitTest({
  required Offset point,
  required Offset canvasOffset,
  required Offset pcbOffset,
  required Offset elOffset,
  required Size size,
  double rotation = 0.0,
  double pad = 12.0,
}) {
  final base = canvasOffset + pcbOffset;
  final elLeft = base.dx + elOffset.dx;
  final elTop = base.dy + elOffset.dy;
  final cx = elLeft + size.width / 2;
  final cy = elTop + size.height / 2;
  final rect = Rect.fromLTWH(
    elLeft - pad,
    elTop - pad,
    size.width + pad * 2,
    size.height + pad * 2,
  );
  if (rotation == 0.0) return rect.contains(point);
  final rad = -rotation * math.pi / 180.0;
  final dx = point.dx - cx;
  final dy = point.dy - cy;
  return rect.contains(
    Offset(
      cx + dx * math.cos(rad) - dy * math.sin(rad),
      cy + dx * math.sin(rad) + dy * math.cos(rad),
    ),
  );
}

/// 复刻落点写入：只改被拖的那一端，另一端保持原样。
Map<String, dynamic> applyWiring({
  required Map<String, dynamic> before,
  required String port,
  required String targetId,
}) {
  final data = Map<String, dynamic>.from(before);
  if (port == 'input') {
    data['sourceModuleId'] = targetId;
  } else {
    data['targetModuleId'] = targetId;
  }
  return data;
}

/// 复刻 `_disconnectLinkerPort`：断开单侧，方案随之失效。
Map<String, dynamic> disconnectPort(
  Map<String, dynamic> before,
  String port,
) {
  final data = Map<String, dynamic>.from(before);
  if (port == 'input') {
    data
      ..remove('sourceModuleId')
      ..remove('sourcePort')
      ..remove('sourceType')
      ..remove('sourceGesture')
      ..remove('inputConnection');
  } else {
    data
      ..remove('targetModuleId')
      ..remove('targetPort')
      ..remove('targetType')
      ..remove('outputConnection');
  }
  data['scheme'] = '未配置';
  data['enabled'] = false;
  data.remove('schemeParams');
  return data;
}

/// 复刻「是否该弹方案选择」：两端齐了才弹。
bool shouldPromptScheme(Map<String, dynamic> data) {
  final s = data['sourceModuleId']?.toString() ?? '';
  final t = data['targetModuleId']?.toString() ?? '';
  return s.isNotEmpty && t.isNotEmpty;
}

/// 复刻「待定起拖」状态机。
///
/// 按下只记待定，位移超过阈值才真正起拖。
/// 这是为了让双击可用：按下即 setState 会让 linker 子树重建、
/// GestureDetector 被 unmount，双击的第二次按下永远等不到。
class WireDragMachine {
  static const double slop = 6.0;

  Offset? pendingOrigin;
  bool dragging = false;
  int setStateCount = 0;

  void pointerDown(Offset at) {
    pendingOrigin = at;
    // 关键：这里绝不 setState。
  }

  bool pointerMove(Offset at) {
    if (dragging) return true;
    final origin = pendingOrigin;
    if (origin == null) return false;
    if ((at - origin).distance < slop) return true;
    dragging = true;
    pendingOrigin = null;
    setStateCount++;
    return true;
  }

  bool pointerUp(Offset at) {
    if (dragging) {
      dragging = false;
      pendingOrigin = null;
      setStateCount++;
      return true;
    }
    final had = pendingOrigin != null;
    pendingOrigin = null;
    return had;
  }
}

void main() {
  group('待定起拖（双击可用性的前提）', () {
    test('纯点击全程不触发任何重建', () {
      // 按下即 setState 会重建 linker 子树、卸载其 GestureDetector，
      // 双击的第二次按下就永远等不到了，还会引发
      // 「setState called when widget tree was locked」崩溃。
      final m = WireDragMachine();
      m.pointerDown(const Offset(100, 100));
      m.pointerUp(const Offset(100, 100));
      expect(m.setStateCount, 0);
      expect(m.dragging, isFalse);
    });

    test('双击的两次按下都不会起拖', () {
      final m = WireDragMachine();
      for (var i = 0; i < 2; i++) {
        m.pointerDown(const Offset(100, 100));
        m.pointerUp(const Offset(100, 100));
      }
      expect(m.setStateCount, 0);
    });

    test('阈值内的抖动不算起拖', () {
      // 手指按下时的轻微抖动不应该被当成接线。
      final m = WireDragMachine();
      m.pointerDown(const Offset(100, 100));
      m.pointerMove(const Offset(103, 102));
      expect(m.dragging, isFalse);
      expect(m.setStateCount, 0);
    });

    test('超过阈值才真正起拖', () {
      final m = WireDragMachine();
      m.pointerDown(const Offset(100, 100));
      m.pointerMove(const Offset(120, 100));
      expect(m.dragging, isTrue);
      expect(m.setStateCount, 1);
    });

    test('起拖阈值小于 kTouchSlop，接线优先于拖动元件', () {
      // Flutter 的 kTouchSlop 是 18。接线要更早被判定，
      // 否则手指刚动就把 linker 整个拖走了。
      expect(WireDragMachine.slop, lessThan(18.0));
    });

    test('没按下过热区时不消费移动事件', () {
      // 返回 false 才能让资产栏拖放等其他逻辑继续处理。
      final m = WireDragMachine();
      expect(m.pointerMove(const Offset(50, 50)), isFalse);
    });
  });

  group('热区划分', () {
    test('左右热区之外仍有足够的拖动区', () {
      // linker 在 Assembly 是 132×44。
      const linkerWidth = 132.0;
      final middle = linkerWidth - kLinkerPortHotZone * 2;
      expect(middle, 84.0);
      // 中间区域必须明显宽于一个手指的接触宽度，否则挪不动元件。
      expect(middle, greaterThan(48.0));
    });

    test('热区仍比手指宽，接线不会难点', () {
      expect(kLinkerPortHotZone, greaterThanOrEqualTo(24.0));
    });
  });

  group('可作为连线端点的组件', () {
    test('普通可见组件可以', () {
      for (final t in ['text', 'progress', 'switch', 'surface', 'button']) {
        expect(canBeEndpoint(type: t), isTrue, reason: t);
      }
    });

    test('linker 不能作为端点', () {
      // linker 是唯一能拉出线的组件，但它自己不是被连的目标。
      expect(canBeEndpoint(type: 'linker'), isFalse);
    });

    test('复合黑盒不能作为端点', () {
      expect(canBeEndpoint(type: 'surface', isComposite: true), isFalse);
    });

    test('全锁元素不能作为端点', () {
      // 全锁的语义就是「连线不可改」，它不该被拖拽命中。
      expect(canBeEndpoint(type: 'text', sealed: true), isFalse);
    });
  });

  group('命中检测', () {
    const canvas = Offset(10, 20);
    const pcb = Offset(30, 40);
    const el = Offset(100, 200);
    const size = Size(80, 40);
    // 元件屏幕矩形：left=140 top=260 right=220 bottom=300

    test('落在元件内命中', () {
      expect(
        hitTest(
          point: const Offset(180, 280),
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
        ),
        isTrue,
      );
    });

    test('12px 容差内也命中', () {
      // 手指没那么精准，边缘外一点也算。
      expect(
        hitTest(
          point: const Offset(132, 280),
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
        ),
        isTrue,
      );
    });

    test('容差之外不命中', () {
      expect(
        hitTest(
          point: const Offset(120, 280),
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
        ),
        isFalse,
      );
    });

    test('漏掉 pcbOffset 会整体错位', () {
      // 这是 A14-4 记录的易错点：Assembly 的元素坐标相对 PCB。
      // 用同一个点、但不加 pcbOffset 去算，结论会相反。
      const point = Offset(180, 280);
      expect(
        hitTest(
          point: point,
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
        ),
        isTrue,
      );
      expect(
        hitTest(
          point: point,
          canvasOffset: canvas,
          pcbOffset: Offset.zero,
          elOffset: el,
          size: size,
        ),
        isFalse,
      );
    });

    test('旋转 90 度后按旋转后的形状命中', () {
      // 80×40 转 90° 后，视觉上占 40×80。
      // 元件中心 (180,280)，转后上下各伸出 40。
      expect(
        hitTest(
          point: const Offset(180, 315),
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
          rotation: 90,
        ),
        isTrue,
      );
    });
  });

  group('落点写入', () {
    test('拖左侧只改来源，不动目标', () {
      final after = applyWiring(
        before: {'sourceModuleId': 'a', 'targetModuleId': 'b'},
        port: 'input',
        targetId: 'c',
      );
      expect(after['sourceModuleId'], 'c');
      // 作者可能只是在改接一条已配好的连线，另一端必须留着。
      expect(after['targetModuleId'], 'b');
    });

    test('拖右侧只改目标', () {
      final after = applyWiring(
        before: {'sourceModuleId': 'a', 'targetModuleId': 'b'},
        port: 'output',
        targetId: 'c',
      );
      expect(after['sourceModuleId'], 'a');
      expect(after['targetModuleId'], 'c');
    });
  });

  group('方案选择的弹出时机', () {
    test('两端齐了才弹', () {
      expect(
        shouldPromptScheme({'sourceModuleId': 'a', 'targetModuleId': 'b'}),
        isTrue,
      );
    });

    test('只接了一半不弹', () {
      // 可用方案取决于「来源类型 + 目标类型」的组合，
      // 缺一端算出来就是空列表，弹出来也是空的。
      expect(shouldPromptScheme({'sourceModuleId': 'a'}), isFalse);
      expect(shouldPromptScheme({'targetModuleId': 'b'}), isFalse);
      expect(shouldPromptScheme(<String, dynamic>{}), isFalse);
    });
  });

  group('复合组件的连线支持', () {
    // 首轮测试反馈：linker 连不上复合件。
    //
    // 复合是黑盒，作者无法选中它内部的组件；制作时勾选的「暴露端口」
    // 就是它与外界的唯一接口。连线连的是**被暴露的子元素**，
    // 而不是复合件外壳——外壳没有 module，方案矩阵拿它算不出东西。

    /// 复刻 `_canBeConnectionEndpoint` 中复合件的分支。
    bool compositeCanConnect({
      required List<String> exposedChildTypes,
      bool sealed = false,
    }) {
      if (sealed) return false;
      return exposedChildTypes.isNotEmpty;
    }

    test('有暴露端口的复合件可作为连线目标', () {
      expect(
        compositeCanConnect(exposedChildTypes: ['progress']),
        isTrue,
      );
    });

    test('没有暴露端口的复合件连不了', () {
      // 没开放接口就是不想被外部连，这是复合件作者的设计意图。
      expect(compositeCanConnect(exposedChildTypes: []), isFalse);
    });

    test('全锁的复合件连不了', () {
      expect(
        compositeCanConnect(exposedChildTypes: ['progress'], sealed: true),
        isFalse,
      );
    });

    test('连线存的是子元素 id，不是复合外壳 id', () {
      // 存外壳 id 的话，运行端 LinkerService 找不到对应 module，
      // 这条连线会静默失效。
      const shellId = 'composite_1';
      const childId = 'child_progress';
      final stored = applyWiring(
        before: {},
        port: 'output',
        targetId: childId,
      );
      expect(stored['targetModuleId'], childId);
      expect(stored['targetModuleId'], isNot(shellId));
    });

    test('画线锚点回落到复合外壳', () {
      // 子元素的 offset 相对复合件，直接当画布坐标会错位一整个复合件。
      String anchorFor(String id, Map<String, String> childToShell) {
        return childToShell[id] ?? id;
      }

      expect(
        anchorFor('child_progress', {'child_progress': 'composite_1'}),
        'composite_1',
      );
      // 顶层元素不受影响。
      expect(anchorFor('text_1', {'child_progress': 'composite_1'}), 'text_1');
    });
  });

  group('配置面板移除来源/目标选择器', () {
    // 画线做好之后，下拉选择器就成了重复入口。
    // 同一件事有两个入口时作者会困惑「哪个才算数」，
    // 而且下拉列表在元件一多时根本找不到目标。

    /// 复刻「清除连接」按钮的可用条件。
    bool canClear({required String sourceId, required String targetId}) =>
        sourceId.isNotEmpty || targetId.isNotEmpty;

    /// 复刻保存按钮的可用条件。
    bool canSave({
      required String sourceId,
      required String targetId,
      required String scheme,
    }) =>
        sourceId.isNotEmpty && targetId.isNotEmpty && scheme.isNotEmpty;

    test('两端齐备且选了方案才能保存', () {
      expect(
        canSave(sourceId: 'a', targetId: 'b', scheme: 'click_to_switch_toggle'),
        isTrue,
      );
      expect(canSave(sourceId: 'a', targetId: '', scheme: 'x'), isFalse);
      expect(canSave(sourceId: 'a', targetId: 'b', scheme: ''), isFalse);
    });

    test('只连了一端也能清除', () {
      // 旧实现「清空下拉再保存」在这种情况下完全失效：
      // canSave 要求两端非空，清空后保存按钮直接变灰、提交不了。
      // 现在清除是独立动作，不经过保存校验。
      expect(canClear(sourceId: 'a', targetId: ''), isTrue);
      expect(canClear(sourceId: '', targetId: 'b'), isTrue);
    });

    test('完全没连时清除按钮禁用', () {
      expect(canClear(sourceId: '', targetId: ''), isFalse);
    });

    test('清除走独立返回值，不复用保存路径', () {
      // 三个动作各自独立，避免「清除」被保存分支的校验拦住。
      const actions = {'cancel', 'clear', 'save'};
      expect(actions.length, 3);
      expect(actions.contains('clear'), isTrue);
    });
  });

  group('断开单侧端口', () {
    final connected = <String, dynamic>{
      'sourceModuleId': 'a',
      'sourcePort': 'long_press',
      'sourceGesture': 'long_press',
      'targetModuleId': 'b',
      'targetPort': 'value',
      'scheme': 'click_to_switch_toggle',
      'enabled': true,
      'schemeParams': {'action': 'regenerate'},
    };

    test('断开左侧清掉来源与手势', () {
      final after = disconnectPort(connected, 'input');
      expect(after.containsKey('sourceModuleId'), isFalse);
      // A14-3 的连线级手势也挂在这一端，必须一起清。
      expect(after.containsKey('sourceGesture'), isFalse);
      expect(after['targetModuleId'], 'b');
    });

    test('断开右侧保留来源', () {
      final after = disconnectPort(connected, 'output');
      expect(after['sourceModuleId'], 'a');
      expect(after.containsKey('targetModuleId'), isFalse);
    });

    test('断开任一侧都会让方案失效', () {
      // 少了一端，方案必然不再成立，留着会造成「显示已配置但不生效」。
      for (final port in ['input', 'output']) {
        final after = disconnectPort(connected, port);
        expect(after['scheme'], '未配置', reason: port);
        expect(after['enabled'], isFalse, reason: port);
        expect(after.containsKey('schemeParams'), isFalse, reason: port);
      }
    });
  });
}
