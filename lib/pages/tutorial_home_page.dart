import 'package:flutter/material.dart';

class TutorialHomePage extends StatelessWidget {
  final VoidCallback? onStartNewUserGuide;
  final VoidCallback? onStartSettingsGuide;

  const TutorialHomePage({
    super.key,
    this.onStartNewUserGuide,
    this.onStartSettingsGuide,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教程与导览'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.route_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '推荐路线',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '新用户快速导览会按推荐顺序串联多个页面导览。第一版先介绍主页和设置页，后续会继续接入 API 配置页、角色库和聊天页。',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onStartNewUserGuide == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            onStartNewUserGuide!();
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始新用户快速导览'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '页面导览',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _GuidePageTile(
            icon: Icons.home_outlined,
            title: '主页导览',
            subtitle: '聊天、角色库、世界书库、背景图库和侧滑设置页。',
            enabled: onStartNewUserGuide != null,
            onTap: onStartNewUserGuide == null
                ? null
                : () {
                    Navigator.pop(context);
                    onStartNewUserGuide!();
                  },
          ),
          _GuidePageTile(
            icon: Icons.settings_outlined,
            title: '设置页导览',
            subtitle: 'API 配置、用户设定、Prompt 策略、备份和教程入口。',
            enabled: onStartSettingsGuide != null,
            onTap: onStartSettingsGuide == null
                ? null
                : () {
                    Navigator.pop(context);
                    onStartSettingsGuide!();
                  },
          ),
          const _GuidePageTile(
            icon: Icons.api_outlined,
            title: 'API 配置页导览',
            subtitle: '后续接入：新增配置、测试连接、选择模型和保存。',
            enabled: false,
          ),
          const _GuidePageTile(
            icon: Icons.people_outline,
            title: '角色库导览',
            subtitle: '后续接入：角色列表、新建角色、编辑和导入。',
            enabled: false,
          ),
          const _GuidePageTile(
            icon: Icons.chat_outlined,
            title: '聊天页导览',
            subtitle: '后续接入：角色选择、输入框、发送按钮和聊天设置。',
            enabled: false,
          ),
        ],
      ),
    );
  }
}

class _GuidePageTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _GuidePageTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.play_circle_outline)
            : const Text('待加入', style: TextStyle(fontSize: 12)),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
