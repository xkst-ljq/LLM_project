/// 世界书条目。
///
/// 高级触发字段（对齐酒馆 / Character Card 的世界书，便于忠实还原第三方卡）：
///   - keys            主关键词列表（命中其一即触发）
///   - secondaryKeys   次关键词列表（配合 selective 逻辑，预留）
///   - enabled         是否启用（作者关闭的条目仍导入，但默认不启用）
///   - insertionOrder  注入优先级（数值小的排在前，越靠前 LLM 越重视）
///   - position        插入位置：'before_char'（角色设定之前）/ 'after_char'（之后）
///   - alwaysActive    常驻（对应酒馆 constant）
///   - recursive       是否参与递归扩展
///
/// 兼容性：旧数据只有单个 `keyword` 字符串，fromJson 会按逗号拆分为 keys，
/// 因此旧世界书读出来行为不变（多关键词同样生效）。
class WorldBookEntry {
  String id;
  String title;
  String content;
  List<String> keys;
  List<String> secondaryKeys;
  int sortOrder;
  int insertionOrder;
  String position;
  bool enabled;
  bool alwaysActive;
  bool recursive;

  WorldBookEntry({
    required this.id,
    required this.title,
    this.content = '',
    List<String>? keys,
    List<String>? secondaryKeys,
    this.sortOrder = 0,
    this.insertionOrder = 0,
    this.position = 'before_char',
    this.enabled = true,
    this.alwaysActive = false,
    this.recursive = true,
  })  : keys = keys ?? <String>[],
        secondaryKeys = secondaryKeys ?? <String>[];

  /// 关键词的展示 / 编辑用字符串（逗号分隔）。
  String get keywordDisplay => keys.join('，');

  /// 是否设置了任何主关键词。
  bool get hasKeys => keys.any((k) => k.trim().isNotEmpty);

  /// 把逗号 / 中文逗号 / 分号分隔的字符串拆成关键词列表（去空白、去重、保序）。
  static List<String> splitKeys(String raw) {
    if (raw.trim().isEmpty) return <String>[];
    final parts = raw.split(RegExp(r'[，,;；\n]'));
    final out = <String>[];
    for (final p in parts) {
      final k = p.trim();
      if (k.isNotEmpty && !out.contains(k)) out.add(k);
    }
    return out;
  }

  static List<String> _readKeys(dynamic v) {
    if (v is List) {
      final out = <String>[];
      for (final e in v) {
        final k = e.toString().trim();
        if (k.isNotEmpty && !out.contains(k)) out.add(k);
      }
      return out;
    }
    if (v is String) return splitKeys(v);
    return <String>[];
  }

  factory WorldBookEntry.fromJson(Map<String, dynamic> json) {
    // 关键词：优先读新字段 keys；否则回退旧字段 keyword（按逗号拆分）。
    List<String> keys = _readKeys(json['keys']);
    if (keys.isEmpty && json['keyword'] != null) {
      keys = _readKeys(json['keyword']);
    }

    return WorldBookEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      keys: keys,
      secondaryKeys: _readKeys(json['secondary_keys']),
      sortOrder: json['sort_order'] as int? ?? 0,
      insertionOrder: json['insertion_order'] as int? ?? 0,
      position: (json['position'] as String?)?.trim().isNotEmpty == true
          ? json['position'] as String
          : 'before_char',
      enabled: json['enabled'] as bool? ?? true,
      alwaysActive: json['always_active'] as bool? ?? false,
      recursive: json['recursive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'keys': keys,
      'secondary_keys': secondaryKeys,
      'sort_order': sortOrder,
      'insertion_order': insertionOrder,
      'position': position,
      'enabled': enabled,
      'always_active': alwaysActive,
      'recursive': recursive,
    };
  }

  WorldBookEntry copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? keys,
    List<String>? secondaryKeys,
    int? sortOrder,
    int? insertionOrder,
    String? position,
    bool? enabled,
    bool? alwaysActive,
    bool? recursive,
  }) {
    return WorldBookEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      keys: keys ?? List<String>.from(this.keys),
      secondaryKeys: secondaryKeys ?? List<String>.from(this.secondaryKeys),
      sortOrder: sortOrder ?? this.sortOrder,
      insertionOrder: insertionOrder ?? this.insertionOrder,
      position: position ?? this.position,
      enabled: enabled ?? this.enabled,
      alwaysActive: alwaysActive ?? this.alwaysActive,
      recursive: recursive ?? this.recursive,
    );
  }
}
