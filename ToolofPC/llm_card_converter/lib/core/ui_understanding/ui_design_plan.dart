/// AI UI 理解阶段输出的中间格式。
///
/// 这是 AI 可以安全输出的“设计计划书”，不是 UIEngine 内部 assembly JSON。
class UiDesignPlan {
  final bool hasUi;
  final double confidence;
  final String uiMode;
  final String uiName;
  final String evidenceSummary;
  final List<String> sourceRefs;
  final UiPlanStyle visualStyle;
  final UiPlanLayout layout;
  final List<UiPlanField> fields;
  final List<UiPlanInput> inputs;
  final List<UiPlanAction> actions;
  final List<UiPlanUnsupported> unsupported;
  final List<String> notes;

  const UiDesignPlan({
    required this.hasUi,
    required this.confidence,
    required this.uiMode,
    required this.uiName,
    required this.evidenceSummary,
    required this.sourceRefs,
    required this.visualStyle,
    required this.layout,
    required this.fields,
    required this.inputs,
    required this.actions,
    required this.unsupported,
    required this.notes,
  });

  static List<UiDesignPlan> listFromJson(Map<String, dynamic> json) {
    final rawAssemblies = json['assemblies'];
    if (rawAssemblies is List) {
      final out = <UiDesignPlan>[];
      for (final item in rawAssemblies) {
        if (item is! Map) continue;
        final child = Map<String, dynamic>.from(item);
        child.putIfAbsent('hasUi', () => json['hasUi'] ?? true);
        child.putIfAbsent('confidence', () => json['confidence']);
        child.putIfAbsent('evidenceSummary', () => json['evidenceSummary']);
        child.putIfAbsent('sourceRefs', () => json['sourceRefs']);
        child.putIfAbsent('visualStyle', () => json['visualStyle'] ?? json['style']);
        child.putIfAbsent('style', () => json['style'] ?? json['visualStyle']);
        child.putIfAbsent('unsupported', () => const <dynamic>[]);
        child.putIfAbsent('notes', () => const <dynamic>[]);
        final mode = _modeOf(child['uiMode']);
        child.putIfAbsent('uiName', () => _defaultNameForMode(mode));
        out.add(UiDesignPlan.fromJson(child));
      }
      if (out.isNotEmpty) return out;
    }
    return [UiDesignPlan.fromJson(json)];
  }

  factory UiDesignPlan.fromJson(Map<String, dynamic> json) {
    final layout = UiPlanLayout.fromJson(_mapOf(json['layout']));

    final fields = <UiPlanField>[];
    final inputs = <UiPlanInput>[];
    final actions = <UiPlanAction>[];

    fields.addAll(_listOf(json['fields']).map(UiPlanField.fromJson));
    inputs.addAll(_listOf(json['inputs']).map(UiPlanInput.fromJson));
    actions.addAll(_listOf(json['actions']).map(UiPlanAction.fromJson));

    // 兼容 AI 输出 nested pages: pages[].fields / pages[].actions。
    for (final page in _listOf(json['pages'])) {
      final title = _str(page['title']).trim();
      for (final f in _listOf(page['fields'])) {
        final m = Map<String, dynamic>.from(f);
        m.putIfAbsent('page', () => title);
        fields.add(UiPlanField.fromJson(m));
      }
      for (final input in _listOf(page['inputs'])) {
        final m = Map<String, dynamic>.from(input);
        m.putIfAbsent('page', () => title);
        inputs.add(UiPlanInput.fromJson(m));
      }
      for (final a in _listOf(page['actions'])) {
        final m = Map<String, dynamic>.from(a);
        m.putIfAbsent('page', () => title);
        actions.add(UiPlanAction.fromJson(m));
      }
    }

    return UiDesignPlan(
      hasUi: _boolOf(json['hasUi']),
      confidence: _doubleOf(json['confidence'], 0.0).clamp(0.0, 1.0).toDouble(),
      uiMode: _modeOf(json['uiMode']),
      uiName: _fallback(_str(json['uiName']), 'AI 转译 UI'),
      evidenceSummary: _str(json['evidenceSummary']),
      sourceRefs: _strings(json['sourceRefs']),
      visualStyle: UiPlanStyle.fromJson(_mapOf(json['visualStyle'] ?? json['style'])),
      layout: layout,
      fields: fields,
      inputs: inputs,
      actions: actions,
      unsupported:
          _listOf(json['unsupported']).map(UiPlanUnsupported.fromJson).toList(),
      notes: _strings(json['notes']),
    );
  }

