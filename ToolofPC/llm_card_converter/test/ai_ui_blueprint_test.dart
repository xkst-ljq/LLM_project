import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_card_converter/core/ai_ui_blueprint.dart';
import 'package:llm_card_converter/core/ai_ui_designer.dart';

void main() {
  group('UiBlueprint - 分条目蓝图', () {
    test('从 JSON 解析蓝图条目', () {
      final bp = UiBlueprint.fromJson({
        'cardName': '异世界公会',
        'items': [
          {
            'index': 1,
            'kind': 'status_bar',
            'title': '玩家状态',
            'intent': '展示 HP/MP 等数值',
            'fields': ['HP', 'MP', 'Name'],
            'relationship': '主页面顶部',
          },
          {
            'index': 2,
            'kind': 'quest_list',
            'title': '任务卡',
            'intent': '任务信息列表',
            'fields': ['quest', 'desc'],
          },
        ],
        'reasoning': ['第一步思考'],
      });
      expect(bp.items.length, 2);
      expect(bp.items[0].kind, 'status_bar');
      expect(bp.items[0].fields, contains('HP'));
      expect(bp.items[0].keep, isTrue);
      expect(bp.hasUi, isTrue);
    });

    test('keptItems 排除被删除条目', () {
      final bp = UiBlueprint(
        cardName: '测试',
        items: [
          BlueprintItem(index: 1, kind: 'status_bar', title: 'A'),
          BlueprintItem(index: 2, kind: 'quest_list', title: 'B', keep: false),
        ],
      );
      final kept = bp.items.where((i) => i.keep).toList();
      expect(kept.length, 1);
      expect(kept.first.title, 'A');
    });
  });

  group('UiReviewIssue - 自检问题', () {
    test('从 JSON 解析自检问题', () {
      final issue = UiReviewIssue.fromJson({
        'severity': 'error',
        'page': 'lobby',
        'message': '字段与消息流重叠',
        'suggestion': '下移字段',
      });
      expect(issue.severity, 'error');
      expect(issue.page, 'lobby');
      expect(issue.suggestion, '下移字段');
    });
  });

  group('UiCreationIntent.toJson - 供自检序列化', () {
    test('意图能序列化为 JSON', () {
      final intent = UiCreationIntent(
        mode: 'scene',
        pages: const [
          ScenePage(id: 'lobby', name: '公会大厅', pcbHeight: 800),
        ],
        activePage: 'lobby',
        panels: const [
          UiPanel(
            kind: 'status_bar',
            page: 'lobby',
            title: '状态',
            fields: [
              UiFieldIntent(
                name: 'HP', type: 'number', display: 'progress',
                min: 0, max: 100, initialValue: '100', x: 14, y: 30,
              ),
            ],
          ),
        ],
        reasoning: const ['思考'],
      );
      final json = jsonDecode(jsonEncode(intent.toJson())) as Map;
      final scene = json['scene'] as Map;
      expect(scene['activePage'], 'lobby');
      final panels = json['panels'] as List;
      expect(panels.length, 1);
      final fields = (panels.first as Map)['fields'] as List;
      expect((fields.first as Map)['name'], 'HP');
    });
  });
}
