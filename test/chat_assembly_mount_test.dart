import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/character_meta.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';
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

  group('挂件默认不吃页面手势', () {
    test('ChatAssemblyMount 默认关闭整页滑动手势', () {
      // 挂件覆盖在聊天内容上，开启会抢走内部 slider 的拖动，
      // 且挂件通常只有一页，页面切换没有意义。
      final mount = ChatAssemblyMount(
        meta: CharacterMeta(),
        mode: 'extra_sticky',
        sessionState: SessionState(),
      );
      expect(mount.enablePageGestures, isFalse);
    });
  });

  group('开场白一次性状态', () {
    test('默认未确认', () {
      expect(OpeningGreetingState.isDismissed(SessionState()), isFalse);
    });

    test('标记后变为已确认', () {
      final session = SessionState();
      expect(OpeningGreetingState.markDismissed(session), isTrue);
      expect(OpeningGreetingState.isDismissed(session), isTrue);
    });

    test('重复标记返回 false，避免无谓落盘', () {
      final session = SessionState();
      OpeningGreetingState.markDismissed(session);
      expect(OpeningGreetingState.markDismissed(session), isFalse);
    });

    test('状态随会话副本序列化，重启后不再弹出', () {
      final session = SessionState();
      OpeningGreetingState.markDismissed(session);
      final restored = SessionState.fromJsonString(session.toJsonString());
      expect(OpeningGreetingState.isDismissed(restored), isTrue);
    });

    test('新会话副本恢复为未确认（清空记录后重新出现）', () {
      expect(OpeningGreetingState.isDismissed(SessionState()), isFalse);
    });
  });

  group('canRun 准入', () {
    test('开场白缺少确认按钮时不允许运行', () {
      // 没有出口按钮会把玩家卡在全屏遮罩后面。
      final meta = _meta([_assemblyJson(id: 'a', mode: 'opening')]);
      expect(ChatAssemblyMount.canRun(meta, 'opening'), isFalse);
    });

    test('场景 UI 同样受限', () {
      final meta = _meta([_assemblyJson(id: 'a', mode: 'scene')]);
      expect(ChatAssemblyMount.canRun(meta, 'scene'), isFalse);
    });

    test('常驻 UI 缺标记仍可运行（有内置兜底按钮）', () {
      final meta = _meta([_assemblyJson(id: 'a', mode: 'extra_sticky')]);
      expect(ChatAssemblyMount.canRun(meta, 'extra_sticky'), isTrue);
    });

    test('伴生 UI 不要求标记', () {
      final meta = _meta([_assemblyJson(id: 'a', mode: 'extra_companion')]);
      expect(ChatAssemblyMount.canRun(meta, 'extra_companion'), isTrue);
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
