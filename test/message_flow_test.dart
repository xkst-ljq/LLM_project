import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/ui_engine/message_flow_scope.dart';

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
