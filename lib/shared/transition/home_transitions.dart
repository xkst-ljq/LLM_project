// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/character_card.dart';
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
    final tokens = AppThemeTokens.of(context);
    Rect? sourceRect;
    if (sourceKey != null) {
      final ro = sourceKey.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final off = ro.localToGlobal(Offset.zero);
        sourceRect = off & ro.size;
      }
    }
    sourceRect ??= Rect.fromLTWH(
      MediaQuery.of(context).size.width / 2 - 60,
      MediaQuery.of(context).size.height / 2 - 40,
      120,
      80,
    );
    // 下面继续走 PageRouteBuilder，不再回退到 MaterialPageRoute
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

        // sourceRect 已在外层计算并兜底，此处直接使用

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

  /// 角色入口 -> 聊天（三段式舞台，带冷调蒙版与外置超细胶囊）
  ///
  /// 时序：180ms 初次等比例放大到中间态 → 玻璃胶囊淡入+三点循环（与
  /// UIEngine 加载并发）→ [readyFuture] 完成后 280ms 全屏扩张。
  /// - 等比中间态：卡片围绕中心放大 1.22 倍（不是拉宽），悬浮在胶囊与
  ///   Avatar Stage 之间的留白，观感是「整张卡在变大」。
  /// - 蒙版：冷调 #0F1A2A 渐现到 ~0.16 + blur 8，缓缓盖住 HomeBackground/
  ///   ModuleRail/Stage。
  /// - 胶囊：跟随卡片矩形同步移动/变宽（top = 卡底 + 12px，left = 卡左 +
  ///   11% 宽，宽 = 卡宽 × 0.78），双层 BackdropFilter 高斯模糊、无描边
  ///   无实色，靠透过下方蒙版/背景的模糊呈现「独立悬浮物」。
  static Route<T> stagedRole<T>({
    required BuildContext context,
    required GlobalKey? sourceKey,
    required CharacterCard character,
    required Widget page,
    required Color accent,
    Future<void>? readyFuture,
  }) {
    if (MediaQuery.disableAnimationsOf(context) || sourceKey == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }

    final tokens = AppThemeTokens.of(context);
    Rect? sourceRect;
    final renderObject = sourceKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final offset = renderObject.localToGlobal(Offset.zero);
      sourceRect = offset & renderObject.size;
    }
    if (sourceRect == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }
    final src = sourceRect;
    final screenSize = MediaQuery.of(context).size;
    final fullRect = Offset.zero & screenSize;
    // 等比中间态：围绕卡片中心放大，并**水平居中**——放大后卡片左/右边缘
    // 离屏幕两边等距，封面图块不再偏右。
    // 原始卡宽 332 → 放大到 396（×1.19），高度同比例，绝不再把卡片拉宽。
    final scale = (396.0 / src.width).clamp(1.0, 1.35);
    final intW = src.width * scale;
    final intH = src.height * scale;
    final intLeft = (screenSize.width - intW) / 2;
    // 垂直：围绕源中心，再上移一点，给下方胶囊留出空间。
    final intTop = (src.center.dy - intH / 2).clamp(40.0, src.top);
    final intermediateRect = Rect.fromLTWH(intLeft, intTop, intW, intH);

    // 路由时长必须覆盖「保底 hold + 收尾」全程：路由动画完成后 Overlay 会把
    // 这条路由标记为 opaque，主页随即进入 offstage 不再构建（routes.dart 的
    // _handleStatusChanged）。若路由先于收尾完成，卡片四周（还没铺满屏幕）
    // 露出的将是 Overlay 底层的黑画布，即用户看到的黑屏。
    // 保底 hold 1400ms + 收尾 360ms，路由给 1900ms：收尾完成后主页才被卸载，
    // 全程「卡片 → 全屏」无缝衔接，不再有黑屏窗口。
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 1900),
      reverseTransitionDuration: _roleReverseDuration,
      opaque: true,
      pageBuilder: (ctx, _, secondaryAnimation) => page,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        return _StagedRoleTransition(
          animation: animation,
          sourceRect: src,
          intermediateRect: intermediateRect,
          fullRect: fullRect,
          character: character,
          tokens: tokens,
          accent: accent,
          readyFuture: readyFuture,
          child: child,
        );
      },
    );
  }