  static String _defaultNameForMode(String mode) => switch (mode) {
        'opening' => '开场选择',
        'scene' => '场景终端',
        'extra_sticky' => '常驻 UI',
        'extra_companion' => '伴生状态栏',
        _ => 'AI 转译 UI',
      };

  static String _modeOf(dynamic raw) {
    final v = _str(raw).trim();
    switch (v) {
      case 'opening':
      case 'scene':
      case 'extra_sticky':
      case 'extra_companion':
        return v;
      case 'companion':
      case 'status':
      case 'status_bar':
      case 'dashboard':
        return 'extra_companion';
      case 'sticky':
        return 'extra_sticky';
      default:
        return 'extra_companion';
    }
  }
}

class UiPlanStyle {
  final String styleName;
  final String pcbColor;
  final String panelColor;
  final String titleColor;
  final String labelColor;
  final String valueColor;
  final String accentColor;
  final String buttonBgColor;
  final String barFillColor;
  final String barTrackColor;
  final double borderRadius;
  final bool glow;

  const UiPlanStyle({
    required this.styleName,
    required this.pcbColor,
    required this.panelColor,
    required this.titleColor,
    required this.labelColor,
    required this.valueColor,
    required this.accentColor,
    required this.buttonBgColor,
    required this.barFillColor,
    required this.barTrackColor,
    required this.borderRadius,
    required this.glow,
  });

  factory UiPlanStyle.fromJson(Map<String, dynamic> json) {
    return UiPlanStyle(
      styleName: _fallback(_str(json['styleName']), 'dark terminal'),
      pcbColor: _hex(json['pcbColor'], '#15161A'),
      panelColor: _hex(json['panelColor'], '#1E2027'),
      titleColor: _hex(json['titleColor'], '#FFFFFF'),
      labelColor: _hex(json['labelColor'], '#AAB0BC'),
      valueColor: _hex(json['valueColor'], '#E8EDF5'),
      accentColor: _hex(json['accentColor'], '#4FA3D1'),
      buttonBgColor: _hex(json['buttonBgColor'], '#2A3340'),
      barFillColor: _hex(json['barFillColor'], '#4FA3D1'),
      barTrackColor: _hex(json['barTrackColor'], '#2A2D36'),
      borderRadius: _doubleOf(json['borderRadius'], 14.0).clamp(0.0, 32.0).toDouble(),
      glow: _boolOf(json['glow']),
    );
  }
}

class UiPlanLayout {
  final String kind;
  final String navigation;

  /// 页面默认列数（AI 可表达「两列属性网格」等意图）。
  ///
  /// 编译为每页的默认网格列数；字段级 [UiPlanField.span] 可在此基础上加宽。
  /// 1 = 单列（标准行），2 = 两列网格，3 = 三列紧凑网格。
  /// 未提供时由编译器按字段数量启发式决定。
  final int columns;

  final List<UiPlanPageSpec> pages;

  const UiPlanLayout({
    required this.kind,
    required this.navigation,
    this.columns = 0,
    required this.pages,
  });

  factory UiPlanLayout.fromJson(Map<String, dynamic> json) {
    return UiPlanLayout(
      kind: _fallback(_str(json['kind']), 'tabbed_companion_panel'),
      navigation: _navigationOf(json['navigation']),
      columns: _positiveIntOf(json['columns']),
      pages: _listOf(json['pages']).map(UiPlanPageSpec.fromJson).toList(),
    );
  }
}

class UiPlanPageSpec {
  final String title;
  final String role;

  /// 页面类型。
  ///
  /// - `base`: 平级主页面 / tab / swipe 页面；
  /// - `overlay`: 叠加页，运行时覆盖在父 base 页面上，适合任务详情、档案、羁绊名录。
  final String type;

  /// overlay 的父页面标题。AI 可以用 parentPage / parent / parentPageId。
  /// 如果留空，编译器会回退到第一个 base 页面。
  final String parentPage;

  /// 页面级列数覆写。0 = 未指定，跟随 layout.columns / 编译器启发式。
  final int columns;

  /// 页面密度：'compact' | 'normal' | 'spacious'。
  /// 未指定时编译器按字段数量启发式决定。
  final String density;

  /// 是否尽量占满 PCB 高度（避免底部大片空白）。
  /// 未指定时编译器会尽量拉伸 scroll / message_flow 占满。
  final bool fill;

  const UiPlanPageSpec({
    required this.title,
    required this.role,
    required this.type,
    required this.parentPage,
    this.columns = 0,
    this.density = '',
    this.fill = false,
  });

