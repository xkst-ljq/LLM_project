import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../tools/character_converter/conversion_models.dart';
import '../tools/character_converter/conversion_service.dart';
import '../tools/character_converter/conversion_writer.dart';

/// 第三方角色卡转换工具页。
///
/// - 桌面端：支持拖入文件 / 文件夹，自动识别 PNG / JSON 并批量转换；
/// - 移动端：通过文件选择器多选文件转换。
///
/// 转换结果写为 .llmcard（可被本应用「导入角色卡」识别）+ 转换报告。
class CharacterConverterPage extends StatefulWidget {
  const CharacterConverterPage({super.key});

  @override
  State<CharacterConverterPage> createState() => _CharacterConverterPageState();
}

class _CharacterConverterPageState extends State<CharacterConverterPage> {
  bool _dragging = false;
  bool _busy = false;
  BatchConversionReport? _report;
  Directory? _outputDir;
  String? _message;

  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  // 支持的输入扩展名
  static const _exts = ['png', 'json'];

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _exts,
      withData: false,
    );
    if (result == null) return;
    final paths =
        result.files.map((f) => f.path).whereType<String>().toList();
    await _convertPaths(paths);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final paths = _scanFolder(Directory(dir));
    if (paths.isEmpty) {
      setState(() => _message = '该文件夹中没有找到 PNG / JSON 角色卡。');
      return;
    }
    await _convertPaths(paths);
  }

  List<String> _scanFolder(Directory dir) {
    final out = <String>[];
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          final ext = p.extension(e.path).toLowerCase();
          if (ext == '.png' || ext == '.json') out.add(e.path);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _onDrop(List<String> paths) async {
    final files = <String>[];
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        files.addAll(_scanFolder(Directory(path)));
      } else if (type == FileSystemEntityType.file) {
        final ext = p.extension(path).toLowerCase();
        if (ext == '.png' || ext == '.json') files.add(path);
      }
    }
    if (files.isEmpty) {
      setState(() => _message = '拖入的内容里没有可识别的 PNG / JSON 角色卡。');
      return;
    }
    await _convertPaths(files);
  }

  Future<void> _convertPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      // 读字节
      final inputs = <({String name, List<int> bytes})>[];
      for (final path in paths) {
        try {
          final bytes = await File(path).readAsBytes();
          inputs.add((name: p.basename(path), bytes: bytes));
        } catch (e) {
          // 读不了的文件单独记一条失败
          inputs.add((name: p.basename(path), bytes: const []));
        }
      }

      // 在后台线程转换（纯 Dart，可 compute）
      final report = await compute(_convertInIsolate, inputs);

      // 写出
      final baseDir = await _resolveOutputBaseDir();
      final outDir = await ConversionWriter.writeBatch(report, baseDir: baseDir);

      if (!mounted) return;
      setState(() {
        _report = report;
        _outputDir = outDir;
        _message = '转换完成：成功 ${report.successCount} / ${report.total}，'
            '已保存到：\n${outDir.path}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '转换失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Directory> _resolveOutputBaseDir() async {
    if (_isDesktop) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(p.join(downloads.path, 'LLM Project'));
      }
    }
    // 移动端 / 兜底：应用文档目录
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'LLM Project'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色卡转换工具'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDropZone(context),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickFiles,
                    icon: const Icon(Icons.insert_drive_file_outlined),
                    label: const Text('选择文件'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件夹'),
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_message!),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildDropZone(BuildContext context) {
    final inner = Container(
      height: 140,
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
      child: Center(
        child: _busy
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在转换…'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.move_to_inbox_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    _isDesktop
                        ? '把 SillyTavern / TavernAI 角色卡或文件夹拖到这里'
                        : '点击下方按钮选择角色卡文件',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '支持 PNG 角色卡 与 JSON（V1 / V2）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );

    if (!_isDesktop) return inner;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _onDrop(detail.files.map((f) => f.path).toList());
      },
      child: inner,
    );
  }

  Widget _buildResults(BuildContext context) {
    final report = _report;
    if (report == null) {
      return Center(
        child: Text(
          '转换结果会显示在这里。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.separated(
      itemCount: report.results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = report.results[i];
        final color = !r.success
            ? Colors.red
            : (r.partial ? Colors.orange : Colors.green);
        final icon = !r.success
            ? Icons.error_outline
            : (r.partial ? Icons.warning_amber_outlined : Icons.check_circle_outline);
        return ExpansionTile(
          leading: Icon(icon, color: color),
          title: Text(r.success ? r.characterName : r.sourceName),
          subtitle: Text(
            '${r.format.label}'
            '${r.success ? (r.partial ? " · 成功（部分降级）" : " · 成功") : " · 失败"}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            if (r.convertedFields.isNotEmpty)
              _kv('已转换', r.convertedFields.join('、')),
            if (r.unsupportedFields.isNotEmpty)
              _kv('未支持/降级', r.unsupportedFields.join('、')),
            if (r.worldBooks.isNotEmpty)
              _kv('内嵌世界书', '${r.worldBooks.length} 本'),
            for (final n in r.notes) _kv(_noteTag(n.level), n.message),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(k,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  String _noteTag(ConversionNoteLevel l) => switch (l) {
        ConversionNoteLevel.info => '提示',
        ConversionNoteLevel.warning => '注意',
        ConversionNoteLevel.error => '错误',
      };
}

/// 在隔离线程中执行批量转换（纯 Dart，可序列化）。
BatchConversionReport _convertInIsolate(
  List<({String name, List<int> bytes})> inputs,
) {
  return CharacterConversionService.convertBatch(inputs);
}
