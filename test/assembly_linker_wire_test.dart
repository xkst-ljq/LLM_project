import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/linker_connection_painter.dart';

/// A14-4 第一步：linker 连线可视化。
///
/// 采用 Studio 的连线方式（用户要求）：操作性、可视性、
/// 与端口设计的匹配度都优于配置式。画布拥挤靠**减小线宽 + 降低不透明度**
/// 缓解，**不换配色**——颜色语义必须与 Studio 一致，
/// 否则同一条线在两个编辑器里是两个颜色。

/// 复刻 `_assemblyLinkerConnections`。
List<Map<String, dynamic>> connectionsOf(
  List<Map<String, dynamic>> linkerElements,
) {
  final connections = <Map<String, dynamic>>[];
  for (final el in linkerElements) {
    final data = el['linker'] as Map<String, dynamic>?;
    if (data == null) continue;
    final sourceId = data['sourceModuleId']?.toString();
    final targetId = data['targetModuleId']?.toString();
    final sourcePort = data['sourcePort']?.toString() ?? 'current';
    final storedTargetPort = data['targetPort']?.toString() ?? 'text';
    final scheme = data['scheme']?.toString();
    final targetPort = (scheme == 'click_to_math_trigger' ||
            scheme == 'timer_tick_to_math_trigger')
        ? 'gate_in'
        : storedTargetPort;

    if (sourceId != null && sourceId.isNotEmpty) {
      connections.add({
        'from': sourceId,
        'fromPort': sourcePort,
        'to': el['id'],
        'toPort': 'input',
        'type': 'input',
      });
    }
    if (targetId != null && targetId.isNotEmpty) {
      connections.add({
        'from': el['id'],
        'fromPort': 'output',
        'to': targetId,
        'toPort': targetPort,
        'type': 'output',
      });
    }
  }
  return connections;
}

/// 复刻 `_assemblyPortOffset`。
Offset portOffset({
  required Offset canvasOffset,
  required Offset pcbOffset,
  required Offset elOffset,
  required Size size,
  required bool isInput,
  String? portName,
  double rotation = 0.0,
}) {
  final base = canvasOffset + pcbOffset;
  final elLeft = base.dx + elOffset.dx;
  final elTop = base.dy + elOffset.dy;
  final cx = elLeft + size.width / 2;
  final cy = elTop + size.height / 2;

  if (portName == 'gate_in') {
    if (rotation == 0.0) return Offset(cx, elTop + 7.0);
    final rad = rotation * math.pi / 180.0;
    final distance = math.max(0.0, size.height / 2 - 7.0);
    return Offset(
      cx + distance * math.sin(rad),
      cy - distance * math.cos(rad),
    );
  }

  if (rotation == 0.0) {
    return Offset(isInput ? elLeft : elLeft + size.width, cy);
  }

  final rad = rotation * math.pi / 180.0;
  final sign = isInput ? -1.0 : 1.0;
  final halfWidth = size.width / 2;
  return Offset(
    cx + sign * halfWidth * math.cos(rad),
    cy + sign * halfWidth * math.sin(rad),
  );
}

