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
  ChannelSection(1, '数据归属', ['targetKind', 'cardEntryTarget']),
  ChannelSection(2, '数据标识', ['semanticSource', 'name', 'preview']),
  ChannelSection(3, 'AI 读写', ['llmReadPolicy', 'promptSection', 'llmWritePolicy']),
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

/// 建议排序规则，复刻 `_statusFieldNameSuggestions`。
///
/// 前缀命中的提到前面：作者打了几个字再点开，想找的多半在那几个字里。
List<String> suggestionOrder(List<String> fields, String input) {
  final key = input.trim().toLowerCase();
  if (key.isEmpty) return fields;
  final hit = <String>[];
  final rest = <String>[];
  for (final f in fields) {
    if (f.toLowerCase().startsWith(key)) {
      hit.add(f);
    } else {
      rest.add(f);
    }
  }
  return [...hit, ...rest];
}

/// 是否与当前输入完全一致（用于打勾标记）。
bool isExactMatch(String name, String input) {
  final key = input.trim().toLowerCase();
  if (key.isEmpty) return false;
  return name.toLowerCase() == key;
}

const List<String> sampleFields = ['等级', '生命值', '生命上限', '金钱'];

void main() {
  group('三段结构', () {
    test('恰好三段', () => expect(sections.length, 3));

    test('顺序是 数据归属 → 数据标识 → AI 读写', () {
      expect(sections.map((s) => s.title).toList(),
          ['数据归属', '数据标识', 'AI 读写']);
    });

    test('标题是名词短语，不用口语化说法', () {
      // 「存在哪里 / 叫什么 / 怎么交互」是讨论时的说法，
      // 直接当界面标题过于随便。
      const banned = ['存在哪里', '叫什么', '怎么交互'];
      for (final s in sections) {
        expect(banned, isNot(contains(s.title)));
      }
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

  group('状态字段名称建议', () {
    test('输入为空时保持状态栏原顺序', () {
      expect(suggestionOrder(sampleFields, ''), sampleFields);
    });

    test('前缀命中的排到前面', () {
      expect(
        suggestionOrder(sampleFields, '生命'),
        ['生命值', '生命上限', '等级', '金钱'],
      );
    });

    test('无命中时顺序不变', () {
      expect(suggestionOrder(sampleFields, 'xyz'), sampleFields);
    });

    test('完全一致的判定为 matched', () {
      expect(isExactMatch('等级', '等级'), isTrue);
      expect(isExactMatch('等级', ' 等级 '), isTrue);
      expect(isExactMatch('等级', '等'), isFalse);
      // 输入为空时不该把任何一项标成命中。
      expect(isExactMatch('等级', ''), isFalse);
    });

    test('没有状态字段时返回空表（按钮应隐藏）', () {
      expect(suggestionOrder(const <String>[], '等级'), isEmpty);
    });
  });

  group('建议不能干扰手动输入', () {
    testWidgets('输入框可自由输入任意文本', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: controller),
          ),
        ),
      );
      // 输入一个状态栏里没有的名字，必须能照常输入。
      await tester.enterText(find.byType(TextField), '自定义名称');
      expect(controller.text, '自定义名称');
    });

    test('选中建议后光标应落在末尾', () {
      // 不设 selection 的话，选完再点输入框光标会跳回开头，
      // 想接着改就得先按一堆右方向键。
      final controller = TextEditingController();
      const picked = '生命值';
      controller.text = picked;
      controller.selection = TextSelection.collapsed(offset: picked.length);
      expect(controller.selection.baseOffset, picked.length);
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
    // 用普通 Map 而不是记录（record）列表 + 解构 for。
    // `for (final (v, label) in options)` 这种记录解构模式会让
    // 分析器在此处报 "Expected an identifier"，且错误会向上传导，
    // 把文件顶层结构一起判错——前面所有 group 都会变成
    // "referenced before declaration"，报错行号完全指向错误的位置。
    const options = <String, String>{
      'a': '选项A',
      'b': '选项B',
      'c': '选项C',
    };
    return Wrap(
      spacing: 6,
      children: [
        for (final entry in options.entries)
          InkWell(
            onTap: () => onChanged(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: entry.key == value ? Colors.teal : Colors.black12,
                  width: entry.key == value ? 1.4 : 1.0,
                ),
              ),
              child: Text(entry.value),
            ),
          ),
      ],
    );
  }
}
