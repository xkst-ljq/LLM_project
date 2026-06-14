import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../utils/asset_magic.dart';
import 'conversion_models.dart';

/// 把转换结果写成 LLM Project 角色卡文件（.llmcard）以及转换报告。
///
/// 输出的 .llmcard 与 CharacterCardAssetService 的格式完全一致：
///   manifest.json / data/character.json /
///   data/dependencies/world_books.json / assets/*
/// 因此可被现有 App 的「导入角色卡」直接识别。
///
/// 使用 dart:io，可在桌面端与移动端运行（不依赖 path_provider）。
class ConversionWriter {
  static const String magic = AssetMagic.assetV1;
  static const String assetType = AssetMagic.characterCard;
  static const int formatVersion = 1;

  static String safeFileName(String input) {
    final value = input.trim().isEmpty ? '未命名角色卡' : input.trim();
    return value
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String timestampForDir([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static void _addJson(Archive archive, String path, Object? data) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  /// 将单个转换结果写为 .llmcard 文件。返回写入的文件。
  static Future<File> writeLlmCard(
    CardConversionResult result, {
    required Directory outputDir,
  }) async {
    if (!result.success || result.characterData == null) {
      throw StateError('该结果不可导出（转换失败）。');
    }
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }

    final archive = Archive();
    final character = Map<String, dynamic>.from(result.characterData!);

    final hasWorldBook = result.worldBooks.isNotEmpty;

    // manifest
    _addJson(archive, 'manifest.json', {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project Converter',
      'source_format': result.format.label,
      'contains': {
        'user_override': false,
        'world_book': hasWorldBook,
      },
    });

    // 角色图：作为 card_image + avatar 一并嵌入
    if (result.imageBytes != null && result.imageBytes!.isNotEmpty) {
      archive.addFile(ArchiveFile(
        'assets/card_image.png',
        result.imageBytes!.length,
        result.imageBytes!,
      ));
      archive.addFile(ArchiveFile(
        'assets/avatar.png',
        result.imageBytes!.length,
        result.imageBytes!,
      ));
      character['card_image_path'] = 'assets/card_image.png';
      character['avatar'] = 'assets/avatar.png';
    } else {
      character['card_image_path'] = '';
      character['avatar'] = '';
    }

    // 世界书依赖
    if (hasWorldBook) {
      final wbs = result.worldBooks
          .map((e) => Map<String, dynamic>.from(e)
            ..['cover_image_path'] = ''
            ..['is_preset'] = 0)
          .toList();
      _addJson(archive, 'data/dependencies/world_books.json', wbs);
      // 角色绑定第一本世界书（导入流程会重映射 id）
      character['world_book_id'] = wbs.first['id'];
    } else {
      character['world_book_id'] = '';
    }

    _addJson(archive, 'data/character.json', character);

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw Exception('角色卡压缩失败');

    final fileName = '${safeFileName(result.characterName)}.llmcard';
    final file = File(p.join(outputDir.path, _uniqueName(outputDir, fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 批量写入：在 [baseDir] 下新建时间戳子目录，写入所有成功结果 + 报告。
  /// 返回创建的输出目录。
  static Future<Directory> writeBatch(
    BatchConversionReport report, {
    required Directory baseDir,
  }) async {
    final outDir = Directory(
      p.join(baseDir.path, 'Converted Cards', timestampForDir()),
    );
    await outDir.create(recursive: true);

    for (final r in report.results) {
      if (r.success && r.characterData != null) {
        try {
          await writeLlmCard(r, outputDir: outDir);
        } catch (_) {
          // 单卡写入失败不影响其他卡，报告里仍保留状态
        }
      }
    }

    // 写报告
    final reportJson = File(p.join(outDir.path, 'conversion_report.json'));
    await reportJson.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );
    final reportTxt = File(p.join(outDir.path, 'conversion_report.txt'));
    await reportTxt.writeAsString(report.toPlainText(), flush: true);

    return outDir;
  }

  static String _uniqueName(Directory dir, String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = fileName;
    var i = 1;
    while (File(p.join(dir.path, candidate)).existsSync()) {
      candidate = '$base ($i)$ext';
      i++;
    }
    return candidate;
  }
}
