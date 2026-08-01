import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/session_state.dart';
import 'package:llm_project/models/ui_assembly_info.dart';
import 'package:llm_project/services/ui_engine/data_channel_prompt_builder.dart';
import 'package:llm_project/services/ui_engine/ui_models.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

/// A13-1：注入位置可选（`[界面数据]` / `[玩家档案]`）。
///
/// 玩家在 opening UI 里填的姓名 / 职业 / 属性，本质是**角色设定的一部分**，
/// 不是「界面上的一个数值」。混在 `[界面数据]` 里模型会当成可有可无的
/// 运行时状态而弱化处理。

UIElement _atom({
  required String id,
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
      type: 'input',
      properties: {
        'dataChannel': ?channel,
      },
    ),
  );
}

Map<String, dynamic> _channel({
  required String label,
  String read = 'prompt',
  String write = 'none',
  String? section,
}) {
  return {
    'semanticLabel': label,
    'targetKind': 'session_var',
    'targetId': '',
    'llmReadPolicy': read,
    'llmWritePolicy': write,
    'promptSection': ?section,
  };
}

String _assemblyJson(List<UIElement> elements) {
  final page = AssemblyPage(
    id: 'p1',
    name: '开场白',
    type: 'base',
    elements: elements,
  );
  final info = UIAssemblyInfo(
    id: 'ui_1',
    mode: 'opening',
    pagesJson: jsonEncode([page.toJson()]),
  );
  return info.toJsonString();
}

List<DataChannelPromptItem> _collect(
  List<UIElement> elements,
  SessionState session,
) {
  return DataChannelPromptBuilder.collectItems(
    uiAssemblyJsons: [_assemblyJson(elements)],
    session: session,
  );
}

void main() {
  group('promptSection 解析', () {
    test('缺省时回落界面数据，老卡片行为不变', () {
      final items = _collect(
        [_atom(id: 'e1', channel: _channel(label: '好感度'))],
        SessionState(),
      );
      expect(items.single.promptSection, DataChannelPromptItem.sectionUiData);
      expect(items.single.isCoreSetting, isFalse);
    });

    test('显式配置为玩家档案时被识别', () {
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(
              label: '主角姓名',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        SessionState(),
      );
      expect(items.single.isCoreSetting, isTrue);
    });
  });

  group('buildInjection 分段', () {
    test('玩家档案独立成段，且排在界面数据之前', () {
      final session = SessionState()
        ..vars['主角姓名'] = '林'
        ..vars['好感度'] = '45';
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(label: '好感度'),
          ),
          _atom(
            id: 'e2',
            channel: _channel(
              label: '主角姓名',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        session,
      );
      final text = DataChannelPromptBuilder.buildInjection(items);

      expect(text, contains('[玩家档案]'));
      expect(text, contains('[界面数据]'));
      // 档案是设定，应先于运行时数据出现。
      expect(text.indexOf('[玩家档案]'), lessThan(text.indexOf('[界面数据]')));
      expect(text, contains('主角姓名：林'));
      expect(text, contains('好感度：45'));
    });

    test('只有档案时不出现空的界面数据段', () {
      final session = SessionState()..vars['职业'] = '剑士';
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(
              label: '职业',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        session,
      );
      final text = DataChannelPromptBuilder.buildInjection(items);
      expect(text, contains('[玩家档案]'));
      expect(text, isNot(contains('[界面数据]')));
    });

    test('只有界面数据时不出现空的档案段', () {
      final session = SessionState()..vars['好感度'] = '10';
      final items = _collect(
        [_atom(id: 'e1', channel: _channel(label: '好感度'))],
        session,
      );
      final text = DataChannelPromptBuilder.buildInjection(items);
      expect(text, contains('[界面数据]'));
      expect(text, isNot(contains('[玩家档案]')));
    });

    test('档案段的措辞强调「全程有效」而非「当前数据」', () {
      // 措辞直接决定模型是否会在长对话里持续遵守，
      // 与「运行时数值」区分开是这一步的全部意义。
      final session = SessionState()..vars['姓名'] = '林';
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(
              label: '姓名',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        session,
      );
      final text = DataChannelPromptBuilder.buildInjection(items);
      expect(text, contains('角色设定的一部分'));
      expect(text, contains('整场对话中保持有效'));
    });

    test('不可读的档案项不会被注入', () {
      // 读策略优先于注入位置：选了档案但不发送，仍然不该出现。
      final session = SessionState()..vars['隐藏设定'] = 'x';
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(
              label: '隐藏设定',
              read: 'none',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        session,
      );
      final text = DataChannelPromptBuilder.buildInjection(items);
      expect(text, isNot(contains('隐藏设定')));
    });

    test('档案项未填写时显示（未设置），不静默消失', () {
      // 玩家跳过了某个字段，模型需要知道「这项没填」，
      // 而不是完全看不到这一项。
      final items = _collect(
        [
          _atom(
            id: 'e1',
            channel: _channel(
              label: '外号',
              section: DataChannelPromptItem.sectionCoreSetting,
            ),
          ),
        ],
        SessionState(),
      );
      final text = DataChannelPromptBuilder.buildInjection(items);
      expect(text, contains('外号：（未设置）'));
    });
  });
}
