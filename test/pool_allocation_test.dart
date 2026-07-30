import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/linker_matrix_engine.dart';
import 'package:llm_project/services/ui_engine/linker_service.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';

/// A13-3：配额分配（`pool_to_allocation`）。
///
/// 源 = 可分配总量，目标 = 参与分配的组件。
/// 连上后分配组件归零，总量组件显示剩余可分配数。

UIElement _text(String id, {String text = ''}) => UIElement(
      id: id,
      isComposite: false,
      offset: Offset.zero,
      size: const Size(100, 30),
      module: UIModule(
        id: 'm_$id',
        name: id,
        type: 'text',
        properties: {'text': text},
      ),
    );

UIElement _slider(String id, double current) => UIElement(
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

UIElement _poolLinker(
  String id, {
  required String from,
  required String to,
  Map<String, dynamic>? params,
  bool enabled = true,
}) =>
    UIElement(
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
            'scheme': 'pool_to_allocation',
            'enabled': enabled,
            'schemeParams': ?params,
          },
        },
      ),
    );

UIModule _moduleOf(List<UIElement> elements, String id) =>
    elements.firstWhere((e) => e.id == id).module!;

void _install(List<UIElement> elements) {
  LinkerService.installSnapshot(LinkerSnapshot.fromElements(elements));
}

/// 力量/敏捷/智力三滑块共享 10 点。
List<UIElement> _panel({
  double str = 0,
  double agi = 0,
  double intel = 0,
  String poolText = '10',
}) =>
    [
      // 总量直接写在文本里，作者改文本即改总量。
      _text('pool', text: poolText),
      _slider('str', str),
      _slider('agi', agi),
      _slider('int', intel),
      _poolLinker('l1', from: 'pool', to: 'str', params: {
        'template': '剩余 {{remain}}/{{total}}',
      }),
      _poolLinker('l2', from: 'pool', to: 'agi'),
      _poolLinker('l3', from: 'pool', to: 'int'),
    ];

