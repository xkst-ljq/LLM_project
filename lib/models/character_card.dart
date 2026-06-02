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
  });
}