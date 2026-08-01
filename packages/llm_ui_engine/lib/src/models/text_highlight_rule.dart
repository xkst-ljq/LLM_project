import 'dart:convert';

/// 一条文本着色规则：正则匹配到的片段按指定样式渲染。
///
/// 用途：角色扮演文本里「台词」「心理活动」「系统提示」等靠标点区分，
/// 纯文本渲染看起来是一整坨。着色后阅读效率显著提升。
///
/// 原本这套规则写死在 `chat_page._styleForRoleplayToken` 里（引号 / 括号 /
/// 书名号 / 方括号四种）。改为数据驱动后，作者可以增删改——
/// 不同卡片的写作约定差异很大：有人用 `**` 包动作，有人用 `[]` 包旁白，
/// 写死的四条覆盖不了。
///
/// **不做的事**：不执行任何替换 / 脚本（酒馆的 regex_scripts 会改写文本内容，
/// 我们只着色，不改动原文）。这是有意的安全边界——
/// 着色是纯展示层行为，不影响发给 LLM 的内容，也不会污染存档。
class TextHighlightRule {
  /// 规则名，仅用于编辑器里辨认，不参与渲染。
  final String name;

  /// 匹配用的正则表达式源码。
  ///
  /// 存的是源码字符串而非编译结果：要随角色卡 JSON 序列化。
  /// 编译在 [pattern] 里做，失败返回 null（见该 getter 的说明）。
  final String regex;

  /// 文字颜色（ARGB int）。null 表示沿用基准样式的颜色。
  final int? colorValue;

  final bool bold;
  final bool italic;

  /// 是否启用。停用而不删除，方便作者临时对比效果。
  final bool enabled;

  const TextHighlightRule({
    required this.name,
    required this.regex,
    this.colorValue,
    this.bold = false,
    this.italic = false,
    this.enabled = true,
  });

  /// 编译后的正则；源码非法时返回 null。
  ///
  /// 作者手写的正则**必然**会出现半成品状态（比如刚敲下 `(` 还没敲 `)`），
  /// 这时抛异常会让整个消息列表崩掉。因此这里吞掉异常，
  /// 由调用方跳过该条规则——渲染退化成「这条不生效」，而不是白屏。
  RegExp? get pattern {
    final src = regex.trim();
    if (src.isEmpty) return null;
    try {
      return RegExp(src, multiLine: true);
    } catch (_) {
      return null;
    }
  }

  /// 正则是否可用。编辑器据此给出即时校验提示。
  bool get isValid => regex.trim().isEmpty ? false : pattern != null;

  TextHighlightRule copyWith({
    String? name,
    String? regex,
    int? colorValue,
    bool clearColor = false,
    bool? bold,
    bool? italic,
    bool? enabled,
  }) {
    return TextHighlightRule(
      name: name ?? this.name,
      regex: regex ?? this.regex,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      enabled: enabled ?? this.enabled,
    );
  }

  factory TextHighlightRule.fromJson(Map<String, dynamic> json) {
    return TextHighlightRule(
      name: json['name']?.toString() ?? '',
      regex: json['regex']?.toString() ?? '',
      colorValue: (json['color'] as num?)?.toInt(),
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      // 缺省视为启用：旧数据没有这个字段。
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'regex': regex,
        if (colorValue != null) 'color': colorValue,
        'bold': bold,
        'italic': italic,
        'enabled': enabled,
      };

  static List<TextHighlightRule> listFromJson(dynamic raw) {
    if (raw is! List) return const <TextHighlightRule>[];
    final out = <TextHighlightRule>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(TextHighlightRule.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  static String listToJsonString(List<TextHighlightRule> rules) =>
      jsonEncode(rules.map((r) => r.toJson()).toList());

  /// 内置默认规则。
  ///
  /// 与改造前 `_styleForRoleplayToken` 的四条完全一致，
  /// 保证老卡片升级后观感不变（作者没配过规则时就用这套）。
  /// 中英标点各写一份：导入的第三方卡两种写法都有。
  static List<TextHighlightRule> defaults() => const [
        TextHighlightRule(
          name: '台词',
          // 引号内是角色说的话，读者最需要抓住的部分 → 加重。
          regex: r'“[^”]*”|"[^"]*"',
          colorValue: 0xFF000000,
          bold: true,
        ),
        TextHighlightRule(
          name: '心理活动 / 旁白',
          // 括号内是内心戏或旁白，弱化成灰紫斜体，避免与台词抢注意力。
          regex: r'（[^（）]*）|\([^()]*\)',
          colorValue: 0xFF6A5A78,
          italic: true,
        ),
        TextHighlightRule(
          name: '书名 / 专名',
          regex: r'《[^》]*》',
          colorValue: 0xFF4E6FAE,
          bold: true,
        ),
        TextHighlightRule(
          name: '系统提示',
          regex: r'【[^】]*】',
          colorValue: 0xFFB8632A,
          bold: true,
        ),
      ];

  @override
  bool operator ==(Object other) =>
      other is TextHighlightRule &&
      other.name == name &&
      other.regex == regex &&
      other.colorValue == colorValue &&
      other.bold == bold &&
      other.italic == italic &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(name, regex, colorValue, bold, italic, enabled);
}