void main() {
  group('方案登记', () {
    test('已登记进方案矩阵', () {
      expect(
        LinkerMatrixEngine.isSchemeSelectable('pool_to_allocation'),
        isTrue,
      );
    });

    test('来源限于玩家改不了的组件', () {
      // 总量一旦能被玩家自己拖动 / 输入，配额约束就失去意义。
      for (final src in ['text', 'progress', 'math_node']) {
        expect(
          LinkerMatrixEngine.getAvailableSchemes(src, 'slider')
              .map((s) => s.id),
          contains('pool_to_allocation'),
          reason: src,
        );
      }
      for (final src in ['slider', 'input']) {
        expect(
          LinkerMatrixEngine.getAvailableSchemes(src, 'slider')
              .map((s) => s.id),
          isNot(contains('pool_to_allocation')),
          reason: src,
        );
      }
    });

    test('目标限于玩家能操作的组件', () {
      // progress 没有任何手势，玩家改不了它的值，作分配项纯属摆设。
      for (final tgt in ['slider', 'input']) {
        expect(
          LinkerMatrixEngine.getAvailableSchemes('text', tgt).map((s) => s.id),
          contains('pool_to_allocation'),
          reason: tgt,
        );
      }
      expect(
        LinkerMatrixEngine.getAvailableSchemes('text', 'progress')
            .map((s) => s.id),
        isNot(contains('pool_to_allocation')),
      );
    });

    test('text → slider 能选到（黑名单需为显式白名单方案放行）', () {
      // text→slider 在黑名单里，但这正是本方案最主要的用法：
      // 用文本当「剩余 10 点」去驱动滑块。
      final ids = LinkerMatrixEngine.getAvailableSchemes('text', 'slider')
          .map((s) => s.id);
      expect(ids, contains('pool_to_allocation'));
    });

    test('黑名单对未声明白名单的方案依然生效', () {
      // 放行只针对显式声明了该目标的方案，不能把整条通路敞开。
      final ids = LinkerMatrixEngine.getAvailableSchemes('text', 'slider')
          .map((s) => s.id);
      expect(ids, isNot(contains('to_string')));
    });

    test('progress 也可以当池子', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('progress', 'slider')
          .map((s) => s.id);
      expect(ids, contains('pool_to_allocation'));
    });
  });

  group('剩余量显示', () {
    test('未分配时显示全部总量', () {
      final elements = _panel();
      _install(elements);
      final display = LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'));
      expect(display, isNotNull);
      expect(display!.render(), '剩余 10/10');
    });

    test('分配后总量组件显示剩余数', () {
      final elements = _panel(str: 3, agi: 2);
      _install(elements);
      final display = LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'));
      expect(display!.remain, 5.0);
      expect(display.used, 5.0);
      expect(display.render(), '剩余 5/10');
    });

    test('非池子组件返回 null，不影响普通文本', () {
      final elements = _panel();
      _install(elements);
      expect(
        LinkerService.resolvePoolDisplay(_moduleOf(elements, 'str')),
        isNull,
      );
    });

    test('总量直接读文本内容，改文本即改总量', () {
      // 首轮测试反馈：总量只能在方案编辑器里填，text 的值用不上。
      final elements = _panel(poolText: '25', str: 5);
      _install(elements);
      final display =
          LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'))!;
      expect(display.total, 25.0);
      expect(display.remain, 20.0);
    });

    test('允许文本带单位', () {
      final elements = _panel(poolText: '10 点');
      _install(elements);
      expect(
        LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'))!.total,
        10.0,
      );
    });

    test('文本读不出数字时回退连线参数', () {
      final elements = [
        _text('pool', text: '属性点'),
        _slider('str', 0),
        _poolLinker('l1', from: 'pool', to: 'str', params: {'total': 8.0}),
      ];
      _install(elements);
      expect(
        LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'))!.total,
        8.0,
      );
    });

    test('渲染出的剩余数不会回写文本，不产生反馈循环', () {
      // 池文本渲染成「剩余 7」，若把它当总量读会每帧递减。
      final elements = _panel(poolText: '10', str: 3);
      _install(elements);
      final pool = _moduleOf(elements, 'pool');
      for (var i = 0; i < 3; i++) {
        final d = LinkerService.resolvePoolDisplay(pool)!;
        expect(d.total, 10.0);
        expect(d.remain, 7.0);
      }
      expect(pool.properties['text'], '10');
    });
  });

  group('分配上限', () {
    test('上限 = 剩余额度 + 自己已占用', () {
      // 加回自己是关键：否则已分配 5 点的滑块想调到 6 会被卡在剩余值上，
      // 等于只能往下调、调不回去。
      final elements = _panel(str: 5, agi: 2);
      _install(elements);
      // 剩余 3，自己占 5 → 上限 8。
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'str')), 8.0);
      // 剩余 3，自己占 2 → 上限 5。
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'agi')), 5.0);
    });

    test('额度耗尽时未分配项的上限为 0', () {
      final elements = _panel(str: 6, agi: 4);
      _install(elements);
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'int')), 0.0);
    });

    test('超额时上限不会变成负数', () {
      // 旧数据或作者手改可能造成超额，上限必须收敛到 0 而不是负值。
      final elements = _panel(str: 8, agi: 8);
      _install(elements);
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'int')), 0.0);
    });

    test('非分配组件没有上限约束', () {
      final elements = _panel();
      _install(elements);
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'pool')), isNull);
    });
  });

  group('初始值', () {
    test('默认归零', () {
      final elements = _panel();
      _install(elements);
      expect(LinkerService.allocationInitialValue(_moduleOf(elements, 'str')), 0.0);
    });

    test('可为单个分配组件设定初始值', () {
      final elements = [
        _text('pool', text: '10'),
        _slider('str', 0),
        _poolLinker('l1', from: 'pool', to: 'str', params: {
          'initialValue': 3.0,
        }),
      ];
      _install(elements);
      expect(LinkerService.allocationInitialValue(_moduleOf(elements, 'str')), 3.0);
    });
  });

  group('连线时归零（回归）', () {
    test('分配组件的 current 会被计入已分配量', () {
      // slider 模板默认 current=50。若连线时不归零，
      // 池子一连上就凭空少 50（首轮测试反馈的现象）。
      final elements = [
        _text('pool', text: '10'),
        _slider('str', 50),
        _poolLinker('l1', from: 'pool', to: 'str'),
      ];
      _install(elements);
      // 这里直接验证统计口径：读的就是目标的 current。
      expect(LinkerService.poolUsedAmount('pool'), 50.0);
      // 因此归零必须发生在配置连线时，把 current 真正写成 0，
      // 而不是只在渲染时改显示值。
    });

    test('归零后剩余量等于总量', () {
      final elements = [
        _text('pool', text: '10'),
        _slider('str', 0),
        _poolLinker('l1', from: 'pool', to: 'str'),
      ];
      _install(elements);
      expect(LinkerService.poolUsedAmount('pool'), 0.0);
      expect(
        LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'))!.remain,
        10.0,
      );
    });
  });

  group('识别与边界', () {
    test('分配组件能被正确识别', () {
      final elements = _panel();
      _install(elements);
      expect(LinkerService.isAllocationTarget(_moduleOf(elements, 'str')), isTrue);
      expect(LinkerService.isAllocationTarget(_moduleOf(elements, 'pool')), isFalse);
    });

    test('停用的连线不参与统计', () {
      final elements = [
        _text('pool', text: '10'),
        _slider('str', 3),
        _slider('agi', 4),
        _poolLinker('l1', from: 'pool', to: 'str'),
        _poolLinker('l2', from: 'pool', to: 'agi', enabled: false),
      ];
      _install(elements);
      // 只统计启用的那条：已用 3 而不是 7。
      expect(LinkerService.poolUsedAmount('pool'), 3.0);
    });

    test('input 作分配项时按 text 计入已分配量', () {
      // input 把值存在 text 而不是 current，取值口径必须覆盖两者，
      // 否则用输入框做分配项时统计恒为 0。
      final elements = [
        _text('pool', text: '10'),
        UIElement(
          id: 'name',
          isComposite: false,
          offset: Offset.zero,
          size: const Size(100, 30),
          module: UIModule(
            id: 'm_name',
            name: 'name',
            type: 'input',
            properties: {'text': '4'},
          ),
        ),
        _poolLinker('l1', from: 'pool', to: 'name'),
      ];
      _install(elements);
      expect(LinkerService.poolUsedAmount('pool'), 4.0);
      expect(
        LinkerService.resolvePoolDisplay(_moduleOf(elements, 'pool'))!.remain,
        6.0,
      );
    });

    test('slider 与 input 混用时合并统计', () {
      final elements = [
        _text('pool', text: '10'),
        _slider('str', 3),
        UIElement(
          id: 'bonus',
          isComposite: false,
          offset: Offset.zero,
          size: const Size(100, 30),
          module: UIModule(
            id: 'm_bonus',
            name: 'bonus',
            type: 'input',
            properties: {'text': '2'},
          ),
        ),
        _poolLinker('l1', from: 'pool', to: 'str'),
        _poolLinker('l2', from: 'pool', to: 'bonus'),
      ];
      _install(elements);
      expect(LinkerService.poolUsedAmount('pool'), 5.0);
      // 上限 = 自己已占 + 剩余：input 自己占 2，剩余 5 → 7。
      expect(
        LinkerService.allocationCeilingFor(_moduleOf(elements, 'bonus')),
        7.0,
      );
    });

    test('进度条当池子时读其当前值', () {
      final elements = [
        UIElement(
          id: 'pool',
          isComposite: false,
          offset: Offset.zero,
          size: const Size(100, 30),
          module: UIModule(
            id: 'm_pool',
            name: 'pool',
            type: 'progress',
            properties: {'current': 20.0, 'min': 0.0, 'max': 100.0},
          ),
        ),
        _slider('str', 5),
        _poolLinker('l1', from: 'pool', to: 'str'),
      ];
      _install(elements);
      // 用进度条当池子：总量取它的 current=20，已分配 5 → 上限 20。
      expect(LinkerService.allocationCeilingFor(_moduleOf(elements, 'str')), 20.0);
    });
  });
}
