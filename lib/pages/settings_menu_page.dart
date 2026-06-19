import 'package:flutter/material.dart';

import 'api_config_page.dart';
import 'backup_restore_page.dart';
import 'character_converter_page.dart';
import 'prompt_settings_page.dart';
import 'tutorial_home_page.dart';
import 'ui_studio_page.dart';
import 'user_settings_page.dart';


class SettingsMenuPage extends StatelessWidget {
  final VoidCallback? onStartNewUserGuide;
  final VoidCallback? onStartSettingsGuide;
  final GlobalKey? apiConfigTileKey;
  final GlobalKey? userSettingsTileKey;
  final GlobalKey? promptSettingsTileKey;
  final GlobalKey? backupTileKey;
  final GlobalKey? tutorialTileKey;
  final GlobalKey? apiConfigTextKey;
  final GlobalKey? userSettingsTextKey;
  final GlobalKey? promptSettingsTextKey;
  final GlobalKey? backupTextKey;
  final GlobalKey? tutorialTextKey;

  const SettingsMenuPage({
    super.key,
    this.onStartNewUserGuide,
    this.onStartSettingsGuide,
    this.apiConfigTileKey,
    this.userSettingsTileKey,
    this.promptSettingsTileKey,
    this.backupTileKey,
    this.tutorialTileKey,
    this.apiConfigTextKey,
    this.userSettingsTextKey,
    this.promptSettingsTextKey,
    this.backupTextKey,
    this.tutorialTextKey,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '设置',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const Divider(),
          Container(
            key: apiConfigTileKey,
            child: ListTile(
              leading: const Icon(Icons.api),
              title: Text('API 配置', key: apiConfigTextKey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ApiConfigPage()),
                );
              },
            ),
          ),
          Container(
            key: userSettingsTileKey,
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text('用户设定', key: userSettingsTextKey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserSettingsPage()),
                );
              },
            ),
          ),
          Container(
            key: promptSettingsTileKey,
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text('Prompt 策略', key: promptSettingsTextKey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PromptSettingsPage()),
                );
              },
            ),
          ),
          Container(
            key: backupTileKey,
            child: ListTile(
              leading: const Icon(Icons.backup),
              title: Text('备份与恢复', key: backupTextKey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackupRestorePage()),
                );
              },
            ),
          ),
          Container(
            key: tutorialTileKey,
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text('教程与导览', key: tutorialTextKey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TutorialHomePage(
                      onStartNewUserGuide: onStartNewUserGuide,
                      onStartSettingsGuide: onStartSettingsGuide,
                    ),
                  ),
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.transform),
            title: const Text('角色卡转换工具'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CharacterConverterPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('UI 创作工作室'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UIStudioPage(),
                ),
              );
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('关于'),
          ),
        ],
      ),
    );
  }
}
