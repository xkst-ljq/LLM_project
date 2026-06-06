import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backup_service.dart';
import '../services/android_download_service.dart';
import '../utils/app_feedback.dart';

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

      final fileName = file.uri.pathSegments.last;

      final downloadsPath = await AndroidDownloadService.saveFileToDownloads(
        sourcePath: file.path,
        fileName: fileName,
        subDir: 'LLM Project/Backups',
        mimeType: 'application/octet-stream',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            downloadsPath != null
                ? '备份已保存到 Download/LLM Project/Backups'
                : '备份已导出到应用目录，可点击分享/保存',
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
              if (downloadsPath != null) ...[
                const Text('备份已保存到系统下载目录：'),
                const SizedBox(height: 8),
                SelectableText(
                  downloadsPath,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  '你可以在文件管理器的 Download / LLM Project / Backups 中找到它。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ] else ...[
                const Text('备份已生成到应用目录：'),
                const SizedBox(height: 8),
                SelectableText(
                  file.path,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  '如果你找不到该文件，请点击“分享/保存”导出到其他位置。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
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
      await AppFeedback.showErrorDialog(
        context,
        title: '导出失败',
        error: e,
        message: '备份导出过程中出现错误。',
        suggestion: '请检查剩余存储空间，或尝试重新导出。',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_busy) return;

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.any,
      allowMultiple: false,
    );

    if (picked == null || picked.files.isEmpty) return;

    final pickedFile = picked.files.single;
    final filePath = pickedFile.path;
    final fileName = pickedFile.name.toLowerCase();

    if (filePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件路径，请尝试将备份文件移动到下载目录后再导入')),
      );
      return;
    }

    if (!fileName.endsWith('.llmbak') && !fileName.endsWith('.zip')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择 .llmbak 备份文件')),
      );
      return;
    }

    if (!mounted) return;
    BackupImportMode selectedMode = BackupImportMode.merge;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('选择导入方式'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<BackupImportMode>(
                    groupValue: selectedMode,
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedMode = value;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<BackupImportMode>(
                          value: BackupImportMode.merge,
                          title: const Text('合并导入（推荐）'),
                          subtitle: const Text(
                            '生成新 ID，不覆盖当前数据。适合导入别人分享的备份或部分资源。',
                          ),
                        ),
                        RadioListTile<BackupImportMode>(
                          value: BackupImportMode.restore,
                          title: const Text('恢复导入'),
                          subtitle: const Text(
                            '保留原 ID，同 ID 数据会被覆盖。适合迁移自己的完整数据。',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '导入前建议先导出一次当前数据备份。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('继续'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await BackupService.importBackup(
        File(filePath),
        mode: selectedMode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedMode == BackupImportMode.merge
                ? '合并导入完成'
                : '恢复导入完成，建议返回主菜单后重新进入相关页面刷新数据',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showErrorDialog(
        context,
        title: '导入失败',
        error: e,
        message: '备份导入过程中出现错误。',
        suggestion: '请确认选择的是 LLM Project 导出的完整备份文件。如果文件来自聊天软件，请确认它没有被改名、截断或损坏。',
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '备份会自动保存到：Download / LLM Project / Backups。\n'
                      '如果系统下载目录保存失败，可在导出完成后点击“分享/保存”手动保存到其他位置。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
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
