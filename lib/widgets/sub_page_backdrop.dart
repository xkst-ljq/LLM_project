import 'dart:ui';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';

/// 子页面通用磨砂背景（供 世界书/背景/角色库等二级页面复用）。
///
/// 设计上与主页的 `HomeBackground` 保持同源：canvas + canvasDeep + 极淡的 stage 光晕，
/// 但更轻量，不包含对角线/椭圆轨道，避免抢夺列表内容焦点。
/// 若调用方不传 [child]，则仅作为背景层使用。
class SubPageBackdrop extends StatelessWidget {
  const SubPageBackdrop({
    super.key,
    this.child,
    this.showStageGlow = true,
  });

  final Widget? child;
  final bool showStageGlow;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: tokens.canvas),
        ),
        if (showStageGlow)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.92, 0.52),
                radius: 0.33,
                colors: [
                  tokens.stage.withValues(alpha: 0.05),
                  tokens.canvas.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tokens.canvas.withValues(alpha: 0.0), tokens.canvasDeep],
              stops: const [0.6, 1.0],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// 带模糊的磨砂变体，用于需要强调层级感的弹窗/底部抽屉背景。
class SubPageBlurBackdrop extends StatelessWidget {
  const SubPageBlurBackdrop({
    super.key,
    required this.child,
    this.blurSigma = 12,
  });

  final Widget child;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusPanel),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surfaceGlass,
            borderRadius: BorderRadius.circular(tokens.radiusPanel),
            border: Border.all(color: tokens.outline.withValues(alpha: 0.6)),
          ),
          child: child,
        ),
      ),
    );
  }
}
