import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/session_state.dart';
import 'package:llm_project/models/status_bar_field.dart';
import 'package:llm_project/services/ui_engine/data_channel_prompt_builder.dart';
import 'package:llm_project/services/ui_engine/data_channel_update_engine.dart';

DataChannelPromptItem _item({
  required String label,
  String targetKind = 'status_field',
  String targetId = 'f_aff',
  String read = 'prompt',
  String write = 'suggest_delta',
  String apply = 'confirm',
  String value = '45',
}) {
  return DataChannelPromptItem(
    semanticLabel: label,
    targetKind: targetKind,
    targetId: targetId,
    llmReadPolicy: read,
    llmWritePolicy: write,
    applyPolicy: apply,
    value: value,
    rangeHint: '',
  );
}

String _reply(String body) {
  final tag = DataChannelUpdateEngine.tag;
  return '剧情正文。\n\n<$tag>\n$body\n</$tag>';
}

final _affField = StatusBarField(
  id: 'f_aff',
  name: '好感度',
  type: 'number',
  initialValue: '45',
  minValue: 0,
  maxValue: 100,
);

void main() {
  group('parse - 权限校验', () {
    test('不可写通道的建议一律拒绝', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', write: 'none')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });

    test('applyPolicy 为 never 时拒绝', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', apply: 'never')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });

    test('LLM 编造的未知语义名被丢弃', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('并不存在的字段:+99'),
        items: [_item(label: '好感度')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejectedCount, 1);
    });

    test('suggest_delta 通道拒绝绝对值赋值', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度=100'),
        items: [_item(label: '好感度', write: 'suggest_delta')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
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
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.needsConfirm.length, 1);
      final update = result.needsConfirm.single;
      expect(update.oldValue, '45');
      expect(update.newValue, '48');
      expect(update.rawSuggestion, '+3');
    });

    test('增量结果按角色卡范围 clamp', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+999'),
        items: [_item(label: '好感度')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.needsConfirm.single.newValue, '100');
    });

    test('负增量同样 clamp 到下限', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:-999'),
        items: [_item(label: '好感度')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.needsConfirm.single.newValue, '0');
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

      expect(result.needsConfirm.single.newValue, '放松');
    });

    test('值没有实际变化时不产生更新', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+0'),
        items: [_item(label: '好感度')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.isEmpty, isTrue);
    });

    test('同一项重复输出只取第一条，不叠加算账', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3\n好感度:+5'),
        items: [_item(label: '好感度')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.needsConfirm.length, 1);
      expect(result.needsConfirm.single.newValue, '48');
    });
  });

  group('parse - 应用策略分流', () {
    test('auto_low_risk 进自动应用组', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', apply: 'auto_low_risk')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.autoApply.length, 1);
      expect(result.needsConfirm, isEmpty);
    });

    test('confirm 进待确认组', () {
      final result = DataChannelUpdateEngine.parse(
        reply: _reply('好感度:+3'),
        items: [_item(label: '好感度', apply: 'confirm')],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [_affField],
      );

      expect(result.autoApply, isEmpty);
      expect(result.needsConfirm.length, 1);
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
          applyPolicy: 'confirm',
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
          applyPolicy: 'confirm',
        ),
      ]);

      expect(session.vars['心情'], '放松');
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
