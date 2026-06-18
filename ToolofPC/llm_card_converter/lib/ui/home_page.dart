import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/app_settings.dart';
import '../core/history_service.dart';
import '../core/png_chara_reader.dart';
import 'api_config_dialog.dart';
import 'workspace_page.dart';

/// 主页：选/拖入文件（支持多个、文件夹）→ 列表检查 → 开始转译。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<PickedCard> _picked = [];
  bool _dragging = false;
  List<HistoryEntry> _history = [];
  bool _apiConfigured = true; // 默认 true，避免加载前闪烁提示

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _refreshApiStatus();
  }

  Future<void> _loadHistory() async {
    final list = await HistoryService.getAll();
    if (!mounted) return;
    setState(() => _history = list);
  }

  Future<void> _refreshApiStatus() async {
    final c = await AppSettings.getApiConfig();
    if (!mounted) return;
    setState(() => _apiConfigured = c.isComplete);
  }

  bool _isCardFile(String path) {
    final e = path.toLowerCase();
    return e.endsWith('.png') || e.endsWith('.json');
  }

  List<String> _scanFolder(Directory dir) {
    final out = <String>[];
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File && _isCardFile(e.path)) out.add(e.path);
      }
    } catch (_) {}
    return out;
  }

  Future<void> _addPaths(List<String> paths) async {
    final files = <String>[];
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        files.addAll(_scanFolder(Directory(path)));
      } else if (_isCardFile(path)) {
        files.add(path);
      }
    }
    if (files.isEmpty) return;

    final existing = _picked.map((e) => e.name).toSet();
    final added = <PickedCard>[];
    for (final path in files) {
      try {
        final name = p.basename(path);
        if (existing.contains(name)) continue; // 去重（按文件名）
        final bytes = await File(path).readAsBytes();
        added.add(PickedCard(name, bytes));
        existing.add(name);
      } catch (_) {}
    }
    if (added.isEmpty || !mounted) return;
    setState(() => _picked.addAll(added));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'json'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    await _addPaths(paths);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择包含角色卡的文件夹',
    );
    if (dir == null) return;
    await _addPaths([dir]);
  }

  void _removeAt(int i) => setState(() => _picked.removeAt(i));
  void _clearAll() => setState(() => _picked.clear());

  Future<void> _startConvert() async {
    if (_picked.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkspacePage(cards: List.of(_picked)),
      ),
    );
    // 回来刷新历史记录
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          _addPaths(d.files.map((f) => f.path).toList());
        },
        child: Container(
          color: _dragging
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: _leftPanel()),
              const VerticalDivider(width: 1),
              Expanded(child: _historyArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leftPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_apiConfigured) ...[
            _apiWarningBanner(),
            const SizedBox(height: 12),
          ],
          _uploadButton(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('选择文件'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('文件夹'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _pickedList()),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _picked.isEmpty ? null : _clearAll,
                  child: const Text('清空'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _picked.isEmpty ? null : _startConvert,
                  child: Text(_picked.isEmpty
                      ? '开始转译'
                      : '开始转译（${_picked.length}）'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uploadButton() {
    return InkWell(
      onTap: _pickFiles,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          color: _dragging
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _dragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: _dragging ? 2 : 1,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file, size: 26),
              SizedBox(height: 6),
              Text('点击上传 / 拖入窗口（可多个、文件夹）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('支持 SillyTavern / TavernAI 的 PNG / JSON',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickedList() {
    if (_picked.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('待转译文件列表',
              style: TextStyle(color: Colors.black45, fontSize: 16)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Text('已选 ${_picked.length} 个',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _picked.length,
              itemBuilder: (context, i) {
                final c = _picked[i];
                return ListTile(
                  leading: _thumb(c),
                  title: Text(c.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _removeAt(i),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 列表缩略图：PNG 角色卡显示立绘，JSON 显示图标。
  Widget _thumb(PickedCard c) {
    final isPng = c.name.toLowerCase().endsWith('.png') &&
        PngCharaReader.isPng(c.bytes);
    if (isPng) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          Uint8List.fromList(c.bytes),
          width: 36,
          height: 48,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _thumbFallback(true),
        ),
      );
    }
    return _thumbFallback(false);
  }

  Widget _thumbFallback(bool isPng) {
    return Container(
      width: 36,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        isPng ? Icons.image_outlined : Icons.description_outlined,
        size: 18,
        color: Colors.white70,
      ),
    );
  }

  Widget _historyArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: 8),
              const Text('历史转译记录',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_history.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await _confirmClear();
                    if (ok) {
                      await HistoryService.clear();
                      _loadHistory();
                    }
                  },
                  child: const Text('清空'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _history.isEmpty
              ? Center(
            child: Text('暂无历史记录',
                style: TextStyle(color: Theme.of(context).disabledColor)),
          )
              : ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _history.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _historyTile(_history[i]),
          ),
        ),
      ],
    );
  }

  Widget _historyTile(HistoryEntry e) {
    final hasThumb = e.thumbPath.isNotEmpty && File(e.thumbPath).existsSync();
    return ListTile(
      leading: hasThumb
          ? ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(File(e.thumbPath),
            width: 36, height: 48, fit: BoxFit.cover,
            gaplessPlayback: true),
      )
          : Container(
        width: 36,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.description_outlined,
            size: 18, color: Colors.white70),
      ),
      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtTime(e.time),
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 3),
          Row(
            children: [
              _tag(e.success ? '成功' : '失败',
                  e.success ? Colors.green : Colors.red),
              const SizedBox(width: 6),
              _tag(e.saved ? '已保存' : '未保存',
                  e.saved ? Colors.blue : Colors.grey),
            ],
          ),
          if (e.saved && e.savedPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(e.savedPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black38)),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        tooltip: '删除记录',
        onPressed: () async {
          await HistoryService.remove(e.id);
          _loadHistory();
        },
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  Future<bool> _confirmClear() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定清空所有历史记录吗？（不影响已导出的角色卡文件）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    return r ?? false;
  }

  Widget _apiWarningBanner() {
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openSettings,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade800, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('尚未配置 AI',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900)),
                    const SizedBox(height: 2),
                    Text(
                      '当前仅能进行规则转译，无法智能归类与检查。点击前往配置。',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.orange.shade800),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final dir = await AppSettings.getOutputDir();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _SettingsDialog(initialDir: dir),
    );
    // 设置可能改了 API，刷新提醒状态
    _refreshApiStatus();
  }
}

