import 'package:flutter/material.dart';

/// Night 模式下给子页面叠加一层蓝紫渐变氛围；Day 模式无操作（保持现状）。
///
/// 包在子页面 Scaffold 的 body 外层（或覆盖层 Stack 底部）：
/// Night 时 body 背后是「左上靛蓝 → 中深蓝 → 右下紫」的线性渐变，
/// 比纯 canvas 略亮、带一点冷色调；Day 时原样返回 [child]，不引入任何变化。
class SubPageBackdrop extends StatelessWidget {
  const SubPageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    if (!isNight) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 蓝紫氛围层：左上靛蓝 → 中深蓝 → 右下紫。
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
        child,
      ],
    );
  }
}
