import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/ui_assembly_info.dart';

void main() {
  group('按 mode 的默认画布尺寸', () {
    test('常驻 UI 是小而扁的挂件尺寸', () {
      final size = UIAssemblyInfo.defaultPcbSizeFor('extra_sticky');
      expect(size.width, 300);
      expect(size.height, 120);
      // 挂件不该占满屏宽，否则作者会按错误比例摆元件。
      expect(size.width, lessThan(UIAssemblyInfo.defaultPcbWidth));
    });

    test('伴生 UI 宽度接近气泡', () {
      final size = UIAssemblyInfo.defaultPcbSizeFor('extra_companion');
      expect(size.width, 320);
      expect(size.height, 200);
    });

    test('全屏类维持 360x800', () {
      for (final mode in ['opening', 'scene']) {
        final size = UIAssemblyInfo.defaultPcbSizeFor(mode);
        expect(size.width, 360, reason: mode);
        expect(size.height, 800, reason: mode);
      }
    });

    test('未知 mode 回落全屏尺寸', () {
      final size = UIAssemblyInfo.defaultPcbSizeFor('unknown');
      expect(size.width, UIAssemblyInfo.defaultPcbWidth);
    });
  });

  group('pcbWidth 持久化', () {
    test('宽度参与序列化往返', () {
      final info = UIAssemblyInfo(
        id: 'ui_1',
        mode: 'extra_sticky',
        pcbWidth: 280,
        pcbHeight: 140,
      );
      final restored = UIAssemblyInfo.fromJsonString(info.toJsonString());
      expect(restored.pcbWidth, 280);
      expect(restored.pcbHeight, 140);
    });

    test('缺少 pcbWidth 的数据回落默认宽度', () {
      // 开发阶段的旧数据不保证带该字段，不能因此崩溃或变成 0 宽。
      final restored = UIAssemblyInfo.fromJson({
        'id': 'ui_old',
        'mode': 'extra_sticky',
        'pcbHeight': 800,
      });
      expect(restored.pcbWidth, UIAssemblyInfo.defaultPcbWidth);
    });

    test('默认构造使用基准宽度', () {
      expect(UIAssemblyInfo(id: 'x').pcbWidth, UIAssemblyInfo.defaultPcbWidth);
    });
  });

  group('尺寸范围常量', () {
    test('宽度范围允许做窄挂件也允许超出屏宽', () {
      // 超宽由运行时等比缩小兜底，不限制作者。
      expect(UIAssemblyInfo.minPcbWidth, lessThanOrEqualTo(120));
      expect(UIAssemblyInfo.maxPcbWidth, greaterThanOrEqualTo(600));
    });

    test('各 mode 默认尺寸都落在允许范围内', () {
      for (final mode in [
        'extra_sticky',
        'extra_companion',
        'opening',
        'scene',
      ]) {
        final size = UIAssemblyInfo.defaultPcbSizeFor(mode);
        expect(size.width, greaterThanOrEqualTo(UIAssemblyInfo.minPcbWidth),
            reason: mode);
        expect(size.width, lessThanOrEqualTo(UIAssemblyInfo.maxPcbWidth),
            reason: mode);
        expect(size.height, greaterThanOrEqualTo(UIAssemblyInfo.minPcbHeight),
            reason: mode);
        expect(size.height, lessThanOrEqualTo(UIAssemblyInfo.maxPcbHeight),
            reason: mode);
      }
    });
  });
}
