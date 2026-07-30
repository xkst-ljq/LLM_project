import 'package:flutter/material.dart';

/// A12：统一动画通道。
///
/// ## 为什么要有这一层
///
/// 此前每种动画各有一套字段：surface 按压/涟漪用 `anim_trigger` +
/// `anim_timestamp` + `anim_duration` + `anim_radius`，
/// indicator 闪烁用另一套 `eventFlashTimestamp` + `eventFlashColor` +
/// `eventFlashDurationMs`。两套时间戳、两套时长键、两套触发判定。
/// 再加数值跳动 / 发光脉冲 / 粒子就是五套，运行端与渲染端都要各自维护。
///
/// 而且 `_buildAnimatedSurface` 只在 `case 'surface' / 'base_box'` 里调用，
/// 也就是**只有面板能播动画**——数值跳动的目标是 progress/text，
/// 发光脉冲可能用在 indicator/image，旧结构根本接不上。
///
/// 这里收敛为**单一字段族 `__anim`**：新增动画类型只是多一个 enum 值，
/// 运行端一行都不用改。
///
/// ## 参数归属
///
/// 动画参数（时长、曲线、幅度）挂在**元件**上，不在连线方案里。
/// 依据是既定的分工线：动画是「这个元件在这张卡里怎么表现」，
/// 属于 Assembly 的元件配置；连线只负责「什么时候触发」。
///
/// 好处：同一元件被多条连线驱动时只需配一次。
/// 旧做法把 `durationMs` 放进 `SchemeParamField`，
/// 两条连线指向同一个面板就得配两遍，还可能配出两个不同的值。
enum ElementAnimationType {
  /// 按压凹陷。原 `click_to_surface_press`。
  press,

  /// 水波折射（片元着色器实现）。
  ///
  /// 早期由已废弃的 `click_to_surface_ripple` 方案驱动，
  /// 现在改为在元件外观页配置、用 `event_to_animation` 触发。
  ripple,

  /// 短暂高亮。原 indicator 的 `eventFlash*`。
  flash,

  /// 数值跳动：目标值变化时先放大再回弹。
  numberPop,

  /// 发光脉冲：外发光呼吸一次。
  glowPulse,

  /// 粒子迸发。
  particleBurst,
}

/// 动画曲线的可选项。
///
/// 只开放几条常用曲线而非全部 `Curves`：作者要的是「快出慢入」这类
/// 手感描述，几十条曲线名反而选不动，与外观页用固定色板同理。
enum ElementAnimationCurve {
  easeInOut,
  easeOut,
  easeIn,
  linear,
  bounceOut,
  elasticOut,
}

extension ElementAnimationCurveX on ElementAnimationCurve {
  Curve get curve => switch (this) {
        ElementAnimationCurve.easeInOut => Curves.easeInOut,
        ElementAnimationCurve.easeOut => Curves.easeOutCubic,
        ElementAnimationCurve.easeIn => Curves.easeInCubic,
        ElementAnimationCurve.linear => Curves.linear,
        ElementAnimationCurve.bounceOut => Curves.bounceOut,
        ElementAnimationCurve.elasticOut => Curves.elasticOut,
      };

  String get label => switch (this) {
        ElementAnimationCurve.easeInOut => '平滑进出',
        ElementAnimationCurve.easeOut => '快出慢停',
        ElementAnimationCurve.easeIn => '慢起快收',
        ElementAnimationCurve.linear => '匀速',
        ElementAnimationCurve.bounceOut => '弹跳',
        ElementAnimationCurve.elasticOut => '回弹',
      };
}

extension ElementAnimationTypeX on ElementAnimationType {
  String get storageKey => switch (this) {
        ElementAnimationType.press => 'press',
        ElementAnimationType.ripple => 'ripple',
        ElementAnimationType.flash => 'flash',
        ElementAnimationType.numberPop => 'number_pop',
        ElementAnimationType.glowPulse => 'glow_pulse',
        ElementAnimationType.particleBurst => 'particle_burst',
      };

  String get label => switch (this) {
        ElementAnimationType.press => '按压凹陷',
        ElementAnimationType.ripple => '水波扩散',
        ElementAnimationType.flash => '短暂高亮',
        ElementAnimationType.numberPop => '数值跳动',
        ElementAnimationType.glowPulse => '发光脉冲',
        ElementAnimationType.particleBurst => '粒子迸发',
      };

