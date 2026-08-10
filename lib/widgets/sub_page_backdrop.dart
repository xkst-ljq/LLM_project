import 'dart:ui';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';

/// 子页面通用背景（供 世界书/背景/角色库等二级页面复用）。
///
/// 合并了两条线的设计：
/// - Day：`canvas + 极淡 stage 光晕 + canvasDeep` 的轻量磨砂（来自 arena 分支），保持与主页同源
/// - Night：`蓝紫渐变(左上靛蓝→中深蓝→右下紫)` 的氛围层（来自 main 的 5e6a0ba），比纯 canvas 更有冷色调
/// 若不传 [child]，则仅作为背景层使用；兼容 main 分支 `required child` 的调用方。
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
    final isNight = Theme.of(context).brightness == Brightness.dark;

    // Night：使用 main 的蓝紫渐变作为基底，再叠加极淡的 stage 光晕（如果开启）
    // Day：使用 tokens 的 canvas 体系
    if (isNight) {
      final content = child;
      return Stack(
        fit: StackFit.expand,
        children: [
          // 蓝紫氛围层：左上靛蓝 → 中深蓝 → 右下紫（main 5e6a0ba）
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF151B30),
                  Color(0xFF101322),
                  Color(0xFF1D1830),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          if (showStageGlow)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.92, 0.52),
                  radius: 0.33,
                  colors: [
                    // Night 下 stage 光晕略强一点
                    Color(0x0D79D4C7),
                    Colors.transparent,
                  ],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          if (content case final c?) c,
        ],
      );
    }

    // Day
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
        if (child case final c?) c,
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
