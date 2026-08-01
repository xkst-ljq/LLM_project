import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'assembly_rich_text.dart';
import 'avatar_scope.dart';
import 'element_animation.dart';
import 'linker_event_bus.dart';
import 'linker_matrix_engine.dart';
import 'linker_service.dart';
import 'ripple_shader.dart';
import 'message_flow_scope.dart';
import 'select_option.dart';
import 'text_highlight_scope.dart';
import 'ui_models.dart';

class UIRenderer {
  /// 将 UIElement 渲染为 Flutter Widget
  static Widget render(BuildContext context, UIElement element) {
    final snapshot = UILinkerSnapshotScope.maybeOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
    final bool isStudio = UISceneModeScope.of(context);
    final module = element.module;
    final controls = module == null
        ? const LinkerTargetControlState()
        : LinkerService.resolveTargetControlState(module);

    // 非工作室（预览模式与运行时）：隐形后台纯逻辑节点。
    if (!isStudio && ['linker', 'math_node', 'page_router'].contains(module?.type)) {
      return const SizedBox.shrink();
    }
    if (!isStudio &&
        (!controls.visible ||
            !LinkerService.isElementVisibleInSurfaceHierarchy(element))) {
      return const SizedBox.shrink();
    }
    // 后台逻辑模式：编辑器中保留节点与通路，预览/运行时不渲染也不接收用户交互。
    const backgroundCapableTypes = {'text', 'switch', 'progress', 'indicator', 'input'};
    if (!isStudio &&
        backgroundCapableTypes.contains(module?.type) &&
        module?.properties['runtimePlacement'] == 'background') {
      return const SizedBox.shrink();
    }

    Widget widget;
    if (element.isComposite && element.composite != null) {
      widget = _renderComposite(context, element.composite!, element.size);
    } else if (!element.isComposite && element.module != null) {
      widget = _renderModule(context, element, element.module!, element.size);
    } else {
      widget = const SizedBox();
    }
    // A12：统一动画通道。
    //
    // 放在这里而不是各 case 内部，是为了让**所有可见组件**都能播动画。
    // 旧实现只在 `case 'surface' / 'base_box'` 里调 `_buildAnimatedSurface`，
    // 等于只有面板会动；数值跳动的目标是 progress/text、
    // 发光脉冲可能用在 indicator/image，旧结构根本接不上。
    //
    // 编辑期不播：动画依赖真实触发时刻，编辑器里只会看到
    // 打开页面那一瞬间的残留帧，反而干扰排版。
    if (!isStudio && module != null) {
      // indicator 的 flash 由它自己改灯色实现（见 _buildIndicatorBlock），
      // 这里跳过，否则会在改色之上再盖一层同色蒙版、颜色变浑。
      final isIndicatorFlash = module.type == 'indicator' &&
          ElementAnimation.readFrom(module.properties)?.type ==
              ElementAnimationType.flash;
      // 进度条的粒子由它自己从填充边缘喷射
      // （见 _EdgeBurstProgressBar），这里必须跳过通用的中心爆发，
      // 否则两层粒子叠加，中心那层会完全盖住边缘喷射
      // ——用户反馈「还是以中点为喷射中心，也不分前后」正是这个。
      final selfHandlesBurst = module.type == 'progress' &&
          ElementAnimation.readFrom(module.properties)?.type ==
              ElementAnimationType.particleBurst;

      if (!isIndicatorFlash && !selfHandlesBurst) {
        widget = _wrapWithAnimation(widget, module, element.size);
      }
      // A12-2：值变化自动播放。
      //
      // 与上面的连线触发是两条独立通路，可以并存：
      // 前者由 button/timer 打时间戳，后者由「值自己变了」驱动。
      //
      // ⚠️ 拖 slider 走的是**这一条**。进度条自带边缘喷射时同样要跳过，
      // 否则中心爆发照样会盖在上面（只改上面那条不够）。
      if (!selfHandlesBurst) {
        widget = _wrapWithValueChangeAnimation(widget, module, element.size);
      }
    }

    final bool shouldBlockInteraction =
        !isStudio &&
        !controls.isInteractive &&
        ['button', 'slider', 'select', 'switch'].contains(module?.type);
    if (shouldBlockInteraction) {
      widget = Opacity(
        opacity: 0.45,
        child: IgnorePointer(child: widget),
      );
    }

    // 围绕元素自身中心旋转。工作室拖拽与运行时聊天渲染共用此入口。
    // 为防止从 0° 拖动发生树结构突变导致手势中断断触，此处自出生起无条件包裹 Transform.rotate。
    return Transform.rotate(
      angle: element.rotation * math.pi / 180.0,
      child: widget,
    );
  }