  /// 该动画的建议默认时长。
  ///
  /// 按压要快（超过 200ms 会显得黏手），粒子要久一点才看得清扩散。
  int get defaultDurationMs => switch (this) {
        ElementAnimationType.press => 150,
        ElementAnimationType.ripple => 300,
        ElementAnimationType.flash => 300,
        ElementAnimationType.numberPop => 260,
        ElementAnimationType.glowPulse => 600,
        ElementAnimationType.particleBurst => 700,
      };

  static ElementAnimationType? fromStorage(String? raw) {
    if (raw == null) return null;
    for (final t in ElementAnimationType.values) {
      if (t.storageKey == raw) return t;
    }
    // 兼容旧数据：`anim_trigger` 存的是完整方案 id。
    return switch (raw) {
      'click_to_surface_press' => ElementAnimationType.press,
      // 方案本身已移除，但老卡的 props 里仍可能存着这个字符串，
      // 迁移映射必须保留，否则旧数据读不出动画类型。
      'click_to_surface_ripple' => ElementAnimationType.ripple,
      _ => null,
    };
  }
}

/// 元件的动画配置 + 最近一次触发的时间戳。
///
/// 配置部分由作者在外观页设置；`timestamp` 由运行端在连线触发时写入。
/// 两者放同一个字段族，渲染层读一次就够。
class ElementAnimation {
  /// 属性键。双下划线前缀表示引擎内部字段，与作者可见的属性区分开。
  static const String propsKey = '__anim';

  final ElementAnimationType type;
  final int durationMs;
  final ElementAnimationCurve curve;

  /// 动画幅度，0~1 的相对强度。
  ///
  /// 各动画自行解释：按压是凹陷深度、脉冲是发光半径、跳动是放大比例。
  /// 用相对值而非绝对像素，元件尺寸变化时不用重配。
  final double intensity;

  /// 附加色。发光脉冲、闪烁、粒子用它；为空时回落到元件主色。
  final int? colorValue;

  /// 最近一次触发的毫秒时间戳。0 表示从未触发。
  final int timestamp;

  const ElementAnimation({
    required this.type,
    this.durationMs = 300,
    this.curve = ElementAnimationCurve.easeInOut,
    this.intensity = 0.6,
    this.colorValue,
    this.timestamp = 0,
  });

  /// 动画是否仍在播放窗口内。
  ///
  /// 多给 200ms 余量：写入时间戳与真正开始绘制之间隔着一帧调度，
  /// 卡帧时若严格按 duration 判定，动画会被提前掐掉。
  bool isActiveAt(int nowMs) {
    if (timestamp <= 0) return false;
    return (nowMs - timestamp) < (durationMs + 200);
  }

