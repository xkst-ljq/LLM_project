/// 状态栏字段定义（卡片层，属于角色卡的玩法设定）。
///
/// 设计要点（见 ROADMAP 状态栏 / 会话副本机制）：
///   - 字段「定义」和「初始值」写在角色卡里（随卡片导入导出），由作者决定。
///   - 字段「当前值」存在会话副本（SessionState.statusValues）里，
///     键为字段 id；清空聊天记录后回到卡片初始值。
///   - 数值字段（number）：LLM 只返回变化量（delta），引擎做
///     `新值 = clamp(旧值 + delta, min, max)`，绝不让 LLM 直接给绝对值。
///   - 文本字段（text）：用于地点 / 时间 / 关系阶段等，按新值替换。
///
/// 用 id 作为运行时值的键（而非 name），这样作者改字段显示名不会丢失已有值。
class StatusBarField {
  String id;
  String name; // 显示名 / 字段名（也用于 prompt 中向 LLM 标识该字段）
  String type; // 'number' | 'text'
  String initialValue;
  double? minValue; // 仅 number 有意义
  double? maxValue; // 仅 number 有意义
  String pinSide; // 'none' | 'left' | 'right'：折叠长条上固定在哪一侧
  int order; // 排序

  StatusBarField({
    required this.id,
    required this.name,
    this.type = 'number',
    this.initialValue = '',
    this.minValue,
    this.maxValue,
    this.pinSide = 'none',
    this.order = 0,
  });

  bool get isNumber => type == 'number';
  bool get isPinned => pinSide == 'left' || pinSide == 'right';
  bool get isPinnedLeft => pinSide == 'left';
  bool get isPinnedRight => pinSide == 'right';

  static double? _readDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
    return null;
  }

  static String _readPinSide(Map<String, dynamic> json) {
    final raw = json['pin_side']?.toString();
    if (raw == 'left' || raw == 'right' || raw == 'none') return raw!;
    // 兼容旧字段 pinned(bool)：true -> 默认固定到左侧。
    if (json['pinned'] == true) return 'left';
    return 'none';
  }

  factory StatusBarField.fromJson(Map<String, dynamic> json) {
    final id = (json['id']?.toString() ?? '').trim();
    final name = (json['name']?.toString() ?? '').trim();
    return StatusBarField(
      // id 兜底：旧 / 损坏数据用 name 兜底，避免空 id。
      id: id.isNotEmpty ? id : (name.isNotEmpty ? name : 'field'),
      name: name,
      type: (json['type']?.toString() == 'text') ? 'text' : 'number',
      initialValue: json['initial_value']?.toString() ?? '',
      minValue: _readDouble(json['min_value']),
      maxValue: _readDouble(json['max_value']),
      pinSide: _readPinSide(json),
      order: json['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'initial_value': initialValue,
      'min_value': minValue,
      'max_value': maxValue,
      'pin_side': pinSide,
      'order': order,
    };
  }

  StatusBarField copyWith({
    String? id,
    String? name,
    String? type,
    String? initialValue,
    double? minValue,
    double? maxValue,
    String? pinSide,
    int? order,
  }) {
    return StatusBarField(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialValue: initialValue ?? this.initialValue,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      pinSide: pinSide ?? this.pinSide,
      order: order ?? this.order,
    );
  }
}