  static Widget _renderModule(BuildContext context, UIElement element, UIModule module, Size size) {
    // 原子部件只渲染自己的单一职责：
    // progress = 一根条；text = 一段文字；surface/base_box = 一个视觉表面；
    // button/input = 透明逻辑热区，不自带任何边框或底色。
    switch (module.type) {
      case 'progress':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildProgressBar(module, size),
        );
      case 'text':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildTextBlock(module),
        );
      case 'input':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildInputBlock(context, element, module),
        );
      case 'switch':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSwitchBlock(context, element, module),
        );
      case 'line':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildLineBlock(module, size),
        );
      case 'image':
        return SizedBox(
          width: size.width,
          height: size.height,
          // Builder 取新 context：AvatarScope 在运行时视图内部，
          // 沿用外层 context 拿不到（MessageFlowScope 上踩过这个坑）。
          child: Builder(
            builder: (inner) => _buildImageBlock(inner, module),
          ),
        );
      case 'slider':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSlider(context, element, module, size),
        );
      case 'primitive_art':
      case 'surface_art':
      case 'light_effect':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(
            painter: UIPrimitiveArtPainter(module.properties),
          ),
        );
      case 'button':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildButton(context, element, module),
        );
      case 'surface':
      case 'base_box':
        // 动画已上移到 render() 里的统一通道（_wrapWithAnimation），
        // 这里只负责画静态外观。
        return _applyMaterialAndShape(
          module.material,
          module.shape,
          module.color,
          module.opacity,
          module.borderRadius,
          _buildBaseBox(),
          size,
        );
      case 'linker':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildLinkerNode(module, size),
        );
      case 'page_router':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildPageRouterNode(module),
        );
      case 'math_node':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildMathNodeBlock(module, size),
        );
      case 'select':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildSelectBlock(context, element, module, size),
        );
      case 'indicator':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildIndicatorBlock(context, element, module, size),
        );
      case 'message_flow':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildMessageFlowBlock(context, module, size),
        );
      case 'timer':
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _buildTimerBlock(context, element, module, size),
        );
      default:
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Center(
            child: Text(
              '未知控件: ${module.type}',
              style: const TextStyle(color: Color(0xFF111116), fontSize: 12),
            ),
          ),
        );
    }
  }

  /// 复合组件内容的自然尺寸（子元素包围盒的右下边界）。
  ///
  /// 复合件没有单独的「设计尺寸」字段，子元素用绝对坐标摆放，
  /// 因此以包围盒作为缩放基准：外框被拉到多大，
  /// 内容就整体缩放多少倍，而不是只有边框在变。
  ///
  /// 取右下边界而非 `max - min`：子元素坐标以复合件左上角为原点，
  /// 左上留白也是布局的一部分，减掉会让内容贴边。
  static Size compositeNaturalSize(UIComposite composite) {
    var maxX = 0.0;
    var maxY = 0.0;
    for (final child in composite.children) {
      final right = child.offset.dx + child.size.width;
      final bottom = child.offset.dy + child.size.height;
      if (right > maxX) maxX = right;
      if (bottom > maxY) maxY = bottom;
    }
    // 空复合件给个非零兜底，避免除零。
    return Size(maxX <= 0 ? 1.0 : maxX, maxY <= 0 ? 1.0 : maxY);
  }

  static Widget _renderComposite(BuildContext context, UIComposite composite, Size size) {
    // 复合组件渲染其子元素（当前简化实现：stack 布局）
    final children = <Widget>[];
    // 编辑模式下跳过纯后端逻辑组件与后台标记元素，保持画布整洁
    final isStudioMode = UISceneModeScope.of(context);
    const backendTypes = {'linker', 'math_node', 'timer'};
    for (final child in composite.children) {
      final isBackendNode = !child.isComposite && child.module != null && backendTypes.contains(child.module!.type);
      final isBackground = child.module?.properties['runtimePlacement'] == 'background';
      if (isStudioMode && (isBackendNode || isBackground)) {
        continue;
      }
      final childWidget = render(context, child);
      children.add(
        Positioned(
          left: child.offset.dx,
          top: child.offset.dy,
          width: child.size.width,
          height: child.size.height,
          child: childWidget,
        ),
      );
    }

    // 内容按外框尺寸等比缩放。
    //
    // 此前直接把 children 摆进 size 的 Stack 里，子元素用的是绝对坐标，
    // 于是拉伸外框只有边框在变、内容纹丝不动（用户反馈）。
    //
    // 用 Transform.scale 而非 FittedBox：等比因子取宽高比例中的较小值，
    // 内容始终完整可见且不变形；FittedBox 的 contain 虽然也等比，
    // 但会自动居中，导致作者摆好的左上留白被吃掉。
    final natural = compositeNaturalSize(composite);
    final scaleX = size.width / natural.width;
    final scaleY = size.height / natural.height;
    final scale = math.min(scaleX, scaleY);

    Widget content = SizedBox(
      width: natural.width,
      height: natural.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: children,
      ),
    );

    // scale 恒为 1 时也保留 Transform：树结构不随缩放比突变，
    // 避免拖动过程中 widget 被销毁重建、手势中断。
    content = Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: content,
    );

    return SizedBox(
      width: size.width,
      height: size.height,
      child: content,
    );
  }

  static Widget _applyMaterialAndShape(
      UIModuleMaterial material,
      UIModuleShape shape,
      Color color,
      double opacity,
      double borderRadius,
      Widget child,
      Size size,
      ) {
    Widget content = child;

    switch (material) {
      case UIModuleMaterial.glass:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity * 0.25),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.solid:
        content = Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.gradient:
        content = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: opacity), color.withValues(alpha: opacity * 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        );
        break;
      case UIModuleMaterial.outline:
        content = Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: color.withValues(alpha: opacity), width: 2),
          ),
          child: child,
        );
        break;
    }

    // 形状裁剪
    switch (shape) {
      case UIModuleShape.circle:
        return ClipOval(child: content);
      case UIModuleShape.capsule:
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: content,
        );
      case UIModuleShape.rounded:
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        );
      case UIModuleShape.heart:
        return ClipPath(clipper: _PathClipper(getHeartPath), child: content);
      case UIModuleShape.star5:
        return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 5, 0.45)), child: content);
      case UIModuleShape.star4:
        return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 4, 0.4)), child: content);
      case UIModuleShape.rectangle:
        return content;
    }
  }

  static Widget _buildBaseBox() {
    return Container(); // 纯视觉表面，内容由外部决定
  }

  /// A12：统一动画包裹层。
  ///
  /// 所有可见组件共用同一条通道，新增动画类型只是多一个 case，
  /// 不必再各写一套字段与触发判定（见 `element_animation.dart`）。
  static Widget _wrapWithAnimation(Widget child, UIModule module, Size size) {
    final animation = ElementAnimation.readFrom(module.properties);
    if (animation == null) return child;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!animation.isActiveAt(now)) return child;

    // key 带上时间戳：同一元件连续触发时必须重新起播，
    // 否则 TweenAnimationBuilder 会认为参数没变而停在末态。
    //
    // 这里**故意**允许打断——触发源是按钮点击这类离散事件，
    // 连点两下本来就该重新播一次（第二次点击不该被忽略）。
    // 与值变化通路不同：那边的值是连续变化的（拖滑块每帧都变），
    // 打断会让动画永远停在第一帧，因此那边采用「播完再补」
    // （见 ValueChangeAnimator）。
    final key = ValueKey(
      '${animation.type.storageKey}_${animation.timestamp}_'
      '${animation.durationMs}',
    );
    final accent = animation.colorValue != null
        ? Color(animation.colorValue!)
        : module.color;

    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: animation.durationMs),
      curve: animation.curve.curve,
      builder: (ctx, t, inner) {
        return _paintAnimationFrame(
          type: animation.type,
          progress: t,
          intensity: animation.intensity,
          accent: accent,
          borderRadius: module.borderRadius,
          size: size,
          child: inner!,
        );
      },
      child: child,
    );
  }

  /// A12-2：值变化自动播放动画。
  ///
  /// 数值跳动的自然语义是「值变了就自己弹一下」，不该还要额外接一条
  /// `event_to_animation` 连线——那等于让作者手动告诉系统
  /// 「现在数值变了」，而系统自己明明知道。
  ///
  /// 只对**显示数值/文本**的组件生效：面板、按钮之类没有「值」可言，
  /// 它们的动画仍由连线触发。
  ///
  /// 注意这里**不写 props**：时间戳交给 `ValueChangeAnimator` 的本地状态，
  /// 写进 props 会被 `_persistAssemblyElements` 存进角色卡
  /// （见「渲染函数只读不写」）。
  static Widget _wrapWithValueChangeAnimation(
    Widget child,
    UIModule module,
    Size size,
  ) {
    const valueDrivenTypes = {'progress', 'text', 'slider', 'select', 'input'};
    if (!valueDrivenTypes.contains(module.type)) return child;

    final animation = ElementAnimation.readFrom(module.properties);
    if (animation == null) return child;

    // 六种动画都允许值变化自动播放（用户选定）。
    //
    // 曾按「交互反馈 vs 数值反馈」设过白名单，把按压/水波/粒子排除在外。
    // 但那是我的主观归类，实测下来站不住：粒子迸发用在「数值突变」
    // 上很自然（扣血炸一下），而作者既然特意为这个组件选了某种动画，
    // 就说明他想要那个效果，引擎不该替他否决。
    //
    // 副作用是选了按压/水波时，值变化也会播——那是作者自己的选择。

    return ValueChangeAnimator(
      value: _currentDisplayValueOf(module),
      animation: animation,
      frameBuilder: (ctx, anim, progress, inner) => _paintAnimationFrame(
        type: anim.type,
        progress: progress,
        intensity: anim.intensity,
        accent: anim.colorValue != null
            ? Color(anim.colorValue!)
            : module.color,
        borderRadius: module.borderRadius,
        size: size,
        child: inner,
      ),
      child: child,
    );
  }

  /// 取组件当前展示的值，用于变化检测。
  ///
  /// 必须取**解析后**的值而不是 `properties['current']`——
  /// 联动驱动的组件属性里存的是初始值，真正显示的来自
  /// `LinkerService.resolveTargetValue`，比较原始属性永远不会变。
  static Object? _currentDisplayValueOf(UIModule module) {
    final controls = LinkerService.resolveTargetControlState(module);
    if (controls.frozen) return null;
    final linked = LinkerService.resolveTargetValue(module);
    if (linked != null) return linked;
    return switch (module.type) {
      'progress' || 'slider' => module.properties['current'],
      'text' => module.properties['text'],
      'input' => module.properties['text'],
      'select' => module.properties['current'],
      _ => null,
    };
  }

  /// 单帧绘制。按类型分派，每种动画只关心「给定进度画成什么样」。
  static Widget _paintAnimationFrame({
    required ElementAnimationType type,
    required double progress,
    required double intensity,
    required Color accent,
    required double borderRadius,
    required Size size,
    required Widget child,
  }) {
    // ⚠️ 必须夹取：elasticOut / bounceOut 这类曲线**会过冲**，
    // progress 可能是 -0.05 或 1.08。
    // 不夹的话由它算出的 wave 会变负，
    // 传给 BoxShadow.blurRadius 直接触发
    // 「Text shadow blur radius should be non-negative」断言崩溃
    // （用户在发光脉冲 + 回弹曲线下实测到）。
    //
    // 只夹**派生量**而不夹 progress 本身：
    // Transform.scale 需要过冲才有弹性观感，那正是选这类曲线的目的。
    final double t = progress;
    double waveOf(double peak) {
      final w = t < peak ? t / peak : (1.0 - t) / (1.0 - peak);
      return w.clamp(0.0, 1.0);
    }

    switch (type) {
      case ElementAnimationType.press:
        // 前 35% 下沉、后 65% 回弹，与旧 _buildAnimatedSurface 一致。
        final double depth = 0.16 * intensity / 0.6;
        final double wave = waveOf(0.35);
        final double scale = 1.0 - depth * wave;
        final double dim = (0.3 * wave).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(borderRadius),
                    child: Container(
                      color: Colors.black.withValues(alpha: dim),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case ElementAnimationType.ripple:
        // 方案 A：片元着色器逐像素折射。
        //
        // 前五版都是 Canvas 叠加绘制（画环 / 渐变 / 加色混合），
        // 底层像素一个都没动，用户始终觉得「像两个图层」。
        // 那是叠加绘制的天花板，不是参数问题——
        // 只有重采样纹理才能让组件内容本身被拉伸挤压。
        //
        // 着色器不可用时 RippleShaderView 会原样显示 child，
        // 不会崩溃也不会让组件消失。
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: RippleShaderView(
            progress: t.clamp(0.0, 1.0),
            intensity: intensity,
            tint: accent,
            child: child,
          ),
        );

      case ElementAnimationType.flash:
        // 三角波：中点最亮，两端归零，避免结束时突然掉色。
        final double wave = waveOf(0.5);
        // 蒙版上限从 0.55 提到 0.85：
        // 默认 intensity=0.6 时原来只有 0.33，几乎看不出「闪了一下」。
        final double flashAlpha =
            (wave * 0.85 * intensity).clamp(0.0, 1.0);
        return Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: flashAlpha),
                      borderRadius: BorderRadius.circular(borderRadius),
                      // 外发光让高亮「溢出」组件轮廓，
                      // 单纯蒙一层色在深色背景上依然不显眼。
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: flashAlpha * 0.7),
                          blurRadius: 18 * wave * intensity,
                          spreadRadius: 3 * wave * intensity,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      case ElementAnimationType.numberPop:
        // 先放大后回落。
        //
        // 幅度系数从 0.3 提到 0.55：默认 intensity=0.6 时
        // 原来峰值只有 +18%，在一行数字上几乎察觉不到。
        // 现在 +33%，是「跳了一下」该有的量级。
        //
        // 这里**不夹取** rawWave：Transform.scale 允许过冲，
        // 回弹曲线的弹性观感正来自于此。只兜住负缩放。
        final double rawWave =
            t < 0.4 ? t / 0.4 : (1.0 - t) / 0.6;
        // 顺带一点上浮：数值跳动配合轻微抬起更像「弹出来」，
        // 纯缩放会显得只是在原地胀大。
        final double lift = -6.0 * intensity * rawWave;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(
            scale: (1.0 + 0.55 * intensity * rawWave).clamp(0.05, 4.0),
            child: child,
          ),
        );

      case ElementAnimationType.glowPulse:
        // 呼吸两次而不是一次。
        //
        // 「脉冲」的语感本就是一下一下的；单次三角波起落一回就结束，
        // 观感更接近「闪了下」而不是「在发光」。
        // 频率 2 让它在同样时长内跳动两轮，明显得多。
        final double breathe = (math.sin(t * math.pi * 2 * 2 - math.pi / 2) +
                1.0) /
            2.0;
        final double wave = breathe * math.pow(1.0 - t, 0.8).toDouble();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              // 三层叠加：紧贴组件的亮边 + 中层光晕 + 大范围弥散。
              //
              // 单层阴影在深色背景上几乎不可见（用户反馈）——
              // 深色底本来就吃光，只有把亮边收紧、同时把弥散铺开，
              // 才能同时读出「轮廓在发亮」与「光在扩散」。
              BoxShadow(
                color: accent.withValues(
                    alpha: (wave * 0.95).clamp(0.0, 1.0)),
                blurRadius: 6 * intensity * wave,
                spreadRadius: 1.5 * intensity * wave,
              ),
              BoxShadow(
                color: accent.withValues(
                    alpha: (wave * 0.6).clamp(0.0, 1.0)),
                // blurRadius / spreadRadius 必须非负，见上方夹取说明。
                blurRadius: 26 * intensity * wave,
                spreadRadius: 7 * intensity * wave,
              ),
              BoxShadow(
                color: accent.withValues(
                    alpha: (wave * 0.28).clamp(0.0, 1.0)),
                blurRadius: 54 * intensity * wave,
                spreadRadius: 14 * intensity * wave,
              ),
            ],
          ),
          child: child,
        );

      case ElementAnimationType.particleBurst:
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ParticleBurstPainter(
                    progress: t.clamp(0.0, 1.0),
                    intensity: intensity,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  static Widget _buildProgressBar(UIModule module, Size size) {
    final double min = (module.properties['min'] ?? 0).toDouble();
    final double max = (module.properties['max'] ?? 100).toDouble();
    double current = (module.properties['current'] ?? min).toDouble();

    final controls = LinkerService.resolveTargetControlState(module);
    final linkedVal = controls.frozen ? null : LinkerService.resolveTargetValue(module);
    if (linkedVal != null && linkedVal is num) {
      current = linkedVal.toDouble();
    }
    final double actualMin = min <= max ? min : max;
    final double actualMax = min <= max ? max : min;
    current = current.clamp(actualMin, actualMax).toDouble();

    final double progress = actualMax > actualMin ? (current - actualMin) / (actualMax - actualMin) : 0.0;

    final fillColor = module.color;
    final int? trackColorVal = module.properties['trackColor'] as int?;
    final Color trackColor = trackColorVal != null ? Color(trackColorVal) : Colors.grey.shade200;
    final String shapeStr = module.properties['progressShape']?.toString() ?? 'rounded';

    if (shapeStr == 'ring') {
      final double shortestSide = math.min(size.width, size.height);
      final double defaultSw = shortestSide * 0.12;
      final dynamic customSwProp = module.properties['strokeWidth'];
      double sw = (customSwProp != null && customSwProp is num) ? customSwProp.toDouble() : defaultSw;
      sw = sw.clamp(2.0, shortestSide * 0.42).toDouble();
      return CustomPaint(
        painter: _RingProgressBarPainter(progress: progress, fillColor: fillColor, trackColor: trackColor, strokeWidth: sw),
        size: size,
      );
    }

    if (shapeStr == 'heart') {
      return ClipPath(
        clipper: _PathClipper(getHeartPath),
        child: Container(
          color: trackColor,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: progress.clamp(0.0, 1.0),
              widthFactor: 1.0,
              child: Container(color: fillColor),
            ),
          ),
        ),
      );
    }

    final radius = shapeStr == 'rectangle' ? BorderRadius.zero : BorderRadius.circular(999);

    // 水波动画期间，让**填充边界本身**随波起伏。
    //
    // 用户反馈：进度条只有两种纯色，折射只在两色交界处可见，
    // 「显示效果太小了」。这是折射的固有局限——
    // 采样偏移作用在纯色区域上，偏到哪儿取到的还是同一个颜色。
    //
    // 解法不是加强折射，而是**制造新的可动边界**：
    // 把填充的右边缘画成波浪线，波纹经过时它跟着荡漾。
    // 配了水波动画的进度条，填充边界自己会荡漾。
    //
    // ⚠️ 不能靠外层动画的 progress 判断。
    //
    // 上一轮试过两种都失败：
    // 1. 读 props 里的 timestamp —— 值变化通路里它恒为 0
    //    （渲染函数不能写 props），`isActiveAt` 永远返回 false；
    // 2. 用静态通道从外层传进度 —— `_buildProgressBar` 在
    //    `_renderModule` 阶段执行，比外层的动画包裹**早得多**，
    //    push/pop 包不住它。
    //
    // 改为让进度条**自己**成为一个带 Ticker 的组件：
    // 检测到值变化就自行起波，不依赖任何外部时序。
    final barAnim = ElementAnimation.readFrom(module.properties);
    if (barAnim != null && barAnim.type == ElementAnimationType.ripple) {
      return ClipRRect(
        borderRadius: radius,
        child: _WavyProgressBar(
          progress: progress.clamp(0.0, 1.0),
          fillColor: fillColor,
          trackColor: trackColor,
          intensity: barAnim.intensity,
          durationMs: barAnim.durationMs,
          size: size,
        ),
      );
    }

    // 粒子迸发：从**填充边缘**朝数值变化的方向喷射（用户提议）。
    //
    // 通用的中心爆发只表达「这个组件有事发生」，
    // 而进度条有明确的「数值位置」——从那里喷粒子，
    // 语义直接变成「数值在这里推进了」，与组件本身的含义吻合。
    //
    // 必须做成进度条**自己的一部分**而不是外层叠加：
    // `_paintAnimationFrame` 只拿得到动画进度（时间轴 0→1），
    // 拿不到数值进度；而 `_buildProgressBar` 在 `_renderModule` 阶段
    // 执行、早于所有动画包裹层，反向传值行不通
    // （波浪边界已经踩过这个坑）。
    // 与上面的 ripple 读同一份配置（上面已 return，这里必然是别的类型）。
    if (barAnim != null &&
        barAnim.type == ElementAnimationType.particleBurst) {
      return _EdgeBurstProgressBar(
        progress: progress.clamp(0.0, 1.0),
        fillColor: fillColor,
        trackColor: trackColor,
        radius: radius,
        intensity: barAnim.intensity,
        durationMs: barAnim.durationMs,
        particleColor: barAnim.colorValue != null
            ? Color(barAnim.colorValue!)
            : fillColor,
        size: size,
      );
    }

    return Container(
      decoration: BoxDecoration(color: trackColor, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            heightFactor: 1.0,
            child: Container(color: fillColor),
          ),
        ),
      ),
    );
  }

  static double _snapSliderValue(
    double value,
    double min,
    double max,
    double step,
  ) {
    final actualMin = min <= max ? min : max;
    final actualMax = min <= max ? max : min;
    final safeStep = step > 0 ? step : 1.0;
    final snapped = actualMin +
        ((value - actualMin) / safeStep).round() * safeStep;
    return snapped.clamp(actualMin, actualMax).toDouble();
  }

  static Widget _buildSlider(
    BuildContext context,
    UIElement element,
    UIModule module,
    Size size,
  ) {
    final bool isStudio = UISceneModeScope.of(context);

    Widget buildSliderWidget(double currentVal) {
      final double min = (module.properties['min'] ?? 0).toDouble();
      final double max = (module.properties['max'] ?? 100).toDouble();
      final double actualMin = min <= max ? min : max;
      final double actualMax = min <= max ? max : min;
      final double step =
          ((module.properties['step'] as num?)?.toDouble() ?? 1.0).abs();
      final double clampedCur =
          _snapSliderValue(currentVal, actualMin, actualMax, step);

      final double ratio = actualMax > actualMin
          ? (clampedCur - actualMin) / (actualMax - actualMin)
          : 0.0;

      final fillColor = module.color;
      final int? trackColorVal = module.properties['trackColor'] as int?;
      final Color trackColor =
          trackColorVal != null ? Color(trackColorVal) : Colors.grey.shade300;
      final double knobSize = (module.properties['knobSize'] ?? 18.0)
          .toDouble()
          .clamp(12.0, 36.0)
          .toDouble();
      final String knobShape =
          module.properties['knobShape']?.toString() ?? 'circle';

      final double h = size.height > 0 ? size.height : 32.0;
      final double trackWidth = math.max(10.0, size.width - 20.0);
      final double maxKnobLeft = math.max(0.0, trackWidth - knobSize);
      final double knobLeft = 10.0 + ratio.clamp(0.0, 1.0) * maxKnobLeft;

      final double activeTrackWidth =
          math.max(0.0, knobLeft - 10.0 + knobSize / 2);

      return SizedBox(
        height: h,
        child: Stack(
          children: [
            Positioned(
              left: 10,
              right: 10,
              top: (h - 6) / 2,
              height: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: (h - 6) / 2,
              width: activeTrackWidth,
              height: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              left: knobLeft,
              top: (h - knobSize) / 2,
              width: knobSize,
              height: knobSize,
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: knobShape == 'rectangle'
                      ? BoxShape.rectangle
                      : BoxShape.circle,
                  borderRadius: knobShape == 'rectangle'
                      ? BorderRadius.circular(4)
                      : null,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isStudio) {
      final double min = (module.properties['min'] ?? 0).toDouble();
      double current = (module.properties['current'] ?? min).toDouble();
      // A13-3：分配组件的值由玩家决定，编辑态不接收上游联动值。
      // 归零发生在配置连线时（见 `_zeroAllocationTargets`），
      // 此处 current 已经是 0，直接画即可。
      if (!LinkerService.isAllocationTarget(module)) {
        final linkedVal = LinkerService.resolveTargetValue(module);
        if (linkedVal != null && linkedVal is num) {
          current = linkedVal.toDouble();
        }
      }
      return buildSliderWidget(current);
    }

    return StatefulBuilder(
      builder: (ctx, setSliderState) {
        final snapshot = UILinkerSnapshotScope.maybeOf(ctx);
        if (snapshot != null) {
          LinkerService.installSnapshot(snapshot);
        }
        final double min = (module.properties['min'] ?? 0).toDouble();
        final double max = (module.properties['max'] ?? 100).toDouble();
        double current = (module.properties['current'] ?? min).toDouble();

        // A13-3：作为配额分配组件时，值完全由玩家拖动决定，
        // 引擎只负责「不超过剩余额度」。归零已在配置连线时完成，
        // 这里绝不能走 resolveTargetValue 去接收上游值——
        // 上游是配额池，把总量灌进分配项就全乱了。
        final isAllocation = LinkerService.isAllocationTarget(module);
        if (!isAllocation) {
          final linkedVal = LinkerService.resolveTargetValue(module);
          if (linkedVal != null && linkedVal is num) {
            current = linkedVal.toDouble();
          }
        }
        module.properties['committedValue'] ??= current;

        void updatePosition(Offset localPos) {
          final double actualMin = min <= max ? min : max;
          final double actualMax = min <= max ? max : min;
          final double knobSize = (module.properties['knobSize'] ?? 18.0)
              .toDouble()
              .clamp(12.0, 36.0)
              .toDouble();
          final double trackWidth = math.max(10.0, size.width - 20.0);
          final double maxKnobLeft = math.max(0.0, trackWidth - knobSize);

          if (maxKnobLeft <= 0) return;
          final dx = localPos.dx - 10.0;
          final newRatio = (dx / maxKnobLeft).clamp(0.0, 1.0);
          final rawCurrent = actualMin + newRatio * (actualMax - actualMin);
          final step =
              ((module.properties['step'] as num?)?.toDouble() ?? 1.0).abs();
          var newCurrent =
              _snapSliderValue(rawCurrent, actualMin, actualMax, step);

          // A13-3：配额约束。上限 = 剩余可分配额 + 自己已占用的部分，
          // 加回自己是必须的，否则已分配的点数只能往下调、调不回去。
          final ceiling = LinkerService.allocationCeilingFor(module);
          if (ceiling != null && newCurrent > ceiling) {
            newCurrent = _snapSliderValue(
              ceiling.clamp(actualMin, actualMax).toDouble(),
              actualMin,
              actualMax,
              step,
            );
            // snap 可能又超出上限（步长不整除时），再收一次。
            if (newCurrent > ceiling) newCurrent = math.max(actualMin, newCurrent - step);
          }

          module.properties['current'] = newCurrent;
          final snapshot = UILinkerSnapshotScope.peekOf(ctx);
          if (snapshot != null) {
            LinkerService.installSnapshot(snapshot);
          }
          LinkerEventBus().emit(element.id, 'slider_change', newCurrent);
          setSliderState(() {});
        }

        void commitValue() {
          final value = (module.properties['current'] as num?)?.toDouble() ?? current;
          module.properties['committedValue'] = value;
          final snapshot = UILinkerSnapshotScope.peekOf(ctx);
          if (snapshot != null) {
            LinkerService.installSnapshot(snapshot);
          }
          LinkerEventBus().emit(element.id, 'slider_commit', value);
        }

        // 用 RawGestureDetector 显式声明水平拖动识别器。
        //
        // 原先用 onPanStart（PanGestureRecognizer）时，滑块拖不动：
        // 聊天页根部有 onHorizontalDrag* 用于滑出侧栏，
        // 在手势竞技场里「专用」识别器（Horizontal）优先于
        // 「通用」识别器（Pan），与嵌套深浅无关，于是父级总是胜出。
        // 这里改用同为专用的 HorizontalDrag，并在 onStart 立即 resolve，
        // 让滑块在竞争中拿下手势。
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (instance) {
                // 用块体而非箭头函数：updatePosition / commitValue 返回 void，
                // 箭头体会被当成「使用 void 值」而编译失败。
                instance.onTapDown = (details) {
                  updatePosition(details.localPosition);
                };
                instance.onTapUp = (_) {
                  commitValue();
                };
              },
            ),
            _EagerHorizontalDragRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    _EagerHorizontalDragRecognizer>(
              () => _EagerHorizontalDragRecognizer(),
              (instance) {
                instance.onStart = (details) {
                  updatePosition(details.localPosition);
                };
                instance.onUpdate = (details) {
                  updatePosition(details.localPosition);
                };
                instance.onEnd = (_) {
                  commitValue();
                };
              },
            ),
          },
          child: buildSliderWidget(current),
        );
      },
    );
  }

  /// 点击热区渲染。
  ///
  /// button 的本意是「一块可被按动的区域」，而**不是**一个有文案的控件：
  /// 运行期它完全不显形，视觉反馈一律由它联动的 surface 去表现。
  /// 编辑期才画出灰色区域，让作者知道热区在哪、多大。
  ///
  /// 历史上这里支持过 `text` / `showTextOnRuntime`（在运行期显示文案），
  /// 那是 Studio 缺编辑入口时留下的遗留设定，已废弃：
  /// 一个会自己显字的按钮既与「热区」定位冲突，
  /// 也让作者误以为按钮有外观可调。
  static Widget _buildButton(BuildContext context, UIElement element, UIModule module) {
    final bool isStudio = UISceneModeScope.of(context);

    // 运行期：纯热区，不占任何像素的视觉表达。
    if (!isStudio) {
      return _ButtonGestureWidget(
        elementId: element.id,
        module: module,
        child: const SizedBox.expand(),
      );
    }

    // 编辑期：统一的灰色区域 + 手势图标，表明这是热区而非可见控件。
    final hasTap = LinkerService.hasConnectedPort(element.id, 'tap');
    final hasDoubleTap = LinkerService.hasConnectedPort(element.id, 'double_tap');
    final hasLongPress = LinkerService.hasConnectedPort(element.id, 'long_press');

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF9E9E9E).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF9E9E9E).withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(
              Icons.touch_app_outlined,
              size: 14,
              color: Color(0xFF757580),
            ),
          ),
          if (hasTap || hasDoubleTap || hasLongPress)
            Positioned(
              left: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTap)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (hasDoubleTap)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF29B6F6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (hasLongPress)
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF5252),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 显示表达式求值（{{key}} 模板替换）
  static String evaluateDisplayExpression(UIModule module, [Map<String, dynamic>? extraContext]) {
    final expr = module.displayExpression?.trim() ?? '';
    if (expr.isEmpty) {
      return module.properties['text']?.toString() ?? module.name;
    }

    String result = expr;
    final context = <String, dynamic>{
      ...module.properties,
      if (extraContext != null) ...extraContext,
    };

    // 标准 {{key}} 替换
    context.forEach((key, value) {
      if (value == null) return;
      final valStr = value is num ? value.toStringAsFixed(0) : value.toString();
      final pattern = RegExp(r'\{\{\s*' + RegExp.escape(key) + r'\s*\}\}');
      result = result.replaceAllMapped(pattern, (_) => valStr);
    });

    // 常见进度别名支持：{{current}}、{{max}}、{{progress.current}} 等
    final cur = context['current'] ?? context['progress']?['current'];
    final mx = context['max'] ?? context['progress']?['max'];
    if (cur != null) {
      final curStr = cur is num ? cur.toStringAsFixed(0) : cur.toString();
      result = result.replaceAll(RegExp(r'\{\{\s*current\s*\}\}'), curStr);
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.current\s*\}\}'), curStr);
    }
    if (mx != null) {
      final mxStr = mx is num ? mx.toStringAsFixed(0) : mx.toString();
      result = result.replaceAll(RegExp(r'\{\{\s*max\s*\}\}'), mxStr);
      result = result.replaceAll(RegExp(r'\{\{\s*progress\.max\s*\}\}'), mxStr);
    }

    // 兜底：如果表达式未被替换且有原始 text，则回退
    if (result == expr) {
      final fallback = module.properties['text']?.toString();
      if (fallback != null && fallback.isNotEmpty) {
        result = fallback;
      }
    }

    return result.isEmpty ? module.name : result;
  }

  static Widget _buildTextBlock(UIModule module) {
    String displayText = module.properties['text']?.toString() ?? module.name;
    final linkedValue = _resolveLinkerValueForText(module);

    // A13-3：作为配额池时显示剩余可分配数。
    // 优先级高于普通联动值——池子的语义就是「还能分多少」。
    final poolDisplay = LinkerService.resolvePoolDisplay(module);

    if (poolDisplay != null) {
      displayText = poolDisplay.render();
    } else if (module.displayExpression != null && module.displayExpression!.trim().isNotEmpty) {
      displayText = evaluateDisplayExpression(
        module,
        LinkerService.getSourceContextForTarget(module),
      );
    } else if (linkedValue != null) {
      displayText = linkedValue;
    }

    final double fs = (module.properties['fontSize'] ?? 14.0).toDouble().clamp(10.0, 72.0).toDouble();
    final String overflowMode = module.properties['overflow']?.toString() ?? 'ellipsis';
    final String alignStr = module.properties['textAlign']?.toString() ?? 'center';

    TextAlign ta = TextAlign.center;
    Alignment boxAlign = Alignment.center;
    if (alignStr == 'left') {
      ta = TextAlign.left;
      boxAlign = Alignment.centerLeft;
    } else if (alignStr == 'right') {
      ta = TextAlign.right;
      boxAlign = Alignment.centerRight;
    }

    final isScroll = overflowMode == 'scroll';

    final textWidget = Text(
      displayText,
      style: TextStyle(
        color: module.color,
        fontSize: fs,
        // 长文说明需要正常字重与行距，粗体读起来很累。
        fontWeight: isScroll ? FontWeight.w400 : FontWeight.w600,
        height: isScroll ? 1.5 : null,
      ),
      textAlign: ta,
      overflow: overflowMode == 'ellipsis' ? TextOverflow.ellipsis : null,
    );

    if (isScroll) {
      // 滚动长文：内容从顶部开始、可选择复制、带滚动条。
      // 与消息流不同——这里是一整块静态内容，不该自动滚到底。
      //
      // A11-2：滚动模式富文本默认**开启**——它的典型用途是 readme 与
      // 道具说明，这类内容几乎必然带标题和列表。
      // 非滚动 text 的默认相反，见下方分支。
      return _ScrollableTextBlock(
        text: displayText,
        style: TextStyle(
          color: module.color,
          fontSize: fs,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        textAlign: ta,
        padding: (module.properties['contentPadding'] as num?)?.toDouble() ??
            10.0,
        richText: module.properties['richText'] != false,
      );
    }

    // 非滚动 text：仅在作者显式开启时走富文本。
    // 它常被 linker 指向来显示数值 / 短标签，默认解析会带来
    // 「HP<50」被当成 HTML 标签这类误判。
    if (module.properties['richText'] == true) {
      return Container(
        alignment: boxAlign,
        child: Builder(
          builder: (context) => AssemblyRichText(
            text: displayText,
            baseStyle: TextStyle(
              color: module.color,
              fontSize: fs,
              fontWeight: FontWeight.w600,
            ),
            textAlign: ta,
            highlightRules: TextHighlightScope.maybeOf(context),
          ),
        ),
      );
    }

    return Container(
      alignment: boxAlign,
      child: textWidget,
    );
  }

  /// Linker MVP：尝试解析当前 text 是否被 linker 指向，并返回联动后的值
  static String? _resolveLinkerValueForText(UIModule textModule) {
    return LinkerService.resolveLinkedTextValue(textModule);
  }

  static Widget _buildInputBlock(BuildContext context, UIElement element, UIModule module) {
    final bool isStudio = UISceneModeScope.of(context);
    final controls = LinkerService.resolveTargetControlState(module);
    String placeholder = module.properties['placeholder']?.toString() ?? '请输入...';
    if (placeholder == '请输入...' || placeholder.trim().isEmpty) {
      final linkedVal = LinkerService.resolveTargetValue(module);
      if (linkedVal != null && linkedVal.toString().trim().isNotEmpty) {
        placeholder = '请输入${linkedVal.toString().trim()}...';
      }
    }
    final visualMode = module.properties['visualMode']?.toString() ?? 'filled';
    final placeholderColor = Color((module.properties['placeholderColor'] as num?)?.toInt() ?? 0xFF888896);

    // 编辑态占位预览也要跟随文本落点设置。
    //
    // 这里是一条**独立于运行时 TextField 的分支**（编辑器里不该出现
    // 可聚焦的真输入框），所以新属性必须在两处各读一遍。
    // 只改运行时那边的话，作者在画布上看到的永远是居中，
    // 改了设置却没有任何反馈（用户反馈）。
    final vAlign = module.properties['textVerticalAlign']?.toString() ?? 'center';
    final hAlign = module.properties['textHorizontalAlign']?.toString() ?? 'left';
    final multiline = module.properties['multiline'] == true;
    // 与运行时同一条规则：多行强制贴顶。
    final effectiveVAlign = multiline ? 'top' : vAlign;

    final displayBox = Container(
      alignment: switch ((effectiveVAlign, hAlign)) {
        ('top', 'center') => Alignment.topCenter,
        ('top', 'right') => Alignment.topRight,
        ('top', _) => Alignment.topLeft,
        ('bottom', 'center') => Alignment.bottomCenter,
        ('bottom', 'right') => Alignment.bottomRight,
        ('bottom', _) => Alignment.bottomLeft,
        (_, 'center') => Alignment.center,
        (_, 'right') => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: visualMode == 'filled' ? module.color.withValues(alpha: module.opacity * 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: visualMode == 'transparent' ? null : Border.all(color: module.color.withValues(alpha: visualMode == 'outline' ? 0.8 : 0.38), width: visualMode == 'outline' ? 1.4 : 1),
      ),
      child: Text(
        placeholder,
        style: TextStyle(color: placeholderColor, fontSize: 13),
        textAlign: switch (hAlign) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        },
        // 多行时让占位文字也能折行，直观反映「这是个多行框」。
        maxLines: multiline ? null : 1,
        overflow: multiline ? TextOverflow.clip : TextOverflow.ellipsis,
      ),
    );

    if (isStudio) {
      return displayBox;
    }

    return _InputBlockWidget(
      key: ValueKey('input_${element.id}'),
      element: element,
      module: module,
      placeholder: placeholder,
      controls: controls,
    );
  }

  static Widget _buildImageBlock(BuildContext context, UIModule module) {
    final props = module.properties;
    String url = props['url']?.toString() ?? '';
    String assetPath = props['assetPath']?.toString() ?? '';

    // A11-2：头像同步。来源选了角色 / 用户头像时，路径由运行时提供，
    // 覆盖作者填的静态值——作者在编辑器里填不出运行时才知道的本地路径。
    final avatarSource = props['imageSource']?.toString();
    if (AvatarScope.isDynamic(avatarSource)) {
      final resolved = AvatarScope.resolve(context, avatarSource);
      if (resolved != null && resolved.trim().isNotEmpty) {
        assetPath = resolved.trim();
        url = '';
      } else {
        // 头像没设置时不回落到作者填的静态图：作者选了「显示角色头像」，
        // 却显示出一张无关的占位图会更让人困惑。
        assetPath = '';
        url = '';
      }
    }
    final String fitStr = props['fit']?.toString() ?? 'cover';
    final String shapeStr = props['shape']?.toString() ?? 'rectangle';
    final double radiusVal = (props['borderRadius'] ?? 8.0).toDouble();

    final linkedVal = LinkerService.resolveTargetValue(module);
    if (linkedVal != null && linkedVal.toString().trim().isNotEmpty) {
      final str = linkedVal.toString().trim();
      if (str.startsWith('http') || str.startsWith('data:image')) {
        url = str;
      } else {
        assetPath = str;
      }
    }

    BoxFit fit = BoxFit.cover;
    if (fitStr == 'contain') { fit = BoxFit.contain; }
    else if (fitStr == 'fill') { fit = BoxFit.fill; }

    Widget imgContent;
    // data URI 优先判断：角色卡导出时会把本地图片内联成
    // `data:image/png;base64,...`，导入方机器上没有原路径，
    // 只能靠这条分支渲染。放在最前面是因为它既可能出现在 url
    // 也可能出现在 assetPath（取决于作者当初填在哪一栏）。
    final String inlineData =
        url.startsWith('data:image') ? url : (assetPath.startsWith('data:image') ? assetPath : '');
    if (inlineData.isNotEmpty) {
      final bytes = _decodeDataUri(inlineData);
      imgContent = bytes == null
          ? _buildImagePlaceholder(module, '内联图片数据损坏')
          : Image.memory(
              bytes,
              fit: fit,
              errorBuilder: (_, _, _) =>
                  _buildImagePlaceholder(module, '内联图片解码失败'),
            );
    } else if (url.isNotEmpty) {
      imgContent = Image.network(
        url,
        fit: fit,
        errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '加载网络图片失败'),
      );
    } else if (assetPath.isNotEmpty) {
      if (assetPath.startsWith('/') || assetPath.contains('\\')) {
        imgContent = Image.file(
          File(assetPath),
          fit: fit,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '读取本地文件失败'),
        );
      } else {
        imgContent = Image.asset(
          assetPath,
          fit: fit,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(module, '未找到内部资产图片'),
        );
      }
    } else {
      imgContent = _buildImagePlaceholder(module, '静态位图占位热区\n(请在编辑器设定图片)');
    }

    if (shapeStr == 'none') {
      return imgContent;
    } else if (shapeStr == 'circle') {
      return ClipOval(child: imgContent);
    } else if (shapeStr == 'capsule') {
      return ClipRRect(borderRadius: BorderRadius.circular(999), child: imgContent);
    } else if (shapeStr == 'heart') {
      return ClipPath(clipper: _PathClipper(getHeartPath), child: imgContent);
    } else if (shapeStr == 'star5') {
      return ClipPath(clipper: _PathClipper((r) => getStarPath(r, 5, 0.45)), child: imgContent);
    } else if (radiusVal > 0) {
      return ClipRRect(borderRadius: BorderRadius.circular(radiusVal), child: imgContent);
    }
    return imgContent;
  }

  /// 解析 `data:image/xxx;base64,....`。格式不对或解码失败返回 null。
  static Uint8List? _decodeDataUri(String uri) {
    final comma = uri.indexOf(',');
    if (comma == -1) return null;
    try {
      return base64Decode(uri.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static Widget _buildImagePlaceholder(UIModule module, String tip) {
    return Container(
      color: module.color.withValues(alpha: module.opacity * 0.15),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, color: module.color, size: 22),
          const SizedBox(height: 2),
          Text(
            tip,
            style: TextStyle(color: module.color, fontSize: 9, height: 1.2),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  static Widget _buildLineBlock(UIModule module, Size size) {
    final props = module.properties;
    final double th = (props['thickness'] ?? 2.0).toDouble().clamp(1.0, 32.0).toDouble();
    final String ls = props['lineStyle']?.toString() ?? 'solid';
    final String ax = props['axis']?.toString() ?? 'horizontal';
    final double dl = (props['dashLength'] ?? 6.0).toDouble();
    final double gl = (props['gapLength'] ?? 3.0).toDouble();

    return CustomPaint(
      painter: _MultiLinePainter(color: module.color, thickness: th, lineStyle: ls, axis: ax, dashLength: dl, gapLength: gl),
      size: size,
    );
  }

  static Widget _buildSwitchBlock(BuildContext context, UIElement element, UIModule module) {
    final bool isStudio = UISceneModeScope.of(context);
    final int? inactiveColorVal = module.properties['inactiveTrackColor'] as int?;
    final Color inactiveColor = inactiveColorVal != null ? Color(inactiveColorVal) : Colors.grey.shade300;
    final int? thumbColorVal = module.properties['thumbColor'] as int?;
    final Color thumbColor = thumbColorVal != null ? Color(thumbColorVal) : Colors.white;

    return StatefulBuilder(
      builder: (ctx, setState) {
        final snapshot = UILinkerSnapshotScope.maybeOf(ctx);
        if (snapshot != null) {
          LinkerService.installSnapshot(snapshot);
        }
        final linkedValue = LinkerService.resolveTargetValue(module);
        final bool isExternallyControlled = linkedValue is bool;
        final bool currentVal = isExternallyControlled
            ? linkedValue
            : module.properties['value'] != false;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isStudio || isExternallyControlled
              ? null
              : () {
                  final bool nextVal = !currentVal;
                  module.properties['value'] = nextVal;
                  final snapshot = UILinkerSnapshotScope.peekOf(ctx);
                  if (snapshot != null) {
                    LinkerService.installSnapshot(snapshot);
                  }
                  LinkerEventBus().emit(element.id, 'switch_change', nextVal);
                  setState(() {});
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: currentVal ? module.color : inactiveColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: currentVal ? module.color : Colors.grey.shade400, width: 1),
            ),
            alignment: currentVal ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: thumbColor, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))]),
            ),
          ),
        );
      },
    );
  }

  static String _linkerDisplayPort(String port) {
    const labels = {'input':'输入','output':'输出','current':'当前值','currentVal':'当前值','currentValue':'当前值','value':'开关值','tap':'单击','double_tap':'双击','long_press':'长按','data_in':'数值输入','data_out':'计算结果','gate_in':'计算触发','timer_tick':'定时触发','tickCount':'触发次数','committedValue':'已提交值'};
    return labels[port] ?? port;
  }

  static String _linkerDisplayScheme(String scheme) {
    const labels = <String, String>{
      'click_to_surface_press': '按压反馈',
      'click_to_switch_toggle': '切换开关', 'click_to_switch_set_true': '开启开关',
      'click_to_switch_set_false': '关闭开关', 'click_to_input_clear': '清空输入',
      'click_to_slider_reset': '重置滑块', 'click_to_timer_toggle': '切换定时器',
      'click_to_timer_reset': '重置定时器', 'click_to_math_trigger': '触发计算',
      'timer_tick_to_math_trigger': '定时触发计算',
      'timer_tick_to_progress_increment': '定时增加进度', 'timer_tick_to_progress_decrement': '定时减少进度',
      'value_to_math_param': '注入计算参数', 'progress_to_math_param': '进度注入参数',
      'text_extract_to_math_param': '文本取数计算', 'slider_commit_to_math_param': '滑块提交参数',
      'input_live_to_text': '实时同步文本', 'input_commit_to_text': '提交同步文本',
      'input_submit_to_text_clear': '提交后清空', 'input_value_to_select_match': '匹配下拉选项',
      'input_value_to_select_filter': '过滤下拉选项',
      'indicator_color_to_enabled': '颜色控制可交互', 'indicator_color_to_visible': '颜色控制显示',
      'indicator_color_to_locked': '颜色控制运行锁定', 'indicator_color_to_frozen': '颜色控制数值冻结',
      'event_to_indicator': '事件高亮指示灯',
    };
    if (labels.containsKey(scheme)) return labels[scheme]!;
    if (scheme == '未配置' || scheme == '未连接') return scheme;
    final definition = LinkerMatrixEngine.getSchemeDefinition(scheme);
    return definition?.label.split(' (').first ?? '已配置通路';
  }

  static Widget _buildPageRouterNode(UIModule module) {
    final routeData =
        (module.properties['route'] as Map?)?.cast<String, dynamic>() ?? {};
    final action = routeData['action']?.toString() == 'open_overlay'
        ? '打开叠加页'
        : '切换平级页';
    final targetId = routeData['targetPageId']?.toString() ?? '';
    final status = targetId.trim().isEmpty ? '未配置' : '已配置';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00897B).withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 15, color: Color(0xFF00897B)),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  '页面路由器',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF00695C),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$action · $status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF33695F),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  /// 联动器节点渲染（MVP）
  /// 样式：圆角矩形 + 左右端口原点（垂直居中）+ 端口旁标签 + 中间传输方案
  /// 端口已放大并移至中点，方便后续拖拽接线
  static Widget _buildLinkerNode(UIModule module, Size size) {
    final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>() ?? {};

    final String sourceId = linkerData['sourceModuleId']?.toString() ?? '';
    final String targetId = linkerData['targetModuleId']?.toString() ?? '';
    final bool hasSource = sourceId.trim().isNotEmpty && sourceId != 'null' && sourceId != '—';
    final bool hasTarget = targetId.trim().isNotEmpty && targetId != 'null' && targetId != '—';

    final sourcePort = hasSource ? _linkerDisplayPort(linkerData['sourcePort']?.toString() ?? '—') : '';
    final targetPort = hasTarget ? _linkerDisplayPort(linkerData['targetPort']?.toString() ?? '—') : '';
    final scheme = (hasSource && hasTarget) ? (linkerData['scheme']?.toString() ?? '未配置') : '未连接';
    final displayScheme = _linkerDisplayScheme(scheme);
    final bool isEnabled = hasSource &&
        hasTarget &&
        linkerData['enabled'] == true &&
        scheme != '未配置';
    final statusText = !hasSource || !hasTarget
        ? '未连接'
        : isEnabled
            ? '已启用'
            : '待选方案';
    const activeColor = Color(0xFF00ACC1);
    final statusColor = isEnabled ? activeColor : const Color(0xFF757575);

    final portColor = statusColor.withValues(alpha: 0.95);
    final borderColor = statusColor.withValues(alpha: 0.45);
    const double portSize = 15.0; // 放大端口，方便接线交互

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 左上角端口标签
          if (sourcePort.isNotEmpty && sourcePort != '—')
            Positioned(
              left: 8,
              top: 2,
              child: Text(
                sourcePort,
                style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
              ),
            ),

          // 左侧端口（垂直居中）
          Positioned(
            left: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 右上角端口标签
          if (targetPort.isNotEmpty && targetPort != '—')
            Positioned(
              right: 8,
              top: 2,
              child: Text(
                targetPort,
                style: const TextStyle(fontSize: 9, color: Color(0xFF444455), fontWeight: FontWeight.w700),
              ),
            ),

          // 右侧端口（垂直居中）
          Positioned(
            right: 6,
            top: (size.height - portSize) / 2,
            child: Container(
              width: portSize,
              height: portSize,
              decoration: BoxDecoration(
                color: portColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),

          // 中间传输方案
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
              child: Text(
                displayScheme,
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
              ),
            ),
          ),

          // 底部提示
          Positioned(
            bottom: 3,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 8,
                  color: statusColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 算术算账节点渲染（第一步 MVP）
  /// 浅紫色逻辑背景框，中间粗体运算字符，左端点青色 Data IN，右端点绿色 Data OUT，顶部中心金色 Gate IN
  static Widget _buildMathNodeBlock(UIModule module, Size size) {
    final props = module.properties;
    final String op = props['operation']?.toString() ?? '+';
    final params = LinkerService.resolveMathNodeParameters(module);
    final result = LinkerService.resolveMathNodeResult(module);
    final controls = LinkerService.resolveTargetControlState(module);
    final resultText = result is bool
        ? (result ? 'true' : 'false')
        : result is num
            ? (result == result.toInt()
                ? result.toInt().toString()
                : result.toStringAsFixed(2))
            : '—';
    String formatNumber(num value) => value == value.toInt()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);

    final activeParams = LinkerService.resolveMathNodeActiveParams(module);
    final operands = activeParams
        .map((param) => formatNumber(params[param] ?? 0))
        .toList();
    final formula = op == 'set'
        ? (operands.isEmpty ? '—' : operands.first)
        : operands.join(' $op ');
    final opText = controls.frozen
        ? '冻结 · $resultText'
        : '$formula = $resultText';

    const double portSize = 9.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF9575CD), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 中点公式：旧草稿节点较窄时自动缩小，始终完整显示。
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 1, 18, 1),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '计算：$opText',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF512DA8),
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
          // 三个端口保持同一圆点外观；说明改为悬停提示，避免侵占公式区域。
          Positioned(
            left: 4,
            top: (size.height - portSize) / 2,
            child: Tooltip(
              message: '数值输入：为参数 A / B / C 提供数值',
              child: Container(
                width: portSize,
                height: portSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: (size.height - portSize) / 2,
            child: Tooltip(
              message: '计算结果输出',
              child: Container(
                width: portSize,
                height: portSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF66BB6A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2.5,
            left: (size.width - portSize) / 2,
            child: Tooltip(
              message: '计算触发：仅接收 Button、Timer 等控制通路',
              child: Container(
                width: portSize,
                height: portSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下拉选择框渲染（第一步 MVP 进阶版）
  /// 白底微圆角矩形，左侧主区域选中，右侧箭头热区点选悬浮展开选项列表，无接线孔
  static Widget _buildSelectBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final props = module.properties;
    final options = SelectOption.parseList(props['options']);

    return StatefulBuilder(
      builder: (ctx, setState) {
        final snapshot = UILinkerSnapshotScope.maybeOf(ctx);
        if (snapshot != null) {
          LinkerService.installSnapshot(snapshot);
        }
        // current 保存稳定 value；展示时转换为用户可见 label。
        final linkedSelection = LinkerService.resolveTargetValue(module);
        final currentValue = linkedSelection?.toString() ??
            props['current']?.toString() ??
            props['defaultValue']?.toString() ??
            options.first.value;
        final matched = options.where((option) => option.value == currentValue).toList();
        final currentText = matched.isEmpty ? options.first.label : matched.first.label;
        final bool isStudio = UISceneModeScope.of(context);
        final previewSelection =
            matched.isEmpty ? options.first.value : currentValue;
        final filterQuery =
            LinkerService.resolveSelectFilterQuery(module)?.trim() ?? '';

        // 模拟预览使用原生下拉组件，菜单由 Overlay 管理，可在节点边界外正常点击。
        if (!isStudio) {
          return _PreviewSelectWidget(
            key: ValueKey('preview_select_${element.id}'),
            element: element,
            module: module,
            options: options,
            currentSelection: previewSelection,
            expandDirection: props['expandDirection'] == 'up' ? 'up' : 'down',
            inputControlled: LinkerService.isSelectInputControlled(module),
            filterQuery: filterQuery,
          );
        }

        final bool isSelected = UISceneModeScope.selectedIdOf(context) == element.id;
        bool isExpanded = props['is_expanded_preview'] == true;
        // 创作模式下只允许当前选中节点保持展开；模拟预览允许正常交互。
        if (isStudio && !isSelected && isExpanded) {
          isExpanded = false;
          props['is_expanded_preview'] = false;
        }

        final Widget content = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isExpanded ? const Color(0xFF7E57C2) : const Color(0xFFD0D0D8),
              width: isExpanded ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isExpanded ? 0.12 : 0.06),
                blurRadius: isExpanded ? 6 : 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    currentText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111116),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  props['is_expanded_preview'] = !isExpanded;
                  setState(() {});
                },
                child: Container(
                  width: 36,
                  height: double.infinity,
                  alignment: Alignment.center,
                  child: Text(
                    isExpanded ? '▲' : '▼',
                    style: TextStyle(
                      fontSize: 9,
                      color: isExpanded ? const Color(0xFF7E57C2) : const Color(0xFF888896),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (!isExpanded) return content;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              top: size.height + 4,
              left: 0,
              right: 0,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF7E57C2).withValues(alpha: 0.3)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: options.map((option) {
                        final bool active = option.value == currentValue;
                        return InkWell(
                          onTap: () {
                            props['current'] = option.value;
                            props['is_expanded_preview'] = false;
                            final snapshot = UILinkerSnapshotScope.peekOf(ctx);
                            if (snapshot != null) {
                              LinkerService.installSnapshot(snapshot);
                            }
                            LinkerEventBus().emit(
                              element.id,
                              'select_change',
                              option.value,
                            );
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            color: active ? const Color(0xFFEDE7F6) : Colors.transparent,
                            child: Text(
                              option.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: active ? const Color(0xFF512DA8) : const Color(0xFF111116),
                                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 多态状态指示点渲染：工作室中 36x36 磁吸感应框，中心呈现 14x14 霓虹 LED 灯
  static Widget _buildIndicatorBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final props = module.properties;
    final bool isStudio = UISceneModeScope.of(context);
    final indicatorState = LinkerService.resolveIndicatorActiveState(module);
    int activeColorInt = indicatorState.colorValue;
    bool activeGlow = indicatorState.glow;
    double glowRadius = indicatorState.glowRadius;

    final controls = LinkerService.resolveTargetControlState(module);
    if (!controls.enabled) {
      activeColorInt = 0xFF9E9E9E;
      activeGlow = false;
    } else {
      // 指示灯的闪烁走统一动画通道。
      //
      // 这里做的是**改色**而非叠加图层——指示灯本体就是一颗小圆点，
      // 盖一层半透明色只会让它变浑浊，直接换灯色才有「亮了一下」的观感。
      // 因此 flash 类型在这里被消费掉，不再走 _wrapWithAnimation。
      final anim = ElementAnimation.readFrom(props);
      if (anim != null &&
          anim.type == ElementAnimationType.flash &&
          anim.isActiveAt(DateTime.now().millisecondsSinceEpoch)) {
        activeColorInt = anim.colorValue ?? activeColorInt;
        activeGlow = true;
        glowRadius = 16.0;
      }
    }

    final Color activeColor = Color(activeColorInt);
    final double dotSize = (props['dotSize'] as num?)?.toDouble().clamp(8.0, 28.0) ?? 14.0;

    Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: activeColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
        boxShadow: activeGlow
            ? [
                BoxShadow(color: activeColor.withValues(alpha: 0.65), blurRadius: glowRadius, spreadRadius: 1.5),
                BoxShadow(color: activeColor.withValues(alpha: 0.35), blurRadius: glowRadius * 1.6, spreadRadius: 3.0),
              ]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1)),
              ],
      ),
    );

    if (isStudio) {
      return Container(
        width: size.width,
        height: size.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.06),
          shape: BoxShape.circle,
          border: Border.all(color: activeColor.withValues(alpha: 0.25), width: 1, style: BorderStyle.solid),
        ),
        child: dot,
      );
    }

    return Center(child: dot);
  }

  /// 消息流窗口（A11-1）。
  ///
  /// 数据来自 `MessageFlowScope`；没有作用域时（Assembly 编辑器预览）
  /// 显示占位示例，让作者能看到排版效果。
  static Widget _buildMessageFlowBlock(
    BuildContext context,
    UIModule module,
    Size size,
  ) {
    final props = module.properties;
    final scope = MessageFlowScope.maybeOf(context);
    final isStudio = UISceneModeScope.of(context);

    // 编辑态与预览都用示例消息，只有真实聊天里才显示真实历史。
    //
    // 判定依据是作用域上的 isLive 标记，不能看列表是否为空——
    // 运行时预览与「真实聊天但历史为空」都是空列表，
    // 前者该显示示例，后者该显示「暂无消息」。
    //
    // 真实聊天里**绝不**回落到示例，不能让玩家看见假对话。
    final useSample = isStudio || scope == null || !scope.isLive;
    final messages = useSample ? kMessageFlowSampleMessages : scope.messages;

    final showUser = props['showUser'] != false;
    final showAssistant = props['showAssistant'] != false;
    final limit = (props['historyLimit'] as num?)?.toInt() ?? 0;

    var visible = messages
        .where((m) => m.isUser ? showUser : showAssistant)
        .toList();
    // limit 为 0 表示不限制；否则只保留最近 N 条。
    if (limit > 0 && visible.length > limit) {
      visible = visible.sublist(visible.length - limit);
    }

    final fontSize =
        (props['fontSize'] as num?)?.toDouble().clamp(8.0, 24.0) ?? 12.5;
    final radius =
        (props['bubbleRadius'] as num?)?.toDouble().clamp(0.0, 32.0) ?? 12.0;
    final userColor =
        Color((props['userBubbleColor'] as num?)?.toInt() ?? 0xFFDCF8C6);
    final assistantColor =
        Color((props['assistantBubbleColor'] as num?)?.toInt() ?? 0xFFF1F1F4);

    return ClipRRect(
      borderRadius: BorderRadius.circular(module.borderRadius),
      child: Container(
        color: module.color.withValues(alpha: module.opacity),
        child: visible.isEmpty
            ? Center(
                child: Text(
                  '暂无消息',
                  style: TextStyle(
                    fontSize: fontSize,
                    color: const Color(0xFF9E9EA8),
                  ),
                ),
              )
            : _MessageFlowList(
                messages: visible,
                fontSize: fontSize,
                bubbleRadius: radius,
                userColor: userColor,
                assistantColor: assistantColor,
                // A11-2：消息流默认开启富文本——LLM 回复里带 Markdown
                // 是常态，关掉会看到满屏的 ** 和 #。
                richText: props['richText'] != false,
              ),
      ),
    );
  }

  /// 定时脉冲发生器渲染：工作室显形为带自测热区的逻辑卡片，运行时彻底隐形 SizedBox.shrink()
  static Widget _buildTimerBlock(BuildContext context, UIElement element, UIModule module, Size size) {
    final bool isStudio = UISceneModeScope.of(context);
    return _TimerBlockWidget(element: element, module: module, size: size, isStudio: isStudio);
  }

}

/// Button 的运行时手势分发器。
///
/// 单击的语义事件需要等待双击判定窗口结束，避免一次双击同时触发两次单击；
/// 但按下瞬间会立即发出仅供 Surface 视觉反馈使用的 `tap_down` 脉冲，
/// 因此按压/涟漪动画不会被双击判定窗口拖慢。
class _ButtonGestureWidget extends StatefulWidget {
  final String elementId;
  final UIModule module;
  final Widget child;

  const _ButtonGestureWidget({
    required this.elementId,
    required this.module,
    required this.child,
  });

  @override
  State<_ButtonGestureWidget> createState() => _ButtonGestureWidgetState();
}

class _ButtonGestureWidgetState extends State<_ButtonGestureWidget> {
  Timer? _doubleTapTimer;
  Timer? _longPressTimer;
  int? _activePointer;
  bool _longPressFired = false;
  bool _waitingForSecondTap = false;

  void _installLocalSnapshot() {
    final snapshot = UILinkerSnapshotScope.peekOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
  }

  int get _doubleTapIntervalMs =>
      ((widget.module.properties['doubleTapIntervalMs'] as num?)?.toInt() ?? 300)
          .clamp(100, 1000)
          .toInt();

  int get _longPressThresholdMs =>
      ((widget.module.properties['longPressThresholdMs'] as num?)?.toInt() ??
              500)
          .clamp(150, 3000)
          .toInt();

  void _onPointerDown(PointerDownEvent event) {
    // 一个按钮只跟踪首个有效指针，避免多指产生重复语义事件。
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _longPressFired = false;

    // 视觉脉冲不等待双击判定：LinkerService 仅允许其驱动 Surface 动画。
    _installLocalSnapshot();
    LinkerEventBus().emit(widget.elementId, 'tap_down');
    _longPressTimer = Timer(
      Duration(milliseconds: _longPressThresholdMs),
      () {
        if (!mounted || _activePointer == null) return;
        _longPressFired = true;
        _doubleTapTimer?.cancel();
        _doubleTapTimer = null;
        _waitingForSecondTap = false;
        _installLocalSnapshot();
        LinkerEventBus().emit(widget.elementId, 'long_press');
      },
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_longPressFired) return;

    if (_waitingForSecondTap) {
      _doubleTapTimer?.cancel();
      _doubleTapTimer = null;
      _waitingForSecondTap = false;
      _installLocalSnapshot();
      LinkerEventBus().emit(widget.elementId, 'double_tap');
      return;
    }

    _waitingForSecondTap = true;
    _doubleTapTimer = Timer(Duration(milliseconds: _doubleTapIntervalMs), () {
      if (!mounted || !_waitingForSecondTap) return;
      _waitingForSecondTap = false;
      _doubleTapTimer = null;
      _installLocalSnapshot();
      LinkerEventBus().emit(widget.elementId, 'tap');
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}

/// 运行时输入框：持久化 controller，避免上游刷新时重置光标和输入法编辑状态。
class _PreviewSelectWidget extends StatefulWidget {
  final UIElement element;
  final UIModule module;
  final List<SelectOption> options;
  final String currentSelection;
  final String expandDirection;
  final bool inputControlled;
  final String filterQuery;

  const _PreviewSelectWidget({
    super.key,
    required this.element,
    required this.module,
    required this.options,
    required this.currentSelection,
    required this.expandDirection,
    required this.inputControlled,
    required this.filterQuery,
  });

  @override
  State<_PreviewSelectWidget> createState() => _PreviewSelectWidgetState();
}

class _PreviewSelectWidgetState extends State<_PreviewSelectWidget> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  late String _selectedValue;
  double _anchorWidth = 0;

  void _installLocalSnapshot() {
    final snapshot = UILinkerSnapshotScope.peekOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.currentSelection;
  }

  @override
  void didUpdateWidget(covariant _PreviewSelectWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSelection != _selectedValue) {
      _selectedValue = widget.currentSelection;
    }
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _closeMenu();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    _anchorWidth = box?.size.width ?? 160;
    _menuEntry = OverlayEntry(builder: _buildMenuOverlay);
    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);
  }

  Widget _buildMenuOverlay(BuildContext overlayContext) {
    final opensUp = widget.expandDirection == 'up';
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeMenu,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: opensUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: opensUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, opensUp ? -6 : 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: _anchorWidth,
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD0D0D8)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.inputControlled)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          Icon(Icons.keyboard, size: 14, color: Color(0xFF7E57C2)),
                          SizedBox(width: 6),
                          Text('由输入控制选择', style: TextStyle(fontSize: 11, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _filteredOptions.length,
                      itemBuilder: (context, index) {
                  final option = _filteredOptions[index];
                  final selected = option.value == _selectedValue;
                  return InkWell(
                    onTap: widget.inputControlled ? null : () => _selectOption(option.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      color: selected ? const Color(0xFFEDE7F6) : Colors.transparent,
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? const Color(0xFF512DA8) : const Color(0xFF111116),
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _selectOption(String value) {
    widget.module.properties['current'] = value;
    widget.module.properties['is_expanded_preview'] = false;
    _installLocalSnapshot();
    LinkerEventBus().emit(widget.element.id, 'select_change', value);
    setState(() => _selectedValue = value);
    _closeMenu();
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  List<SelectOption> get _filteredOptions {
    final query = widget.filterQuery.toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((option) =>
            option.label.toLowerCase().contains(query) ||
            option.value.toLowerCase().contains(query))
        .toList();
  }

  String get _selectedLabel {
    final matches = widget.options
        .where((option) => option.value == _selectedValue)
        .toList();
    return matches.isEmpty ? _selectedValue : matches.first.label;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _toggleMenu,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFD0D0D8)),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111116),
                  ),
                ),
              ),
              if (widget.inputControlled)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.keyboard, size: 15, color: Color(0xFF7E57C2)),
                ),
              Icon(
                widget.expandDirection == 'up'
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
                color: const Color(0xFF666672),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBlockWidget extends StatefulWidget {
  final UIElement element;
  final UIModule module;
  final String placeholder;
  final LinkerTargetControlState controls;

  const _InputBlockWidget({
    super.key,
    required this.element,
    required this.module,
    required this.placeholder,
    required this.controls,
  });

  @override
  State<_InputBlockWidget> createState() => _InputBlockWidgetState();
}

class _InputBlockWidgetState extends State<_InputBlockWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.module.properties['text']?.toString() ?? '',
    );
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  void _commitValue() {
    final snapshot = UILinkerSnapshotScope.peekOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
    final value = _controller.text;
    final shouldClear =
        LinkerService.shouldClearInputAfterCommit(widget.element.id);
    // 提交后清空 controller 会触发一次失焦回调；忽略其空值二次提交。
    // 对“提交并清空”方案，空内容或纯空格均不属于有效提交。
    if (shouldClear && value.trim().isEmpty) {
      if (value.isNotEmpty) {
        widget.module.properties['text'] = '';
        widget.module.properties['value'] = '';
        _controller.clear();
      }
      return;
    }
    // A13-3：作为配额分配项时，提交的数字不能超出剩余额度。
    // 超额直接截断而不是拒绝提交——玩家输入 99 时给他能给的最大值，
    // 比整条丢弃、输入框莫名清空要好理解。
    var value2 = value;
    final ceiling = LinkerService.allocationCeilingFor(widget.module);
    if (ceiling != null) {
      final typed = double.tryParse(value.trim());
      if (typed == null) {
        // 非数字对配额没有意义，按 0 处理，避免污染统计。
        value2 = '0';
      } else if (typed > ceiling) {
        value2 = _trimAllocationNumber(ceiling);
      } else if (typed < 0) {
        value2 = '0';
      }
      if (value2 != value) {
        _controller.text = value2;
        _controller.selection =
            TextSelection.collapsed(offset: value2.length);
      }
      widget.module.properties['text'] = value2;
      widget.module.properties['value'] = value2;
    }

    final didChange = widget.module.properties['committedValue'] != value2;
    widget.module.properties['committedValue'] = value2;
    if (shouldClear && value.isNotEmpty) {
      widget.module.properties['text'] = '';
      widget.module.properties['value'] = '';
      _controller.clear();
    }
    if (didChange || shouldClear) {
      LinkerEventBus().emit(widget.element.id, 'input_commit', value2);
    }
  }

  /// 把配额上限格式化成输入框里的字符串。整数不带小数尾巴。
  static String _trimAllocationNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commitValue();
  }

  @override
  void didUpdateWidget(covariant _InputBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final externalText = widget.module.properties['text']?.toString() ?? '';
    if (externalText == _controller.text) return;

    final selectionOffset = _controller.selection.baseOffset.clamp(
      0,
      externalText.length,
    ).toInt();
    _controller.value = TextEditingValue(
      text: externalText,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final visualMode = module.properties['visualMode']?.toString() ?? 'filled';
    final placeholderColor = Color((module.properties['placeholderColor'] as num?)?.toInt() ?? 0xFF888896);
    final inputTextColor = Color((module.properties['inputTextColor'] as num?)?.toInt() ?? 0xFF111116);

    // 文本落点。
    //
    // 输入框被拉高后，单行 TextField 的文字仍垂直居中，作者往往期望
    // 它贴着顶部开始（用户反馈）。这两个属性让作者自己决定。
    final vAlign = module.properties['textVerticalAlign']?.toString() ?? 'center';
    final hAlign = module.properties['textHorizontalAlign']?.toString() ?? 'left';
    final multiline = module.properties['multiline'] == true;

    // 多行时**必须**顶部对齐：TextAlignVertical 对多行框不起作用，
    // 而且从中间往下写字本来也不合理。
    final effectiveVAlign = multiline ? 'top' : vAlign;

    const vAlignMap = {
      'top': TextAlignVertical.top,
      'center': TextAlignVertical.center,
      'bottom': TextAlignVertical.bottom,
    };
    const hAlignMap = {
      'left': TextAlign.left,
      'center': TextAlign.center,
      'right': TextAlign.right,
    };

    return Container(
      // 单行时靠 alignment 定位内容；多行要让 TextField 撑满，
      // 否则 Container 会把它压成一行高，换行根本看不见。
      alignment: multiline
          ? null
          : switch (effectiveVAlign) {
              'top' => Alignment.topLeft,
              'bottom' => Alignment.bottomLeft,
              _ => Alignment.centerLeft,
            },
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: visualMode == 'filled' ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: visualMode == 'transparent' ? null : Border.all(color: module.color.withValues(alpha: visualMode == 'outline' ? 0.9 : 0.5), width: visualMode == 'outline' ? 1.4 : 1),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.controls.enabled,
        readOnly: widget.controls.locked,
        maxLength: (module.properties['maxLength'] as num?)?.toInt(),
        // maxLines: null + expands: true 让输入区填满可用高度，
        // 文字自然从顶部开始排。
        maxLines: multiline ? null : 1,
        expands: multiline,
        textAlign: hAlignMap[hAlign] ?? TextAlign.left,
        textAlignVertical: vAlignMap[effectiveVAlign] ?? TextAlignVertical.center,
        // 多行时回车用来换行，不能再当提交；
        // 单行保持 done，回车即提交（sendsMessage 依赖这个）。
        keyboardType: multiline ? TextInputType.multiline : null,
        textInputAction: multiline ? TextInputAction.newline : null,
        style: TextStyle(fontSize: 13, color: inputTextColor),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: widget.placeholder,
          hintStyle: TextStyle(fontSize: 12, color: placeholderColor),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          counterText: '',
        ),
        onSubmitted: (_) => _commitValue(),
        onChanged: (value) {
          module.properties['text'] = value;
          module.properties['value'] = value;
          final snapshot = UILinkerSnapshotScope.peekOf(context);
          if (snapshot != null) {
            LinkerService.installSnapshot(snapshot);
          }
          LinkerEventBus().emit(widget.element.id, 'input_change', value);
        },
      ),
    );
  }
}

