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
/// 纹理**只在动画开始时抓一次**，整段动画复用。
/// 代价是这 600ms 内组件内容冻结——对瞬时事件（点击反馈）无感知；
/// 换来的是不必每帧离屏渲染，也彻底避开了方案 C 那种
/// 「抓取 → 重绘 → 再抓取」的循环陷阱。
class RippleShaderView extends StatefulWidget {
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
  State<RippleShaderView> createState() => _RippleShaderViewState();
}

class _RippleShaderViewState extends State<RippleShaderView> {
  final GlobalKey _boundaryKey = GlobalKey();
  ui.Image? _snapshot;
  bool _captureScheduled = false;

  @override
  void initState() {
    super.initState();
    RippleShaderLoader.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _scheduleCapture();
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  void _scheduleCapture() {
    if (_captureScheduled || _snapshot != null) return;
    _captureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final obj = _boundaryKey.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary || obj.debugNeedsPaint) {
        // 这一帧还没画完，下一帧再试。
        _captureScheduled = false;
        if (mounted) _scheduleCapture();
        return;
      }
      try {
        final image = obj.toImageSync(
          pixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
        );
        // ⚠️ 必须 setState。方案 C 正是漏了这一步，
        // 纹理抓到了却永远不重绘，等于整个特效没运行。
        if (mounted) {
          setState(() => _snapshot = image);
        } else {
          image.dispose();
        }
      } catch (_) {
        // 抓取失败就一直显示原图，不要炸掉页面。
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final useShader = snapshot != null && RippleShaderLoader.isReady;

    // ⚠️ RepaintBoundary 必须**恒定存在于同一位置**。
    //
    // 曾写成「未就绪时 return RepaintBoundary，就绪后 return CustomPaint」，
    // 两个分支在同一位置是不同的 widget 类型：一旦切换，
    // 原来的 RepaintBoundary 被销毁、GlobalKey 脱离，
    // 下次就再也抓不到纹理了。
    // 这与「手势进行中改变树结构」是同一类陷阱。
    return Stack(
      children: [
        // 纹理来源。
        //
        // ⚠️ 不能用 Offstage（跳过绘制就抓不到图），
        // 也**不能用 Opacity(0)**——Flutter 对全透明子树有优化，
        // 同样可能跳过绘制，导致抓到空图或过期内容，
        // 表现为动画「一顿一顿」。
        //
        // 改用 ShaderMask 之类会更重，这里用最朴素的办法：
        // 让它照常绘制，再用上层的着色器结果完全覆盖。
        // 多画一遍的代价远小于一次离屏抓取。
        RepaintBoundary(
          key: _boundaryKey,
          child: widget.child,
        ),
        if (useShader)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RippleShaderPainter(
                  image: snapshot,
                  progress: widget.progress,
                  intensity: widget.intensity,
                  tint: widget.tint,
                  // 不透明覆盖：底层原图被完全遮住，
                  // 因此不会出现「原图 + 折射图」重影。
                  opaque: true,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RippleShaderPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final double intensity;
  final Color tint;

  /// 是否用不透明方式覆盖底层。
  ///
  /// 底层的原始 child 仍在绘制（不能隐藏，否则抓不到纹理），
  /// 因此这一层必须完全盖住它，否则会看到原图与折射图重影。
  final bool opaque;

  const _RippleShaderPainter({
    required this.image,
    required this.progress,
    required this.intensity,
    required this.tint,
    this.opaque = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = RippleShaderLoader.createShader();
    if (shader == null) return;

    // 纵向压缩：仅在极扁组件上轻微收一点，下限 0.55。
    // 完全跟随长宽比会让波纹退化成扁线（第三版的错误）。
    final aspect = size.height / size.width;
    final squash =
        aspect >= 1.0 ? 1.0 : (0.55 + 0.45 * aspect).clamp(0.55, 1.0);

    // ⚠️ 索引顺序必须与 .frag 里的 uniform 声明顺序完全一致。
    // 错位不会报错，只会画出莫名其妙的结果。
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, progress.clamp(0.0, 1.0))
      ..setFloat(3, intensity.clamp(0.0, 1.0))
      ..setFloat(4, squash)
      ..setFloat(5, tint.r)
      ..setFloat(6, tint.g)
      ..setFloat(7, tint.b)
      ..setFloat(8, tint.a)
      ..setImageSampler(0, image);

    final paint = Paint()..shader = shader;
    if (opaque) {
      // src 模式直接替换目标像素，把下面的原图整块盖掉。
      // 需要先开一个图层，否则会连同背景一起清掉。
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawRect(Offset.zero & size, paint);
      canvas.restore();
    } else {
      canvas.drawRect(Offset.zero & size, paint);
    }
    shader.dispose();
  }

  @override
  bool shouldRepaint(covariant _RippleShaderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.tint != tint ||
        !identical(oldDelegate.image, image);
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
