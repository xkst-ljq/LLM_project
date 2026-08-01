import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';
import 'package:llm_project/services/ui_engine/data_channel_prompt_builder.dart';

/// A13-2：数据通道指向角色卡设定条目的三级定位。

CharacterEntry _entry({
  required String id,
  required String title,
  Map<String, dynamic>? fields,
  String? text,
  bool enabled = true,
  bool isCustom = false,
}) {
  return CharacterEntry(
    id: id,
    title: title,
    content: fields != null ? jsonEncode(fields) : (text ?? ''),
    enabled: enabled,
    isCustom: isCustom,
  );
}

UIElement _input({
  required String id,
  required Map<String, dynamic> channel,
  String text = '',
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
        'dataChannel': channel,
        'text': text,
        'committedValue': text,
      },
    ),
  );
}

Map<String, dynamic> _cardChannel({
  required String label,
  required CardEntryTarget target,
  String read = 'prompt',
}) {
  return {
    'semanticLabel': label,
    'targetKind': 'card_entry',
    'targetId': '',
    'llmReadPolicy': read,
    'llmWritePolicy': 'none',
    'cardEntryTarget': target.toJson(),
  };
}

String _assemblyJson(List<UIElement> elements) {
  final page = AssemblyPage(
    id: 'p1',
    name: '开场白',
    type: 'base',
    elements: elements,
  );
  return UIAssemblyInfo(
    id: 'ui_1',
    mode: 'opening',
    pagesJson: jsonEncode([page.toJson()]),
  ).toJsonString();
}

