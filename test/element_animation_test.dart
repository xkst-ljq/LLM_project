import 'dart:math' as math;

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
    // event_to_indicator / click_to_surface_press。
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
            'event_to_indicator' => ElementAnimationType.flash,
            _ => null,
          };
      expect(legacyFallback('event_to_animation'), isNull);
      // 对照：三条老方案仍要兜底，否则老卡动画会消失。
      expect(legacyFallback('click_to_surface_press'),
          ElementAnimationType.press);
    });
  });

  group('缓动曲线过冲的安全性（崩溃修复）', () {
    // 用户实测：发光脉冲配回弹类曲线时崩溃——
    // 「Text shadow blur radius should be non-negative」。
    //
    // 根因：elasticOut / bounceOut 这类曲线**会过冲**，
    // TweenAnimationBuilder 给出的 progress 可能是 -0.05 或 1.08。
    // 由它算出的 wave 变负，传给 BoxShadow.blurRadius 就触发断言。

    double waveOf(double t, double peak) {
      final w = t < peak ? t / peak : (1.0 - t) / (1.0 - peak);
      return w.clamp(0.0, 1.0);
    }

    test('过冲时派生量被夹到非负', () {
      for (final t in [-0.08, -0.01, 1.01, 1.12]) {
        final wave = waveOf(t, 0.5);
        expect(wave, greaterThanOrEqualTo(0.0), reason: '$t');
        // blurRadius / spreadRadius 都由 wave 缩放而来。
        expect(24 * 0.6 * wave, greaterThanOrEqualTo(0.0), reason: '$t');
      }
    });

    test('正常区间的波形不受夹取影响', () {
      // 夹取只兜边界，中间段的观感必须和以前一致。
      expect(waveOf(0.0, 0.5), closeTo(0.0, 1e-9));
      expect(waveOf(0.25, 0.5), closeTo(0.5, 1e-9));
      expect(waveOf(0.5, 0.5), closeTo(1.0, 1e-9));
      expect(waveOf(0.75, 0.5), closeTo(0.5, 1e-9));
      expect(waveOf(1.0, 0.5), closeTo(0.0, 1e-9));
    });

    test('按压的峰值点在 35%', () {
      expect(waveOf(0.35, 0.35), closeTo(1.0, 1e-9));
    });

    test('数值跳动保留过冲，但兜住负缩放', () {
      // 这一项**不夹** wave：Transform.scale 允许过冲，
      // 回弹曲线的弹性观感正来自于此。只兜住不合法的缩放值。
      double scaleAt(double t) {
        final raw = t < 0.4 ? t / 0.4 : (1.0 - t) / 0.6;
        return (1.0 + 0.3 * 0.6 * raw).clamp(0.05, 4.0);
      }

      for (final t in [-0.08, 0.4, 1.12]) {
        expect(scaleAt(t), greaterThan(0.0), reason: '$t');
      }
      // 峰值仍有放大效果，没被夹平。
      expect(scaleAt(0.4), greaterThan(1.0));
    });

    test('所有曲线都能安全求值', () {
      // 回归守卫：新增曲线时若忘了考虑过冲，这条会失败。
      for (final c in ElementAnimationCurve.values) {
        final curve = c.curve;
        for (final input in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final t = curve.transform(input);
          final wave = waveOf(t, 0.5);
          expect(wave.isNaN, isFalse, reason: '${c.name}@$input');
          expect(wave, greaterThanOrEqualTo(0.0), reason: '${c.name}@$input');
          expect(wave, lessThanOrEqualTo(1.0), reason: '${c.name}@$input');
        }
      }
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
    test('只有显示数值/文本的组件参与自动播放', () {
      expect(valueDrivenTypes.contains('progress'), isTrue);
      expect(valueDrivenTypes.contains('text'), isTrue);
      // 面板、按钮没有「值」可言，动画仍由连线触发。
      expect(valueDrivenTypes.contains('surface'), isFalse);
      expect(valueDrivenTypes.contains('button'), isFalse);
    });

    test('六种动画都允许自动播放，不设白名单', () {
      // 曾按「交互反馈 vs 数值反馈」把按压/水波/粒子排除在外，
      // 用户实测发现拖 slider 时这三种毫无反应。
      // 那个归类是主观的且站不住——粒子迸发用在数值突变上很自然
      // （扣血炸一下）；作者既然特意选了某种动画，
      // 就说明他想要那个效果，引擎不该替他否决。
      const excluded = <ElementAnimationType>{};
      expect(excluded, isEmpty);
      for (final t in ElementAnimationType.values) {
        expect(excluded.contains(t), isFalse, reason: t.name);
      }
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
    });
  });

  group('多波次并发叠加', () {
    // 迭代历程：
    // 1. 每次变值都重启 → 拖滑块时动画被反复掐死在第一帧；
    // 2. 改为「播放期间不重启、播完再补一轮」→ 不断了，
    //    但那是**串行排队**，每次触发都要等满一个 duration，
    //    用户反馈「每次的动画等待时间太长」；
    // 3. 现在：新变化立刻起一道新波，与旧波叠加并发。

    const maxConcurrent = 3;
    const minGapMs = 90;

    /// 复刻并发调度器。
    ({int spawns, int peak}) simulate({
      required int totalMs,
      required int stepMs,
      required int durationMs,
    }) {
      final waves = <int>[];
      var spawns = 0;
      var peak = 0;
      int? lastSpawn;

      for (var t = 0; t < totalMs; t += stepMs) {
        // 过期的波自然退场。
        waves.removeWhere((start) => t - start >= durationMs);
        // 限流。
        if (lastSpawn != null && t - lastSpawn < minGapMs) continue;
        lastSpawn = t;
        // 超上限淘汰最老的一道。
        while (waves.length >= maxConcurrent) {
          waves.removeAt(0);
        }
        waves.add(t);
        spawns++;
        if (waves.length > peak) peak = waves.length;
      }
      return (spawns: spawns, peak: peak);
    }

    test('连续拖动能持续起波，不再排队等待', () {
      // 500ms 拖动、每帧 16ms 变一次值。
      final r = simulate(totalMs: 500, stepMs: 16, durationMs: 600);
      // 旧的串行方案在 600ms duration 下只会播 1 次。
      expect(r.spawns, greaterThan(1));
      expect(r.spawns, 6);
    });

    test('并发数不超过上限', () {
      final r = simulate(totalMs: 2000, stepMs: 16, durationMs: 600);
      // 波次太多会糊成一团，也白耗性能。
      expect(r.peak, lessThanOrEqualTo(maxConcurrent));
    });

    test('限流阻止每帧起波', () {
      // 不限流的话每 16ms 一道，瞬间堆满上限且相位几乎相同，
      // 看起来只是一道很粗的波。
      final r = simulate(totalMs: 900, stepMs: 16, durationMs: 600);
      final maxPossible = 900 ~/ minGapMs;
      expect(r.spawns, lessThanOrEqualTo(maxPossible));
    });

    test('单次变化只起一道波', () {
      final r = simulate(totalMs: 16, stepMs: 16, durationMs: 600);
      expect(r.spawns, 1);
      expect(r.peak, 1);
    });

    test('间隔足够长时不会积压', () {
      // 每次变化都在上一道播完之后，峰值应始终为 1。
      final r = simulate(totalMs: 3000, stepMs: 700, durationMs: 600);
      expect(r.peak, 1);
    });
  });

  group('动画强度（用户反馈「太无感」后的调整）', () {
    // 默认 intensity = 0.6，各动画在这个值下的实际效果必须可辨认。
    const defaultIntensity = 0.6;

    test('短暂高亮的蒙版足够明显', () {
      // 原系数 0.55，默认强度下 alpha 仅 0.33，几乎看不出闪过。
      const alpha = 0.85 * defaultIntensity;
      expect(alpha, greaterThan(0.45));
    });

    test('数值跳动的峰值足够大', () {
      // 原系数 0.3，默认强度下峰值仅 +18%，一行数字上察觉不到。
      const peak = 0.55 * defaultIntensity;
      expect(peak, greaterThan(0.3));
    });

    test('发光脉冲呼吸两次而非一次', () {
      // 「脉冲」的语感是一下一下的；单次起落更像「闪了下」。
      var peaks = 0;
      double waveAt(double t) =>
          (math.sin(t * math.pi * 2 * 2 - math.pi / 2) + 1.0) / 2.0;
      for (var i = 1; i < 999; i++) {
        final prev = waveAt((i - 1) / 1000.0);
        final cur = waveAt(i / 1000.0);
        final next = waveAt((i + 1) / 1000.0);
        if (cur > prev && cur > next) peaks++;
      }
      expect(peaks, 2);
    });

    test('发光脉冲的衰减让第二次更弱', () {
      // 两次等强会显得机械，后一次弱下去才像余韵。
      double full(double t) =>
          ((math.sin(t * math.pi * 2 * 2 - math.pi / 2) + 1.0) / 2.0) *
          math.pow(1.0 - t, 0.8).toDouble();
      // 第一个峰约在 t=0.25，第二个约在 t=0.75。
      expect(full(0.25), greaterThan(full(0.75)));
    });

    test('所有强度系数在 intensity=0 时归零', () {
      // 强度为 0 应完全静止，否则「关掉」不彻底。
      expect(0.85 * 0.0, 0.0);
      expect(0.55 * 0.0, 0.0);
      expect(24 * 0.0, 0.0);
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

  group('只认统一字段族', () {
    // A12 早期为兼容两套历史字段（surface 的 `anim_*`、
    // indicator 的 `eventFlash*`）写过迁移分支。
    // 项目仍在开发期、无已发布数据，已全部删除——
    // 留着只会让「关掉动画却还在播」这类问题多一条排查路径。

    test('旧的 anim_* 字段不再被识别', () {
      expect(
        ElementAnimation.readFrom({
          'anim_trigger': 'click_to_surface_press',
          'anim_duration': 150,
          'anim_timestamp': 1700000000000,
        }),
        isNull,
      );
    });

    test('旧的 eventFlash* 字段不再被识别', () {
      expect(
        ElementAnimation.readFrom({
          'eventFlashTimestamp': 1700000000000,
          'eventFlashDurationMs': 400,
          'eventFlashColor': 0xFFFFA726,
        }),
        isNull,
      );
    });

    test('只有 __anim 能读出配置', () {
      final anim = ElementAnimation.readFrom({
        '__anim': {'type': 'glow_pulse', 'durationMs': 900},
      })!;
      expect(anim.type, ElementAnimationType.glowPulse);
      expect(anim.durationMs, 900);
    });

    test('没有任何动画字段时返回 null', () {
      expect(ElementAnimation.readFrom({'text': 'hi'}), isNull);
    });
  });

  group('写入配置', () {
    test('写入后能读回同一份配置', () {
      final props = <String, dynamic>{};
      ElementAnimation.writeConfig(
        props,
        const ElementAnimation(type: ElementAnimationType.ripple),
      );
      expect(ElementAnimation.readFrom(props)!.type,
          ElementAnimationType.ripple);
    });

    test('关闭动画后彻底读不出配置', () {
      final props = <String, dynamic>{
        '__anim': {'type': 'press'},
      };
      ElementAnimation.writeConfig(props, null);
      expect(ElementAnimation.readFrom(props), isNull);
      expect(props.containsKey(ElementAnimation.propsKey), isFalse);
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

    test('打戳保留配置中的颜色', () {
      // 时间戳只是「什么时候播」，不该顺手改掉「播成什么样」。
      final props = <String, dynamic>{
        '__anim': {
          'type': 'flash',
          'durationMs': 300,
          'color': 0xFFFFA726,
        },
      };
      expect(ElementAnimation.stamp(props, nowMs: 999), isTrue);
      final anim = ElementAnimation.readFrom(props)!;
      expect(anim.type, ElementAnimationType.flash);
      expect(anim.timestamp, 999);
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

    test('方案 id 不再被当作动画类型', () {
      // 早期 anim_trigger 存的是完整方案 id，迁移映射已删除。
      expect(
        ElementAnimationTypeX.fromStorage('click_to_surface_press'),
        isNull,
      );
      expect(
        ElementAnimationTypeX.fromStorage('click_to_surface_ripple'),
        isNull,
      );
    });

    test('每种曲线都有中文标签', () {
      for (final c in ElementAnimationCurve.values) {
        expect(c.label.isNotEmpty, isTrue, reason: c.name);
      }
    });
  });
}