class _TimerBlockWidget extends StatefulWidget {
  final UIElement element;
  final UIModule module;
  final Size size;
  final bool isStudio;

  const _TimerBlockWidget({required this.element, required this.module, required this.size, required this.isStudio});

  @override
  State<_TimerBlockWidget> createState() => _TimerBlockWidgetState();
}

class _TimerBlockWidgetState extends State<_TimerBlockWidget> {
  Timer? _timer;
  Timer? _initialDelayTimer;
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkTimerState();
  }

  @override
  void didUpdateWidget(covariant _TimerBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkTimerState();
  }

  void _startPeriodicTimer({
    required int intervalMs,
    required int maxTicks,
    required Map<String, dynamic> props,
    required String pulseType,
    required double stepValue,
    required bool loop,
  }) {
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        final current = (props['currentVal'] as num?)?.toDouble() ?? 0.0;
        if (pulseType == 'toggle') {
          props['currentVal'] = current == 1.0 ? 0.0 : 1.0;
        } else if (pulseType == 'timestamp') {
          props['currentVal'] = current + intervalMs / 1000.0;
        } else if (pulseType == 'countdown') {
          final next = current - stepValue;
          props['currentVal'] = next <= 0.0 ? 0.0 : next;
          if (next <= 0.0 && !loop) {
            props['isRunning'] = false;
          }
        } else {
          props['currentVal'] = current + stepValue;
        }
        _tickCount++;
        props['tickCount'] = _tickCount;
      });

      final snapshot = UILinkerSnapshotScope.peekOf(context);
      if (snapshot != null) {
        LinkerService.installSnapshot(snapshot);
      }
      LinkerEventBus().emit(
        widget.element.id,
        'timer_tick',
        props['currentVal'],
      );

      final countdownFinished =
          pulseType == 'countdown' && props['isRunning'] == false;
      if (countdownFinished || (maxTicks > 0 && _tickCount >= maxTicks)) {
        props['isRunning'] = false;
        timer.cancel();
        _timer = null;
      }
    });
  }

  void _checkTimerState() {
    final snapshot = UILinkerSnapshotScope.peekOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
    final props = widget.module.properties;
    final runMode = LinkerService.resolveTimerRunMode(widget.module);
    final systemRunning = LinkerService.resolveTimerSystemRunning(widget.module);
    final highRisk = LinkerService.timerHasHighRiskOutputs(widget.module);
    final configuredInterval =
        (props['interval'] as num?)?.toDouble() ?? 1.0;
    final minimumInterval = runMode == 'manual'
        ? 0.1
        : highRisk
            ? 1.0
            : 0.5;
    final intervalSeconds = configuredInterval
        .clamp(minimumInterval, 60.0)
        .toDouble();
    final initialDelaySeconds =
        ((props['initialDelay'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 3600.0)
            .toDouble();
    final maxTicks = (props['maxTicks'] as num?)?.toInt() ?? 0;
    final pulseType = props['pulseType']?.toString() ?? 'increment';
    final stepValue = (props['stepValue'] as num?)?.toDouble() ?? 1.0;
    final loop = props['loop'] != false;
    final isRunning = widget.isStudio
        ? false
        : (runMode == 'controlled'
            ? systemRunning == true
            : runMode == 'manual'
                ? props['isRunning'] == true
                : true);

    if (isRunning && _timer == null && _initialDelayTimer == null) {
      _tickCount = (props['tickCount'] as num?)?.toInt() ?? 0;
      void start() {
        if (!mounted) return;
        _initialDelayTimer = null;
        _startPeriodicTimer(
          intervalMs: (intervalSeconds * 1000).toInt(),
          maxTicks: maxTicks,
          props: props,
          pulseType: pulseType,
          stepValue: stepValue,
          loop: loop,
        );
      }
      if (initialDelaySeconds > 0) {
        _initialDelayTimer = Timer(
          Duration(milliseconds: (initialDelaySeconds * 1000).toInt()),
          start,
        );
      } else {
        start();
      }
    } else if (!isRunning) {
      _initialDelayTimer?.cancel();
      _initialDelayTimer = null;
      _timer?.cancel();
      _timer = null;
      _tickCount = 0;
    }
  }

  @override
  void dispose() {
    _initialDelayTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = UILinkerSnapshotScope.maybeOf(context);
    if (snapshot != null) {
      LinkerService.installSnapshot(snapshot);
    }
    if (!widget.isStudio) {
      return const SizedBox.shrink();
    }
    final props = widget.module.properties;
    final runMode = LinkerService.resolveTimerRunMode(widget.module);
    final systemRunning = LinkerService.resolveTimerSystemRunning(widget.module);
    final highRisk = LinkerService.timerHasHighRiskOutputs(widget.module);
    final configuredInterval =
        (props['interval'] as num?)?.toDouble() ?? 1.0;
    final minimumInterval = runMode == 'manual'
        ? 0.1
        : highRisk
            ? 1.0
            : 0.5;
    final interval = configuredInterval.clamp(minimumInterval, 60.0).toDouble();
    final currentVal = (props['currentVal'] as num?)?.toDouble() ?? 0.0;
    final tickCount = (props['tickCount'] as num?)?.toInt() ?? 0;
    final maxTicks = (props['maxTicks'] as num?)?.toInt() ?? 0;
    final isRunning = widget.isStudio
        ? false
        : (runMode == 'controlled'
            ? systemRunning == true
            : runMode == 'manual'
                ? props['isRunning'] == true
                : true);
    final pulseType = props['pulseType']?.toString() ?? 'increment';
    final label = pulseType == 'countdown'
        ? '倒计时脉冲'
        : pulseType == 'toggle'
            ? '翻转脉冲'
            : '定时脉冲';

    return Container(
      width: widget.size.width,
      height: widget.size.height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRunning ? const Color(0xFFFFF3E0) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFFF9100),
          width: isRunning ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.timer : Icons.timer_outlined,
                size: 14,
                color: isRunning ? const Color(0xFFFF6D00) : const Color(0xFFF57C00),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isRunning ? '运行中 · $label' : '等待前置触发',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isRunning ? const Color(0xFFE65100) : const Color(0xFFF57C00),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${interval.toStringAsFixed(1)}s · 值 ${currentVal.toStringAsFixed(0)} · Tick $tickCount/${maxTicks == 0 ? '∞' : maxTicks}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF6D4C41)),
          ),
        ],
      ),
    );
  }
}

