import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

UIModule _module(String type, {bool keyAction = false, bool sends = false}) {
  return UIModule(
    id: 'm',
    name: type,
    type: type,
    properties: {
      if (keyAction) UISemanticRole.propKey: true,
      if (sends) UISemanticRole.sendKey: true,
    },
  );
}

void main() {
  group('scene 的关键职责语义', () {
    test('scene 要求标记，且缺失时拦截', () {
      // 缺「打开聊天设置」时不接管：否则玩家进不了设置页，
      // 连重置对话都做不到，等于被锁死。
      expect(UISemanticRole.requiresKeyAction('scene'), isTrue);
      expect(UISemanticRole.blocksWithoutKeyAction('scene'), isTrue);
    });

    test('scene 的职责名是打开聊天设置，不是退出', () {
      // scene 底层无法关闭，只能删除 UI 方案。
      expect(UISemanticRole.actionLabelOf('scene'), '打开聊天设置');
      expect(UISemanticRole.missingHintOf('scene'), contains('无法打开'));
    });
  });

  group('发送消息标记', () {
    test('仅 scene 支持', () {
      // 其余 mode 的原生输入框仍在，不需要这个能力。
      expect(UISemanticRole.supportsSendMessage('scene'), isTrue);
      for (final mode in ['opening', 'extra_sticky', 'extra_companion']) {
        expect(
          UISemanticRole.supportsSendMessage(mode),
          isFalse,
          reason: mode,
        );
      }
    });

    test('只有 button 与 input 可标记', () {
      expect(UISemanticRole.canMarkSend('button'), isTrue);
      expect(UISemanticRole.canMarkSend('input'), isTrue);
      for (final type in ['text', 'slider', 'progress', 'surface']) {
        expect(UISemanticRole.canMarkSend(type), isFalse, reason: type);
      }
    });

    test('未标记时不触发发送', () {
      expect(UISemanticRole.sendsMessage(_module('button')), isFalse);
    });

    test('标记后可读出', () {
      expect(
        UISemanticRole.sendsMessage(_module('button', sends: true)),
        isTrue,
      );
    });

    test('module 为空时安全返回', () {
      expect(UISemanticRole.sendsMessage(null), isFalse);
    });
  });

  group('两种标记互相独立', () {
    test('同一按钮可同时承担两种职责', () {
      // 虽然实践中通常分开放，但机制上不应互斥。
      final both = _module('button', keyAction: true, sends: true);
      expect(UISemanticRole.isKeyAction(both), isTrue);
      expect(UISemanticRole.sendsMessage(both), isTrue);
    });

    test('只标发送时不触发关键职责', () {
      final sendOnly = _module('button', sends: true);
      expect(UISemanticRole.isKeyAction(sendOnly), isFalse);
      expect(UISemanticRole.sendsMessage(sendOnly), isTrue);
    });

    test('两种标记使用不同的属性键', () {
      expect(UISemanticRole.propKey, isNot(UISemanticRole.sendKey));
    });
  });

  group('标记持久化', () {
    test('发送标记随实例序列化', () {
      final module = _module('input', sends: true);
      final restored = UIModule.fromJson(module.toJson());
      expect(UISemanticRole.sendsMessage(restored), isTrue);
    });

    test('未标记时不写入冗余字段', () {
      final module = _module('button');
      expect(module.properties.containsKey(UISemanticRole.sendKey), isFalse);
    });
  });
}