void main() {
  const bodyRace = CardEntryTarget(
    group: CardEntryTarget.groupDetail,
    entryId: 'body',
    fieldKey: 'race',
  );

  group('三级定位模型', () {
    test('固定条目的 sessionKey 带 card: 前缀，与普通变量隔开', () {
      // 作者可能起一个同名会话变量，不隔开会互相覆盖。
      expect(bodyRace.sessionKey, 'card:detail:body:race');
    });

    test('自定义条目按标题成键', () {
      const custom = CardEntryTarget(
        group: CardEntryTarget.groupDetail,
        entryId: CardEntryTarget.customEntryMarker,
        fieldKey: '职业',
      );
      expect(custom.isCustomEntry, isTrue);
      expect(custom.sessionKey, 'card:detail:custom:职业');
    });

    test('自定义条目标题留空视为未配置', () {
      // 作者选了「添加自定义条目」但没填标题，此时无处可写。
      const blank = CardEntryTarget(
        group: CardEntryTarget.groupDetail,
        entryId: CardEntryTarget.customEntryMarker,
        fieldKey: '   ',
      );
      expect(blank.isValid, isFalse);
    });

    test('JSON 往返保真', () {
      expect(CardEntryTarget.fromJson(bodyRace.toJson()), bodyRace);
    });

    test('损坏数据返回 null 而不抛异常', () {
      expect(CardEntryTarget.fromJson(null), isNull);
      expect(CardEntryTarget.fromJson('not a map'), isNull);
      expect(CardEntryTarget.fromJson({'group': ''}), isNull);
    });
  });

  group('卡片结构查询', () {
    test('人物卡与系统卡的条目集合不同', () {
      expect(
        CardEntryTarget.fixedEntryIdsOf('character', CardEntryTarget.groupIntro),
        contains('name_entry'),
      );
      expect(
        CardEntryTarget.fixedEntryIdsOf('system', CardEntryTarget.groupIntro),
        contains('system_name'),
      );
    });

    test('子字段从条目 JSON 里读，不硬编码', () {
      // 作者可能改过结构，硬编码一份会与实际数据脱节。
      final entry = _entry(
        id: 'body',
        title: '身体数据',
        fields: {'race': '', 'gender': '', '自定义项': ''},
      );
      expect(CardEntryTarget.fieldKeysOf(entry), contains('自定义项'));
    });

    test('纯文本条目没有子字段', () {
      final entry = _entry(id: 'relationship', title: '与用户关系', text: '青梅竹马');
      expect(CardEntryTarget.fieldKeysOf(entry), isEmpty);
    });

    test('自定义条目没有子字段', () {
      final entry =
          _entry(id: 'c1', title: '职业', text: '剑士', isCustom: true);
      expect(CardEntryTarget.fieldKeysOf(entry), isEmpty);
    });
  });

  group('注入', () {
    final entries = [
      _entry(id: 'body', title: '身体数据', fields: {'race': '人族', 'gender': ''}),
    ];

    List<DataChannelPromptItem> collect(SessionState session) {
      return DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [
          _assemblyJson([
            _input(
              id: 'e1',
              channel: _cardChannel(label: '种族', target: bodyRace),
            ),
          ]),
        ],
        session: session,
        cardEntries: entries,
      );
    }

    test('角色卡设定自动归入玩家档案，无需另选注入位置', () {
      // 它填的就是角色设定本身，再让作者选一次注入位置是多余的。
      final session = SessionState()..vars[bodyRace.sessionKey] = '精灵';
      expect(collect(session).single.isCoreSetting, isTrue);
    });

    test('显示名带条目归属，而不是裸的语义名', () {
      final session = SessionState()..vars[bodyRace.sessionKey] = '精灵';
      final text = DataChannelPromptBuilder.buildInjection(collect(session));
      expect(text, contains('[玩家档案]'));
      expect(text, contains('身体数据 · 种族：精灵'));
    });

    test('玩家未填时整条不注入，母版原值继续生效', () {
      // 关键：不能覆盖成「（未设置）」，否则作者写的默认设定会被抹掉。
      final items = collect(SessionState());
      expect(items, isEmpty);
    });

    test('三级定位不完整的通道被跳过', () {
      final items = DataChannelPromptBuilder.collectItems(
        uiAssemblyJsons: [
          _assemblyJson([
            _input(
              id: 'e1',
              channel: _cardChannel(
                label: '坏配置',
                target: const CardEntryTarget(
                  group: CardEntryTarget.groupDetail,
                  entryId: 'body',
                  fieldKey: '',
                ),
              ),
            ),
          ]),
        ],
        session: SessionState()..vars['card:detail:body:'] = 'x',
        cardEntries: entries,
      );
      expect(items, isEmpty);
    });

    test('冲突时提示以玩家档案为准', () {
      // 作者写了默认值、玩家又填了，措辞必须让模型知道该听谁的。
      final session = SessionState()..vars[bodyRace.sessionKey] = '精灵';
      final text = DataChannelPromptBuilder.buildInjection(collect(session));
      expect(text, contains('以此处为准'));
    });
  });

  group('写入', () {
    test('玩家提交后写进专属键', () {
      final session = SessionState();
      final writes = DataChannelService.collectWrites([
        _input(
          id: 'e1',
          channel: _cardChannel(label: '种族', target: bodyRace),
          text: '龙裔',
        ),
      ]);
      expect(DataChannelService.applyWrites(session, writes), isTrue);
      expect(session.vars[bodyRace.sessionKey], '龙裔');
    });

    test('定位不完整时不写入，也不误报变更', () {
      final session = SessionState();
      final writes = DataChannelService.collectWrites([
        _input(
          id: 'e1',
          channel: _cardChannel(
            label: '空标题自定义',
            target: const CardEntryTarget(
              group: CardEntryTarget.groupDetail,
              entryId: CardEntryTarget.customEntryMarker,
              fieldKey: '',
            ),
          ),
          text: '写不进去',
        ),
      ]);
      expect(DataChannelService.applyWrites(session, writes), isFalse);
      expect(session.vars, isEmpty);
    });

    test('不写普通会话变量，避免与作者的同名变量互相覆盖', () {
      final session = SessionState();
      final writes = DataChannelService.collectWrites([
        _input(
          id: 'e1',
          channel: _cardChannel(label: '种族', target: bodyRace),
          text: '龙裔',
        ),
      ]);
      DataChannelService.applyWrites(session, writes);
      expect(session.vars.containsKey('种族'), isFalse);
    });
  });
}
