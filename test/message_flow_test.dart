import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/message_flow_scope.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

void main() {
  group('FlowMessage', () {
    test('按 role 区分左右', () {
      expect(const FlowMessage(role: 'user', content: 'a').isUser, isTrue);
      expect(
        const FlowMessage(role: 'assistant', content: 'a').isUser,
        isFalse,
      );
    });
  });

  group('示例消息', () {
    test('四句、玩家与角色各两句', () {
      // 单看一两句分不出气泡样式差异，四句才能判断
      // 左右对齐、颜色对比与换行效果。
      expect(kMessageFlowSampleMessages.length, 4);
      expect(kMessageFlowSampleMessages.where((m) => m.isUser).length, 2);
      expect(kMessageFlowSampleMessages.where((m) => !m.isUser).length, 2);
    });

    test('交替出现，便于观察左右对齐', () {
      final roles = kMessageFlowSampleMessages.map((m) => m.isUser).toList();
      for (var i = 1; i < roles.length; i++) {
        expect(roles[i], isNot(roles[i - 1]), reason: '第 $i 句应与上一句身份相反');
      }
    });

    test('每句都标注了「示例」与身份', () {
      // 作者必须一眼知道这是测试内容、且分得清谁是谁。
      for (final m in kMessageFlowSampleMessages) {
        expect(m.content, contains('示例'));
        expect(m.content, contains(m.isUser ? '玩家' : '角色'));
      }
    });
  });

  group('isLive 区分预览与真实对话', () {
    // 不能靠「列表是否为空」推断：运行时预览与
    // 「真实聊天但历史为空」都是空列表，前者该显示示例，
    // 后者该显示「暂无消息」。
    bool useSample(MessageFlowScope? scope, {bool isStudio = false}) =>
        isStudio || scope == null || !scope.isLive;

    test('编辑器无作用域 → 用示例', () {
      expect(useSample(null, isStudio: true), isTrue);
    });

    test('预览提供空列表且 isLive=false → 用示例', () {
      final scope = MessageFlowScope(
        messages: const [],
        child: const SizedBox(),
      );
      expect(useSample(scope), isTrue);
    });

    test('真实聊天历史为空 → 不用示例，显示暂无消息', () {
      final scope = MessageFlowScope(
        messages: const [],
        isLive: true,
        child: const SizedBox(),
      );
      expect(useSample(scope), isFalse);
    });

    test('真实聊天有历史 → 用真实内容', () {
      final scope = MessageFlowScope(
        messages: const [FlowMessage(role: 'user', content: '你好')],
        isLive: true,
        child: const SizedBox(),
      );
      expect(useSample(scope), isFalse);
    });

    test('isLive 变化会触发通知', () {
      final a = MessageFlowScope(
          messages: const [], isLive: false, child: const SizedBox());
      final b = MessageFlowScope(
          messages: const [], isLive: true, child: const SizedBox());
      expect(b.updateShouldNotify(a), isTrue);
    });
  });

  group('MessageFlowScope 更新通知', () {
    const a = FlowMessage(role: 'user', content: 'hello');
    const b = FlowMessage(role: 'assistant', content: 'hi');

    MessageFlowScope scope(List<FlowMessage> m) =>
        MessageFlowScope(messages: m, child: const SizedBox());

    test('消息数量变化时通知', () {
      expect(
        scope([a, b]).updateShouldNotify(scope([a])),
        isTrue,
      );
    });

    test('最后一条内容变化时通知（流式追加）', () {
      // 流式输出每个 chunk 都在改最后一条，必须逐帧刷新。
      expect(
        scope([a, const FlowMessage(role: 'assistant', content: 'hi there')])
            .updateShouldNotify(scope([a, b])),
        isTrue,
      );
    });

    test('内容完全相同时不通知，避免无谓重建', () {
      expect(
        scope([a, b]).updateShouldNotify(scope([a, b])),
        isFalse,
      );
    });

    test('空列表安全处理', () {
      expect(scope([]).updateShouldNotify(scope([])), isFalse);
    });
  });

  group('历史条数限制语义', () {
    // 复刻渲染侧的裁剪规则：limit<=0 表示不限制。
    List<FlowMessage> applyLimit(List<FlowMessage> all, int limit) {
      if (limit > 0 && all.length > limit) {
        return all.sublist(all.length - limit);
      }
      return all;
    }

    final history = List.generate(
      10,
      (i) => FlowMessage(role: i.isEven ? 'user' : 'assistant', content: '$i'),
    );

    test('limit 为 0 时显示全部', () {
      expect(applyLimit(history, 0).length, 10);
    });

    test('limit 大于总数时显示全部', () {
      expect(applyLimit(history, 99).length, 10);
    });

    test('limit 生效时保留最近 N 条而非最早', () {
      final result = applyLimit(history, 3);
      expect(result.length, 3);
      expect(result.first.content, '7');
      expect(result.last.content, '9');
    });
  });

  group('角色过滤', () {
    final history = [
      const FlowMessage(role: 'user', content: 'u1'),
      const FlowMessage(role: 'assistant', content: 'a1'),
      const FlowMessage(role: 'user', content: 'u2'),
    ];

    List<FlowMessage> filter(bool showUser, bool showAssistant) {
      return history
          .where((m) => m.isUser ? showUser : showAssistant)
          .toList();
    }

    test('可只显示角色消息（旁白式场景）', () {
      final result = filter(false, true);
      expect(result.length, 1);
      expect(result.single.content, 'a1');
    });

    test('可只显示玩家消息', () {
      expect(filter(true, false).length, 2);
    });

    test('两者都关时为空', () {
      expect(filter(false, false), isEmpty);
    });
  });
}
