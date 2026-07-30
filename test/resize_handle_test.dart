import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A14-1g：形变把手。
///
/// 用户选定**只做形变、不做旋转把手**：旋转使用率不高，
/// 精确几何里已有角度输入且更准；而 Studio 的单把手靠
/// 「点一下切换形变/旋转」实现两用，代价是每次形变前都要确认当前模式——
/// 为低频功能给高频操作上税不划算。
///
/// 用户的纠结点是「旋转过后形变把手也会跟着旋转」。
/// 核实后发现别扭的真正来源是 **Studio 旧实现把屏幕 dx/dy
/// 直接当宽高增量**：把手跟着转了，拖动的数学却没跟着转。
/// 修正为投影到局部轴后，旋转后的把手反而完全直觉，
/// 不需要靠旋转把手来「补偿」。

/// 把手边距。撑开元件盒子给把手站位——
/// Flutter 命中检测会先判断 `size.contains(position)`，
/// 画在盒外的把手收不到点击。
const double kResizeHandlePadding = 12.0;

/// 复刻局部轴投影。
Offset projectToLocalAxes(Offset rawDelta, double rotationDegrees) {
  final rad = rotationDegrees * math.pi / 180.0;
  final cosR = math.cos(rad);
  final sinR = math.sin(rad);
  return Offset(
    rawDelta.dx * cosR + rawDelta.dy * sinR,
    -rawDelta.dx * sinR + rawDelta.dy * cosR,
  );
}

Size minResizeFor(String? type) {
  if (type == 'progress') return const Size(12, 6);
  if (isSurfaceLike(type)) return const Size(20, 20);
  return const Size(40, 20);
}

Size maxResizeFor(String? type) {
  if (isSurfaceLike(type)) return const Size(4096, 4096);
  return const Size(600, 400);
}

bool isSurfaceLike(String? type) => const {
      'surface',
      'surface_art',
      'primitive_art',
      'base_box',
    }.contains(type);

/// 复刻「是否显示把手」。
bool supportsResizeHandle({
  required bool isSelected,
  required String? type,
  bool layoutLocked = false,
  bool sealed = false,
  bool isComposite = false,
}) {
  if (!isSelected) return false;
  if (layoutLocked || sealed) return false;
  if (type == null) return isComposite;
  const fixedSize = {
    'linker',
    'math_node',
    'timer',
    'page_router',
    'indicator',
  };
  return !fixedSize.contains(type);
}

Size applyResize({
  required Size startSize,
  required Offset rawDelta,
  required double rotation,
  String? type,
}) {
  final local = projectToLocalAxes(rawDelta, rotation);
  final minSize = minResizeFor(type);
  final maxSize = maxResizeFor(type);
  return Size(
    (startSize.width + local.dx).clamp(minSize.width, maxSize.width).toDouble(),
    (startSize.height + local.dy)
        .clamp(minSize.height, maxSize.height)
        .toDouble(),
  );
}

/// 复刻 `_offsetKeepingResizeAnchor`。
Offset offsetKeepingAnchor({
  required Offset offset,
  required Size oldSize,
  required Size newSize,
  required double rotation,
}) {
  if (rotation == 0.0) return offset;
  final dW = (newSize.width - oldSize.width) / 2;
  final dH = (newSize.height - oldSize.height) / 2;
  final rad = rotation * math.pi / 180.0;
  final cosR = math.cos(rad);
  final sinR = math.sin(rad);
  return Offset(
    offset.dx - dW + (dW * cosR - dH * sinR),
    offset.dy - dH + (dW * sinR + dH * cosR),
  );
}

/// 局部左上角（把手对角）在屏幕上的位置。
///
/// `Transform.rotate` 绕中心旋转，因此要先到中心、再转半尺寸向量。
Offset anchorScreenPos(Offset offset, Size size, double rotation) {
  final cx = offset.dx + size.width / 2;
  final cy = offset.dy + size.height / 2;
  final rad = rotation * math.pi / 180.0;
  final cosR = math.cos(rad);
  final sinR = math.sin(rad);
  final hx = -size.width / 2;
  final hy = -size.height / 2;
  return Offset(
    cx + hx * cosR - hy * sinR,
    cy + hx * sinR + hy * cosR,
  );
}

