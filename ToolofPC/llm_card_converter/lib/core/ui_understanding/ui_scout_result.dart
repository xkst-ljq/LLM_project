/// Scout 阶段（AI UI 转译分级第一步）的输出模型。
///
/// Scout 读整张卡的证据**指纹**（不注入全文），先判断「这张卡需要哪几套
/// UI、每套要看哪些证据的细节」，再交给 Detailer 逐套单独设计。
/// 这样避免"单轮全量注入"里多套生命周期挤在一起导致 AI 漏掉某套。
class UiScoutResult {
  final bool hasUi;
  final String evidenceSummary;
  final List<UiAssemblySpec> assemblies;
  final List<String> sourceRefs;

  const UiScoutResult({
    required this.hasUi,
    required this.evidenceSummary,
    required this.assemblies,
    required this.sourceRefs,
  });

  factory UiScoutResult.fromJson(Map<String, dynamic> json) {
    final assemblies = <UiAssemblySpec>[];
    for (final item in _listOf(json['assemblies'])) {
      final spec = UiAssemblySpec.fromJson(item);
      if (spec.uiMode.isEmpty) continue;
      assemblies.add(spec);
    }
    return UiScoutResult(
      hasUi: _boolOf(json['hasUi']),
      evidenceSummary: _str(json['evidenceSummary']),
      assemblies: assemblies,
      sourceRefs: _strings(json['sourceRefs']),
    );
  }
}

/// Scout 判级出的"一套 UI"的选型，指导 Detailer 单独设计。
class UiAssemblySpec {
  final String uiMode;
  final String uiName;
  final List<String> reasons;
  final String evidenceSummary;
  final List<String> sourceRefs;
  final UiDetailRequest neededDetail;

  const UiAssemblySpec({
    required this.uiMode,
    required this.uiName,
    required this.reasons,
    required this.evidenceSummary,
    required this.sourceRefs,
    required this.neededDetail,
  });

  factory UiAssemblySpec.fromJson(Map<String, dynamic> json) {
    return UiAssemblySpec(
      uiMode: _modeOf(json['uiMode']),
      uiName: _fallback(_str(json['uiName']), _defaultNameForMode(_modeOf(json['uiMode']))),
      reasons: _strings(json['reasons']),
      evidenceSummary: _str(json['evidenceSummary']),
      sourceRefs: _strings(json['sourceRefs']),
      neededDetail: UiDetailRequest.fromJson(_mapOf(
        json['neededDetail'] ?? json['detail'],
      )),
    );
  }
}

/// Detailer 阶段要看哪些证据的细节（按索引切片，交给 detailPromptFor）。
class UiDetailRequest {
  final Set<int> regexIndices;
  final Set<int> pluginIndices;
  final Set<int> htmlIndices;
  final Set<int> worldBookIndices;
  final bool includeFullBranches;

  const UiDetailRequest({
    this.regexIndices = const {},
    this.pluginIndices = const {},
    this.htmlIndices = const {},
    this.worldBookIndices = const {},
    this.includeFullBranches = false,
  });

  factory UiDetailRequest.fromJson(Map<String, dynamic> json) {
    return UiDetailRequest(
      regexIndices: _intSetOf(json['regex'] ?? json['regexIndices']),
      pluginIndices: _intSetOf(json['plugin'] ?? json['pluginIndices']),
      htmlIndices: _intSetOf(json['html'] ?? json['htmlIndices']),
      worldBookIndices: _intSetOf(json['worldbook'] ?? json['worldbookIndices'] ?? json['worldBookIndices']),
      includeFullBranches: _boolOf(json['includeFullBranches'] ?? json['fullBranches']),
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
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Set<int> _intSetOf(dynamic raw) {
  final out = <int>{};
  if (raw is List) {
    for (final v in raw) {
      if (v is num && v >= 0) out.add(v.toInt());
    }
  } else if (raw is num && raw >= 0) {
    out.add(raw.toInt());
  }
  return out;
}

bool _boolOf(dynamic raw) {
  if (raw is bool) return raw;
  final v = _str(raw).toLowerCase().trim();
  return v == 'true' || v == '1' || v == 'yes' || v == '是';
}

/// 与 UiDesignPlan 相同的 mode 白名单解析；非法回落空串（调用方丢弃）。
String _modeOf(dynamic raw) {
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
      return '';
  }
}

String _defaultNameForMode(String mode) => switch (mode) {
      'opening' => '开场选择',
      'scene' => '场景终端',
      'extra_sticky' => '常驻 UI',
      'extra_companion' => '伴生状态栏',
      _ => 'AI 转译 UI',
    };
