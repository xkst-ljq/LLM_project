import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/character_meta.dart';
import 'package:llm_project/models/ui_assembly_info.dart';
import 'package:llm_project/widgets/chat_assembly_mount.dart';

/// A10-3：伴生 UI（extra_companion）。
///
/// 伴生内嵌在 AI 消息气泡最下方，因此宽度必须塞得进气泡；
/// 且与 scene 互斥——scene 不渲染原生消息列表，伴生没有宿主。
void main() {
  group('伴生宽度上限', () {
    test('伴生比其余 mode 更窄', () {
      expect(
        UIAssemblyInfo.maxPcbWidthFor('extra_companion'),
        UIAssemblyInfo.companionMaxPcbWidth,
      );
      expect(
        UIAssemblyInfo.maxPcbWidthFor('extra_companion'),
        lessThan(UIAssemblyInfo.maxPcbWidth),
      );
    });

    test('其余 mode 沿用通用上限', () {
      for (final mode in ['opening', 'scene', 'extra_sticky', 'unknown']) {
        expect(
          UIAssemblyInfo.maxPcbWidthFor(mode),
          UIAssemblyInfo.maxPcbWidth,
          reason: mode,
        );
      }
    });

    test('上限与气泡可显示宽度一致', () {
      // 气泡宽 = 屏宽 * 0.7 - 20，再扣掉左右各 10 的内边距。
      // 以设计基准宽 360 折算：360 * 0.7 - 20 - 20 = 212。
      expect(
        UIAssemblyInfo.companionMaxPcbWidth,
        closeTo(UIAssemblyInfo.defaultPcbWidth * 0.7 - 40, 0.001),
      );
    });

    test('默认画布宽度不超过上限', () {
      final size = UIAssemblyInfo.defaultPcbSizeFor('extra_companion');
      expect(size.width, lessThanOrEqualTo(UIAssemblyInfo.companionMaxPcbWidth));
      // 高度不做多大限制：内容长了由气泡撑高，随聊天列表滚动。
      expect(size.height, 200);
    });

    test('超限的旧数据在挂载时被收进上限内', () {
      // 宽度约束是后加的，先前存下的伴生方案可能超宽。
      final info = UIAssemblyInfo(
        id: 'ui_c',
        mode: 'extra_companion',
        pcbWidth: 500,
        pcbHeight: 200,
        elementsJson: '[{"id":"e1"}]',
      );
      final meta = CharacterMeta(uiAssemblies: [info.toJsonString()]);
      final size = assemblyDesignSize(meta, 'extra_companion');
      expect(size, isNotNull);
      expect(size!.width, UIAssemblyInfo.companionMaxPcbWidth);
    });
  });

  group('关键职责标记', () {
    test('伴生不要求关键职责，缺标记也能运行', () {
      // 它嵌在消息气泡里，没有需要主动退出的状态，
      // 给它加折叠语义只是徒增作者负担。
      final info = UIAssemblyInfo(
        id: 'ui_c',
        mode: 'extra_companion',
        elementsJson: '[{"id":"e1"}]',
      );
      final meta = CharacterMeta(uiAssemblies: [info.toJsonString()]);
      expect(ChatAssemblyMount.hasAssembly(meta, 'extra_companion'), isTrue);
      expect(ChatAssemblyMount.hasKeyAction(meta, 'extra_companion'), isFalse);
      expect(ChatAssemblyMount.canRun(meta, 'extra_companion'), isTrue);
    });
  });

  group('与 scene 互斥', () {
    UIAssemblyInfo make(String mode) => UIAssemblyInfo(
          id: 'ui_$mode',
          mode: mode,
          elementsJson: '[{"id":"e1"}]',
        );

    test('同时存在时两者都能被解析出来（数据层不做删除）', () {
      // 互斥在新建入口拦截，不在数据层强制——
      // 已有的卡片不该因为规则变化而被静默删掉方案。
      final meta = CharacterMeta(uiAssemblies: [
        make('scene').toJsonString(),
        make('extra_companion').toJsonString(),
      ]);
      expect(ChatAssemblyMount.hasAssembly(meta, 'scene'), isTrue);
      expect(ChatAssemblyMount.hasAssembly(meta, 'extra_companion'), isTrue);
    });
  });
}
