import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
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
  static const String pngContainer = 'png_card';
  static const int formatVersion = 1;

  // 与 CharacterCardPngAssetService 完全一致的图片角色卡标记
  static final List<int> _pngStartMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_START---\n');
  static final List<int> _pngEndMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_END---\n');

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

  /// 把转换结果写成图片角色卡（.llmchar.png）。
  ///
  /// 格式与 CharacterCardPngAssetService 完全一致：
  ///   [PNG 图片字节] + 起始标记 + base64(payload JSON) + 结束标记
  /// 优点：在文件管理器里能直接看到角色立绘缩略图，比 .llmcard 直观。
  /// 仅当结果带有封面图（imageBytes）时可用。
  static Future<File> writeLlmCharPng(
      CardConversionResult result, {
        required Directory outputDir,
      }) async {
    if (!result.success || result.characterData == null) {
      throw StateError('该结果不可导出（转换失败）。');
    }
    final imageBytes = result.imageBytes;
    if (imageBytes == null || imageBytes.isEmpty) {
      throw StateError('该结果没有封面图，无法导出为图片角色卡。');
    }
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }

    // 重新编码为标准 PNG，保证产物是合法 PNG 图片
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw Exception('无法读取角色封面图片');
    }
    final pngBytes = img.encodePng(decoded);

    final character = Map<String, dynamic>.from(result.characterData!);
    // 图片卡本身即封面，导入时会重建路径
    character['card_image_path'] = '';
    character['avatar'] = '';

    final hasWorldBook = result.worldBooks.isNotEmpty;
    final worldBooks = hasWorldBook
        ? result.worldBooks
        .map((e) => Map<String, dynamic>.from(e)
      ..['cover_image_path'] = ''
      ..['is_preset'] = 0)
        .toList()
        : <Map<String, dynamic>>[];
    character['world_book_id'] =
    hasWorldBook ? worldBooks.first['id'] : '';

    final root = {
      'magic': magic,
      'asset_type': assetType,
      'container': pngContainer,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project Converter',
      'source_format': result.format.label,
      'contains': {
        'user_override': false,
        'world_book': hasWorldBook,
      },
      'payload': {
        'character': character,
        'dependencies': {'world_books': worldBooks},
      },
    };

    final payloadBase64 = base64Encode(utf8.encode(jsonEncode(root)));

    final outputBytes = <int>[
      ...pngBytes,
      ..._pngStartMarker,
      ...utf8.encode(payloadBase64),
      ..._pngEndMarker,
    ];

    final fileName = '${safeFileName(result.characterName)}.llmchar.png';
    final file = File(p.join(outputDir.path, _uniqueName(outputDir, fileName)));
    await file.writeAsBytes(outputBytes, flush: true);
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
          // 有封面图 → 输出图片角色卡(.llmchar.png)，文件管理器可直接看缩略图；
          // 无封面图 → 回退为 .llmcard。
          if (r.imageBytes != null && r.imageBytes!.isNotEmpty) {
            try {
              await writeLlmCharPng(r, outputDir: outDir);
            } catch (_) {
              await writeLlmCard(r, outputDir: outDir);
            }
          } else {
            await writeLlmCard(r, outputDir: outDir);
          }
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
