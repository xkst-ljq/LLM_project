import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// RenderRepaintBoundary / RenderObject 由 rendering.dart 导出，
// material.dart 并不转出它们。
import 'package:flutter/rendering.dart';

/// 水波折射：网格变形实现（方案 C）。
///
/// ## 为什么不是「盖一个白圈」
///
/// 旧实现是 `Center` + 一个圆形 `Container`，被 `ClipRRect` 裁在组件里。
/// 用户评价「很敷衍」——因为它模拟的是波的**轮廓**，
/// 而组件本身纹丝不动，缺少「介质被扰动」的感觉。
/// 而且进度条 200×12 时，直径 300px 的圆只剩中间一条 12px 高的窄带，
/// 表现为「只有中点很小一部分有动画」。
///
/// 真实水波的视觉本质是**折射**：水面起伏改变光路，让水下的东西位移扭曲。
/// 这里把组件抓成纹理、切成网格，按波函数扰动顶点位置（UV 保持不动），
/// 采样区域随之被拉伸——这就是放大镜/透镜效应。
///
/// ## 关键设计
///
/// **椭圆归一化距离**：`d = √((dx/(w/2))² + (dy/(h/2))²)`，
/// 组件边界恒为 1.0，与长宽比无关。波沿这个度量传播，
/// 扁长组件也能沿长轴扫满，根治「只有中点一小块」。
///
/// **位移基准取「该方向上的实际半径」**而非 `min(w, h)`：
/// 用短边当基准时，进度条横向位移只有 0.4px（实测），完全看不出来。
/// 改为按方向取半径后横向 6~7px、纵向 2~3px，量级合理且自适应形状。
/// 粒子动画此前也栽在同一个坑上（用了 `shortestSide`）。
class RippleMeshDistortion {
  const RippleMeshDistortion._();

  /// 网格密度。
  ///
  /// 首版用 32×6，实测折射看不出来。原因是环带要窄才像「一圈环扫过」，
  /// 而窄环带跨越的顶点太少，波形被采样成折线。
  /// 64×8 时环带能跨约 26 列，跳变/峰值 ≈ 0.37，既锐利又平滑。
  static const int cols = 64;
  static const int rows = 8;

  /// 环带宽度（归一化距离单位）。
  ///
  /// ⚠️ 首版取 0.6，是「看不出水波、只觉得在抖」的主因之一：
  /// 波前在 0.5 时影响范围是 -0.1~1.1，**整个组件都在环带内**，
  /// 表现为整体缓慢起伏而非一圈环扫过。
  /// 0.4 时环带只占组件的一段，才有波纹推进的观感。
  static const double ringWidth = 0.4;

  /// 波在组件内来回反弹的次数。
  ///
  /// 2.5 = 外行 → 撞壁 → 回弹 → 再外行，撞壁发生在 t≈0.42。
  /// 用户要求「像波浪一样碰到壁面会反弹」，这是瞬时事件的典型手感。
  static const double bounces = 2.5;

  /// 生成的顶点总数。
  ///
  /// 每个网格单元 2 个三角形、每个三角形 3 个顶点。
  /// `ui.Vertices` 构造后不暴露顶点数，测试与性能评估都要靠这个常量。
  static const int vertexCount = cols * rows * 6;

  /// 位移强度上限（相对该方向半径的比例）。
  ///
  /// 首版 0.12 时折射峰值只有 4.7px，而同期本体形变让整个组件
  /// 横向移动 9.2px——**全局运动压过局部扭曲**，
  /// 眼睛只看得到「整体在抖」，这是用户反馈的直接原因。
  /// 提到 0.28 后折射峰值约 10.6px，成为视觉主角。
  static const double maxStrength = 0.28;

  /// 波前位置：在 [0,1] 之间折返行进。
  ///
  /// 撞到边界（1.0）后原路弹回，回到中心（0.0）再次外行。
  /// 这比「三角波让圆环忽大忽小」更像真实反射——
  /// 后者看起来是圆环在呼吸，不是波在传播。
  static double waveFront(double t) {
    final d = t * bounces;
    final k = d.floor();
    final f = d - k;
    return k.isEven ? f : 1.0 - f;
  }

