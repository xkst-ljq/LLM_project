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

  /// 键前缀，用于批量清理过期草稿。
  static const String _keyPrefix = 'character_draft_';

  /// 草稿保质期。
  ///
  /// 用户判断：「修改过后一般都会体验一下看看如何，所以被遗忘的概率很小」。
  /// 这个机制针对的是**刚刚误触退出**那一下，不是长期存档；
  /// 放太久反而会在几天后弹出一份自己都想不起来的修改，令人困惑。
  static const Duration maxAge = Duration(hours: 24);

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

  /// 读取草稿。没有 / 已过期 / 解析失败时返回 null。
  ///
  /// 解析失败按「没有草稿」处理而不是抛出：草稿是锦上添花的功能，
  /// 不该因为一份坏数据就让用户进不了编辑页。
  ///
  /// 过期的草稿会**顺手删掉**——读取是它唯一的必经之路，
  /// 在这里清理比额外跑一个定时任务简单可靠。
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

      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        (decoded['savedAt'] as num?)?.toInt() ?? 0,
      );

      // 过期即作废。用 abs() 是为了兼容「用户把系统时间往回调」的情况——
      // 那会让 difference 变成负数，不判绝对值就会让草稿永不过期。
      if (DateTime.now().difference(savedAt).abs() >= maxAge) {
        await prefs.remove(_keyOf(characterId));
        return null;
      }

      return CharacterDraft(savedAt: savedAt, data: Map<String, dynamic>.from(data));
    } catch (_) {
      // 坏数据也顺手清掉，免得每次进编辑页都白解析一遍。
      await prefs.remove(_keyOf(characterId));
      return null;
    }
  }

  /// 清理所有已过期的草稿。
  ///
  /// `load` 只在进入某张卡时清理那一张；已经删掉的角色卡、
  /// 或者再也没打开过的卡，其草稿会一直躺在 SharedPreferences 里。
  /// 在 App 启动时跑一次，把它们一并回收。
  static Future<void> purgeExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      for (final key in prefs.getKeys().toList()) {
        if (!key.startsWith(_keyPrefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) {
          await prefs.remove(key);
          continue;
        }
        try {
          final decoded = jsonDecode(raw);
          final savedAt = DateTime.fromMillisecondsSinceEpoch(
            (decoded is Map ? (decoded['savedAt'] as num?)?.toInt() : null) ?? 0,
          );
          if (now.difference(savedAt).abs() >= maxAge) {
            await prefs.remove(key);
          }
        } catch (_) {
          await prefs.remove(key);
        }
      }
    } catch (_) {
      // 清理失败不影响任何功能，静默即可。
    }
  }

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
    // 草稿最长只活 24h（见 maxAge），所以不会走到「天」这个量级。
    return '${diff.inHours} 小时前';
  }
}