Path getHeartPath(Rect rect) {
  final w = rect.width;
  final h = rect.height;
  final l = rect.left;
  final t = rect.top;
  final path = Path();
  path.moveTo(l + 0.5 * w, t + h * 0.35);
  path.cubicTo(l + 0.2 * w, t + h * 0.1, l - 0.25 * w, t + h * 0.6, l + 0.5 * w, t + h);
  path.cubicTo(l + 1.25 * w, t + h * 0.6, l + 0.8 * w, t + h * 0.1, l + 0.5 * w, t + h * 0.35);
  path.close();
  return path;
}

Path getStarPath(Rect rect, int points, double innerRatio) {
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final rx = rect.width / 2;
  final ry = rect.height / 2;
  final path = Path();
  final step = math.pi / points;
  var angle = -math.pi / 2;

  for (var i = 0; i < points * 2; i++) {
    final rRatio = (i % 2 == 0) ? 1.0 : innerRatio;
    final x = cx + rx * rRatio * math.cos(angle);
    final y = cy + ry * rRatio * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
    angle += step;
  }
  path.close();
  return path;
}

class _PathClipper extends CustomClipper<Path> {
  final Path Function(Rect rect) getPathFunc;
  _PathClipper(this.getPathFunc);
  @override
  Path getClip(Size size) => getPathFunc(Rect.fromLTWH(0, 0, size.width, size.height));
  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => false;
}

