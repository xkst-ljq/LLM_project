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
class _Palette {
  static const int pcb = 0xFF15161A;
  static const int panel = 0xFF1E2027;
  static const int title = 0xFFFFFFFF;
  static const int label = 0xFFAAB0BC; // 对 panel 约 7.4:1
  static const int value = 0xFFE8EDF5;
  static const int barTrack = 0xFF2A2D36;
  static const int barFill = 0xFF4FA3D1;
  static const int accent = 0xFF4FA3D1;
  static const int buttonBg = 0xFF2A3340;
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

  static BuiltAssembly build(UiExtraction ex, {String cardName = ''}) {
    final notes = <String>[];

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
    final primary = _pickPrimary(usable);
    if (primary != null) {
      final skipped = usable.length - 1;
      if (skipped > 0) {
        notes.add('原卡有 ${usable.length} 条 UI 脚本，'
            '取字段最多的「${primary.scriptName}」生成主面板'
            '（其余多为同内容的换肤版本）。');
      }
      final r = _buildStatusPanel(primary, nextId, cardName);
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
      final json = _buildOpeningPage(ex.openingActions, nextId, cardName);
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
  static UiRegexScript? _pickPrimary(List<UiRegexScript> scripts) {
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

    // 标题
    elements.add(_text(
      id: nextId('el'),
      name: '标题',
      text: cardName.isEmpty ? '状态' : cardName,
      x: _Layout.pcbPadding,
      y: y,
      w: innerW,
      h: _Layout.titleHeight,
      fontSize: 15,
      color: _Palette.title,
      align: 'left',
      layer: elements.length + 1,
    ));
    y += _Layout.titleHeight + _Layout.sectionGap;

    // 数值字段：标签 + 进度条
    for (final f in numeric) {
      final fieldId = 'sf_${_slug(f.name)}';
      elements.add(_text(
        id: nextId('el'),
        name: '${f.name}标签',
        text: f.name,
        x: _Layout.pcbPadding,
        y: y,
        w: _Layout.labelWidth,
        h: _Layout.rowHeight,
        fontSize: 11,
        color: _Palette.label,
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
      ));
      statusFields.add({
        'id': fieldId,
        'name': f.name,
        'type': 'number',
        'initial_value': '0',
        'min_value': 0.0,
        'max_value': 100.0,
        'pin_side': 'none',
        'order': statusFields.length,
        'owner': 'player',
      });
      y += _Layout.rowHeight + _Layout.rowGap;
    }

    if (numeric.isNotEmpty && textual.isNotEmpty) {
      y += _Layout.sectionGap - _Layout.rowGap;
    }

    // 文本字段：标签 + 值
    for (final f in textual) {
      final fieldId = 'sf_${_slug(f.name)}';
      elements.add(_text(
        id: nextId('el'),
        name: '${f.name}标签',
        text: f.name,
        x: _Layout.pcbPadding,
        y: y,
        w: _Layout.labelWidth,
        h: _Layout.rowHeight,
        fontSize: 11,
        color: _Palette.label,
        align: 'left',
        layer: elements.length + 1,
      ));
      elements.add(_text(
        id: nextId('el'),
        name: f.name,
        text: '—',
        x: _Layout.pcbPadding + _Layout.labelWidth + 6,
        y: y,
        w: innerW - _Layout.labelWidth - 6,
        h: _Layout.rowHeight,
        fontSize: 12,
        color: _Palette.value,
        align: 'left',
        layer: elements.length + 1,
        statusFieldId: fieldId,
      ));
      statusFields.add({
        'id': fieldId,
        'name': f.name,
        'type': 'text',
        'initial_value': '',
        'pin_side': 'none',
        'order': statusFields.length,
        'owner': 'player',
      });
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
      color: _Palette.panel,
      layer: 0,
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
      color: _Palette.title,
      align: 'center',
      layer: 1,
    ));
    y += 28 + 12;

    for (var i = 0; i < actions.length; i++) {
      final label = actions[i];
      elements.add(_surface(
        id: nextId('el'),
        name: '选项底${i + 1}',
        x: padding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        color: _Palette.buttonBg,
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
        color: _Palette.value,
        align: 'left',
        layer: elements.length + 1,
      ));
      // button 是不显形的热区，盖在底板与文字之上。
      //
      // 第一个按钮标 keyAction：opening 缺这个标记会
      // **整层不渲染**（UISemanticRole.blocksWithoutKeyAction）。
      elements.add(_button(
        id: nextId('el'),
        name: '选项${i + 1}',
        x: padding,
        y: y,
        w: innerW,
        h: _Layout.buttonHeight,
        layer: elements.length + 1,
        sendsMessage: true,
        keyAction: i == 0,
        message: label,
      ));
      y += _Layout.buttonHeight + 8;
    }

    final pcbH = (y + padding).clamp(64.0, 2000.0).toDouble();
    final bg = _surface(
      id: nextId('el'),
      name: '底板',
      x: 0,
      y: 0,
      w: pcbW,
      h: pcbH,
      color: _Palette.pcb,
      layer: 0,
    );

    return _assembly(
      id: nextId('asm'),
      name: '开场选择',
      mode: 'opening',
      pcbW: pcbW,
      pcbH: pcbH,
      pageName: '开场',
      elements: [bg, ...elements],
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
          color: _Palette.barFill,
          shape: 2, // capsule
          radius: h / 2,
          props: {
            'min': 0.0,
            'max': 100.0,
            'current': 0.0,
            'progressShape': 'capsule',
            'trackColor': _Palette.barTrack,
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
    String message = '',
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
          type: 'button',
          color: _Palette.accent,
          props: {
            if (sendsMessage) 'sendsMessage': true,
            if (keyAction) 'keyAction': true,
            if (message.isNotEmpty) 'messageText': message,
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
  /// **三层嵌套在这里收口**：`elements` 与 `pages` 必须是 JSON 字符串。
  /// `createdAt` 必须是毫秒时间戳（写 ISO 字符串会直接抛异常）。
  static String _assembly({
    required String id,
    required String name,
    required String mode,
    required double pcbW,
    required double pcbH,
    required String pageName,
    required List<Map<String, dynamic>> elements,
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
      'pcbColorValue': _Palette.pcb,
      'pcbRadius': 14.0,
      'pcbRounded': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─────────────────────── 工具 ───────────────────────

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
