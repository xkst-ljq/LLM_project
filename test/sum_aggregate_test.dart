import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/linker_matrix_engine.dart';
import 'package:llm_project/services/ui_engine/linker_service.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

/// A13-3：数值求和汇总（`sum_to_display`）。
///
/// 与其他方案的根本区别：**同一目标可以接多条**，运行端把它们全部
/// 收集起来算总和，而不是像普通方案那样只取优先级最高的那条。

UIElement _slider(String id, double current) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(100, 30),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: 'slider',
      properties: {'current': current, 'min': 0.0, 'max': 100.0},
    ),
  );
}

UIElement _text(String id) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(100, 30),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: 'text',
      properties: {'text': ''},
    ),
  );
}

UIElement _progress(String id) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(100, 30),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: 'progress',
      properties: {'current': 0.0, 'min': 0.0, 'max': 100.0},
    ),
  );
}

UIElement _sumLinker(
  String id, {
  required String from,
  required String to,
  Map<String, dynamic>? params,
}) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(40, 40),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: 'linker',
      properties: {
        'linker': {
          'sourceModuleId': from,
          'targetModuleId': to,
          'scheme': 'sum_to_display',
          'enabled': true,
          'sourcePort': 'current',
          'targetPort': 'text',
          'schemeParams': ?params,
        },
      },
    ),
  );
}

dynamic _resolve(List<UIElement> elements, String targetId) {
  LinkerService.installSnapshot(LinkerSnapshot.fromElements(elements));
  final target = elements.firstWhere((e) => e.id == targetId).module!;
  return LinkerService.resolveTargetValue(target);
}

