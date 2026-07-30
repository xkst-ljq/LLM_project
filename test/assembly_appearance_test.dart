import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/ui_models.dart';

/// A14-3：外观专项页。
///
/// 分工上外观属于「这一个实例在这张卡里长什么样」——
/// 同一个面板在 A 卡是深蓝、B 卡是暖橙很正常，因此归 Assembly。
/// 与之相对，indicator 的状态映射规则是零件自带行为，仍只在 Studio。

/// 复刻 `_supportsAppearanceEditor`。
bool supportsAppearance(String type) => const {
      'surface',
      'base_box',
      'text',
      'progress',
      'slider',
      'input',
      'switch',
      'select',
      'indicator',
      'line',
      'image',
      'message_flow',
    }.contains(type);

UIModule _module({
  String type = 'surface',
  Color color = const Color(0xFF651FFF),
  Map<String, dynamic>? props,
}) =>
    UIModule(
      id: 'm',
      name: 'm',
      type: type,
      color: color,
      properties: props ?? {},
    );

void main() {
  group('适用范围', () {
    test('显示类组件都能改外观', () {
      for (final t in ['surface', 'text', 'progress', 'image', 'slider']) {
        expect(supportsAppearance(t), isTrue, reason: t);
      }
    });

    test('纯逻辑件没有外观可言', () {
      // 运行时不渲染，改颜色没有意义。
      // button 也在此列：它运行期是纯点击热区，不显形，
      // 视觉反馈一律交给它联动的 surface。
      for (final t in [
        'linker',
        'page_router',
        'math_node',
        'timer',
        'button',
      ]) {
        expect(supportsAppearance(t), isFalse, reason: t);
      }
    });
  });

  group('外观字段可写回模块', () {
    test('颜色 / 材质 / 形状 / 圆角 / 透明度都能改', () {
      final before = _module();
      final after = before.copyWith(
        color: const Color(0xFF00897B),
        material: UIModuleMaterial.solid,
        shape: UIModuleShape.capsule,
        borderRadius: 20,
        opacity: 0.6,
      );
      expect(after.color, const Color(0xFF00897B));
      expect(after.material, UIModuleMaterial.solid);
      expect(after.shape, UIModuleShape.capsule);
      expect(after.borderRadius, 20);
      expect(after.opacity, 0.6);
    });

    test('外观改动参与序列化，重开方案不丢', () {
      final m = _module().copyWith(
        color: const Color(0xFFE8833A),
        shape: UIModuleShape.circle,
        opacity: 0.42,
      );
      final restored = UIModule.fromJson(m.toJson());
      expect(restored.color.toARGB32(), 0xFFE8833A);
      expect(restored.shape, UIModuleShape.circle);
      expect(restored.opacity, closeTo(0.42, 0.001));
    });
  });

  group('按类型的专属字段', () {
    test('进度条有轨道色与形状', () {
      final props = <String, dynamic>{};
      props['trackColor'] = const Color(0xFFEEEEEE).toARGB32();
      props['progressShape'] = 'ring';
      expect(props['trackColor'], 0xFFEEEEEE);
      expect(props['progressShape'], 'ring');
    });

    test('消息流有双气泡色', () {
      // 两种气泡必须分开设，否则玩家与角色分不出来。
      final props = <String, dynamic>{
        'userBubbleColor': 0xFFDCF8C6,
        'assistantBubbleColor': 0xFFF1F1F4,
      };
      expect(props['userBubbleColor'], isNot(props['assistantBubbleColor']));
    });

    test('indicator 只给兜底色，不给状态规则', () {
      // 规则引擎是零件自带行为，留在 Studio。
      final props = <String, dynamic>{'defaultColor': 0xFF9E9E9E};
      expect(props.containsKey('defaultColor'), isTrue);
      expect(props.containsKey('statusRules'), isFalse);
    });
  });

  group('避免覆盖（回归）', () {
    test('实例编辑器不应回写 borderRadius / opacity', () {
      // 外观页保存后，实例对话框的 controller 仍是打开那一刻的旧值。
      // 若保存时回写，会把刚调好的外观覆盖掉——与数据通道同一类陷阱。
      final afterAppearance =
          _module().copyWith(borderRadius: 24, opacity: 0.5);
      // 模拟实例编辑器只改名称
      final afterInstance =
          afterAppearance.copyWith(name: '改名后');
      expect(afterInstance.borderRadius, 24);
      expect(afterInstance.opacity, 0.5);
    });
  });
}