class UIPrimitiveArtPainter extends CustomPainter {
  final Map<String, dynamic> properties;

  UIPrimitiveArtPainter(this.properties);

  @override
  void paint(Canvas canvas, Size size) {
    final rawLayers = properties['layers'];
    if (rawLayers is! List || size.width <= 0 || size.height <= 0) return;

    final layers = <UIPrimitiveLayer>[];
    for (final raw in rawLayers) {
      if (raw is Map) {
        layers.add(UIPrimitiveLayer.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (layers.isEmpty) return;

    for (final layer in layers) {
      _paintLayer(canvas, size, layer);
    }
  }

  Rect _layerRect(Size canvasSize, UIPrimitiveLayer layer) {
    final x = layer.offset.dx * canvasSize.width;
    final y = layer.offset.dy * canvasSize.height;
    final w = layer.size.width * canvasSize.width;
    final h = layer.size.height * canvasSize.height;
    return Rect.fromLTWH(x, y, w, h);
  }

  void _paintLayer(Canvas canvas, Size size, UIPrimitiveLayer layer) {
    final rect = _layerRect(size, layer);
    if (rect.width <= 0 || rect.height <= 0) return;

    final paint = Paint()
      ..color = layer.color.withValues(alpha: layer.opacity)
      ..style = PaintingStyle.fill;

    final r = layer.borderRadius;

    switch (layer.shape) {
      case UIModuleShape.circle:
        canvas.drawOval(rect, paint);
        break;
      case UIModuleShape.capsule:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
          paint,
        );
        break;
      case UIModuleShape.rounded:
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), paint);
        break;
      case UIModuleShape.heart:
        canvas.drawPath(getHeartPath(rect), paint);
        break;
      case UIModuleShape.star5:
        canvas.drawPath(getStarPath(rect, 5, 0.45), paint);
        break;
      case UIModuleShape.star4:
        canvas.drawPath(getStarPath(rect, 4, 0.4), paint);
        break;
      case UIModuleShape.rectangle:
        canvas.drawRect(rect, paint);
        break;
    }

    // 额外描边支持
    if (layer.properties['stroke'] == true) {
      final strokePaint = Paint()
        ..color = (layer.properties['strokeColor'] != null
            ? Color(layer.properties['strokeColor'])
            : Colors.black)
            .withValues(alpha: layer.opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (layer.properties['strokeWidth'] ?? 1.5).toDouble();
      switch (layer.shape) {
        case UIModuleShape.circle:
          canvas.drawOval(rect, strokePaint);
          break;
        case UIModuleShape.capsule:
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
            strokePaint,
          );
          break;
        case UIModuleShape.rounded:
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), strokePaint);
          break;
        case UIModuleShape.heart:
          canvas.drawPath(getHeartPath(rect), strokePaint);
          break;
        case UIModuleShape.star5:
          canvas.drawPath(getStarPath(rect, 5, 0.45), strokePaint);
          break;
        case UIModuleShape.star4:
          canvas.drawPath(getStarPath(rect, 4, 0.4), strokePaint);
          break;
        case UIModuleShape.rectangle:
          canvas.drawRect(rect, strokePaint);
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant UIPrimitiveArtPainter oldDelegate) {
    return oldDelegate.properties != properties;
  }
}

