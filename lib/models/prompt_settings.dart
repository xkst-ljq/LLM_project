class PromptSettings {
  static const String defaultCharacterRoleplayRules = '''
你正在扮演 {{char}}。
请始终保持 {{char}} 的身份、性格、语气、关系和当前处境。
不要代替 {{user}} 做决定、说话或行动。
涉及动作、表情、心理和互动时，应以 {{char}} 的视角自然回应。
''';

  static const String defaultSystemRoleplayRules = '''
你正在作为系统叙事与角色扮演引擎运行。
请保持世界观、规则、剧情、角色关系与上下文连续。
不要代替 {{user}} 做决定、说话或行动。
''';

  static const String defaultContinuityReminder = '''
保持当前角色身份、关系、场景、上下文和既有设定连续。
不要忽略最近对话中的动作、情绪、距离、称呼和关系变化。
''';

  bool injectRoleplayRules;
  bool injectContinuityReminder;
  String characterRoleplayRules;
  String systemRoleplayRules;
  String continuityReminder;
  int summaryInterval;
  int fullDetailInterval;
  int worldBookScanDepth;

  PromptSettings({
    this.injectRoleplayRules = true,
    this.injectContinuityReminder = true,
    this.characterRoleplayRules = defaultCharacterRoleplayRules,
    this.systemRoleplayRules = defaultSystemRoleplayRules,
    this.continuityReminder = defaultContinuityReminder,
    this.summaryInterval = 3,
    this.fullDetailInterval = 12,
    this.worldBookScanDepth = 4,
  });

  static int _readInt(Map<String, dynamic> json, String key, int fallback) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  factory PromptSettings.fromJson(Map<String, dynamic> json) {
    return PromptSettings(
      injectRoleplayRules: json['inject_roleplay_rules'] as bool? ?? true,
      injectContinuityReminder:
      json['inject_continuity_reminder'] as bool? ?? true,
      characterRoleplayRules:
      json['character_roleplay_rules'] as String? ??
          defaultCharacterRoleplayRules,
      systemRoleplayRules:
      json['system_roleplay_rules'] as String? ?? defaultSystemRoleplayRules,
      continuityReminder:
      json['continuity_reminder'] as String? ?? defaultContinuityReminder,
      summaryInterval: _readInt(json, 'summary_interval', 3),
      fullDetailInterval: _readInt(json, 'full_detail_interval', 12),
      worldBookScanDepth: _readInt(json, 'world_book_scan_depth', 4),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inject_roleplay_rules': injectRoleplayRules,
      'inject_continuity_reminder': injectContinuityReminder,
      'character_roleplay_rules': characterRoleplayRules,
      'system_roleplay_rules': systemRoleplayRules,
      'continuity_reminder': continuityReminder,
      'summary_interval': summaryInterval,
      'full_detail_interval': fullDetailInterval,
      'world_book_scan_depth': worldBookScanDepth,
    };
  }

  PromptSettings copy() {
    return PromptSettings(
      injectRoleplayRules: injectRoleplayRules,
      injectContinuityReminder: injectContinuityReminder,
      characterRoleplayRules: characterRoleplayRules,
      systemRoleplayRules: systemRoleplayRules,
      continuityReminder: continuityReminder,
      summaryInterval: summaryInterval,
      fullDetailInterval: fullDetailInterval,
      worldBookScanDepth: worldBookScanDepth,
    );
  }
}
