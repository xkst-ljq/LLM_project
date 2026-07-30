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
  group('环带剖面（透镜的内推外拉）', () {
    test('波前处连续过零，不会撕裂', () {
      // ⚠️ 最初写成 cos²(πx/2) × sign(x)，在 x=0 处从 -1 跳到 +1，
      // 是 2.0 的阶跃，表现为波前处图像撕裂，
      // 且加密网格反而更明显（因为跳变本身没消失）。
      const front = 0.5;
      final atFront = RippleMeshDistortion.ringProfile(front, front);
      expect(atFront.abs(), lessThan(1e-9));

      // 紧邻两侧应该符号相反且幅度相近——这才是透镜。
      final inner = RippleMeshDistortion.ringProfile(front - 0.05, front);
      final outer = RippleMeshDistortion.ringProfile(front + 0.05, front);
      expect(inner * outer, lessThan(0));
      expect((inner.abs() - outer.abs()).abs(), lessThan(0.05));
    });

    test('环带之外没有位移', () {
      const front = 0.5;
      // 超出环带宽度的地方必须完全归零，否则整个组件都在抖。
      expect(
        RippleMeshDistortion.ringProfile(
            front + RippleMeshDistortion.ringWidth + 0.01, front),
        0.0,
      );
      expect(
        RippleMeshDistortion.ringProfile(
            front - RippleMeshDistortion.ringWidth - 0.01, front),
        0.0,
      );
    });

    test('剖面处处有界', () {
      // 防止某个角度算出爆炸的位移把纹理扯坏。
      for (var i = 0; i <= 100; i++) {
        final d = i / 50.0;
        final v = RippleMeshDistortion.ringProfile(d, 0.5);
        expect(v.abs(), lessThanOrEqualTo(1.0), reason: 'd=$d');
        expect(v.isNaN, isFalse, reason: 'd=$d');
      }
    });

    test('相邻网格点之间的剖面变化足够平缓', () {
      // 32 列时若剖面跳变过大，会看出多边形折线。
      const front = 0.5;
      double worst = 0;
      double? prev;
      for (var c = 0; c <= RippleMeshDistortion.cols; c++) {
        // 中线上的归一化距离：从 1.0 递减到 0 再回到 1.0。
        final x = c / RippleMeshDistortion.cols;
        final d = (x - 0.5).abs() * 2;
        final v = RippleMeshDistortion.ringProfile(d, front);
        if (prev != null) worst = math.max(worst, (v - prev).abs());
        prev = v;
      }
      expect(worst, lessThan(0.35));
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
      expect(RippleMeshDistortion.vertexCount, 1152);
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

    test('幅度不超过 9%', () {
      // 再大文字会明显糊。
      for (var i = 0; i <= 100; i++) {
        final m = RippleMeshDistortion.bodyDistortion(i / 100.0, 1.0);
        expect((m.storage[0] - 1.0).abs(), lessThanOrEqualTo(0.09 + 1e-9));
      }
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
