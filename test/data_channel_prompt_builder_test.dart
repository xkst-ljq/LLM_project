import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/session_state.dart';
import 'package:llm_project/models/status_bar_field.dart';
import 'package:llm_project/models/ui_assembly_info.dart';
import 'package:llm_project/services/ui_engine/data_channel_prompt_builder.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';

UIElement _atom({
  required String id,
  required String type,
  Map<String, dynamic>? channel,
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
      properties: {
        if (channel != null) 'dataChannel': channel,
      },
    ),
  );
}

Map<String, dynamic> _channel({
  required String label,
  String targetKind = 'session_var',
  String targetId = '',
  String read = 'prompt',
  String write = 'none',
}) {
  return {
    'semanticLabel': label,
    'targetKind': targetKind,
    'targetId': targetId,
    'llmReadPolicy': read,
    'llmWritePolicy': write,
  };
}

String _assemblyJson(List<UIElement> elements) {
  final page = AssemblyPage(
    id: 'p1',
    name: '主菜单',
    type: 'base',
    elements: elements,
  );
  final info = UIAssemblyInfo(
    id: 'ui_1',
    pagesJson: jsonEncode([page.toJson()]),
  );
  return info.toJsonString();
}

void main() {
  group('collectItems', () {
    test('UI 内部状态通道永不参与 Prompt', () {
      final json = _assemblyJson([
        _atom(
          id: 'e1',
          type: 'select',
          channel: _channel(label: '当前tab', targetKind: 'local_ui_state'),
        ),
      ]);

      final items = DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [json],
        session: SessionState(),
      );
      expect(items, isEmpty);
    });

    test('未匹配的状态字段通道被跳过', () {
      final json = _assemblyJson([
        _atom(
          id: 'e1',
          type: 'slider',
          channel: _channel(label: '还没建', targetKind: 'status_field'),
        ),
      ]);

      final items = DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [json],
        session: SessionState(),
      );
      expect(items, isEmpty);
    });

    test('状态字段取 statusValues，并带上范围提示', () {
      final json = _assemblyJson([
        _atom(
          id: 'e1',
          type: 'slider',
          channel: _channel(
            label: '好感度',
            targetKind: 'status_field',
            targetId: 'f_aff',
          ),
        ),
      ]);

      final items = DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [json],
        session: SessionState(statusValues: {'f_aff': '45'}),
        statusFields: [
          StatusBarField(
            id: 'f_aff',
            name: '好感度',
            type: 'number',
            minValue: 0,
            maxValue: 100,
          ),
        ],
      );

      expect(items.length, 1);
      expect(items.single.value, '45');
      expect(items.single.rangeHint, '范围 0~100');
    });

    test('同一目标重复配置只保留一条', () {
      final json = _assemblyJson([
        _atom(id: 'e1', type: 'input', channel: _channel(label: '主角姓名')),
        _atom(id: 'e2', type: 'input', channel: _channel(label: '主角姓名')),
      ]);

      final items = DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [json],
        session: SessionState(vars: {'主角姓名': '林'}),
      );
      expect(items.length, 1);
    });
  });

  group('buildInjection', () {
    test('不可读不可写时不产生任何注入', () {
      final injection = DataChannelPromptBuilder.buildInjection([
        const DataChannelPromptItem(
          semanticLabel: '好感度',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'none',
          llmWritePolicy: 'none',
          value: '45',
          rangeHint: '',
        ),
      ]);
      expect(injection, isEmpty);
    });

    test('更新格式已移到 PHI，不再出现在 system 注入里', () {
      final injection = DataChannelPromptBuilder.buildInjection([
        const DataChannelPromptItem(
          semanticLabel: '好感度',
          targetKind: 'status_field',
          targetId: 'f_aff',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'suggest_delta',
          value: '45',
          rangeHint: '',
        ),
      ]);
      expect(injection, contains('[界面数据]'));
      expect(injection, isNot(contains('[界面数据更新格式')));
    });

    test('可读通道注入带语义名的当前值，不出现裸值', () {
      final injection = DataChannelPromptBuilder.buildInjection([
        const DataChannelPromptItem(
          semanticLabel: '主角姓名',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'none',
          value: '林',
          rangeHint: '',
        ),
      ]);

      expect(injection, contains('[界面数据]'));
      expect(injection, contains('- 主角姓名：林'));
    });

    test('状态字段交给状态栏，不在界面数据里重复注入', () {
      final injection = DataChannelPromptBuilder.buildInjection([
        const DataChannelPromptItem(
          semanticLabel: '好感度',
          targetKind: 'status_field',
          targetId: 'f_aff',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'suggest_delta',
          value: '45',
          rangeHint: '范围 0~100',
        ),
      ]);
      // 同一字段被两套机制注入会让模型面对两个标签、两套格式。
      expect(injection, isEmpty);
    });

    test('collectStatusFieldPolicies 传递读写策略给状态栏', () {
      final policies = DataChannelPromptBuilder.collectStatusFieldPolicies([
        const DataChannelPromptItem(
          semanticLabel: '敌方警觉度',
          targetKind: 'status_field',
          targetId: 'f_alert',
          llmReadPolicy: 'none',
          llmWritePolicy: 'suggest_delta',
          value: '80',
          rangeHint: '',
        ),
      ]);

      expect(policies['f_alert']!.canRead, isFalse);
      expect(policies['f_alert']!.canWrite, isTrue);
    });

    test('可写不可读只注入更新规则，不暴露当前值', () {
      final injection = DataChannelPromptBuilder.buildInjection([
        const DataChannelPromptItem(
          semanticLabel: '敌方警觉度',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'none',
          llmWritePolicy: 'suggest_delta',
          value: '80',
          rangeHint: '',
        ),
      ]);

      expect(injection, contains('[可建议更新的隐藏状态]'));
      expect(injection, contains('敌方警觉度'));
      // 关键：当前值 80 绝不能出现。
      expect(injection, isNot(contains('80')));
    });

    test('可写通道在 PHI 里给出对应格式约定', () {
      final instruction =
          DataChannelPromptBuilder.buildUpdateFormatInstruction([
        const DataChannelPromptItem(
          semanticLabel: '好感度',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'suggest_delta',
          value: '45',
          rangeHint: '',
        ),
        const DataChannelPromptItem(
          semanticLabel: '心情',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'suggest_replace',
          value: '平静',
          rangeHint: '',
        ),
      ]);

      expect(instruction, contains('好感度:+N'));
      expect(instruction, contains('心情=新内容'));
      expect(
        instruction,
        contains('<${DataChannelPromptBuilder.updateTag}>'),
      );
    });
  });

  group('buildUpdateFormatInstruction - 遵从度强化', () {
    const deltaItem = DataChannelPromptItem(
      semanticLabel: '心情',
      targetKind: 'session_var',
      targetId: '',
      llmReadPolicy: 'prompt',
      llmWritePolicy: 'suggest_delta',
      value: '45',
      rangeHint: '',
    );

    test('要求每回合都输出标签，无变化也要输出空标签', () {
      final out =
          DataChannelPromptBuilder.buildUpdateFormatInstruction([deltaItem]);
      // 关键：不能给模型「无变化就整块省略」的台阶，
      // 否则它每回合都判定无变化，永远不输出标签块。
      expect(out, contains('每回合'));
      expect(out, contains('空标签'));
    });

    test('示例用空标签块，避免模型照抄具体数值', () {
      final out =
          DataChannelPromptBuilder.buildUpdateFormatInstruction([deltaItem]);
      // 示例里出现具体变化量会被模型当成标准答案每回合照抄，
      // 造成数值漂移，因此示例必须是空块。
      expect(out, isNot(contains('心情:+2')));
      expect(out, contains('默认输出'));
    });

    test('明确空结算是常态，抑制过度触发', () {
      final out =
          DataChannelPromptBuilder.buildUpdateFormatInstruction([deltaItem]);
      expect(out, contains('绝大多数回合都应该是空结算块'));
      expect(out, contains('拿不准时，一律不写'));
      expect(out, contains('不要为了让结算块'));
    });

    test('无可写通道时不产生任何约束', () {
      final out = DataChannelPromptBuilder.buildUpdateFormatInstruction([
        const DataChannelPromptItem(
          semanticLabel: '主角姓名',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'none',
          value: '林',
          rangeHint: '',
        ),
      ]);
      expect(out, isEmpty);
    });
  });

  group('buildTurnReminder', () {
    test('有可写通道时生成简短提醒', () {
      final out = DataChannelPromptBuilder.buildTurnReminder([
        const DataChannelPromptItem(
          semanticLabel: '心情',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'suggest_delta',
          value: '45',
          rangeHint: '',
        ),
      ]);
      expect(out, contains(DataChannelPromptBuilder.updateTag));
      // 提醒必须足够短，避免干扰正文角色扮演质量。
      expect(out.length, lessThan(120));
    });

    test('无可写通道时不打扰模型', () {
      final out = DataChannelPromptBuilder.buildTurnReminder([
        const DataChannelPromptItem(
          semanticLabel: '主角姓名',
          targetKind: 'session_var',
          targetId: '',
          llmReadPolicy: 'prompt',
          llmWritePolicy: 'none',
          value: '林',
          rangeHint: '',
        ),
      ]);
      expect(out, isEmpty);
    });
  });

  group('renderPlaceholders', () {
    const items = [
      DataChannelPromptItem(
        semanticLabel: '主角姓名',
        targetKind: 'session_var',
        targetId: '',
        llmReadPolicy: 'prompt',
        llmWritePolicy: 'none',
        value: '林',
        rangeHint: '',
      ),
      DataChannelPromptItem(
        semanticLabel: '隐藏值',
        targetKind: 'session_var',
        targetId: '',
        llmReadPolicy: 'none',
        llmWritePolicy: 'none',
        value: '机密',
        rangeHint: '',
      ),
    ];

    test('可读通道正常替换', () {
      final out = DataChannelPromptBuilder.renderPlaceholders(
        '你好，{{ui.主角姓名}}。',
        items,
      );
      expect(out, '你好，林。');
    });

    test('不可读通道替换为空串，不泄漏值', () {
      final out = DataChannelPromptBuilder.renderPlaceholders(
        '密码是{{ui.隐藏值}}',
        items,
      );
      expect(out, '密码是');
      expect(out, isNot(contains('机密')));
    });

    test('未知占位符替换为空串，不残留原文', () {
      final out = DataChannelPromptBuilder.renderPlaceholders(
        'A{{ui.不存在}}B',
        items,
      );
      expect(out, 'AB');
    });
  });
}
