class WorldBookEntry {
  String id;
  String title;
  String content;
  String keyword;
  int sortOrder;
  bool alwaysActive;
  bool recursive;

  WorldBookEntry({
    required this.id,
    required this.title,
    this.content = '',
    this.keyword = '',
    this.sortOrder = 0,
    this.alwaysActive = false,
    this.recursive = true,
  });

  factory WorldBookEntry.fromJson(Map<String, dynamic> json) {
    return WorldBookEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      keyword: json['keyword'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      alwaysActive: json['always_active'] as bool? ?? false,
      recursive: json['recursive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'keyword': keyword,
      'sort_order': sortOrder,
      'always_active': alwaysActive,
      'recursive': recursive,
    };
  }

  WorldBookEntry copyWith({
    String? id,
    String? title,
    String? content,
    String? keyword,
    int? sortOrder,
    bool? alwaysActive,
    bool? recursive,
  }) {
    return WorldBookEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      keyword: keyword ?? this.keyword,
      sortOrder: sortOrder ?? this.sortOrder,
      alwaysActive: alwaysActive ?? this.alwaysActive,
      recursive: recursive ?? this.recursive,
    );
  }
}