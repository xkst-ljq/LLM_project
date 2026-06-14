import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/id_utils.dart';
import '../models/character_card.dart';
import '../services/android_download_service.dart';
import '../services/database_service.dart';
import '../utils/asset_magic.dart';

class CharacterCardAssetService {
  static const String magic = AssetMagic.assetV1;
  static const String assetType = AssetMagic.characterCard;
  static const int formatVersion = 1;

  static String _safeFileName(String input) {
    final value = input.trim().isEmpty ? '未命名角色卡' : input.trim();
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

  static void _addText(Archive archive, String path, Object? data) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static Future<Map<String, dynamic>> readCharacterCardData(File file) async {
    final files = await _extractArchive(file);

    final manifest = _readJson(files, 'manifest.json');
    if (manifest is! Map) {
      throw Exception('未识别到角色卡标识');
    }

    if (!AssetMagic.isSupportedAssetMagic(manifest['magic']?.toString()) ||
        manifest['asset_type'] != assetType) {
      throw Exception('这不是 LLM Project 角色卡文件');
    }

    final version = manifest['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('角色卡版本过高，请升级 App 后再导入');
    }

    final rawCharacter = _readJson(files, 'data/character.json');
    if (rawCharacter is! Map) {
      throw Exception('角色卡数据缺失或损坏');
    }

    final worldBooks = _readJson(files, 'data/dependencies/world_books.json');

    return {
      'container': 'llmcard',
      'manifest': Map<String, dynamic>.from(manifest),
      'character': Map<String, dynamic>.from(rawCharacter),
      'world_books': worldBooks is List
          ? worldBooks.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[],
    };
  }

  static Future<String> _addAssetIfExists({
    required Archive archive,
    required String sourcePath,
    required String archivePath,
  }) async {
    if (sourcePath.trim().isEmpty) return '';

    final file = File(sourcePath);
    if (!file.existsSync()) return '';

    try {
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      return archivePath;
    } catch (e) {
      debugPrint('添加角色卡资源失败: $sourcePath $e');
      return '';
    }
  }

  static Future<Map<String, dynamic>?> _findWorldBookRaw(String id) async {
    if (id.trim().isEmpty) return null;

    final all = await DatabaseService.getAllWorldBooks();
    for (final wb in all) {
      if (wb['id'] == id) {
        return Map<String, dynamic>.from(wb);
      }
    }
    return null;
  }

  static Future<String> _uniqueCharacterName(String baseName) async {
    final all = await DatabaseService.getAllCharacters();
    final names = all.map((e) => (e['name'] as String? ?? '').trim()).toSet();

    final normalized = baseName.trim().isEmpty ? '导入角色卡' : baseName.trim();
    if (!names.contains(normalized)) return normalized;

    var index = 1;
    while (names.contains('$normalized ($index)')) {
      index++;
    }
    return '$normalized ($index)';
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

  static Map<String, dynamic> _characterToExportMap(
      CharacterCard character, {
        required String avatarAssetPath,
        required String cardImageAssetPath,
        required bool includeUserOverride,
        required String userAvatarAssetPath,
        required bool includeBoundWorldBook,
      }) {
    return {
      'id': character.id,
      'name': character.name,
      'avatar': avatarAssetPath,
      'card_image_path': cardImageAssetPath,
      'description': character.description,
      'system_prompt': character.systemPrompt,

      // 如果不包含世界书依赖，就不要保留 world_book_id，避免导入后出现无效绑定
      'world_book_id':
      includeBoundWorldBook ? character.worldBookId : '',

      // 背景是本地环境资源，角色卡分享第一版先不绑定背景
      'background_id': '',

      'card_type': character.cardType,
      'entries_json': character.entriesJson,
      'opening_greetings': character.openingGreetings,
      'meta_json': character.metaJson,

      // 默认不导出当前用户覆盖设定，避免分享个人信息
      'user_name': includeUserOverride ? character.userName : '',
      'user_avatar': includeUserOverride ? userAvatarAssetPath : '',
      'user_detail_setting':
      includeUserOverride ? character.userDetailSetting : '',
    };
  }

  static Future<File> exportCharacterCard({
    required CharacterCard character,
    bool includeUserOverride = false,
    bool includeBoundWorldBook = false,
  }) async {
    final archive = Archive();

    final manifest = {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
      'contains': {
        'user_override': includeUserOverride,
        'world_book': includeBoundWorldBook &&
            character.worldBookId.trim().isNotEmpty,
      },
    };

    _addText(archive, 'manifest.json', manifest);

    final cardImageExt = p.extension(character.cardImagePath).isEmpty
        ? '.png'
        : p.extension(character.cardImagePath);

    final cardImageAssetPath = await _addAssetIfExists(
      archive: archive,
      sourcePath: character.cardImagePath,
      archivePath: 'assets/card_image$cardImageExt',
    );

    final avatarExt = p.extension(character.avatar).isEmpty
        ? '.png'
        : p.extension(character.avatar);

    final avatarAssetPath = await _addAssetIfExists(
      archive: archive,
      sourcePath: character.avatar,
      archivePath: 'assets/avatar$avatarExt',
    );

    String userAvatarAssetPath = '';
    if (includeUserOverride) {
      final userAvatarExt = p.extension(character.userAvatar).isEmpty
          ? '.png'
          : p.extension(character.userAvatar);

      userAvatarAssetPath = await _addAssetIfExists(
        archive: archive,
        sourcePath: character.userAvatar,
        archivePath: 'assets/user_avatar$userAvatarExt',
      );
    }

    final shouldIncludeWorldBook =
        includeBoundWorldBook && character.worldBookId.trim().isNotEmpty;

    if (shouldIncludeWorldBook) {
      final wb = await _findWorldBookRaw(character.worldBookId);
      if (wb != null) {
        // 世界书目前无图形资产，直接 JSON 内嵌
        wb['cover_image_path'] = '';
        wb['is_preset'] = 0;

        _addText(
          archive,
          'data/dependencies/world_books.json',
          [wb],
        );
      }
    }

    final characterJson = _characterToExportMap(
      character,
      avatarAssetPath: avatarAssetPath,
      cardImageAssetPath: cardImageAssetPath,
      includeUserOverride: includeUserOverride,
      userAvatarAssetPath: userAvatarAssetPath,
      includeBoundWorldBook: shouldIncludeWorldBook,
    );

    _addText(archive, 'data/character.json', characterJson);

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw Exception('角色卡压缩失败');
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'characters'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final fileName =
        '${_safeFileName(character.name)}_${_timestampForFile()}.llmcard';

    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  static Future<String?> saveCharacterCardToDownloads(File file) {
    return AndroidDownloadService.saveFileToDownloads(
      sourcePath: file.path,
      fileName: file.uri.pathSegments.last,
      subDir: 'LLM Project/Characters',
      mimeType: 'application/octet-stream',
    );
  }

  static Future<Map<String, List<int>>> _extractArchive(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final result = <String, List<int>>{};
    for (final item in archive.files) {
      if (item.isFile) {
        result[item.name] = List<int>.from(item.content as List<int>);
      }
    }
    return result;
  }

  static dynamic _readJson(Map<String, List<int>> files, String path) {
    final bytes = files[path];
    if (bytes == null) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  static Future<Map<String, String>> _restoreAssets(
      Map<String, List<int>> files,
      ) async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(
      p.join(
        docs.path,
        'imported_assets',
        'characters',
        _timestampForFile(),
      ),
    );

    await root.create(recursive: true);

    final pathMap = <String, String>{};

    for (final entry in files.entries) {
      if (!entry.key.startsWith('assets/')) continue;

      final target = File(
        p.join(root.path, entry.key.substring('assets/'.length)),
      );

      await target.parent.create(recursive: true);
      await target.writeAsBytes(entry.value, flush: true);

      pathMap[entry.key] = target.path;
    }

    return pathMap;
  }

  static String _restorePath(dynamic value, Map<String, String> pathMap) {
    final s = value?.toString() ?? '';
    if (s.startsWith('assets/')) return pathMap[s] ?? '';
    return s;
  }

  static Future<Map<String, String>> _importWorldBookDependencies(
      Map<String, List<int>> files,
      ) async {
    final idMap = <String, String>{};

    final raw = _readJson(files, 'data/dependencies/world_books.json');
    if (raw is! List) return idMap;

    for (int i = 0; i < raw.length; i++) {
      final wb = Map<String, dynamic>.from(raw[i] as Map);

      final oldId = wb['id']?.toString() ?? '';
      if (oldId.isEmpty) continue;

      final newId = IdUtils.timestampId(i);

      final oldName = wb['name']?.toString() ?? '导入世界书';
      final newName = await _uniqueWorldBookName(oldName);

      wb['id'] = newId;
      wb['name'] = newName;
      wb['cover_image_path'] = '';
      wb['is_preset'] = 0;

      await DatabaseService.insertWorldBook(wb);

      idMap[oldId] = newId;
    }

    return idMap;
  }

  static Future<void> importCharacterCard(File file) async {
    final files = await _extractArchive(file);

    final manifest = _readJson(files, 'manifest.json');
    if (manifest is! Map) {
      throw Exception('未识别到角色卡标识');
    }

    if (!AssetMagic.isSupportedAssetMagic(manifest['magic']?.toString()) ||
        manifest['asset_type'] != assetType) {
      throw Exception('这不是 LLM Project 角色卡文件');
    }

    final version = manifest['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('角色卡版本过高，请升级 App 后再导入');
    }

    final rawCharacter = _readJson(files, 'data/character.json');
    if (rawCharacter is! Map) {
      throw Exception('角色卡数据缺失或损坏');
    }

    final worldBookIdMap = await _importWorldBookDependencies(files);
    final pathMap = await _restoreAssets(files);

    final c = Map<String, dynamic>.from(rawCharacter);

    final oldWorldBookId = c['world_book_id']?.toString() ?? '';

    final newId = IdUtils.timestampId();
    final newName = await _uniqueCharacterName(c['name']?.toString() ?? '');

    c['id'] = newId;
    c['name'] = newName;

    c['avatar'] = _restorePath(c['avatar'], pathMap);
    c['card_image_path'] = _restorePath(c['card_image_path'], pathMap);
    c['user_avatar'] = _restorePath(c['user_avatar'], pathMap);

    // 如果包内包含世界书，则绑定新世界书 ID；否则清空，避免无效绑定
    c['world_book_id'] = worldBookIdMap[oldWorldBookId] ?? '';

    // 背景绑定是本机环境资源，导入角色卡时默认清空
    c['background_id'] = '';

    await DatabaseService.insertCharacter(c);
  }
}