  ElementAnimation copyWith({
    ElementAnimationType? type,
    int? durationMs,
    ElementAnimationCurve? curve,
    double? intensity,
    int? colorValue,
    bool clearColor = false,
    int? timestamp,
  }) {
    return ElementAnimation(
      type: type ?? this.type,
      durationMs: durationMs ?? this.durationMs,
      curve: curve ?? this.curve,
      intensity: intensity ?? this.intensity,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.storageKey,
        'durationMs': durationMs,
        'curve': curve.name,
        'intensity': intensity,
        if (colorValue != null) 'color': colorValue,
        if (timestamp > 0) 'ts': timestamp,
      };

  static ElementAnimation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<dynamic, dynamic>();
    final type =
        ElementAnimationTypeX.fromStorage(map['type']?.toString());
    if (type == null) return null;
    final curveName = map['curve']?.toString();
    return ElementAnimation(
      type: type,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? type.defaultDurationMs,
      curve: ElementAnimationCurve.values.firstWhere(
        (c) => c.name == curveName,
        orElse: () => ElementAnimationCurve.easeInOut,
      ),
      intensity:
          ((map['intensity'] as num?)?.toDouble() ?? 0.6).clamp(0.0, 1.0),
      colorValue: (map['color'] as num?)?.toInt(),
      timestamp: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }

  /// 从元件属性里解析动画配置，**兼容两套旧字段**。
  ///
  /// 读取顺序：新字段 `__anim` → 旧 `anim_*` → 旧 `eventFlash*`。
  /// 老角色卡不做迁移也能正常播放，作者一旦在外观页改过就写成新格式。
  static ElementAnimation? readFrom(Map<String, dynamic> props) {
    final fresh = fromJson(props[propsKey]);
    if (fresh != null) return fresh;

    // 旧字段族一：surface 按压 / 涟漪。
    final legacyTrigger = props['anim_trigger']?.toString();
    final legacyType = ElementAnimationTypeX.fromStorage(legacyTrigger);
    if (legacyType != null) {
      final duration = (props['anim_duration'] as num?)?.toInt() ??
          legacyType.defaultDurationMs;
      // 旧的 anim_radius 是绝对像素（默认 150），换算成相对强度。
      final radius = (props['anim_radius'] as num?)?.toDouble() ?? 150.0;
      return ElementAnimation(
        type: legacyType,
        durationMs: duration,
        intensity: (radius / 250.0).clamp(0.0, 1.0),
        timestamp: (props['anim_timestamp'] as num?)?.toInt() ?? 0,
      );
    }

    // 旧字段族二：indicator 事件闪烁。
    final flashTs = (props['eventFlashTimestamp'] as num?)?.toInt() ?? 0;
    if (flashTs > 0) {
      return ElementAnimation(
        type: ElementAnimationType.flash,
        durationMs: (props['eventFlashDurationMs'] as num?)?.toInt() ?? 300,
        colorValue: (props['eventFlashColor'] as num?)?.toInt(),
        timestamp: flashTs,
      );
    }
    return null;
  }

  /// 把配置写回属性表（不含时间戳，供编辑器保存用）。
  static void writeConfig(
    Map<String, dynamic> props,
    ElementAnimation? animation,
  ) {
    if (animation == null) {
      props.remove(propsKey);
      // 同时清掉旧字段，否则 readFrom 的兼容分支会把它又读出来，
      // 表现为「关掉动画却还在播」。
      props
        ..remove('anim_trigger')
        ..remove('anim_duration')
        ..remove('anim_radius')
        ..remove('anim_timestamp');
      return;
    }
    // 保留已有时间戳：编辑器保存不应该顺手触发一次动画。
    final existing = fromJson(props[propsKey]);
    props[propsKey] =
        animation.copyWith(timestamp: existing?.timestamp ?? 0).toJson();
    props
      ..remove('anim_trigger')
      ..remove('anim_duration')
      ..remove('anim_radius')
      ..remove('anim_timestamp');
  }

  /// 打一次触发时间戳（运行端在连线触发时调用）。
  ///
  /// 若元件没配动画则什么都不做——连线只负责「触发」，
  /// 「播什么」由元件自己决定。这正是参数归元件的意义：
  /// 作者没给这个元件配动画，就说明他不想让它动。
  static bool stamp(Map<String, dynamic> props, {int? nowMs}) {
    final current = readFrom(props);
    if (current == null) return false;
    props[propsKey] = current
        .copyWith(
          timestamp: nowMs ?? DateTime.now().millisecondsSinceEpoch,
        )
        .toJson();
    // 旧字段已被新字段取代，清掉避免两套时间戳打架。
    props
      ..remove('anim_trigger')
      ..remove('anim_duration')
      ..remove('anim_radius')
      ..remove('anim_timestamp')
      ..remove('eventFlashTimestamp')
      ..remove('eventFlashDurationMs')
      ..remove('eventFlashColor');
    return true;
  }
}

/// 「值变化时自动播放动画」的包裹层。
///
/// ## 为什么需要它
///
/// 数值跳动的自然语义是「进度条的值变了，它自己弹一下」，
/// 不该还要额外接一条 `event_to_animation` 连线——
/// 那等于让作者手动告诉系统「现在数值变了」，系统自己明明知道。
///
/// ## 为什么不写 props
///
/// 最直接的做法是渲染时比较新旧值、变了就打时间戳。但这违反
/// **「渲染函数只读不写」**（见 ASSEMBLY_HANDOFF）：
/// 写进 props 的时间戳会被 `_persistAssemblyElements` 存进角色卡，
/// 既污染产物，又会让作者下次打开时凭空看到一次动画。
/// 配额归零就是这么踩过一次的。
///
/// 因此改用 **StatefulWidget 的本地状态**记住上一次的值：
/// 它随 widget 树存活，不进入任何持久化路径。
class ValueChangeAnimator extends StatefulWidget {
  /// 参与比较的值。变化即触发一次动画。
  final Object? value;

