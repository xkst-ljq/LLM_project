/// 原卡视觉分析（给 AI UI 理解阶段的参考证据）。
///
/// 目标：让 AI「看见」原卡 CSS 的视觉特征（渐变/描边/发光/两列网格/明暗），
/// 从而在 UiDesignPlan.visualStyle 里自主映射到引擎可消费的字段。
///
/// 它是**参考材料，不是硬约束**——模型可以自主决定是否采用，采用与否
/// 都不影响转译流程本身。产出物只进 prompt，不事后 merge。
class UiVisualProfile {
  /// 证据来源（哪些 regexScripts / htmlSnippets 贡献了这些判断）。
  final String sourceSummary;

  /// 原卡 CSS 是否出现 linear-gradient。
  final bool hasGradient;

  /// 原卡 CSS 是否出现描边框（border solid）。
  final bool hasStroke;

  /// 原卡 CSS 是否出现 box-shadow 发光。
  final bool hasGlow;

  /// 推荐的底板材质：'solid' | 'gradient' | 'outline' | 'glass' | 'auto'。
  final String materialHint;

  /// 从 background 提取的主色（hex，无 #）。
  final String? primaryColor;

  /// 渐变第二色（hex，无 #）。
  final String? gradientSecondColor;

  /// 描边色（hex，无 #）。
  final String? strokeColor;

  /// 整体是否偏亮（决定气泡文字方向 / outline 可读性）。
  final bool lightTheme;

  /// 自由文本说明，供 AI 参考。
  final List<String> notes;

  /// 来源：'rule'（规则扫描）| 'ai'（模型深化）| 'none'。
  final String source;

  const UiVisualProfile({
    this.sourceSummary = '',
    this.hasGradient = false,
    this.hasStroke = false,
    this.hasGlow = false,
    this.materialHint = 'auto',
    this.primaryColor,
    this.gradientSecondColor,
    this.strokeColor,
    this.lightTheme = false,
    this.notes = const [],
    this.source = 'none',
  });

  /// 空实例：无视觉证据时使用，不向 prompt 输出任何内容。
  static const UiVisualProfile none = UiVisualProfile(source: 'none');

  bool get isEmpty =>
      source == 'none' ||
      (sourceSummary.isEmpty &&
          !hasGradient &&
          !hasStroke &&
          !hasGlow &&
          primaryColor == null &&
          notes.isEmpty);

  /// 压成给 AI 的 prompt 段。空实例返回空串。
  String toPromptSlim() {
    if (isEmpty) return '';
    final b = StringBuffer();
    b.writeln('【原卡视觉分析（参考，自行决定是否采用）】');
    if (sourceSummary.isNotEmpty) b.writeln('来源：$sourceSummary');
    final features = <String>[
      if (hasGradient) '渐变底',
      if (hasStroke) '描边框',
      if (hasGlow) '发光',
      if (materialHint != 'auto') '底板材质倾向=$materialHint',
      if (lightTheme) '整体偏亮',
      if (!lightTheme && (hasGlow || hasStroke || hasGradient)) '整体偏暗',
    ];
    if (features.isNotEmpty) b.writeln('特征：${features.join('；')}');
    if (primaryColor != null) b.writeln('主色候选：#${primaryColor!}');
    if (gradientSecondColor != null) {
      b.writeln('渐变第二色候选：#${gradientSecondColor!}');
    }
    if (strokeColor != null) b.writeln('描边色候选：#${strokeColor!}');
    for (final note in notes) {
      b.writeln('- $note');
    }
    b.writeln(
        '以上线索可映射到 visualStyle：gradientTo / surfaceMaterial / strokeColor / '
        'glowColor / glowIntensity / userBubbleColor / assistantBubbleColor。'
        '拿不准就留空，编译器会回落默认值。');
    return b.toString();
  }
}