/// 设置弹窗：默认转译保存位置 + AI 配置。
class _SettingsDialog extends StatefulWidget {
  final String initialDir;
  const _SettingsDialog({required this.initialDir});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late String _dir = widget.initialDir;
  String _apiSummary = '配置 AI';

  @override
  void initState() {
    super.initState();
    _refreshApiSummary();
  }

  Future<void> _refreshApiSummary() async {
    final c = await AppSettings.getApiConfig();
    if (!mounted) return;
    setState(() {
      _apiSummary = c.isComplete ? '已配置：${c.model}' : '配置 AI';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('默认转译保存位置',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('设置后，转译完成将直接保存到此目录（批量转译也不再逐次询问）。',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _dir.isEmpty ? '（未设置 · 首次保存时会询问）' : _dir,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择目录'),
                  onPressed: () async {
                    final picked = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: '选择默认转译保存位置',
                    );
                    if (picked == null) return;
                    await AppSettings.setOutputDir(picked);
                    if (!mounted) return;
                    setState(() => _dir = picked);
                  },
                ),
                const SizedBox(width: 8),
                if (_dir.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await AppSettings.clearOutputDir();
                      if (!mounted) return;
                      setState(() => _dir = '');
                    },
                    child: const Text('清除'),
                  ),
              ],
            ),
            const Divider(height: 32),
            const Text('AI 配置', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('用于第二步「AI 智能归类」与第三步「检查精修」。',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(_apiSummary),
                  onPressed: () async {
                    final saved = await ApiConfigDialog.show(context);
                    if (saved == true) _refreshApiSummary();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
