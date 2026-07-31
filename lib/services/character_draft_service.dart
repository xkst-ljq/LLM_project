import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 角色卡编辑草稿。
///
/// ## 解决什么问题
///
/// 角色卡编辑页里改的东西（词条、开场白、元信息……）**必须点「保存」
/// 才会落库**。而这个页面是个浮层对话框，点一下外部空白就直接关闭——
/// 用户反馈：「如果不小心意外没有保存，点了一下外部，可能就前功尽弃了」。
///
/// 机制：退出时若检测到有未保存改动，静默存一份草稿（不打断关闭手势）；
/// 下次进入同一张卡时提示「上次有未保存的修改，是否恢复」。
///
/// ## 为什么存 SharedPreferences 而不是 characters 表
///
/// 草稿是**临时中间态**，不该混进角色卡本体：
///   - 存进表里，任何读取角色卡的地方（聊天页、导出、备份）都要额外
///     判断「这份数据是正式的还是草稿」，污染面太大；
///   - 草稿随时可能被丢弃，不值得为它做数据库迁移；
///   - 体积很小（纯文本字段），SharedPreferences 完全够用。
class CharacterDraftService {
  /// 每张卡一个键，避免互相覆盖。
  static String _keyOf(String characterId) => 'character_draft_$characterId';

  /// 保存草稿。[payload] 由编辑页自己组织，本服务不关心其结构。
  static Future<void> save(
    String characterId,
    Map<String, dynamic> payload,
  ) async {
    if (characterId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyOf(characterId),
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'data': payload,
      }),
    );
  }

  /// 读取草稿。没有 / 解析失败时返回 null。
  ///
  /// 解析失败按「没有草稿」处理而不是抛出：草稿是锦上添花的功能，
  /// 不该因为一份坏数据就让用户进不了编辑页。
  static Future<CharacterDraft?> load(String characterId) async {
    if (characterId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOf(characterId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      if (data is! Map) return null;
      return CharacterDraft(
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (decoded['savedAt'] as num?)?.toInt() ?? 0,
        ),
        data: Map<String, dynamic>.from(data),
      );
    } catch (_) {
      return null;
    }
  }

  /// 是否存在草稿。用于进入编辑页前的快速判断。
  static Future<bool> has(String characterId) async =>
      (await load(characterId)) != null;

  /// 丢弃草稿。
  ///
  /// **两个时机都必须调**：
  ///   1. 用户点「不保存」——按用户要求「彻底不留上次的修改记录」；
  ///   2. 用户正常点了「保存」——此时草稿已经过时，留着会在下次进入时
  ///      弹出一个内容和当前卡完全一致的提示，纯噪音。
  static Future<void> clear(String characterId) async {
    if (characterId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOf(characterId));
  }
}

/// 一份草稿及其保存时间。
class CharacterDraft {
  const CharacterDraft({required this.savedAt, required this.data});

  final DateTime savedAt;
  final Map<String, dynamic> data;

  /// 「3 分钟前」这类相对时间，用于提示文案。
  /// 草稿通常是刚刚误触产生的，相对时间比绝对时间更有判断价值。
  String get relativeTime {
    final diff = DateTime.now().difference(savedAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
