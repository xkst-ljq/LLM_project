import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

void main() {
  group('MessageAction 取值', () {
    test('key 与方案参数选项完全一致', () {
      // 方案参数里的 options 是作者实际能选到的值；
      // 与枚举对不上就会出现「选了却识别不出来」的静默失效。
      final def =
          LinkerMatrixEngine.getSchemeDefinition('button_to_message_action');
      expect(def, isNotNull);
      final param = def!.params.firstWhere((p) => p.key == 'action');
      expect(param.options, MessageAction.allKeys);
    });

    test('fromKey 能还原每一个动作', () {
      for (final action in MessageAction.values) {
        expect(MessageAction.fromKey(action.key), action);
      }
    });

    test('无法识别时返回 null 而非回落默认动作', () {
      // 静默执行「重新生成」会让玩家莫名其妙丢掉一条回复。
      expect(MessageAction.fromKey('not_an_action'), isNull);
      expect(MessageAction.fromKey(''), isNull);
      expect(MessageAction.fromKey(null), isNull);
    });

    test('key 用显式字符串，不随枚举名变化', () {
      // 参数值会随角色卡序列化，重命名枚举项不该让老卡片失效。
      expect(MessageAction.continueWrite.key, 'continue');
      expect(MessageAction.versionPrev.key, 'version_prev');
      expect(MessageAction.versionNext.key, 'version_next');
    });

    test('每个动作都有面向作者的说明文字', () {
      for (final action in MessageAction.values) {
        expect(action.label, isNotEmpty, reason: action.key);
        expect(action.description, isNotEmpty, reason: action.key);
      }
    });
  });

  group('消息操作方案登记', () {
    test('已登记进方案矩阵，运行端不会静默跳过', () {
      // 漏登记时 isSchemeSelectable 判为非法，运行端直接跳过——
      // button_to_page_route 就漏过一次。
      expect(
        LinkerMatrixEngine.isSchemeSelectable('button_to_message_action'),
        isTrue,
      );
    });

    test('button → message_flow 能选到该方案', () {
      final schemes =
          LinkerMatrixEngine.getAvailableSchemes('button', 'message_flow');
      expect(
        schemes.map((s) => s.id),
        contains('button_to_message_action'),
      );
    });

    test('是脉冲型方案', () {
      final def =
          LinkerMatrixEngine.getSchemeDefinition('button_to_message_action')!;
      expect(def.isPulse, isTrue);
    });
  });

  group('方案参数缺省处理', () {
    test('action 参数声明了默认值，缺省时不会变成「按钮没反应」', () {
      final def =
          LinkerMatrixEngine.getSchemeDefinition('button_to_message_action')!;
      final param = def.params.firstWhere((p) => p.key == 'action');
      expect(param.defaultValue, isNotNull);
      // 默认值必须是合法动作，否则回落逻辑同样解析不出来。
      expect(MessageAction.fromKey(param.defaultValue.toString()), isNotNull);
    });

    test('六个动作都能从参数选项里选到，含两个方向的版本切换', () {
      final def =
          LinkerMatrixEngine.getSchemeDefinition('button_to_message_action')!;
      final options = def.params.firstWhere((p) => p.key == 'action').options!;
      expect(options, contains('version_prev'));
      expect(options, contains('version_next'));
      expect(options.length, MessageAction.values.length);
    });
  });

  group('AvatarScope', () {
    testWidgets('按来源取出对应头像', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        AvatarScope(
          characterAvatar: '/tmp/char.png',
          userAvatar: '/tmp/user.png',
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        AvatarScope.resolve(ctx, AvatarScope.sourceCharacter),
        '/tmp/char.png',
      );
      expect(
        AvatarScope.resolve(ctx, AvatarScope.sourceUser),
        '/tmp/user.png',
      );
      // 自定义来源不参与解析，由作者填的静态值决定。
      expect(AvatarScope.resolve(ctx, AvatarScope.sourceCustom), isNull);
    });

    testWidgets('头像为空时返回 null 而不是空字符串', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        AvatarScope(
          characterAvatar: '',
          userAvatar: '',
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(AvatarScope.resolve(ctx, AvatarScope.sourceCharacter), isNull);
      expect(AvatarScope.resolve(ctx, AvatarScope.sourceUser), isNull);
    });

    testWidgets('没有作用域时返回 null，不抛异常', (tester) async {
      // 编辑器预览没有这层作用域，崩掉会让整个画布白屏。
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      expect(AvatarScope.resolve(ctx, AvatarScope.sourceCharacter), isNull);
    });

    test('isDynamic 只对头像来源为真', () {
      expect(AvatarScope.isDynamic(AvatarScope.sourceCharacter), isTrue);
      expect(AvatarScope.isDynamic(AvatarScope.sourceUser), isTrue);
      expect(AvatarScope.isDynamic(AvatarScope.sourceCustom), isFalse);
      expect(AvatarScope.isDynamic(null), isFalse);
    });
  });
}
