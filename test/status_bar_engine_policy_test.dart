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
