import 'package:flutter/material.dart';

import '../theme/app_theme_tokens.dart';

/// 主页进入其他页面的统一转场。
///
/// 设计依据 `HOMEPAGE_UI_DESIGN_SPEC` / `HOMEPAGE_BLUEPRINT` / `UI_FOUNDATION`：
/// - 80%稳定骨架平时安静，只有事件才有张力
/// - 形状语言一致：模块卡 13/6 圆角、角色入口斜切，都要形变到全屏矩形
/// - 支持减少动效，尊重 `MediaQuery.disableAnimationsOf`
/// - 时长：module 380ms / role 520ms，曲线 easeOutCubic
class HomeTransitions {
  static const _moduleDuration = Duration(milliseconds: 440);
  static const _moduleReverseDuration = Duration(milliseconds: 300);
  static const _roleDuration = Duration(milliseconds: 700);
  static const _roleReverseDuration = Duration(milliseconds: 360);

  /// 模块轨道 -> 资产库（角色/世界书/背景/UI模组）
  ///
  /// 以被点击的 ModuleTile 为起点，形变扩张到全屏。
  /// 若 [sourceKey] 取不到 Rect（首帧未布局等），降级为淡入。
  static Route<T> module<T>({
    required BuildContext context,
    required GlobalKey? sourceKey,
    required Widget page,
    required Color accent,
  }) {
    if (MediaQuery.disableAnimationsOf(context) || sourceKey == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }

    final tokens = AppThemeTokens.of(context);
    return PageRouteBuilder<T>(
      transitionDuration: _moduleDuration,
      reverseTransitionDuration: _moduleReverseDuration,
      opaque: true,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      pageBuilder: (ctx, _, secondaryAnimation) => page,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        // 目标页：延迟淡入，让扩张卡片先充分展示（解决“打开不明显”）
        // 打开时 0-28% 卡片独自扩张，页面才开始淡入；关闭时页面保持到 62% 才开始淡出
        final pageFade = FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(0.0, 0.72, curve: Curves.easeInCubic),
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
              reverseCurve: const Interval(0.0, 0.72, curve: Curves.easeInCubic),
            )),
            child: child,
          ),
        );

        final renderObject = sourceKey.currentContext?.findRenderObject();
        Rect? sourceRect;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final offset = renderObject.localToGlobal(Offset.zero);
          sourceRect = offset & renderObject.size;
        }

        if (sourceRect == null) {
          return pageFade;
        }

        // 扩张蒙层：在 page 之上，从 Tile 位置形变到全屏。
        // pop 时反向：从全屏收缩回 Tile，同时 page 淡出。
        return Stack(
          clipBehavior: Clip.none,
          children: [
            pageFade,
            AnimatedBuilder(
              animation: curved,
              builder: (ctx2, _) {
                final t = curved.value;
                // 完全展开/完全收起时不绘制，避免盖住最终画面。
                if (t > 0.97 && animation.status == AnimationStatus.completed) {
                  return const SizedBox.shrink();
                }
                if (t < 0.02 && animation.status == AnimationStatus.dismissed) {
                  return const SizedBox.shrink();
                }
                // 扩张卡片保持到 96% 再消失，之前过早隐藏导致“打开不明显”
                if (t > 0.96) {
                  return const SizedBox.shrink();
                }

                final screenSize = MediaQuery.of(ctx2).size;
                final fullRect = Offset.zero & screenSize;
                // 按压回弹：0-16% 内缩到 0.94，17-28% 回弹到 1.0，之后保持 1.0
                // 原 0.035 太轻看不见，现在 0.06 更有“摁下去”的反馈
                double pressScale = 1.0;
                if (t < 0.16) {
                  pressScale = 1 - (t / 0.16) * 0.06;
                } else if (t < 0.28) {
                  final r = (t - 0.16) / 0.12;
                  pressScale = 0.94 + 0.06 * Curves.easeOutBack.transform(r);
                }
                final rect = Rect.lerp(sourceRect!, fullRect, t)!;

                // 圆角 13/6 -> 0，前 55% 保持圆角，后 45% 快速抹平，形变更有节奏
                final radiusT = (t < 0.55 ? 0.0 : (t - 0.55) / 0.45).clamp(0.0, 1.0);
                const beginRadius = BorderRadius.only(
                  topLeft: Radius.circular(13),
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(13),
                  bottomLeft: Radius.circular(6),
                );
                final radius = BorderRadius.lerp(beginRadius, BorderRadius.zero, radiusT)!;

                // 扩张卡片保持不透明到 62% 再快速淡出，解决“打开不明显”
                // 之前 (1-t) 在 t=0.5 就半透明，扩张过程被页面盖住
                final overlayOpacity = t < 0.62
                    ? 1.0
                    : (1 - (t - 0.62) / 0.38).clamp(0.0, 1.0);
                // 避免在 pop 初期闪现：pop 时 t=1->0，overlayOpacity 0->1 正好反向淡入
                // 这里保持同样的逻辑，pop 时会从透明渐现再收缩，符合预期。

                return Positioned.fromRect(
                  rect: rect,
                  child: Transform.scale(
                    scale: pressScale,
                    alignment: Alignment.center,
                    child: Opacity(
                      opacity: overlayOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: radius,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.55 * (1 - t * 0.3)),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color.fromRGBO(48, 60, 84, 1)
                                  .withValues(alpha: 0.07 * (1 - t)),
                              offset: const Offset(5, 6),
                              blurRadius: 12 * (1 - t) + 2,
                            ),
                            BoxShadow(
                              color: accent.withValues(alpha: 0.18 * (1 - t)),
                              blurRadius: 14 * t,
                              spreadRadius: 1 * t,
                            ),
                          ],
                        ),
                      child: ClipRRect(
                        borderRadius: radius,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 顶部象征性内容：图标占位 + 标题，跟真实 Tile 保持语义一致但不强求像素精确
                            // 用 accent 色的极淡底 + 底部分隔线，足以让用户感知“这张卡在变大”
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.06 * (1 - t * 0.5)),
                                ),
                              ),
                            ),
                            // 底部分隔线，随扩张渐隐
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 10,
                              child: Opacity(
                                opacity: (1 - t * 1.2).clamp(0.0, 1.0),
                                child: Container(
                                  height: 1,
                                  color: accent.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                            // 中心高光，随扩张消失
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: const Alignment(0.2, -0.3),
                                      radius: 0.9,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.08 * (1 - t)),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// 角色入口 -> 聊天（Stage Enter）
  ///
  /// 对齐 HTML `screen.experience-entering`：角色色面扩张 + Avatar/Module 淡出。
  /// 这里用 Overlay 的斜切形变来模拟，避免改动 ChatPage 本身。
  static Route<T> role<T>({
    required BuildContext context,
    required GlobalKey? sourceKey,
    required Widget page,
  }) {
    if (MediaQuery.disableAnimationsOf(context) || sourceKey == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }

    final tokens = AppThemeTokens.of(context);
    return PageRouteBuilder<T>(
      transitionDuration: _roleDuration,
      reverseTransitionDuration: _roleReverseDuration,
      opaque: true,
      pageBuilder: (ctx, _, secondaryAnimation) => page,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final pageFade = FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.32, 1.0, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(0.0, 0.68, curve: Curves.easeInCubic),
          ),
          child: child,
        );

        final renderObject = sourceKey.currentContext?.findRenderObject();
        Rect? sourceRect;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final offset = renderObject.localToGlobal(Offset.zero);
          sourceRect = offset & renderObject.size;
        }

        if (sourceRect == null) {
          return pageFade;
        }

        return Stack(
          children: [
            pageFade,
            AnimatedBuilder(
              animation: curved,
              builder: (ctx2, _) {
                final t = curved.value;
                if (t > 0.97 && animation.status == AnimationStatus.completed) {
                  return const SizedBox.shrink();
                }
                if (t < 0.02 && animation.status == AnimationStatus.dismissed) {
                  return const SizedBox.shrink();
                }
                // 扩张卡片保持到 96% 再消失，之前 0.88 过早隐藏
                if (t > 0.96) {
                  return const SizedBox.shrink();
                }

                final screenSize = MediaQuery.of(ctx2).size;
                final fullRect = Offset.zero & screenSize;
                // 角色卡扩张路径：不是线性到全屏，而是带一点过冲的舞台感
                // 前 70% 快速扩张到 1.06 倍，后 30% 回弹到 1.0
                double expansionT = Curves.easeOutCubic.transform(t);
                // 轻微过冲：0.7 时达到 1.06，最后回到 1.0
                if (t < 0.7) {
                  expansionT = t / 0.7 * 1.06;
                } else {
                  final rest = (t - 0.7) / 0.3;
                  expansionT = 1.06 - 0.06 * Curves.easeOutBack.transform(rest);
                }
                expansionT = expansionT.clamp(0.0, 1.06);

                final rect = Rect.lerp(sourceRect!, fullRect, expansionT)!;

                // 斜切 -> 矩形的插值
                final clipT = t;

                // 保持不透明到 68% 再快速淡出，之前 0.65 过早
                final opacity = t < 0.68 ? 1.0 : (1 - (t - 0.68) / 0.32).clamp(0.0, 1.0);

                return Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: opacity,
                    child: ClipPath(
                      clipper: _SlantedToRectClipper(progress: clipT),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [tokens.accent, tokens.accentStrong],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 复刻角色入口的渐变蒙层
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: const Alignment(-1, -0.55),
                                  end: const Alignment(1, 0.55),
                                  colors: [
                                    tokens.accentStrong.withValues(alpha: 0.88 * (1 - t * 0.4)),
                                    tokens.accentStrong.withValues(alpha: 0.30 * (1 - t * 0.5)),
                                    Colors.black.withValues(alpha: 0.50 * (1 - t * 0.3)),
                                  ],
                                  stops: const [0.0, 0.58, 1.0],
                                ),
                              ),
                            ),
                            // 同心环，随扩张淡出
                            Opacity(
                              opacity: (1 - t * 1.5).clamp(0.0, 1.0),
                              child: CustomPaint(
                                painter: _ConcentricRingsForTransition(
                                  ringColor: Colors.white.withValues(alpha: 1.0),
                                ),
                              ),
                            ),
                            // 亮度闪光：扩张中段提亮
                            Opacity(
                              opacity: (t < 0.5 ? t / 0.5 * 0.14 : (1 - (t - 0.5) / 0.5) * 0.14)
                                  .clamp(0.0, 0.14),
                              child: Container(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// 斜切面 -> 矩形的插值 Clipper
///
/// 斜切 5 点（来自 _SlantedSurfaceClipper）：
/// (0,0) -> (0.94w,0) -> (1w,0.12h) -> (0.92w,1h) -> (0.02w,0.94h)
/// 矩形 5 点（补一个重复点保持点数一致）：
/// (0,0) -> (1w,0) -> (1w,1h) -> (0,1h) -> (0,1h)
class _SlantedToRectClipper extends CustomClipper<Path> {
  _SlantedToRectClipper({required this.progress});

  final double progress;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    // 起点斜切
    final slanted = <Offset>[
      Offset(0, 0),
      Offset(w * 0.94, 0),
      Offset(w, h * 0.12),
      Offset(w * 0.92, h),
      Offset(w * 0.02, h * 0.94),
    ];

    // 终点矩形（5点，末点重复以对齐）
    final rect = <Offset>[
      Offset(0, 0),
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
      Offset(0, h),
    ];

    final points = List<Offset>.generate(
      5,
      (i) => Offset.lerp(slanted[i], rect[i], progress)!,
    );

    return Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..lineTo(points[4].dx, points[4].dy)
      ..close();
  }

  @override
  bool shouldReclip(covariant _SlantedToRectClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _ConcentricRingsForTransition extends CustomPainter {
  const _ConcentricRingsForTransition({required this.ringColor});
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 107, 22);
    void ring(double radius, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ringColor.withValues(alpha: alpha),
      );
    }
    ring(86, 0.17);
    ring(86 + 18, 0.035);
    ring(86 + 42, 0.025);
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsForTransition oldDelegate) =>
      oldDelegate.ringColor != ringColor;
}
