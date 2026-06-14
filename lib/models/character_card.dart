import 'character_meta.dart';

class CharacterCard {
  final String id;
  String name;
  String avatar;
  String cardImagePath;
  String description;
  String systemPrompt;
  String worldBookId;
  String userName;
  String userAvatar;
  String backgroundId;
  String userDetailSetting;

  String cardType;           // 'character' 或 'system'
  String entriesJson;        // 条目列表 JSON
  String openingGreetings;   // 开场白列表 JSON
  String metaJson;           // 扩展元信息 JSON（标签、作者、来源、post_history 等）

  CharacterCard({
    required this.id,
    required this.name,
    this.avatar = '',
    this.cardImagePath = '',
    this.description = '',
    this.systemPrompt = '',
    this.worldBookId = '',
    this.userName = '',
    this.userAvatar = '',
    this.backgroundId = '',
    this.userDetailSetting = '',
    this.cardType = 'character',        // 默认人物卡
    this.entriesJson = '[]',
    this.openingGreetings = '[]',
    this.metaJson = '{}',
  });

  /// 解析后的扩展元信息。修改后请调用 [applyMeta] 写回 [metaJson]。
  CharacterMeta get meta => CharacterMeta.fromJsonString(metaJson);

  /// 把修改后的 meta 写回 metaJson。
  void applyMeta(CharacterMeta value) {
    metaJson = value.toJsonString();
  }

  /// 从数据库 map 构造（统一入口，避免各处手写遗漏字段）。
  factory CharacterCard.fromDb(Map<String, dynamic> c) {
    return CharacterCard(
      id: c['id'] as String,
      name: c['name'] as String? ?? '',
      avatar: c['avatar'] as String? ?? '',
      cardImagePath: c['card_image_path'] as String? ?? '',
      description: c['description'] as String? ?? '',
      systemPrompt: c['system_prompt'] as String? ?? '',
      worldBookId: c['world_book_id'] as String? ?? '',
      userName: c['user_name'] as String? ?? '',
      userAvatar: c['user_avatar'] as String? ?? '',
      backgroundId: c['background_id'] as String? ?? '',
      userDetailSetting: c['user_detail_setting'] as String? ?? '',
      cardType: c['card_type'] as String? ?? 'character',
      entriesJson: c['entries_json'] as String? ?? '[]',
      openingGreetings: c['opening_greetings'] as String? ?? '[]',
      metaJson: c['meta_json'] as String? ?? '{}',
    );
  }
}