void main() {
  group('方案登记', () {
    test('已登记进方案矩阵', () {
      expect(LinkerMatrixEngine.isSchemeSelectable('sum_to_display'), isTrue);
    });

    test('slider → text 能选到', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('slider', 'text')
          .map((s) => s.id);
      expect(ids, contains('sum_to_display'));
    });

    test('通用性：不止 slider 可作为来源', () {
      // 用户明确要求这个方案能用在其他数据组件上，不是点数分配专用。
      for (final src in ['progress', 'input', 'math_node', 'timer']) {
        final ids = LinkerMatrixEngine.getAvailableSchemes(src, 'text')
            .map((s) => s.id);
        expect(ids, contains('sum_to_display'), reason: src);
      }
    });

    test('目标可以是 progress，用于做配额条', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('slider', 'progress')
          .map((s) => s.id);
      expect(ids, contains('sum_to_display'));
    });
  });

  group('多源求和', () {
    test('三条连线汇总成一个值', () {
      final elements = [
        _slider('s1', 3),
        _slider('s2', 4),
        _slider('s3', 2),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1'),
        _sumLinker('l2', from: 's2', to: 't1'),
        _sumLinker('l3', from: 's3', to: 't1'),
      ];
      expect(_resolve(elements, 't1'), '9');
    });

    test('单条连线也正常工作', () {
      final elements = [
        _slider('s1', 7),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1'),
      ];
      expect(_resolve(elements, 't1'), '7');
    });

    test('数值型目标拿到的是数字而非模板字符串', () {
      // progress/slider 收到带单位的字符串会解析失败。
      final elements = [
        _slider('s1', 5),
        _slider('s2', 6),
        _progress('p1'),
        _sumLinker('l1', from: 's1', to: 'p1', params: {'template': '共 {{value}} 点'}),
        _sumLinker('l2', from: 's2', to: 'p1'),
      ];
      // 未设总量：原样给出，由目标自身量程决定观感。
      expect(_resolve(elements, 'p1'), 11.0);
    });
  });

  group('配额与超额策略', () {
    List<UIElement> build({
      required double a,
      required double b,
      required String mode,
      String template = '{{value}}/{{total}} 剩余 {{remain}}',
    }) {
      return [
        _slider('s1', a),
        _slider('s2', b),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1', params: {
          'total': 10.0,
          'overflowMode': mode,
          'template': template,
        }),
        _sumLinker('l2', from: 's2', to: 't1'),
      ];
    }

    test('未超额时正常显示剩余量', () {
      expect(_resolve(build(a: 3, b: 4, mode: 'allow'), 't1'), '7/10 剩余 3');
    });

    test('allow 模式：可以超出，剩余显示为负数', () {
      // 作者据此自行决定怎么提示「超支」，比引擎硬拦更灵活。
      expect(_resolve(build(a: 6, b: 7, mode: 'allow'), 't1'), '13/10 剩余 -3');
    });

    test('clamp 模式：汇总值不超过总量', () {
      expect(_resolve(build(a: 6, b: 7, mode: 'clamp'), 't1'), '10/10 剩余 0');
    });

    test('配额参数只需在一条连线上填写', () {
      // 给每条连线都重复配一遍太繁琐，容易配漏配错。
      final elements = [
        _slider('s1', 2),
        _slider('s2', 3),
        _text('t1'),
        // 第一条不带参数，第二条才带。
        _sumLinker('l1', from: 's1', to: 't1'),
        _sumLinker('l2', from: 's2', to: 't1', params: {
          'total': 20.0,
          'template': '剩余 {{remain}}',
        }),
      ];
      expect(_resolve(elements, 't1'), '剩余 15');
    });

    test('未设总量时 remain 为 0，不显示成负数', () {
      final elements = [
        _slider('s1', 5),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1', params: {
          'template': '{{value}} 剩余 {{remain}}',
        }),
      ];
      expect(_resolve(elements, 't1'), '5 剩余 0');
    });

    test('小数位数生效', () {
      final elements = [
        _slider('s1', 1.25),
        _slider('s2', 2.5),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1', params: {'precision': 2}),
        _sumLinker('l2', from: 's2', to: 't1'),
      ];
      expect(_resolve(elements, 't1'), '3.75');
    });
  });

  group('文本目标与数值目标语义一致', () {
    // 首轮测试反馈「用不同的目标效果不一样」。同一份配置换个目标类型
    // 就变一套行为，作者无法预期，必须对齐。
    List<UIElement> build(String targetId, UIElement target, String mode) {
      return [
        _slider('s1', 6),
        _slider('s2', 7),
        target,
        _sumLinker('l1', from: 's1', to: targetId, params: {
          'total': 10.0,
          'overflowMode': mode,
          'template': '{{value}}/{{total}}',
        }),
        _sumLinker('l2', from: 's2', to: targetId),
      ];
    }

    test('设了总量时，进度条把总量当作满值', () {
      // 作者填总量 10、已分配 7，进度条就该是 70%，
      // 而不是拿 7 去套进度条自己的 max=100 变成 7%。
      final elements = [
        _slider('s1', 3),
        _slider('s2', 4),
        _progress('p1'),
        _sumLinker('l1', from: 's1', to: 'p1', params: {'total': 10.0}),
        _sumLinker('l2', from: 's2', to: 'p1'),
      ];
      expect(_resolve(elements, 'p1'), 70.0);
    });

    test('clamp 模式下两种目标都被限制住', () {
      expect(_resolve(build('t1', _text('t1'), 'clamp'), 't1'), '10/10');
      expect(_resolve(build('p1', _progress('p1'), 'clamp'), 'p1'), 100.0);
    });

    test('allow 模式下文本可超额，进度条填满但不溢出', () {
      // 文本保留真实值 13 供作者提示超支；
      // 进度条没有「超过 100%」的表现形式，填满即可。
      expect(_resolve(build('t1', _text('t1'), 'allow'), 't1'), '13/10');
      expect(_resolve(build('p1', _progress('p1'), 'allow'), 'p1'), 100.0);
    });
  });

  group('边界', () {
    test('停用的连线不参与汇总', () {
      final elements = [
        _slider('s1', 3),
        _slider('s2', 4),
        _text('t1'),
        _sumLinker('l1', from: 's1', to: 't1'),
        UIElement(
          id: 'l2',
          isComposite: false,
          offset: Offset.zero,
          size: const Size(40, 40),
          module: UIModule(
            id: 'm_l2',
            name: 'l2',
            type: 'linker',
            properties: {
              'linker': {
                'sourceModuleId': 's2',
                'targetModuleId': 't1',
                'scheme': 'sum_to_display',
                'enabled': false,
              },
            },
          ),
        ),
      ];
      expect(_resolve(elements, 't1'), '3');
    });

    test('没有聚合连线时不影响普通方案', () {
      // 聚合走的是独立路径，必须确认它不会吃掉别的方案。
      final elements = [
        _slider('s1', 42),
        _text('t1'),
        UIElement(
          id: 'l1',
          isComposite: false,
          offset: Offset.zero,
          size: const Size(40, 40),
          module: UIModule(
            id: 'm_l1',
            name: 'l1',
            type: 'linker',
            properties: {
              'linker': {
                'sourceModuleId': 's1',
                'targetModuleId': 't1',
                'scheme': 'slider_to_text',
                'enabled': true,
                'sourcePort': 'current',
                'targetPort': 'text',
              },
            },
          ),
        ),
      ];
      expect(_resolve(elements, 't1'), '42');
    });
  });
}
