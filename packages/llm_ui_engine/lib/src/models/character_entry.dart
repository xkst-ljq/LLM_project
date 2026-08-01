// 人物卡固定条目名称
enum CharacterEntryType {
  name,           // 名称
  relationship,   // 与用户关系
  body,           // 身体数据
  psychology,     // 心理数据
  background,     // 背景数据
}

// 系统卡固定条目名称
enum SystemEntryType {
  systemName,     // 系统名称
  systemSummary,  // 系统概要
  systemDetails,  // 系统详情
  protagonist,    // 主角设定
  plot,           // 剧情
}

// 单个条目（固定条目的子字段，或自定义条目）
class CharacterEntry {
  String id;               // 唯一标识（固定条目用枚举名，自定义条目用时间戳）
  String title;            // 显示标题（如“姓名”、“身体数据”）
  String content;          // 内容文本（固定条目存储 JSON 子字段，自定义条目存储纯文本）
  bool enabled;            // 是否启用
  bool isCustom;           // 是否自定义条目
  int sortOrder;           // 排序

  CharacterEntry({
    required this.id,
    required this.title,
    this.content = '',
    this.enabled = false,    // 默认关闭（详细设定类）
    this.isCustom = false,
    this.sortOrder = 0,
  });

  factory CharacterEntry.fromJson(Map<String, dynamic> json) {
    return CharacterEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      isCustom: json['is_custom'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'enabled': enabled,
      'is_custom': isCustom,
      'sort_order': sortOrder,
    };
  }

  CharacterEntry copyWith({
    String? id,
    String? title,
    String? content,
    bool? enabled,
    bool? isCustom,
    int? sortOrder,
  }) {
    return CharacterEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      isCustom: isCustom ?? this.isCustom,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

// 开场白条目
class OpeningGreeting {
  String id;
  String content;

  OpeningGreeting({required this.id, this.content = ''});

  factory OpeningGreeting.fromJson(Map<String, dynamic> json) {
    return OpeningGreeting(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'content': content};
  }

  OpeningGreeting copyWith({String? id, String? content}) {
    return OpeningGreeting(
      id: id ?? this.id,
      content: content ?? this.content,
    );
  }
}