import 'dart:convert';

import 'character_entry.dart';

/// A13-2：数据通道指向「角色卡设定条目」的三级定位。
///
/// 玩家在 opening UI 里填的姓名 / 职业 / 属性，语义上属于**角色档案**，
/// 而不是散装的会话变量。这个类描述「填的内容要落到卡片的哪一格」：
///
/// ```
/// 一级 group   简单介绍 / 详细设定
/// 二级 entryId 条目（身体数据 / 心理数据 / 自定义条目…）
/// 三级 fieldKey 子字段（种族 / 性别 / 年龄…），自定义条目则是标题
/// ```
///
/// **不修改角色卡本体**：玩家填的值写进 `SessionState`，
/// 注入 Prompt 时覆盖母版对应位置。角色卡是可分享的，
/// 玩家 A 填的内容不能带给玩家 B；清空聊天记录即回到作者的原始设定。
class CardEntryTarget {
  /// 一级：`intro`（简单介绍）/ `detail`（详细设定）。
  final String group;

  /// 二级：条目 id。固定条目用枚举名（如 `body`），
  /// 自定义条目用 [customEntryId]，此时本字段为 [customEntryMarker]。
  final String entryId;

  /// 三级：子字段 key（如 `race`）。
  ///
  /// 自定义条目没有子字段，此处存**条目标题**——
  /// 默认标题是「新条目」，靠标题区分才能同时存在多个自定义条目。
  final String fieldKey;

  const CardEntryTarget({
    required this.group,
    required this.entryId,
    required this.fieldKey,
  });

  /// 一级取值：简单介绍。只有固定条目，不能加自定义。
  static const String groupIntro = 'intro';

  /// 一级取值：详细设定。允许添加自定义条目。
  static const String groupDetail = 'detail';

  /// 二级的特殊取值：表示这是一个自定义条目。
  static const String customEntryMarker = '__custom__';

  bool get isCustomEntry => entryId == customEntryMarker;

  /// 配置是否完整可用。
  ///
  /// 自定义条目要求标题非空；固定条目要求选了子字段。
  bool get isValid {
    if (group.isEmpty || entryId.isEmpty) return false;
    return fieldKey.trim().isNotEmpty;
  }

  /// 写进 `SessionState.vars` 的键。
  ///
  /// 带 `card:` 前缀与普通会话变量区隔，避免作者起了同名变量互相覆盖。
  /// 自定义条目按标题成键——同一标题视为同一条目，重复填写是覆盖而非新增。
  String get sessionKey => isCustomEntry
      ? 'card:$group:custom:${fieldKey.trim()}'
      : 'card:$group:$entryId:$fieldKey';

  /// 供 Prompt 显示的名字，例如「身体数据 · 种族」。
  String displayLabel(String entryTitle) =>
      isCustomEntry ? fieldKey.trim() : '$entryTitle · ${fieldLabelOf(entryId, fieldKey)}';

  Map<String, dynamic> toJson() => {
        'group': group,
        'entryId': entryId,
        'fieldKey': fieldKey,
      };

  static CardEntryTarget? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final group = map['group']?.toString() ?? '';
    final entryId = map['entryId']?.toString() ?? '';
    final fieldKey = map['fieldKey']?.toString() ?? '';
    if (group.isEmpty || entryId.isEmpty) return null;
    return CardEntryTarget(
      group: group,
      entryId: entryId,
      fieldKey: fieldKey,
    );
  }

  CardEntryTarget copyWith({
    String? group,
    String? entryId,
    String? fieldKey,
  }) {
    return CardEntryTarget(
      group: group ?? this.group,
      entryId: entryId ?? this.entryId,
      fieldKey: fieldKey ?? this.fieldKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardEntryTarget &&
      other.group == group &&
      other.entryId == entryId &&
      other.fieldKey == fieldKey;

  @override
  int get hashCode => Object.hash(group, entryId, fieldKey);

  // ---------------------------------------------------------------
  // 卡片结构查询
  // ---------------------------------------------------------------

  /// 各卡类型下，一级分组包含哪些固定条目。
  ///
  /// 与 `character_edit_page` 的分区保持一致——作者在角色卡里看到的
  /// 「简单介绍 / 详细设定」怎么分，这里就怎么分，否则会对不上。
  static List<String> fixedEntryIdsOf(String cardType, String group) {
    if (cardType == 'system') {
      return group == groupIntro
          ? const ['system_name', 'system_summary']
          : const ['system_details', 'protagonist', 'plot'];
    }
    return group == groupIntro
        ? const ['name_entry', 'relationship']
        : const ['body', 'psychology', 'background'];
  }

  /// 该条目的子字段 key 列表。空表示这是纯文本条目（无三级）。
  ///
  /// 固定条目的子字段从条目自身的 JSON 内容里读——
  /// 作者可能改过结构，硬编码一份会与实际数据脱节。
  static List<String> fieldKeysOf(CharacterEntry entry) {
    if (entry.isCustom) return const [];
    final raw = entry.content.trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.keys.map((k) => k.toString()).toList();
      }
    } catch (_) {
      // 纯文本条目（如「与用户关系」）解析失败是正常的。
    }
    return const [];
  }

  /// 子字段的中文名。与角色卡编辑页的 `_fieldLabel` 保持一致。
  static String fieldLabelOf(String entryId, String fieldKey) {
    const map = {
      'name_entry': {'last_name': '姓', 'first_name': '名', 'other': '其他'},
      'body': {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'height': '身高',
        'weight': '体重',
        'measurements': '三围',
        'other': '其他数据',
      },
      'psychology': {'personality': '性格', 'thoughts': '思想', 'interests': '兴趣/爱好/癖好'},
      'background': {'origin': '出身背景', 'experiences': '经历事件', 'current': '当前背景'},
      'system_details': {
        'world_setting': '世界设定',
        'worldview': '世界观设定',
        'system_mechanism': '系统机制设定',
      },
      'protagonist': {'name': '主角名称', 'detail': '主角详细设定'},
      'plot': {
        'cause': '起因',
        'events': '中途特定触发事件',
        'goal': '目标',
        'possible_endings': '可能结局设定',
      },
    };
    return map[entryId]?[fieldKey] ?? fieldKey;
  }

  /// 一级分组的显示名。
  static String groupLabelOf(String group) =>
      group == groupIntro ? '简单介绍' : '详细设定';
}
