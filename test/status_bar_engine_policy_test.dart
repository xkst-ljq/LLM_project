import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/status_bar_field.dart';
import 'package:llm_project/services/status_bar_engine.dart';

final _fields = [
  StatusBarField(
    id: 'f_aff',
    name: '好感度',
    type: 'number',
    initialValue: '0',
    minValue: 0,
    maxValue: 100,
  ),
  StatusBarField(
    id: 'f_alert',
    name: '敌方警觉度',
    type: 'number',
    initialValue: '0',
    minValue: 0,
    maxValue: 100,
  ),
];

const _values = {'f_aff': '4', 'f_alert': '0'};

void main() {
  group('buildInjection - 尊重数据通道策略', () {
    test('无策略时行为不变，全部可读可写', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '45', 'f_alert': '80'},
      );
      expect(out, contains('好感度：45'));
      expect(out, contains('敌方警觉度：80'));
    });

    test('可写不可读的字段绝不泄漏当前值', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '45', 'f_alert': '80'},
        policies: {
          'f_alert': const StatusFieldPolicy(canRead: false, canWrite: true),
        },
      );

      // 关键红线：当前值 80 不能出现在任何位置。
      expect(out, isNot(contains('80')));
      expect(out, contains('[可建议更新的隐藏状态]'));
      expect(out, contains('敌方警觉度'));
      // 可读字段不受影响。
      expect(out, contains('好感度：45'));
    });

    test('格式约束不再出现在 system 注入里，已移交 PHI', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '45', 'f_alert': '80'},
      );
      expect(out, contains('好感度：45'));
      // 放在 system 开头会被长对话淡忘，因此移到 PHI。
      expect(out, isNot(contains('<状态变化>')));
    });

    test('全部字段既不可读也不可写时不产生注入', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '45', 'f_alert': '80'},
        policies: {
          'f_aff': const StatusFieldPolicy(canRead: false, canWrite: false),
          'f_alert': const StatusFieldPolicy(canRead: false, canWrite: false),
        },
      );
      expect(out, isEmpty);
    });
  });

  group('buildUpdateFormatInstruction - 状态栏 PHI', () {
    test('明确告知只有标签块才生效，防止口头声称已修改', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      // 模型最常见的失败模式：正文说「已修改」但不输出标签块。
      expect(out, contains('仅在正文里说'));
      expect(out, contains('无效'));
    });

    test('要求每回合输出，无变化也输出空标签', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, contains('每回合'));
      expect(out, contains('空标签'));
    });

    test('要求每项单独一行，避免同行多项解析问题', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, contains('不要把多项写在同一行'));
    });

    test('示例用空块，避免模型照抄具体数值', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, isNot(contains('好感度:+2')));
      expect(out, contains('默认输出'));
    });

    test('不可写字段不进入可结算项', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(
        _fields,
        _values,
        policies: {
          'f_aff': const StatusFieldPolicy(canRead: true, canWrite: false),
        },
      );
      expect(out, contains('敌方警觉度'));
      expect(out, isNot(contains('`好感度:+N`')));
    });

    test('全部不可写时不产生约束', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(
        _fields,
        _values,
        policies: {
          'f_aff': const StatusFieldPolicy(canWrite: false),
          'f_alert': const StatusFieldPolicy(canWrite: false),
        },
      );
      expect(out, isEmpty);
    });
  });

  group('防止模型脑补数值', () {
    test('注入先肯定可读性，再要求照抄', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '16', 'f_alert': '0'},
      );
      // 只写否定句会被模型泛化成「我无权读取状态」而拒绝回答。
      expect(out, contains('你可以看到'));
      expect(out, contains('直接读出'));
      // 同时要说明这是结算后的最新值，否则会被当成起点重复累加。
      expect(out, contains('已包含此前所有回合的结算结果'));
    });

    test('PHI 以肯定句说明可读，并解释结算时序', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, contains('你能够看到'));
      expect(out, contains('如实回答'));
      expect(out, contains('回复之后自动结算'));
    });

    test('PHI 区分可读字段与隐藏字段，避免规则被泛化', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      // 只有隐藏字段才该声称「无法得知」。
      expect(out, contains('可建议更新的隐藏状态'));
      expect(out, contains('这类项才需要说明'));
    });
  });

  group('PHI 重述当前值', () {
    test('当前值在 PHI 里重复一份，避免模型回头翻远处的 system', () {
      final out =
          StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      // system 开头的 [状态栏] 距离太远，模型更容易采信近处历史里的旧数字。
      expect(out, contains('最新状态值'));
      expect(out, contains('好感度：4'));
    });

    test('明确注入值已含历史结算，防止重复累加', () {
      final out =
          StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      // 只说「当前值」时模型会当成起点，把历史里的请求量再加一遍
      // （实测 50 被报成 75）。必须点明它已经是结算后的结果。
      expect(out, contains('已包含此前所有回合的结算结果'));
      expect(out, contains('不要再把历史消息里出现过的变化量加到它们上面'));
    });

    test('要求以注入值为准而非自己的计算结果', () {
      final out =
          StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, contains('一定是你算错了或重复计算了'));
    });

    test('明确要求以此为准，覆盖历史里说过的旧数字', () {
      final out =
          StatusBarEngine.buildUpdateFormatInstruction(_fields, _values);
      expect(out, contains('过时或错误'));
      expect(out, contains('不要沿用历史消息里的旧数字'));
    });

    test('不可读字段不在 PHI 里暴露当前值', () {
      final out = StatusBarEngine.buildUpdateFormatInstruction(
        _fields,
        _values,
        policies: {
          'f_alert': const StatusFieldPolicy(canRead: false, canWrite: true),
        },
      );
      // 敌方警觉度可写不可读，当前值绝不能出现。
      final section = out.substring(out.indexOf('当前状态值'));
      expect(section, isNot(contains('敌方警觉度：')));
    });
  });

  group('buildTurnReminder - 状态栏', () {
    test('有可写字段时生成简短提醒', () {
      final out = StatusBarEngine.buildTurnReminder(_fields);
      expect(out, contains('状态变化'));
      expect(out.length, lessThan(150));
    });

    test('全部不可写时不打扰模型', () {
      final out = StatusBarEngine.buildTurnReminder(
        _fields,
        policies: {
          'f_aff': const StatusFieldPolicy(canWrite: false),
          'f_alert': const StatusFieldPolicy(canWrite: false),
        },
      );
      expect(out, isEmpty);
    });
  });

  group('splitSegments - 同行多项', () {
    const names = ['心情', '好感度'];

    test('同行多项按字段名正确切分', () {
      expect(
        StatusBarEngine.splitSegments('心情=平静，好感度:+3', names),
        ['心情=平静', '好感度:+3'],
      );
    });

    test('文本值里的逗号不会被误切', () {
      expect(
        StatusBarEngine.splitSegments('心情=有点复杂，说不清', names),
        ['心情=有点复杂，说不清'],
      );
    });

    test('单项原样返回并去掉列表符号', () {
      expect(
        StatusBarEngine.splitSegments('- 好感度:+3', names),
        ['好感度:+3'],
      );
    });

    test('字段名出现在文本值中但后面没有分隔符时不切分', () {
      expect(
        StatusBarEngine.splitSegments('心情=我在想好感度这件事', names),
        ['心情=我在想好感度这件事'],
      );
    });
  });

  group('applyFromReply - 同行多项回归', () {
    test('好感度增量不会被心情的文本值吞掉', () {
      final fields = [
        StatusBarField(
          id: 'f_mood',
          name: '心情',
          type: 'text',
          initialValue: '平静',
        ),
        StatusBarField(
          id: 'f_aff',
          name: '好感度',
          type: 'number',
          initialValue: '0',
          minValue: 0,
          maxValue: 100,
        ),
      ];
      final values = {'f_mood': '平静', 'f_aff': '5'};

      StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n心情=开心，好感度:+3\n</状态变化>',
        fields,
        values,
      );

      // 修复前：心情会变成 "开心，好感度:+3"，而好感度纹丝不动。
      expect(values['f_mood'], '开心');
      expect(values['f_aff'], '8');
    });
  });

  group('applyFromReply - commit 开关', () {
    test('commit=false 时只算账不写入，供确认弹窗预览', () {
      final values = {'f_aff': '45'};
      final changes = StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n好感度:+3\n</状态变化>',
        _fields,
        values,
        commit: false,
      );

      expect(changes.length, 1);
      expect(changes.single.oldValue, '45');
      expect(changes.single.newValue, '48');
      // 关键：用户尚未确认，会话副本不能被改动。
      expect(values['f_aff'], '45');
    });

    test('commit=true 时正常写入', () {
      final values = {'f_aff': '45'};
      StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n好感度:+3\n</状态变化>',
        _fields,
        values,
      );
      expect(values['f_aff'], '48');
    });

    test('commit=false 下文本字段同样不写入', () {
      final fields = [
        StatusBarField(id: 'f_mood', name: '心情', type: 'text',
            initialValue: '平静'),
      ];
      final values = {'f_mood': '平静'};
      final changes = StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n心情=放松\n</状态变化>',
        fields,
        values,
        commit: false,
      );

      expect(changes.single.newValue, '放松');
      expect(values['f_mood'], '平静');
    });
  });

  group('applyFromReply - 尊重写策略', () {
    test('不可写字段即使 LLM 输出也不生效', () {
      final values = {'f_aff': '45'};
      final changes = StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n好感度:+10\n</状态变化>',
        _fields,
        values,
        policies: {
          'f_aff': const StatusFieldPolicy(canRead: true, canWrite: false),
        },
      );

      expect(changes, isEmpty);
      expect(values['f_aff'], '45');
    });

    test('可写字段正常算账并 clamp', () {
      final values = {'f_aff': '95'};
      final changes = StatusBarEngine.applyFromReply(
        '正文\n<状态变化>\n好感度:+20\n</状态变化>',
        _fields,
        values,
      );

      expect(changes.length, 1);
      expect(values['f_aff'], '100');
    });
  });
}
