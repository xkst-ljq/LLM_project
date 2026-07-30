import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// RenderRepaintBoundary 由 rendering.dart 导出，material.dart **不转出**它。
// 漏掉这行会连带报三个错：类型未定义、debugNeedsPaint 与 toImageSync
// 被判为对 null 调用（因为 `is!` 类型收窄失效）。
import 'package:flutter/rendering.dart';

/// A12 水波折射（方案 A：片元着色器）。
///
/// ## 为什么必须是着色器
///
/// 水波前后改了五版，全是 Canvas 叠加绘制——在组件**上面**画圆环、
/// 画渐变光带、加色混合。底层像素一个都没移动，
/// 所以用户始终觉得「像两个图层」「不像波纹」。
/// 那是叠加绘制的天花板，不是参数没调好。
///
/// 只有逐像素重采样才能让**组件内容本身**被拉伸挤压。
///
/// ## 方案 C 的教训（网格变形）
///
/// 曾用 `drawVertices` 做过一版，用户反馈「看不出任何变化」。
/// 复盘发现根因不在数学：捕获纹理的回调只写字段、**从不 setState**，
/// 变形结果压根没被画出来，一直显示的是 fallback 原图。
///
/// 所以这里的纹理捕获做了两件事保证链路真的通：
/// 1. 捕获成功后**显式 setState**；
/// 2. 只在动画开始时抓一次，不存在「每帧抓 → setState → 再抓」的循环。
class RippleShaderLoader {
  RippleShaderLoader._();

  static ui.FragmentProgram? _program;
  static bool _loading = false;
  static bool _failed = false;

  /// 加载失败的原因。
  ///
  /// 着色器失败是**静默**的——`RippleShaderView` 会安静地退回原样显示，
  /// 用户只看到「没有动画」，无从判断是效果不对还是根本没加载。
  /// 这里留下原因，配合 debugPrint 至少能在控制台看到。
  static Object? lastError;

  /// 着色器是否已就绪。未就绪时调用方应回退到无动画显示。
  static bool get isReady => _program != null;

  /// 加载失败（例如构建时漏配 `shaders:`）。失败后不再重试。
  static bool get hasFailed => _failed;

  static ui.FragmentShader? createShader() => _program?.fragmentShader();

  /// 预加载。多次调用只会真正加载一次。
  static Future<void> ensureLoaded() async {
    if (_program != null || _loading || _failed) return;
    _loading = true;
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'shaders/ripple_refraction.frag',
      );
    } catch (error, stack) {
      // 着色器缺失或编译失败时不应拖垮整个 UI，
      // 调用方会退回「不播动画」而不是崩溃。
      //
      // 但必须留下痕迹：否则表现为「动画毫无反应」，
      // 与「效果做得不好」无法区分（已经因此浪费过一轮排查）。
      _failed = true;
      lastError = error;
      assert(() {
        debugPrint(
          '[RippleShader] 着色器加载失败，水波动画将退回无特效显示。\n'
          '常见原因：pubspec.yaml 漏配 shaders: 段、'
          '或 .frag 缺少 #extension GL_GOOGLE_include_directive。\n'
          '$error\n$stack',
        );
        return true;
      }());
    } finally {
      _loading = false;
    }
  }
}

/// 用着色器对子组件施加水波折射。
///
/// ## 为什么必须自定义 RenderObject
///
/// 曾用 `GlobalKey` + `toImageSync` 在 `addPostFrameCallback` 里抓纹理，
/// **只抓一次**、整段动画复用。两个后果：
///
/// 1. 显示的是动画开始那一刻的**冻结画面**，
///    组件内容（比如被 slider 驱动的进度值）在动画期间不更新，
///    结束时才跳到最新值——用户描述的「一顿一顿」正是这个；
/// 2. 子组件自己的动画（如进度条的波浪边界）全被冻结的纹理盖住，
///    等于没做。
///
/// 每帧重抓又不能走 setState：那会变成
/// 「抓取 → setState → 重建 → 再抓取」的死循环。
///
/// 正解是在**绘制阶段**抓：把子树画进一个离屏 `OffsetLayer`，
/// 同步转成图像，再用着色器画出来。全程在 `paint()` 内完成，
/// 不触发布局与重建，内容永远是最新的。
class RippleShaderView extends StatelessWidget {
  final Widget child;
  final double progress;
  final double intensity;
  final Color tint;

  const RippleShaderView({
    super.key,
    required this.child,
    required this.progress,
    required this.intensity,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    // 着色器未就绪时原样显示，不崩溃也不让组件消失。
    //
    // 加载是异步的，但动画本身每帧都在重建这棵子树，
    // 因此加载完成后的下一帧会自动切到着色器分支，
    // 不需要额外的 setState。
    if (!RippleShaderLoader.isReady) {
      RippleShaderLoader.ensureLoaded();
      return child;
    }

    return _ShaderSampler(
      progress: progress,
      intensity: intensity,
      tint: tint,
      child: child,
    );
  }
}

/// 把子树采样成纹理并交给着色器绘制。
class _ShaderSampler extends SingleChildRenderObjectWidget {
  final double progress;
  final double intensity;
  final Color tint;