  /// 元件配置的动画；为 null 时直接透传 child。
  final ElementAnimation? animation;

  /// 动画帧的绘制回调。由渲染器传入，避免这里依赖具体绘制实现。
  final Widget Function(
    BuildContext context,
    ElementAnimation animation,
    double progress,
    Widget child,
  ) frameBuilder;

  final Widget child;

  const ValueChangeAnimator({
    super.key,
    required this.value,
    required this.animation,
    required this.frameBuilder,
    required this.child,
  });

  @override
  State<ValueChangeAnimator> createState() => _ValueChangeAnimatorState();
}

class _ValueChangeAnimatorState extends State<ValueChangeAnimator>
    with TickerProviderStateMixin {
  Object? _lastValue;
  bool _initialized = false;

  /// 同时在播的波次。
  ///
  /// ## 为什么要多波次
  ///
  /// 最初只有一个「正在播」的标记：播放期间的新变化只记一个 bool，
  /// 等这一轮播完再补一轮。那是**串行排队**——
  /// 每次触发都得等满一个 duration，用户反馈「每次的动画等待时间太长」。
  ///
  /// 现在改为并发：新变化立刻起一道新波，与仍在播的旧波**叠加**，
  /// 各自独立走完自己的生命周期。连续变值会得到层层叠起的涟漪，
  /// 而不是一段接一段的等待。
  ///
  /// 上限 [_maxConcurrent]：波次太多会糊成一团，也白耗性能。
  /// 超出时淘汰最老的一道——它本来也快结束了。
  final List<AnimationController> _waves = <AnimationController>[];

  /// 同时存在的波次上限。
  ///
  /// 3 道足够表达「连续变化」的层次感；再多在小组件上会互相盖住。
  static const int _maxConcurrent = 3;

  /// 两次起波的最小间隔。
  ///
  /// 拖滑块时值每帧都在变，不限流会每帧起一道波，
  /// 瞬间堆满上限且彼此相位几乎相同，看起来只是一道很粗的波。
  static const Duration _minGap = Duration(milliseconds: 90);
  DateTime? _lastSpawn;

  @override
  void initState() {
    super.initState();
    _lastValue = widget.value;
    // 首帧不播：刚进页面时所有值都是「从无到有」，
    // 全部弹一遍会像页面在抽搐。
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant ValueChangeAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncValue();
  }

  @override
  void dispose() {
    for (final c in _waves) {
      c.dispose();
    }
    _waves.clear();
    super.dispose();
  }

  void _syncValue() {
    if (!_initialized) return;
    if (widget.value == _lastValue) return;
    _lastValue = widget.value;
    final animation = widget.animation;
    if (animation == null) return;

    // 限流：见 _minGap 的说明。
    final now = DateTime.now();
    final last = _lastSpawn;
    if (last != null && now.difference(last) < _minGap) return;
    _lastSpawn = now;

    _spawnWave(animation.durationMs);
  }

  void _spawnWave(int durationMs) {
    // 超出上限就淘汰最老的一道（它本来也快结束了）。
    while (_waves.length >= _maxConcurrent) {
      final oldest = _waves.removeAt(0);
      oldest.dispose();
    }

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    _waves.add(controller);

    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      // 结束回调发生在构建过程中，直接 setState 会撞上
      // 「widget tree was locked」——与双击断开那次崩溃同源。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          controller.dispose();
          return;
        }
        if (_waves.remove(controller)) {
          controller.dispose();
          setState(() {});
        }
      });
    });

    controller.forward(from: 0.0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation;
    if (animation == null || _waves.isEmpty) return widget.child;

    // 逐层包裹：最老的波在最内层，新波叠在外面。
    //
    // 这样多道波的效果自然复合——比如两道数值跳动会叠出更大的幅度，
    // 两道水波会前后错开地扫过，正是「重叠播放」想要的观感。
    return AnimatedBuilder(
      animation: Listenable.merge(_waves),
      builder: (ctx, _) {
        var result = widget.child;
        for (final c in _waves) {
          result = widget.frameBuilder(ctx, animation, c.value, result);
        }
        return result;
      },
    );
  }
}

