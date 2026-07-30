import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/ui_assembly_info.dart';

/// A14-5：PCB 自定义。
///
/// 补的是一个真缺口：`pcbColorValue` 与圆角这两个字段
/// 数据结构、序列化、渲染全都齐了，但全局没有任何赋值点，
/// 只在初始化时读一次——PCB 永远是白色圆角，作者根本改不了。
///
/// 同时把圆角从布尔 `pcbRounded`（只能 20 或 0）升级为
/// 数值 `pcbRadius`（0~40），旧卡自动迁移。

void main() {
  group('圆角字段迁移', () {
    test('旧卡 pcbRounded=true 迁移为默认半径', () {
      final info = UIAssemblyInfo.fromJson({
        'id': 'a',
        'pcbRounded': true,
      });
      expect(info.pcbRadius, UIAssemblyInfo.defaultPcbRadius);
      // 默认值必须与早期布尔 true 的观感一致，否则旧卡打开就变样。
      expect(info.pcbRadius, 20.0);
    });

    test('旧卡 pcbRounded=false 迁移为直角', () {
      final info = UIAssemblyInfo.fromJson({
        'id': 'a',
        'pcbRounded': false,
      });
      expect(info.pcbRadius, 0.0);
    });

    test('旧卡完全没有圆角字段时按圆角处理', () {
      // 与迁移前 `json['pcbRounded'] != false` 的行为保持一致。
      final info = UIAssemblyInfo.fromJson({'id': 'a'});
      expect(info.pcbRadius, UIAssemblyInfo.defaultPcbRadius);
    });

    test('新字段优先于旧布尔', () {
      // 两个字段并存时（新版写出的卡）必须以数值为准，
      // 否则「微圆角 8」会被布尔的 20 覆盖掉。
      final info = UIAssemblyInfo.fromJson({
        'id': 'a',
        'pcbRadius': 8.0,
        'pcbRounded': true,
      });
      expect(info.pcbRadius, 8.0);
    });

    test('超范围的半径会被夹取', () {
      expect(
        UIAssemblyInfo.fromJson({'id': 'a', 'pcbRadius': 999.0}).pcbRadius,
        UIAssemblyInfo.kMaxPcbRadius,
      );
      expect(
        UIAssemblyInfo.fromJson({'id': 'a', 'pcbRadius': -5.0}).pcbRadius,
        0.0,
      );
    });
  });

  group('序列化', () {
    test('写出数值字段，同时保留布尔供旧版本读取', () {
      final info = UIAssemblyInfo(id: 'a', pcbRadius: 12.0);
      final json = info.toJson();
      expect(json['pcbRadius'], 12.0);
      // 老版本读到新卡时仍能得到合理形态，不会变成直角。
      expect(json['pcbRounded'], isTrue);
    });

    test('直角时布尔写 false', () {
      final json = UIAssemblyInfo(id: 'a', pcbRadius: 0.0).toJson();
      expect(json['pcbRounded'], isFalse);
    });

    test('往返不丢精度', () {
      final before = UIAssemblyInfo(
        id: 'a',
        pcbRadius: 7.0,
        pcbColorValue: 0xFF2979FF,
        pcbWidth: 300,
        pcbHeight: 640,
      );
      final after = UIAssemblyInfo.fromJson(before.toJson());
      expect(after.pcbRadius, 7.0);
      expect(after.pcbColorValue, 0xFF2979FF);
      expect(after.pcbWidth, 300);
      expect(after.pcbHeight, 640);
    });
  });

  group('尺寸输入的夹取', () {
    // 复刻面板保存时的处理：非法输入保留原值，合法输入按 mode 夹取。
    double clampWidth(String text, double current, String mode) {
      final parsed = double.tryParse(text.trim()) ?? current;
      return parsed
          .clamp(
            UIAssemblyInfo.minPcbWidth,
            UIAssemblyInfo.maxPcbWidthFor(mode),
          )
          .toDouble();
    }

    test('空输入保留原值', () {
      // 作者手滑清空输入框不该让辛苦拖出来的画布跳回默认尺寸。
      expect(clampWidth('', 333, 'extra'), 333);
      expect(clampWidth('  ', 333, 'extra'), 333);
    });

    test('非数字保留原值', () {
      expect(clampWidth('abc', 333, 'extra'), 333);
    });

    test('伴生模式的宽度上限更窄', () {
      // 伴生内嵌在消息气泡里，超出会被运行时等比缩小。
      expect(
        clampWidth('600', 300, 'extra_companion'),
        UIAssemblyInfo.companionMaxPcbWidth,
      );
      expect(clampWidth('600', 300, 'extra'), 600);
    });

    test('低于下限会被抬到下限', () {
      expect(clampWidth('10', 300, 'extra'), UIAssemblyInfo.minPcbWidth);
    });
  });
}