class _MultiLinePainter extends CustomPainter {
  final Color color;
  final double thickness;
  final String lineStyle;
  final String axis;
  final double dashLength;
  final double gapLength;

  _MultiLinePainter({required this.color, required this.thickness, required this.lineStyle, required this.axis, required this.dashLength, required this.gapLength});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = lineStyle == 'dotted' ? StrokeCap.round : StrokeCap.butt;

    final bool isHoriz = axis != 'vertical';
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    void drawLineSegment(Offset p1, Offset p2) {
      if (lineStyle == 'solid') {
        canvas.drawLine(p1, p2, paint);
      } else if (lineStyle == 'dotted') {
        final double step = thickness * 2.5;
        final double totalLen = (p2 - p1).distance;
        final Offset dir = (p2 - p1) / (totalLen > 0 ? totalLen : 1.0);
        var dist = 0.0;
        while (dist <= totalLen) {
          canvas.drawPoints(ui.PointMode.points, [p1 + dir * dist], paint);
          dist += step;
        }
      } else {
        final double dl = math.max(1.0, dashLength);
        final double gl = math.max(1.0, gapLength);
        final double totalLen = (p2 - p1).distance;
        final Offset dir = (p2 - p1) / (totalLen > 0 ? totalLen : 1.0);
        var dist = 0.0;
        while (dist < totalLen) {
          final double next = math.min(totalLen, dist + dl);
          canvas.drawLine(p1 + dir * dist, p1 + dir * next, paint);
          dist = next + gl;
        }
      }
    }