  factory UiPlanPageSpec.fromJson(Map<String, dynamic> json) {
    return UiPlanPageSpec(
      title: _fallback(_str(json['title']), '页面'),
      role: _str(json['role']),
      type: _pageTypeOf(json['type'] ?? json['presentation'] ?? json['pageType']),
      parentPage: _str(json['parentPage'] ?? json['parent'] ?? json['parentPageId']).trim(),
      columns: _positiveIntOf(json['columns'] ?? json['cols']),
      density: _densityOf(json['density']),
      fill: _boolOf(json['fill']),
    );
  }
}

class UiPlanField {
  final String name;
  final String sourceKey;
  final String group;
  final String type;
  final String display;
  final String textAlign;
  final String overflow;
  final String initialValue;
  final Map<String, String> branchInitialValues;
  final double? min;
  final double? max;
  final String owner;
  final String page;
  final String sourceRef;

  /// 网格跨度：1 = 占 1 列，2 = 占满整行。仅列数 > 1 时生效。
  /// 未指定时按内容（长文本 → 占满）启发式决定。
  final int span;

  /// 字段布局意图：'' | 'standard' | 'grid' | 'progress' | 'badge'。
  /// '' = 让编译器按类型/分组启发式决定。
  final String layout;

  const UiPlanField({
    required this.name,
    required this.sourceKey,
    required this.group,
    required this.type,
    required this.display,
    required this.textAlign,
    required this.overflow,
    required this.initialValue,
    required this.branchInitialValues,
    required this.min,
    required this.max,
    required this.owner,
    required this.page,
    required this.sourceRef,
    this.span = 0,
    this.layout = '',
  });

  factory UiPlanField.fromJson(Map<String, dynamic> json) {
    final type = _fieldTypeOf(json['type']);
    return UiPlanField(
      name: _str(json['name']).trim(),
      sourceKey: _str(json['sourceKey'] ?? json['key']).trim(),
      group: _str(json['group'] ?? json['section']).trim(),
      type: type,
      display: _displayOf(json['display'], type),
      textAlign: _textAlignOf(json['textAlign'] ?? json['align']),
      overflow: _overflowOf(json['overflow']),
      initialValue: _str(json['initialValue'] ?? json['initial_value']).trim(),
      branchInitialValues: _stringMapOf(
        json['branchInitialValues'] ?? json['branch_initial_values'],
      ),
      min: _nullableDouble(json['min']),
      max: _nullableDouble(json['max']),
      owner: _ownerOf(json['owner']),
      page: _str(json['page']).trim(),
      sourceRef: _str(json['sourceRef']).trim(),
      span: _positiveIntOf(json['span']),
      layout: _fieldLayoutOf(json['layout']),
    );
  }

  bool get isNumber => type == 'number';
}

String _fieldLayoutOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  const allowed = {'standard', 'grid', 'progress', 'badge'};
  return allowed.contains(v) ? v : '';
}

class UiPlanInput {
  final String name;
  final String sourceKey;
  final String placeholder;
  final String initialValue;
  final bool sendOnSubmit;

  /// 输入值写入哪里。
  ///
  /// - `status_field`: 生成一个状态字段并用 dataChannel 绑定，适合 opening 的
  ///   多个“玩家设定词条”；
  /// - `session_var`: 写入会话变量；
  /// - `user_profile`: 写入用户档案（仅昵称/详情两类，多个字段不建议用）；
  /// - `none`: 只作为发送框 / 本地输入框。
  final String targetKind;
  final String page;
  final String sourceRef;

  const UiPlanInput({
    required this.name,
    required this.sourceKey,
    required this.placeholder,
    required this.initialValue,
    required this.sendOnSubmit,
    required this.targetKind,
    required this.page,
    required this.sourceRef,
  });

  factory UiPlanInput.fromJson(Map<String, dynamic> json) {
    final placeholder =
        _fallback(_str(json['placeholder'] ?? json['inputPrompt']), '输入你的决定...');
    final name = _fallback(_str(json['name'] ?? json['label']), placeholder);
    return UiPlanInput(
      name: name,
      sourceKey: _str(json['sourceKey'] ?? json['key']).trim(),
      placeholder: placeholder,
      initialValue: _str(json['initialValue'] ?? json['initial_value']).trim(),
      sendOnSubmit: _boolOf(json['sendOnSubmit'] ?? json['sendsMessage']),
      targetKind: _inputTargetKindOf(json['targetKind']),
      page: _str(json['page']).trim(),
      sourceRef: _str(json['sourceRef']).trim(),
    );
  }
}

