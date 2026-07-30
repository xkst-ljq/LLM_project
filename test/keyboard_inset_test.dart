import 'package:flutter_test/flutter_test.dart';

/// 键盘弹出时的布局策略。
///
/// 用户反馈：「用 input 输入时，输入法弹出挤压的区域会算进可用屏幕里，
/// UI 界面会重新分配到输入法以上的区域，这样会刻意压缩导致体验感差」。
///
/// 全仓此前**没有任何一处**设置 `resizeToAvoidBottomInset`，
/// 全部走 Flutter 默认的 `true`——键盘一弹，Scaffold body 就收缩，
/// 布局被强行重排。
///
/// 但这**不能一刀切关掉**：聊天页的输入框必须跟着键盘上移，
/// 关了会让输入框被键盘盖住。所以要按页面类型区分。

/// 页面对键盘的三种处理策略。
enum KeyboardStrategy {
  /// 不重排：画布/全屏 UI 类。布局依赖完整高度，压缩会破坏设计。
  keepLayout,

  /// 随键盘收缩：输入为主的表单、聊天输入框。
  shrink,

  /// 收缩但补偿特定图层：聊天页——输入框要跟，场景 UI 不跟。
  shrinkWithCompensation,
}

/// 复刻各页面的策略决策。
KeyboardStrategy strategyFor({
  required bool isCanvasLike,
  required bool scalesToAvailableHeight,
  required bool hasBottomAnchoredInput,
}) {
  // 按可用高度等比缩放的页面，被压缩会让整个 UI 变小——
  // 比单纯挤压更糟，作者摆好的字号与间距全变样。
  if (scalesToAvailableHeight && !hasBottomAnchoredInput) {
    return KeyboardStrategy.keepLayout;
  }
  if (isCanvasLike) return KeyboardStrategy.keepLayout;
  if (hasBottomAnchoredInput && scalesToAvailableHeight) {
    return KeyboardStrategy.shrinkWithCompensation;
  }
  return KeyboardStrategy.shrink;
}

/// 复刻场景层的高度补偿。
///
/// Scaffold body 被键盘压缩后，`top:0 bottom:0` 的图层跟着缩。
/// 把吃掉的高度用负 bottom 补回去，图层就保持原尺寸。
double compensatedBottom(double keyboardInset) => -keyboardInset;

void main() {
  group('页面策略', () {
    test('编辑画布不随键盘重排', () {
      // 画布有自己的平移/缩放，被压缩后正在编辑的元件会跑出可视区。
      expect(
        strategyFor(
          isCanvasLike: true,
          scalesToAvailableHeight: false,
          hasBottomAnchoredInput: false,
        ),
        KeyboardStrategy.keepLayout,
      );
    });

    test('全屏运行时预览不随键盘重排', () {
      // UIAssemblyRuntimeView 按 constraints.maxHeight 等比缩放整张 PCB，
      // Scaffold 一收缩就把整个 UI 缩小。
      expect(
        strategyFor(
          isCanvasLike: false,
          scalesToAvailableHeight: true,
          hasBottomAnchoredInput: false,
        ),
        KeyboardStrategy.keepLayout,
      );
    });

    test('聊天页收缩但补偿场景层', () {
      // 输入框必须跟着键盘上移，否则被盖住；
      // 但场景 UI 是全屏接管的，不该跟着缩。
      expect(
        strategyFor(
          isCanvasLike: false,
          scalesToAvailableHeight: true,
          hasBottomAnchoredInput: true,
        ),
        KeyboardStrategy.shrinkWithCompensation,
      );
    });

    test('普通表单页保持默认收缩', () {
      // 表单本来就该让输入框可见，默认行为是对的。
      expect(
        strategyFor(
          isCanvasLike: false,
          scalesToAvailableHeight: false,
          hasBottomAnchoredInput: false,
        ),
        KeyboardStrategy.shrink,
      );
    });

    test('不能一刀切关闭 resize', () {
      // 关键约束：至少要有一类页面仍然收缩，
      // 否则聊天输入框会被键盘盖住。
      final strategies = [
        strategyFor(
          isCanvasLike: true,
          scalesToAvailableHeight: false,
          hasBottomAnchoredInput: false,
        ),
        strategyFor(
          isCanvasLike: false,
          scalesToAvailableHeight: false,
          hasBottomAnchoredInput: false,
        ),
      ];
      expect(strategies.contains(KeyboardStrategy.keepLayout), isTrue);
      expect(strategies.contains(KeyboardStrategy.shrink), isTrue);
    });
  });

  group('场景层高度补偿', () {
    test('键盘收起时不补偿', () {
      expect(compensatedBottom(0), 0);
    });

    test('补偿量等于被吃掉的高度', () {
      // body 缩了 320，就用 bottom:-320 把它撑回去。
      expect(compensatedBottom(320), -320);
    });

    test('补偿后总高度回到原值', () {
      const screenHeight = 800.0;
      const keyboard = 320.0;
      // Scaffold body 收缩后的高度。
      const shrunk = screenHeight - keyboard;
      // 图层实际高度 = body 高度 - top - bottom。
      final layerHeight = shrunk - 0 - compensatedBottom(keyboard);
      expect(layerHeight, screenHeight);
    });
  });
}
