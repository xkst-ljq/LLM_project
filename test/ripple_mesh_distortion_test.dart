import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ripple_mesh_distortion.dart';

/// 水波折射（方案 C：网格变形）的数学不变量。
///
/// 用户对旧实现的评价是「很敷衍」——它只是盖一个扩大的白圈，
/// 组件本身纹丝不动；而且进度条这类扁长组件上，
/// 圆被 ClipRRect 裁得只剩中间一条窄带，表现为「只有中点一小部分有动画」。
///
/// 新实现抓取纹理 + 扰动网格顶点，做出真正的折射（透镜）效果。

void main() {
  group('环带剖面（凸透镜）', () {
    test('剖面恒为非负，方向由径向向量决定', () {
      // ⚠️ 这是第三版剖面。前两版都因为「正负对撞」出问题：
      // 内侧向外推、外侧向内拉，两股位移在波前处相遇，
      // 相邻顶点间距被压到 2%，内容原地折叠成一团。
      // 那不是放大镜，是像素在小范围挤压 —— 用户两轮都反馈「像抖动」。
      for (var i = 0; i <= 100; i++) {
        final d = i / 50.0;
        final v = RippleMeshDistortion.ringProfile(d, 0.5);
        expect(v, greaterThanOrEqualTo(0.0), reason: 'd=$d');
        expect(v.isNaN, isFalse, reason: 'd=$d');
      }
    });

    test('波前处取得峰值', () {
      const front = 0.5;
      final atFront = RippleMeshDistortion.ringProfile(front, front);
      expect(atFront, closeTo(1.0, 1e-9));
      // 两侧对称衰减。
      final a = RippleMeshDistortion.ringProfile(front - 0.1, front);
      final b = RippleMeshDistortion.ringProfile(front + 0.1, front);
      expect(a, closeTo(b, 1e-9));
      expect(a, lessThan(atFront));
    });

    test('远离波前处归零', () {
      const front = 0.5;
      // 高斯在 ±2σ 外截断，避免整个组件都被轻微扰动。
      expect(
        RippleMeshDistortion.ringProfile(
            front + RippleMeshDistortion.ringWidth * 2.1, front),
        0.0,
      );
    });

    test('位移场单调，不产生网格折叠', () {
      // 核心不变量：变形后相邻顶点的间距必须恒为正，
      // 否则内容会折叠、糊成一团。
      const w = 200.0;
      const cols = RippleMeshDistortion.cols;
      const halfW = w / 2;
      var worstGap = double.infinity;

      for (var i = 0; i <= 40; i++) {
        final t = i / 40.0;
        final front = RippleMeshDistortion.waveFront(t);
        final amp = RippleMeshDistortion.maxStrength *
            0.6 *
            RippleMeshDistortion.damping(t);
        double? prevNew;
        double? prevX;
        for (var c = 0; c <= cols; c++) {
          final x = w * c / cols;
          final d = (x - halfW).abs() / halfW;
          var nx = x;
          if (c != 0 && c != cols && d > 1e-6) {
            final taper = ((1.0 - d) / 0.15).clamp(0.0, 1.0);
            final sign = x > halfW ? 1.0 : -1.0;
            nx = x +
                RippleMeshDistortion.ringProfile(d, front) *
                    amp *
                    halfW *
                    sign *
                    taper;
          }
          if (prevNew != null && prevX != null) {
            final gap = (nx - prevNew) / (x - prevX);
            worstGap = math.min(worstGap, gap);
          }
          prevNew = nx;
          prevX = x;
        }
      }
      expect(worstGap, greaterThan(0.0));
    });

    test('产生足够的局部放大，才看得出透镜', () {
      // 前一版剖面最大放大率仅 1.58x 且伴随折叠；
      // 单向高斯凸起能到约 4x，这才是「放大镜扫过」。
      const w = 200.0;
      const cols = RippleMeshDistortion.cols;
      const halfW = w / 2;
      var bestGap = 0.0;
      for (var i = 0; i <= 40; i++) {
        final t = i / 40.0;
        final front = RippleMeshDistortion.waveFront(t);
        final amp = RippleMeshDistortion.maxStrength *
            0.6 *
            RippleMeshDistortion.damping(t);
        double? prevNew;
        double? prevX;
        for (var c = 0; c <= cols; c++) {
          final x = w * c / cols;
          final d = (x - halfW).abs() / halfW;
          var nx = x;
          if (c != 0 && c != cols && d > 1e-6) {
            final taper = ((1.0 - d) / 0.15).clamp(0.0, 1.0);
            final sign = x > halfW ? 1.0 : -1.0;
            nx = x +
                RippleMeshDistortion.ringProfile(d, front) *
                    amp *
                    halfW *
                    sign *
                    taper;
          }
          if (prevNew != null && prevX != null) {
            bestGap = math.max(bestGap, (nx - prevNew) / (x - prevX));
          }
          prevNew = nx;
          prevX = x;
        }
      }
      expect(bestGap, greaterThan(2.0));
    });
  });

  group('壁面反弹', () {
    test('从中心出发', () {
      expect(RippleMeshDistortion.waveFront(0.0), closeTo(0.0, 1e-9));
    });

    test('中途撞到边界', () {
      // bounces=2.5 时，波前在 t≈0.4 抵达 1.0。
      final atWall = RippleMeshDistortion.waveFront(0.4);
      expect(atWall, closeTo(1.0, 1e-9));
    });

    test('撞壁后原路弹回', () {
      // 用户要求「像波浪一样碰到壁面会反弹」。
      final before = RippleMeshDistortion.waveFront(0.35);
      final after = RippleMeshDistortion.waveFront(0.45);
      expect(before, lessThan(1.0));
      expect(after, lessThan(1.0));
      // 撞壁前后都在往回走的对称位置附近。
      expect((before - after).abs(), lessThan(0.3));
    });

    test('波前始终在组件范围内', () {
      // 越界会让波跑到组件外面去，视觉上就断了。
      for (var i = 0; i <= 100; i++) {
        final t = i / 100.0;
        final f = RippleMeshDistortion.waveFront(t);
        expect(f, greaterThanOrEqualTo(-1e-9), reason: 't=$t');
        expect(f, lessThanOrEqualTo(1.0 + 1e-9), reason: 't=$t');
      }
    });

    test('全程发生多次往返', () {
      // 只弹一次没有余韵，弹太多次会显得拖沓。
      var reversals = 0;
      double? prevDelta;
      for (var i = 1; i <= 100; i++) {
        final a = RippleMeshDistortion.waveFront((i - 1) / 100.0);
        final b = RippleMeshDistortion.waveFront(i / 100.0);
        final delta = b - a;
        if (prevDelta != null && prevDelta * delta < 0) reversals++;
        prevDelta = delta;
      }
      expect(reversals, greaterThanOrEqualTo(2));
    });
  });

  group('衰减', () {
    test('起始为满、结束归零', () {
      expect(RippleMeshDistortion.damping(0.0), closeTo(1.0, 1e-9));
      expect(RippleMeshDistortion.damping(1.0), closeTo(0.0, 1e-9));
    });

    test('单调递减', () {
      // 波必须越来越弱，中途变强会很怪。
      double prev = 2.0;
      for (var i = 0; i <= 20; i++) {
        final v = RippleMeshDistortion.damping(i / 20.0);
        expect(v, lessThanOrEqualTo(prev + 1e-9));
        prev = v;
      }
    });

    test('超范围输入被夹取', () {
      expect(RippleMeshDistortion.damping(1.5), closeTo(0.0, 1e-9));
      expect(RippleMeshDistortion.damping(-0.2).isNaN, isFalse);
    });
  });

  group('顶点生成', () {
    test('顶点数与网格规格一致', () {
      // ui.Vertices 构造后不暴露顶点数，改为断言公开常量，
      // 它同时被 buildVertices 用于分配缓冲区，两者不会漂移。
      expect(
        RippleMeshDistortion.vertexCount,
        RippleMeshDistortion.cols * RippleMeshDistortion.rows * 6,
      );
      expect(RippleMeshDistortion.vertexCount, 3072);
      // 构造本身要能跑通。
      expect(
        () => RippleMeshDistortion.buildVertices(
          size: const Size(200, 12),
          progress: 0.3,
          intensity: 0.6,
        ),
        returnsNormally,
      );
    });

    test('零尺寸不崩溃', () {
      expect(
        () => RippleMeshDistortion.buildVertices(
          size: Size.zero,
          progress: 0.3,
          intensity: 0.6,
        ),
        returnsNormally,
      );
    });

    test('极端进度值不崩溃', () {
      // 回弹类曲线会让 progress 过冲出 [0,1]。
      for (final p in [-0.2, 0.0, 1.0, 1.3]) {
        expect(
          () => RippleMeshDistortion.buildVertices(
            size: const Size(200, 12),
            progress: p,
            intensity: 1.0,
          ),
          returnsNormally,
          reason: 'progress=$p',
        );
      }
    });
  });

  group('本体形变（动荡感）', () {
    test('横纵反相，形成挤压回弹', () {
      // 同相只是整体放大缩小；反相才有果冻感（近似体积守恒）。
      final m = RippleMeshDistortion.bodyDistortion(0.1, 1.0);
      final sx = m.storage[0];
      final sy = m.storage[5];
      expect((sx - 1.0) * (sy - 1.0), lessThan(0));
    });

    test('幅度不超过 1.5%，让折射当主角', () {
      // 形变是全局运动、折射是局部扭曲，量级相近时眼睛只看得到前者。
      // 9% 时 200px 组件整体横移 9.2px，用户反馈「就是抖动了」；
      // 降到 3% 仍嫌抢戏，现在压到 1.5%，只留一丝介质回弹的余味。
      for (var i = 0; i <= 100; i++) {
        final m = RippleMeshDistortion.bodyDistortion(i / 100.0, 1.0);
        expect((m.storage[0] - 1.0).abs(), lessThanOrEqualTo(0.015 + 1e-9));
      }
    });

    test('折射位移显著大于本体形变', () {
      // 这是「能看出水波」的必要条件，锁死两者的主次关系。
      const size = Size(200, 12);
      var maxRefraction = 0.0;
      var maxBodyShift = 0.0;
      for (var i = 0; i <= 40; i++) {
        final t = i / 40.0;
        final front = RippleMeshDistortion.waveFront(t);
        final amp = RippleMeshDistortion.maxStrength *
            0.6 *
            RippleMeshDistortion.damping(t);
        for (var c = 0; c <= RippleMeshDistortion.cols; c++) {
          final x = size.width * c / RippleMeshDistortion.cols;
          final d = (x - size.width / 2).abs() / (size.width / 2);
          if (d < 1e-6) continue;
          final shift =
              (RippleMeshDistortion.ringProfile(d, front) * amp * size.width / 2)
                  .abs();
          if (shift > maxRefraction) maxRefraction = shift;
        }
        final m = RippleMeshDistortion.bodyDistortion(t, 0.6);
        final bodyShift = ((m.storage[0] - 1.0).abs() * size.width / 2);
        if (bodyShift > maxBodyShift) maxBodyShift = bodyShift;
      }
      expect(maxRefraction, greaterThan(maxBodyShift * 4));
    });

    test('结束时回到原始比例', () {
      // 动画结束后组件必须恢复原样，否则会留下永久变形。
      final m = RippleMeshDistortion.bodyDistortion(1.0, 1.0);
      expect(m.storage[0], closeTo(1.0, 1e-9));
      expect(m.storage[5], closeTo(1.0, 1e-9));
    });

    test('强度为零时不形变', () {
      final m = RippleMeshDistortion.bodyDistortion(0.3, 0.0);
      expect(m.storage[0], closeTo(1.0, 1e-9));
      expect(m.storage[5], closeTo(1.0, 1e-9));
    });
  });
}
