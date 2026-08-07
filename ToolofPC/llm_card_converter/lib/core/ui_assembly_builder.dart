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

/// 单页的布局意图（来自 AI 的 layout.pages[].columns/density/fill，或启发式）。
class _PageLayoutIntent {
  /// 网格列数。0 = 未指定，用启发式。
  final int columns;

  /// 'compact' | 'normal' | 'spacious' | ''。'' = 未指定。
  final String density;

  /// 是否尽量占满 PCB 高度。
  final bool fill;

  const _PageLayoutIntent({
    this.columns = 0,
    this.density = '',
    this.fill = false,
  });

  /// 实际生效的列数：AI 指定 > 0 用 AI 的，否则按字段数量启发式。
  int effectiveColumns(int fieldCount, String mode) {
    if (columns > 0) return columns;
    if (mode == 'extra_companion') return 1;
    if (fieldCount >= 8) return 2;
    if (fieldCount >= 4) {
      // 4~7 个字段：若都是数值属性（适合网格）则两列，否则单列。
      return 1;
    }
    return 1;
  }

  /// 行高缩放：compact 压紧、spacious 放宽。
  double rowScale() {
    switch (density) {
      case 'compact':
        return 0.85;
      case 'spacious':
        return 1.25;
      default:
        return 1.0;
    }
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

  /// 多份 AI UiDesignPlan → 多个可共存 assembly。
  ///
  /// 例如 SillyTavern 的“开场身份选择 + 正文终端场景”应编译成
  /// opening 与 scene 两份 UI，而不是把一次性的开场按钮硬塞进 scene。
  static BuiltAssembly buildFromPlans(
    List<UiDesignPlan> plans, {
    String cardName = '',
  }) {
    final assemblies = <String>[];
    final statusFields = <Map<String, dynamic>>[];
    final notes = <String>[];
    final seenStatusIds = <String>{};

    if (plans.isEmpty) {
      return const BuiltAssembly(
        assemblies: [],
        statusFields: [],
        notes: ['AI 没有输出任何 UI 方案。'],
      );
    }

    for (final plan in plans) {
      final built = buildFromPlan(plan, cardName: cardName);
      assemblies.addAll(built.assemblies);
      for (final field in built.statusFields) {
        final id = field['id']?.toString() ?? '';
        if (id.isEmpty || seenStatusIds.add(id)) {
          statusFields.add(field);
        }
      }
      notes.addAll(built.notes);
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
    final mode = plan.uiMode;
    var pageTitles = _planPageTitles(plan);
    final pageRoles = _planPageRoles(plan);
    final pageTypes = _planPageTypes(plan);
    final pageParents = _planPageParents(plan);

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
    if (mode == 'extra_companion' && plan.inputs.isNotEmpty) {
      notes.add('已跳过原卡 input_prompt：伴生 UI 内可直接使用聊天页主输入框，避免重复输入入口。');
    } else {
      for (final input in plan.inputs) {
        final page = _resolvePlanPage(input.page, pageTitles, '选项');
        inputsByPage.putIfAbsent(page, () => <UiPlanInput>[]).add(input);
      }
    }
    for (final a in plan.actions) {
      final page = _resolvePlanPage(a.page, pageTitles, '选项');
      actionsByPage.putIfAbsent(page, () => <UiPlanAction>[]).add(a);
    }

    // AI 有时会根据原卡证据创建“任务/好友”等页签，但没有给出可编译
    // 字段或动作。空页会误导作者，以为内容丢失；这里直接移除并说明原因。
    if (pageTitles.length > 1) {
      final emptyPages = pageTitles.where((title) {
        if (_isSceneMessagePage(mode, title, pageRoles[title])) return false;
        return (fieldsByPage[title]?.isEmpty ?? true) &&
            (inputsByPage[title]?.isEmpty ?? true) &&
            (actionsByPage[title]?.isEmpty ?? true);
      }).toList();
      if (emptyPages.isNotEmpty && emptyPages.length < pageTitles.length) {
        pageTitles = pageTitles
            .where((title) => !emptyPages.contains(title))
            .toList();
        for (final title in emptyPages) {
          notes.add('已移除空页面「$title」：AI 没有提供可编译的字段/输入/动作。');
        }
      }
    }
    if (pageTitles.isEmpty) pageTitles = ['主界面'];

    var basePageTitles = pageTitles
        .where((title) => pageTypes[title] != 'overlay')
        .toList();
    if (basePageTitles.isEmpty) {
      final promoted = pageTitles.first;
      pageTypes[promoted] = 'base';
      basePageTitles = [promoted];
      notes.add('AI 只输出了 overlay 页面，已将「$promoted」提升为 base 页面作为叠加页父级。');
    }

    // A: 布局意图解析：每页的列数 / 密度 / 是否占满。
    // AI 可在 layout.pages 里声明 columns / density / fill，未声明时
    // 由编译器按字段数量启发式决定（见 _resolvePageLayoutIntent）。
    final pageLayoutIntents = <String, _PageLayoutIntent>{};
    for (final spec in plan.layout.pages) {
      final title = spec.title.trim();
      if (title.isEmpty) continue;
      pageLayoutIntents[title] = _PageLayoutIntent(
        columns: spec.columns,
        density: spec.density,
        fill: spec.fill,
      );
    }
    // 补充 AI 可能只放在 fields.page 里的页面：它们没有 spec，用默认意图。
    for (final title in pageTitles) {
      pageLayoutIntents.putIfAbsent(title, () => const _PageLayoutIntent());
    }

    final declaredMessagePage = pageTitles.any(
      (title) => _isSceneMessagePage(mode, title, pageRoles[title]),
    );
    final fallbackMessagePage = mode == 'scene' && !declaredMessagePage
        ? basePageTitles.first
        : '';
    if (fallbackMessagePage.isNotEmpty) {
      notes.add('scene 方案没有声明 story/message 页面；已在「$fallbackMessagePage」自动插入 message_flow，避免正文悬空。');
    }

    final pageIds = <String, String>{
      for (final title in pageTitles) title: 'page_${nextId('page')}',
    };

    String parentTitleOf(String title) {
      final requested = pageParents[title]?.trim() ?? '';
      if (requested.isNotEmpty && basePageTitles.contains(requested)) {
        return requested;
      }
      return basePageTitles.first;
    }

    final overlayTargetsByParent = <String, List<({String title, String pageId})>>{};
    for (final title in pageTitles) {
      if (pageTypes[title] != 'overlay') continue;
      final parent = parentTitleOf(title);
      overlayTargetsByParent
          .putIfAbsent(parent, () => <({String title, String pageId})>[])
          .add((title: title, pageId: pageIds[title] ?? ''));
    }
    if (overlayTargetsByParent.values.any((items) => items.isNotEmpty)) {
      final count = overlayTargetsByParent.values.fold<int>(
        0,
        (sum, items) => sum + items.length,
      );
      notes.add('已编译 $count 个 overlay 叠加页，并在父页面生成打开入口。');
    }

    final pcbW = switch (mode) {
      'extra_companion' => 212.0,
      'opening' => 320.0,
      'scene' => 360.0,
      'extra_sticky' => 320.0,
      _ => 212.0,
    };
    final innerW = pcbW - _Layout.pcbPadding * 2;
    final pages = <Map<String, dynamic>>[];
    final pageHeights = <({String title, bool isOverlay, double height})>[];

    for (var i = 0; i < pageTitles.length; i++) {
      final title = pageTitles[i];
      final isOverlayPage = pageTypes[title] == 'overlay';
      final parentTitle = isOverlayPage ? parentTitleOf(title) : null;
      final elements = _buildPlanPageElements(
        pageTitle: title,
        navigationTitles: isOverlayPage ? const [] : basePageTitles,
        pageIds: pageIds,
        overlayTargets: isOverlayPage
            ? const <({String title, String pageId})>[]
            : (overlayTargetsByParent[title] ?? const <({String title, String pageId})>[]),
        parentPageId: parentTitle == null ? null : pageIds[parentTitle],
        isOverlayPage: isOverlayPage,
        fields: fieldsByPage[title] ?? const [],
        inputs: inputsByPage[title] ?? const [],
        actions: actionsByPage[title] ?? const [],
        nextId: nextId,
        statusFields: statusFields,
        theme: theme,
        mode: mode,
        pcbW: pcbW,
        innerW: innerW,
        pageIntent: pageLayoutIntents[title] ?? const _PageLayoutIntent(),
        showMessageFlow: title == fallbackMessagePage ||
            _isSceneMessagePage(mode, title, pageRoles[title]),
      );
      final h = _pageContentHeight(elements);
      pageHeights.add((title: title, isOverlay: isOverlayPage, height: h));
      pages.add({
        'id': pageIds[title],
        'name': title,
        'type': isOverlayPage ? 'overlay' : 'base',
        'parentPageId': parentTitle == null ? null : pageIds[parentTitle],
        'sortOrder': i,
        'elements': elements,
        'gestures': isOverlayPage
            ? const <Map<String, dynamic>>[]
            : _planGesturesForPage(
                mode: mode,
                index: basePageTitles.indexOf(title),
                pageTitles: basePageTitles,
                pageIds: pageIds,
                navigation: plan.layout.navigation,
              ),
        'propertyOverrides': <dynamic>[],
      });
    }

    final allHeights = pageHeights.map((item) => item.height).toList();
    final hasOverlayPages = pageHeights.any((item) => item.isOverlay);
    final contentPcbH = allHeights.isEmpty
        ? 96.0
        : allHeights.reduce((a, b) => a > b ? a : b);
    final minPcbH = mode == 'scene' && hasOverlayPages ? 760.0 : 96.0;
    final pcbH = contentPcbH.clamp(minPcbH, 2000.0).toDouble();
    for (final page in pages) {
      final elements = page['elements'];
      if (elements is! List) continue;
      for (final element in elements) {
        if (element is Map && element['name'] == '底板') {
          final size = element['size'];
          final offset = element['offset'];
          if (size is Map) {
            final insetX = offset is Map
                ? ((offset['x'] as num?)?.toDouble() ?? 0.0)
                : 0.0;
            final insetY = offset is Map
                ? ((offset['y'] as num?)?.toDouble() ?? 0.0)
                : 0.0;
            size['width'] = (pcbW - insetX * 2).clamp(0.0, pcbW).toDouble();
            size['height'] = (pcbH - insetY * 2).clamp(0.0, pcbH).toDouble();
          }
        }
      }
      _expandScrollableContentToFillPage(
        elements.cast<Map<String, dynamic>>(),
        pcbH: pcbH,
      );
      // 几何自检：把所有元素收敛到 PCB 内边距内，超宽文本转 wrap / 补高。
      _sanitizeElementGeometry(
        elements.cast<Map<String, dynamic>>(),
        pcbW: pcbW,
        pcbH: pcbH,
      );
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

  static Map<String, String> _planPageRoles(UiDesignPlan plan) {
    final out = <String, String>{};
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isNotEmpty) out[title] = page.role.trim().toLowerCase();
    }
    return out;
  }

  static Map<String, String> _planPageTypes(UiDesignPlan plan) {
    final out = <String, String>{};
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isNotEmpty) out[title] = page.type;
    }
    return out;
  }

