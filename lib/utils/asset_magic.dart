class AssetMagic {
  static const String assetV1 = 'LLM_PROJECT_ASSET_V1';
  static const String backupV1 = 'LLM_PROJECT_BACKUP_V1';

  static const String characterCard = 'character_card';
  static const String backgroundCard = 'background_card';
  static const String worldBook = 'world_book';
  static const String knowledgeBase = 'knowledge_base';
  static const String jailbreak = 'jailbreak';

  /// 复合组件（UI 部件）。
  ///
  /// 单独成一类而不是跟着角色卡走：复合件存在**全局资产库**里、
  /// 不属于任何角色卡，本来就是自包含的「零件」。
  /// 整套 UI 方案则与角色卡绑定太深（页面路由、状态字段 id），
  /// 不适合独立分享。
  static const String uiComposite = 'ui_composite';

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
