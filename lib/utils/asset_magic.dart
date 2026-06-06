class AssetMagic {
  static const String assetV1 = 'LLM_PROJECT_ASSET_V1';
  static const String backupV1 = 'LLM_PROJECT_BACKUP_V1';

  static const String characterCard = 'character_card';
  static const String backgroundCard = 'background_card';
  static const String worldBook = 'world_book';
  static const String knowledgeBase = 'knowledge_base';
  static const String jailbreak = 'jailbreak';

  /// 后续正式命名后，可以把新 magic 加到这里，旧 magic 保留兼容。
  static const Set<String> supportedAssetMagics = {
    assetV1,
  };

  static const Set<String> supportedBackupMagics = {
    backupV1,
  };

  static bool isSupportedAssetMagic(String? value) {
    return supportedAssetMagics.contains(value);
  }

  static bool isSupportedBackupMagic(String? value) {
    return supportedBackupMagics.contains(value);
  }
}