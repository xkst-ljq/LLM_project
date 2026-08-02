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

  /// 归属：这个字段描述的是谁的属性。
  ///
  /// 'player'  玩家的（金钱、体力、背包容量等）
  /// 'char'    角色自己的（商贩的钱包、角色的心情）
  /// 'neutral' 中立/环境（时间、天气、地点）
  ///
  /// 注入 Prompt 时会据此加上主语。缺少主语时 LLM 无法判断增减方向——
  /// 实测「金钱数量」在商贩剧情里被理解成商贩的收入，买东西反而 +600。
  String owner;

  /// 各开场分支的初始值：分支下标 -> 初值。
  ///
  /// ## 解决什么
  ///
  /// 一张卡常有多条开场白，且**各自带不同的起始状态**。
  /// 例如黑曜石那张卡：
  ///
  /// | 开场 | 精神 | 体力 | 势力 |
  /// |---|---|---|---|
  /// | 新人入狱 | 84% | 92% | 无 |
  /// | 狱警入职 | 90% | 90% | 管理局 |
  ///
  /// 只有一个 [initialValue] 表达不了这种差异，
  /// 转译时只能把所有分支压成同一个值——作者精心设计的开局区别就没了。
  ///
  /// ## 与 [initialValue] 的关系
  ///
  /// [initialValue] 是**主支路（分支 0）**的值，也是兜底：
  /// 某分支没登记时回落到它。因此单开场白的卡完全不受影响，
  /// 这个 Map 留空即可。
  ///
  /// 键用 String 而非 int，是为了能直接进 JSON（JSON 的键必须是字符串）。
  Map<String, String> branchInitialValues;

  StatusBarField({
    required this.id,
    required this.name,
    this.type = 'number',
    this.initialValue = '',
    this.minValue,
    this.maxValue,
    this.pinSide = 'none',
    this.order = 0,
    this.owner = 'player',
    Map<String, String>? branchInitialValues,
  }) : branchInitialValues =
            branchInitialValues ?? <String, String>{};

  /// 取某分支的初值。没登记则回落主支路 [initialValue]。
  ///
  /// 返回 null 表示「该分支无预设且主支路也没值」，调用方应跳过。
  String? initialValueForBranch(int branch) {
    final v = branchInitialValues['\$branch'];
    if (v != null && v.isNotEmpty) return v;
    if (branch == 0) return initialValue.isEmpty ? null : initialValue;
    // 未设计的分支照搬主支路。
    return initialValue.isEmpty ? null : initialValue;
  }

  /// 某个值是否来自任一分支的预设。
  ///
  /// 用于判断「玩家翻看别的开场白时，当前值能否被覆盖」：
  /// 若当前值仍是某分支的预设，说明玩家还没真正改动过，可以换；
  /// 若已经是别的值（对话中变化过），就不该被重置。
  bool isBranchPreset(String value) =>
      value == initialValue || branchInitialValues.containsValue(value);

  bool get isNumber => type == 'number';

  /// 带主语的显示名，用于 Prompt 注入。
  /// 中立字段不加主语，避免「环境的时间」这种别扭表述。
  String get qualifiedName {
    switch (owner) {
      case 'char':
        return '你的$name';
      case 'neutral':
        return name;
      default:
        return '玩家的$name';
    }
  }

  String get ownerLabel {
    switch (owner) {
      case 'char':
        return '角色自己';
      case 'neutral':
        return '中立/环境';
      default:
        return '玩家';
    }
  }
  bool get isPinned => pinSide == 'left' || pinSide == 'right';
  bool get isPinnedLeft => pinSide == 'left';
  bool get isPinnedRight => pinSide == 'right';

  static double? _readDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
    return null;
  }

  static String _readOwner(dynamic raw) {
    final v = raw?.toString();
    if (v == 'char' || v == 'neutral' || v == 'player') return v!;
    return 'player';
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
      // 旧卡片没有该字段，默认按玩家属性处理（最常见的情况）。
      owner: _readOwner(json['owner']),
      branchInitialValues: _readBranchValues(json['branch_initial_values']),
    );
  }

  /// 读分支初值表。
  ///
  /// 容错要到位：这份数据由转译工具生成，键可能是数字也可能是字符串
  /// （JSON 里本该是字符串，但手写的卡什么情况都有）。
  static Map<String, String> _readBranchValues(dynamic raw) {
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      // 只收非负整数下标，挡掉脏数据。
      if (k.isEmpty || int.tryParse(k) == null) return;
      final v = value?.toString() ?? '';
      if (v.isNotEmpty) out[k] = v;
    });
    return out;
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
      'owner': owner,
      // 空表不落盘：单开场白的卡不该平白多一个空字段。
      if (branchInitialValues.isNotEmpty)
        'branch_initial_values': branchInitialValues,
    };
  }

  /// [clearMinValue] / [clearMaxValue] 用于把上下限显式改回「不限制」。
  /// 仅靠 `minValue: null` 无法表达清空——那与「不修改」无法区分。
  StatusBarField copyWith({
    String? id,
    String? name,
    String? type,
    String? initialValue,
    double? minValue,
    double? maxValue,
    String? pinSide,
    int? order,
    String? owner,
    bool clearMinValue = false,
    bool clearMaxValue = false,
  }) {
    return StatusBarField(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialValue: initialValue ?? this.initialValue,
      minValue: clearMinValue ? null : (minValue ?? this.minValue),
      maxValue: clearMaxValue ? null : (maxValue ?? this.maxValue),
      pinSide: pinSide ?? this.pinSide,
      order: order ?? this.order,
      owner: owner ?? this.owner,
    );
  }
}
