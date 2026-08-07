/// 阶段 1（Scout）的轻量选型计划。
///
/// 只让 AI 输出「这张卡有没有 UI、用哪种模式、大概需要哪些组件、要看哪些
/// 证据的细节」，token 开销远小于完整 UiDesignPlan。程序再按这里的点名，
/// 把对应组件的 API 详情与证据片段拼进阶段 2，输出完整 UiDesignPlan。
class UiScoutPlan {
  final bool hasUi;
  final double confidence;
  final String uiMode;
  final String uiName;
  final List<String> components;
  final List<int> regexIndices;
  final List<int> pluginIndices;
  final List<int> htmlIndices;
  final List<int> worldBookIndices;
  final bool includeFullBranches;
  final String evidenceSummary;
  final List<String> notes;

  const UiScoutPlan({
    required this.hasUi,
    required this.confidence,
    required this.uiMode,
    required this.uiName,
    required this.components,
    required this.regexIndices,
    required this.pluginIndices,
    required this.htmlIndices,
    required this.worldBookIndices,
    this.includeFullBranches = false,
    required this.evidenceSummary,
    required this.notes,
  });

  factory UiScoutPlan.fromJson(Map<String, dynamic> json) {
    final hasUi = json['hasUi'] != false;
    return UiScoutPlan(
      hasUi: hasUi,
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble().clamp(0.0, 1.0)
          : 0.5,
      uiMode: _modeOf(json['uiMode']),
      uiName: (json['uiName']?.toString().trim().isNotEmpty ?? false)
          ? json['uiName'].toString().trim()
          : 'AI 转译 UI',
      components: _strList(json['components']),
      regexIndices: _intList(json['regexIndices']),
      pluginIndices: _intList(json['pluginIndices']),
      htmlIndices: _intList(json['htmlIndices']),
      worldBookIndices: _intList(json['worldBookIndices']),
      includeFullBranches: json['includeFullBranches'] == true,
      evidenceSummary: json['evidenceSummary']?.toString().trim() ?? '',
      notes: _strList(json['notes']),
    );
  }

  static List<String> _strList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<int> _intList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <int>[];
    for (final item in raw) {
      if (item is int) {
        out.add(item);
      } else if (item is num) {
        out.add(item.toInt());
      } else if (item is String) {
        final v = int.tryParse(item.trim());
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  static String _modeOf(dynamic raw) {
    final v = raw?.toString().trim() ?? '';
    const allowed = {'opening', 'scene', 'extra_sticky', 'extra_companion'};
    return allowed.contains(v) ? v : 'extra_companion';
  }
}
