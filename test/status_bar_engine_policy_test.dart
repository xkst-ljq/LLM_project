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

    test('不可写的字段不出现在可更新清单里', () {
      final out = StatusBarEngine.buildInjection(
        _fields,
        {'f_aff': '45', 'f_alert': '80'},
        policies: {
          'f_aff': const StatusFieldPolicy(canRead: true, canWrite: false),
        },
      );
      expect(out, contains('好感度：45'));
      expect(out, contains('可更新的项：敌方警觉度'));
      expect(out, isNot(contains('可更新的项：好感度')));
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
