/// 把 [UiExtraction] 的提取结果，构建成合法的 LLM Project assembly JSON。
///
/// ## 为什么这一步绝不能交给 AI
///
/// 目标结构有一堆「写错不报错、只是静默失效」的陷阱
/// （见 `ASSEMBLY_HANDOFF.md` 3.5j）：
///
/// - `elements` / `pages` 是**三层嵌套的 JSON 字符串**，少一层 encode 就读不到；
/// - `material` / `shape` 是**枚举下标整数**，写 `'solid'` 会静默回落成 0；
/// - `color` 是 **ARGB 整数**，不是 `#RRGGBB`；
/// - `createdAt` 是**毫秒时间戳**，写 ISO 字符串会直接抛异常；
/// - `keyAction` 键名写错 → `opening`/`scene` **整层不渲染**。
///
/// 我自己手写 JSON 已经栽过三次（键名、类型、结构各一次）。
/// AI 生成只会错得更多、更难查。**所以这里是确定性代码，
/// 每个字段都有明确出处，产物再过 `validate_card.py`。**
///
/// ## 布局策略：朴素但可靠
///
/// 这一版**不追求还原原卡外观**，只保证「信息不丢、结构正确、能渲染」。
/// 视觉还原是后续 AI 层的事——先有能跑的骨架，再往上做美化。
///
/// 布局用最简单的纵向流式排布：
///
/// ```
/// ┌─────────────────────┐
/// │ 底板 surface        │
/// │  ┌───────────────┐  │
/// │  │ 标题 text      │  │
/// │  ├───────────────┤  │
/// │  │ 生命  ▓▓▓░░ 72 │  │  ← 数值字段：标签 + progress
/// │  │ 精神  ▓▓▓▓░ 85 │  │
/// │  ├───────────────┤  │
/// │  │ 称号：囚犯     │  │  ← 文本字段：单行 text
/// │  └───────────────┘  │
/// └─────────────────────┘
/// ```
library;

import 'dart:convert';
import 'regex_ui_extractor.dart';
import 'ui_understanding/ui_design_plan.dart';

/// 构建时的布局常量。
///
/// 单独抽出来是因为它们会被多处引用，散落在代码里改一处漏一处。
class _Layout {
  static const double pcbPadding = 12;
  static const double rowHeight = 22;
  static const double rowGap = 6;
  static const double barHeight = 10;
  static const double buttonHeight = 34;

  /// 单份 UI 最多放多少字段。
  ///
  /// 异世界公会的「好友列表」有 20 个字段，全放进伴生 UI 会超高。
  /// 超出的部分丢弃并在 notes 里说明——**宁可少放也不要生成一个
  /// 高度 2000 的巨型面板**（PCB 上限就是 2000）。
  static const int maxFields = 14;
}

/// 配色。取自引擎示例卡的深色系，保证文字对比度达标。
///
/// 小字（<14px）按 WCAG **AAA 7:1** 要求，不是 4.5:1
/// ——状态栏的标签基本都是 11~12px。
class UiVisualTheme {
  final int pcbColor;
  final int panelColor;
  final int titleColor;
  final int labelColor;
  final int valueColor;
  final int barFillColor;
  final int barTrackColor;
  final int accentColor;
  final int buttonBgColor;
  final double borderRadius;
  final bool glow;

  const UiVisualTheme({
    required this.pcbColor,
    required this.panelColor,
    required this.titleColor,
    required this.labelColor,
    required this.valueColor,
    required this.barFillColor,
    required this.barTrackColor,
    required this.accentColor,
    required this.buttonBgColor,
    required this.borderRadius,
    required this.glow,
  });

  factory UiVisualTheme.defaultTheme() => const UiVisualTheme(
        pcbColor: 0xFF15161A,
        panelColor: 0xFF1E2027,
        titleColor: 0xFFFFFFFF,
        labelColor: 0xFFAAB0BC,
        valueColor: 0xFFE8EDF5,
        barFillColor: 0xFF4FA3D1,
        barTrackColor: 0xFF2A2D36,
        accentColor: 0xFF4FA3D1,
        buttonBgColor: 0xFF2A3340,
        borderRadius: 14.0,
        glow: false,
      );

  factory UiVisualTheme.fromJson(Map<String, dynamic> json) {
    int parseColor(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is String) {
        final s = v.trim().replaceAll('#', '');
        if (s.length == 6) {
          return int.tryParse('FF$s', radix: 16) ?? fallback;
        } else if (s.length == 8) {
          return int.tryParse(s, radix: 16) ?? fallback;
        }
      }
      return fallback;
    }

    double parseDouble(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    final d = UiVisualTheme.defaultTheme();
    return UiVisualTheme(
      pcbColor: parseColor(json['pcbColor'], d.pcbColor),
      panelColor: parseColor(json['panelColor'], d.panelColor),
      titleColor: parseColor(json['titleColor'], d.titleColor),
      labelColor: parseColor(json['labelColor'], d.labelColor),
      valueColor: parseColor(json['valueColor'], d.valueColor),
      barFillColor: parseColor(json['barFillColor'], d.barFillColor),
      barTrackColor: parseColor(json['barTrackColor'], d.barTrackColor),
      accentColor: parseColor(json['accentColor'], d.accentColor),
      buttonBgColor: parseColor(json['buttonBgColor'], d.buttonBgColor),
      borderRadius: parseDouble(json['borderRadius'], d.borderRadius)
          .clamp(0.0, 32.0)
          .toDouble(),
      glow: json['glow'] == true,
    );
  }
}

/// 构建结果。
class BuiltAssembly {
  const BuiltAssembly({
    required this.assemblies,
    required this.statusFields,
    required this.notes,
  });

  /// 可直接写进 `meta_json.ui_assemblies` 的 JSON 字符串列表。
  final List<String> assemblies;

  /// 需要一并写进 `meta_json.status_bar_fields` 的状态栏字段。
  ///
  /// 数值型 UI 字段绑到状态字段上，LLM 才能读写它们
  /// ——否则界面只是个静态装饰。
  final List<Map<String, dynamic>> statusFields;

  final List<String> notes;

  bool get isEmpty => assemblies.isEmpty;
}

/// 构建器本体。
class UiAssemblyBuilder {
  const UiAssemblyBuilder._();

  static BuiltAssembly build(UiExtraction ex, {String cardName = '', UiVisualTheme? theme}) {
    final notes = <String>[];
    final visualTheme = theme ?? UiVisualTheme.defaultTheme();

    if (ex.pluginDependent) {
      notes.add('依赖外部插件，跳过 UI 生成。');
      return BuiltAssembly(
          assemblies: const [], statusFields: const [], notes: notes);
    }

    final usable = ex.usableScripts;
    if (usable.isEmpty && ex.openingActions.isEmpty) {
      notes.add('原卡没有可识别的界面元素，不生成 UI。');
      return BuiltAssembly(
          assemblies: const [], statusFields: const [], notes: notes);
    }

    final assemblies = <String>[];
    final statusFields = <Map<String, dynamic>>[];
    var seed = DateTime.now().millisecondsSinceEpoch;
    String nextId(String prefix) => '${prefix}_${seed++}';

    // ── 主状态面板 ──
    //
    // 挑字段最多的那条脚本。一张卡常有多个"皮肤"版本
    // （异世界公会有「玩家状态栏」和「玩家状态栏（古早游戏版）」），
    // 内容相同只是外观不同，全转会得到几份重复 UI。
    final primary = pickPrimary(usable);
    if (primary != null) {
      final skipped = usable.length - 1;
      if (skipped > 0) {
        notes.add('原卡有 ${usable.length} 条 UI 脚本，'
            '取字段最多的「${primary.scriptName}」生成主面板'
            '（其余多为同内容的换肤版本）。');
      }
      final r = _buildStatusPanel(
        primary,
        nextId,
        cardName,
        ex.branchPresets,
        visualTheme,
        ex.openingActions,
      );
      if (r != null) {
        assemblies.add(r.assemblyJson);
        statusFields.addAll(r.statusFields);
        notes.addAll(r.notes);
      }
    }

    // ── 开场选项页 ──
    //
    // `onclick="send('...')"` 是明确的交互意图，
    // 对应 button + sendsMessage，做成 opening 开场页。
    if (ex.openingActions.isNotEmpty) {
      final json = _buildOpeningPage(ex.openingActions, nextId, cardName, visualTheme, ex.cleanFirstMes);
      assemblies.add(json);
      notes.add('开场消息里的 ${ex.openingActions.length} 个选项'
          '已转为可点击按钮（opening 开场页）。');
    }

    return BuiltAssembly(
      assemblies: assemblies,
      statusFields: statusFields,
      notes: notes,
    );
  }

