import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

/// A12 水波折射（方案 A：片元着色器）的数学不变量。
///
/// 着色器本身无法在单元测试里运行，`RippleWaveMath` 是它的 Dart 复刻。
/// 两份实现必须同步——GLSL 那份是实际生效的。
///
/// 水波改到第六版了。前五版的失败原因分别是：
/// 1. 单正圆 + 裁切 → 进度条上只剩中间一条窄带
/// 2. 网格变形 → 捕获回调从不 setState，代码根本没执行
/// 3. 椭圆跟随长宽比 → 环变成 16.7:1 的扁线
/// 4. 正圆实色描边 → 像贴了几个同心圆环
/// 5. 渐变光带 + 加色 → 「很像是两个图层」（底层像素确实没动）
///
/// 第六版用逐像素重采样，让**内容本身**扭曲，这是叠加绘制做不到的。

/// 复刻着色器里的采样偏移计算，用于验证不会折叠。
double sampleOffsetAt({
  required double u,
  required double t,
  required double intensity,
}) {
  final envelope = RippleWaveMath.envelope(t);
  if (envelope <= 0.01) return 0.0;

  final cx = (u - 0.5) * 2.0;
  final dist = cx.abs();
  if (dist <= 1e-4) return 0.0;

  final dir = cx / dist;
  final bandWidth = (0.10 + 0.10 * intensity).clamp(0.06, 0.24);
  final amp = 0.12 * intensity * envelope;

  var offset = 0.0;
  for (var i = 0; i < 3; i++) {
    final front = RippleWaveMath.waveFront(t, i * 0.22);
    final fade = envelope * math.max(1.0 - i * 0.3, 0.0);
    if (fade <= 0.015) continue;
    final p = RippleWaveMath.ringProfile(dist, front, bandWidth);
    if (p <= 0.001) continue;
    offset += dir * p * amp * fade;
  }

  final edgeFade = ((1.0 - dist) / 0.18).clamp(0.0, 1.0);
  return offset * edgeFade * 0.5;
}

