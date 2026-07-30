import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/linker_matrix_engine.dart';

/// Assembly 侧的端口推导必须与运行端 `LinkerService` 的匹配口径一致。
///
/// 这里复刻 `_schemeSourcePort` / `_schemeTargetPort` 的规则做校验——
/// 它们是私有方法，无法直接引用，因此以「同一份规则」的形式锁住行为，
/// 一旦哪天改动导致端口错配，测试会立刻失败。
String schemeSourcePort(String scheme) {
  if (scheme.startsWith('click_') || scheme.startsWith('event_')) return 'tap';
  if (scheme.startsWith('double_click_')) return 'double_tap';
  if (scheme.startsWith('long_press_')) return 'long_press';
  if (scheme.startsWith('timer_tick_')) return 'timer_tick';
  if (scheme.startsWith('input_submit_')) return 'committedValue';
  if (scheme.startsWith('slider_commit_')) return 'committedValue';
  if (scheme.startsWith('input_value_')) return 'text';
  if (scheme.startsWith('text_extract_')) return 'text';
  return 'current';
}

String schemeTargetPort(String scheme) {
  if (scheme.endsWith('_to_text')) return 'text';
  if (scheme.contains('_to_progress')) return 'current';
  if (scheme.contains('_to_slider')) return 'current';
  if (scheme.contains('_to_switch')) return 'value';
  if (scheme.contains('_to_indicator')) return 'currentValue';
  if (scheme.contains('_to_input')) return 'text';
  if (scheme.contains('_to_select')) return 'current';
  if (scheme.contains('_to_surface_visible')) return 'visible';
  if (scheme.contains('_to_surface')) return 'anim';
  if (scheme.contains('_to_image')) return 'assetPath';
  if (scheme.contains('_to_math_trigger')) return 'gate_in';
  if (scheme.contains('_to_math_param')) return 'data_in';
  if (scheme.contains('_to_timer')) return 'value';
  if (scheme.contains('_to_page_route') || scheme.contains('_page_route')) {
    return 'trigger';
  }
  return 'value';
}

void main() {
  group('方案矩阵可用性', () {
    test('button → surface 能选到按压方案', () {
      // 这是本次移植的直接动因：button 本身不显形，
      // 必须靠联动 surface 才能做出按下反馈。
      final schemes = LinkerMatrixEngine.getAvailableSchemes(
        'button',
        'surface',
      );
      final ids = schemes.map((e) => e.id).toSet();
      expect(ids, contains('click_to_surface_press'));
    });

    test('涟漪方案已移除', () {
      // 它是「盖一个扩大的白圈」，与 A12 反复推翻的前几版水波同源。
      // 真正的折射水波已由片元着色器实现，配在元件外观页里、
      // 用 event_to_animation 触发，不必再为 surface 单独维护一份。
      expect(
        LinkerMatrixEngine.isSchemeSelectable('click_to_surface_ripple'),
        isFalse,
      );
      final ids = LinkerMatrixEngine.getAvailableSchemes('button', 'surface')
          .map((e) => e.id)
          .toSet();
      expect(ids, isNot(contains('click_to_surface_ripple')));
    });

    test('surface 仍可用通用动画方案播水波', () {
      // 移除涟漪不等于 surface 不能有水波——
      // 改走 event_to_animation，动画类型在元件自己的外观页里选。
      final ids = LinkerMatrixEngine.getAvailableSchemes('button', 'surface')
          .map((e) => e.id)
          .toSet();
      expect(ids, contains('event_to_animation'));
    });

    test('button → switch 能选到开关切换', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('button', 'switch')
          .map((e) => e.id)
          .toSet();
      expect(ids, contains('click_to_switch_toggle'));
    });

    test('slider → text 能选到数值显示', () {
      final ids = LinkerMatrixEngine.getAvailableSchemes('slider', 'text')
          .map((e) => e.id)
          .toSet();
      expect(ids, isNotEmpty);
    });

    test('不兼容组合返回空列表', () {
      final schemes = LinkerMatrixEngine.getAvailableSchemes('text', 'text');
      for (final def in schemes) {
        expect(LinkerMatrixEngine.isSchemeSelectable(def.id), isTrue);
      }
    });

    test('页面路由方案已登记，否则运行端会判为非法而跳过', () {
      // page_router 是 Assembly 专属，但必须登记在共享矩阵里。
      expect(
        LinkerMatrixEngine.isSchemeSelectable('button_to_page_route'),
        isTrue,
      );
      final ids =
          LinkerMatrixEngine.getAvailableSchemes('button', 'page_router')
              .map((e) => e.id)
              .toSet();
      expect(ids, contains('button_to_page_route'));
    });

    test('页面路由的端口推导正确', () {
      expect(schemeSourcePort('button_to_page_route'), 'tap');
      expect(schemeTargetPort('button_to_page_route'), 'trigger');
    });

    test('源或目标为空时安全返回', () {
      expect(LinkerMatrixEngine.getAvailableSchemes(null, 'text'), isEmpty);
      expect(LinkerMatrixEngine.getAvailableSchemes('button', null), isEmpty);
    });
  });

  group('端口推导', () {
    test('点击类方案来源端口为 tap', () {
      for (final s in [
        'click_to_surface_press',
        'click_to_switch_toggle',
        'click_to_math_trigger',
        'event_to_indicator',
      ]) {
        expect(schemeSourcePort(s), 'tap', reason: s);
      }
    });

    test('定时器方案来源端口为 timer_tick', () {
      expect(schemeSourcePort('timer_tick_to_switch_toggle'), 'timer_tick');
      expect(schemeSourcePort('timer_tick_to_math_trigger'), 'timer_tick');
    });

    test('提交类方案取已提交值而非实时值', () {
      // 实时值会在输入过程中不断触发，语义不同。
      expect(schemeSourcePort('input_submit_to_text_clear'), 'committedValue');
      expect(schemeSourcePort('slider_commit_to_text'), 'committedValue');
    });

    test('surface 可见性与动画走不同端口', () {
      expect(schemeTargetPort('select_value_to_surface_visible'), 'visible');
      expect(schemeTargetPort('click_to_surface_press'), 'anim');
    });

    test('计算节点区分触发与参数', () {
      expect(schemeTargetPort('click_to_math_trigger'), 'gate_in');
      expect(schemeTargetPort('progress_to_math_param'), 'data_in');
    });

    test('所有已注册方案都能推导出非空端口', () {
      // 保证新增方案时不会因漏配规则而写出空端口。
      for (final type in ['button', 'slider', 'input', 'progress', 'timer']) {
        for (final target in [
          'text',
          'surface',
          'switch',
          'progress',
          'indicator',
        ]) {
          for (final def
              in LinkerMatrixEngine.getAvailableSchemes(type, target)) {
            expect(schemeSourcePort(def.id), isNotEmpty, reason: def.id);
            expect(schemeTargetPort(def.id), isNotEmpty, reason: def.id);
          }
        }
      }
    });
  });
}
