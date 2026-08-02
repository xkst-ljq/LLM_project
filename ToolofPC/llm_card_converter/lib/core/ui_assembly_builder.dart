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

/// 构建时的布局常量。
///
/// 单独抽出来是因为它们会被多处引用，散落在代码里改一处漏一处。
class _Layout {
  static const double pcbPadding = 12;
  static const double rowHeight = 22;
  static const double rowGap = 6;
  static const double labelWidth = 72;
  static const double barHeight = 10;
  static const double titleHeight = 26;
  static const double sectionGap = 10;
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
  ) {
    final notes = <String>[];

    // 「正文」这类整段叙事不适合塞进状态面板——
    // 它是消息正文本身，不是状态。
    final fields = script.fields
        .where((f) => !_isNarrativeField(f.name))
        .toList();
    if (fields.isEmpty) return null;

    var used = fields;
    if (used.length > _Layout.maxFields) {
      used = used.sublist(0, _Layout.maxFields);
      notes.add('字段过多（${fields.length} 个），'
          '取前 ${_Layout.maxFields} 个以免面板过高。');
    }

    final numeric = used.where((f) => f.isNumeric).toList();
    final textual = used.where((f) => !f.isNumeric).toList();

    // ── 算高度 ──
    var y = _Layout.pcbPadding;
    final elements = <Map<String, dynamic>>[];
    final statusFields = <Map<String, dynamic>>[];

    const pcbW = 300.0;
    final innerW = pcbW - _Layout.pcbPadding * 2;

    // 标题（右侧留出折叠按钮的位置）
    const collapseSize = 26.0;
    elements.add(_text(
      id: nextId('el'),
      name: '标题',
      text: cardName.isEmpty ? '状态' : cardName,
      x: _Layout.pcbPadding,
      y: y,
      w: innerW - collapseSize - 6,
      h: _Layout.titleHeight,
      fontSize: 15,
      color: theme.titleColor,
      align: 'left',
      layer: elements.length + 1,
    ));

    // 折叠按钮。
    //
    // `extra_sticky` 缺 keyAction 标记不会导致整层不渲染
    // （那是 opening / scene 的规则，见 UISemanticRole.blocksWithoutKeyAction），
    // 但**玩家就没法收起这条常驻栏**——它会一直占着消息流顶部。
    // 引擎给这个 mode 的关键职责定义就是「折叠界面」。
    elements.add(_text(
      id: nextId('el'),
      name: '折叠图标',
      text: '▾',
      x: pcbW - _Layout.pcbPadding - collapseSize,
      y: y,
      w: collapseSize,
      h: _Layout.titleHeight,
      fontSize: 14,
      color: theme.labelColor,
      align: 'center',
      layer: elements.length + 1,
    ));
    elements.add(_button(
      id: nextId('el'),
      name: '折叠',
      x: pcbW - _Layout.pcbPadding - collapseSize,
      y: y,
      w: collapseSize,
      h: _Layout.titleHeight,
      layer: elements.length + 1,
      sendsMessage: false,
      keyAction: true,
      color: theme.accentColor,
    ));
    y += _Layout.titleHeight + _Layout.sectionGap;

    // 数值字段：标签 + 进度条
    //
    // 但要先筛一道：量程超出 0~100 的（如「点数 200万」）
    // 用进度条表达会永远满格，退回文本更诚实。
    final barFields = <UiField>[];
    final overflowFields = <UiField>[];
    for (final f in numeric) {
      if (_fitsPercentBar(_presetsOf(branchPresets, f.name, numeric: true))) {
        barFields.add(f);
      } else {
        overflowFields.add(f);
      }
    }
    if (overflowFields.isNotEmpty) {
      notes.add('${overflowFields.map((f) => f.name).join('、')} '
          '的取值超出 0~100，改用文本显示（进度条会永远满格）。');
    }
    final textual2 = [...textual, ...overflowFields];

    for (final f in barFields) {
      final fieldId = 'sf_${_slug(f.name)}';
      elements.add(_text(
        id: nextId('el'),
        name: '${f.name}标签',
        text: _decorateEmoji(f.name),
        x: _Layout.pcbPadding,
        y: y,
        w: _Layout.labelWidth,
        h: _Layout.rowHeight,
        fontSize: 11,
        color: theme.labelColor,
        align: 'left',
        layer: elements.length + 1,
      ));
      elements.add(_progress(
        id: nextId('el'),
        name: f.name,
        x: _Layout.pcbPadding + _Layout.labelWidth + 6,
        y: y + (_Layout.rowHeight - _Layout.barHeight) / 2,
        w: innerW - _Layout.labelWidth - 6,
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
        // 主支路（分支 0）的值就是这个字段的默认初值。
        'initial_value': numPresets['0'] ?? '0',
        'min_value': 0.0,
        'max_value': 100.0,
        'pin_side': 'none',
        'order': statusFields.length,
        'owner': 'player',
        if (numPresets.length > 1) 'branch_initial_values': numPresets,
      });
      y += _Layout.rowHeight + _Layout.rowGap;
    }

    if (barFields.isNotEmpty && textual2.isNotEmpty) {
      y += _Layout.rowGap;
      elements.add(_line(
        id: nextId('el'),
        name: '分割线',
        x: _Layout.pcbPadding,
        y: y,
        w: innerW,
        h: 2.0,
        color: (theme.labelColor & 0x00FFFFFF) | 0x26000000, // 15% 透明度
        layer: elements.length + 1,
        thickness: 1.0,
      ));
      y += 8.0;
    }

    // 文本字段：双列并排流式布局，使面板大幅紧凑美观
    for (var i = 0; i < textual2.length; i += 2) {
      final f1 = textual2[i];
      final hasF2 = i + 1 < textual2.length;
      final f2 = hasF2 ? textual2[i + 1] : null;

      final colW = innerW / 2 - 4;
      final colLabelW = 46.0;

      // 列 1
      final fieldId1 = 'sf_${_slug(f1.name)}';
      elements.add(_text(
        id: nextId('el'),
        name: '${f1.name}标签',
        text: _decorateEmoji(f1.name),
        x: _Layout.pcbPadding,
        y: y,
        w: colLabelW,
        h: _Layout.rowHeight,
        fontSize: 10,
        color: theme.labelColor,
        align: 'left',
        layer: elements.length + 1,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: f1.name,
        text: '—',
        x: _Layout.pcbPadding + colLabelW + 4,
        y: y,
        w: colW - colLabelW - 4,
        h: _Layout.rowHeight,
        fontSize: 11,
        color: theme.valueColor,
        align: 'left',
        layer: elements.length + 1,
        statusFieldId: fieldId1,
      ));
      final txtPresets1 = _presetsOf(branchPresets, f1.name, numeric: false);
      statusFields.add({
        'id': fieldId1,
        'name': f1.name,
        'type': 'text',
        'initial_value': txtPresets1['0'] ?? '',
        'pin_side': 'none',
        'order': statusFields.length,
        'owner': 'player',
        if (txtPresets1.length > 1) 'branch_initial_values': txtPresets1,
      });

      // 列 2
      if (f2 != null) {
        final fieldId2 = 'sf_${_slug(f2.name)}';
        final col2X = _Layout.pcbPadding + innerW / 2 + 4;
        elements.add(_text(
          id: nextId('el'),
          name: '${f2.name}标签',
          text: _decorateEmoji(f2.name),
          x: col2X,
          y: y,
          w: colLabelW,
          h: _Layout.rowHeight,
          fontSize: 10,
          color: theme.labelColor,
          align: 'left',
          layer: elements.length + 1,
        ));
        elements.add(_text(
          id: nextId('el'),
          name: f2.name,
          text: '—',
          x: col2X + colLabelW + 4,
          y: y,
          w: colW - colLabelW - 4,
          h: _Layout.rowHeight,
          fontSize: 11,
          color: theme.valueColor,
          align: 'left',
          layer: elements.length + 1,
          statusFieldId: fieldId2,
        ));
        final txtPresets2 = _presetsOf(branchPresets, f2.name, numeric: false);
        statusFields.add({
          'id': fieldId2,
          'name': f2.name,
          'type': 'text',
          'initial_value': txtPresets2['0'] ?? '',
          'pin_side': 'none',
          'order': statusFields.length,
          'owner': 'player',
          if (txtPresets2.length > 1) 'branch_initial_values': txtPresets2,
        });
      }
      y += _Layout.rowHeight + _Layout.rowGap;
    }

    final pcbH = (y + _Layout.pcbPadding).clamp(64.0, 2000.0).toDouble();

    // 底板放最底层（layerIndex 0），其余依次向上。
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

    // extra_sticky：常驻条，跟着消息流顶部显示。
    // 选它而非 extra_companion 的理由：字段较多时塞进气泡会很挤，
    // 而且状态是"持续的"，不该随某条消息滚走。
    return _PanelResult(
      assemblyJson: _assembly(
        id: nextId('asm'),
        name: '${cardName.isEmpty ? "角色" : cardName}状态栏',
        mode: 'extra_sticky',
        pcbW: pcbW,
        pcbH: pcbH,
        pageName: '状态',
        elements: [bg, ...elements],
        pcbColor: theme.pcbColor,
        pcbRadius: theme.borderRadius,
      ),
      statusFields: statusFields,
      notes: notes,
    );
  }

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

    for (var i = 0; i < actions.length; i++) {
      final label = actions[i];
      final surfaceId = nextId('el');
      elements.add(_surface(
        id: surfaceId,
        name: '选项底${i + 1}',
        x: padding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        color: theme.buttonBgColor,
        layer: elements.length + 1,
        radius: 8,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: '选项文${i + 1}',
        text: label,
        x: padding + 10,
        y: y + 8,
        w: innerW - 20,
        h: 18,
        fontSize: 12,
        color: theme.valueColor,
        align: 'left',
        layer: elements.length + 1,
      ));
      // button 是不显形的热区，盖在底板与文字之上。
      //
      // **每个选项都标 keyAction**：各开场之间是平级分支，
      // 点哪个就用哪个开局，不存在「第一个特殊、其余普通」。
      // （opening 缺 keyAction 会整层不渲染，这里天然满足。）
      final buttonId = nextId('el');
      elements.add(_button(
        id: buttonId,
        name: '选项${i + 1}',
        x: padding,
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

    return _assembly(
      id: nextId('asm'),
      name: '开场选择',
      mode: 'opening',
      pcbW: pcbW,
      pcbH: pcbH,
      pageName: '开场',
      elements: [bg, ...elements],
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

  static Map<String, dynamic> _line({
    required String id,
    required String name,
    required double x,
    required double y,
    required double w,
    required double h,
    required int color,
    required int layer,
    double thickness = 1.0,
    String lineStyle = 'solid',
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
            'thickness': thickness,
            'lineStyle': lineStyle,
            'axis': 'horizontal',
          },
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
            'min': 0.0,
            'max': 100.0,
            'current': 0.0,
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
      if (message.isNotEmpty) 'messageText': message,
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
    required String pageName,
    required List<Map<String, dynamic>> elements,
    required int pcbColor,
    required double pcbRadius,
  }) {
    final page = {
      'id': 'page_$id',
      'name': pageName,
      'type': 'base',
      'parentPageId': null,
      'sortOrder': 0,
      'elements': elements,
      'gestures': <dynamic>[],
      'propertyOverrides': <dynamic>[],
    };
    return jsonEncode({
      'id': id,
      'name': name,
      'mode': mode,
      'elements': '[]',
      'pages': jsonEncode([page]),
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
