import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/character_meta.dart';
import 'package:llm_project/models/ui_assembly_info.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_project/widgets/chat_assembly_mount.dart';

String _assemblyJson({
  required String id,
  required String mode,
  double width = 300,
  double height = 120,
  bool withContent = true,
}) {
  final page = AssemblyPage(
    id: 'p1',
    name: '主页',
    type: 'base',
    elements: withContent
        ? [
            UIElement(
              id: 'e1',
              isComposite: false,
              offset: Offset.zero,
              size: const Size(100, 40),
              module: UIModule(
                id: 'm1',
                name: 'text',
                type: 'text',
                properties: const {'text': '好感度'},
              ),
            ),
          ]
        : const [],
  );

  return UIAssemblyInfo(
    id: id,
    mode: mode,
    pcbWidth: width,
    pcbHeight: height,
    pagesJson: jsonEncode([page.toJson()]),
  ).toJsonString();
}

CharacterMeta _meta(List<String> assemblies) =>
    CharacterMeta(uiAssemblies: assemblies);

void main() {
  group('resolveAssembly', () {
    test('按 mode 取出对应方案', () {
      final meta = _meta([
        _assemblyJson(id: 'a', mode: 'opening'),
        _assemblyJson(id: 'b', mode: 'extra_sticky'),
      ]);

      final info = ChatAssemblyMount.resolveAssembly(meta, 'extra_sticky');
      expect(info, isNotNull);
      expect(info!.id, 'b');
    });

    test('没有对应 mode 时返回 null', () {
      final meta = _meta([_assemblyJson(id: 'a', mode: 'opening')]);
      expect(
        ChatAssemblyMount.resolveAssembly(meta, 'extra_sticky'),
        isNull,
      );
    });

    test('空方案不挂载，避免出现一块空白', () {
      final meta = _meta([
        _assemblyJson(id: 'a', mode: 'extra_sticky', withContent: false),
      ]);
      expect(
        ChatAssemblyMount.resolveAssembly(meta, 'extra_sticky'),
        isNull,
      );
    });

    test('损坏数据被跳过而不是崩溃', () {
      final meta = _meta([
        'not-json',
        _assemblyJson(id: 'ok', mode: 'extra_sticky'),
      ]);
      final info = ChatAssemblyMount.resolveAssembly(meta, 'extra_sticky');
      expect(info?.id, 'ok');
    });

    test('没有任何 UI 方案时安全返回', () {
      expect(ChatAssemblyMount.resolveAssembly(_meta([]), 'extra_sticky'),
          isNull);
    });
  });

  group('hasAssembly', () {
    test('与 resolveAssembly 结果一致', () {
      final meta = _meta([_assemblyJson(id: 'a', mode: 'extra_sticky')]);
      expect(ChatAssemblyMount.hasAssembly(meta, 'extra_sticky'), isTrue);
      expect(ChatAssemblyMount.hasAssembly(meta, 'scene'), isFalse);
    });
  });

  group('assemblyDesignSize', () {
    test('返回该方案的设计尺寸', () {
      final meta = _meta([
        _assemblyJson(
            id: 'a', mode: 'extra_sticky', width: 280, height: 140),
      ]);
      expect(assemblyDesignSize(meta, 'extra_sticky'), const Size(280, 140));
    });

    test('超出允许范围的尺寸被 clamp', () {
      final meta = _meta([
        _assemblyJson(id: 'a', mode: 'extra_sticky', width: 9999, height: 1),
      ]);
      final size = assemblyDesignSize(meta, 'extra_sticky')!;
      expect(size.width, UIAssemblyInfo.maxPcbWidth);
      expect(size.height, UIAssemblyInfo.minPcbHeight);
    });

    test('无方案时返回 null', () {
      expect(assemblyDesignSize(_meta([]), 'extra_sticky'), isNull);
    });
  });
}