  /// AI UiDesignPlan → 合法 assembly/status_bar_fields。
  ///
  /// AI 只负责输出高层计划；内部 JSON 的三层 encode、ARGB、枚举下标、
  /// keyAction 等易错细节仍由这里的确定性代码收口。
  static BuiltAssembly buildFromPlan(
    UiDesignPlan plan, {
    String cardName = '',
  }) {
    final notes = <String>[];
    if (!plan.hasUi) {
      final reason = plan.evidenceSummary.trim().isEmpty
          ? 'AI 判断原卡没有可转译 UI。'
          : 'AI 判断不生成 UI：${plan.evidenceSummary}';
      return BuiltAssembly(
        assemblies: const [],
        statusFields: const [],
        notes: [reason, ...plan.notes],
      );
    }

    final theme = UiVisualTheme.fromJson({
      'pcbColor': plan.visualStyle.pcbColor,
      'panelColor': plan.visualStyle.panelColor,
      'titleColor': plan.visualStyle.titleColor,
      'labelColor': plan.visualStyle.labelColor,
      'valueColor': plan.visualStyle.valueColor,
      'barFillColor': plan.visualStyle.barFillColor,
      'barTrackColor': plan.visualStyle.barTrackColor,
      'accentColor': plan.visualStyle.accentColor,
      'buttonBgColor': plan.visualStyle.buttonBgColor,
      'borderRadius': plan.visualStyle.borderRadius,
      'glow': plan.visualStyle.glow,
    });

    var seed = DateTime.now().millisecondsSinceEpoch;
    String nextId(String prefix) => '${prefix}_${seed++}';

    final statusFields = <Map<String, dynamic>>[];
    final pageTitles = _planPageTitles(plan);
    final pageIds = <String, String>{
      for (final title in pageTitles) title: 'page_${nextId('page')}',
    };

    final fieldsByPage = <String, List<UiPlanField>>{
      for (final title in pageTitles) title: <UiPlanField>[],
    };
    final inputsByPage = <String, List<UiPlanInput>>{
      for (final title in pageTitles) title: <UiPlanInput>[],
    };
    final actionsByPage = <String, List<UiPlanAction>>{
      for (final title in pageTitles) title: <UiPlanAction>[],
    };
    for (final f in _dedupePlanFields(plan.fields)) {
      final page = _resolvePlanPage(f.page, pageTitles, f.isNumber ? '属性' : '档案');
      fieldsByPage.putIfAbsent(page, () => <UiPlanField>[]).add(f);
    }
    for (final input in plan.inputs) {
      final page = _resolvePlanPage(input.page, pageTitles, '选项');
      inputsByPage.putIfAbsent(page, () => <UiPlanInput>[]).add(input);
    }
    for (final a in plan.actions) {
      final page = _resolvePlanPage(a.page, pageTitles, '选项');
      actionsByPage.putIfAbsent(page, () => <UiPlanAction>[]).add(a);
    }

    final mode = plan.uiMode;
    final pcbW = switch (mode) {
      'extra_companion' => 212.0,
      'opening' => 320.0,
      'scene' => 360.0,
      'extra_sticky' => 320.0,
      _ => 212.0,
    };
    final innerW = pcbW - _Layout.pcbPadding * 2;
    final pages = <Map<String, dynamic>>[];
    final pageHeights = <double>[];

    for (var i = 0; i < pageTitles.length; i++) {
      final title = pageTitles[i];
      final elements = _buildPlanPageElements(
        pageTitle: title,
        pageTitles: pageTitles,
        pageIds: pageIds,
        fields: fieldsByPage[title] ?? const [],
        inputs: inputsByPage[title] ?? const [],
        actions: actionsByPage[title] ?? const [],
        nextId: nextId,
        statusFields: statusFields,
        theme: theme,
        mode: mode,
        pcbW: pcbW,
        innerW: innerW,
      );
      final h = _pageContentHeight(elements);
      pageHeights.add(h);
      pages.add({
        'id': pageIds[title],
        'name': title,
        'type': 'base',
        'parentPageId': null,
        'sortOrder': i,
        'elements': elements,
        'gestures': _planGesturesForPage(
          mode: mode,
          index: i,
          pageTitles: pageTitles,
          pageIds: pageIds,
          navigation: plan.layout.navigation,
        ),
        'propertyOverrides': <dynamic>[],
      });
    }

    final pcbH = pageHeights.isEmpty
        ? 96.0
        : pageHeights.reduce((a, b) => a > b ? a : b);
    for (final page in pages) {
      final elements = page['elements'];
      if (elements is! List) continue;
      for (final element in elements) {
        if (element is Map && element['name'] == '底板') {
          final size = element['size'];
          if (size is Map) size['height'] = pcbH;
        }
      }
    }

    notes.add('AI 已理解原卡 UI 并生成 ${plan.uiName}（置信度 ${plan.confidence.toStringAsFixed(2)}）。');
    if (plan.evidenceSummary.trim().isNotEmpty) {
      notes.add('UI 证据：${plan.evidenceSummary.trim()}');
    }
    notes.addAll(plan.notes);
    for (final item in plan.unsupported) {
      final reason = item.reason.trim().isEmpty ? item.kind : item.reason.trim();
      notes.add('未转译：$reason${item.sourceRef.trim().isEmpty ? '' : '（${item.sourceRef}）'}');
    }

    return BuiltAssembly(
      assemblies: [
        _assembly(
          id: nextId('asm'),
          name: plan.uiName.trim().isEmpty
              ? '${cardName.isEmpty ? '角色' : cardName} UI'
              : plan.uiName,
          mode: mode,
          pcbW: pcbW,
          pcbH: pcbH,
          pages: pages,
          pcbColor: theme.pcbColor,
          pcbRadius: theme.borderRadius,
        ),
      ],
      statusFields: statusFields,
      notes: notes,
    );
  }

  // ─────────────────────── 主状态面板 ───────────────────────

  /// 挑一条脚本做主状态面板。
  ///
  /// **不能只看字段数量。** 实测异世界公会那张卡：
  ///
  /// | 脚本 | 字段 | 数值 |
  /// |---|---|---|
  /// | 好友列表 | 20 | **0** |
  /// | 玩家状态栏 | 15 | **10** |
  ///
  /// 「好友列表」字段更多，但那是 `name1/level1/equip1...` 三个好友的
  /// 重复条目，全是文本；真正的状态面板是「玩家状态栏」（HP/MP/XP 等）。
  /// 按数量挑会选错。
  ///
  /// 排序依据：**数值字段数优先**（状态面板的本质是数值），
  /// 数值相同再比总字段数。
  static UiRegexScript? pickPrimary(List<UiRegexScript> scripts) {
    if (scripts.isEmpty) return null;
    final sorted = [...scripts]
      ..sort((a, b) {
        final an = a.fields.where((f) => f.isNumeric).length;
        final bn = b.fields.where((f) => f.isNumeric).length;
        if (an != bn) return bn.compareTo(an);
        return b.fields.length.compareTo(a.fields.length);
      });
    return sorted.first;
  }

