import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/pages/prompt_preview_page.dart';

PromptPreviewData _data(List<Map<String, String>> messages) {
  return PromptPreviewData(
    userTurnCount: 1,
    injectedSummary: false,
    injectedFullDetail: false,
    estimatedTokens: 0,
    systemPrompt: 'SYS',
    messages: messages,
  );
}

void main() {
  group('历史后注入拆分', () {
    test('末尾连续的 system 消息被识别为 PHI', () {
      final data = _data([
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好'},
        {'role': 'system', 'content': 'PHI-1'},
        {'role': 'system', 'content': 'PHI-2'},
      ]);

      expect(data.postHistorySystemMessages.length, 2);
      expect(data.postHistorySystemMessages.first['content'], 'PHI-1');
      expect(data.historyMessages.length, 2);
    });

    test('没有历史后注入时全部算作对话历史', () {
      final data = _data([
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好'},
      ]);

      expect(data.postHistorySystemMessages, isEmpty);
      expect(data.historyMessages.length, 2);
    });

    test('对话中间的 system 消息不会被误判为 PHI', () {
      final data = _data([
        {'role': 'system', 'content': '中间的'},
        {'role': 'user', 'content': '你好'},
      ]);

      expect(data.postHistorySystemMessages, isEmpty);
      expect(data.historyMessages.length, 2);
    });

    test('消息为空时不崩溃', () {
      final data = _data([]);
      expect(data.postHistorySystemMessages, isEmpty);
      expect(data.historyMessages, isEmpty);
    });
  });

  group('toFullText', () {
    test('完整文本包含 PHI 内容，便于复制核对', () {
      final data = _data([
        {'role': 'user', 'content': '你好'},
        {'role': 'system', 'content': '状态结算格式约束'},
      ]);

      final text = data.toFullText();
      expect(text, contains('SYS'));
      expect(text, contains('对话历史'));
      expect(text, contains('历史后注入'));
      // 关键：PHI 内容必须出现，否则作者无法核对真实请求。
      expect(text, contains('状态结算格式约束'));
    });
  });
}