class UiPlanAction {
  final String label;
  final String sendText;
  final bool keyAction;
  final int? branchIndex;
  final String page;
  final String sourceRef;

  const UiPlanAction({
    required this.label,
    required this.sendText,
    this.keyAction = false,
    required this.branchIndex,
    required this.page,
    required this.sourceRef,
  });

  factory UiPlanAction.fromJson(Map<String, dynamic> json) {
    return UiPlanAction(
      label: _str(json['label']).trim(),
      sendText: _str(json['sendText'] ?? json['message'] ?? json['text']).trim(),
      keyAction: _boolOf(json['keyAction']),
      branchIndex: _intOf(json['branchIndex']),
      page: _str(json['page']).trim(),
      sourceRef: _str(json['sourceRef']).trim(),
    );
  }
}

class UiPlanUnsupported {
  final String kind;
  final String reason;
  final String sourceRef;

  const UiPlanUnsupported({
    required this.kind,
    required this.reason,
    required this.sourceRef,
  });

  factory UiPlanUnsupported.fromJson(Map<String, dynamic> json) {
    return UiPlanUnsupported(
      kind: _str(json['kind']),
      reason: _str(json['reason']),
      sourceRef: _str(json['sourceRef']),
    );
  }
}

// ───────────────────────── JSON helpers ─────────────────────────

String _str(dynamic v) => (v ?? '').toString();

String _fallback(String v, String fallback) => v.trim().isEmpty ? fallback : v.trim();

List<String> _strings(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = _str(raw).trim();
  return s.isEmpty ? const [] : [s];
}

Map<String, dynamic> _mapOf(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _listOf(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Map<String, String> _stringMapOf(dynamic raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((key, value) {
    final k = key.toString().trim();
    final v = value?.toString().trim() ?? '';
    if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
  });
  return out;
}

double _doubleOf(dynamic v, double fallback) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double? _nullableDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _intOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 解析正整数（列数 / 跨度）。0 / 非法返回 0（表示未指定）。
int _positiveIntOf(dynamic v) {
  final n = _intOf(v);
  if (n == null || n <= 0) return 0;
  return n > 6 ? 6 : n; // 列数上限 6，防止 AI 输出荒谬值撑爆布局
}

String _densityOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  const allowed = {'compact', 'normal', 'spacious'};
  return allowed.contains(v) ? v : '';
}

String _hex(dynamic raw, String fallback) {
  var s = _str(raw).trim();
  if (s.isEmpty) return fallback;
  if (!s.startsWith('#')) s = '#$s';
  final body = s.substring(1);
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(body)) return '#${body.toUpperCase()}';
  if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(body)) {
    return '#${body.substring(2).toUpperCase()}';
  }
  return fallback;
}

String _fieldTypeOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'text' || v == 'string') return 'text';
  if (v == 'bool' || v == 'boolean') return 'bool';
  return 'number';
}

String _navigationOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'swipe' || v == 'gesture' || v == 'gestures') return 'swipe';
  if (v == 'tabs' || v == 'tab') return 'tabs';
  if (v == 'tabs_and_swipe' || v == 'tab_and_swipe' || v == 'both') {
    return 'tabs_and_swipe';
  }
  return 'tabs_and_swipe';
}

String _pageTypeOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'overlay' || v == 'dialog' || v == 'modal' || v == 'popup' || v == '叠加页') {
    return 'overlay';
  }
  return 'base';
}

String _displayOf(dynamic raw, String type) {
  final v = _str(raw).toLowerCase().trim();
  const allowed = {'progress', 'text', 'badge'};
  if (allowed.contains(v)) return v;
  return type == 'number' ? 'progress' : 'text';
}

String _textAlignOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'left' || v == 'center' || v == 'right') return v;
  return 'left';
}

String _overflowOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'scroll' || v == 'wrap' || v == 'ellipsis') return v;
  return 'ellipsis';
}

bool _boolOf(dynamic raw) {
  if (raw is bool) return raw;
  final v = _str(raw).toLowerCase().trim();
  return v == 'true' || v == '1' || v == 'yes' || v == '是';
}

String _inputTargetKindOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'status_field' || v == 'session_var' || v == 'user_profile') {
    return v;
  }
  if (v == 'none' || v == 'local') return 'none';
  return 'none';
}

String _ownerOf(dynamic raw) {
  final v = _str(raw).toLowerCase().trim();
  if (v == 'char' || v == 'character') return 'char';
  if (v == 'neutral' || v == 'world' || v == 'environment') return 'neutral';
  return 'player';
}
