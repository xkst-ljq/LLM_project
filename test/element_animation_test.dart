import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/element_animation.dart';

/// A12 第一步：统一动画通道。
///
/// 此前每种动画各有一套字段——surface 用 `anim_trigger`/`anim_timestamp`/
/// `anim_duration`/`anim_radius`，indicator 用 `eventFlashTimestamp`/
/// `eventFlashColor`/`eventFlashDurationMs`。两套时间戳、两套时长键。
/// 再加数值跳动 / 发光脉冲 / 粒子就是五套。
///
/// 收敛为单一字段族 `__anim` 后，新增动画类型只是多一个 enum 值。

void main() {
  group('序列化往返', () {
    test('配置往返不丢字段', () {
      const before = ElementAnimation(
        type: ElementAnimationType.glowPulse,
        durationMs: 480,
        curve: ElementAnimationCurve.bounceOut,
        intensity: 0.8,
        colorValue: 0xFF2979FF,
        timestamp: 1700000000000,
      );
      final after = ElementAnimation.fromJson(before.toJson())!;
      expect(after.type, ElementAnimationType.glowPulse);
      expect(after.durationMs, 480);
      expect(after.curve, ElementAnimationCurve.bounceOut);
      expect(after.intensity, 0.8);
      expect(after.colorValue, 0xFF2979FF);
      expect(after.timestamp, 1700000000000);
    });

    test('未知类型返回 null，不抛异常', () {
      expect(ElementAnimation.fromJson({'type': 'no_such_anim'}), isNull);
      expect(ElementAnimation.fromJson(null), isNull);
      expect(ElementAnimation.fromJson('not a map'), isNull);
    });

    test('强度超范围会被夹取', () {
      expect(
        ElementAnimation.fromJson({'type': 'press', 'intensity': 9.0})!
            .intensity,
        1.0,
      );
      expect(
        ElementAnimation.fromJson({'type': 'press', 'intensity': -1.0})!
            .intensity,
        0.0,
      );
    });

    test('缺时长时回落该类型的建议值', () {
      // 按压 150ms 与粒子 700ms 差很多，统一给 300 会让按压显得黏手。
      expect(
        ElementAnimation.fromJson({'type': 'press'})!.durationMs,
        ElementAnimationType.press.defaultDurationMs,
      );
      expect(
        ElementAnimation.fromJson({'type': 'particle_burst'})!.durationMs,
        ElementAnimationType.particleBurst.defaultDurationMs,
      );
    });
  });

  group('旧字段兼容（老卡不迁移也能播）', () {
    test('读得懂旧的 surface 按压字段', () {
      final anim = ElementAnimation.readFrom({
        'anim_trigger': 'click_to_surface_press',
        'anim_duration': 150,
        'anim_timestamp': 1700000000000,
      })!;
      expect(anim.type, ElementAnimationType.press);
      expect(anim.durationMs, 150);
      expect(anim.timestamp, 1700000000000);
    });

    test('旧的 rippleRadius 换算成相对强度', () {
      // 旧字段是绝对像素（默认 150），新模型用 0~1 相对值，
      // 这样元件尺寸变化时不用重配。
      final anim = ElementAnimation.readFrom({
        'anim_trigger': 'click_to_surface_ripple',
        'anim_radius': 250.0,
      })!;
      expect(anim.type, ElementAnimationType.ripple);
      expect(anim.intensity, 1.0);
    });

    test('读得懂旧的 indicator 闪烁字段', () {
      final anim = ElementAnimation.readFrom({
        'eventFlashTimestamp': 1700000000000,
        'eventFlashDurationMs': 400,
        'eventFlashColor': 0xFFFFA726,
      })!;
      expect(anim.type, ElementAnimationType.flash);
      expect(anim.durationMs, 400);
      expect(anim.colorValue, 0xFFFFA726);
    });

    test('新字段优先于旧字段', () {
      // 作者在外观页改过之后就该以新配置为准，
      // 否则旧字段会把刚配好的值盖回去。
      final anim = ElementAnimation.readFrom({
        '__anim': {'type': 'glow_pulse', 'durationMs': 900},
        'anim_trigger': 'click_to_surface_press',
        'anim_duration': 150,
      })!;
      expect(anim.type, ElementAnimationType.glowPulse);
      expect(anim.durationMs, 900);
    });

    test('没有任何动画字段时返回 null', () {
      expect(ElementAnimation.readFrom({'text': 'hi'}), isNull);
    });
  });

  group('写入配置', () {
    test('写新字段的同时清掉旧字段', () {
      // 不清的话 readFrom 的兼容分支会把旧值读出来，
      // 表现为「明明改了配置却还是老样子」。
      final props = <String, dynamic>{
        'anim_trigger': 'click_to_surface_press',
        'anim_duration': 150,
        'anim_radius': 150.0,
        'anim_timestamp': 123,
      };
      ElementAnimation.writeConfig(
        props,
        const ElementAnimation(type: ElementAnimationType.ripple),
      );
      expect(props.containsKey('anim_trigger'), isFalse);
      expect(props.containsKey('anim_duration'), isFalse);
      expect(props.containsKey('anim_radius'), isFalse);
      expect(props.containsKey('anim_timestamp'), isFalse);
      expect(ElementAnimation.readFrom(props)!.type,
          ElementAnimationType.ripple);
    });

    test('关闭动画会连旧字段一并清除', () {
      // 只删新字段的话，旧字段仍会被兼容分支读出来，
      // 表现为「关掉了动画却还在播」。
      final props = <String, dynamic>{
        '__anim': {'type': 'press'},
        'anim_trigger': 'click_to_surface_press',
      };
      ElementAnimation.writeConfig(props, null);
      expect(ElementAnimation.readFrom(props), isNull);
    });

    test('保存配置不会顺手触发一次动画', () {
      // 时间戳属于「运行时触发」，编辑器保存必须保留原值，
      // 否则每次点保存都会看到组件闪一下。
      final props = <String, dynamic>{
        '__anim': {'type': 'press', 'ts': 1700000000000},
      };
      ElementAnimation.writeConfig(
        props,
        const ElementAnimation(
          type: ElementAnimationType.press,
          durationMs: 200,
        ),
      );
      expect(ElementAnimation.readFrom(props)!.timestamp, 1700000000000);
      expect(ElementAnimation.readFrom(props)!.durationMs, 200);
    });
  });

  group('触发打戳', () {
    test('已配动画的元件能打戳', () {
      final props = <String, dynamic>{
        '__anim': {'type': 'press', 'durationMs': 150},
      };
      expect(ElementAnimation.stamp(props, nowMs: 999), isTrue);
      expect(ElementAnimation.readFrom(props)!.timestamp, 999);
    });

    test('没配动画的元件不打戳', () {
      // 连线只负责「触发」，播不播由元件决定。
      // 作者没给这个元件配动画，就说明他不想让它动。
      final props = <String, dynamic>{'text': 'hi'};
      expect(ElementAnimation.stamp(props), isFalse);
      expect(props.containsKey(ElementAnimation.propsKey), isFalse);
    });

    test('打戳会清掉两套旧时间戳，避免打架', () {
      final props = <String, dynamic>{
        'eventFlashTimestamp': 111,
        'eventFlashDurationMs': 300,
        'eventFlashColor': 0xFFFFA726,
      };
      expect(ElementAnimation.stamp(props, nowMs: 999), isTrue);
      expect(props.containsKey('eventFlashTimestamp'), isFalse);
      expect(props.containsKey('anim_timestamp'), isFalse);
      final anim = ElementAnimation.readFrom(props)!;
      expect(anim.type, ElementAnimationType.flash);
      expect(anim.timestamp, 999);
      // 旧配置的颜色要保下来，不能因为迁移而变色。
      expect(anim.colorValue, 0xFFFFA726);
    });

    test('连续触发会刷新时间戳', () {
      final props = <String, dynamic>{
        '__anim': {'type': 'ripple'},
      };
      ElementAnimation.stamp(props, nowMs: 100);
      ElementAnimation.stamp(props, nowMs: 500);
      expect(ElementAnimation.readFrom(props)!.timestamp, 500);
    });
  });

  group('播放窗口判定', () {
    test('刚触发时处于播放中', () {
      const anim = ElementAnimation(
        type: ElementAnimationType.press,
        durationMs: 150,
        timestamp: 1000,
      );
      expect(anim.isActiveAt(1000), isTrue);
      expect(anim.isActiveAt(1100), isTrue);
    });

    test('超过时长加余量后停止', () {
      const anim = ElementAnimation(
        type: ElementAnimationType.press,
        durationMs: 150,
        timestamp: 1000,
      );
      // 余量 200ms：写入时间戳与真正开始绘制之间隔着一帧调度，
      // 卡帧时严格按 duration 判定会把动画提前掐掉。
      expect(anim.isActiveAt(1349), isTrue);
      expect(anim.isActiveAt(1351), isFalse);
    });

    test('从未触发过则不播放', () {
      const anim = ElementAnimation(type: ElementAnimationType.press);
      expect(anim.isActiveAt(999999), isFalse);
    });
  });

  group('类型元数据', () {
    test('每种类型的存储键唯一', () {
      final keys =
          ElementAnimationType.values.map((t) => t.storageKey).toSet();
      expect(keys.length, ElementAnimationType.values.length);
    });

    test('存储键往返稳定', () {
      for (final t in ElementAnimationType.values) {
        expect(ElementAnimationTypeX.fromStorage(t.storageKey), t,
            reason: t.name);
      }
    });

    test('旧方案 id 能映射到对应类型', () {
      expect(
        ElementAnimationTypeX.fromStorage('click_to_surface_press'),
        ElementAnimationType.press,
      );
      expect(
        ElementAnimationTypeX.fromStorage('click_to_surface_ripple'),
        ElementAnimationType.ripple,
      );
    });

    test('每种曲线都有中文标签', () {
      for (final c in ElementAnimationCurve.values) {
        expect(c.label.isNotEmpty, isTrue, reason: c.name);
      }
    });
  });
}
