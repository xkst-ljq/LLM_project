import 'package:flutter/material.dart';
import 'api_config_page.dart';
import 'user_settings_page.dart';
import 'backup_restore_page.dart';
import 'export_path_settings_page.dart';

class SettingsMenuPage extends StatelessWidget {
  const SettingsMenuPage({super.key});

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
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API 配置'),        // 改名为 API 配置
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ApiConfigPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('用户设定'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserSettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('备份与恢复'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackupRestorePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('导出位置设置'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExportPathSettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('帮助与使用说明'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('帮助'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '1. 在「API 配置」中选择或添加 API 服务商。\n'
                          '2. 填写 API Key（需要自行获取）。\n'
                          '3. 测试连接以获取可用模型列表。\n'
                          '4. 保存后即可开始对话。\n\n'
                          '免费 API 推荐：SiliconFlow 提供免费 Qwen 模型，'
                          '访问 siliconflow.cn 注册并获取 Key。',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('知道了'),
                    ),
                  ],
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