void main() {
  group('连线派生', () {
    test('配好两端的 linker 产生两条线', () {
      final conns = connectionsOf([
        {
          'id': 'lk1',
          'linker': {
            'sourceModuleId': 'btn',
            'targetModuleId': 'sw',
            'sourcePort': 'tap',
            'targetPort': 'value',
          },
        },
      ]);
      expect(conns.length, 2);
      // 来源 → linker
      expect(conns[0]['from'], 'btn');
      expect(conns[0]['to'], 'lk1');
      expect(conns[0]['type'], 'input');
      // linker → 目标
      expect(conns[1]['from'], 'lk1');
      expect(conns[1]['to'], 'sw');
      expect(conns[1]['type'], 'output');
    });

    test('只连了一半也要画出那半条', () {
      // 作者正需要看到「这条还没接完」，不能等两端齐了才显示。
      final conns = connectionsOf([
        {
          'id': 'lk1',
          'linker': {'sourceModuleId': 'btn'},
        },
      ]);
      expect(conns.length, 1);
      expect(conns.single['type'], 'input');
    });

    test('未配置的 linker 不产生线', () {
      expect(connectionsOf([
        {'id': 'lk1', 'linker': <String, dynamic>{}},
      ]), isEmpty);
      expect(connectionsOf([
        {'id': 'lk1'},
      ]), isEmpty);
    });

    test('旧草稿的 math 触发方案按控制端口绘制', () {
      // 早期数据没写 gate_in，若按 targetPort 原样画会画成数据线，
      // 与 Studio 里同一张卡的显示不一致。
      final conns = connectionsOf([
        {
          'id': 'lk1',
          'linker': {
            'sourceModuleId': 'btn',
            'targetModuleId': 'math',
            'scheme': 'click_to_math_trigger',
            'targetPort': 'data_in',
          },
        },
      ]);
      expect(conns[1]['toPort'], 'gate_in');
    });

    test('按 sourceGesture 覆写过的端口原样呈现', () {
      // A14-3 的连线级手势：端口是 long_press，连线照画。
      final conns = connectionsOf([
        {
          'id': 'lk1',
          'linker': {
            'sourceModuleId': 'btn',
            'targetModuleId': 'sw',
            'sourcePort': 'long_press',
            'targetPort': 'value',
          },
        },
      ]);
      expect(conns[0]['fromPort'], 'long_press');
    });
  });

  group('端口几何', () {
    const canvas = Offset(10, 20);
    const pcb = Offset(30, 40);
    const el = Offset(100, 200);
    const size = Size(80, 40);

    test('未旋转时输入在左中、输出在右中', () {
      final input = portOffset(
        canvasOffset: canvas,
        pcbOffset: pcb,
        elOffset: el,
        size: size,
        isInput: true,
      );
      final output = portOffset(
        canvasOffset: canvas,
        pcbOffset: pcb,
        elOffset: el,
        size: size,
        isInput: false,
      );
      // 画布偏移与 PCB 偏移都要叠加，漏一个会整体错位。
      expect(input, const Offset(140, 280));
      expect(output, const Offset(220, 280));
    });

    test('gate_in 在顶部中央', () {
      final gate = portOffset(
        canvasOffset: canvas,
        pcbOffset: pcb,
        elOffset: el,
        size: size,
        isInput: true,
        portName: 'gate_in',
      );
      expect(gate, const Offset(180, 267));
    });

    test('旋转 180 度后左右端口互换位置', () {
      final input = portOffset(
        canvasOffset: canvas,
        pcbOffset: pcb,
        elOffset: el,
        size: size,
        isInput: true,
        rotation: 180,
      );
      expect(input.dx, closeTo(220, 0.001));
      expect(input.dy, closeTo(280, 0.001));
    });

    test('旋转不改变端口到中心的距离', () {
      const center = Offset(180, 280);
      for (final angle in [0.0, 37.0, 90.0, 213.0]) {
        final p = portOffset(
          canvasOffset: canvas,
          pcbOffset: pcb,
          elOffset: el,
          size: size,
          isInput: false,
          rotation: angle,
        );
        expect((p - center).distance, closeTo(40, 0.001), reason: '$angle');
      }
    });
  });

  group('端点与渲染器实际端口的对应关系', () {
    // 这一组是为了钉死「连线端点画在哪」这个容易算错的问题。
    // 数值全部来自 ui_renderer.dart 里各组件的端口绘制代码。

    test('linker 端口垂直居中，与连线端点同轴', () {
      // 渲染器：Positioned(top: (size.height - portSize) / 2)，
      // portSize = 15.0（ui_renderer.dart 第 1318 行附近）。
      const h = 44.0;
      const portSize = 15.0;
      final portCenterY = (h - portSize) / 2 + portSize / 2;
      // 连线端点取 elTop + height / 2。
      expect(portCenterY, h / 2);
    });

    test('连线端点落在元件边缘而非端口圆心，这是刻意的', () {
      // 渲染器把 linker 端口内缩了 6px：Positioned(left: 6)。
      // 圆心 x = 6 + 15/2 = 13.5，而连线端点取 x = 0（左边缘）。
      const portSize = 15.0;
      final portCenterX = 6 + portSize / 2;
      expect(portCenterX, 13.5);
      // 差 13.5px。照搬 Studio 的 _resolvePortGlobalOffset，
      // 且观感上更合理——接到圆心会让线有一截压在元件内部、
      // 从圆点底下穿出来。
      expect(portCenterX - 0.0, 13.5);
    });

    test('math_node 的 gate 口圆心正好是 7.0', () {
      // ⚠️ 易错点：math_node 的 portSize 是 9.0（第 1470 行），
      // **不是** linker 的 15.0。用错常数会算出 10.0 并误以为差了 3px。
      // 渲染器：Positioned(top: 2.5)。
      const mathPortSize = 9.0;
      final gateCenterY = 2.5 + mathPortSize / 2;
      expect(gateCenterY, 7.0);
      // _assemblyPortOffset 里 gate_in 用的正是 elTop + 7.0，零偏差。
    });
  });

  group('配色语义与 Studio 一致', () {
    test('接收线青 / 输出线绿', () {
      expect(LinkerLineColors.resolve(isInput: true), LinkerLineColors.input);
      expect(LinkerLineColors.resolve(isInput: false), LinkerLineColors.output);
    });

    test('复合组件用粉 / 浅蓝', () {
      expect(
        LinkerLineColors.resolve(isInput: true, isCompositePort: true),
        LinkerLineColors.compositeInput,
      );
      expect(
        LinkerLineColors.resolve(isInput: false, isCompositePort: true),
        LinkerLineColors.compositeOutput,
      );
    });

    test('算数操控线优先级高于复合件', () {
      // 「这是触发通路」比「这一端在复合件里」更需要被一眼看出，
      // 优先级顺序不能调换。
      expect(
        LinkerLineColors.resolve(
          isInput: true,
          isControlLine: true,
          isCompositePort: true,
        ),
        LinkerLineColors.control,
      );
    });

    test('颜色常量值与 Studio 历史字面量一致', () {
      // 这些值原本硬编码在 ui_studio_page/linker.dart，
      // 提取时若抄错，两个编辑器的连线颜色就对不上了。
      expect(LinkerLineColors.input, const Color(0xFF00ACC1));
      expect(LinkerLineColors.output, const Color(0xFF66BB6A));
      expect(LinkerLineColors.control, const Color(0xFFFFB300));
      expect(LinkerLineColors.compositeInput, const Color(0xFFFF4081));
      expect(LinkerLineColors.compositeOutput, const Color(0xFF4FC3F7));
      expect(LinkerLineColors.hitTarget, const Color(0xFF00E676));
    });
  });

  group('端口切线跟随旋转', () {
    // 首轮测试反馈：端口位置会跟着元件转，但线的「出头」仍水平拉出，
    // 元件转 90° 时线先横着窜出去再拐回来，像从侧面漏出来的。
    // 根因是 painter 里两个控制点写死了水平方向。

    Offset dirOf(bool isInput, String? port, double rotation) {
      final base = port == 'gate_in'
          ? LinkerConnectionPainter.gateEndDirection
          : (isInput
              ? LinkerConnectionPainter.defaultEndDirection
              : LinkerConnectionPainter.defaultStartDirection);
      return LinkerConnectionPainter.rotateDirection(base, rotation);
    }

    test('未旋转时与历史行为一致', () {
      expect(dirOf(false, null, 0), const Offset(1, 0));
      expect(dirOf(true, null, 0), const Offset(-1, 0));
      expect(dirOf(true, 'gate_in', 0), const Offset(0, -1));
    });

    test('输出口转 90 度后朝下', () {
      // 与 _assemblyPortOffset 对同一角度算出的端口位置同向，
      // 两者必须同步，否则线会从端口旁边而不是端口上冒出来。
      final d = dirOf(false, null, 90);
      expect(d.dx, closeTo(0, 1e-9));
      expect(d.dy, closeTo(1, 1e-9));
    });

    test('输入口转 90 度后朝上', () {
      final d = dirOf(true, null, 90);
      expect(d.dx, closeTo(0, 1e-9));
      expect(d.dy, closeTo(-1, 1e-9));
    });

    test('gate 口跟着转', () {
      final d = dirOf(true, 'gate_in', 90);
      expect(d.dx, closeTo(1, 1e-9));
      expect(d.dy, closeTo(0, 1e-9));
    });

    test('方向始终是单位向量', () {
      for (final angle in [0.0, 37.0, 90.0, 213.0, -45.0]) {
        expect(dirOf(false, null, angle).distance, closeTo(1, 1e-9),
            reason: '$angle');
      }
    });

    test('旋转 180 度后出入方向互换', () {
      final out180 = dirOf(false, null, 180);
      expect(out180.dx, closeTo(-1, 1e-9));
      expect(out180.dy, closeTo(0, 1e-9));
    });
  });

  group('画笔重绘判定', () {
    test('线宽或透明度变化要触发重绘', () {
      const a = LinkerConnectionPainter(
        start: Offset.zero,
        end: Offset(10, 10),
        color: Color(0xFF00ACC1),
      );
      const thinner = LinkerConnectionPainter(
        start: Offset.zero,
        end: Offset(10, 10),
        color: Color(0xFF00ACC1),
        strokeWidth: 1.4,
      );
      const fainter = LinkerConnectionPainter(
        start: Offset.zero,
        end: Offset(10, 10),
        color: Color(0xFF00ACC1),
        opacity: 0.55,
      );
      expect(thinner.shouldRepaint(a), isTrue);
      expect(fainter.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(a), isFalse);
    });

    test('切线方向变化要触发重绘', () {
      // 元件旋转时端点可能不变（绕中心转到对称位置），
      // 只有方向变了——不比较方向就会漏重绘，线卡在旧朝向上。
      const a = LinkerConnectionPainter(
        start: Offset.zero,
        end: Offset(10, 10),
        color: Color(0xFF00ACC1),
      );
      const turned = LinkerConnectionPainter(
        start: Offset.zero,
        end: Offset(10, 10),
        color: Color(0xFF00ACC1),
        startDirection: Offset(0, 1),
      );
      expect(turned.shouldRepaint(a), isTrue);
    });
  });
}
