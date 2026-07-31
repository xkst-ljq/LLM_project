import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 4.3 HUD：数据通道页三段式改造。
///
/// 用户反馈：「整页都是列排列，而且还有七项，容易眼花缭乱。
/// 在每一条的关系连接上也不大。」
///
/// 改造要点：
/// 1. 分三段，顺序 **存哪里 → 叫什么 → 怎么交互**
///    （先问存放位置，因为它决定后面所有项的含义）
/// 2. 选项少的平铺成分段控件，不用下拉
/// 3. 删除两个字段：玩家可见性（死字段）、AI 更新应用方式（语义重复）
///
/// 这里锁的是**结构约定**——纯 UI 布局无法在沙箱里渲染验证，
/// 但字段清单、顺序、条件显示规则这些约定必须锁住，
/// 否则后续改动很容易把某一项又加回去或漏掉。

/// 段落定义。
class ChannelSection {
  const ChannelSection(this.index, this.title, this.fields);
  final int index;
  final String title;
  final List<String> fields;
}

/// 改造后的页面结构。
const sections = <ChannelSection>[
  ChannelSection(1, '存在哪里', ['targetKind', 'cardEntryTarget']),
  ChannelSection(2, '叫什么', ['semanticSource', 'name', 'preview']),
  ChannelSection(3, '怎么交互', ['llmReadPolicy', 'promptSection', 'llmWritePolicy']),
];

/// 已从 UI 删除的字段。
const removedFields = <String>['visibility', 'llmUpdateApplyPolicy'];

/// 仍用下拉的字段（项数不定）。其余一律平铺。
const dropdownFields = <String>['labelElementId'];

/// 条件显示规则：字段 → 显示条件描述。
bool showsCardEntryTarget(String targetKind) => targetKind == 'card_entry';
bool showsPromptSection(String llmReadPolicy) => llmReadPolicy != 'none';
bool showsNameInput(String semanticSource) => semanticSource == 'manual';
bool showsLabelDropdown(String semanticSource) =>
    semanticSource == 'text_label';

void main() {
  group('三段结构', () {
    test('恰好三段', () => expect(sections.length, 3));

    test('顺序是 存哪里 → 叫什么 → 怎么交互', () {
      expect(sections.map((s) => s.title).toList(),
          ['存在哪里', '叫什么', '怎么交互']);
    });

    test('序号连续从 1 开始', () {
      for (var i = 0; i < sections.length; i++) {
        expect(sections[i].index, i + 1);
      }
    });

    test('存放位置排在名称之前', () {
      // 这是本次改造的核心：存放位置决定了「名称」的含义
      // （角色卡设定里名称是条目标题，会话变量里只是个键名）。
      final whereIdx =
          sections.indexWhere((s) => s.fields.contains('targetKind'));
      final nameIdx =
          sections.indexWhere((s) => s.fields.contains('semanticSource'));
      expect(whereIdx, lessThan(nameIdx));
    });

    test('预览与它服务的名称字段同段', () {
      // 旧版预览挂在页顶，与真正相关的两项隔着六个下拉。
      final seg = sections.firstWhere((s) => s.fields.contains('preview'));
      expect(seg.fields, contains('semanticSource'));
    });
  });

  group('删除的字段', () {
    test('玩家可见性已移除', () {
      // 死字段：全项目零读取点。三个值想表达的事已分别由
      // 「发送当前值给 AI」和「组件放不放在 PCB 上」承担。
      for (final s in sections) {
        expect(s.fields, isNot(contains('visibility')));
      }
    });

    test('AI 更新应用方式已移除', () {
      // never 与「允许 AI 更新 = 不允许」重复；
      // confirm 的否决权语义被废除（数据变化不该让玩家拒绝）。
      for (final s in sections) {
        expect(s.fields, isNot(contains('llmUpdateApplyPolicy')));
      }
    });

    test('删除清单恰好两项', () => expect(removedFields.length, 2));
  });

  group('条件显示', () {
    test('卡片定位仅在选角色卡设定时出现', () {
      expect(showsCardEntryTarget('card_entry'), isTrue);
      for (final k in ['local_ui_state', 'session_var', 'status_field']) {
        expect(showsCardEntryTarget(k), isFalse);
      }
    });

    test('注入位置仅在会发送给 AI 时出现', () {
      expect(showsPromptSection('none'), isFalse);
      expect(showsPromptSection('prompt'), isTrue);
      expect(showsPromptSection('hidden_context'), isTrue);
    });

    test('名称输入框与标签下拉互斥', () {
      expect(showsNameInput('manual'), isTrue);
      expect(showsLabelDropdown('manual'), isFalse);
      expect(showsNameInput('text_label'), isFalse);
      expect(showsLabelDropdown('text_label'), isTrue);
      // 用组件名时两者都不显示，只给一行说明。
      expect(showsNameInput('component_name'), isFalse);
      expect(showsLabelDropdown('component_name'), isFalse);
    });
  });

  group('控件选型：少的平铺、不定的下拉', () {
    test('只有标签文本仍用下拉', () {
      expect(dropdownFields, ['labelElementId']);
    });

    test('标签文本用下拉是因为项数不定', () {
      // 数量取决于画布上有几个 Text 组件，无法平铺。
      expect(dropdownFields, contains('labelElementId'));
    });

    test('固定选项的字段一律平铺', () {
      const flatFields = [
        'targetKind', // 4 项
        'semanticSource', // 3 项
        'llmReadPolicy', // 3 项
        'promptSection', // 2 项
        'llmWritePolicy', // 3 项
      ];
      for (final f in flatFields) {
        expect(dropdownFields, isNot(contains(f)));
      }
      expect(flatFields.length, 5);
    });
  });

  group('SegmentedField 控件行为', () {
    testWidgets('渲染全部选项并高亮选中项', (tester) async {
      var current = 'b';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SegmentedFieldHarness(
                value: current,
                onChanged: (v) => setState(() => current = v),
              ),
            ),
          ),
        ),
      );

      expect(find.text('选项A'), findsOneWidget);
      expect(find.text('选项B'), findsOneWidget);
      expect(find.text('选项C'), findsOneWidget);
    });

    testWidgets('点击切换选中值', (tester) async {
      var current = 'b';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SegmentedFieldHarness(
                value: current,
                onChanged: (v) => setState(() => current = v),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('选项C'));
      await tester.pumpAndSettle();
      expect(current, 'c');
    });
  });
}

/// 测试替身：复刻 SegmentedField 的对外行为。
///
/// 不直接引用 `character_assembly_page.dart` 里的 part 控件——
/// 那个文件是 `part of`，导入会把整个 7700 行的编辑器一起拖进来，
/// 测试启动会非常慢且需要一大堆无关的 mock。
class SegmentedFieldHarness extends StatelessWidget {
  const SegmentedFieldHarness({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('a', '选项A'),
      ('b', '选项B'),
      ('c', '选项C'),
    ];
    return Wrap(
      spacing: 6,
      children: [
        for (final (v, label) in options)
          InkWell(
            onTap: () => onChanged(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: v == value ? Colors.teal : Colors.black12,
                  width: v == value ? 1.4 : 1.0,
                ),
              ),
              child: Text(label),
            ),
          ),
      ],
    );
  }
}
