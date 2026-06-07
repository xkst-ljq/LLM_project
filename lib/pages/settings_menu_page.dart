import 'package:flutter/material.dart';

import 'api_config_page.dart';
import 'backup_restore_page.dart';
import 'prompt_settings_page.dart';
import 'tutorial_home_page.dart';
import 'user_settings_page.dart';

class SettingsMenuPage extends StatelessWidget {
  final VoidCallback? onStartNewUserGuide;
  final VoidCallback? onStartSettingsGuide;
  final GlobalKey? apiConfigTileKey;
  final GlobalKey? userSettingsTileKey;
  final GlobalKey? promptSettingsTileKey;
  final GlobalKey? backupTileKey;
  final GlobalKey? tutorialTileKey;

  const SettingsMenuPage({
    super.key,
    this.onStartNewUserGuide,
    this.onStartSettingsGuide,
    this.apiConfigTileKey,
    this.userSettingsTileKey,
    this.promptSettingsTileKey,
    this.backupTileKey,
    this.tutorialTileKey,
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
              title: const Text('API 配置'),
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
              title: const Text('用户设定'),
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
              title: const Text('Prompt 策略'),
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
              title: const Text('备份与恢复'),
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
              title: const Text('教程与导览'),
              subtitle: const Text('页面导览、推荐路线与后续帮助内容'),
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