    if (lineStyle == 'curve') {
      final curvePath = Path();
      if (isHoriz) {
        curvePath.moveTo(0, cy);
        curvePath.quadraticBezierTo(size.width / 2, size.height * 0.88, size.width, cy);
      } else {
        curvePath.moveTo(cx, 0);
        curvePath.quadraticBezierTo(size.width * 0.88, size.height / 2, cx, size.height);
      }
      canvas.drawPath(curvePath, paint);
    } else if (lineStyle == 'double') {
      final double offset = thickness * 1.5;
      if (isHoriz) {
        drawLineSegment(Offset(0, cy - offset), Offset(size.width, cy - offset));
        drawLineSegment(Offset(0, cy + offset), Offset(size.width, cy + offset));
      } else {
        drawLineSegment(Offset(cx - offset, 0), Offset(cx - offset, size.height));
        drawLineSegment(Offset(cx + offset, 0), Offset(cx + offset, size.height));
      }
    } else {
      if (isHoriz) {
        drawLineSegment(Offset(0, cy), Offset(size.width, cy));
      } else {
        drawLineSegment(Offset(cx, 0), Offset(cx, size.height));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) =>
      old.color != color || old.thickness != thickness || old.lineStyle != lineStyle || old.axis != axis || old.dashLength != dashLength || old.gapLength != gapLength;
}

class _RingProgressBarPainter extends CustomPainter {
  final double progress;
  final Color fillColor;
  final Color trackColor;
  final double strokeWidth;

  _RingProgressBarPainter({required this.progress, required this.fillColor, required this.trackColor, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingProgressBarPainter old) =>
      old.progress != progress || old.fillColor != fillColor || old.trackColor != trackColor || old.strokeWidth != strokeWidth;
}

/// 抢占式水平拖动识别器（滑块专用）。
///
/// 背景：滑块「点击轨道能跳转、但拖不动」。点击能生效说明触摸确实到达了
/// 滑块，问题出在水平拖动的竞技场竞争——聊天页根部注册了 `onHorizontalDrag*`
/// 用于滑出侧栏，挂件外层又加了一层同类型的吸收器，
/// 光靠「层级更深」并不足以让滑块稳定胜出。
///
/// 处理：在 `addAllowedPointer` 阶段立即宣告胜利，抢先关闭竞技场。
/// 这是安全的——滑块本来就该独占自己区域内的水平拖动，
/// 而竖直滚动由父级的 Scrollable 走另一套识别器，不受影响。
class _EagerHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 消息流列表：固定区域内滚动，新消息自动滚到底。
///
/// 独立成 StatefulWidget 是为了持有 ScrollController——
/// 作者固定了窗口尺寸后，内容必须能在其中滚动，
/// 否则长对话会被裁掉且无法查看。
class _MessageFlowList extends StatefulWidget {
  final List<FlowMessage> messages;
  final double fontSize;
  final double bubbleRadius;
  final Color userColor;
  final Color assistantColor;

  /// A11-2：气泡内容是否按 Markdown / HTML 渲染。
  final bool richText;

  const _MessageFlowList({
    required this.messages,
    required this.fontSize,
    required this.bubbleRadius,
    required this.userColor,
    required this.assistantColor,
    this.richText = true,
  });

  @override
  State<_MessageFlowList> createState() => _MessageFlowListState();
}

class _MessageFlowListState extends State<_MessageFlowList> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant _MessageFlowList old) {
    super.didUpdateWidget(old);
    // 新消息或流式追加都要跟到底部。
    final grew = widget.messages.length != old.messages.length;
    final lastChanged = widget.messages.isNotEmpty &&
        old.messages.isNotEmpty &&
        widget.messages.last.content != old.messages.last.content;
    if (grew || lastChanged) _scheduleScrollToBottom();
  }

  /// 用户主动向上翻看历史时不要硬拽回底部。
  bool get _isNearBottom {
    if (!_controller.hasClients) return true;
    final max = _controller.position.maxScrollExtent;
    return max - _controller.offset < 80;
  }

  void _scheduleScrollToBottom() {
    final shouldFollow = _isNearBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || !shouldFollow) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final msg = widget.messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.66,
            ),
            decoration: BoxDecoration(
              color: msg.isUser ? widget.userColor : widget.assistantColor,
              borderRadius: BorderRadius.circular(widget.bubbleRadius),
            ),
            child: Builder(
              builder: (context) {
                final style = TextStyle(
                  fontSize: widget.fontSize,
                  height: 1.35,
                  color: const Color(0xFF111116),
                );
                if (!widget.richText) {
                  return Text(msg.content, style: style);
                }
                // 气泡内不开 selectable：长按选中会与列表滚动、
                // 以及外层可能存在的拖动手势抢竞技场。
                return AssemblyRichText(
                  text: msg.content,
                  baseStyle: style,
                  textAlign: TextAlign.left,
                  highlightRules: TextHighlightScope.maybeOf(context),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 可滚动长文本块。
///
/// 用于 readme 说明、道具描述这类「一整块静态内容」：
///   - 从顶部开始，不像消息流那样自动滚到底；
///   - 带滚动条，让玩家知道还有内容；
///   - 可选中复制。
class _ScrollableTextBlock extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final double padding;

  /// A11-2：是否按 Markdown / HTML 渲染。
  final bool richText;

  const _ScrollableTextBlock({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.padding,
    this.richText = true,
  });

  @override
  State<_ScrollableTextBlock> createState() => _ScrollableTextBlockState();
}

class _ScrollableTextBlockState extends State<_ScrollableTextBlock> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _ScrollableTextBlock old) {
    super.didUpdateWidget(old);
    // 内容被 linker / 数据通道换成另一段时回到顶部，
    // 否则玩家会从上一段的滚动位置开始看新内容。
    if (old.text != widget.text && _controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: EdgeInsets.all(widget.padding),
        child: widget.richText
            // 长文说明按整块渲染，且允许选中复制——
            // readme 里的设定、道具描述都是玩家会想摘出来的内容。
            ? SizedBox(
                width: double.infinity,
                child: AssemblyRichText(
                  text: widget.text,
                  baseStyle: widget.style,
                  textAlign: widget.textAlign,
                  selectable: true,
                  highlightRules: TextHighlightScope.maybeOf(context),
                ),
              )
            : SelectableText(
                widget.text,
                style: widget.style,
                textAlign: widget.textAlign,
              ),
      ),
    );
  }
}

/// 粒子迸发画笔。
///
/// 从中心向外抛出一圈小圆点：位置随进度外扩、半径与不透明度随之衰减。
/// 用固定角度分布而非随机——随机会让每帧重绘时粒子乱跳，
/// 因为 CustomPainter 每帧都是重新构造的、拿不到上一帧的状态。
class _ParticleBurstPainter extends CustomPainter {
  final double progress;
  final double intensity;
  final Color color;

