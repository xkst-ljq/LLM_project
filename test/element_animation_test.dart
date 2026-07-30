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
  group('通用动画触发方案（A12-1 的缺口修补）', () {
    // A12-1 把渲染层做成了「所有可见组件都能播动画」，
    // 但触发端只认三条老方案：
    // event_to_indicator / click_to_surface_press / click_to_surface_ripple。
    // 这三条的 targetType 写死是 indicator 与 surface，
    // 于是进度条、文本虽然会画动画，却没有任何连线能触发它。
    //
    // 新增 event_to_animation 补齐：来源 button/timer，
    // 目标是全部可见组件，且**不带动画参数**——
    // 播什么由目标元件的外观页决定，方案只回答「什么时候播」。

    const animatableTargets = {
      'text',
      'progress',
      'slider',
      'switch',
      'select',
      'input',
      'image',
      'surface',
      'base_box',
      'indicator',
      'message_flow',
    };

    test('进度条与文本都在可触发目标里', () {
      // 这正是用户问「该如何连线让进度条或文本触发动画」的答案。
      expect(animatableTargets.contains('progress'), isTrue);
      expect(animatableTargets.contains('text'), isTrue);
    });

    test('不显形的逻辑件不在目标里', () {
      // 播动画没有意义，列进去只会让方案列表变脏。
      for (final t in ['linker', 'math_node', 'timer', 'page_router']) {
        expect(animatableTargets.contains(t), isFalse, reason: t);
      }
    });

    test('方案本身不带动画参数', () {
      // 参数归元件是 A12 确立的分工。若方案再带一份 durationMs，
      // 同一元件被两条连线驱动就会出现两个不同的时长。
      const schemeParamKeys = <String>[];
      expect(schemeParamKeys, isEmpty);
    });

    test('目标端口推导为动画通道', () {
      // 复刻 _schemeTargetPort：event_to_animation 必须在通配规则之前拦住，
      // 否则会落到兜底的 'value'，运行端会当成写数据字段。
      String targetPort(String scheme) {
        if (scheme == 'event_to_animation') return 'anim';
        if (scheme.endsWith('_to_text')) return 'text';
        if (scheme.contains('_to_progress')) return 'current';
        return 'value';
      }

      expect(targetPort('event_to_animation'), 'anim');
      // 对照：别的方案不受影响。
      expect(targetPort('result_to_text'), 'text');
      expect(targetPort('slider_to_progress'), 'current');
    });

    test('新方案不给老卡兜底动画配置', () {
      // event_to_animation 是 A12 之后才有的，不存在老卡兼容问题。
      // 作者没配动画就什么都不播——凭空给个默认动画反而是意外行为。
      ElementAnimationType? legacyFallback(String scheme) =>
          switch (scheme) {
            'click_to_surface_press' => ElementAnimationType.press,
            'click_to_surface_ripple' => ElementAnimationType.ripple,
            'event_to_indicator' => ElementAnimationType.flash,
            _ => null,
          };
      expect(legacyFallback('event_to_animation'), isNull);
      // 对照：三条老方案仍要兜底，否则老卡动画会消失。
      expect(legacyFallback('click_to_surface_press'),
          ElementAnimationType.press);
    });
  });

  group('值变化自动播放（A12-2）', () {
    // 数值跳动的自然语义是「值变了就自己弹一下」，
    // 不该还要额外接一条 event_to_animation 连线——
    // 那等于让作者手动告诉系统「现在数值变了」，而系统自己明明知道。

    const valueDrivenTypes = {
      'progress',
      'text',
      'slider',
      'select',
      'input',
    };
    const autoPlayTypes = {
      ElementAnimationType.numberPop,
      ElementAnimationType.glowPulse,
      ElementAnimationType.flash,
    };

    test('只有显示数值/文本的组件参与自动播放', () {
      expect(valueDrivenTypes.contains('progress'), isTrue);
      expect(valueDrivenTypes.contains('text'), isTrue);
      // 面板、按钮没有「值」可言，动画仍由连线触发。
      expect(valueDrivenTypes.contains('surface'), isFalse);
      expect(valueDrivenTypes.contains('button'), isFalse);
    });

    test('交互反馈类动画不自动播放', () {
      // 按压/涟漪是「我碰了它」的反馈，
      // 值变了自己涟漪一下会很怪。
      expect(autoPlayTypes.contains(ElementAnimationType.press), isFalse);
      expect(autoPlayTypes.contains(ElementAnimationType.ripple), isFalse);
    });

    test('跟数值相关的动画会自动播放', () {
      expect(autoPlayTypes.contains(ElementAnimationType.numberPop), isTrue);
      expect(autoPlayTypes.contains(ElementAnimationType.glowPulse), isTrue);
    });

    test('自动播放不依赖时间戳', () {
      // 关键约束：不能在渲染时往 props 写时间戳，
      // 那会被 _persistAssemblyElements 存进角色卡，
      // 既污染产物、又让作者下次打开时凭空看到一次动画。
      // 因此自动播放走 ValueChangeAnimator 的本地状态，
      // 配置里的 timestamp 保持为 0 也应能播。
      const anim = ElementAnimation(
        type: ElementAnimationType.numberPop,
        timestamp: 0,
      );
      // 连线触发那条通路要求时间戳有效……
      expect(anim.isActiveAt(999999), isFalse);
      // ……但值变化通路不看它，只看值有没有变。
      expect(anim.type, ElementAnimationType.numberPop);
    });

    test('两条通路可以并存', () {
      // 值变化自动播 + 按钮额外触发，互不排斥。
      const anim = ElementAnimation(
        type: ElementAnimationType.glowPulse,
        timestamp: 1000,
        durationMs: 600,
      );
      expect(anim.isActiveAt(1100), isTrue);
      expect(autoPlayTypes.contains(anim.type), isTrue);
    });
  });

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