/// 复刻 `UIRenderer.compositeNaturalSize`：子元素包围盒的右下边界。
Size compositeNaturalSize(List<({Offset offset, Size size})> children) {
  var maxX = 0.0;
  var maxY = 0.0;
  for (final c in children) {
    final right = c.offset.dx + c.size.width;
    final bottom = c.offset.dy + c.size.height;
    if (right > maxX) maxX = right;
    if (bottom > maxY) maxY = bottom;
  }
  return Size(maxX <= 0 ? 1.0 : maxX, maxY <= 0 ? 1.0 : maxY);
}

const double kMinCompositeScale = 0.45;

/// 复刻复合件的等比缩放夹取。
Size resizeComposite({
  required Size natural,
  required Size startSize,
  required double localDx,
  required Size pcb,
}) {
  final aspect = natural.height / natural.width;
  final minSize = Size(
    natural.width * kMinCompositeScale,
    natural.height * kMinCompositeScale,
  );
  var w = (startSize.width + localDx).clamp(minSize.width, pcb.width).toDouble();
  var h = w * aspect;
  if (h > pcb.height) {
    h = pcb.height;
    w = h / aspect;
  } else if (h < minSize.height) {
    h = minSize.height;
    w = h / aspect;
  }
  return Size(w, h);
}