  const _ParticleBurstPainter({
    required this.progress,
    required this.intensity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1 || size.isEmpty) return;

    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final cx = halfW;
    final cy = halfH;

    // ⚠️ 扩散半径不能用 shortestSide。
    // 进度条 200×12 时短边是 12，粒子只飞 14px、占可用横向距离的 14%，
    // 即用户说的「只有中点一点点，看着太小气」。
    // 改用椭圆半径后各方向按自己的可用距离伸展，能飞满约 97%。
    final spread = 0.55 + 0.75 * intensity;

    // 粒子数随组件面积增加：小图标不必堆满，长条要够密才不显稀疏。
    // 用户反馈「量有些少」，基数从 14 提到 22，宽组件最多 40。
    final areaFactor = (size.width * size.height) / (120.0 * 40.0);
    final count = (22 + areaFactor * 6).clamp(22, 40).toInt();

    final fade = (1.0 - progress).clamp(0.0, 1.0);
    // 初速度衰减：先快后慢，比匀速外扩自然。
    final travel = 1.0 - math.pow(1.0 - progress, 2.2).toDouble();
    // 重力下坠（用户要求）：随时间平方累积。
    final gravity = halfH * 1.6 * intensity * progress * progress;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      // 由 index 派生的伪随机，不能用 Random()——
      // CustomPainter 每帧重新构造，随机会让粒子逐帧乱跳。
      final h1 = ((i * 73) % 101) / 101.0; // 0..1
      final h2 = ((i * 149) % 97) / 97.0;
      final h3 = ((i * 37) % 89) / 89.0;

      // 角度：均匀分布 + 抖动，避免连成规整圆环。
      final angle = (math.pi * 2 / count) * (i + 0.5) + (h1 - 0.5) * 0.45;

      // ⚠️ 发射源不是一个点。
      //
      // 上一版所有粒子共用正中心，视觉上就是「一个点在爆」（用户反馈）。
      // 真实迸发的源头有面积，粒子从不同位置飞出。
      // 这里让起点在中心附近的小椭圆内散开，横向铺得更宽
      // （长条组件的源头本来就该沿长轴展开）。
      final originSpread = 0.22 + 0.18 * intensity;
      final originAngle = h2 * math.pi * 2;
      final originR = math.sqrt(h3); // sqrt 让点在圆面内均匀而非聚在中心
      final ox = cx + math.cos(originAngle) * halfW * originSpread * originR;
      final oy = cy + math.sin(originAngle) * halfH * originSpread * originR;

      // 飞行距离交错，十几颗才不会连成一圈。
      final reach = 0.62 + h1 * 0.55;

      final dx = math.cos(angle) * halfW * spread * reach * travel;
      final dy = math.sin(angle) * halfH * spread * reach * travel + gravity;

      final sizeJitter = 0.6 + h3 * 0.8;
      final radius = (2.6 * intensity * sizeJitter + 0.7) * fade;
      if (radius <= 0.15) continue;

      paint.color = color.withValues(
        alpha: (fade * (0.55 + 0.45 * sizeJitter)).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(ox + dx, oy + dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.color != color;
  }
}

/// 进度条填充边界的波动。
///
/// ## 为什么要独立成一个带 Ticker 的组件
///
/// 用户反馈水波「只有交接处有明显扰动，显示效果太小了」。
///
/// 这是折射的**固有局限**：折射的本质是采样位置偏移，
/// 而进度条内部是大片纯色——偏移 5px 取到的还是同一个颜色。
/// 只有已填充/未填充的交界处存在颜色梯度，所以只有那条线在动。
/// 加强折射强度解决不了，只会让交界处抖得更厉害。
///
/// 正确解法是**制造新的可动边界**：把填充右缘画成波浪线。
///
/// 试过两种「从外部拿动画进度」的写法，都失败了：
/// 1. 读 props 里的 `timestamp` —— 值变化通路里它恒为 0
///    （渲染函数不能写 props），`isActiveAt` 永远 false；
/// 2. 用静态通道从外层压入 —— `_buildProgressBar` 在 `_renderModule`
///    阶段执行，比外层动画包裹早得多，push/pop 根本包不住它。
///
/// 所以让它**自己驱动**：检测到进度值变化就起一轮波，
/// 不依赖任何外部时序。
class _WavyProgressBar extends StatefulWidget {
  final double progress;
  final Color fillColor;
  final Color trackColor;
  final double intensity;
  final int durationMs;
  final Size size;

  const _WavyProgressBar({
    required this.progress,
    required this.fillColor,
    required this.trackColor,
    required this.intensity,
    required this.durationMs,
    required this.size,
  });

  @override
  State<_WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<_WavyProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 上次起波时刻，用于限流（见 didUpdateWidget 的说明）。
  DateTime? _lastRestart;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );
  }

  @override
  void didUpdateWidget(covariant _WavyProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationMs != oldWidget.durationMs) {
      _controller.duration = Duration(milliseconds: widget.durationMs);
    }
    // 值变了就起一轮波。
    //
    // ⚠️ 这里**不能**用 `!isAnimating` 拦住新波。
    //
    // 那样是串行排队：一轮播完才允许下一轮，
    // 连续拖动时每次都要等满一个 duration，
    // 用户反馈「每次的动画等待时间太长」。
    //
    // 波浪边界是**连续相位**的（正弦随 t 推进），
    // 从头重启不会出现跳变，因此可以随时刷新。
    // 真正要避免的是每帧都重启——那会让相位永远停在起点，
    // 所以用时间限流而不是「播完再说」。
    if (widget.progress != oldWidget.progress) {
      final now = DateTime.now();
      final last = _lastRestart;
      if (last == null ||
          now.difference(last) >= const Duration(milliseconds: 90)) {
        _lastRestart = now;
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, _) => CustomPaint(
        size: widget.size,
        painter: _WavyProgressPainter(
          progress: widget.progress,
          fillColor: widget.fillColor,
          trackColor: widget.trackColor,
          animProgress: _controller.value,
          intensity: widget.intensity,
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  final double progress;
  final Color fillColor;
  final Color trackColor;

  /// 波动进度 0..1。0 或 1 表示静止。
  final double animProgress;
  final double intensity;

  const _WavyProgressPainter({
    required this.progress,
    required this.fillColor,
    required this.trackColor,
    required this.animProgress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
    if (progress <= 0.0) return;

    final edgeX = size.width * progress;
    final t = animProgress;

    // 静止、或进度满格（没有边界可动）时画直边。
    final envelope = (t <= 0.0 || t >= 1.0)
        ? 0.0
        : math.pow(1.0 - t, 1.2).toDouble();
    // 波幅。
    //
    // 曾取组件高度的一半，但进度条通常只有 12px 高，
    // 折算下来波幅仅 3.6px——叠加在折射之上根本分辨不出来
    // （用户反馈「进度条的边界没有那种效果」）。
    //
    // 改为以高度为基准但允许超出：边界左右摆动本就不受高度约束，
    // 真正的限制是「不能甩出组件宽度」。
    // 1.6 倍高度对 12px 的条约等于 ±11px，明显可见又不至于失真。
    final amp = size.height * 1.6 * intensity * envelope;

    if (amp <= 0.3 || progress >= 1.0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, edgeX, size.height),
        Paint()..color = fillColor,
      );
      return;
    }

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height);
    // 边界摆动不能越过组件左右边缘，否则填充会凭空断开。
    final minX = 0.0;
    final maxX = size.width;

    // 沿纵向起伏，相位随时间推进，让边界在「荡」而不是整体平移。
    const steps = 24;
    final phase = t * 2.5 * math.pi * 2;
    for (var i = steps; i >= 0; i--) {
      final y = size.height * i / steps;
      final n = y / size.height;
      // 两个不同频率叠加，避免规整正弦显得机械。
      final wave = math.sin(n * math.pi * 2.2 - phase) * 0.7 +
          math.sin(n * math.pi * 3.7 - phase * 1.3) * 0.3;
      path.lineTo((edgeX + wave * amp).clamp(minX, maxX), y);
    }

    path.close();
    canvas.drawPath(path, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animProgress != animProgress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.trackColor != trackColor;
  }
}

/// 进度条的边缘喷射粒子。
///
/// ## 为什么不用通用的中心爆发
///
/// 通用粒子从组件正中心向四周炸开，表达的是
/// 「这个组件有事发生」。而进度条有明确的**数值位置**——
/// 从填充边缘喷射，语义直接变成「数值在这里推进了」，
/// 与组件本身的含义吻合（用户提议）。
///
/// ## 为什么是自驱动
///
/// 和 `_WavyProgressBar` 同样的理由：
/// `_buildProgressBar` 在 `_renderModule` 阶段执行，
/// 早于所有动画包裹层，拿不到外层的动画时序，
/// 也无法把数值进度反向传给外层。
/// 所以让它自己持有 `AnimationController`，
/// 检测到数值变化就起一轮喷射。
class _EdgeBurstProgressBar extends StatefulWidget {
  final double progress;
  final Color fillColor;
  final Color trackColor;
  final BorderRadius radius;
  final double intensity;
  final int durationMs;
  final Color particleColor;
  final Size size;

  const _EdgeBurstProgressBar({
    required this.progress,
    required this.fillColor,
    required this.trackColor,
    required this.radius,
    required this.intensity,
    required this.durationMs,
    required this.particleColor,
    required this.size,
  });

  @override
  State<_EdgeBurstProgressBar> createState() => _EdgeBurstProgressBarState();
}

/// 一次喷射的记录。
///
/// 粒子是**离散**的：重启控制器会让上一批粒子瞬间消失，
/// 与波浪边界那种连续相位不同，所以必须每次喷射各自持有一个控制器。
class _BurstWave {
  final AnimationController controller;

  /// 起喷位置（归一化 0..1）。
  ///
  /// 记录**变化发生那一刻**的边缘，而不是实时进度——
  /// 否则连续拖动时喷射点会跟着手指跑，看不出是从哪儿溅出来的。
  final double originProgress;

  /// 飞出方向：+1 数值增长（向前），-1 数值减少（向后）。
  ///
  /// 用户选定「跟随数值变化方向」：扣血时粒子应该往回飞，
  /// 一律向前会让减少也看起来像增长。
  final double direction;

  const _BurstWave({
    required this.controller,
    required this.originProgress,
    required this.direction,
  });
}

class _EdgeBurstProgressBarState extends State<_EdgeBurstProgressBar>
    with TickerProviderStateMixin {
  /// 同时在飞的几批粒子。
  ///
  /// 曾用单个控制器 + `if (isAnimating) return`，那是串行排队：
  /// 一批飞完才允许下一批，连续拖动时每次都要等满一个 duration
  /// （用户反馈「每次的动画等待时间太长」）。
  /// 改为并发后，连续变化会喷出层层叠起的粒子流。
  final List<_BurstWave> _waves = <_BurstWave>[];

  /// 同时存在的批次上限。超出时淘汰最老的一批。
  static const int _maxConcurrent = 3;

  /// 两次喷射的最小间隔。
  ///
  /// 拖滑块时值每帧都在变，不限流会每帧喷一批、瞬间堆满上限，
  /// 且彼此位置几乎重合，看起来只是一团更密的粒子。
  static const Duration _minGap = Duration(milliseconds: 90);
  DateTime? _lastSpawn;

  @override
  void didUpdateWidget(covariant _EdgeBurstProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.progress - oldWidget.progress;
    if (delta == 0.0) return;

    final now = DateTime.now();
    final last = _lastSpawn;
    if (last != null && now.difference(last) < _minGap) return;
    _lastSpawn = now;

    _spawn(
      origin: oldWidget.progress,
      direction: delta > 0 ? 1.0 : -1.0,
    );
  }

  void _spawn({required double origin, required double direction}) {
    while (_waves.length >= _maxConcurrent) {
      final oldest = _waves.removeAt(0);
      oldest.controller.dispose();
    }

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );
    final wave = _BurstWave(
      controller: controller,
      originProgress: origin,
      direction: direction,
    );
    _waves.add(wave);

    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      // 结束回调发生在构建过程中，直接 setState 会撞上
      // 「widget tree was locked」。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          controller.dispose();
          return;
        }
        if (_waves.remove(wave)) {
          controller.dispose();
          setState(() {});
        }
      });
    });

    controller.forward(from: 0.0);
    setState(() {});
  }

  @override
  void dispose() {
    for (final w in _waves) {
      w.controller.dispose();
    }
    _waves.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        _waves.map((w) => w.controller).toList(),
      ),
      builder: (ctx, _) {
        return Stack(
          // 粒子允许飞出组件边界，否则在细长的进度条上施展不开。
          clipBehavior: Clip.none,
          children: [
            // 进度条本体照常裁切圆角。
            ClipRRect(
              borderRadius: widget.radius,
              child: Container(
                decoration: BoxDecoration(color: widget.trackColor),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: widget.progress,
                    heightFactor: 1.0,
                    child: Container(color: widget.fillColor),
                  ),
                ),
              ),
            ),
            // 粒子层不裁切；每批各画各的。
            for (final w in _waves)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EdgeBurstPainter(
                      animProgress: w.controller.value,
                      originProgress: w.originProgress,
                      direction: w.direction,
                      intensity: widget.intensity,
                      color: widget.particleColor,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EdgeBurstPainter extends CustomPainter {
  final double animProgress;
  final double originProgress;
  final double direction;
  final double intensity;
  final Color color;

  const _EdgeBurstPainter({
    required this.animProgress,
    required this.originProgress,
    required this.direction,
    required this.intensity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = animProgress;
    if (t <= 0.0 || t >= 1.0 || size.isEmpty) return;

    final originX = size.width * originProgress;
    final cy = size.height / 2;

    final fade = (1.0 - t).clamp(0.0, 1.0);
    // 初速度衰减：先快后慢，比匀速外飞自然。
    final travel = 1.0 - math.pow(1.0 - t, 2.2).toDouble();
    // 重力下坠，随时间平方累积。
    final gravity = size.height * 1.2 * intensity * t * t;

    // 喷射距离以组件高度为基准而非宽度——
    // 进度条很扁，用宽度会让粒子飞得离谱地远。
    final reachBase = size.height * (2.2 + 2.6 * intensity);

    const count = 16;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      // 由 index 派生的伪随机：CustomPainter 每帧重建，
      // 用 Random() 会让粒子逐帧乱跳。
      final h1 = ((i * 73) % 101) / 101.0;
      final h2 = ((i * 149) % 97) / 97.0;
      final h3 = ((i * 37) % 89) / 89.0;

      // 扇形张角：以水平方向为主轴，上下各散开约 55°。
      // 纯直线喷射太机械，全向又失去方向感。
      final spreadAngle = (h1 - 0.5) * (math.pi * 0.62);
      final speed = 0.55 + h2 * 0.65;

      final dx = math.cos(spreadAngle) * reachBase * speed * travel * direction;
      final dy = math.sin(spreadAngle) * reachBase * speed * travel * 0.55 +
          gravity;

      final sizeJitter = 0.55 + h3 * 0.9;
      final r = (1.9 * intensity * sizeJitter + 0.6) * fade;
      if (r <= 0.12) continue;

      paint.color = color.withValues(
        alpha: (fade * (0.5 + 0.5 * sizeJitter)).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(originX + dx, cy + dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeBurstPainter oldDelegate) {
    return oldDelegate.animProgress != animProgress ||
        oldDelegate.originProgress != originProgress ||
        oldDelegate.direction != direction ||
        oldDelegate.intensity != intensity ||
        oldDelegate.color != color;
  }
}