  static _PanelResult? _buildStatusPanel(
    UiRegexScript script,
    String Function(String) nextId,
    String cardName,
    Map<int, Map<String, String>> branchPresets,
    UiVisualTheme theme,
    List<String> openingActions,
  ) {
    final notes = <String>[];

    // 「正文」这类整段叙事不适合塞进状态面板──
    // 它是消息正文本身，不是状态。
    final fields = script.fields
        .where((f) => !_isNarrativeField(f.name))
        .toList();
    if (fields.isEmpty) return null;

    var used = fields;
    if (used.length > _Layout.maxFields) {
      used = used.sublist(0, _Layout.maxFields);
      notes.add('字段过多（${fields.length} 个），'
          '已限制前 ${_Layout.maxFields} 个以防高度溢出。');
    }

    final numeric = used.where((f) => f.isNumeric).toList();
    final textual = used.where((f) => !f.isNumeric).toList();

    final barFields = <UiField>[];
    final overflowFields = <UiField>[];
    for (final f in numeric) {
      if (_fitsPercentBar(_presetsOf(branchPresets, f.name, numeric: true))) {
        barFields.add(f);
      } else {
        overflowFields.add(f);
      }
    }
    final textual2 = [...textual, ...overflowFields];

    // 分页切分
    final tab1Fields = barFields;
    final tab2Fields = textual2;

    const pcbW = 212.0;
    final innerW = pcbW - _Layout.pcbPadding * 2;

    final hasActions = openingActions.isNotEmpty;
    final tabCount = hasActions ? 3 : 2;

    // 创建平级页面的 ID
    final page1Id = 'page_${nextId("page")}';
    final page2Id = 'page_${nextId("page")}';
    final page3Id = hasActions ? 'page_${nextId("page")}' : '';

    final statusFields = <Map<String, dynamic>>[];

    // 编译第一页 (📊 属性)
    final elements1 = _buildPageElements(
      pageIndex: 1,
      fields: tab1Fields,
      actions: const [],
      nextId: nextId,
      branchPresets: branchPresets,
      statusFields: statusFields,
      theme: theme,
      page1Id: page1Id,
      page2Id: page2Id,
      page3Id: page3Id,
      pcbW: pcbW,
      innerW: innerW,
      tabCount: tabCount,
    );
    final page1 = {
      'id': page1Id,
      'name': '属性',
      'type': 'base',
      'parentPageId': null,
      'sortOrder': 0,
      'elements': elements1,
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };

    // 编译第二页 (📁 档案)
    final elements2 = _buildPageElements(
      pageIndex: 2,
      fields: tab2Fields,
      actions: const [],
      nextId: nextId,
      branchPresets: branchPresets,
      statusFields: statusFields,
      theme: theme,
      page1Id: page1Id,
      page2Id: page2Id,
      page3Id: page3Id,
      pcbW: pcbW,
      innerW: innerW,
      tabCount: tabCount,
    );
    final page2 = {
      'id': page2Id,
      'name': '档案',
      'type': 'base',
      'parentPageId': null,
      'sortOrder': 1,
      'elements': elements2,
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };

    // 编译第三页 (🎯 选项)
    final elements3 = hasActions
        ? _buildPageElements(
            pageIndex: 3,
            fields: const [],
            actions: openingActions,
            nextId: nextId,
            branchPresets: branchPresets,
            statusFields: statusFields,
            theme: theme,
            page1Id: page1Id,
            page2Id: page2Id,
            page3Id: page3Id,
            pcbW: pcbW,
            innerW: innerW,
            tabCount: tabCount,
          )
        : const <Map<String, dynamic>>[];
    final page3 = hasActions
        ? {
            'id': page3Id,
            'name': '选项',
            'type': 'base',
            'parentPageId': null,
            'sortOrder': 2,
            'elements': elements3,
            'gestures': <dynamic>[],
            'propertyOverrides': <dynamic>[],
          }
        : null;

    // 动态计算最大高度，使页面高度对齐统一不缩放
    double getMaxHeight(List<Map<String, dynamic>> elList) {
      double maxH = 0.0;
      for (final e in elList) {
        if (e['id'].toString().startsWith('el_')) {
          final offset = e['offset'] as Map;
          final size = e['size'] as Map;
          final h = (offset['y'] as num).toDouble() + (size['height'] as num).toDouble();
          if (h > maxH) maxH = h;
        }
      }
      return (maxH + _Layout.pcbPadding).clamp(64.0, 2000.0).toDouble();
    }

    final heights = [
      getMaxHeight(elements1),
      getMaxHeight(elements2),
      if (hasActions) getMaxHeight(elements3),
    ];
    final pcbH = heights.reduce((a, b) => a > b ? a : b);

    // 统一将底板高度打补丁
    void patchBackgroundHeight(List<Map<String, dynamic>> elList) {
      for (var i = 0; i < elList.length; i++) {
        if (elList[i]['name'] == '底板') {
          elList[i]['size']['height'] = pcbH;
        }
      }
    }
    patchBackgroundHeight(elements1);
    patchBackgroundHeight(elements2);
    if (hasActions) patchBackgroundHeight(elements3);

    final pagesLabel = hasActions ? '📊属性/📁档案/🎯选项' : '📊属性/📁档案';
    notes.add('通过多页面 ($pagesLabel) 与顶置 Tab 标签切换按钮整合面板属性与预设选项，使信息流与操作深度聚合。');

    final pList = <Map<String, dynamic>>[page1, page2];
    if (page3 != null) {
      pList.add(page3);
    }

    return _PanelResult(
      assemblyJson: _assembly(
        id: nextId('asm'),
        name: '${cardName.isEmpty ? "角色" : cardName}状态栏',
        mode: 'extra_companion',
        pcbW: pcbW,
        pcbH: pcbH,
        pages: pList,
        pcbColor: theme.pcbColor,
        pcbRadius: theme.borderRadius,
      ),
      statusFields: statusFields,
      notes: notes,
    );
  }

  static List<Map<String, dynamic>> _buildPageElements({
    required int pageIndex,
    required List<UiField> fields,
    required List<String> actions,
    required String Function(String) nextId,
    required Map<int, Map<String, String>> branchPresets,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String page1Id,
    required String page2Id,
    required String page3Id,
    required double pcbW,
    required double innerW,
    required int tabCount,
  }) {
    final elements = <Map<String, dynamic>>[];
    var y = _Layout.pcbPadding;

    // ── 1. 顶部 Tab 标签切换栏 ──
    final tabW = (innerW - (tabCount - 1) * 6.0) / tabCount;
    final tabH = 22.0;

    final tabs = [
      (index: 1, title: '📊 属性', pageId: page1Id),
      (index: 2, title: '📁 档案', pageId: page2Id),
      if (tabCount > 2) (index: 3, title: '🎯 选项', pageId: page3Id),
    ];

    final routerIds = <int, String>{};
    for (final tab in tabs) {
      if (tab.index != pageIndex) {
        final rId = nextId('el');
        routerIds[tab.index] = rId;
        elements.add(_pageRouter(
          id: rId,
          name: '路由器_${tab.title}',
          targetPageId: tab.pageId,
        ));
      }
    }

    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final isActive = tab.index == pageIndex;
      final tabX = _Layout.pcbPadding + i * (tabW + 6.0);

      final sId = nextId('el');
      elements.add(_surface(
        id: sId,
        name: '标签底_${tab.title}',
        x: tabX,
        y: y,
        w: tabW,
        h: tabH,
        color: isActive ? theme.accentColor : theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 6.0,
      ));

      elements.add(_text(
        id: nextId('el'),
        name: '标签文_${tab.title}',
        text: tab.title,
        x: tabX + 2,
        y: y + 4,
        w: tabW - 4,
        h: 14,
        fontSize: 9,
        color: isActive ? theme.titleColor : theme.labelColor,
        align: 'center',
        layer: elements.length + 1,
      ));

      if (!isActive) {
        final bId = nextId('el');
        elements.add(_button(
          id: bId,
          name: '标签按_${tab.title}',
          x: tabX,
          y: y,
          w: tabW,
          h: tabH,
          layer: elements.length + 1,
          sendsMessage: false,
          keyAction: false,
          color: 0x00000000, // 保持完全透明作为按钮点击热区
        ));

        elements.add(_pressLinker2(
          id: nextId('el'),
          name: '标签跳_${tab.title}',
          buttonId: bId,
          routerId: routerIds[tab.index]!,
          scheme: 'button_to_page_route',
          y: i * 52.0,
          layer: elements.length + 1,
        ));
      }
    }

