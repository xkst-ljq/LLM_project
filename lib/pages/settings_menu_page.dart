import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';
import '../widgets/sub_page_backdrop.dart';
import 'api_config_page.dart';
import 'backup_restore_page.dart';
import 'prompt_settings_page.dart';
import 'tutorial_home_page.dart';
import 'ui_studio_page/ui_studio_page.dart';
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

  /// 玻璃分组卡片：一组设置项 + 可选组标题。
  Widget _groupCard(BuildContext context, {String? title, required List<Widget> items}) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ],
          SubPageBlurBackdrop(
            child: Column(children: items),
          ),
        ],
      ),
    );
  }

  /// 带图标色块的设置项。
  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Key? tileKey,
    Key? textKey,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final tokens = AppThemeTokens.of(context);
    return InkWell(
      key: tileKey,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: tokens.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: textKey,
                    style: TextStyle(
                      fontSize: 14,
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null && trailing == null)
              Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // 连接与数据
            _groupCard(
              context,
              title: '连接与数据',
              items: [
                _tile(
                  context,
                  tileKey: apiConfigTileKey,
                  textKey: apiConfigTextKey,
                  icon: Icons.api,
                  title: 'API 配置',
                  subtitle: '服务地址与密钥',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ApiConfigPage()),
                    );
                  },
                ),
                _tile(
                  context,
                  tileKey: backupTileKey,
                  textKey: backupTextKey,
                  icon: Icons.backup,
                  title: '备份与恢复',
                  subtitle: '导出与导入全部数据',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
                    );
                  },
                ),
              ],
            ),

            // 角色与内容
            _groupCard(
              context,
              title: '角色与内容',
              items: [
                _tile(
                  context,
                  tileKey: userSettingsTileKey,
                  textKey: userSettingsTextKey,
                  icon: Icons.person,
                  title: '用户设定',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UserSettingsPage()),
                    );
                  },
                ),
                _tile(
                  context,
                  tileKey: promptSettingsTileKey,
                  textKey: promptSettingsTextKey,
                  icon: Icons.tune,
                  title: 'Prompt 策略',
                  subtitle: '注入与分频策略',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PromptSettingsPage()),
                    );
                  },
                ),
              ],
            ),

            // 外观与创作
            _groupCard(
              context,
              title: '外观与创作',
              items: [
                _tile(
                  context,
                  icon: Icons.palette,
                  title: 'UI 创作工作室',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UIStudioPage(),
                      ),
                    );
                  },
                ),
                _tile(
                  context,
                  tileKey: tutorialTileKey,
                  textKey: tutorialTextKey,
                  icon: Icons.school_outlined,
                  title: '教程与导览',
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
              ],
            ),

            // 关于
            _groupCard(
              context,
              items: [
                _tile(
                  context,
                  icon: Icons.info,
                  title: '关于',
                  subtitle: 'LLM Project',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