  const _ShaderSampler({
    required this.progress,
    required this.intensity,
    required this.tint,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderShaderSampler(
      progress: progress,
      intensity: intensity,
      tint: tint,
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShaderSampler renderObject,
  ) {
    renderObject
      ..progress = progress
      ..intensity = intensity
      ..tint = tint
      ..devicePixelRatio =
          MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
  }
}

/// 可访问受保护成员的绘制上下文。
///
/// `stopRecordingIfNeeded` 是 `@protected` 的，
/// 通过子类调用才不会触发分析告警。
class _CaptureContext extends PaintingContext {
  _CaptureContext(super.containerLayer, super.estimatedBounds);

  void finishRecording() => stopRecordingIfNeeded();
}

class _RenderShaderSampler extends RenderProxyBox {
  _RenderShaderSampler({
    required double progress,
    required double intensity,
    required Color tint,
    required double devicePixelRatio,
  })  : _progress = progress,
        _intensity = intensity,
        _tint = tint,
        _devicePixelRatio = devicePixelRatio;

  double _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsPaint();
  }

  double _intensity;
  set intensity(double value) {
    if (_intensity == value) return;
    _intensity = value;
    markNeedsPaint();
  }

  Color _tint;
  set tint(Color value) {
    if (_tint == value) return;
    _tint = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final LayerHandle<OffsetLayer> _layerHandle = LayerHandle<OffsetLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final target = child;
    if (target == null || size.isEmpty) return;

    final shader = RippleShaderLoader.createShader();
    if (shader == null) {
      // 着色器不可用就原样画出子树，绝不让组件消失。
      super.paint(context, offset);
      return;
    }

    // 把子树画进离屏图层。每帧都做，因此内容始终是最新的。
    final layer = _layerHandle.layer ??= OffsetLayer();
    layer.removeAllChildren();
    final childContext = _CaptureContext(layer, Offset.zero & size);
    super.paint(childContext, Offset.zero);
    childContext.finishRecording();

    ui.Image? image;
    try {
      image = layer.toImageSync(
        Offset.zero & size,
        pixelRatio: _devicePixelRatio,
      );
    } catch (_) {
      super.paint(context, offset);
      shader.dispose();
      return;
    }

    // 纵向压缩：仅在极扁组件上轻微收一点，下限 0.55。
    // 完全跟随长宽比会让波纹退化成扁线。
    final aspect = size.height / size.width;
    final squash =
        aspect >= 1.0 ? 1.0 : (0.55 + 0.45 * aspect).clamp(0.55, 1.0);

    // ⚠️ 索引顺序必须与 .frag 里的 uniform 声明顺序完全一致。
    // 错位不会报错，只会画出莫名其妙的结果。
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _progress.clamp(0.0, 1.0))
      ..setFloat(3, _intensity.clamp(0.0, 1.0))
      ..setFloat(4, squash)
      ..setFloat(5, _tint.r)
      ..setFloat(6, _tint.g)
      ..setFloat(7, _tint.b)
      ..setFloat(8, _tint.a)
      ..setImageSampler(0, image);

    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();

    image.dispose();
    shader.dispose();
  }

  @override
  void dispose() {
    _layerHandle.layer = null;
    super.dispose();
  }
}

/// 与着色器保持一致的波前函数，供测试与文档参考。
///
/// GLSL 里那份是实际生效的实现；这里复刻一份是为了能在纯 Dart 测试中
/// 校验数学不变量——着色器本身无法在单元测试里运行。
class RippleWaveMath {
  RippleWaveMath._();

  static const double bounces = 2.5;

  static double waveFront(double t, double phaseOffset) {
    final d = t * bounces + phaseOffset;
    final k = d.floor();
    final f = d - k;
    return k.isEven ? f : 1.0 - f;
  }

  /// 与 GLSL 侧保持一致。
  ///
  /// 着色器里用 `step(abs(x), 2.0)` 做无分支截断
  /// （部分 GLSL 后端对函数中途 return 支持参差），
  /// 这里的 early return 在数值上等价。
  static double ringProfile(double dist, double front, double width) {
    final x = (dist - front) / width;
    if (x.abs() > 2.0) return 0.0;
    return math.exp(-3.0 * x * x);
  }

  static double envelope(double t) =>
      math.pow(math.max(1.0 - t, 0.0), 1.2).toDouble();

  static double squashFor(Size size) {
    if (size.width <= 0) return 1.0;
    final aspect = size.height / size.width;
    return aspect >= 1.0 ? 1.0 : (0.55 + 0.45 * aspect).clamp(0.55, 1.0);
  }
}