    y += tabH + 12.0;
    const colLabelW = 50.0;

    // ── 2. 渲染专页的属性列表数据（单列最松弛排布，完全不拥挤） ──
    if (pageIndex == 3 && tabCount > 2) {
      final pressPairs = <({String surface, String button})>[];
      for (var i = 0; i < actions.length; i++) {
        final label = actions[i];
        final surfaceId = nextId('el');
        elements.add(_surface(
          id: surfaceId,
          name: '选项底_${i + 1}',
          x: _Layout.pcbPadding,
          y: y,
          w: innerW,
          h: _Layout.buttonHeight,
          color: theme.buttonBgColor,
          layer: elements.length + 1,
          radius: 8,
        ));
        elements.add(_text(
          id: nextId('el'),
          name: '选项文_${i + 1}',
          text: label,
          x: _Layout.pcbPadding + 10,
          y: y + 8,
          w: innerW - 20,
          h: 18,
          fontSize: 10,
          color: theme.valueColor,
          align: 'left',
          layer: elements.length + 1,
        ));
        final buttonId = nextId('el');
        elements.add(_button(
          id: buttonId,
          name: '选项_${i + 1}',
          x: _Layout.pcbPadding,
          y: y,
          w: innerW,
          h: _Layout.buttonHeight,
          layer: elements.length + 1,
          sendsMessage: true,
          keyAction: true,
          message: label,
          targetBranchIndex: i,
          color: theme.accentColor,
        ));
        pressPairs.add((surface: surfaceId, button: buttonId));
        y += _Layout.buttonHeight + 6.0;
      }

      // 按压反馈
      for (var i = 0; i < pressPairs.length; i++) {
        elements.add(_pressLinker(
          id: nextId('el'),
          name: '选项_${i + 1}按压',
          buttonId: pressPairs[i].button,
          surfaceId: pressPairs[i].surface,
          y: i * 52.0,
          layer: elements.length + 1,
          color: theme.accentColor,
        ));
      }
    } else {
      for (final f in fields) {
        final fieldId = 'sf_${_slug(f.name)}';
        elements.add(_text(
          id: nextId('el'),
          name: '${f.name}标签',
          text: _decorateEmoji(f.name),
          x: _Layout.pcbPadding,
          y: y,
          w: colLabelW,
          h: _Layout.rowHeight,
          fontSize: 10,
          color: theme.labelColor,
          align: 'left',
          layer: elements.length + 1,
        ));

        if (f.isNumeric && pageIndex == 1) {
          elements.add(_progress(
            id: nextId('el'),
            name: f.name,
            x: _Layout.pcbPadding + colLabelW + 6,
            y: y + (_Layout.rowHeight - _Layout.barHeight) / 2,
            w: innerW - colLabelW - 6,
            h: _Layout.barHeight,
            statusFieldId: fieldId,
            layer: elements.length + 1,
            barFillColor: _barColorOf(f.name, theme.barFillColor),
            barTrackColor: theme.barTrackColor,
          ));
          final numPresets = _presetsOf(branchPresets, f.name, numeric: true);
          statusFields.add({
            'id': fieldId,
            'name': f.name,
            'type': 'number',
            'initial_value': numPresets['0'] ?? '0',
            'min_value': 0.0,
            'max_value': 100.0,
            'pin_side': 'none',
            'order': statusFields.length,
            'owner': 'player',
            if (numPresets.length > 1) 'branch_initial_values': numPresets,
          });
        } else {
          elements.add(_text(
            id: nextId('el'),
            name: f.name,
            text: '—',
            x: _Layout.pcbPadding + colLabelW + 6,
            y: y,
            w: innerW - colLabelW - 6,
            h: _Layout.rowHeight,
            fontSize: 11,
            color: theme.valueColor,
            align: 'left',
            layer: elements.length + 1,
            statusFieldId: fieldId,
          ));
          final txtPresets = _presetsOf(branchPresets, f.name, numeric: false);
          statusFields.add({
            'id': fieldId,
            'name': f.name,
            'type': 'text',
            'initial_value': txtPresets['0'] ?? '',
            'pin_side': 'none',
            'order': statusFields.length,
            'owner': 'player',
            if (txtPresets.length > 1) 'branch_initial_values': txtPresets,
          });
        }
        y += _Layout.rowHeight + _Layout.rowGap;
      }
    }

    final pcbH = (y + _Layout.pcbPadding).clamp(64.0, 2000.0).toDouble();

    // ── 3. 底板放最底层 ──
    final bg = _surface(
      id: nextId('el'),
      name: '底板',
      x: 0,
      y: 0,
      w: pcbW,
      h: pcbH,
      color: theme.panelColor,
      layer: 0,
      radius: theme.borderRadius,
    );

