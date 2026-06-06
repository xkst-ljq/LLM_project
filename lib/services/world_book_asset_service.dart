import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/world_book.dart';
import '../utils/id_utils.dart';
import '../services/android_download_service.dart';
import '../services/database_service.dart';
import '../utils/asset_magic.dart';

class WorldBookAssetService {
  static const String magic = AssetMagic.assetV1;
  static const String assetType = AssetMagic.worldBook;
  static const int formatVersion = 1;

  static String _safeFileName(String input) {
    final value = input.trim().isEmpty ? '未命名世界书' : input.trim();
    return value
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String _timestampForFile() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Map<String, dynamic> _wrap(WorldBook wb) {
    return {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
      'payload': {
        'world_book': wb.toDb(),
      },
    };
  }

  static Future<File> exportWorldBook(WorldBook wb) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'world_books'));
    if (!dir.existsSync()) await dir.create(recursive: true);

    final fileName = '${_safeFileName(wb.name)}_${_timestampForFile()}.llmworld.json';
    final file = File(p.join(dir.path, fileName));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_wrap(wb)), flush: true);
    return file;
  }

  static Future<String?> saveWorldBookToDownloads(File file) {
    return AndroidDownloadService.saveFileToDownloads(
      sourcePath: file.path,
      fileName: file.uri.pathSegments.last,
      subDir: 'LLM Project/WorldBooks',
      mimeType: 'application/json',
    );
  }

  static Future<String> _uniqueWorldBookName(String baseName) async {
    final all = await DatabaseService.getAllWorldBooks();
    final names = all.map((e) => (e['name'] as String? ?? '').trim()).toSet();
    final normalized = baseName.trim().isEmpty ? '导入世界书' : baseName.trim();
    if (!names.contains(normalized)) return normalized;

    var index = 1;
    while (names.contains('$normalized ($index)')) {
      index++;
    }
    return '$normalized ($index)';
  }

  static Future<WorldBook> readWorldBookAsset(File file) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      throw Exception('文件不是有效的 JSON 世界书资产');
    }

    if (decoded is! Map) {
      throw Exception('世界书资产格式错误');
    }
    final root = Map<String, dynamic>.from(decoded);

    if (!AssetMagic.isSupportedAssetMagic(root['magic']?.toString()) ||
        root['asset_type'] != assetType) {
      throw Exception('未识别到 LLM Project 世界书标识');
    }

    final version = root['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('世界书资产版本过高，请升级 App 后再导入');
    }

    final payload = root['payload'];
    if (payload is! Map) {
      throw Exception('世界书资产数据缺失');
    }

    final wbRaw = payload['world_book'];
    if (wbRaw is! Map) {
      throw Exception('世界书数据缺失或损坏');
    }

    return WorldBook.fromDb(Map<String, dynamic>.from(wbRaw));
  }

  static Future<WorldBook> importWorldBook(File file) async {
    final wb = await readWorldBookAsset(file);
    final newId = IdUtils.timestampId();
    final newName = await _uniqueWorldBookName(wb.name);

    final imported = WorldBook(
      id: newId,
      name: newName,
      description: wb.description,
      detailedSetting: wb.detailedSetting,
      entriesJson: wb.entriesJson,
      coverImagePath: '', // 世界书当前无图形资产，导入时不恢复外部路径
      isPreset: false,
    );

    await DatabaseService.insertWorldBook(imported.toDb());
    return imported;
  }
}
