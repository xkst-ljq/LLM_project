import 'package:flutter_test/flutter_test.dart';

/// button 的定位：一块「点击热区」。
///
/// 它在运行期完全不显形，视觉反馈一律由它联动的 surface 表现。
/// 历史上曾支持 `text` / `showTextOnRuntime`（运行期显示文案）与
/// `active_gesture`（在按钮上选一种触发手势），两者都已废弃：
///
/// * 会自己显字的按钮与「热区」定位冲突，也让作者误以为它有外观可调；
/// * 在按钮上选手势意味着同一个按钮只能有一种触控语义，
///   改为在**每条连线**上选手势后，单击 / 双击 / 长按可以各接各的目标。
///
/// 手势的落点是连线的 `sourcePort`——运行端 `LinkerService`
/// 本就按 'tap' / 'double_tap' / 'long_press' 三个端口名分派事件，
/// 因此不需要为「双击触发某某」单开方案 id（那会让方案矩阵翻三倍）。

/// 复刻 `_schemeSourcePort` 中与 button 相关的部分。
String baseSourcePort(String scheme) {
  if (scheme.startsWith('click_') || scheme.startsWith('event_')) return 'tap';
  if (scheme.startsWith('timer_tick_')) return 'timer_tick';
  return 'current';
}

/// 复刻保存分支里「手势覆写端口」的判定。
///
/// 只有来源确实是 button、且方案本身走单击通道时才允许覆写；
/// 否则（例如 timer 的 tick）手势无从谈起，必须原样保留推导端口。
Map<String, String?> resolveSourcePort({
  required String scheme,
  required String sourceType,
  required String gesture,
}) {
  final base = baseSourcePort(scheme);
  final canOverride = sourceType == 'button' && base == 'tap';
  if (canOverride && gesture.isNotEmpty) {
    return {'sourcePort': gesture, 'sourceGesture': gesture};
  }
  return {'sourcePort': base, 'sourceGesture': null};
}

/// 复刻 `_buttonUsesNonTapGesture`。
bool buttonUsesNonTapGesture(
  String buttonId,
  List<Map<String, dynamic>> linkers,
) {
  for (final data in linkers) {
    if (data['sourceModuleId'] != buttonId) continue;
    final port = data['sourcePort']?.toString() ?? '';
    if (port == 'double_tap' || port == 'long_press') return true;
  }
  return false;
}

/// 复刻实例编辑器保存 button 时的属性迁移与手感参数夹取。
Map<String, dynamic> saveButtonProps(
  Map<String, dynamic> before, {
  String? doubleTapText,
  String? longPressText,
}) {
  final props = Map<String, dynamic>.from(before);
  props
    ..remove('text')
    ..remove('showTextOnRuntime')
    ..remove('active_gesture');
  final interval = int.tryParse(doubleTapText?.trim() ?? '');
  if (interval == null) {
    props.remove('doubleTapIntervalMs');
  } else {
    props['doubleTapIntervalMs'] = interval.clamp(100, 1000);
  }
  final threshold = int.tryParse(longPressText?.trim() ?? '');
  if (threshold == null) {
    props.remove('longPressThresholdMs');
  } else {
    props['longPressThresholdMs'] = threshold.clamp(150, 3000);
  }
  return props;
}

void main() {
  group('连线手势覆写 sourcePort', () {
    test('默认单击时端口与旧行为一致', () {
      final r = resolveSourcePort(
        scheme: 'click_to_switch_toggle',
        sourceType: 'button',
        gesture: 'tap',
      );
      expect(r['sourcePort'], 'tap');
    });

    test('选双击 / 长按会覆写端口', () {
      for (final g in ['double_tap', 'long_press']) {
        final r = resolveSourcePort(
          scheme: 'click_to_switch_toggle',
          sourceType: 'button',
          gesture: g,
        );
        expect(r['sourcePort'], g, reason: g);
        expect(r['sourceGesture'], g, reason: g);
      }
    });

    test('同一按钮三条连线可各用一种手势', () {
      final ports = ['tap', 'double_tap', 'long_press']
          .map(
            (g) => resolveSourcePort(
              scheme: 'click_to_switch_toggle',
              sourceType: 'button',
              gesture: g,
            )['sourcePort'],
          )
          .toList();
      // 三条连线端口互不相同，运行端才能分派到不同目标。
      expect(ports.toSet().length, 3);
    });

    test('非 button 来源不受手势影响', () {
      // timer 的 tick 没有「双击」可言，误传手势也必须被忽略。
      final r = resolveSourcePort(
        scheme: 'timer_tick_to_text',
        sourceType: 'timer',
        gesture: 'double_tap',
      );
      expect(r['sourcePort'], 'timer_tick');
      expect(r['sourceGesture'], isNull);
    });

    test('button 走非单击通道的方案也不覆写', () {
      // 防止哪天新增 button 的值型方案时被手势串改端口。
      final r = resolveSourcePort(
        scheme: 'value_to_text',
        sourceType: 'button',
        gesture: 'long_press',
      );
      expect(r['sourcePort'], 'current');
      expect(r['sourceGesture'], isNull);
    });
  });

  group('手感参数的显示条件', () {
    test('只有单击连线时不显示', () {
      expect(
        buttonUsesNonTapGesture('btn', [
          {'sourceModuleId': 'btn', 'sourcePort': 'tap'},
        ]),
        isFalse,
      );
    });

    test('存在双击或长按连线时显示', () {
      expect(
        buttonUsesNonTapGesture('btn', [
          {'sourceModuleId': 'btn', 'sourcePort': 'tap'},
          {'sourceModuleId': 'btn', 'sourcePort': 'long_press'},
        ]),
        isTrue,
      );
    });

    test('别的按钮的连线不算数', () {
      expect(
        buttonUsesNonTapGesture('btn', [
          {'sourceModuleId': 'other', 'sourcePort': 'double_tap'},
        ]),
        isFalse,
      );
    });
  });

  group('保存时的属性迁移', () {
    test('旧卡的文案键会被清除', () {
      // 不清的话渲染端虽然已经不读，但属性会一直躺在角色卡里，
      // 且 Studio 旧编辑器若被回滚会再次把它显示出来。
      final after = saveButtonProps({
        'text': '开始',
        'showTextOnRuntime': true,
        'active_gesture': 'long_press',
      });
      expect(after.containsKey('text'), isFalse);
      expect(after.containsKey('showTextOnRuntime'), isFalse);
      expect(after.containsKey('active_gesture'), isFalse);
    });

    test('手感参数夹取到渲染端认可的区间', () {
      // 渲染端 _ButtonGestureWidget 自己也会 clamp，
      // 这里提前夹取是为了让存进卡里的值就是生效值，避免作者困惑。
      final after = saveButtonProps(
        {},
        doubleTapText: '50',
        longPressText: '99999',
      );
      expect(after['doubleTapIntervalMs'], 100);
      expect(after['longPressThresholdMs'], 3000);
    });

    test('留空则移除，回落渲染端默认值', () {
      final after = saveButtonProps(
        {'doubleTapIntervalMs': 300, 'longPressThresholdMs': 500},
        doubleTapText: '',
        longPressText: '  ',
      );
      expect(after.containsKey('doubleTapIntervalMs'), isFalse);
      expect(after.containsKey('longPressThresholdMs'), isFalse);
    });

    test('正常值原样保留', () {
      final after = saveButtonProps(
        {},
        doubleTapText: '260',
        longPressText: '700',
      );
      expect(after['doubleTapIntervalMs'], 260);
      expect(after['longPressThresholdMs'], 700);
    });
  });
}