/// 角色库卡片 -> 聊天（简化直放转场）
  ///
  /// 与 `stagedRole` 的区别：
  /// - 不套用主页「accent 渐变 + 同心环」封面，直接用**角色卡真实封面图**；
  /// - 不引入「中间态居中悬停卡片 + 底部加载胶囊」，卡片从它在角色库里的
  ///   自身位置直接放大到全屏；
  /// - 仍保留 `readyFuture` 等待：UIEngine 就绪前卡片放大到中段暂停，
  ///   就绪后才铺满全屏 + 页面淡入，避免加载卡顿/白屏。
  static Route<T> cardToChat<T>({
    required BuildContext context,
    required GlobalKey? sourceKey,
    required CharacterCard character,
    required Widget page,
    required Color accent,
    Future<void>? readyFuture,
  }) {
    if (MediaQuery.disableAnimationsOf(context) || sourceKey == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }

    final tokens = AppThemeTokens.of(context);
    Rect? sourceRect;
    final renderObject = sourceKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final offset = renderObject.localToGlobal(Offset.zero);
      sourceRect = offset & renderObject.size;
    }
    if (sourceRect == null) {
      return MaterialPageRoute<T>(builder: (_) => page);
    }
    final src = sourceRect;
    final screenSize = MediaQuery.of(context).size;
    final fullRect = Offset.zero & screenSize;

    return PageRouteBuilder<T>(
      // 路由时长覆盖「保底 hold + 收尾」全程，避免收尾前主页被卸载露黑底。
      transitionDuration: const Duration(milliseconds: 1900),
      reverseTransitionDuration: const Duration(milliseconds: 360),
      opaque: true,
      pageBuilder: (ctx, _, secondaryAnimation) => page,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        return _CardExpandTransition(
          animation: animation,
          sourceRect: src,
          fullRect: fullRect,
          character: character,
          tokens: tokens,
          accent: accent,
          readyFuture: readyFuture,
          child: child,
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


class _StagedRoleTransition extends StatefulWidget {
  const _StagedRoleTransition({
    required this.animation,
    required this.sourceRect,
    required this.intermediateRect,
    required this.fullRect,
    required this.character,
    required this.tokens,
    required this.accent,
    required this.child,
    this.readyFuture,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Rect intermediateRect;
  final Rect fullRect;
  final CharacterCard character;
  final AppThemeTokens tokens;
  final Color accent;
  final Widget child;

  /// 聊天页 UIEngine 就绪信号：完成后收尾做全屏扩张。
  final Future<void>? readyFuture;

  @override
  State<_StagedRoleTransition> createState() => _StagedRoleTransitionState();
}

/// 转场扩张卡的忠实内容：真实封面图 + 渐变蒙层 + 同心环，复刻主页角色卡。
///
/// 合成纯色块的问题是「封面消失只剩一个色块」——这里直接用真实卡片素材，
/// 放大过程中封面始终在，观感与主页角色卡完全一致。
class _StagedRoleCardBody extends StatelessWidget {
  const _StagedRoleCardBody({
    required this.character,
    required this.tokens,
    required this.accent,
    required this.opacity,
  });

  final CharacterCard character;
  final AppThemeTokens tokens;
  final Color accent;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final path = character.cardImagePath;
    final hasImage = path.isNotEmpty && File(path).existsSync();
    final cover = hasImage
        ? Image.file(File(path), fit: BoxFit.cover)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.accent, tokens.accentStrong],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );

    return Opacity(
      opacity: opacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: cover),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -0.55),
                  end: const Alignment(1, 0.55),
                  colors: [
                    accent.withValues(alpha: 0.88),
                    accent.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.50),
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConcentricRingsForTransition(
                  ringColor: Colors.white.withValues(alpha: 1.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StagedRoleTransitionState extends State<_StagedRoleTransition>
    with TickerProviderStateMixin {
  late final AnimationController _stageController;
  late final AnimationController _dotsController;
  bool _readyDone = false;
  bool _minHoldDone = false;
  // 是否正在反向（pop 返回主页）：决定卡片是收缩回角色入口还是全屏铺开。
  bool _isReversing = false;

  @override
  void initState() {
    super.initState();
    _stageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    if (widget.readyFuture != null) {
      widget.readyFuture!.whenComplete(() {
        if (mounted) setState(() => _readyDone = true);
        _tryFinish();
      });
    } else {
      _readyDone = true;
    }

    // 保底：UIEngine 再快也要在中间态停够一瞬，保证「放大→胶囊→全屏」
    // 三段节奏完整。1.4s 内 ready 都会等它走完再收尾。
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _minHoldDone = true);
        _tryFinish();
      }
    });

    // 预放大入场：easeOutBack 轻微过冲，先快速放大再回落定住，像「弹起」。
    _stageController.animateTo(0.257,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack);

    // 反向（pop 返回主页）：把 stage 从 1 拉回 0，让卡片从全屏收缩回
    // 主页角色入口，形成与进场对称的退出动画。否则 stageT 停在 1，
    // 返回时卡片不会收缩，只剩页面淡出——即「退出没有主页动画」。
    widget.animation.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.reverse) {
        _isReversing = true;
        _stageController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInCubic,
        );
      }
    });
  }

  void _tryFinish() {
    if (_readyDone && _minHoldDone && mounted && _stageController.value < 1.0) {
      _stageController.animateTo(1.0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _stageController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
      animation:
          Listenable.merge([widget.animation, _stageController, _dotsController]),
      builder: (context, _) {
        final routeT = curved.value;
        final stageT = _stageController.value;

        Rect cardRect;
        double clipT;
        double cardOpacity;
        if (stageT <= 0.257) {
          // 预放大阶段：只把卡片等比放大，斜切保持主页原样（progress 0），
          // 形状/比例绝不提前改变。
          final a = stageT / 0.257;
          cardRect = Rect.lerp(widget.sourceRect, widget.intermediateRect,
              Curves.easeOutCubic.transform(a))!;
          clipT = 0.0;
          cardOpacity = 1.0;
        } else {
          // 收尾全屏扩张：卡片从中间态放大到全屏，同时斜切抹平为矩形。
          final b = (stageT - 0.257) / 0.743;
          cardRect = Rect.lerp(widget.intermediateRect, widget.fullRect,
              Curves.easeOutCubic.transform(b))!;
          clipT = b * 0.95;
          cardOpacity = 1.0;
        }

        // 收尾十字淡变：卡片淡出的同时页面淡入，两者同步走完，
        // 全程「卡片+页面」不透明度 ≥ 1，杜绝中间露出路由的黑底黑屏。
        final revealT = ((stageT - 0.86) / 0.14).clamp(0.0, 1.0);
        cardOpacity = (1.0 - revealT) * cardOpacity;

        // 蒙版：冷调 #0F1A2A 渐现到 ~0.16 + blur 8。这里盖住的是**主页**——
        // 路由时长被拉长到收尾完成后才结束（见 stagedRole），主页在整个
        // hold + 收尾期间保持 onstage，所以 blur 有真实内容可糊，不会露出
        // Overlay 底层的黑画布。
        final scrimOpacity = stageT < 0.257
            ? stageT / 0.257 * 0.16
            : stageT < 0.86
                ? 0.16
                : 0.16 * (1 - revealT);
        // 胶囊：中间态（stageT 被钉在 0.257）淡入到全亮，收尾全屏时淡出。
        // 用 (stageT - 0.20) 起点：stageT 停在 0.257 时胶囊已经在显现，hold 全程可见。
        final capsuleOpacity = stageT < 0.20
            ? 0.0
            : stageT < 0.40
                ? ((stageT - 0.20) / 0.20).clamp(0.0, 1.0)
                : stageT > 0.92
                    ? (1 - (stageT - 0.92) / 0.08).clamp(0.0, 1.0)
                    : 1.0;
        // 页面淡入被 stage 完成度钳制：即使路由动画已跑完（ready 还没到），
        // 页面也保持隐藏，卡片 + 胶囊 + 蒙版继续盖住，直到 UIEngine 真正
        // 就绪、最终全屏扩张时才放页面出来。pop 时仍跟路由反向淡出。
        final routeFade =
            routeT < 0.32 ? 0.0 : ((routeT - 0.32) / 0.68).clamp(0.0, 1.0);
        final pageOpacity = math.min(routeFade, revealT);

        // 胶囊跟随当前卡片矩形等比移动/变宽：同一平面一起放大。
        final capsuleHeight = 32.0;
        final capsuleLeft = cardRect.left + cardRect.width * 0.11;
        final capsuleTop = cardRect.bottom + 12;
        final capsuleWidth = cardRect.width * 0.78;

        return Stack(
          children: [
            Opacity(opacity: pageOpacity, child: widget.child),
            if (scrimOpacity > 0.005)
              Positioned.fill(
                child: IgnorePointer(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                        color:
                            const Color(0xFF0F1A2A).withValues(alpha: scrimOpacity)),
                  ),
                ),
              ),
            if (cardOpacity > 0.01)
              Positioned.fromRect(
                rect: cardRect,
                child: Opacity(
                  opacity: cardOpacity,
                  child: ClipPath(
                    clipper: _SlantedToRectClipper(progress: clipT),
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: _StagedRoleCardBody(
                          character: widget.character,
                          tokens: widget.tokens,
                          accent: widget.accent,
                          opacity: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 外置悬浮玻璃胶囊：无描边无实色，双层 BackdropFilter 高斯模糊，
            // 靠透过下方蒙版/背景的模糊呈现「独立悬浮物」。
            // 反向（pop 返回）时不显示胶囊。
            if (!_isReversing && capsuleOpacity > 0.01 && capsuleWidth > 60)
              Positioned(
                left: capsuleLeft,
                top: capsuleTop,
                width: capsuleWidth,
                height: capsuleHeight,
                child: Opacity(
                  opacity: capsuleOpacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              color: widget.tokens.surfaceGlass
                                  .withValues(alpha: 0.30),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: Container(
                              color: widget.tokens.surface.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: _StagedDotsTrack(
                            dotsController: _dotsController,
                            accent: widget.accent,
                          ),
                        ),
                      ],
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

class _StagedDotsTrack extends StatelessWidget {
  const _StagedDotsTrack({required this.dotsController, required this.accent});
  final AnimationController dotsController;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const iconSize = 10.0;
        const dotSize = 4.0;
        final trackLeft = iconSize + 8;
        final trackRight = iconSize + 8;
        final trackWidth = w - trackLeft - trackRight;
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: trackLeft,
              right: trackRight,
              child: Container(height: 1.5, color: accent.withValues(alpha: 0.22)),
            ),
            Positioned(
              left: 6,
              child: Icon(Icons.play_arrow_rounded, size: 12, color: accent.withValues(alpha: 0.72)),
            ),
            Positioned(
              right: 6,
              child: Icon(Icons.person_rounded, size: 12, color: accent.withValues(alpha: 0.72)),
            ),
            AnimatedBuilder(
              animation: dotsController,
              builder: (context, _) {
                final cycle = dotsController.value;
                double cycleT;
                if (cycle < 0.845) {
                  cycleT = cycle / 0.845;
                } else {
                  return const SizedBox.shrink();
                }
                return Stack(
                  children: List.generate(3, (i) {
                    final startOffset = i * 0.074;
                    final localT = (cycleT - startOffset).clamp(0.0, 1.0);
                    if (localT <= 0 || localT >= 1) {
                      return const SizedBox.shrink();
                    }
                    final posT = Curves.easeInOutCubic.transform(localT);
                    final x = trackLeft + posT * trackWidth;
                    final scale = 1.0 + 0.28 * (1 - (posT - 0.5).abs() * 2).clamp(0.0, 1.0);
                    final alpha = 0.62 + 0.13 * (1 - (posT - 0.5).abs() * 2).clamp(0.0, 1.0);
                    return Positioned(
                      left: x - dotSize / 2,
                      top: h / 2 - dotSize / 2,
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: dotSize,
                          height: dotSize,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: alpha),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.18),
                                blurRadius: 4,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        );
      },
    );
  }
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

/// 角色卡直放转场：卡片从自身位置放大到全屏，过程中始终显示角色卡封面。
class _CardExpandTransition extends StatefulWidget {
  const _CardExpandTransition({
    required this.animation,
    required this.sourceRect,
    required this.fullRect,
    required this.character,
    required this.tokens,
    required this.accent,
    required this.child,
    this.readyFuture,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Rect fullRect;
  final CharacterCard character;
  final AppThemeTokens tokens;
  final Color accent;
  final Widget child;
  final Future<void>? readyFuture;

  @override
  State<_CardExpandTransition> createState() => _CardExpandTransitionState();
}

class _CardExpandTransitionState extends State<_CardExpandTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stageController;
  bool _readyDone = false;
  bool _minHoldDone = false;

  @override
  void initState() {
    super.initState();
    _stageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    if (widget.readyFuture != null) {
      widget.readyFuture!.whenComplete(() {
        if (mounted) setState(() => _readyDone = true);
        _tryFinish();
      });
    } else {
      _readyDone = true;
    }

    // 极短保底：只为兜底 ready 永不回调的异常，正常路径下放大由 ready 触发。
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _minHoldDone = true);
        _tryFinish();
      }
    });
  }

  void _tryFinish() {
    // 等 UIEngine 就绪后再开始**一次连续放大**到满屏：
    // 放大动画本身是唯一的运动，中途不停驻；放大末期同步淡化，聊天页随之显现。
    if (_readyDone && _minHoldDone && mounted && _stageController.value < 1.0) {
      // 等 UIEngine 就绪后再开始**一次连续放大**到满屏：
      // 放大动画本身是唯一的运动，中途不停驻；放大末期同步淡化，聊天页随之显现。
      _stageController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _stageController.dispose();
    super.dispose();
  }

  Widget _buildCardBody() {
    final path = widget.character.cardImagePath;
    final hasImage = path.isNotEmpty && File(path).existsSync();
    return hasImage
        ? Image.file(File(path), fit: BoxFit.cover)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.accent, widget.accent.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _stageController]),
      builder: (context, _) {
        final routeT = curved.value;
        final stageT = _stageController.value;

        // 卡片从自身位置直接放大到全屏（不经过居中悬停中间态）。
        final cardRect = Rect.lerp(
          widget.sourceRect,
          widget.fullRect,
          Curves.easeInOutCubic.transform(stageT),
        )!;

        // 圆角从卡片圆角抹平到 0。
        final radius = BorderRadius.circular(
          14 * (1 - stageT).clamp(0.0, 1.0),
        );

        // 就绪后卡片淡出、页面淡入，两者同步，杜绝黑底。
        // 淡化只在放大几乎到底的最后一段（stageT 0.95 → 1.0）发生：
        // 放大到满屏的瞬间才淡出，聊天页随之显现，终点过渡很短。
        final revealT = ((stageT - 0.95) / 0.05).clamp(0.0, 1.0);
        final cardOpacity = (1.0 - revealT).clamp(0.0, 1.0);
        final pageOpacity = math.min(
          routeT < 0.32 ? 0.0 : ((routeT - 0.32) / 0.68).clamp(0.0, 1.0),
          revealT,
        );

        return Stack(
          children: [
            Opacity(opacity: pageOpacity, child: widget.child),
            if (cardOpacity > 0.01)
              Positioned.fromRect(
                rect: cardRect,
                child: Opacity(
                  opacity: cardOpacity,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: _buildCardBody(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
