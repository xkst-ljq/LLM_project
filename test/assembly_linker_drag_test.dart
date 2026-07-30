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

void main() {
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
