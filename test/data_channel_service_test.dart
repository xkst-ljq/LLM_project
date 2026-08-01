import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/session_state.dart';
import 'package:llm_project/models/status_bar_field.dart';
import 'package:llm_project/services/ui_engine/data_channel_service.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

UIElement _atom({
  required String id,
  required String type,
  required Map<String, dynamic> properties,
}) {
  return UIElement(
    id: id,
    isComposite: false,
    offset: Offset.zero,
    size: const Size(100, 40),
    module: UIModule(
      id: 'm_$id',
      name: id,
      type: type,
      properties: properties,
    ),
  );
}

Map<String, dynamic> _channel({
  required String label,
  String targetKind = 'session_var',
  String targetId = '',
  String pendingName = '',
  String fieldType = 'string',
}) {
  return {
    'semanticLabel': label,
    'targetKind': targetKind,
    'targetId': targetId,
    'pendingName': pendingName,
    'fieldType': fieldType,
  };
}

void main() {
  group('readModuleValue', () {
    test('input 优先读取已提交值', () {
      final module = UIModule(
        id: 'm',
        name: 'n',
        type: 'input',
        properties: {'text': '草稿', 'committedValue': '林'},
      );
      expect(DataChannelService.readModuleValue(module), '林');
    });

    test('switch 返回布尔字符串，缺省视为开启', () {
      final on = UIModule(id: 'a', name: 'a', type: 'switch', properties: {});
      final off = UIModule(
        id: 'b',
        name: 'b',
        type: 'switch',
        properties: {'value': false},
      );
      expect(DataChannelService.readModuleValue(on), 'true');
      expect(DataChannelService.readModuleValue(off), 'false');
    });

    test('slider 整数值不带小数尾巴', () {
      final module = UIModule(
        id: 'm',
        name: 'n',
        type: 'slider',
        properties: {'current': 45.0},
      );
      expect(DataChannelService.readModuleValue(module), '45');
    });
  });

  group('collectWrites', () {
    test('只收集可写类型，progress 被忽略', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'input',
          properties: {
            'committedValue': '林',
            'dataChannel': _channel(label: '主角姓名', targetKind: 'session_var'),
          },
        ),
        _atom(
          id: 'e2',
          type: 'progress',
          properties: {
            'current': 10,
            'dataChannel': _channel(label: '进度', targetKind: 'session_var'),
          },
        ),
      ];

      final writes = DataChannelService.collectWrites(elements);
      expect(writes.length, 1);
      expect(writes.single.semanticLabel, '主角姓名');
      expect(writes.single.value, '林');
    });

    test('无数据通道的组件不产生写入', () {
      final writes = DataChannelService.collectWrites([
        _atom(id: 'e1', type: 'input', properties: {'committedValue': '林'}),
      ]);
      expect(writes, isEmpty);
    });

    test('复合组件内部子元素与暴露项覆写通道都会被收集', () {
      final child = _atom(
        id: 'c1',
        type: 'slider',
        properties: {'current': 45},
      );
      final composite = UIElement(
        id: 'comp',
        isComposite: true,
        offset: Offset.zero,
        size: const Size(200, 100),
        composite: UIComposite(
          id: 'tpl',
          name: '状态条',
          layoutType: 'free',
          children: [child],
        ),
      );

      final writes = DataChannelService.collectWrites(
        [composite],
        overrideChannels: {
          'c1': _channel(
            label: '好感度',
            targetKind: 'status_field',
            targetId: 'f_aff',
            fieldType: 'number',
          ),
        },
      );

      expect(writes.length, 1);
      expect(writes.single.targetId, 'f_aff');
      expect(writes.single.value, '45');
    });
  });

  group('applyValueToModule', () {
    UIModule mod(String type, [Map<String, dynamic>? props]) => UIModule(
          id: 'm',
          name: 'n',
          type: type,
          properties: props ?? <String, dynamic>{},
        );

    test('slider 按量程 clamp，不会推到轨道外', () {
      final module = mod('slider', {'min': 0, 'max': 100, 'current': 10});
      DataChannelService.applyValueToModule(module, '160');
      expect(module.properties['current'], 100.0);
    });

    test('switch 识别多种真值写法', () {
      for (final raw in ['true', '1', '开启']) {
        final module = mod('switch', {'value': false});
        DataChannelService.applyValueToModule(module, raw);
        expect(module.properties['value'], isTrue, reason: raw);
      }
    });

    test('非数值写入 slider 时忽略，不破坏原值', () {
      final module = mod('slider', {'min': 0, 'max': 100, 'current': 42});
      final changed = DataChannelService.applyValueToModule(module, '一堆文字');
      expect(changed, isFalse);
      expect(module.properties['current'], 42);
    });

    test('值未变化时返回 false，避免无谓重建', () {
      final module = mod('text', {'text': '林'});
      expect(DataChannelService.applyValueToModule(module, '林'), isFalse);
    });

    test('与 readModuleValue 往返一致', () {
      // 写进去和读出来必须是同一个字段，否则同步会静默丢值。
      final cases = {
        'input': '林',
        'select': 'option_2',
        'switch': 'true',
        'slider': '45',
        'progress': '45',
        'text': '你好',
      };
      cases.forEach((type, value) {
        final module = mod(type, {'min': 0, 'max': 100});
        DataChannelService.applyValueToModule(module, value);
        expect(DataChannelService.readModuleValue(module), value,
            reason: type);
      });
    });
  });

  group('applySessionToElements', () {
    test('会话变量按语义名回填', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'text',
          properties: {
            'dataChannel': _channel(label: '主角姓名', targetKind: 'session_var'),
          },
        ),
      ];

      final changed = DataChannelService.applySessionToElements(
        elements,
        SessionState(vars: {'主角姓名': '林'}),
      );

      expect(changed, isTrue);
      expect(elements.first.module!.properties['text'], '林');
    });

    test('状态字段按 targetId 回填', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'progress',
          properties: {
            'min': 0,
            'max': 100,
            'dataChannel': _channel(
              label: '好感度',
              targetKind: 'status_field',
              targetId: 'f_aff',
            ),
          },
        ),
      ];

      DataChannelService.applySessionToElements(
        elements,
        SessionState(statusValues: {'f_aff': '45'}),
      );

      expect(elements.first.module!.properties['current'], 45.0);
    });

    test('local_ui_state 通道不回填，它没有外部数据源', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'text',
          properties: {
            'text': '原值',
            'dataChannel':
                _channel(label: '当前tab', targetKind: 'local_ui_state'),
          },
        ),
      ];

      final changed = DataChannelService.applySessionToElements(
        elements,
        SessionState(vars: {'当前tab': '2'}),
      );

      expect(changed, isFalse);
      expect(elements.first.module!.properties['text'], '原值');
    });

    test('未匹配的状态字段（pendingName）不回填', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'progress',
          properties: {
            'current': 10,
            'dataChannel':
                _channel(label: '还没建', targetKind: 'status_field'),
          },
        ),
      ];

      final changed = DataChannelService.applySessionToElements(
        elements,
        SessionState(),
      );
      expect(changed, isFalse);
      expect(elements.first.module!.properties['current'], 10);
    });

    test('会话里没有该键时保持组件原值', () {
      final elements = [
        _atom(
          id: 'e1',
          type: 'text',
          properties: {
            'text': '默认文案',
            'dataChannel': _channel(label: '未设置的变量'),
          },
        ),
      ];

      final changed = DataChannelService.applySessionToElements(
        elements,
        SessionState(),
      );
      expect(changed, isFalse);
      expect(elements.first.module!.properties['text'], '默认文案');
    });

    test('复合组件内部子元素与暴露项覆写通道都会被回填', () {
      final child = _atom(id: 'c1', type: 'progress', properties: {
        'min': 0,
        'max': 100,
        'current': 0,
      });
      final composite = UIElement(
        id: 'comp',
        isComposite: true,
        offset: Offset.zero,
        size: const Size(200, 100),
        composite: UIComposite(
          id: 'tpl',
          name: '状态条',
          layoutType: 'free',
          children: [child],
        ),
      );

      DataChannelService.applySessionToElements(
        [composite],
        SessionState(statusValues: {'f_aff': '77'}),
        overrideChannels: {
          'c1': _channel(
            label: '好感度',
            targetKind: 'status_field',
            targetId: 'f_aff',
          ),
        },
      );

      expect(child.module!.properties['current'], 77.0);
    });
  });

  group('applyWrites', () {
    test('session_var 按语义名写入 vars', () {
      final session = SessionState();
      final changed = DataChannelService.applyWrites(session, [
        const DataChannelWrite(
          semanticLabel: '主角姓名',
          targetKind: 'session_var',
          targetId: '',
          pendingName: '',
          fieldType: 'string',
          value: '林',
          sourceElementId: 'e1',
        ),
      ]);

      expect(changed, isTrue);
      expect(session.vars['主角姓名'], '林');
    });

    test('local_ui_state 永不进入会话副本', () {
      final session = SessionState();
      final changed = DataChannelService.applyWrites(session, [
        const DataChannelWrite(
          semanticLabel: '当前tab',
          targetKind: 'local_ui_state',
          targetId: '',
          pendingName: '',
          fieldType: 'string',
          value: '2',
          sourceElementId: 'e1',
        ),
      ]);

      expect(changed, isFalse);
      expect(session.isEmpty, isTrue);
    });

    test('状态字段未匹配（pendingName）时跳过写入', () {
      final session = SessionState();
      final changed = DataChannelService.applyWrites(session, [
        const DataChannelWrite(
          semanticLabel: '还没建的字段',
          targetKind: 'status_field',
          targetId: '',
          pendingName: '还没建的字段',
          fieldType: 'number',
          value: '10',
          sourceElementId: 'e1',
        ),
      ]);

      expect(changed, isFalse);
      expect(session.statusValues, isEmpty);
    });

    test('数值状态字段按角色卡定义 clamp', () {
      final session = SessionState();
      final fields = [
        StatusBarField(
          id: 'f_aff',
          name: '好感度',
          type: 'number',
          minValue: 0,
          maxValue: 100,
        ),
      ];

      DataChannelService.applyWrites(
        session,
        [
          const DataChannelWrite(
            semanticLabel: '好感度',
            targetKind: 'status_field',
            targetId: 'f_aff',
            pendingName: '',
            fieldType: 'number',
            value: '160',
            sourceElementId: 'e1',
          ),
        ],
        statusFields: fields,
      );
      expect(session.statusValues['f_aff'], '100');

      DataChannelService.applyWrites(
        session,
        [
          const DataChannelWrite(
            semanticLabel: '好感度',
            targetKind: 'status_field',
            targetId: 'f_aff',
            pendingName: '',
            fieldType: 'number',
            value: '-20',
            sourceElementId: 'e1',
          ),
        ],
        statusFields: fields,
      );
      expect(session.statusValues['f_aff'], '0');
    });

    test('值未变化时不报告 changed，避免无谓落盘', () {
      final session = SessionState(vars: {'主角姓名': '林'});
      final changed = DataChannelService.applyWrites(session, [
        const DataChannelWrite(
          semanticLabel: '主角姓名',
          targetKind: 'session_var',
          targetId: '',
          pendingName: '',
          fieldType: 'string',
          value: '林',
          sourceElementId: 'e1',
        ),
      ]);

      expect(changed, isFalse);
    });
  });
}
