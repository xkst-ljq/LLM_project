import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/session_state.dart';
import 'package:llm_project/services/ui_engine/data_channel_prompt_builder.dart';
import 'package:llm_project/services/ui_engine/data_channel_update_engine.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

DataChannelPromptItem _item({
  required String label,
  // 状态字段已交由 StatusBarEngine 解析 <状态变化>，
  // 本引擎只负责会话变量，因此默认用 session_var。
  String targetKind = 'session_var',
  String targetId = '',
  String read = 'prompt',
  String write = 'suggest_delta',
  String notify = 'silent',
  String value = '45',
}) {
  return DataChannelPromptItem(
    semanticLabel: label,
    targetKind: targetKind,
    targetId: targetId,
    llmReadPolicy: read,
    llmWritePolicy: write,
    notifyStyle: notify,
    value: value,
    rangeHint: '',
  );
}

String _reply(String body) {
  final tag = DataChannelUpdateEngine.tag;
  return '剧情正文。\n\n<$tag>\n$body\n</$tag>';
}


void main() {
  group('parse - 权限校验', () {
    test('不可写通道的建议一律拒绝', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', write: 'none')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });

    test('LLM 编造的未知语义名被丢弃', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('并不存在的字段:+99'),
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });

    test('suggest_delta 通道拒绝绝对值赋值', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度=100'),
        items: [_item(label: '好感度', write: 'suggest_delta')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });
  });

  group('parse - 算账', () {
    test('数值增量由引擎计算', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.length, 1);
      final update = result.applied.single;
      expect(update.oldValue, '45');
      expect(update.newValue, '48');
      expect(update.rawSuggestion, '+3');
    });

    test('状态字段交由状态栏解析，本引擎不重复算账', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [
          _item(label: '好感度', targetKind: 'status_field', targetId: 'f_aff'),
        ],
        session: SessionState(vars: {'好感度': '45'}),
      );
      // 同一字段被两套引擎解析会导致重复算账。
      expect(result.isEmpty, isTrue);
    });

    test('suggest_replace 直接替换文本型会话变量', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('心情=放松'),
        items: [
          _item(
            label: '心情',
            targetKind: 'session_var',
            targetId: '',
            write: 'suggest_replace',
          ),
        ],
        session: SessionState(vars: {'心情': '平静'}),
      );

      expect(result.applied.single.newValue, '放松');
    });

    test('值没有实际变化时不产生更新', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+0'),
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.isEmpty, isTrue);
    });

    test('同一项重复输出只取第一条，不叠加算账', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3\n好感度:+5'),
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.length, 1);
      expect(result.applied.single.newValue, '48');
    });
  });

  group('parse - 应用策略分流', () {
    test('silent 照常写入，但不进通知列表', () {
      // 值一律写入——「拒绝」的语义已废除，
      // notifyStyle 只决定要不要告诉玩家。
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', notify: 'silent')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.length, 1);
      expect(result.needsNotify, isEmpty);
    });

    test('toast / dialog 进通知列表', () {
      for (final style in ['toast', 'dialog']) {
        final result = DataChannelUpdateEngine.parse(
          reply: _reply('好感度:+3'),
          items: [_item(label: '好感度', notify: style)],
          session: SessionState(vars: {'好感度': '45'}),
        );

        expect(result.applied.length, 1, reason: style);
        expect(result.needsNotify.length, 1, reason: style);
        expect(result.needsNotify.single.notifyStyle, style);
      }
    });
  });

  group('apply', () {
    test('状态字段写入 statusValues', () {
      final session = SessionState(statusValues: {'f_aff': '45'});
      final changed = DataChannelUpdateEngine.apply(session, [
        const DataChannelUpdate(
          semanticLabel: '好感度',
          targetKind: 'status_field',
          targetId: 'f_aff',
          oldValue: '45',
          newValue: '48',
          rawSuggestion: '+3',
          notifyStyle: 'silent',
        ),
      ]);

      expect(changed, isTrue);
      expect(session.statusValues['f_aff'], '48');
    });

    test('会话变量按语义名写入 vars', () {
      final session = SessionState();
      DataChannelUpdateEngine.apply(session, [
        const DataChannelUpdate(
          semanticLabel: '心情',
          targetKind: 'session_var',
          targetId: '',
          oldValue: '',
          newValue: '放松',
          rawSuggestion: '放松',
          notifyStyle: 'silent',
        ),
      ]);

      expect(session.vars['心情'], '放松');
    });
  });

  group('parse - 模型格式容错', () {
    test('标签块被代码围栏包裹时仍能解析', () {
      final tag = DataChannelUpdateEngine.tag;
      final reply = '正文。\n\n```\n<$tag>\n好感度:+3\n</$tag>\n```';
      final result = DataChannelUpdateEngine.parse(
        reply: reply,
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.single.newValue, '48');
    });

    test('全角尖括号仍能解析', () {
      final tag = DataChannelUpdateEngine.tag;
      final reply = '正文。\n＜$tag＞\n好感度:+3\n＜/$tag＞';
      final result = DataChannelUpdateEngine.parse(
        reply: reply,
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.single.newValue, '48');
    });

    test('标签内多余空格仍能解析', () {
      final tag = DataChannelUpdateEngine.tag;
      final reply = '正文。\n< $tag >\n好感度:+3\n</ $tag >';
      final result = DataChannelUpdateEngine.parse(
        reply: reply,
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );

      expect(result.applied.single.newValue, '48');
    });

    test('容错格式的标记同样能从展示文本剥离', () {
      final tag = DataChannelUpdateEngine.tag;
      final stripped = DataChannelUpdateEngine.stripFromReply(
        '正文。\n\n```\n<$tag>\n好感度:+3\n</$tag>\n```',
      );
      expect(stripped, isNot(contains(tag)));
      expect(stripped, contains('正文。'));
    });
  });

  group('buildUpdateFormatInstruction', () {
    test('无可写通道时不产生 PHI 约束', () {
      final out = DataChannelPromptBuilder.buildUpdateFormatInstruction([
        _item(label: '好感度', write: 'none'),
      ]);
      expect(out, isEmpty);
    });

    test('可写通道生成末尾强约束，含标签与格式', () {
      final out = DataChannelPromptBuilder.buildUpdateFormatInstruction([
        _item(label: '好感度', write: 'suggest_delta'),
      ]);
      expect(out, contains('每回合必须输出结算块'));
      expect(out, contains('<${DataChannelUpdateEngine.tag}>'));
      // 这是格式占位符而非示例值，保留是为了让模型知道怎么写。
      expect(out, contains('好感度:+N'));
    });
  });

  group('空标签块', () {
    test('模型输出空标签时安全返回，不产生更新也不报错', () {
      final tag = DataChannelUpdateEngine.tag;
      final result = DataChannelUpdateEngine.parse(
        reply: '正文。\n<$tag>\n</$tag>',
        items: [_item(label: '好感度')],
        session: SessionState(vars: {'好感度': '45'}),
      );
      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 0);
    });

    test('空标签同样从展示文本剥离干净', () {
      final tag = DataChannelUpdateEngine.tag;
      final stripped =
          DataChannelUpdateEngine.stripFromReply('正文。\n<$tag>\n</$tag>');
      expect(stripped, '正文。');
    });
  });

  group('stripFromReply', () {
    test('展示文本不含技术标记', () {
      final stripped =
          DataChannelUpdateEngine.stripFromReply(_reply('好感度:+3'));
      expect(stripped, '剧情正文。');
      expect(stripped, isNot(contains(DataChannelUpdateEngine.tag)));
    });

    test('无标记时原样返回', () {
      expect(
        DataChannelUpdateEngine.stripFromReply('普通回复'),
        '普通回复',
      );
    });
  });
}