  /// 环带剖面：波前处为 0，内侧正、外侧负。
  ///
  /// ⚠️ 这个函数的形式很关键。最初写成 `cos²(πx/2) × sign(x)`，
  /// 在 x=0 处会从 -1 直接跳到 +1，**2.0 的阶跃**——
  /// 表现为波前处图像撕裂，且加密网格反而更明显。
  /// 改用 `-sin(πx)·cos²(πx/2)` 后 x=0 处连续过零，两侧自然反向，
  /// 这才是透镜的「内推外拉」。
  static double ringProfile(double distance, double front) {
    final x = (distance - front) / ringWidth;
    if (x.abs() > 1.0) return 0.0;
    final c = math.cos(x * math.pi / 2);
    return -math.sin(x * math.pi) * c * c;
  }

  /// 衰减包络：越到后面波越平息。
  ///
  /// 指数从 1.5 降到 1.2：1.5 衰减太快，波还没扫到边缘就没劲了。
  static double damping(double t) =>
      math.pow(1.0 - t.clamp(0.0, 1.0), 1.2).toDouble();

  /// 构建变形后的顶点。
  ///
  /// UV **保持原样不动**，只移动顶点位置——采样区域因此被拉伸，
  /// 视觉上就是折射。若同时移动 UV 反而会抵消掉这个效果。
  static ui.Vertices buildVertices({
    required Size size,
    required double progress,
    required double intensity,
  }) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final halfW = math.max(w / 2, 0.0001);
    final halfH = math.max(h / 2, 0.0001);

    final front = waveFront(progress);
    final amp = maxStrength * intensity.clamp(0.0, 1.0) * damping(progress);

    // 先算出每个网格点变形后的位置，再拼三角形。
    final grid = List.generate(
      rows + 1,
      (r) => List<Offset>.filled(cols + 1, Offset.zero),
    );

    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        final x = w * c / cols;
        final y = h * r / rows;

        // 边界顶点钉死：一旦移动，组件会露出没有纹理的边。
        final onEdge = r == 0 || r == rows || c == 0 || c == cols;
        if (onEdge) {
          grid[r][c] = Offset(x, y);
          continue;
        }

        final ndx = (x - cx) / halfW;
        final ndy = (y - cy) / halfH;
        final d = math.sqrt(ndx * ndx + ndy * ndy);
        if (d < 1e-6) {
          grid[r][c] = Offset(x, y);
          continue;
        }

        final profile = ringProfile(d, front);
        if (profile == 0.0) {
          grid[r][c] = Offset(x, y);
          continue;
        }

        // 归一化空间里的单位方向。
        final ux = ndx / d;
        final uy = ndy / d;
        // 该方向上的实际半径——扁长组件沿长轴位移大、沿短轴位移小，
        // 这样波看起来是贴着组件形状传播的。
        final radius = math.sqrt(
          (ux * halfW) * (ux * halfW) + (uy * halfH) * (uy * halfH),
        );
        final shift = profile * amp * radius;

        grid[r][c] = Offset(
          (x + ux * shift).clamp(0.0, w),
          (y + uy * shift).clamp(0.0, h),
        );
      }
    }

    // 每个网格单元两个三角形。
    final positions = Float32List(vertexCount * 2);
    final texCoords = Float32List(vertexCount * 2);
    var i = 0;

    void put(int r, int c) {
      final p = grid[r][c];
      positions[i] = p.dx;
      positions[i + 1] = p.dy;
      // UV 用**未变形**的原始网格坐标。
      texCoords[i] = w * c / cols;
      texCoords[i + 1] = h * r / rows;
      i += 2;
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        put(r, c);
        put(r, c + 1);
        put(r + 1, c);
        put(r, c + 1);
        put(r + 1, c + 1);
        put(r + 1, c);
      }
    }

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
    );
  }

  /// 本体形变：横纵反相的非等比缩放。
  ///
  /// 「动荡感」的来源。同相只是整体放大缩小，
  /// **反相**才有被挤压又回弹的果冻感（近似体积守恒）。
  static Matrix4 bodyDistortion(double progress, double intensity) {
    final osc = math.sin(2 * math.pi * bounces * progress);
    // 上限从 9% 降到 3%。
    //
    // 形变是**全局**运动、折射是**局部**扭曲，两者量级相近时
    // 眼睛只会注意到前者——首版 9% 让 200px 宽的组件整体横移 9.2px，
    // 盖过了 4.7px 的折射，用户因此只看到「抖动」。
    // 现在形变退为辅助，只提供轻微的介质回弹感。
    final a = 0.03 * intensity.clamp(0.0, 1.0) * damping(progress);
    final sx = 1.0 + a * osc;
    final sy = 1.0 - a * osc;
    // scale(x, y, z) 已废弃，改用 scaleByDouble（需要第四个 w 分量）。
    return Matrix4.identity()..scaleByDouble(sx, sy, 1.0, 1.0);
  }
}