void main() {
  group('波前折返（壁面反弹）', () {
    test('从中心出发', () {
      expect(RippleWaveMath.waveFront(0.0, 0.0), closeTo(0.0, 1e-9));
    });

    test('撞到边界后原路弹回', () {
      // 用户要求「像波浪一样碰到壁面会反弹」。
      expect(RippleWaveMath.waveFront(0.4, 0.0), closeTo(1.0, 1e-9));
      // 撞壁后开始回程。
      expect(RippleWaveMath.waveFront(0.5, 0.0), lessThan(1.0));
    });

    test('波前始终在组件范围内', () {
      for (var i = 0; i <= 100; i++) {
        for (final phase in [0.0, 0.22, 0.44]) {
          final f = RippleWaveMath.waveFront(i / 100.0, phase);
          expect(f, greaterThanOrEqualTo(-1e-9));
          expect(f, lessThanOrEqualTo(1.0 + 1e-9));
        }
      }
    });

    test('全程发生多次往返', () {
      var reversals = 0;
      double? prevDelta;
      for (var i = 1; i <= 100; i++) {
        final a = RippleWaveMath.waveFront((i - 1) / 100.0, 0.0);
        final b = RippleWaveMath.waveFront(i / 100.0, 0.0);
        final delta = b - a;
        if (prevDelta != null && prevDelta * delta < 0) reversals++;
        prevDelta = delta;
      }
      expect(reversals, greaterThanOrEqualTo(2));
    });

    test('三道波错开相位', () {
      // 同相就只有一个环，看不出「一圈接一圈荡开」。
      final fronts = [0.0, 0.22, 0.44]
          .map((p) => RippleWaveMath.waveFront(0.15, p))
          .toList();
      expect(fronts.toSet().length, 3);
    });
  });

  group('环带剖面', () {
    test('恒为非负，方向交给径向向量', () {
      // ⚠️ 曾用「内侧正、外侧负」的对撞式剖面，
      // 两股位移在波前相遇，采样点被压到 2%，内容原地折叠。
      for (var i = 0; i <= 100; i++) {
        final v = RippleWaveMath.ringProfile(i / 50.0, 0.5, 0.2);
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v.isNaN, isFalse);
      }
    });

    test('波前处取得峰值且两侧对称', () {
      const front = 0.5;
      expect(
        RippleWaveMath.ringProfile(front, front, 0.2),
        closeTo(1.0, 1e-9),
      );
      expect(
        RippleWaveMath.ringProfile(front - 0.1, front, 0.2),
        closeTo(RippleWaveMath.ringProfile(front + 0.1, front, 0.2), 1e-9),
      );
    });

    test('远离波前处截断归零', () {
      expect(RippleWaveMath.ringProfile(0.5 + 0.2 * 2.1, 0.5, 0.2), 0.0);
    });
  });

  group('采样偏移不产生折叠', () {
    test('同一侧内部严格单调', () {
      // 这是「内容不糊成一团」的核心不变量。
      //
      // 注意只能在**同一侧**内部判定：径向位移在中心两侧必然反向，
      // 那是透镜的固有性质。我最初把跨中心那一步也算进去，
      // 误判成折叠、差点把振幅调到没有效果。
      var worst = double.infinity;
      for (var step = 0; step <= 40; step++) {
        final t = step / 40.0;
        for (final range in [
          [0, 99],
          [101, 200],
        ]) {
          double? prevSample;
          double? prevU;
          for (var i = range[0]; i <= range[1]; i++) {
            final u = i / 200.0;
            final sample = u - sampleOffsetAt(u: u, t: t, intensity: 1.0);
            if (prevSample != null && prevU != null) {
              worst = math.min(worst, (sample - prevSample) / (u - prevU));
            }
            prevSample = sample;
            prevU = u;
          }
        }
      }
      expect(worst, greaterThan(0.0));
    });

    test('振幅留有安全余量', () {
      // 实测 0.14 是折叠临界值，取 0.12 留约 15% 余量。
      // 若日后调大，上面那条单调性测试会失败。
      var maxOffset = 0.0;
      for (var step = 0; step <= 40; step++) {
        final t = step / 40.0;
        for (var i = 0; i <= 200; i++) {
          final o = sampleOffsetAt(u: i / 200.0, t: t, intensity: 1.0);
          maxOffset = math.max(maxOffset, o.abs());
        }
      }
      // 归一化偏移换算到 200px 宽组件。
      expect(maxOffset * 200, greaterThan(8.0));
      expect(maxOffset * 200, lessThan(16.0));
    });

    test('边缘位移趋零，不会采样越界', () {
      // 越界会让组件边缘露出空白或拉伸的像素条。
      expect(sampleOffsetAt(u: 0.0, t: 0.2, intensity: 1.0).abs(),
          lessThan(1e-6));
      expect(sampleOffsetAt(u: 1.0, t: 0.2, intensity: 1.0).abs(),
          lessThan(1e-6));
    });

    test('动画结束时无位移', () {
      for (var i = 0; i <= 200; i++) {
        expect(
          sampleOffsetAt(u: i / 200.0, t: 1.0, intensity: 1.0).abs(),
          lessThan(1e-9),
        );
      }
    });

    test('强度为零时无位移', () {
      for (var i = 0; i <= 200; i++) {
        expect(
          sampleOffsetAt(u: i / 200.0, t: 0.2, intensity: 0.0).abs(),
          lessThan(1e-9),
        );
      }
    });
  });

  group('纵向压缩', () {
    test('方形组件不压缩', () {
      expect(RippleWaveMath.squashFor(const Size(80, 80)), 1.0);
    });

    test('扁长组件压缩但有下限', () {
      // ⚠️ 第三版让椭圆完全跟随长宽比，进度条上环变成 16.7:1 的扁线，
      // 用户评价「一点也不像波纹」。压缩比必须封顶。
      final squash = RippleWaveMath.squashFor(const Size(200, 12));
      expect(squash, greaterThanOrEqualTo(0.55));
      // 换算成环的长宽比，应当接近正圆而非扁线。
      expect(1 / squash, lessThan(2.0));
    });

    test('高瘦组件不压缩', () {
      expect(RippleWaveMath.squashFor(const Size(40, 120)), 1.0);
    });

    test('零宽度不崩溃', () {
      expect(RippleWaveMath.squashFor(const Size(0, 50)), 1.0);
    });
  });

  group('衰减包络', () {
    test('起始为满、结束归零', () {
      expect(RippleWaveMath.envelope(0.0), closeTo(1.0, 1e-9));
      expect(RippleWaveMath.envelope(1.0), closeTo(0.0, 1e-9));
    });

    test('单调递减', () {
      var prev = 2.0;
      for (var i = 0; i <= 20; i++) {
        final v = RippleWaveMath.envelope(i / 20.0);
        expect(v, lessThanOrEqualTo(prev + 1e-9));
        prev = v;
      }
    });

    test('超范围输入安全', () {
      expect(RippleWaveMath.envelope(1.5), closeTo(0.0, 1e-9));
      expect(RippleWaveMath.envelope(-0.2).isNaN, isFalse);
    });
  });

  group('着色器加载容错', () {
    test('未加载时不报告就绪', () {
      // 加载失败必须能被察觉，调用方据此回退到原样显示。
      // 这里只验证初始状态与接口存在，实际加载依赖资源与平台。
      expect(RippleShaderLoader.isReady, isA<bool>());
      expect(RippleShaderLoader.hasFailed, isA<bool>());
      expect(RippleShaderLoader.createShader(), isNull);
    });
  });
}
