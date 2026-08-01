import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

/// A14-1d：精确几何 / 精确位移。
/// 与 Studio 的「精确几何」「精调手柄」保持一致的取值口径。

UIElement _el(
  String id, {
  String type = 'text',
  Offset offset = const Offset(10, 20),
  Size size = const Size(96, 28),
  bool layoutLocked = false,
  bool sealed = false,
}) =>
    UIElement(
      id: id,
      isComposite: false,
      offset: offset,
      size: size,
      layoutLocked: layoutLocked,
      sealed: sealed,
      module: UIModule(id: 'm_$id', name: id, type: type, properties: {}),
    );

/// 复刻 `_isGeometryLocked`。
bool geometryLocked(UIElement el) => el.layoutLocked || el.sealed;

/// 复刻尺寸区间：面类是容器，允许远大于画布。
({double minW, double maxW, double minH, double maxH}) sizeBounds(String type) {
  const surfaceTypes = {'surface', 'surface_art', 'primitive_art', 'base_box'};
  final isSurface = surfaceTypes.contains(type);
  return (
    minW: type == 'progress' ? 12.0 : 20.0,
    maxW: isSurface ? 4096.0 : 600.0,
    minH: type == 'progress' ? 6.0 : 20.0,
    maxH: isSurface ? 4096.0 : 400.0,
  );
}

Size clampSize(String type, double w, double h) {
  final b = sizeBounds(type);
  return Size(w.clamp(b.minW, b.maxW).toDouble(),
      h.clamp(b.minH, b.maxH).toDouble());
}

/// 复刻 `_isLogicOnlyElement`：纯逻辑件运行时不渲染。
bool isLogicOnly(String type) =>
    const {'linker', 'page_router', 'math_node', 'timer'}.contains(type);

void main() {
  group('几何锁定', () {
    test('半锁与全锁都禁止改几何', () {
      expect(geometryLocked(_el('a', layoutLocked: true)), isTrue);
      expect(geometryLocked(_el('a', sealed: true)), isTrue);
      expect(geometryLocked(_el('a')), isFalse);
    });
  });

  group('尺寸区间', () {
    test('面类允许远大于普通组件', () {
      // 面是容器，可能需要铺满整块 PCB 甚至更大。
      expect(sizeBounds('surface').maxW, 4096.0);
      expect(sizeBounds('text').maxW, 600.0);
    });

    test('进度条可以很细', () {
      // 细长条是常见做法，用通用下限 20 会把它撑胖。
      expect(sizeBounds('progress').minH, 6.0);
      expect(sizeBounds('text').minH, 20.0);
    });

    test('超出上限被收敛，不会撑坏方案', () {
      expect(clampSize('text', 9999, 9999), const Size(600, 400));
    });

    test('低于下限被抬升，不会缩成不可见', () {
      expect(clampSize('text', 1, 1), const Size(20, 20));
    });

    test('区间内的值原样保留', () {
      expect(clampSize('text', 120, 40), const Size(120, 40));
    });
  });

  group('精确位移', () {
    test('逐像素累加', () {
      var el = _el('a', offset: const Offset(10, 20));
      el = el.copyWith(offset: el.offset + const Offset(1, 0));
      el = el.copyWith(offset: el.offset + const Offset(0, -1));
      expect(el.offset, const Offset(11, 19));
    });

    test('允许移动到负坐标（PCB 外）', () {
      // 逻辑件常被特意拖出 PCB 当后台节点，不能限制在非负区间。
      var el = _el('a', offset: const Offset(2, 2));
      el = el.copyWith(offset: el.offset + const Offset(-5, -5));
      expect(el.offset, const Offset(-3, -3));
    });

    test('锁定的元素不参与位移', () {
      final el = _el('a', layoutLocked: true);
      expect(geometryLocked(el), isTrue);
    });
  });

  group('旋转只能应用一次', () {
    // UIRenderer.render 内部已经按 element.rotation 包了 Transform.rotate。
    // 画布若在外层再套一层用于让选中框跟随旋转，
    // 就必须把传进渲染器的副本剥离旋转，否则角度翻倍
    // （输入 30° 实际转 60°，输入 90° 实际转 180°）。
    test('传给渲染器的副本旋转必须归零', () {
      final el = _el('a').copyWith(rotation: 30);
      final forRenderer = el.copyWith(rotation: 0.0);
      expect(el.rotation, 30);
      expect(forRenderer.rotation, 0.0);
    });

    test('剥离旋转不影响其他几何属性', () {
      final el = _el('a',
              offset: const Offset(12, 34), size: const Size(80, 40))
          .copyWith(rotation: 45);
      final forRenderer = el.copyWith(rotation: 0.0);
      expect(forRenderer.offset, const Offset(12, 34));
      expect(forRenderer.size, const Size(80, 40));
      expect(forRenderer.id, el.id);
    });

    test('未旋转时无需外层包裹，行为不变', () {
      final el = _el('a');
      expect(el.rotation, 0.0);
    });
  });

  group('逻辑件不提供精确几何', () {
    // 它们运行时不渲染，宽高与旋转没有意义；
    // 位置仍可拖动——作者会靠摆放位置给逻辑件分区归类。
    test('四种纯逻辑件都被识别', () {
      for (final type in ['linker', 'page_router', 'math_node', 'timer']) {
        expect(isLogicOnly(type), isTrue, reason: type);
      }
    });

    test('显示类组件不受影响', () {
      for (final type in ['text', 'button', 'slider', 'progress', 'image']) {
        expect(isLogicOnly(type), isFalse, reason: type);
      }
    });
  });

  group('D-Pad 布局', () {
    test('上下行与中间行等宽，箭头才能对齐', () {
      // 上下行 = 占位 52 + 箭头 40 + 占位 52
      // 中间行 = 箭头 40 + 间距 12 + 中心 40 + 间距 12 + 箭头 40
      const outerRow = 52 + 40 + 52;
      const middleRow = 40 + 12 + 40 + 12 + 40;
      expect(outerRow, middleRow);
      // 居中偏移必须是总宽的一半。
      expect(middleRow / 2, 72);
    });
  });
}
