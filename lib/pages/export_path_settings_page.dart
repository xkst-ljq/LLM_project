import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/export_path_service.dart';

class ExportPathSettingsPage extends StatefulWidget {
  const ExportPathSettingsPage({super.key});

  @override
  State<ExportPathSettingsPage> createState() => _ExportPathSettingsPageState();
}

class _ExportPathSettingsPageState extends State<ExportPathSettingsPage> {
  final Map<ExportTargetType, String?> _paths = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paths = await ExportPathService.getAllPaths();
    if (!mounted) return;
    setState(() {
      _paths
        ..clear()
        ..addAll(paths);
    });
  }

  Future<void> _pickPath(ExportTargetType type) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择${ExportPathService.labelOf(type)}导出位置',
    );
    if (path == null || path.isEmpty) return;
    await ExportPathService.setPath(type, path);
    await _load();
  }

  Future<void> _clearPath(ExportTargetType type) async {
    await ExportPathService.clearPath(type);
    await _load();
  }

  bool _pathAvailable(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出位置设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '不同类型的导出可以使用不同位置。Android 10 及以上可能限制直接写入公共目录；如果所选目录不可写，应用会自动导出到私有目录，并提供“分享/保存”按钮。',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          ...ExportTargetType.values.map((type) {
            final path = _paths[type];
            final ok = _pathAvailable(path);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(ok ? Icons.folder : Icons.folder_off),
                title: Text('${ExportPathService.labelOf(type)}导出位置'),
                subtitle: Text(
                  path == null || path.isEmpty
                      ? '未设置，将使用默认位置'
                      : ok
                          ? path
                          : '$path\n路径不可用，将使用默认位置',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: path != null && path.isNotEmpty && !ok,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '选择',
                      icon: const Icon(Icons.drive_folder_upload),
                      onPressed: () => _pickPath(type),
                    ),
                    IconButton(
                      tooltip: '清除',
                      icon: const Icon(Icons.clear),
                      onPressed: path == null || path.isEmpty
                          ? null
                          : () => _clearPath(type),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