/// 把子组件抓成纹理并施加水波折射。
///
/// ## 内容冻结的取舍
///
/// `toImageSync()` 抓取的是**某一刻的静态图**，动画期间组件内容不再更新。
/// 对瞬时事件（点击反馈）无感知；但若进度条正被 slider 连续驱动，
/// 波纹持续期间它的填充会停在触发那一刻。
///
/// 因此这里**每帧重抓纹理**（而不是抓一次用到底）：
/// 代价是每帧一次离屏渲染，换来内容始终跟得上。
/// 若性能不足，可改为抓一次缓存——两种取舍都留了开关。
class RippleDistortionView extends StatefulWidget {
  final Widget child;
  final double progress;
  final double intensity;

  /// 是否每帧重抓纹理。false 时抓一次缓存到动画结束。
  final bool refreshTexture;

  const RippleDistortionView({
    super.key,
    required this.child,
    required this.progress,
    required this.intensity,
    this.refreshTexture = true,
  });

  @override
  State<RippleDistortionView> createState() => _RippleDistortionViewState();
}

class _RippleDistortionViewState extends State<RippleDistortionView> {
  final GlobalKey _boundaryKey = GlobalKey();
  ui.Image? _snapshot;

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  /// 抓取当前子树为纹理。
  ///
  /// 必须在布局完成后调用，否则 `RenderRepaintBoundary` 还没有尺寸。
  void _capture() {
    final obj = _boundaryKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return;
    if (obj.debugNeedsPaint) return;
    try {
      final image = obj.toImageSync(pixelRatio: 1.0);
      final old = _snapshot;
      _snapshot = image;
      old?.dispose();
    } catch (_) {
      // 抓取失败就退回原样显示，不要因为一帧异常炸掉整个页面。
    }
  }

  @override
  Widget build(BuildContext context) {
    // 先把原始子树画进 RepaintBoundary（离屏），再用纹理绘制变形结果。
    // 原始子树用 Offstage 隐藏但仍参与布局与绘制，这样才抓得到。
    return Stack(
      children: [
        // 尺寸占位 + 纹理来源。透明度为 0 但仍会绘制。
        Opacity(
          opacity: 0.0,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: _DistortionPainterHost(
            snapshot: _snapshot,
            progress: widget.progress,
            intensity: widget.intensity,
            onNeedCapture: () {
              if (!widget.refreshTexture && _snapshot != null) return;
              _capture();
            },
            fallback: widget.child,
          ),
        ),
      ],
    );
  }
}

/// 负责在每帧绘制前触发抓取，并把纹理交给画笔。
class _DistortionPainterHost extends StatelessWidget {
  final ui.Image? snapshot;
  final double progress;
  final double intensity;
  final VoidCallback onNeedCapture;
  final Widget fallback;

  const _DistortionPainterHost({
    required this.snapshot,
    required this.progress,
    required this.intensity,
    required this.onNeedCapture,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    // 抓取要在本帧绘制结束后进行，否则会撞上「布局期间修改状态」。
    WidgetsBinding.instance.addPostFrameCallback((_) => onNeedCapture());

    final image = snapshot;
    if (image == null) {
      // 首帧还没有纹理，先原样显示，避免闪一下空白。
      return fallback;
    }
    return CustomPaint(
      painter: _RippleMeshPainter(
        image: image,
        progress: progress,
        intensity: intensity,
      ),
    );
  }
}

class _RippleMeshPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final double intensity;

  const _RippleMeshPainter({
    required this.image,
    required this.progress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final vertices = RippleMeshDistortion.buildVertices(
      size: size,
      progress: progress,
      intensity: intensity,
    );

    // 纹理按组件尺寸铺满：抓取时 pixelRatio=1，所以无需额外缩放。
    final matrix = Matrix4.identity().storage;
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        matrix,
      )
      ..filterQuality = FilterQuality.low;

    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  @override
  bool shouldRepaint(covariant _RippleMeshPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        !identical(oldDelegate.image, image);
  }
}
