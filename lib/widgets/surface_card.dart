import 'dart:ui';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';

/// 统一的表面卡片：玻璃质感（毛玻璃 + 半透明表面 + 描边 + 圆角）。
///
/// 用于列表页、表单页的分组卡片，让所有子页面与主页风格统一。
/// - [margin]/[padding]：卡片外/内边距
/// - [elevation]：是否带轻微投影
/// - [child]：卡片内容
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final bool elevation;
  final BorderRadius? radius;

  const SurfaceCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(12),
    this.elevation = false,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final r = radius ?? BorderRadius.circular(tokens.radiusLarge);

    Widget content = ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tokens.surfaceGlass.withValues(alpha: 0.65),
            borderRadius: r,
            border: Border.all(color: tokens.outline.withValues(alpha: 0.5)),
            boxShadow: elevation
                ? [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: tokens.elevationLow,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (margin == EdgeInsets.zero) return content;
    return Padding(padding: margin, child: content);
  }
}
