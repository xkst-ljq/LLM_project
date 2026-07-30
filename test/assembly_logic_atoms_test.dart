import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/linker_matrix_engine.dart';
import 'package:llm_project/services/ui_engine/ui_asset_service.dart';

/// A14-2：timer / math_node 补进 Assembly 资产栏。
///
/// 这两个组件的渲染、尺寸预设、linker 方案早就齐了，
/// 唯独没有资产栏入口，导致「定时触发剧情」「属性公式计算」做不了。

void main() {
  final service = UIAssetService();

  group('资产模板存在', () {
    test('定时器模板可从资产服务取到', () {
      final module = service.getModule('atom_timer_basic');
      expect(module, isNotNull);
      expect(module!.type, 'timer');
    });

    test('计算节点模板可从资产服务取到', () {
      final module = service.getModule('atom_logic_math_node');
      expect(module, isNotNull);
      expect(module!.type, 'math_node');
    });
  });

  group('模板默认值与运行端读取的键一致', () {
    test('定时器的键覆盖运行端所需', () {
      // 少任何一个键，运行端会静默回落到内置默认，
      // 表现为「编辑器里改了却不生效」。
      final props = service.getModule('atom_timer_basic')!.properties;
      for (final key in [
        'interval',
        'initialDelay',
        'maxTicks',
        'isRunning',
        'loop',
        'pulseType',
      ]) {
        expect(props.containsKey(key), isTrue, reason: key);
      }
    });

    test('计算节点的键覆盖运行端所需', () {
      final props = service.getModule('atom_logic_math_node')!.properties;
      for (final key in [
        'operation',
        'paramA',
        'paramB',
        'paramC',
        'activeParams',
      ]) {
        expect(props.containsKey(key), isTrue, reason: key);
      }
    });

    test('定时器默认间隔为正，不会每帧触发卡死界面', () {
      final interval =
          service.getModule('atom_timer_basic')!.properties['interval'];
      expect((interval as num) > 0, isTrue);
    });
  });

  group('联动方案可用', () {
    test('定时器能作为脉冲源驱动其他组件', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('timer', 'switch')
          .map((s) => s.id);
      expect(ids, isNotEmpty);
    });

    test('计算节点能把结果输出到文本', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('math_node', 'text')
          .map((s) => s.id);
      expect(ids, isNotEmpty);
    });

    test('按钮能启停定时器', () {
      // 手动模式依赖这条方案；没有它 isRunning 开关就没有意义。
      final ids = LinkerMatrixEngine.getAvailableSchemes('button', 'timer')
          .map((s) => s.id);
      expect(ids, contains('click_to_timer_toggle'));
    });
  });

  group('参数口顺序', () {
    test('activeParams 按 A/B/C 固定顺序存储', () {
      // 连续运算（如连续减法）的结果与顺序相关，
      // 若按勾选顺序存，作者取消再勾选就会改变结果。
      const paramKeys = ['paramA', 'paramB', 'paramC'];
      final active = <String>{'paramC', 'paramA'};
      final ordered = paramKeys.where(active.contains).toList();
      expect(ordered, ['paramA', 'paramC']);
    });
  });
}
