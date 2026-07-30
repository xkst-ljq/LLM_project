import 'package:flutter_test/flutter_test.dart';

/// 精调方向键（3×3 D-Pad）的布局不变量。
///
/// Studio 与 Assembly 共用同一套尺寸——用户反馈 Assembly 版
/// 「比 studio 更加紧凑，而且中间的方块还有相对坐标」，
/// 遂反向移植回 Studio。两边任何一侧改了尺寸都应同步，
/// 这组断言用于守住对齐关系。

/// 箭头按钮直径。
const double kArrowSize = 40.0;

/// 相邻控件间距。旧 Studio 版是 16，移植后统一为 12——
/// D-Pad 是拇指连续点按的控件，间距过大反而要挪手。
const double kGap = 12.0;

/// 上下行两侧的占位宽度。
///
/// 必须等于 `箭头 + 间距`，否则上下行的箭头不会与中间行的中心方块对齐。
const double kBlankWidth = kArrowSize + kGap;

/// D-Pad 总宽。
double get padWidth => kArrowSize * 3 + kGap * 2;

/// 居中所需的左偏移。
double get centeringOffset => padWidth / 2;

void main() {
  group('三行宽度必须相等', () {
    test('中间行 = 箭头 + 间距 + 中心 + 间距 + 箭头', () {
      final middle = kArrowSize + kGap + kArrowSize + kGap + kArrowSize;
      expect(middle, 144.0);
    });

    test('上下行 = 占位 + 箭头 + 占位', () {
      final outer = kBlankWidth + kArrowSize + kBlankWidth;
      expect(outer, 144.0);
    });

    test('三行等宽，箭头才会与中心方块严格对齐', () {
      final middle = kArrowSize * 3 + kGap * 2;
      final outer = kBlankWidth * 2 + kArrowSize;
      expect(outer, middle);
    });

    test('占位宽等于箭头加间距', () {
      // 写死成别的值（比如沿用 56）会让上下箭头偏离中轴。
      expect(kBlankWidth, kArrowSize + kGap);
    });
  });

  group('居中偏移', () {
    test('偏移量为总宽的一半', () {
      // 曾把注释里的总宽误写成 136、偏移写成 68，导致整体偏右 4px。
      expect(padWidth, 144.0);
      expect(centeringOffset, 72.0);
    });

    test('偏移量与总宽联动，改尺寸不会漏改居中', () {
      expect(centeringOffset * 2, padWidth);
    });
  });

  group('与旧 Studio 版的差异', () {
    test('新版比旧版紧凑', () {
      const oldGap = 16.0;
      final oldWidth = kArrowSize * 3 + oldGap * 2;
      expect(oldWidth, 152.0);
      expect(padWidth, lessThan(oldWidth));
    });
  });
}