  static Map<String, String> _planPageParents(UiDesignPlan plan) {
    final out = <String, String>{};
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isNotEmpty && page.parentPage.trim().isNotEmpty) {
        out[title] = page.parentPage.trim();
      }
    }
    return out;
  }

  static bool _isSceneMessagePage(String mode, String title, String? role) {
    if (mode != 'scene') return false;
    final r = (role ?? '').toLowerCase();
    if (const {'story', 'log', 'message', 'messages', 'content', 'narrative'}
        .contains(r)) {
      return true;
    }
    final t = title.toLowerCase();
    return title.contains('日志') ||
        title.contains('正文') ||
        title.contains('剧情') ||
        title.contains('故事') ||
        t.contains('log') ||
        t.contains('story');
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

  /// 多页 UI 的高度会按最高页统一。若某页只有一个滚动文本 / message_flow，
  /// 统一高度后就会在下方留下大片空白。这里把页面内最后一个可滚动内容块
  /// 拉伸到接近底部，让任务板、羁绊名录、日志页真正吃满 PCB。
  static void _expandScrollableContentToFillPage(
    List<Map<String, dynamic>> elements, {
    required double pcbH,
  }) {
    var candidateIndex = -1;
    var candidateY = -1.0;
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (!_isVisibleContentElement(element)) continue;
      if (!_isExpandableScrollableElement(element)) continue;
      final y = _elementY(element);
      if (y > candidateY) {
        candidateY = y;
        candidateIndex = i;
      }
    }
    if (candidateIndex < 0) return;

    final candidate = elements[candidateIndex];
    final y = _elementY(candidate);
    final currentH = _elementH(candidate);
    final candidateBottom = y + currentH;
    final below = <int>[];
    var lastBottom = candidateBottom;
    for (var i = 0; i < elements.length; i++) {
      if (i == candidateIndex) continue;
      final other = elements[i];
      if (!_isVisibleContentElement(other)) continue;
      final otherY = _elementY(other);
      if (otherY <= candidateBottom + 1) continue;
      below.add(i);
      final bottom = otherY + _elementH(other);
      if (bottom > lastBottom) lastBottom = bottom;
    }

    // 若 message_flow / 滚动正文下面还有输入框和按钮，不能只因为“下面有东西”
    // 就放弃扩展；否则全局 PCB 高度被其它页撑高时，正文页底部会空一大片。
    // 正确做法是：把后续输入/按钮整体推到底部，同时把滚动区补高。
    if (below.isNotEmpty) {
      final delta = (pcbH - _Layout.pcbPadding - lastBottom)
          .clamp(0.0, 2000.0)
          .toDouble();
      if (delta > 8) {
        final size = candidate['size'];
        final nextH = currentH + delta;
        if (size is Map) size['height'] = nextH;
        _resizeAlignedBackingSurfaces(elements, candidate, currentH, nextH);
        for (final index in below) {
          _shiftElementY(elements[index], delta);
        }
      }
      return;
    }

    final limit = pcbH - _Layout.pcbPadding;
    final nextH = (limit - y).clamp(currentH, 2000.0).toDouble();
    if (nextH > currentH + 8) {
      final size = candidate['size'];
      if (size is Map) size['height'] = nextH;
      _resizeAlignedBackingSurfaces(elements, candidate, currentH, nextH);
    }
  }

  static void _shiftElementY(Map<String, dynamic> element, double delta) {
    final offset = element['offset'];
    if (offset is Map) {
      final y = (offset['y'] as num?)?.toDouble() ?? 0.0;
      offset['y'] = y + delta;
    }
  }

  static void _resizeAlignedBackingSurfaces(
    List<Map<String, dynamic>> elements,
    Map<String, dynamic> candidate,
    double oldHeight,
    double newHeight,
  ) {
    final candidateOffset = candidate['offset'];
    final candidateSize = candidate['size'];
    if (candidateOffset is! Map || candidateSize is! Map) return;
    final x = (candidateOffset['x'] as num?)?.toDouble() ?? 0.0;
    final y = (candidateOffset['y'] as num?)?.toDouble() ?? 0.0;
    final w = (candidateSize['width'] as num?)?.toDouble() ?? 0.0;
    for (final element in elements) {
      if (identical(element, candidate)) continue;
      final module = element['module'];
      if (module is! Map || module['type']?.toString() != 'surface') continue;
      final name = element['name']?.toString() ?? '';
      if (!name.startsWith('滚动底_') && !name.startsWith('滚动容器_')) continue;
      final offset = element['offset'];
      final size = element['size'];
      if (offset is! Map || size is! Map) continue;
      final sx = (offset['x'] as num?)?.toDouble() ?? 0.0;
      final sy = (offset['y'] as num?)?.toDouble() ?? 0.0;
      final sw = (size['width'] as num?)?.toDouble() ?? 0.0;
      final sh = (size['height'] as num?)?.toDouble() ?? 0.0;
      if (name.startsWith('滚动底_')) {
        final oldBackingH = oldHeight + 4.0;
        if ((sx - (x - 2)).abs() < 8 &&
            (sy - (y - 1)).abs() < 4 &&
            (sw - (w + 4)).abs() < 16 &&
            (sh - oldBackingH).abs() < 8) {
          size['height'] = newHeight + 4.0;
        }
      } else if (name.startsWith('滚动容器_')) {
        final containerY = y - _Layout.rowHeight - 2.0;
        final oldContainerH = _Layout.rowHeight + oldHeight + 10.0;
        if ((sx - _Layout.pcbPadding).abs() < 1 &&
            (sy - containerY).abs() < 8 &&
            (sw - (w + 12)).abs() < 16 &&
            (sh - oldContainerH).abs() < 12) {
          size['height'] = _Layout.rowHeight + newHeight + 10.0;
        }
      }
    }
  }

  static bool _isVisibleContentElement(Map<String, dynamic> element) {
    final module = element['module'];
    final type = module is Map ? module['type']?.toString() ?? '' : '';
    if (const {'linker', 'page_router', 'math_node', 'timer'}.contains(type)) {
      return false;
    }
    if (element['name'] == '底板') return false;
    final offset = element['offset'];
    if (offset is! Map) return false;
    final x = (offset['x'] as num?)?.toDouble() ?? 0.0;
    return x >= 0;
  }

  static bool _isExpandableScrollableElement(Map<String, dynamic> element) {
    final module = element['module'];
    if (module is! Map) return false;
    final type = module['type']?.toString() ?? '';
    final props = module['properties'];
    if (type == 'message_flow') return true;
    if (type == 'text' && props is Map) {
      return props['overflow']?.toString() == 'scroll';
    }
    return false;
  }

  static double _elementY(Map<String, dynamic> element) {
    final offset = element['offset'];
    return offset is Map ? ((offset['y'] as num?)?.toDouble() ?? 0.0) : 0.0;
  }

  static double _elementH(Map<String, dynamic> element) {
    final size = element['size'];
    return size is Map ? ((size['height'] as num?)?.toDouble() ?? 0.0) : 0.0;
  }

  /// 编译后几何自检：把每个可见元素收敛到 PCB 内边距内。
  ///
  /// 解决两类布局病：
  /// 1. **组件溢出**：元素右/下边缘超出 PCB 内边距时，clamp 宽高与位置；
  ///    `text` 超宽自动转 `wrap`，超高自动补足（scroll 字段除外）。
  /// 2. **横向越界**：`x + w` 超过 `pcbW - padding` 时缩窄到边界内。
  ///
  /// 后台逻辑件（linker / page_router / math_node / timer）与底板不参与——
  /// 它们本来就放在 PCB 外部逻辑区（x < 0）或整页铺满。
  static void _sanitizeElementGeometry(
    List<Map<String, dynamic>> elements, {
    required double pcbW,
    required double pcbH,
  }) {
    const pad = _Layout.pcbPadding;
    final maxRight = (pcbW - pad).clamp(pad, pcbW).toDouble();
    final maxBottom = (pcbH - pad).clamp(pad, pcbH).toDouble();
    const minSize = 16.0;

    for (final element in elements) {
      final module = element['module'];
      final type = module is Map ? module['type']?.toString() ?? '' : '';
      if (const {'linker', 'page_router', 'math_node', 'timer'}.contains(type)) {
        continue;
      }
      final name = element['name']?.toString() ?? '';
      if (name == '底板') continue;
      final offset = element['offset'];
      final size = element['size'];
      if (offset is! Map || size is! Map) continue;

      var x = (offset['x'] as num?)?.toDouble() ?? 0.0;
      var y = (offset['y'] as num?)?.toDouble() ?? 0.0;
      var w = (size['width'] as num?)?.toDouble() ?? 0.0;
      var h = (size['height'] as num?)?.toDouble() ?? 0.0;
      if (w <= 0 || h <= 0) continue;

      final isScroll = type == 'text' &&
          module['properties'] is Map &&
          module['properties']['overflow']?.toString() == 'scroll';

      // ── 横向越界收敛 ──
      if (x < pad) {
        final delta = pad - x;
        x = pad;
        w = (w - delta).clamp(minSize, maxRight - pad).toDouble();
      }
      if (x + w > maxRight) {
        w = (maxRight - x).clamp(minSize, maxRight - pad).toDouble();
      }

      // ── 纵向越界收敛 ──
      // scroll 字段顶部对齐是刻意的，不上移；其余越顶元素拉回边界。
      if (y < pad && !isScroll) {
        y = pad;
      }
      if (y + h > maxBottom) {
        if (!isScroll) {
          h = (maxBottom - y).clamp(minSize, maxBottom - pad).toDouble();
        }
      }

      // ── 超宽文本转 wrap（估算一行放不下就换行并补高）──
      if (type == 'text' && w > 0 && h > 0) {
        final props = module['properties'];
        if (props is Map) {
          final overflow = props['overflow']?.toString() ?? 'ellipsis';
          final text = props['text']?.toString() ?? '';
          final fontSize = props['fontSize'] is num
              ? (props['fontSize'] as num).toDouble()
              : 12.0;
          // 粗估：CJK 字符 ≈ fontSize 宽，ASCII ≈ 0.55 × fontSize。
          var estimatedWidth = 0.0;
          for (final rune in text.runes) {
            estimatedWidth += (rune > 0x2E80) ? fontSize : fontSize * 0.55;
          }
          if (overflow == 'ellipsis' && estimatedWidth > w * 1.15) {
            props['overflow'] = 'wrap';
            final needed = _Layout.rowHeight * 2;
            if (h < needed) h = needed.clamp(minSize, 80.0).toDouble();
          }
        }
      }

      offset['x'] = x;
      offset['y'] = y;
      size['width'] = w;
      size['height'] = h;
    }
  }

  static double _addOverlayToolbar({
    required List<Map<String, dynamic>> elements,
    required List<({String surface, String button})> pressPairs,
    required List<({String title, String pageId})> overlayTargets,
    required String Function(String) nextId,
    required UiVisualTheme theme,
    required double y,
    required double innerW,
  }) {
    if (overlayTargets.isEmpty) return y;
    final count = overlayTargets.length.clamp(1, 4).toInt();
    final gap = count == 1 ? 0.0 : 6.0;
    final buttonW = (innerW - (count - 1) * gap) / count;
    const buttonH = 26.0;
    for (var i = 0; i < count; i++) {
      final target = overlayTargets[i];
      if (target.pageId.trim().isEmpty) continue;
      final x = _Layout.pcbPadding + i * (buttonW + gap);
      final routerId = nextId('el');
      elements.add(_pageRouter(
        id: routerId,
        name: '打开_${target.title}',
        targetPageId: target.pageId,
        action: 'open_overlay',
        transition: 'overlay_fade',
        durationMs: 180,
      ));
      final surfaceId = nextId('el');
      elements.add(_surface(
        id: surfaceId,
        name: '叠加入口底_${target.title}',
        x: x,
        y: y,
        w: buttonW,
        h: buttonH,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '叠加入口文_${target.title}',
        text: target.title,
        x: x + 4,
        y: y + 5,
        w: buttonW - 8,
        h: 16,
        fontSize: 10,
        color: theme.valueColor,
        align: 'center',
        layer: elements.length + 1,
        overflow: 'wrap',
      ));
      final buttonId = nextId('el');
      elements.add(_button(
        id: buttonId,
        name: '打开${target.title}',
        x: x,
        y: y,
        w: buttonW,
        h: buttonH,
        layer: elements.length + 1,
        sendsMessage: false,
        keyAction: false,
        color: 0x00000000,
      ));
      elements.add(_pressLinker2(
        id: nextId('el'),
        name: '打开_${target.title}_路由',
        buttonId: buttonId,
        routerId: routerId,
        scheme: 'button_to_page_route',
        y: -104.0 - i * 52.0,
        layer: elements.length + 1,
      ));
      pressPairs.add((surface: surfaceId, button: buttonId));
    }
    return y + buttonH + 10.0;
  }

  static List<Map<String, dynamic>> _buildPlanPageElements({
    required String pageTitle,
    required List<String> navigationTitles,
    required Map<String, String> pageIds,
    required List<({String title, String pageId})> overlayTargets,
    required String? parentPageId,
    required bool isOverlayPage,
    required List<UiPlanField> fields,
    required List<UiPlanInput> inputs,
    required List<UiPlanAction> actions,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String mode,
    required double pcbW,
    required double innerW,
    _PageLayoutIntent? pageIntent,
    required bool showMessageFlow,
  }) {
    final elements = <Map<String, dynamic>>[];
    final pressPairs = <({String surface, String button})>[];
    final intent = pageIntent ?? const _PageLayoutIntent();
    final columns = intent.effectiveColumns(fields.length, mode);
    final rowScale = intent.rowScale();
    var y = _Layout.pcbPadding;

    if (navigationTitles.length > 1 && !isOverlayPage) {
      final tabW = (innerW - (navigationTitles.length - 1) * 6.0) / navigationTitles.length;
      const tabH = 22.0;
      final routerIds = <String, String>{};
      for (final title in navigationTitles) {
        if (title == pageTitle) continue;
        final routerId = nextId('el');
        routerIds[title] = routerId;
        elements.add(_pageRouter(
          id: routerId,
          name: '路由器_$title',
          targetPageId: pageIds[title] ?? '',
        ));
      }
      for (var i = 0; i < navigationTitles.length; i++) {
        final title = navigationTitles[i];
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

    if (isOverlayPage && parentPageId != null && parentPageId.isNotEmpty) {
      final routerId = nextId('el');
      elements.add(_pageRouter(
        id: routerId,
        name: '关闭叠加页',
        targetPageId: parentPageId,
        action: 'close_overlay',
        transition: 'overlay_fade',
        durationMs: 160,
      ));
      final closeX = pcbW - _Layout.pcbPadding - 28;
      final surfaceId = nextId('el');
      elements.add(_surface(
        id: surfaceId,
        name: '关闭底',
        x: closeX,
        y: _Layout.pcbPadding,
        w: 24,
        h: 22,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '关闭文',
        text: '×',
        x: closeX,
        y: _Layout.pcbPadding + 1,
        w: 24,
        h: 18,
        fontSize: 16,
        color: theme.titleColor,
        align: 'center',
        layer: elements.length + 1,
      ));
      final buttonId = nextId('el');
      elements.add(_button(
        id: buttonId,
        name: '关闭叠加页',
        x: closeX,
        y: _Layout.pcbPadding,
        w: 24,
        h: 22,
        layer: elements.length + 1,
        sendsMessage: false,
        keyAction: false,
        color: 0x00000000,
      ));
      elements.add(_pressLinker2(
        id: nextId('el'),
        name: '关闭叠加页路由',
        buttonId: buttonId,
        routerId: routerId,
        scheme: 'button_to_page_route',
        y: -52.0,
        layer: elements.length + 1,
      ));
      pressPairs.add((surface: surfaceId, button: buttonId));
    }

    if (overlayTargets.isNotEmpty) {
      y = _addOverlayToolbar(
        elements: elements,
        pressPairs: pressPairs,
        overlayTargets: overlayTargets,
        nextId: nextId,
        theme: theme,
        y: y,
        innerW: innerW,
      );
    }

    if (showMessageFlow) {
      final fullMessagePage = fields.isEmpty && inputs.isEmpty && actions.isEmpty;
      final flowHeight = fullMessagePage ? 650.0 : 320.0;
      elements.add(_messageFlow(
        id: nextId('el'),
        name: '剧情消息流',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: flowHeight,
        color: theme.panelColor,
        layer: elements.length + 1,
        radius: 10,
      ));
      y += flowHeight + 12.0;
    }

    final labelW = mode == 'extra_companion' ? 64.0 : 104.0;
    var fieldIndex = 0;
    while (fieldIndex < fields.length) {
      final group = fields[fieldIndex].group.trim();
      final groupFields = <UiPlanField>[];
      while (fieldIndex < fields.length && fields[fieldIndex].group.trim() == group) {
        groupFields.add(fields[fieldIndex]);
        fieldIndex++;
      }

      if (group.isNotEmpty) {
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
        elements.add(_line(
          id: nextId('el'),
          name: '分组线_$group',
          x: _Layout.pcbPadding,
          y: y + 17,
          w: innerW,
          h: 2,
          color: theme.accentColor,
          layer: elements.length + 1,
          style: 'dashed',
          thickness: 1.0,
        ));
        y += 22.0;
      }

      if (_isAttributeGridGroup(group, groupFields, mode)) {
        y = _renderAttributeGridFields(
          elements: elements,
          fields: groupFields,
          nextId: nextId,
          statusFields: statusFields,
          theme: theme,
          y: y,
          innerW: innerW,
        );
      } else if (_isCoreProgressGroup(groupFields, mode)) {
        y = _renderProgressClusterFields(
          elements: elements,
          fields: groupFields,
          nextId: nextId,
          statusFields: statusFields,
          theme: theme,
          mode: mode,
          y: y,
          innerW: innerW,
          labelW: labelW,
        );
      } else if (columns >= 2 && groupFields.length >= 2) {
        // 列数 > 1 时，普通字段组也走网格：每行放 columns 个字段，
        // 长文本字段自动占满整行（span 2）。
        y = _renderFieldGrid(
          elements: elements,
          fields: groupFields,
          nextId: nextId,
          statusFields: statusFields,
          theme: theme,
          mode: mode,
          y: y,
          innerW: innerW,
          columns: columns,
          rowScale: rowScale,
        );
      } else {
        for (final f in groupFields) {
          y = _renderPlanFieldStandard(
            elements: elements,
            field: f,
            nextId: nextId,
            statusFields: statusFields,
            theme: theme,
            mode: mode,
            y: y,
            innerW: innerW,
            labelW: labelW,
            rowScale: rowScale,
          );
        }
      }
    }

    if (inputs.isNotEmpty) {
      elements.add(_sectionTitle(
        id: nextId('el'),
        title: mode == 'opening' ? '角色设定填写' : '输入',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        color: theme.titleColor,
        layer: elements.length + 1,
      ));
      y += 26.0;
    }
    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final inputLabel = input.name.trim().isEmpty ? '输入 ${i + 1}' : input.name.trim();
      elements.add(_text(
        id: nextId('el'),
        name: '${inputLabel}标签',
        text: inputLabel,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: 18,
        fontSize: mode == 'extra_companion' ? 10 : 12,
        color: theme.labelColor,
        align: 'left',
        layer: elements.length + 1,
        overflow: 'wrap',
      ));
      y += 20.0;
      final statusFieldId = input.targetKind == 'status_field'
          ? 'sf_${_slug(input.sourceKey.trim().isEmpty ? input.name : input.sourceKey)}'
          : null;
      if (statusFieldId != null &&
          !statusFields.any((field) => field['id'] == statusFieldId)) {
        statusFields.add({
          'id': statusFieldId,
          'name': input.name,
          'type': 'text',
          'initial_value': input.initialValue,
          'min_value': null,
          'max_value': null,
          'pin_side': 'none',
          'order': statusFields.length,
          'owner': 'player',
        });
      }
      final inputId = nextId('el');
      elements.add(_input(
        id: inputId,
        name: input.name.trim().isEmpty ? '输入_${i + 1}' : input.name,
        placeholder: input.placeholder,
        initialValue: input.initialValue,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        layer: elements.length + 1,
        sendsMessage: input.sendOnSubmit,
        color: theme.accentColor,
        dataChannel: statusFieldId == null
            ? null
            : _inputStatusChannel(
                label: input.name,
                elementId: inputId,
                statusFieldId: statusFieldId,
              ),
      ));
      y += _Layout.buttonHeight + 8;
    }

    final localActions = [...actions];
    if (localActions.isNotEmpty) {
      elements.add(_sectionTitle(
        id: nextId('el'),
        title: mode == 'opening' ? '选择开场方向' : '可执行操作',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        color: theme.titleColor,
        layer: elements.length + 1,
      ));
      y += 26.0;
    }
    final needsGeneratedKeyAction = isOverlayPage
        ? false
        : (mode == 'opening'
            ? localActions.isEmpty
            : (_modeRequiresGeneratedKeyAction(mode) &&
                !localActions.any((a) => a.sendText.trim().isEmpty)));
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
      final buttonH = label.runes.length > 18 ? 44.0 : _Layout.buttonHeight;
      final surfaceId = nextId('el');
      elements.add(_surface(
        id: surfaceId,
        name: '按钮底_${i + 1}',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: buttonH,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '按钮文_${i + 1}',
        text: label,
        x: _Layout.pcbPadding + 10,
        y: y + 7,
        w: innerW - 20,
        h: buttonH - 12,
        fontSize: mode == 'extra_companion' ? 10 : 12,
        color: theme.valueColor,
        align: 'center',
        layer: elements.length + 1,
        overflow: 'wrap',
      ));
      final buttonId = nextId('el');
      final shouldSendMessage =
          !(mode == 'opening' && a.branchIndex != null) && a.sendText.trim().isNotEmpty;
      elements.add(_button(
        id: buttonId,
        name: label,
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: buttonH,
        layer: elements.length + 1,
        sendsMessage: shouldSendMessage,
        keyAction: _shouldMarkKeyAction(mode, a),
        message: shouldSendMessage ? a.sendText.trim() : '',
        targetBranchIndex: mode == 'opening' ? a.branchIndex : null,
        color: theme.accentColor,
      ));
      pressPairs.add((surface: surfaceId, button: buttonId));
      y += buttonH + 8;
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

    final frameInset = _frameInsetFor(mode);
    final bgHeight = (y + _Layout.pcbPadding).clamp(64.0, 2000.0).toDouble();
    final bg = _surface(
      id: nextId('el'),
      name: '底板',
      x: frameInset,
      y: frameInset,
      w: (pcbW - frameInset * 2).clamp(0.0, pcbW).toDouble(),
      h: (bgHeight - frameInset * 2).clamp(0.0, bgHeight).toDouble(),
      color: theme.panelColor,
      layer: 0,
      radius: theme.borderRadius,
    );
    return [bg, ...elements];
  }

  static String _planFieldId(UiPlanField field) =>
      'sf_${_slug(field.sourceKey.trim().isEmpty ? field.name : field.sourceKey)}';

  static void _addStatusFieldForPlanField(
    List<Map<String, dynamic>> statusFields,
    UiPlanField field, {
    required String fieldId,
    required String initial,
    required double? min,
    required double? max,
  }) {
    if (statusFields.any((item) => item['id'] == fieldId)) return;
    statusFields.add({
      'id': fieldId,
      'name': field.name,
      'type': field.isNumber ? 'number' : 'text',
      'initial_value': initial,
      'min_value': field.isNumber ? min : null,
      'max_value': field.isNumber ? max : null,
      'pin_side': 'none',
      'order': statusFields.length,
      'owner': field.owner,
      if (field.branchInitialValues.isNotEmpty)
        'branch_initial_values': field.branchInitialValues,
    });
  }

  static bool _isCoreProgressGroup(List<UiPlanField> fields, String mode) {
    if (mode == 'extra_companion') return false;
    final progressFields = fields.where((f) => f.isNumber && f.display == 'progress').toList();
    if (progressFields.length < 2) return false;
    final joined = progressFields.map((f) => '${f.name} ${f.sourceKey}').join(' ').toLowerCase();
    final hasHpMp = (joined.contains('hp') || joined.contains('生命')) &&
        (joined.contains('mp') || joined.contains('法力') || joined.contains('魔力'));
    final hasXp = joined.contains('xp') || joined.contains('经验') || joined.contains('exp');
    return hasHpMp || hasXp;
  }

  static bool _isAttributeGridGroup(
    String group,
    List<UiPlanField> fields,
    String mode,
  ) {
    if (mode == 'extra_companion') return false;
    final numeric = fields.where((f) => f.isNumber && f.display != 'progress').toList();
    if (numeric.length < 4) return false;
    final fieldKeys = numeric.map((f) => '${f.name} ${f.sourceKey}').join(' ');
    final text = '$group $fieldKeys'.toLowerCase();
    const markers = ['核心属性', '属性', 'str', 'agi', 'int', 'con', 'per', 'cha', 'dex', 'wis'];
    return markers.any(text.contains);
  }

  static double _renderPlanFieldStandard({
    required List<Map<String, dynamic>> elements,
    required UiPlanField field,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String mode,
    required double y,
    required double innerW,
    required double labelW,
    double rowScale = 1.0,
  }) {
    final fieldId = _planFieldId(field);
    final isProgress = field.isNumber && field.display == 'progress';
    final min = field.min ?? 0.0;
    final max = field.max ?? 100.0;
    final initialNumber = _numberOf(field.initialValue) ?? min;
    final initial = field.isNumber ? _trimNumber(initialNumber) : field.initialValue;

    _addStatusFieldForPlanField(
      statusFields,
      field,
      fieldId: fieldId,
      initial: initial,
      min: min,
      max: max,
    );

    final needsWideText = !isProgress && _needsWideTextLayout(field, initial, mode);
    final shouldScrollText = !isProgress && _shouldScrollTextField(field, initial, mode);
    final effectiveOverflow = shouldScrollText
        ? 'scroll'
        : (needsWideText && field.overflow == 'ellipsis' ? 'wrap' : field.overflow);
    final shouldWrapText = !isProgress && effectiveOverflow == 'wrap';
    final valueHeight = shouldScrollText
        ? _scrollTextHeightFor(initial, mode)
        : (shouldWrapText ? _wrapTextHeightFor(initial, mode) : _Layout.rowHeight);
    final fullProgress = isProgress && mode != 'extra_companion';
    final labelText = fullProgress
        ? _progressLabelText(field.name, initial, max)
        : field.name;

    if (shouldScrollText) {
      elements.add(_surface(
        id: nextId('el'),
        name: '滚动容器_${field.name}',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: _Layout.rowHeight + valueHeight + 4,
        color: _softPanelColor(theme),
        layer: elements.length + 1,
        radius: 10,
      ));
    }

    elements.add(_text(
      id: nextId('el'),
      name: '${field.name}标签',
      text: labelText,
      x: _Layout.pcbPadding,
      y: y,
      w: (shouldScrollText || fullProgress || needsWideText) ? innerW : labelW,
      h: fullProgress ? 20 : _Layout.rowHeight,
      fontSize: mode == 'extra_companion' ? 10 : 12,
      color: theme.labelColor,
      align: fullProgress ? 'center' : 'left',
      layer: elements.length + 1,
      overflow: (fullProgress || needsWideText) ? 'wrap' : 'ellipsis',
      richText: fullProgress,
    ));

    if (isProgress) {
      elements.add(_progress(
        id: nextId('el'),
        name: field.name,
        x: fullProgress ? _Layout.pcbPadding : _Layout.pcbPadding + labelW + 6,
        y: fullProgress ? y + 20 : y + (_Layout.rowHeight - _Layout.barHeight) / 2,
        w: fullProgress ? innerW : innerW - labelW - 6,
        h: _Layout.barHeight,
        statusFieldId: fieldId,
        layer: elements.length + 1,
        barFillColor: _barColorOf(field.name, theme.barFillColor),
        barTrackColor: _barTrackColorOf(field.name, theme.barTrackColor),
        min: min,
        max: max,
        current: initialNumber.clamp(min, max).toDouble(),
      ));
    } else {
      final valueX = (shouldScrollText || needsWideText)
          ? _Layout.pcbPadding
          : _Layout.pcbPadding + labelW + 6;
      final valueY = (shouldScrollText || needsWideText) ? y + _Layout.rowHeight : y;
      final valueW = (shouldScrollText || needsWideText) ? innerW : innerW - labelW - 6;
      final scrollInset = shouldScrollText ? 6.0 : 0.0;
      final textX = valueX + scrollInset;
      final textY = valueY + (shouldScrollText ? 2.0 : 0.0);
      final textW = (valueW - scrollInset * 2).clamp(24.0, valueW).toDouble();
      final textH = (valueHeight - (shouldScrollText ? 6.0 : 0.0))
          .clamp(_Layout.rowHeight, valueHeight)
          .toDouble();
      if (shouldScrollText) {
        elements.add(_surface(
          id: nextId('el'),
          name: '滚动底_${field.name}',
          x: valueX + 4,
          y: valueY + 1,
          w: (valueW - 8).clamp(24.0, valueW).toDouble(),
          h: (valueHeight - 2).clamp(_Layout.rowHeight, valueHeight).toDouble(),
          color: _innerScrollPanelColor(theme),
          layer: elements.length + 1,
          radius: 8,
        ));
      }
      elements.add(_text(
        id: nextId('el'),
        name: field.name,
        text: initial.isEmpty ? '—' : initial,
        x: textX,
        y: textY,
        w: textW,
        h: textH,
        fontSize: shouldScrollText
            ? _scrollTextFontSizeFor(field, initial, mode)
            : (mode == 'extra_companion' ? 11 : 12),
        color: theme.valueColor,
        align: field.textAlign,
        layer: elements.length + 1,
        statusFieldId: fieldId,
        overflow: effectiveOverflow,
        richText: shouldScrollText,
        contentPadding: shouldScrollText ? 8.0 : null,
      ));
    }
    final usedH = (isProgress
            ? (fullProgress ? 20 + _Layout.barHeight : _Layout.rowHeight)
            : ((shouldScrollText || needsWideText)
                ? _Layout.rowHeight + valueHeight
                : valueHeight)) +
        _Layout.rowGap;
    // 密度缩放：compact 压紧到 85%，spacious 放宽到 125%。
    final scaled = usedH * rowScale;
    return y + scaled.clamp(usedH * 0.85, usedH * 1.25).toDouble();
  }

  /// 列数感知的字段网格：每行放 [columns] 个字段，长文本自动占满整行。
  ///
  /// 相比 `_renderPlanFieldStandard` 的单列排布，网格能显著压缩属性面板高度，
  /// 避免「一字段一行」在窄 PCB 上撑出大量纵向空白。
  static double _renderFieldGrid({
    required List<Map<String, dynamic>> elements,
    required List<UiPlanField> fields,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String mode,
    required double y,
    required double innerW,
    required int columns,
    double rowScale = 1.0,
  }) {
    const gap = 8.0;
    final cellW = (innerW - (columns - 1) * gap) / columns;
    final colCount = columns.clamp(2, 3);

    // 先计算每个字段需要的行高：数值短值单行，长文本按内容估算。
    double fieldRowHeight(UiPlanField f) {
      if (f.isNumber && f.display == 'progress') return 26.0;
      final v = f.initialValue.trim();
      if (f.overflow == 'scroll' || v.contains('\n')) {
        final h = _scrollTextHeightFor(v, mode);
        return (h * rowScale).clamp(26.0, 200.0).toDouble();
      }
      if (v.runes.length > 18 || f.name.runes.length > 8) {
        final h = _wrapTextHeightFor(v, mode);
        return (h * rowScale).clamp(22.0, 80.0).toDouble();
      }
      return (22.0 * rowScale).clamp(18.0, 30.0).toDouble();
    }

    var col = 0;
    double rowMaxH = 0.0;
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final fieldId = _planFieldId(f);
      final min = f.min ?? 0.0;
      final max = f.max ?? 100.0;
      final initialNumber = _numberOf(f.initialValue) ?? min;
      final initial = f.isNumber ? _trimNumber(initialNumber) : f.initialValue;
      _addStatusFieldForPlanField(
        statusFields,
        f,
        fieldId: fieldId,
        initial: initial,
        min: f.isNumber ? min : null,
        max: f.isNumber ? max : null,
      );

      // span 2 = 占满整行；长文本也自动占满。
      final span = (f.span == 2 || f.overflow == 'scroll' || initial.runes.length > 18)
          ? colCount
          : 1;
      if (col + span > colCount) {
        y += rowMaxH + gap;
        col = 0;
        rowMaxH = 0.0;
      }

      final x = _Layout.pcbPadding + col * (cellW + gap);
      final w = cellW * span + (span - 1) * gap;
      final cellH = fieldRowHeight(f);
      if (cellH > rowMaxH) rowMaxH = cellH;

      final isProgress = f.isNumber && f.display == 'progress';
      if (isProgress) {
        elements.add(_text(
          id: nextId('el'),
          name: '${f.name}标签',
          text: _progressLabelText(f.name, initial, max),
          x: x,
          y: y,
          w: w,
          h: 16,
          fontSize: mode == 'extra_companion' ? 10 : 11,
          color: theme.labelColor,
          align: 'left',
          layer: elements.length + 1,
          overflow: 'wrap',
          richText: true,
        ));
        elements.add(_progress(
          id: nextId('el'),
          name: f.name,
          x: x,
          y: y + 18,
          w: w,
          h: _Layout.barHeight,
          statusFieldId: fieldId,
          layer: elements.length + 1,
          barFillColor: _barColorOf(f.name, theme.barFillColor),
          barTrackColor: _barTrackColorOf(f.name, theme.barTrackColor),
          min: min,
          max: max,
          current: initialNumber.clamp(min, max).toDouble(),
        ));
      } else {
        final scroll = f.overflow == 'scroll' || initial.contains('\n');
        final wrap = !scroll && (f.overflow == 'wrap' || initial.runes.length > 18);
        final effOverflow = scroll ? 'scroll' : (wrap ? 'wrap' : 'ellipsis');
        elements.add(_text(
          id: nextId('el'),
          name: f.name,
          text: initial.isEmpty ? '—' : initial,
          x: x,
          y: y,
          w: w,
          h: cellH,
          fontSize: mode == 'extra_companion' ? 10.5 : 11,
          color: theme.valueColor,
          align: f.textAlign,
          layer: elements.length + 1,
          statusFieldId: fieldId,
          overflow: effOverflow,
          richText: scroll,
          contentPadding: scroll ? 6.0 : null,
        ));
      }

      col += span;
    }
    return y + rowMaxH + _Layout.rowGap;
  }

  static double _renderAttributeGridFields({
    required List<Map<String, dynamic>> elements,
    required List<UiPlanField> fields,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required double y,
    required double innerW,
  }) {
    const columns = 2;
    const gap = 8.0;
    const cellH = 32.0;
    final cellW = (innerW - gap) / columns;
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final fieldId = _planFieldId(field);
      final min = field.min ?? 0.0;
      final max = field.max ?? 100.0;
      final initialNumber = _numberOf(field.initialValue) ?? min;
      final initial = field.isNumber ? _trimNumber(initialNumber) : field.initialValue;
      _addStatusFieldForPlanField(
        statusFields,
        field,
        fieldId: fieldId,
        initial: initial,
        min: field.isNumber ? min : null,
        max: field.isNumber ? max : null,
      );
      final col = i % columns;
      final row = i ~/ columns;
      final x = _Layout.pcbPadding + col * (cellW + gap);
      final cellY = y + row * (cellH + gap);
      elements.add(_surface(
        id: nextId('el'),
        name: '${field.name}格底',
        x: x,
        y: cellY,
        w: cellW,
        h: cellH,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 7,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: field.name,
        text: '${field.name}: ${initial.isEmpty ? '—' : initial}',
        x: x + 6,
        y: cellY + 7,
        w: cellW - 12,
        h: 18,
        fontSize: 11,
        color: theme.valueColor,
        align: 'center',
        layer: elements.length + 1,
        statusFieldId: fieldId,
        overflow: 'wrap',
      ));
    }
    final rows = (fields.length / columns).ceil();
    final rowGaps = ((rows - 1).clamp(0, 999) as num).toDouble() * gap;
    return y + rows * cellH + rowGaps + _Layout.rowGap;
  }

  static double _renderProgressClusterFields({
    required List<Map<String, dynamic>> elements,
    required List<UiPlanField> fields,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required String mode,
    required double y,
    required double innerW,
    required double labelW,
  }) {
    final remaining = [...fields];
    bool isHp(UiPlanField f) {
      final t = '${f.name} ${f.sourceKey}'.toLowerCase();
      return t.contains('hp') || t.contains('生命') || t.contains('health');
    }

    bool isMp(UiPlanField f) {
      final t = '${f.name} ${f.sourceKey}'.toLowerCase();
      return t.contains('mp') || t.contains('法力') || t.contains('魔力') || t.contains('mana');
    }

    final hpIndex = remaining.indexWhere(isHp);
    final mpIndex = remaining.indexWhere(isMp);
    if (hpIndex >= 0 && mpIndex >= 0 && hpIndex != mpIndex) {
      final hp = remaining[hpIndex];
      final mp = remaining[mpIndex];
      const gap = 8.0;
      final cellW = (innerW - gap) / 2;
      _renderProgressCell(
        elements: elements,
        field: hp,
        nextId: nextId,
        statusFields: statusFields,
        theme: theme,
        x: _Layout.pcbPadding,
        y: y,
        w: cellW,
        compact: true,
      );
      _renderProgressCell(
        elements: elements,
        field: mp,
        nextId: nextId,
        statusFields: statusFields,
        theme: theme,
        x: _Layout.pcbPadding + cellW + gap,
        y: y,
        w: cellW,
        compact: true,
      );
      y += 38.0;
      if (hpIndex > mpIndex) {
        remaining.removeAt(hpIndex);
        remaining.removeAt(mpIndex);
      } else {
        remaining.removeAt(mpIndex);
        remaining.removeAt(hpIndex);
      }
    }

    for (final field in remaining) {
      if (field.isNumber && field.display == 'progress') {
        _renderProgressCell(
          elements: elements,
          field: field,
          nextId: nextId,
          statusFields: statusFields,
          theme: theme,
          x: _Layout.pcbPadding,
          y: y,
          w: innerW,
          compact: false,
        );
        y += 38.0;
      } else {
        y = _renderPlanFieldStandard(
          elements: elements,
          field: field,
          nextId: nextId,
          statusFields: statusFields,
          theme: theme,
          mode: mode,
          y: y,
          innerW: innerW,
          labelW: labelW,
        );
      }
    }
    return y + _Layout.rowGap;
  }

  static void _renderProgressCell({
    required List<Map<String, dynamic>> elements,
    required UiPlanField field,
    required String Function(String) nextId,
    required List<Map<String, dynamic>> statusFields,
    required UiVisualTheme theme,
    required double x,
    required double y,
    required double w,
    required bool compact,
  }) {
    final fieldId = _planFieldId(field);
    final min = field.min ?? 0.0;
    final max = field.max ?? 100.0;
    final initialNumber = _numberOf(field.initialValue) ?? min;
    final initial = _trimNumber(initialNumber);
    _addStatusFieldForPlanField(
      statusFields,
      field,
      fieldId: fieldId,
      initial: initial,
      min: min,
      max: max,
    );
    elements.add(_text(
      id: nextId('el'),
      name: '${field.name}标签',
      text: _progressLabelText(field.name, initial, max),
      x: x,
      y: y,
      w: w,
      h: 19,
      fontSize: compact ? 10 : 11.5,
      color: theme.labelColor,
      align: 'center',
      layer: elements.length + 1,
      overflow: 'wrap',
      richText: true,
    ));
    elements.add(_progress(
      id: nextId('el'),
      name: field.name,
      x: x,
      y: y + 21,
      w: w,
      h: _Layout.barHeight,
      statusFieldId: fieldId,
      layer: elements.length + 1,
      barFillColor: _barColorOf(field.name, theme.barFillColor),
      barTrackColor: _barTrackColorOf(field.name, theme.barTrackColor),
      min: min,
      max: max,
      current: initialNumber.clamp(min, max).toDouble(),
    ));
  }

  static double _frameInsetFor(String mode) {
    // 伴生面板宽度很窄，留 8px 就足以看出“PCB 外框 + 内层面板”层次。
    if (mode == 'extra_companion') return 8.0;
    if (mode == 'opening' || mode == 'scene' || mode == 'extra_sticky') {
      return 12.0;
    }
    return 8.0;
  }

  static bool _modeRequiresGeneratedKeyAction(String mode) =>
      mode == 'opening' || mode == 'scene' || mode == 'extra_sticky';

  static bool _shouldMarkKeyAction(String mode, UiPlanAction action) {
    if (action.keyAction) return true;
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

  static String _progressLabelText(String name, String current, double max) {
    final currentColor = _currentValueColorOf(name);
    final maxText = _trimNumber(max);
    if (currentColor == null) return '$name: $current/$maxText';
    final hex = currentColor.toRadixString(16).padLeft(8, '0').substring(2);
    return '<strong>$name:</strong> '
        '<span style="color:#$hex;font-weight:bold">$current</span> / $maxText';
  }

  static int? _currentValueColorOf(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('生命') || lower.contains('hp') || lower.contains('health')) {
      return 0xFFFF7F7F;
    }
    if (lower.contains('法力') || lower.contains('魔力') || lower.contains('mp') || lower.contains('mana')) {
      return 0xFF87CEFA;
    }
    if (lower.contains('经验') || lower.contains('xp') || lower.contains('exp')) {
      return 0xFFDAA520;
    }
    return null;
  }

  static bool _shouldScrollTextField(
    UiPlanField field,
    String value,
    String mode,
  ) {
    if (field.overflow == 'scroll') return true;
    final text = value.trim();
    if (text.contains('\n')) return true;
    final threshold = mode == 'extra_companion' ? 28 : 56;
    return text.runes.length > threshold;
  }

  static bool _needsWideTextLayout(UiPlanField field, String value, String mode) {
    if (mode == 'extra_companion') return false;
    if (field.overflow == 'wrap' || field.overflow == 'scroll') return true;
    final text = '${field.name} ${field.sourceKey} ${field.group} ${field.page}';
    const markers = [
      '物品',
      'items',
      '声望',
      '点数',
      '位置',
      '关系',
      '选项',
      '任务',
      '羁绊',
      '好友',
      '罪名',
      '称号',
      '当前',
      '状态效果',
      '说明',
    ];
    return markers.any(text.contains) || value.runes.length > 18 || field.name.runes.length > 10;
  }

  static int _softPanelColor(UiVisualTheme theme) {
    // 半透明底色在 JSON 里仍是 ARGB；运行时叠在 PCB/底板上，给任务板等
    // 长文本一个明确容器面，避免看起来像漂浮文字。
    return (theme.panelColor & 0x00FFFFFF) | 0xCC000000;
  }

  static int _innerScrollPanelColor(UiVisualTheme theme) {
    // 内层滚动面稍淡，保证能看出“外容器 + 内滚动区”的边界。
    return (theme.panelColor & 0x00FFFFFF) | 0x99000000;
  }

  static bool _isTaskBoardField(UiPlanField field) {
    final text = '${field.name} ${field.sourceKey} ${field.group} ${field.page}'.toLowerCase();
    return text.contains('quest') || text.contains('task') || text.contains('任务');
  }

  static double _scrollTextFontSizeFor(
    UiPlanField field,
    String value,
    String mode,
  ) {
    if (mode == 'extra_companion') return 10.5;
    if (_isTaskBoardField(field)) return value.runes.length > 240 ? 10.8 : 11.2;
    final text = '${field.name} ${field.sourceKey} ${field.group}'.toLowerCase();
    if (text.contains('friends') || text.contains('album') || text.contains('羁绊') || text.contains('好友')) {
      return 11.0;
    }
    return 11.5;
  }

  static double _scrollTextHeightFor(String value, String mode) {
    final len = value.runes.length;
    final base = mode == 'extra_companion' ? 76.0 : 96.0;
    if (len > 180) return mode == 'extra_companion' ? 120.0 : 160.0;
    if (len > 90) return mode == 'extra_companion' ? 96.0 : 128.0;
    return base;
  }

  static double _wrapTextHeightFor(String value, String mode) {
    final len = value.runes.length;
    final line = mode == 'extra_companion' ? 18.0 : 20.0;
    if (len > 42) return line * 3;
    if (len > 20) return line * 2;
    return _Layout.rowHeight;
  }

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
    String action = 'switch_base_page',
    String transition = 'base_slide',
    int durationMs = 200,
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
              'action': action,
              'transition': transition,
              'durationMs': durationMs,
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
    String overflow = 'ellipsis',
    bool richText = false,
    double? contentPadding,
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
            'richText': richText,
            if (contentPadding != null) 'contentPadding': contentPadding,
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

  static Map<String, dynamic> _sectionTitle({
    required String id,
    required String title,
    required double x,
    required double y,
    required double w,
    required int color,
    required int layer,
  }) =>
      _text(
        id: id,
        name: '分节_$title',
        text: title,
        x: x,
        y: y,
        w: w,
        h: 20,
        fontSize: 13,
        color: color,
        align: 'left',
        layer: layer,
        overflow: 'wrap',
      );

  static Map<String, dynamic> _line({
    required String id,
    required String name,
    required double x,
    required double y,
    required double w,
    required double h,
    required int color,
    required int layer,
    String axis = 'horizontal',
    String style = 'solid',
    double thickness = 1.0,
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
          type: 'line',
          color: color,
          props: {
            'axis': axis,
            'lineStyle': style,
            'thickness': thickness,
          },
        ),
      );

  static Map<String, dynamic> _messageFlow({
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
          type: 'message_flow',
          color: color,
          radius: radius,
          props: {
            'historyLimit': 0,
            'showUser': true,
            'showAssistant': true,
            'richText': true,
            'fontSize': 12.5,
            'userBubbleColor': 0xFFDCF8C6,
            'assistantBubbleColor': 0xFFF1F1F4,
            'bubbleRadius': 12.0,
          },
        ),
      );

  static Map<String, dynamic> _input({
    required String id,
    required String name,
    required String placeholder,
    String initialValue = '',
    Map<String, dynamic>? dataChannel,
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
            'text': initialValue,
            'value': initialValue,
            'committedValue': initialValue,
            'visualMode': 'filled',
            'multiline': false,
            if (sendsMessage) 'sendsMessage': true,
            if (dataChannel != null) 'dataChannel': dataChannel,
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

  static Map<String, dynamic> _inputStatusChannel({
    required String label,
    required String elementId,
    required String statusFieldId,
  }) =>
      _channel(
        label: label,
        elementId: elementId,
        port: 'committedValue',
        statusFieldId: statusFieldId,
        fieldType: 'text',
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
    if (lower.contains('体力') || lower.contains('体能') || lower.contains('stamina') || lower.contains('energy')) return '⚡ $name';
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
    if (lower.contains('生命') || lower.contains('血') || lower.contains('hp') || lower.contains('health')) return 0xFFDC143C; // 原卡 HP 红
    if (lower.contains('法力') || lower.contains('魔力') || lower.contains('mp') || lower.contains('mana')) return 0xFF1E90FF; // 原卡 MP 蓝
    if (lower.contains('经验') || lower.contains('xp') || lower.contains('exp')) return 0xFFDAA520; // 原卡 XP 金
    if (lower.contains('精神') || lower.contains('理智') || lower.contains('san') || lower.contains('mental')) return 0xFFD2A8FF; // 紫色
    if (lower.contains('体力') || lower.contains('精力') || lower.contains('stamina') || lower.contains('energy')) return 0xFF7EE787; // 绿色
    if (lower.contains('饱腹') || lower.contains('饥饿') || lower.contains('food') || lower.contains('hunger')) return 0xFFF2CC60; // 黄色
    return fallback;
  }

  static int _barTrackColorOf(String name, int fallback) {
    final lower = name.toLowerCase();
    if (lower.contains('生命') || lower.contains('血') || lower.contains('hp') || lower.contains('health')) return 0xFF581818;
    if (lower.contains('法力') || lower.contains('魔力') || lower.contains('mp') || lower.contains('mana')) return 0xFF183E58;
    if (lower.contains('经验') || lower.contains('xp') || lower.contains('exp')) return 0xFF4F3A1B;
    if (lower.contains('精神') || lower.contains('理智') || lower.contains('san') || lower.contains('mental')) return 0xFF2B163D;
    if (lower.contains('体力') || lower.contains('精力') || lower.contains('stamina') || lower.contains('energy')) return 0xFF14351C;
    if (lower.contains('饱腹') || lower.contains('饥饿') || lower.contains('food') || lower.contains('hunger')) return 0xFF4A3610;
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
