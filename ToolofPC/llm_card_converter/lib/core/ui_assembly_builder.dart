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

import 'ai_ui_designer.dart';
import 'regex_ui_extractor.dart';

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

/// 后台逻辑区坐标分配器。
///
/// 逻辑组件（linker / page_router / math_node / timer）运行时不可见，
/// 统一摆放在 PCB 左侧的后台区。为避免它们**重叠**、并让玩家研究布局时
/// 能看出层级，这里按「层级」排布：
///
/// ```text
///         后台区                     PCB
///   ┌───────────┬───────────┐ ┌──────────────┐
///   │ level 2   │ level 1   │ │  可见组件     │
///   │ (更深入)  │ page_router│ │  (button等)  │
///   │           │  ┌─────┐  │ │              │
///   │           │  │ 路由器 │  │              │
///   └───────────┴─┬─────┬──┘ └──────────────┘
///                 │ linker(level 0, 最右)  │
///                 └──────┴─────────────────
/// ```
///
/// 最右列（level 0）是第一层 linker（直接连接可见组件的接线），
/// 向左（level 递增）是更深层的逻辑节点。同一列内纵向依次排开。
class _LogicSlots {
  static const double _colGap = 160.0;
  static const double _rowGap = 52.0;

  /// 各层级的当前行号（默认最右列从 PCB 左侧开始）。
  final Map<int, double> _rows = {};

  /// 分配该层级下一个逻辑组件的位置（x, y）。
  ///
  /// [level] 0 = 最右列（第一层 linker），越大越靠左（越深层）。
  (double, double) slot(int level) {
    final row = _rows[level] ?? 0.0;
    _rows[level] = row + _rowGap;
    return (-224.0 - level * _colGap, row);
  }
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
      borderRadius: parseDouble(json['borderRadius'], d.borderRadius).clamp(0.0, 32.0),
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
        ex.branchActions,
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
    Map<int, List<ActionOption>> branchActions,
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

    // extra_companion 只有属性 + 档案两页；选开场白由 opening UI 承担，
    // 不在常驻面板里重复放「选项」页。

    // 创建平级页面的 ID
    final page1Id = 'page_${nextId("page")}';
    final page2Id = 'page_${nextId("page")}';

    final statusFields = <Map<String, dynamic>>[];

    // 后台逻辑区坐标分配器：整个状态栏 assembly 的逻辑组件统一排布。
    final logicSlots = _LogicSlots();

    // ── 动作叠加层页：每个动作一个 overlay 页（详情 + 确认按钮） ──
    final actionOverlayIds = <int, String>{};
    final actionOverlayPages = <Map<String, dynamic>>[];
    if (branchActions.isNotEmpty) {
      final slotCount = branchActions.values
          .map((l) => l.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      for (var sIdx = 0; sIdx < slotCount; sIdx++) {
        final branchValues = <String, String>{};
        for (final entry in branchActions.entries) {
          if (sIdx < entry.value.length) {
            branchValues[entry.key.toString()] = entry.value[sIdx].raw;
          }
        }
        final detail = branchValues['0'] ??
            (branchValues.values.isNotEmpty
                ? branchValues.values.first
                : '');
        if (detail.isEmpty) continue;
        final overlayId = 'page_${nextId("page")}';
        actionOverlayIds[sIdx] = overlayId;
        actionOverlayPages.add(_buildActionOverlayPage(
          id: overlayId,
          parentPageId: page1Id,
          actionTitle: _actionTitleOf(detail),
          detail: detail,
          nextId: nextId,
          theme: theme,
          pcbW: pcbW,
        ));
      }
    }

    // 编译第一页 (📊 属性)
    final elements1 = _buildPageElements(
      pageIndex: 1,
      fields: tab1Fields,
      nextId: nextId,
      branchPresets: branchPresets,
      statusFields: statusFields,
      theme: theme,
      page1Id: page1Id,
      page2Id: page2Id,
      pcbW: pcbW,
      innerW: innerW,
      branchActions: branchActions,
      actionOverlayIds: actionOverlayIds,
      logicSlots: logicSlots,
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
      nextId: nextId,
      branchPresets: branchPresets,
      statusFields: statusFields,
      theme: theme,
      page1Id: page1Id,
      page2Id: page2Id,
      pcbW: pcbW,
      innerW: innerW,
      logicSlots: logicSlots,
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

    notes.add('通过多页面 (📊属性/📁档案) 与顶置 Tab 标签切换按钮'
        '整合面板属性与预设选项，使信息流与操作深度聚合。');

    final pList = <Map<String, dynamic>>[page1, page2, ...actionOverlayPages];

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
    required String Function(String) nextId,
    required Map<int, Map<String, String>> branchPresets,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String page1Id,
    required String page2Id,
    required double pcbW,
    required double innerW,
    Map<int, List<ActionOption>> branchActions = const {},
    Map<int, String> actionOverlayIds = const {},
    _LogicSlots? logicSlots,
  }) {
    final elements = <Map<String, dynamic>>[];
    var y = _Layout.pcbPadding;
    final ls = logicSlots ?? _LogicSlots();

    // ── 1. 顶部 Tab 标签切换栏 ──
    final tabW = (innerW - 6.0) / 2;
    final tabH = 22.0;

    final tabs = [
      (index: 1, title: '📊 属性', pageId: page1Id),
      (index: 2, title: '📁 档案', pageId: page2Id),
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
          // page_router 是被 linker 指向的更深层逻辑（level 1，左一列）。
          pos: ls.slot(1),
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

        final pos = ls.slot(0);
        elements.add(_pressLinker2(
          id: nextId('el'),
          name: '标签跳_${tab.title}',
          buttonId: bId,
          routerId: routerIds[tab.index]!,
          scheme: 'button_to_page_route',
          x: pos.$1,
          y: pos.$2,
          layer: elements.length + 1,
        ));
      }
    }