void main() {
  group('复合组件等比缩放', () {
    // 用户反馈：形变把手给复合组件只能形变边框，内部纹丝不动。
    // 根因是 _renderComposite 用绝对坐标摆子元素，
    // 改外框 size 不影响内容。改为按内容包围盒等比 Transform.scale。

    test('自然尺寸取子元素包围盒的右下边界', () {
      final natural = compositeNaturalSize([
        (offset: const Offset(10, 20), size: const Size(80, 30)),
        (offset: const Offset(0, 60), size: const Size(120, 40)),
      ]);
      // 取右下边界而非 max-min：左上留白也是布局的一部分，
      // 减掉会让内容贴边。
      expect(natural.width, 120);
      expect(natural.height, 100);
    });

    test('空复合件有非零兜底，避免除零', () {
      final natural = compositeNaturalSize([]);
      expect(natural.width, 1.0);
      expect(natural.height, 1.0);
    });

    test('缩放严格等比，宽高比恒定', () {
      const natural = Size(200, 100);
      const pcb = Size(360, 800);
      for (final d in [1000.0, -1000.0, 50.0, 0.0]) {
        final s = resizeComposite(
          natural: natural,
          startSize: natural,
          localDx: d,
          pcb: pcb,
        );
        expect(s.height / s.width, closeTo(0.5, 1e-9), reason: '$d');
      }
    });

    test('最大不超过 PCB 宽度', () {
      final s = resizeComposite(
        natural: const Size(200, 100),
        startSize: const Size(200, 100),
        localDx: 1000,
        pcb: const Size(360, 800),
      );
      expect(s.width, 360);
    });

    test('高瘦复合件放大时撞的是 PCB 高度上限', () {
      // 宽度还没到 360，高度先到 800，此时应由高度反推宽度，
      // 否则比例会被破坏。
      final s = resizeComposite(
        natural: const Size(100, 400),
        startSize: const Size(100, 400),
        localDx: 1000,
        pcb: const Size(360, 800),
      );
      expect(s.height, 800);
      expect(s.width, closeTo(200, 1e-9));
    });

    test('最小比例保证内部文字仍可辨认', () {
      // 复合件内常见字号 9~12，乘 0.45 后约 4~5.4px，再小就糊了。
      const natural = Size(200, 100);
      final s = resizeComposite(
        natural: natural,
        startSize: natural,
        localDx: -1000,
        pcb: const Size(360, 800),
      );
      expect(s.width / natural.width, closeTo(kMinCompositeScale, 1e-9));
      expect(s.width, 90);
      expect(s.height, 45);
    });
  });

  group('形变锚点（旋转后图形到处跑的根因）', () {
    // 用户反馈：旋转 90° 后拖把手，形变没有锚点、图形到处跑。
    //
    // 根因：Transform.rotate 绕**中心**旋转，而 offset 定义的是**左上角**。
    // 改尺寸时若 offset 不动，中心就跟着移动，
    // 旋转后的图形等于绕一个正在移动的中心转。
    // 未旋转时中心也在动，只是增长方向与屏幕轴对齐、左上角看着没变。

    test('不修正 offset 时，旋转 90 度后锚点确实会跑', () {
      const off = Offset(100, 100);
      const oldSize = Size(80, 40);
      const newSize = Size(100, 40);
      final before = anchorScreenPos(off, oldSize, 90);
      final after = anchorScreenPos(off, newSize, 90);
      // 加宽 20，锚点跑了 (10, -10)——这就是「到处跑」的观感来源。
      expect(after.dx - before.dx, closeTo(10, 1e-9));
      expect(after.dy - before.dy, closeTo(-10, 1e-9));
    });

    test('修正后锚点在各角度都严格不动', () {
      const off = Offset(100, 100);
      const oldSize = Size(80, 40);
      const newSize = Size(100, 60);
      for (final angle in [0.0, 45.0, 90.0, 180.0, 213.0, -30.0]) {
        final fixed = offsetKeepingAnchor(
          offset: off,
          oldSize: oldSize,
          newSize: newSize,
          rotation: angle,
        );
        final before = anchorScreenPos(off, oldSize, angle);
        final after = anchorScreenPos(fixed, newSize, angle);
        expect(after.dx, closeTo(before.dx, 1e-9), reason: '$angle');
        expect(after.dy, closeTo(before.dy, 1e-9), reason: '$angle');
      }
    });

    test('未旋转时 offset 完全不变，向后兼容', () {
      // 0° 时 rot 是恒等变换，两项抵消。
      // 这条保证老行为一字不改。
      const off = Offset(100, 100);
      final fixed = offsetKeepingAnchor(
        offset: off,
        oldSize: const Size(80, 40),
        newSize: const Size(500, 300),
        rotation: 0,
      );
      expect(fixed, off);
    });

    test('缩小时锚点同样不动', () {
      const off = Offset(100, 100);
      const oldSize = Size(120, 80);
      const newSize = Size(60, 30);
      final fixed = offsetKeepingAnchor(
        offset: off,
        oldSize: oldSize,
        newSize: newSize,
        rotation: 90,
      );
      final before = anchorScreenPos(off, oldSize, 90);
      final after = anchorScreenPos(fixed, newSize, 90);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('逐帧增量修正与一次性修正等价', () {
      // Assembly 每帧以当前尺寸为基准增量修正，
      // Studio 以拖动起点快照一次性修正。
      // 变换是线性的，两者必须给出同一结果，否则两边手感会分叉。
      const deg = 37.0;
      const startOff = Offset(100, 100);
      const startSize = Size(80, 40);
      const finalSize = Size(140, 90);

      final oneShot = offsetKeepingAnchor(
        offset: startOff,
        oldSize: startSize,
        newSize: finalSize,
        rotation: deg,
      );

      var off = startOff;
      var cur = startSize;
      for (final f in [
        const Size(95, 52),
        const Size(110, 65),
        const Size(125, 78),
        finalSize,
      ]) {
        off = offsetKeepingAnchor(
          offset: off,
          oldSize: cur,
          newSize: f,
          rotation: deg,
        );
        cur = f;
      }

      expect(off.dx, closeTo(oneShot.dx, 1e-9));
      expect(off.dy, closeTo(oneShot.dy, 1e-9));
    });
  });

  group('局部轴投影（旋转后手感的关键）', () {
    test('未旋转时与直接用屏幕位移等价', () {
      final r = projectToLocalAxes(const Offset(20, 0), 0);
      expect(r.dx, closeTo(20, 1e-9));
      expect(r.dy, closeTo(0, 1e-9));
    });

    test('旋转 90 度后，向屏幕下方拖才是加宽', () {
      // 元件转 90° 后，它的「宽」轴在屏幕上指向下方。
      final r = projectToLocalAxes(const Offset(0, 20), 90);
      expect(r.dx, closeTo(20, 1e-9));
      expect(r.dy, closeTo(0, 1e-9));
    });

    test('旋转 90 度后向右拖是减高，不再误加宽', () {
      // 这正是旧实现的 bug：它会把这一拖当成 width + 20。
      final r = projectToLocalAxes(const Offset(20, 0), 90);
      expect(r.dx, closeTo(0, 1e-9));
      expect(r.dy, closeTo(-20, 1e-9));
    });

    test('旋转 180 度后向左拖是加宽', () {
      final r = projectToLocalAxes(const Offset(-20, 0), 180);
      expect(r.dx, closeTo(20, 1e-9));
      expect(r.dy, closeTo(0, 1e-9));
    });

    test('沿把手所在的对角线方向拖，等比放大', () {
      // 45° 时沿屏幕对角线拖，应当只加宽不改高。
      final r = projectToLocalAxes(const Offset(14.142, 14.142), 45);
      expect(r.dx, closeTo(20, 0.01));
      expect(r.dy, closeTo(0, 0.01));
    });

    test('投影保长度，拖多远就长多少', () {
      const raw = Offset(30, 40); // 长度 50
      for (final angle in [0.0, 37.0, 90.0, 213.0]) {
        final r = projectToLocalAxes(raw, angle);
        expect(r.distance, closeTo(50, 1e-6), reason: '$angle');
      }
    });
  });

  group('把手的显示条件', () {
    test('未选中不显示', () {
      expect(supportsResizeHandle(isSelected: false, type: 'text'), isFalse);
    });

    test('半锁 / 全锁都不显示', () {
      // 锁定针对的就是「误改几何」，把手必须收起。
      expect(
        supportsResizeHandle(
            isSelected: true, type: 'text', layoutLocked: true),
        isFalse,
      );
      expect(
        supportsResizeHandle(isSelected: true, type: 'text', sealed: true),
        isFalse,
      );
    });

    test('固定尺寸的逻辑件不显示', () {
      // 尺寸由渲染器决定，拉伸没有意义（与 A14-1 的几何按钮同口径）。
      for (final t in [
        'linker',
        'math_node',
        'timer',
        'page_router',
        'indicator',
      ]) {
        expect(
          supportsResizeHandle(isSelected: true, type: t),
          isFalse,
          reason: t,
        );
      }
    });

    test('普通显示类组件显示', () {
      for (final t in ['text', 'progress', 'surface', 'image', 'slider']) {
        expect(
          supportsResizeHandle(isSelected: true, type: t),
          isTrue,
          reason: t,
        );
      }
    });

    test('复合黑盒显示', () {
      expect(
        supportsResizeHandle(isSelected: true, type: null, isComposite: true),
        isTrue,
      );
    });
  });

  group('尺寸夹取', () {
    test('进度条允许做得很细', () {
      // 血条这类经常只有几像素高。
      final s = applyResize(
        startSize: const Size(100, 10),
        rawDelta: const Offset(-200, -200),
        rotation: 0,
        type: 'progress',
      );
      expect(s.width, 12);
      expect(s.height, 6);
    });

    test('面板类允许铺满整页', () {
      final s = applyResize(
        startSize: const Size(300, 300),
        rawDelta: const Offset(5000, 5000),
        rotation: 0,
        type: 'surface',
      );
      expect(s.width, 4096);
      expect(s.height, 4096);
    });

    test('普通控件保底不被拉成看不见的一条', () {
      final s = applyResize(
        startSize: const Size(100, 40),
        rawDelta: const Offset(-500, -500),
        rotation: 0,
        type: 'text',
      );
      expect(s.width, 40);
      expect(s.height, 20);
    });
  });

  group('撑开的盒子不影响其他几何', () {
    test('四周等量扩张，中心不变', () {
      // padded box 的中心必须仍是元件中心，
      // 否则 Transform.rotate 的旋转中心会漂移。
      const size = Size(80, 40);
      const pad = kResizeHandlePadding;
      final paddedCenter = Offset(
        (size.width + pad * 2) / 2 - pad,
        (size.height + pad * 2) / 2 - pad,
      );
      expect(paddedCenter, Offset(size.width / 2, size.height / 2));
    });

    test('连线端点基于 el.offset 与 el.size，与撑开无关', () {
      // 端点计算不读 widget 盒子，因此加 padding 不会让连线错位。
      const elOffset = Offset(100, 200);
      const size = Size(80, 40);
      const base = Offset(40, 60);
      final leftPort = Offset(
        base.dx + elOffset.dx,
        base.dy + elOffset.dy + size.height / 2,
      );
      expect(leftPort, const Offset(140, 280));
    });
  });
}