    return [bg, ...elements];
  }

  // ─────────────────────── AI Plan 编译辅助 ───────────────────────

  static List<String> _planPageTitles(UiDesignPlan plan) {
    final titles = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!titles.contains(v)) titles.add(v);
    }

    for (final p in plan.layout.pages) {
      add(p.title);
    }
    for (final f in plan.fields) {
      add(f.page);
    }
    for (final input in plan.inputs) {
      add(input.page);
    }
    for (final a in plan.actions) {
      add(a.page);
    }
    if (titles.isEmpty) {
      final hasNumber = plan.fields.any((f) => f.isNumber);
      final hasText = plan.fields.any((f) => !f.isNumber);
      if (hasNumber) titles.add('属性');
      if (hasText) titles.add('档案');
      if (plan.inputs.isNotEmpty || plan.actions.isNotEmpty) titles.add('选项');
      if (titles.isEmpty) titles.add('主界面');
    }
    return titles.take(5).toList();
  }

  static String _resolvePlanPage(
    String requested,
    List<String> titles,
    String preferred,
  ) {
    final r = requested.trim();
    if (r.isNotEmpty && titles.contains(r)) return r;
    if (titles.contains(preferred)) return preferred;
    return titles.isEmpty ? '主界面' : titles.first;
  }

  static List<UiPlanField> _dedupePlanFields(List<UiPlanField> fields) {
    final seen = <String>{};
    final out = <UiPlanField>[];
    for (final f in fields) {
      final key = f.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(f);
      if (out.length >= _Layout.maxFields * 2) break;
    }
    return out;
  }

  static List<Map<String, dynamic>> _planGesturesForPage({
    required String mode,
    required int index,
    required List<String> pageTitles,
    required Map<String, String> pageIds,
    required String navigation,
  }) {
    if (mode == 'opening') return const <Map<String, dynamic>>[];
    if (pageTitles.length <= 1) return const <Map<String, dynamic>>[];
    if (navigation == 'tabs') return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    if (index + 1 < pageTitles.length) {
      out.add({
        'direction': 'swipe_left',
        'action': 'switch_base_page',
        'targetPageId': pageIds[pageTitles[index + 1]] ?? '',
        'transition': 'base_slide',
        'durationMs': 220,
      });
    }
    if (index - 1 >= 0) {
      out.add({
        'direction': 'swipe_right',
        'action': 'switch_base_page',
        'targetPageId': pageIds[pageTitles[index - 1]] ?? '',
        'transition': 'base_slide',
        'durationMs': 220,
      });
    }
    return out;
  }

  static double _pageContentHeight(List<Map<String, dynamic>> elements) {
    var maxH = 64.0;
    for (final e in elements) {
      final offset = e['offset'];
      final size = e['size'];
      if (offset is! Map || size is! Map) continue;
      final x = (offset['x'] as num?)?.toDouble() ?? 0.0;
      // 后台逻辑件不参与 PCB 高度计算。
      if (x < 0) continue;
      final y = (offset['y'] as num?)?.toDouble() ?? 0.0;
      final h = (size['height'] as num?)?.toDouble() ?? 0.0;
      final bottom = y + h + _Layout.pcbPadding;
      if (bottom > maxH) maxH = bottom;
    }
    return maxH.clamp(64.0, 2000.0).toDouble();
  }

  static List<Map<String, dynamic>> _buildPlanPageElements({
    required String pageTitle,
    required List<String> pageTitles,
    required Map<String, String> pageIds,
    required List<UiPlanField> fields,
    required List<UiPlanInput> inputs,
    required List<UiPlanAction> actions,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String mode,
    required double pcbW,
    required double innerW,
  }) {
    final elements = <Map<String, dynamic>>[];
    var y = _Layout.pcbPadding;

    if (pageTitles.length > 1) {
      final tabW = (innerW - (pageTitles.length - 1) * 6.0) / pageTitles.length;
      const tabH = 22.0;
      final routerIds = <String, String>{};
      for (final title in pageTitles) {
        if (title == pageTitle) continue;
        final routerId = nextId('el');
        routerIds[title] = routerId;
        elements.add(_pageRouter(
          id: routerId,
          name: '路由器_$title',
          targetPageId: pageIds[title] ?? '',
        ));
      }
      for (var i = 0; i < pageTitles.length; i++) {
        final title = pageTitles[i];
        final active = title == pageTitle;
        final x = _Layout.pcbPadding + i * (tabW + 6.0);
        final surfaceId = nextId('el');
        elements.add(_surface(
          id: surfaceId,
          name: '标签底_$title',
          x: x,
          y: y,
          w: tabW,
          h: tabH,
          color: active ? theme.accentColor : theme.buttonBgColor,
          layer: elements.length + 1,
          radius: 6,
        ));
        elements.add(_text(
          id: nextId('el'),
          name: '标签文_$title',
          text: title,
          x: x + 2,
          y: y + 4,
          w: tabW - 4,
          h: 14,
          fontSize: 9,
          color: active ? theme.titleColor : theme.labelColor,
          align: 'center',
          layer: elements.length + 1,
        ));
        if (!active) {
          final buttonId = nextId('el');
          elements.add(_button(
            id: buttonId,
            name: '标签按_$title',
            x: x,
            y: y,
            w: tabW,
            h: tabH,
            layer: elements.length + 1,
            sendsMessage: false,
            keyAction: false,
            color: 0x00000000,
          ));
          elements.add(_pressLinker2(
            id: nextId('el'),
            name: '标签跳_$title',
            buttonId: buttonId,
            routerId: routerIds[title]!,
            scheme: 'button_to_page_route',
            y: i * 52.0,
            layer: elements.length + 1,
          ));
        }
      }
      y += tabH + 12.0;
    } else {
      elements.add(_text(
        id: nextId('el'),
        name: '标题',
        text: pageTitle,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: 22,
        fontSize: mode == 'extra_companion' ? 13 : 16,
        color: theme.titleColor,
        align: 'center',
        layer: elements.length + 1,
      ));
      y += 28.0;
    }

    const labelW = 56.0;
    var currentGroup = '';
    for (final f in fields) {
      final group = f.group.trim();
      if (group.isNotEmpty && group != currentGroup) {
        currentGroup = group;
        elements.add(_text(
          id: nextId('el'),
          name: '分组_$group',
          text: group,
          x: _Layout.pcbPadding,
          y: y,
          w: innerW,
          h: 16,
          fontSize: mode == 'extra_companion' ? 10 : 12,
          color: theme.titleColor,
          align: 'left',
          layer: elements.length + 1,
        ));
        y += 18.0;
      }
      final fieldId = 'sf_${_slug(f.sourceKey.trim().isEmpty ? f.name : f.sourceKey)}';
      final isProgress = f.isNumber && f.display == 'progress';
      final min = f.min ?? 0.0;
      final max = f.max ?? 100.0;
      final initialNumber = _numberOf(f.initialValue) ?? min;
      final initial = f.isNumber ? _trimNumber(initialNumber) : f.initialValue;

      statusFields.add({
        'id': fieldId,
        'name': f.name,
        'type': f.isNumber ? 'number' : 'text',
        'initial_value': initial,
        'min_value': f.isNumber ? min : null,
        'max_value': f.isNumber ? max : null,
        'pin_side': 'none',
        'order': statusFields.length,
        'owner': f.owner,
      });

      elements.add(_text(
        id: nextId('el'),
        name: '${f.name}标签',
        text: _decorateEmoji(f.name),
        x: _Layout.pcbPadding,
        y: y,
        w: labelW,
        h: _Layout.rowHeight,
        fontSize: mode == 'extra_companion' ? 10 : 12,
        color: theme.labelColor,
        align: 'left',
        layer: elements.length + 1,
      ));

      if (isProgress) {
        elements.add(_progress(
          id: nextId('el'),
          name: f.name,
          x: _Layout.pcbPadding + labelW + 6,
          y: y + (_Layout.rowHeight - _Layout.barHeight) / 2,
          w: innerW - labelW - 6,
          h: _Layout.barHeight,
          statusFieldId: fieldId,
          layer: elements.length + 1,
          barFillColor: _barColorOf(f.name, theme.barFillColor),
          barTrackColor: theme.barTrackColor,
          min: min,
          max: max,
          current: initialNumber.clamp(min, max).toDouble(),
        ));
      } else {
        elements.add(_text(
          id: nextId('el'),
          name: f.name,
          text: initial.isEmpty ? '—' : initial,
          x: _Layout.pcbPadding + labelW + 6,
          y: y,
          w: innerW - labelW - 6,
          h: _Layout.rowHeight,
          fontSize: mode == 'extra_companion' ? 11 : 12,
          color: theme.valueColor,
          align: 'left',
          layer: elements.length + 1,
          statusFieldId: fieldId,
        ));
      }
      y += _Layout.rowHeight + _Layout.rowGap;
    }

    final pressPairs = <({String surface, String button})>[];
    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      elements.add(_input(
        id: nextId('el'),
        name: '输入_${i + 1}',
        placeholder: input.placeholder,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        layer: elements.length + 1,
        sendsMessage: input.sendOnSubmit,
        color: theme.accentColor,
      ));
      y += _Layout.buttonHeight + 8;
    }

    final localActions = [...actions];
    final needsGeneratedKeyAction = mode == 'opening'
        ? localActions.isEmpty
        : (_modeRequiresGeneratedKeyAction(mode) &&
            !localActions.any((a) => a.sendText.trim().isEmpty));
    if (needsGeneratedKeyAction) {
      localActions.insert(
        0,
        UiPlanAction(
          label: _keyActionLabel(mode),
          sendText: '',
          branchIndex: null,
          page: pageTitle,
          sourceRef: 'generated:keyAction',
        ),
      );
    }
    for (var i = 0; i < localActions.length; i++) {
      final a = localActions[i];
      final label = a.label.trim().isNotEmpty ? a.label.trim() : a.sendText.trim();
      if (label.isEmpty) continue;
      final surfaceId = nextId('el');
      elements.add(_surface(
        id: surfaceId,
        name: '按钮底_${i + 1}',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '按钮文_${i + 1}',
        text: label,
        x: _Layout.pcbPadding + 10,
        y: y + 8,
        w: innerW - 20,
        h: 18,
        fontSize: mode == 'extra_companion' ? 10 : 12,
        color: theme.valueColor,
        align: 'center',
        layer: elements.length + 1,
      ));
      final buttonId = nextId('el');
      elements.add(_button(
        id: buttonId,
        name: label,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        layer: elements.length + 1,
        sendsMessage: a.sendText.trim().isNotEmpty,
        keyAction: _shouldMarkKeyAction(mode, a),
        message: a.sendText.trim(),
        targetBranchIndex: a.branchIndex,
        color: theme.accentColor,
      ));
      pressPairs.add((surface: surfaceId, button: buttonId));
      y += _Layout.buttonHeight + 8;
    }

    for (var i = 0; i < pressPairs.length; i++) {
      elements.add(_pressLinker(
        id: nextId('el'),
        name: '按钮_${i + 1}按压',
        buttonId: pressPairs[i].button,
        surfaceId: pressPairs[i].surface,
        y: i * 52.0,
        layer: elements.length + 1,
        color: theme.accentColor,
      ));
    }

    final bg = _surface(
      id: nextId('el'),
      name: '底板',
      x: 0,
      y: 0,
      w: pcbW,
      h: (y + _Layout.pcbPadding).clamp(64.0, 2000.0).toDouble(),
      color: theme.panelColor,
      layer: 0,
      radius: theme.borderRadius,
    );
    return [bg, ...elements];
  }

  static bool _modeRequiresGeneratedKeyAction(String mode) =>
      mode == 'opening' || mode == 'scene' || mode == 'extra_sticky';

  static bool _shouldMarkKeyAction(String mode, UiPlanAction action) {
    if (mode == 'opening') return true;
    if (mode == 'scene' || mode == 'extra_sticky') {
      // 有发送内容的按钮承担“发消息”职责；非发送按钮承担关键操作。
      return action.sendText.trim().isEmpty;
    }
    return false;
  }

  static String _keyActionLabel(String mode) => switch (mode) {
        'opening' => '开始',
        'scene' => '设置',
        'extra_sticky' => '收起',
        _ => '确认',
      };

  static double? _numberOf(String raw) {
    if (RegExp(r'[万亿千百]').hasMatch(raw)) return null;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static Map<String, dynamic> _pageRouter({
    required String id,
    required String name,
    required String targetPageId,
  }) =>
      _element(
        id: id,
        x: -224, // 放置在PCB左侧外部逻辑区
        y: 0,
        w: 132,
        h: 44,
        layer: 0,
        module: _module(
          id: id,
          name: name,
          type: 'page_router',
          color: 0x00000000,
          props: {
            'route': {
              'targetPageId': targetPageId,
              'action': 'switch_base_page',
              'transition': 'base_slide',
              'durationMs': 200,
            },
          },
        ),
      );

  static Map<String, dynamic> _pressLinker2({
    required String id,
    required String name,
    required String buttonId,
    required String routerId,
    required String scheme,
    required double y,
    required int layer,
  }) =>
      _element(
        id: id,
        x: -224,
        y: y,
        w: 132,
        h: 44,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'linker',
          color: 0x00000000,
          props: {
            'linker': {
              'scheme': scheme,
              'sourceModuleId': buttonId,
              'targetModuleId': routerId,
              'enabled': true,
              'priority': 5,
            },
          },
        ),
      );

  // ─────────────────────── 开场选项页 ───────────────────────

  static String _buildOpeningPage(
    List<String> actions,
    String Function(String) nextId,
    String cardName,
    UiVisualTheme theme,
    String welcomeText,
  ) {
    const pcbW = 320.0;
    const padding = 16.0;
    final innerW = pcbW - padding * 2;
    var y = padding;

    final elements = <Map<String, dynamic>>[];

    elements.add(_text(
      id: nextId('el'),
      name: '标题',
      text: cardName.isEmpty ? '选择开局' : cardName,
      x: padding,
      y: y,
      w: innerW,
      h: 28,
      fontSize: 16,
      color: theme.titleColor,
      align: 'center',
      layer: 1,
    ));
    y += 28 + 12;

    // ── 增加开场白对白/叙述文本整合 ──
    if (welcomeText.isNotEmpty) {
      final textPanelId = nextId('el');
      elements.add(_surface(
        id: textPanelId,
        name: '开场叙述底板',
        x: padding,
        y: y,
        w: innerW,
        h: 110.0,
        color: (theme.panelColor & 0x00FFFFFF) | 0x26000000, // 15% 透明度底色
        layer: elements.length + 1,
        radius: 8.0,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '开场叙述',
        text: welcomeText,
        x: padding + 10,
        y: y + 8,
        w: innerW - 20,
        h: 94.0,
        fontSize: 11,
        color: theme.valueColor,
        align: 'left',
        layer: elements.length + 1,
      ));
      y += 110.0 + 12.0;
    }

    // 记下每个选项的「底板 id ↔ 按钮 id」，稍后连按压联动器。
    final pressPairs = <({String surface, String button})>[];

    for (var i = 0; i < actions.length; i += 2) {
      final label1 = actions[i];
      final has2 = i + 1 < actions.length;
      final label2 = has2 ? actions[i + 1] : null;

      final colW = innerW / 2 - 4;

      // 选项 1
      final surfaceId1 = nextId('el');
      elements.add(_surface(
        id: surfaceId1,
        name: '选项底${i + 1}',
        x: padding,
        y: y,
        w: colW,
        h: _Layout.buttonHeight,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '选项文${i + 1}',
        text: label1,
        x: padding + 8,
        y: y + 8,
        w: colW - 16,
        h: 18,
        fontSize: 10,
        color: theme.valueColor,
        align: 'center',
        layer: elements.length + 1,
      ));
      final buttonId1 = nextId('el');
      elements.add(_button(
        id: buttonId1,
        name: '选项${i + 1}',
        x: padding,
        y: y,
        w: colW,
        h: _Layout.buttonHeight,
        layer: elements.length + 1,
        sendsMessage: true,
        keyAction: true,
        message: label1,
        targetBranchIndex: i,
        color: theme.accentColor,
      ));
      pressPairs.add((surface: surfaceId1, button: buttonId1));

      // 选项 2
      if (label2 != null) {
        final col2X = padding + innerW / 2 + 4;
        final surfaceId2 = nextId('el');
        elements.add(_surface(
          id: surfaceId2,
          name: '选项底${i + 2}',
          x: col2X,
          y: y,
          w: colW,
          h: _Layout.buttonHeight,
          color: theme.buttonBgColor,
          layer: elements.length + 1,
          radius: 8,
        ));
        elements.add(_text(
          id: nextId('el'),
          name: '选项文${i + 2}',
          text: label2,
          x: col2X + 8,
          y: y + 8,
          w: colW - 16,
          h: 18,
          fontSize: 10,
          color: theme.valueColor,
          align: 'center',
          layer: elements.length + 1,
        ));
        final buttonId2 = nextId('el');
        elements.add(_button(
          id: buttonId2,
          name: '选项${i + 2}',
          x: col2X,
          y: y,
          w: colW,
          h: _Layout.buttonHeight,
          layer: elements.length + 1,
          sendsMessage: true,
          keyAction: true,
          message: label2,
          targetBranchIndex: i + 1,
          color: theme.accentColor,
        ));
        pressPairs.add((surface: surfaceId2, button: buttonId2));
      }

      y += _Layout.buttonHeight + 8;
    }

    // 按压反馈：每个选项一条联动器。
    // 放在最后加，这样它们的 layerIndex 都在可见元件之上（不影响显示，
    // 逻辑件本来就不渲染），也便于阅读时和上面的循环对应。
    for (var i = 0; i < pressPairs.length; i++) {
      elements.add(_pressLinker(
        id: nextId('el'),
        name: '选项${i + 1}按压',
        buttonId: pressPairs[i].button,
        surfaceId: pressPairs[i].surface,
        y: i * 52.0,
        layer: elements.length + 1,
        color: theme.accentColor,
      ));
    }

    final pcbH = (y + padding).clamp(64.0, 2000.0).toDouble();
    final bg = _surface(
      id: nextId('el'),
      name: '底板',
      x: 0,
      y: 0,
      w: pcbW,
      h: pcbH,
      color: theme.pcbColor,
      layer: 0,
      radius: theme.borderRadius,
    );

    final page = {
      'id': 'page_${nextId("page")}',
      'name': '开场',
      'type': 'base',
      'parentPageId': null,
      'sortOrder': 0,
      'elements': [bg, ...elements],
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };

    return _assembly(
      id: nextId('asm'),
      name: '开场选择',
      mode: 'opening',
      pcbW: pcbW,
      pcbH: pcbH,
      pages: [page],
      pcbColor: theme.pcbColor,
      pcbRadius: theme.borderRadius,
    );
  }

  // ─────────────────────── 元件工厂 ───────────────────────
  //
  // 所有类型陷阱集中在这几个函数里：
  //   material / shape → 枚举下标 int
  //   color            → ARGB int
  //   offset / size    → { x, y } / { width, height }
  // 只要这里写对，上层就不会踩坑。

  static Map<String, dynamic> _module({
    required String id,
    required String name,
    required String type,
    required int color,
    int material = 1, // solid
    int shape = 1, // rounded
    double radius = 0,
    Map<String, dynamic>? props,
  }) =>
      {
        'id': 'm_$id',
        'name': name,
        'type': type,
        'material': material,
        'shape': shape,
        'color': color,
        'opacity': 1.0,
        'borderRadius': radius,
        'properties': props ?? <String, dynamic>{},
        'boundVariable': '',
        'statusFieldMirrorKey': '',
        'displayExpression': '',
        'linkedSources': <String>[],
      };

  static Map<String, dynamic> _element({
    required String id,
    required double x,
    required double y,
    required double w,
    required double h,
    required int layer,
    required Map<String, dynamic> module,
  }) =>
      {
        'id': id,
        'isComposite': false,
        'offset': {'x': x, 'y': y},
        'size': {'width': w, 'height': h},
        'layerIndex': layer,
        'parentSurfaceId': null,
        'rotation': 0.0,
        'layoutLocked': false,
        'sealed': false,
        'module': module,
      };

  static Map<String, dynamic> _surface({
    required String id,
    required String name,
    required double x,
    required double y,
    required double w,
    required double h,
    required int color,
    required int layer,
    double radius = 12,
  }) =>
      _element(
        id: id,
        x: x,
        y: y,
        w: w,
        h: h,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'surface',
          color: color,
          radius: radius,
        ),
      );



  static Map<String, dynamic> _text({
    required String id,
    required String name,
    required String text,
    required double x,
    required double y,
    required double w,
    required double h,
    required double fontSize,
    required int color,
    required String align,
    required int layer,
    String? statusFieldId,
  }) =>
      _element(
        id: id,
        x: x,
        y: y,
        w: w,
        h: h,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'text',
          color: color,
          shape: 0,
          props: {
            'text': text,
            'fontSize': fontSize,
            'textAlign': align,
            'overflow': 'ellipsis',
            'richText': false,
            if (statusFieldId != null)
              'dataChannel': _channel(
                label: name,
                elementId: id,
                port: 'text',
                statusFieldId: statusFieldId,
                fieldType: 'text',
              ),
          },
        ),
      );

  static Map<String, dynamic> _progress({
    required String id,
    required String name,
    required double x,
    required double y,
    required double w,
    required double h,
    required int layer,
    required String statusFieldId,
    required int barFillColor,
    required int barTrackColor,
    double min = 0.0,
    double max = 100.0,
    double current = 0.0,
  }) =>
      _element(
        id: id,
        x: x,
        y: y,
        w: w,
        h: h,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'progress',
          color: barFillColor,
          shape: 2, // capsule
          radius: h / 2,
          props: {
            'min': min,
            'max': max,
            'current': current,
            'progressShape': 'capsule',
            'trackColor': barTrackColor,
            'dataChannel': _channel(
              label: name,
              elementId: id,
              port: 'current',
              statusFieldId: statusFieldId,
              fieldType: 'number',
            ),
          },
        ),
      );

  static Map<String, dynamic> _input({
    required String id,
    required String name,
    required String placeholder,
    required double x,
    required double y,
    required double w,
    required double h,
    required int layer,
    required bool sendsMessage,
    required int color,
  }) =>
      _element(
        id: id,
        x: x,
        y: y,
        w: w,
        h: h,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'input',
          color: color,
          props: {
            'placeholder': placeholder,
            'text': '',
            'value': '',
            'committedValue': '',
            'visualMode': 'filled',
            'multiline': false,
            if (sendsMessage) 'sendsMessage': true,
          },
        ),
      );

  static Map<String, dynamic> _button({
    required String id,
    required String name,
    required double x,
    required double y,
    required double w,
    required double h,
    required int layer,
    required bool sendsMessage,
    required bool keyAction,
    required int color,
    String message = '',
    int? targetBranchIndex,
  }) {
    final props = <String, dynamic>{
      if (sendsMessage) 'sendsMessage': true,
      if (keyAction) 'keyAction': true,
      if (message.isNotEmpty) 'text': message,
    };
    if (targetBranchIndex != null) {
      props['targetBranchIndex'] = targetBranchIndex;
    }
    return _element(
      id: id,
      x: x,
      y: y,
      w: w,
      h: h,
      layer: layer,
      module: _module(
        id: id,
        name: name,
        type: 'button',
        color: color,
        props: props,
      ),
    );
  }

  /// 联动器：把按钮的点击连到底板的按压动画。
  ///
  /// ## 为什么必须有
  ///
  /// button 是**不显形的点击热区**，本身没有任何视觉。
  /// 不接联动器的话，玩家点下去毫无反馈——按了跟没按一样。
  /// 引擎给这种场景准备了现成方案 `click_to_surface_press`。
  ///
  /// ## 为什么放在 PCB 外
  ///
  /// linker 是纯逻辑件，不需要显示。放进 PCB 内会占位置、
  /// 还可能挡住其它元件；负 x 坐标即引擎的「后台位」，
  /// 校验器对这类逻辑件不做 PCB 包含性检查。
  static Map<String, dynamic> _pressLinker({
    required String id,
    required String name,
    required String buttonId,
    required String surfaceId,
    required double y,
    required int layer,
    required int color,
  }) =>
      _element(
        id: id,
        // 后台位：放在 PCB 左侧外部。
        x: -224,
        y: y,
        w: 132,
        h: 44,
        layer: layer,
        module: _module(
          id: id,
          name: name,
          type: 'linker',
          color: color,
          props: {
            'linker': {
              'scheme': 'click_to_surface_press',
              'sourceModuleId': buttonId,
              'targetModuleId': surfaceId,
              'enabled': true,
              'priority': 5,
            },
          },
        ),
      );

  /// 数据通道：让 LLM 能读写这个组件。
  ///
  /// 没有它，UI 就只是静态装饰——这是「能用」和「好看的摆设」的分界。
  static Map<String, dynamic> _channel({
    required String label,
    required String elementId,
    required String port,
    required String statusFieldId,
    required String fieldType,
  }) =>
      {
        'semanticLabel': label,
        'semanticPath': label,
        'semanticSource': 'manual',
        'labelElementId': '',
        'sourceComponentId': elementId,
        'sourcePort': port,
        'targetKind': 'status_field',
        'targetId': statusFieldId,
        'pendingName': '',
        'displayNameSnapshot': label,
        'visibility': 'ui_only',
        'llmReadPolicy': 'prompt',
        // 让模型能主动更新数值，否则界面永远是初始值。
        'llmWritePolicy':
            fieldType == 'number' ? 'suggest_delta' : 'suggest_replace',
        'notifyStyle': 'silent',
        'promptSection': 'ui_data',
        'fieldType': fieldType,
      };

  /// 组装成顶层 assembly。
  ///
  /// **三层嵌套在这里收口**：`elements` 与 `pages` 必须 be JSON 字符串。
  /// `createdAt` 必须是毫秒时间戳（写 ISO 字符串会直接抛异常）。
  static String _assembly({
    required String id,
    required String name,
    required String mode,
    required double pcbW,
    required double pcbH,
    required List<Map<String, dynamic>> pages,
    required int pcbColor,
    required double pcbRadius,
  }) {
    return jsonEncode({
      'id': id,
      'name': name,
      'mode': mode,
      'elements': '[]',
      'pages': jsonEncode(pages),
      'pcbWidth': pcbW,
      'pcbHeight': pcbH,
      'pcbColorValue': pcbColor,
      'pcbRadius': pcbRadius,
      'pcbRounded': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─────────────────────── 工具 ───────────────────────

  /// 取某字段在各分支的初值。
  ///
  /// 数值字段要清洗：原卡写的是 `84%`、`1000 pts`、`200万+ pts` 这类
  /// 带单位的字符串，而引擎按 number 处理时需要纯数字。
  /// 洗不出数字的（如「200万+」）**保留原文**——
  /// 宁可显示成文本，也不要凭空编一个数。
  static Map<String, String> _presetsOf(
    Map<int, Map<String, String>> branchPresets,
    String fieldName, {
    required bool numeric,
  }) {
    final out = <String, String>{};
    for (final entry in branchPresets.entries) {
      final raw = entry.value[fieldName];
      if (raw == null || raw.isEmpty) continue;
      final v = numeric ? _cleanNumber(raw) : raw;
      if (v != null && v.isNotEmpty) out[entry.key.toString()] = v;
    }
    return out;
  }

  /// 从 `84%` / `1000 pts` 里洗出 `84` / `1000`。
  ///
  /// **带中文数量词的一律不洗**：`200万+ pts` 取第一段数字会得到 `200`，
  /// 与原意差一万倍。这类值宁可保留原文当文本显示，
  /// 也不要凭空造一个错误的数——错误的数比缺失的数更难发现。
  static String? _cleanNumber(String raw) {
    if (RegExp(r'[万亿千百]').hasMatch(raw)) return null;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    return m?.group(0);
  }

  /// 该字段是否适合用 0~100 的进度条表达。
  ///
  /// 判据是**各分支预设是否都落在 0~100**。
  /// 「精神 84%」适合；「点数 1000 / 200万」不适合——
  /// 硬塞进 0~100 的条里会永远满格，反而失真。
  ///
  /// 不适合的字段退回文本显示，信息不丢。
  static bool _fitsPercentBar(Map<String, String> presets) {
    if (presets.isEmpty) return true; // 没数据就按默认量程走
    for (final v in presets.values) {
      final n = double.tryParse(v);
      if (n == null || n < 0 || n > 100) return false;
    }
    return true;
  }

  /// 「正文」这类字段是消息正文本身，不是状态，不该进状态面板。
  static bool _isNarrativeField(String name) => const {
        '正文',
        '内容',
        '叙述',
        'content',
        'text',
        'desc',
        'description',
        'note',
      }.contains(name.toLowerCase());

  /// 字段名 → 稳定的状态字段 id。
  ///
  /// 中文直接保留（引擎按字符串匹配，不限 ASCII），
  /// 只把可能破坏 JSON 或路径的字符换掉。
  static String _slug(String name) =>
      name.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '_');

  static String _decorateEmoji(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('生命') || lower.contains('血') || lower.contains('hp') || lower.contains('health')) return '❤️ $name';
    if (lower.contains('精神') || lower.contains('理智') || lower.contains('san') || lower.contains('mp') || lower.contains('mental')) return '🧠 $name';
    if (lower.contains('体力') || lower.contains('体能') || lower.contains('stamina') || lower.contains('energy') || lower.contains('ap')) return '⚡ $name';
    if (lower.contains('饱腹') || lower.contains('饥饿') || lower.contains('food') || lower.contains('hunger') || lower.contains('饱')) return '🍔 $name';
    if (lower.contains('称号') || lower.contains('职业') || lower.contains('身份') || lower.contains('title') || lower.contains('job')) return '👑 $name';
    if (lower.contains('编号') || lower.contains('id') || lower.contains('number')) return '🆔 $name';
    if (lower.contains('罪名') || lower.contains('罪行') || lower.contains('crime')) return '⚖️ $name';
    if (lower.contains('势力') || lower.contains('阵营') || lower.contains('faction') || lower.contains('alliance')) return '👥 $name';
    if (lower.contains('关系') || lower.contains('好感') || lower.contains('love') || lower.contains('relationship')) return '💖 $name';
    if (lower.contains('声望') || lower.contains('名气') || lower.contains('reputation')) return '🎖️ $name';
    if (lower.contains('点数') || lower.contains(' points') || lower.contains('pts') || lower.contains('money') || lower.contains('coin')) return '🪙 $name';
    if (lower.contains('物品') || lower.contains('行囊') || lower.contains('背包') || lower.contains('items') || lower.contains('bag')) return '🎒 $name';
    if (lower.contains('位置') || lower.contains('地点') || lower.contains('location') || lower.contains('place')) return '📍 $name';
    if (lower.contains('日期') || lower.contains('时间') || lower.contains('date') || lower.contains('time')) return '📅 $name';
    return name;
  }

  static int _barColorOf(String name, int fallback) {
    final lower = name.toLowerCase();
    if (lower.contains('生命') || lower.contains('血') || lower.contains('hp') || lower.contains('health')) return 0xFFE53935; // 红色
    if (lower.contains('精神') || lower.contains('理智') || lower.contains('san') || lower.contains('mental')) return 0xFF8E24AA; // 紫色
    if (lower.contains('体力') || lower.contains('精力') || lower.contains('stamina') || lower.contains('energy') || lower.contains('ap')) return 0xFF4CAF50; // 绿色
    if (lower.contains('饱腹') || lower.contains('饥饿') || lower.contains('food') || lower.contains('hunger')) return 0xFFFF9800; // 橙色
    return fallback;
  }
}

class _PanelResult {
  const _PanelResult({
    required this.assemblyJson,
    required this.statusFields,
    required this.notes,
  });

  final String assemblyJson;
  final List<Map<String, dynamic>> statusFields;
  final List<String> notes;
}