    y += tabH + 12.0;
    const colLabelW = 50.0;

    // ── 2. 渲染专页的属性列表数据（单列最松弛排布，完全不拥挤） ──
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

    // ── 分支动作区：只放在「属性」主页，贴近原版 AVAILABLE ACTIONS ──
    // 每个动作做成「覆盖整个选项的可点击按钮」，点击打开该动作的叠加层，
    // 叠加层里展示完整描述并放「确认选择此方案」按钮，点确认才发送给 AI。
    if (pageIndex == 1 && branchActions.isNotEmpty) {
      final slotCount = branchActions.values
          .map((l) => l.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      if (slotCount > 0) {
        y += 6.0;
        elements.add(_text(
          id: nextId('el'),
          name: '动作区标题',
          text: '🎯 接下来做什么',
          x: _Layout.pcbPadding,
          y: y,
          w: innerW,
          h: 16,
          fontSize: 10,
          color: theme.labelColor,
          align: 'left',
          layer: elements.length + 1,
        ));
        y += 16 + 4;

        for (var sIdx = 0; sIdx < slotCount; sIdx++) {
          final actionFieldId = 'sf_act_${sIdx + 1}';
          final branchValues = <String, String>{};
          for (final entry in branchActions.entries) {
            final list = entry.value;
            if (sIdx < list.length) {
              branchValues[entry.key.toString()] = list[sIdx].raw;
            }
          }
          final firstRaw = branchValues['0'] ??
              (branchValues.values.isNotEmpty
                  ? branchValues.values.first
                  : '');
          final title = _actionTitleOf(firstRaw);

          // 选项底（视觉背景）
          final surfaceId = nextId('el');
          elements.add(_surface(
            id: surfaceId,
            name: '动作底_${sIdx + 1}',
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
            name: '动作文_${sIdx + 1}',
            text: title,
            x: _Layout.pcbPadding + 10,
            y: y + 8,
            w: innerW - 20,
            h: 18,
            fontSize: 10,
            color: theme.valueColor,
            align: 'left',
            layer: elements.length + 1,
            statusFieldId: actionFieldId,
          ));

          // 覆盖整个选项的点击热区：点击打开该动作的叠加层
          final overlayId = actionOverlayIds[sIdx];
          final btnId = nextId('el');
          elements.add(_button(
            id: btnId,
            name: '动作_${sIdx + 1}',
            x: _Layout.pcbPadding,
            y: y,
            w: innerW,
            h: _Layout.buttonHeight,
            layer: elements.length + 1,
            sendsMessage: false,
            keyAction: false,
            color: 0x00000000,
          ));
          if (overlayId != null && overlayId.isNotEmpty) {
            final routerId = nextId('el');
            elements.add(_pageRouter(
              id: routerId,
              name: '动作路由_${sIdx + 1}',
              targetPageId: overlayId,
              action: 'open_overlay',
              // page_router 是更深层逻辑（level 1，左一列）。
              pos: ls.slot(1),
            ));
            final pos = ls.slot(0);
            elements.add(_pressLinker2(
              id: nextId('el'),
              name: '动作跳_${sIdx + 1}',
              buttonId: btnId,
              routerId: routerId,
              scheme: 'button_to_page_route',
              x: pos.$1,
              y: pos.$2,
              layer: elements.length + 1,
            ));
          }

          // 动作 status field：text 类型，branch_initial_values 存各分支动作
          statusFields.add({
            'id': actionFieldId,
            'name': '动作${sIdx + 1}',
            'type': 'text',
            'initial_value': firstRaw,
            'pin_side': 'none',
            'order': statusFields.length,
            'owner': 'player',
            if (branchValues.length > 1) 'branch_initial_values': branchValues,
          });

          y += _Layout.buttonHeight + 6.0;
        }
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

  /// 生成单个动作的叠加层（overlay）页。
  ///
  /// 原版「AVAILABLE ACTIONS」的动作选项做成可点击 → 打开叠加层展示
  /// 该动作的完整描述，叠加层里放一个「确认选择此方案」按钮，点确认才
  /// 把该动作发给 AI。这样既能看到更多信息，又避免误触直接发送。
  static Map<String, dynamic> _buildActionOverlayPage({
    required String id,
    required String parentPageId,
    required String actionTitle,
    required String detail,
    required String Function(String) nextId,
    required UiVisualTheme theme,
    double? pcbW,
  }) {
    // 叠加层「独立悬浮窗」画布：脱离伴生 PCB 限制，用更大的居中画布。
    // 引擎按页的 pcbWidth/pcbHeight 用独立画布渲染并等比缩放，避免溢出。
    const overlayW = 320.0;
    const overlayH = 520.0;
    const padding = 16.0;
    const innerW = overlayW - padding * 2;
    final elements = <Map<String, dynamic>>[];
    var y = padding;

    // 后台逻辑区坐标分配器（叠加层内的按压联动器排布）。
    final logicSlots = _LogicSlots();

    // 全屏遮罩（is_overlay_container → 点遮罩空白处关闭叠加层）
    elements.add(_surface(
      id: nextId('el'),
      name: '叠加遮罩',
      x: 0,
      y: 0,
      w: overlayW,
      h: overlayH,
      color: 0x99000000,
      layer: 0,
      radius: 0,
      overlayContainer: true,
    ));

    // 中央卡片
    final cardX = padding;
    elements.add(_surface(
      id: nextId('el'),
      name: '叠加卡片',
      x: cardX,
      y: padding,
      w: innerW,
      h: overlayH - padding * 2,
      color: theme.panelColor,
      layer: 1,
      radius: 12,
    ));

    y = padding + 18;

    elements.add(_text(
      id: nextId('el'),
      name: '叠加标题',
      text: '🎯 $actionTitle',
      x: cardX + 14,
      y: y,
      w: innerW - 28,
      h: 24,
      fontSize: 15,
      color: theme.titleColor,
      align: 'left',
      layer: 2,
    ));
    y += 24 + 12;

    elements.add(_text(
      id: nextId('el'),
      name: '叠加详情',
      text: detail,
      x: cardX + 14,
      y: y,
      w: innerW - 28,
      h: 300,
      fontSize: 13,
      color: theme.valueColor,
      align: 'left',
      layer: 2,
      // 长文滚动显示，避免放不下时省略号截断。
      overflow: 'scroll',
    ));
    y += 300 + 20;

    // 确认按钮：把该动作发给 AI
    final confirmSurfaceId = nextId('el');
    elements.add(_surface(
      id: confirmSurfaceId,
      name: '确认底',
      x: cardX + 14,
      y: y,
      w: innerW - 28,
      h: 44,
      color: theme.accentColor,
      layer: 2,
      radius: 8,
    ));
    elements.add(_text(
      id: nextId('el'),
      name: '确认字',
      text: '确认选择此方案',
      x: cardX + 14,
      y: y + 13,
      w: innerW - 28,
      h: 18,
      fontSize: 13,
      color: theme.titleColor,
      align: 'center',
      layer: 3,
    ));
    final confirmId = nextId('el');
    elements.add(_button(
      id: confirmId,
      name: '确认按钮',
      x: cardX + 14,
      y: y,
      w: innerW - 28,
      h: 44,
      layer: 3,
      sendsMessage: true,
      keyAction: false,
      message: detail,
      color: theme.accentColor,
    ));
    final pressPos = logicSlots.slot(0);
    elements.add(_pressLinker(
      id: nextId('el'),
      name: '确认按压',
      buttonId: confirmId,
      surfaceId: confirmSurfaceId,
      x: pressPos.$1,
      y: pressPos.$2,
      layer: 4,
      color: theme.accentColor,
    ));

    return {
      'id': id,
      'name': '确认·$actionTitle',
      'type': 'overlay',
      'parentPageId': parentPageId,
      'sortOrder': 100,
      'pcbWidth': overlayW,
      'pcbHeight': overlayH,
      'elements': elements,
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };
  }

  static Map<String, dynamic> _pageRouter({
    required String id,
    required String name,
    required String targetPageId,
    String action = 'switch_base_page',
    (double, double)? pos,
  }) =>
      _element(
        id: id,
        // 默认放在 PCB 左侧外部逻辑区；可经 _LogicSlots 分配坐标。
        x: pos?.$1 ?? -224,
        y: pos?.$2 ?? 0,
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
              'action': action,
              'transition':
                  action == 'open_overlay' ? 'overlay_fade' : 'base_slide',
              'durationMs': action == 'open_overlay' ? 180 : 200,
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
    double x = -224,
  }) =>
      _element(
        id: id,
        x: x,
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

    // 后台逻辑区坐标分配器（开场页的按压联动器排布）。
    final logicSlots = _LogicSlots();

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
    // 高度按文本长度自适应：每行约 16px（11px 字号 + 行距），
    // 避免长开场白被固定高度截断。上限 320，超出用滚动显示。
    if (welcomeText.isNotEmpty) {
      final textPanelId = nextId('el');
      final lineH = 16.0;
      final estLines = (welcomeText.length / 22).ceil().clamp(1, 20);
      final textH = (estLines * lineH).clamp(40.0, 320.0).toDouble();
      final panelH = textH + 16.0;
      elements.add(_surface(
        id: textPanelId,
        name: '开场叙述底板',
        x: padding,
        y: y,
        w: innerW,
        h: panelH,
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
        h: textH,
        fontSize: 11,
        color: theme.valueColor,
        align: 'left',
        layer: elements.length + 1,
        // 长开场白滚动显示，避免省略号截断正文。
        overflow: 'scroll',
      ));
      y += panelH + 12.0;
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
        // 选开场白：只切换分支 + 关闭弹窗，不发送任何文本给 AI。
        sendsMessage: false,
        keyAction: true,
        // 分支索引 = 选项下标 + 1：index 0 是 first_mes 引导页本身，
        // 选项要切到其后的 alternate_greetings（1..N）。
        targetBranchIndex: i + 1,
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
          // 选开场白：只切换分支 + 关闭弹窗，不发送任何文本给 AI。
          sendsMessage: false,
          keyAction: true,
          // 与选项1同理：分支索引 = 选项下标 + 1（跳过 first_mes 引导页本身）。
          targetBranchIndex: i + 2,
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
      final pressPos = logicSlots.slot(0);
      elements.add(_pressLinker(
        id: nextId('el'),
        name: '选项${i + 1}按压',
        buttonId: pressPairs[i].button,
        surfaceId: pressPairs[i].surface,
        x: pressPos.$1,
        y: pressPos.$2,
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

  /// 生成「选择开场白」opening 页。
  ///
  /// 一张卡有 2 条以上开场白时，玩家的开局不该由程序硬定，
  /// 而应由玩家在 opening 弹窗里选。每个开场白一个按钮：
  /// 点击 → 切到对应分支（`targetBranchIndex`）并关闭弹窗，
  /// **不发送任何文本给 AI**（选开场白不是一次对话）。
  static BuiltAssembly? buildOpeningFromGreetings(
    List<Map<String, dynamic>> greetings, {
    String cardName = '',
    UiVisualTheme? theme,
  }) {
    if (greetings.length < 2) return null; // 只有一条开场白，无需选择
    final visualTheme = theme ?? UiVisualTheme.defaultTheme();

    const pcbW = 320.0;
    const padding = 16.0;
    final innerW = pcbW - padding * 2;
    final elements = <Map<String, dynamic>>[];
    final logicSlots = _LogicSlots();
    final pressPairs = <({String surface, String button})>[];
    var seed = DateTime.now().millisecondsSinceEpoch;
    String nextId(String prefix) => '${prefix}_${seed++}';
    var y = padding;

    // 标题
    elements.add(_text(
      id: nextId('op'),
      name: '标题',
      text: cardName.isEmpty ? '选择你的开局' : cardName,
      x: padding,
      y: y,
      w: innerW,
      h: 28,
      fontSize: 16,
      color: visualTheme.titleColor,
      align: 'center',
      layer: 1,
    ));
    y += 28 + 14;

    elements.add(_text(
      id: nextId('op'),
      name: '副标题',
      text: '请选择你的开局',
      x: padding,
      y: y,
      w: innerW,
      h: 18,
      fontSize: 12,
      color: visualTheme.labelColor,
      align: 'center',
      layer: 1,
    ));
    y += 18 + 16;

    // 每个开场白一个按钮
    for (var i = 0; i < greetings.length; i++) {
      final title = _greetingTitle(greetings[i]);
      final surfaceId = nextId('op');
      elements.add(_surface(
        id: surfaceId,
        name: '开局底${i + 1}',
        x: padding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight + 6,
        color: visualTheme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('op'),
        name: '开局文${i + 1}',
        text: title,
        x: padding + 12,
        y: y + 10,
        w: innerW - 24,
        h: 20,
        fontSize: 12,
        color: visualTheme.valueColor,
        align: 'left',
        layer: elements.length + 1,
      ));
      final buttonId = nextId('op');
      elements.add(_button(
        id: buttonId,
        name: '开局${i + 1}',
        x: padding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight + 6,
        layer: elements.length + 1,
        // 选开场白：只切换分支 + 关闭弹窗，不发送任何文本给 AI。
        sendsMessage: false,
        keyAction: true,
        // 分支索引 = 开场白下标（0 是 first_mes，其后为 alternate_greetings）。
        targetBranchIndex: i,
        color: visualTheme.accentColor,
      ));
      pressPairs.add((surface: surfaceId, button: buttonId));
      y += _Layout.buttonHeight + 6 + 10;
    }

    // 按压反馈联动器（放在后台逻辑区）
    for (var i = 0; i < pressPairs.length; i++) {
      final pressPos = logicSlots.slot(0);
      elements.add(_pressLinker(
        id: nextId('op'),
        name: '开局${i + 1}按压',
        buttonId: pressPairs[i].button,
        surfaceId: pressPairs[i].surface,
        x: pressPos.$1,
        y: pressPos.$2,
        layer: elements.length + 1,
        color: visualTheme.accentColor,
      ));
    }

    final pcbH = (y + padding).clamp(64.0, 2000.0).toDouble();
    final bg = _surface(
      id: nextId('op'),
      name: '底板',
      x: 0,
      y: 0,
      w: pcbW,
      h: pcbH,
      color: visualTheme.pcbColor,
      layer: 0,
      radius: visualTheme.borderRadius,
    );

    final page = {
      'id': 'page_${nextId('op')}',
      'name': '选择开局',
      'type': 'base',
      'parentPageId': null,
      'sortOrder': 0,
      'elements': [bg, ...elements],
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };

    final json = _assembly(
      id: nextId('op'),
      name: '选择开局',
      mode: 'opening',
      pcbW: pcbW,
      pcbH: pcbH,
      pages: [page],
      pcbColor: visualTheme.pcbColor,
      pcbRadius: visualTheme.borderRadius,
    );
    return BuiltAssembly(
      assemblies: [json],
      statusFields: const [],
      notes: ['识别到 ${greetings.length} 条开场白，已生成「选择开局」opening 页。'],
    );
  }

  /// 从开场白内容里抽一个短标题当按钮文案。
  static String _greetingTitle(Map<String, dynamic> greeting) {
    final content = greeting['content']?.toString() ?? '';
    final cleaned = content
        .replaceAll(RegExp(r'<[^>]*>'), ' ') // 去标签
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final t = cleaned.isEmpty ? '' : cleaned;
    if (t.isEmpty) return '开局';
    return t.length > 16 ? '${t.substring(0, 16)}…' : t;
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
    bool overlayContainer = false,
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
          props: overlayContainer
              ? {'is_overlay_container': true}
              : null,
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
    String overflow = 'ellipsis',
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
            'overflow': overflow,
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
    double current = 0.0,
    double min = 0.0,
    double max = 100.0,
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
    double x = -224,
  }) =>
      _element(
        id: id,
        // 后台位：放在 PCB 左侧外部。
        x: x,
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
  /// 从完整动作文本提取展示标题。
  ///
  /// 完整动作形如 `1.🤐【保持沉默】默不作声地按照指示上前...`，
  /// 标题取 `【保持沉默】`（带书名号便于识别为选项）；没有【】时
  /// 截取前若干字符。
  static String _actionTitleOf(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final titleM = RegExp(r'【([^】]+)】').firstMatch(t);
    if (titleM != null) return '【${titleM.group(1)}】';
    return t.length > 14 ? t.substring(0, 14) : t;
  }

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

  /// 把 AI 常用的英文缩写字段名翻译成玩家看得懂的中文标签。
  ///
  /// AI（Step A）给 scene 的字段名往往是英文缩写（HP/STR/AGI…），
  /// 直接当标签显示，玩家根本不知道是啥。这里统一映射成中文，
  /// 并保留原缩写便于对照。没匹配到的按原名显示（不丢信息）。
  static String _sceneLabelOf(String name) {
    final n = name.trim();
    if (n.isEmpty) return n;
    final key = n.toLowerCase().replaceAll(' ', '');
    const map = <String, String>{
      'hp': '❤️ 生命', 'mp': '🧠 魔力', 'xp': '⭐ 经验', 'sp': '⚡ 体力',
      'level': '🏅 等级', 'lvl': '🏅 等级', 'exp': '⭐ 经验',
      'str': '💪 力量', 'agi': '🏃 敏捷', 'dex': '🏃 敏捷',
      'int': '🧠 智力', 'con': '🛡️ 体质', 'vit': '🛡️ 体质',
      'per': '👁️ 感知', 'cha': '💬 魅力', 'luck': '🍀 幸运',
      'gold': '🪙 金币', 'money': '🪙 金币', 'coins': '🪙 金币',
      'name': '👤 名字', 'class': '👑 职业', 'job': '💼 职业',
      'weapon': '⚔️ 武器', 'armor': '🛡️ 防具', 'shield': '🛡️ 盾牌',
      'status': '📌 状态', 'title': '👑 称号', 'age': '🎂 年龄',
      'race': '🧬 种族', 'gender': '🚻 性别', 'height': '📏 身高',
      'weight': '⚖️ 体重', 'alive': '💗 存活', 'hunger': '🍔 饱腹',
      'thirst': '💧 口渴', 'energy': '⚡ 精力', 'stamina': '⚡ 体力',
      'fame': '🎖️ 声望', 'reputation': '🎖️ 声望', 'relationship': '💖 好感',
      'affection': '💖 好感', 'inventory': '🎒 背包', 'items': '🎒 背包',
    };
    final zh = map[key];
    if (zh == null) return n;
    // 中文标签 + 保留原缩写，方便玩家对照原卡。
    return '$zh(${n.toUpperCase()})';
  }

  /// 决定 scene 文本字段的高度与滚动方式。
  ///
  /// 返回 (height, overflowMode)。
  ///
  /// 「内容型」字段（描述/备注/任务/正文…）可能很长、且常是构建时为空、
  /// 运行时才由 LLM 填入——给滚动；高度按真实文本行数紧凑计算，
  /// 空值给 2 行默认高度（运行时填长文也能滚，不会溢出）。
  /// 短值字段（名字/职业/状态/装备…）按单行；引擎已对非滚动文本做硬裁剪。
  static (double, String) _sceneTextSizing(String name, String text) {
    final lower = name.toLowerCase();
    const contentKeys = {
      'desc', 'description', 'note', 'notes', 'risk', 'quest', 'content',
      'summary', 'intro', 'story', 'detail', 'details', 'reward', 'location',
      '背景', '描述', '详情', '备注', '正文', '内容', '介绍', '说明', '任务',
      '装备', '奖励', '风险', '地点', '道具', '物品', 'buff', 'skill', '技能',
    };
    final isContent =
        contentKeys.contains(lower) || contentKeys.contains(name) || text.length > 16;
    if (!isContent) return (22.0, 'ellipsis');

    // 内容型字段：滚动 + 高度贴合真实行数，避免整页失控地高。
    if (text.isEmpty || text == '—') {
      // 运行时才填的空白内容：给 2 行默认高度 + 滚动，保证运行时填长文不外溢。
      return (40.0, 'scroll');
    }
    // 12px 中文约 20 字/行（内宽 332 - 滚动内边距）。
    final estLines = (text.length / 20).ceil().clamp(1, 8);
    final h = (estLines * 20.0 + 6.0).clamp(26.0, 180.0).toDouble();
    return (h, 'scroll');
  }

  static int _barColorOf(String name, int fallback) {
    final lower = name.toLowerCase();
    if (lower.contains('生命') || lower.contains('血') || lower.contains('hp') || lower.contains('health')) return 0xFFE53935; // 红色
    if (lower.contains('精神') || lower.contains('理智') || lower.contains('san') || lower.contains('mental')) return 0xFF8E24AA; // 紫色
    if (lower.contains('体力') || lower.contains('精力') || lower.contains('stamina') || lower.contains('energy') || lower.contains('ap')) return 0xFF4CAF50; // 绿色
    if (lower.contains('饱腹') || lower.contains('饥饿') || lower.contains('food') || lower.contains('hunger')) return 0xFFFF9800; // 橙色
    return fallback;
  }

  /// Step B：把 AI 的「创作意图」转成合法的 scene assembly JSON。
  ///
  /// AI（Step A）只产出语义化意图（有哪些页/面板/字段/用什么组件），
  /// 这里由确定性代码算坐标、绑数据通道、生成三层嵌套 JSON，
  /// 杜绝 AI 直接写 JSON 的静默错误。
  static BuiltAssembly buildSceneFromIntent(
    UiCreationIntent intent, {
    String cardName = '',
    UiVisualTheme? theme,
    Map<String, String> initialValues = const {},
  }) {
    final visualTheme = theme ?? UiVisualTheme.defaultTheme();
    // 字段初始值：AI 给的优先，空则回落到从原卡解析的覆盖表。
    // 兜底时做大小写不敏感 + 去空格匹配，避免 AI 改了字段名（如"生命"→"HP"）就匹配不上。
    String initOf(String name, String aiValue) {
      if (aiValue.isNotEmpty) return aiValue;
      // 精确匹配
      final exact = initialValues[name];
      if (exact != null && exact.isNotEmpty) return exact;
      // 大小写不敏感 + 去空格匹配
      final norm = name.toLowerCase().replaceAll(' ', '');
      for (final entry in initialValues.entries) {
        if (entry.key.toLowerCase().replaceAll(' ', '') == norm) {
          return entry.value;
        }
      }
      return '';
    }
    final assemblies = <String>[];
    final statusFields = <Map<String, dynamic>>[];
    var seed = DateTime.now().millisecondsSinceEpoch;
    String nextId(String prefix) => '${prefix}_${seed++}';
    final notes = <String>[
      ...intent.reasoning.map(
        (r) => '【AI 思考】$r',
      ),
    ];

    final pcbW = 360.0;
    const pad = 14.0;
    final innerW = pcbW - pad * 2;

    // 每个页面：id -> elements
    final pageElements = <String, List<Map<String, dynamic>>>{};
    for (final p in intent.pages) {
      pageElements[p.id] = <Map<String, dynamic>>[];
    }

    // 每页的纵向游标：AI 没给布局时按此**接续排布**，而不是各自从 y=250
    // 开始——否则两个面板挤到同一页就会完全重叠。AI 若给了 x/y/w/h
    // 则优先用 AI 的布局（Step B 只做 clamp/兜底）。
    final pageCursor = <String, double>{
      for (final p in intent.pages) p.id: 250.0, // 消息流下方
    };

    // 每个面板在对应页面摆放元素
    for (final panel in intent.panels) {
      final page = panel.page.isNotEmpty ? panel.page : intent.activePage;
      final elements = pageElements.putIfAbsent(
        page,
        () => <Map<String, dynamic>>[],
      );
      // 该面板是否含 AI 显式布局（任一字段给了 x/y/w/h）
      final hasExplicitLayout = panel.fields.any(
        (f) => f.x != null || f.y != null || f.width != null || f.height != null,
      );

      var y = pageCursor[page] ?? 250.0;
      if (panel.title.isNotEmpty && !hasExplicitLayout) {
        elements.add(_text(
          id: nextId('el'),
          name: '面板标题',
          text: panel.title,
          x: pad,
          y: y,
          w: innerW,
          h: 24,
          fontSize: 15,
          color: 0xFFFFFFFF,
          align: 'left',
          layer: 1,
        ));
        y += 30;
      }

      for (final field in panel.fields) {
        final fid = 'sf_${_slug(field.name)}';
        // 标签显示中文（AI 常用英文缩写，玩家看不懂）。
        final label = _sceneLabelOf(field.name);

        // AI 给了布局就用 AI 的位置/尺寸，否则用兜底纵向游标。
        double fx, fy, fw, fh;
        if (field.x != null || field.y != null ||
            field.width != null || field.height != null) {
          fx = field.x ?? pad;
          fy = field.y ?? y;
          fw = field.width ?? innerW;
          fh = field.height ?? 22;
        } else {
          fx = pad;
          fy = y;
          fw = innerW;
          fh = 22;
        }

        if (field.display == 'progress' && field.type == 'number') {
          // 初始值：从原卡提取的数值（如 HP 100/100 的当前值）
          final iv = initOf(field.name, field.initialValue);
          final cur = double.tryParse(iv) ?? 0.0;
          elements.add(_progress(
            id: nextId('el'),
            name: field.name,
            x: fx,
            y: fy,
            w: fw,
            h: fh,
            layer: 1,
            statusFieldId: fid,
            barFillColor: _barColorOf(field.name, 0xFF4FA3D1),
            barTrackColor: 0xFF2A2D36,
            current: cur,
            min: field.min ?? 0.0,
            max: field.max ?? 100.0,
          ));
          // progress 本身不自带 label，加一行文本标签（AI 没给布局时在条上方）
          elements.add(_text(
            id: nextId('el'),
            name: '${field.name}标签',
            text: label,
            x: fx,
            y: (field.y != null) ? fy : fy - 16,
            w: fw,
            h: 14,
            fontSize: 10,
            color: 0xFFAAB0BC,
            align: 'left',
            layer: 1,
          ));
          statusFields.add({
            'id': fid,
            'name': field.name,
            'type': 'number',
            'initial_value': initOf(field.name, field.initialValue),
            'min_value': field.min ?? 0.0,
            'max_value': field.max ?? 100.0,
            'pin_side': 'none',
            'order': statusFields.length,
            'owner': 'player',
          });
          if (field.y == null) y += 34;
        } else {
          // 文本字段：AI 明确 scroll:true 时用固定高度滚动框；
          // 否则按内容长度估算（兜底）。若 AI 给了 x/y/w/h 则用 AI 的，
          // 不靠估算撑高 PCB。
          final text = initOf(field.name, field.initialValue).isEmpty
              ? '—'
              : initOf(field.name, field.initialValue);
          final (autoH, autoMode) = _sceneTextSizing(field.name, text);
          final effH = field.height != null ? field.height! : autoH;
          final effMode = field.scroll || field.height != null
              ? 'scroll'
              : autoMode;
          elements.add(_text(
            id: nextId('el'),
            name: field.name,
            text: text,
            x: fx,
            y: fy,
            w: fw,
            h: effH,
            fontSize: 12,
            color: 0xFFE8EDF5,
            align: 'left',
            layer: 1,
            statusFieldId: fid,
            overflow: effMode,
          ));
          statusFields.add({
            'id': fid,
            'name': field.name,
            'type': 'text',
            'initial_value': initOf(field.name, field.initialValue),
            'pin_side': 'none',
            'order': statusFields.length,
            'owner': 'player',
          });
          if (field.y == null) y += effH + 6;
        }
      }

      // 面板底部留一个间距（仅当面板走兜底纵向排布时）。
      pageCursor[page] = (hasExplicitLayout ? pageCursor[page]! : y) + 16.0;
    }

    // 组装 pages：加底部底板 + 由 AI 声明的外壳（消息流/输入框/设置按钮）
    // + 多页面切换（手势）
    //
    // **核心原则**：外壳组件不再硬塞，而是执行 AI 的 chrome 声明。
    // AI 声明某页有消息流/输入框/设置按钮就放，没声明就不放（纯内容页）。
    // 唯一兜底：整卡没有任何页声明 settingsButton 时，补一个到首页不碍事
    // 的位置（引擎硬性要求，否则 scene 不启用），并写进 notes。
    final pagesJson = <Map<String, dynamic>>[];
    var sort = 0;
    final pageCount = intent.pages.length;

    // 计算 PCB 高度：
    //  - 若 AI 为页面指定了 pcbHeight，取各页最大的（clamp 合理范围）；
    //  - 否则按「内容最多的那页」的真实内容底部推算（含面板与 chrome 占位）。
    double maxContentBottom = 250.0;
    double maxChromeBottom = 250.0;
    bool anyExplicitPageHeight = false;
    double maxExplicitPageHeight = 0.0;
    for (final p in intent.pages) {
      final cb = pageCursor[p.id] ?? 250.0;
      if (cb > maxContentBottom) maxContentBottom = cb;
      // chrome 组件底部（消息流/输入框/设置按钮）
      void consider(double? x, double? y, double? w, double? h) {
        if (y != null && h != null && (y + h) > maxChromeBottom) {
          maxChromeBottom = y + h;
        }
      }
      consider(
        p.chrome.messageFlow?.x, p.chrome.messageFlow?.y,
        p.chrome.messageFlow?.width, p.chrome.messageFlow?.height,
      );
      consider(
        p.chrome.input?.x, p.chrome.input?.y,
        p.chrome.input?.width, p.chrome.input?.height,
      );
      consider(
        p.chrome.settingsButton?.x, p.chrome.settingsButton?.y,
        p.chrome.settingsButton?.width, p.chrome.settingsButton?.height,
      );
      if (p.pcbHeight != null) {
        anyExplicitPageHeight = true;
        if (p.pcbHeight! > maxExplicitPageHeight) maxExplicitPageHeight = p.pcbHeight!;
      }
    }

    double contentBottom;
    if (anyExplicitPageHeight) {
      // AI 指定了页高：取所有页里最大的指定高度（clamp 700~1870）。
      contentBottom = maxExplicitPageHeight.clamp(700.0, 1870.0);
    } else {
      // 取「内容底部」与「chrome 底部」的较大者，避免内容或外壳越界。
      final real = maxContentBottom > maxChromeBottom
          ? maxContentBottom : maxChromeBottom;
      // 内容区上限：PCB 高度最高 2000（引擎硬上限），底栏需在内容之下 130。
      contentBottom = real.clamp(250.0, 1870.0);
    }
    final pcbH = (contentBottom + 130.0).clamp(900.0, 2000.0);

    // 检查整卡是否有设置按钮（引擎硬性要求）。
    bool anySettingsButton = intent.pages.any(
      (p) => p.chrome.settingsButton != null,
    );
    if (!anySettingsButton) {
      notes.add('AI 未在任何页面声明「打开聊天设置」按钮（引擎硬性要求），'
          '已在首页兜底补一个，请到编辑器确认位置。');
    }

    for (var pIdx = 0; pIdx < pageCount; pIdx++) {
      final p = intent.pages[pIdx];
      final elements = pageElements[p.id] ?? <Map<String, dynamic>>[];
      final extras = <Map<String, dynamic>>[];
      final chrome = p.chrome;

      // ── 消息流：AI 声明了才放 ──
      if (chrome.messageFlow != null) {
        final mf = chrome.messageFlow!;
        extras.add(_element(
          id: nextId('el'),
          x: mf.x ?? pad,
          y: mf.y ?? 30,
          w: mf.width ?? innerW,
          h: mf.height ?? 200,
          layer: 1,
          module: _module(
            id: nextId('m'),
            name: '消息流',
            type: 'message_flow',
            color: 0x00000000,
            radius: 10,
            props: {
              'historyLimit': 0,
              'fontSize': 12.5,
              'showUser': true,
              'showAssistant': true,
              'richText': true,
              'userBubbleColor': 0xFFDCF8C6,
              'assistantBubbleColor': 0xFFF1F1F4,
              'bubbleRadius': 10.0,
            },
          ),
        ));
      }

      // ── 输入框：AI 声明了才放 ──
      if (chrome.input != null) {
        final inp = chrome.input!;
        extras.add(_element(
          id: nextId('el'),
          x: inp.x ?? pad,
          y: inp.y ?? pcbH - 50,
          w: inp.width ?? innerW - 48,
          h: inp.height ?? 40,
          layer: 2,
          module: _module(
            id: nextId('m'),
            name: '行动输入',
            type: 'input',
            color: 0xFF000000,
            radius: 8,
            props: {
              'placeholder': '写下你的行动，回车发送',
              'text': '',
              'committedValue': '',
              'maxLength': 300,
              'sendsMessage': true,
            },
          ),
        ));
      }

      // ── 设置按钮：AI 声明了放；整卡都没有时在首页兜底补一个 ──
      if (chrome.settingsButton != null ||
          (!anySettingsButton && pIdx == 0)) {
        final sb = chrome.settingsButton;
        final x = sb?.x ?? pad + innerW - 40;
        final y = sb?.y ?? pcbH - 50;
        final w = sb?.width ?? 40.0;
        final h = sb?.height ?? 40.0;
        extras.add(_button(
          id: nextId('el'),
          name: '设置',
          x: x,
          y: y,
          w: w,
          h: h,
          layer: 2,
          sendsMessage: false,
          keyAction: true,
          color: visualTheme.accentColor,
        ));
      }

      // 底板放最底层
      final bg = _surface(
        id: nextId('el'),
        name: '底板',
        x: 0,
        y: 0,
        w: pcbW,
        h: pcbH,
        color: visualTheme.pcbColor,
        layer: 0,
        radius: visualTheme.borderRadius,
      );

      // 手势：左右滑切换平级页（引擎原生支持 AssemblyPageGesture）。
      final gestures = <Map<String, dynamic>>[
        if (pIdx > 0)
          {
            'direction': 'swipe_right',
            'action': 'switch_base_page',
            'targetPageId': intent.pages[pIdx - 1].id,
            'transition': 'base_slide',
            'durationMs': 200,
          },
        if (pIdx < pageCount - 1)
          {
            'direction': 'swipe_left',
            'action': 'switch_base_page',
            'targetPageId': intent.pages[pIdx + 1].id,
            'transition': 'base_slide',
            'durationMs': 200,
          },
      ];

      pagesJson.add({
        'id': p.id,
        'name': p.name,
        'type': 'base',
        'parentPageId': null,
        'sortOrder': sort++,
        'elements': [bg, ...elements, ...extras],
        'gestures': gestures,
        'propertyOverrides': <dynamic>[],
      });
    }

    final json = _assembly(
      id: nextId('asm'),
      name: '${cardName.isEmpty ? "角色" : cardName}·场景',
      mode: 'scene',
      pcbW: pcbW,
      pcbH: pcbH,
      pages: pagesJson,
      pcbColor: visualTheme.pcbColor,
      pcbRadius: visualTheme.borderRadius,
    );
    assemblies.add(json);

    return BuiltAssembly(
      assemblies: assemblies,
      statusFields: statusFields,
      notes: notes,
    );
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
