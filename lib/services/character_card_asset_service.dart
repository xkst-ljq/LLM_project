import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/character_card.dart';
import '../services/android_download_service.dart';
import '../services/database_service.dart';

class CharacterCardAssetService {
  static const String magic = 'LLM_PROJECT_ASSET_V1';
  static const String assetType = 'character_card';
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

  static Map<String, dynamic> _characterToExportMap(
      CharacterCard character, {
        required String avatarAssetPath,
        required String cardImageAssetPath,
        bool includeUserOverride = false,
        String userAvatarAssetPath = '',
      }) {
    return {
      'id': character.id,
      'name': character.name,
      'avatar': avatarAssetPath,
      'card_image_path': cardImageAssetPath,
      'description': character.description,
      'system_prompt': character.systemPrompt,
      'world_book_id': character.worldBookId,
      'background_id': character.backgroundId,
      'card_type': character.cardType,
      'entries_json': character.entriesJson,
      'opening_greetings': character.openingGreetings,

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
  }) async {
    final archive = Archive();

    final manifest = {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
    };

    _addText(archive, 'manifest.json', manifest);

    final cardImageAssetPath = await _addAssetIfExists(
      archive: archive,
      sourcePath: character.cardImagePath,
      archivePath: 'assets/card_image${p.extension(character.cardImagePath).isEmpty ? '.png' : p.extension(character.cardImagePath)}',
    );

    final avatarAssetPath = await _addAssetIfExists(
      archive: archive,
      sourcePath: character.avatar,
      archivePath: 'assets/avatar${p.extension(character.avatar).isEmpty ? '.png' : p.extension(character.avatar)}',
    );

    String userAvatarAssetPath = '';
    if (includeUserOverride) {
      userAvatarAssetPath = await _addAssetIfExists(
        archive: archive,
        sourcePath: character.userAvatar,
        archivePath: 'assets/user_avatar${p.extension(character.userAvatar).isEmpty ? '.png' : p.extension(character.userAvatar)}',
      );
    }

    final characterJson = _characterToExportMap(
      character,
      avatarAssetPath: avatarAssetPath,
      cardImageAssetPath: cardImageAssetPath,
      includeUserOverride: includeUserOverride,
      userAvatarAssetPath: userAvatarAssetPath,
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
      p.join(docs.path, 'imported_assets', 'characters', _timestampForFile()),
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

  static Future<void> importCharacterCard(File file) async {
    final files = await _extractArchive(file);

    final manifest = _readJson(files, 'manifest.json');
    if (manifest is! Map) {
      throw Exception('未识别到角色卡标识');
    }

    if (manifest['magic'] != magic || manifest['asset_type'] != assetType) {
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

    final pathMap = await _restoreAssets(files);
    final c = Map<String, dynamic>.from(rawCharacter);

    // 导入时生成新 ID，避免覆盖已有角色
    final newId = DateTime.now().millisecondsSinceEpoch.toString();

    c['id'] = newId;
    c['name'] = (c['name']?.toString().trim().isEmpty ?? true)
        ? '导入角色卡'
        : c['name'].toString();

    c['avatar'] = _restorePath(c['avatar'], pathMap);
    c['card_image_path'] = _restorePath(c['card_image_path'], pathMap);
    c['user_avatar'] = _restorePath(c['user_avatar'], pathMap);

    await DatabaseService.insertCharacter(c);
  }
}