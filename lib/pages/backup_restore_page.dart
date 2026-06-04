import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backup_service.dart';
import '../services/export_path_service.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final BackupOptions _options = BackupOptions();
  bool _busy = false;
  String? _lastExportPath;

  Future<void> _exportBackup() async {
    if (_busy) return;

    if (_options.includeApiKeys || _options.includeChatHistory) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('敏感数据提醒'),
          content: Text(
            '${_options.includeApiKeys ? '此备份将包含 API Key。\n' : ''}'
            '${_options.includeChatHistory ? '此备份将包含聊天记录。\n' : ''}'
            '请不要把包含敏感数据的备份分享给他人。是否继续？',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      final result = await BackupService.exportBackup(_options);
      final file = result.file;

      _lastExportPath = file.path;

      if (!mounted) return;

      final usedFallback = result.requestedDirectory != null &&
          result.requestedDirectory!.isNotEmpty &&
          !result.usedCustomDirectory;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usedFallback
                ? '自定义目录不可写，已导出到应用目录'
                : '备份已导出',
          ),
        ),
      );

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (usedFallback) ...[
                const Text(
                  '你设置的自定义导出目录当前不可写，备份已自动保存到应用目录。',
                  style: TextStyle(color: Colors.orange),
                ),
                const SizedBox(height: 8),
                const Text(
                  '你可以点击“分享/保存”，通过系统面板保存到文件管理器、网盘或其他位置。',
                ),
                const SizedBox(height: 12),
              ] else ...[
                const Text('备份文件已生成：'),
                const SizedBox(height: 8),
              ],
              SelectableText(
                file.path,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Share.shareXFiles(
                  [XFile(file.path)],
                  text: 'LLM Project 备份',
                );
              },
              child: const Text('分享/保存'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busy) return;

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: ['llmbak', 'zip'],
    );
    if (picked == null || picked.files.single.path == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: const Text(
          '当前版本采用“同 ID 覆盖 / 不同 ID 合并”的导入策略。\n\n'
          '导入前建议先导出一次当前数据备份。是否继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await BackupService.importBackup(File(picked.files.single.path!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入完成，建议返回主菜单后重新进入相关页面刷新数据')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _switchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool sensitive = false,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          color: sensitive && value ? Colors.red : null,
          fontWeight: sensitive && value ? FontWeight.w600 : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '完整备份用于换包名、换手机或重装迁移。角色卡/背景卡的图片式分享建议后续单独在各自库内实现。',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              _sectionTitle('基础数据'),
              _switchTile(
                title: '角色卡',
                value: _options.includeCharacters,
                onChanged: (v) => _options.includeCharacters = v,
              ),
              _switchTile(
                title: '世界书',
                value: _options.includeWorldBooks,
                onChanged: (v) => _options.includeWorldBooks = v,
              ),
              _switchTile(
                title: '背景图库',
                value: _options.includeBackgrounds,
                onChanged: (v) => _options.includeBackgrounds = v,
              ),
              _switchTile(
                title: '图片资源',
                subtitle: '包含角色头像、角色封面、背景图等。',
                value: _options.includeImages,
                onChanged: (v) => _options.includeImages = v,
              ),
              _sectionTitle('个人数据'),
              _switchTile(
                title: '全局用户设定',
                value: _options.includeUserProfile,
                onChanged: (v) => _options.includeUserProfile = v,
              ),
              _switchTile(
                title: '当前角色用户覆盖设定',
                subtitle: '通常不建议分享；迁移自己的完整数据时可开启。',
                value: _options.includeRoleUserOverrides,
                onChanged: (v) => _options.includeRoleUserOverrides = v,
              ),
              _switchTile(
                title: '聊天记录',
                subtitle: '可能包含隐私内容，默认不导出。',
                value: _options.includeChatHistory,
                onChanged: (v) => _options.includeChatHistory = v,
                sensitive: true,
              ),
              _sectionTitle('API 数据'),
              _switchTile(
                title: 'API 配置',
                subtitle: '包含配置名、Base URL、模型名。',
                value: _options.includeApiConfigs,
                onChanged: (v) => _options.includeApiConfigs = v,
              ),
              _switchTile(
                title: 'API Key',
                subtitle: '敏感信息，只有迁移自己的数据时才建议开启。',
                value: _options.includeApiKeys,
                onChanged: (v) => _options.includeApiKeys = v,
                sensitive: true,
              ),
              _sectionTitle('其他'),
              _switchTile(
                title: '排序和界面偏好',
                value: _options.includePreferences,
                onChanged: (v) => _options.includePreferences = v,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _exportBackup,
                icon: const Icon(Icons.upload_file),
                label: const Text('导出备份'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importBackup,
                icon: const Icon(Icons.download),
                label: const Text('导入备份'),
              ),
              if (_lastExportPath != null) ...[
                const SizedBox(height: 12),
                Text('上次导出：$_lastExportPath', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
              const SizedBox(height: 24),
              FutureBuilder<String?>(
                future: ExportPathService.getPath(ExportTargetType.backup),
                builder: (context, snapshot) {
                  final path = snapshot.data;
                  return Text(
                    path == null || path.isEmpty
                        ? '当前未设置完整备份导出位置，将使用应用默认目录。'
                        : '完整备份导出位置：$path',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  );
                },
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.18),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
