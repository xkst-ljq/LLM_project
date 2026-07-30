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
  });
}
