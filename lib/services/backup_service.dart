import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/api_config.dart';
import '../models/user_profile.dart';
import '../services/api_config_service.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
import '../services/user_service.dart';
import '../utils/asset_magic.dart';
import '../utils/id_utils.dart';

class BackupOptions {
  bool includeCharacters;
  bool includeWorldBooks;
  bool includeBackgrounds;
  bool includeImages;
  bool includeUserProfile;
  bool includeRoleUserOverrides;
  bool includeChatHistory;
  bool includeApiConfigs;
  bool includeApiKeys;
  bool includePreferences;

  BackupOptions({
    this.includeCharacters = true,
    this.includeWorldBooks = true,
    this.includeBackgrounds = true,
    this.includeImages = true,
    this.includeUserProfile = true,
    this.includeRoleUserOverrides = false,
    this.includeChatHistory = false,
    this.includeApiConfigs = true,
    this.includeApiKeys = false,
    this.includePreferences = true,
  });

  Map<String, dynamic> toJson() => {
        'include_characters': includeCharacters,
        'include_world_books': includeWorldBooks,
        'include_backgrounds': includeBackgrounds,
        'include_images': includeImages,
        'include_user_profile': includeUserProfile,
        'include_role_user_overrides': includeRoleUserOverrides,
        'include_chat_history': includeChatHistory,
        'include_api_configs': includeApiConfigs,
        'include_api_keys': includeApiKeys,
        'include_preferences': includePreferences,
      };
}

class BackupExportResult {
  final File file;

  const BackupExportResult({
    required this.file,
  });
}

enum BackupImportMode {
  /// 合并导入：生成新 ID，不覆盖当前资源。
  merge,

  /// 恢复导入：保留原 ID，同 ID 数据会被覆盖。
  restore,
}

class BackupService {
  static const String format = 'llm_project_backup';
  static const int formatVersion = 1;

  static String _safeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String _timestampForFile() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static void _addText(Archive archive, String path, Object? data) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static Future<String> _addAssetIfNeeded({
    required Archive archive,
    required String? sourcePath,
    required String category,
    required String ownerId,
    required String fieldName,
    required bool includeImages,
  }) async {
    if (!includeImages) return '';
    if (sourcePath == null || sourcePath.trim().isEmpty) return '';
    final file = File(sourcePath);
    if (!file.existsSync()) return '';

    try {
      final ext = p.extension(sourcePath).isEmpty ? '.png' : p.extension(sourcePath);
      final relativePath = 'assets/$category/${_safeFileName(ownerId)}_${_safeFileName(fieldName)}$ext';
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      return relativePath;
    } catch (e) {
      debugPrint('添加资源失败: $sourcePath $e');
      return '';
    }
  }

  static Future<BackupExportResult> exportBackup(BackupOptions options) async {
    final archive = Archive();
    final db = await DatabaseService.database;
    final contains = options.toJson();

    final manifest = {
      'magic': AssetMagic.backupV1,
      'format': format,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'contains': contains,
      'notes': 'Do not share backups containing API keys or chat history.',
    };

    _addText(archive, 'manifest.json', manifest);

    if (options.includeCharacters) {
      final characters = await DatabaseService.getAllCharacters();
      final exported = <Map<String, dynamic>>[];
      for (final raw in characters) {
        final c = Map<String, dynamic>.from(raw);
        final id = c['id']?.toString() ?? IdUtils.timestampId();

        c['avatar'] = await _addAssetIfNeeded(
          archive: archive,
          sourcePath: c['avatar'] as String?,
          category: 'characters',
          ownerId: id,
          fieldName: 'avatar',
          includeImages: options.includeImages,
        );
        c['card_image_path'] = await _addAssetIfNeeded(
          archive: archive,
          sourcePath: c['card_image_path'] as String?,
          category: 'characters',
          ownerId: id,
          fieldName: 'card',
          includeImages: options.includeImages,
        );

        if (options.includeRoleUserOverrides) {
          c['user_avatar'] = await _addAssetIfNeeded(
            archive: archive,
            sourcePath: c['user_avatar'] as String?,
            category: 'characters',
            ownerId: id,
            fieldName: 'user_avatar',
            includeImages: options.includeImages,
          );
        } else {
          c['user_name'] = '';
          c['user_avatar'] = '';
          c['user_detail_setting'] = '';
        }

        exported.add(c);
      }
      _addText(archive, 'data/characters.json', exported);
    }

    if (options.includeWorldBooks) {
      final worldBooks = await DatabaseService.getAllWorldBooks();
      final exported = <Map<String, dynamic>>[];
      for (final raw in worldBooks) {
        final wb = Map<String, dynamic>.from(raw);
        final id = wb['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (wb.containsKey('cover_image_path')) {
          wb['cover_image_path'] = await _addAssetIfNeeded(
            archive: archive,
            sourcePath: wb['cover_image_path'] as String?,
            category: 'world_books',
            ownerId: id,
            fieldName: 'cover',
            includeImages: options.includeImages,
          );
        }
        exported.add(wb);
      }
      _addText(archive, 'data/world_books.json', exported);
    }

    if (options.includeBackgrounds) {
      final backgrounds = await BackgroundService.getAll();
      final exported = <Map<String, dynamic>>[];
      for (final bg in backgrounds) {
        final b = bg.toDb();
        final id = b['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        b['original_image_path'] = await _addAssetIfNeeded(
          archive: archive,
          sourcePath: b['original_image_path'] as String?,
          category: 'backgrounds',
          ownerId: id,
          fieldName: 'original',
          includeImages: options.includeImages,
        );
        // 兼容旧表字段：如果未来还有裁剪图字段，导出时也会保留空/相对路径。
        for (final field in ['portrait_crop_path', 'landscape_crop_path']) {
          if (b.containsKey(field)) {
            b[field] = await _addAssetIfNeeded(
              archive: archive,
              sourcePath: b[field] as String?,
              category: 'backgrounds',
              ownerId: id,
              fieldName: field,
              includeImages: options.includeImages,
            );
          }
        }
        exported.add(b);
      }
      _addText(archive, 'data/backgrounds.json', exported);
    }

    if (options.includeUserProfile) {
      final user = await UserService.getUser();
      final data = user.toJson();
      data['avatar_path'] = await _addAssetIfNeeded(
        archive: archive,
        sourcePath: user.avatarPath,
        category: 'users',
        ownerId: 'global_user',
        fieldName: 'avatar',
        includeImages: options.includeImages,
      );
      _addText(archive, 'data/user_profile.json', data);
    }

    if (options.includeApiConfigs) {
      final configs = await ApiConfigService.getAllConfigs();
      final activeId = await ApiConfigService.getActiveConfigId();
      final data = {
        'active_config_id': activeId,
        'configs': configs.map((c) {
          final map = c.toJson();
          if (options.includeApiKeys) {
            map['api_key'] = c.apiKey;
          }
          return map;
        }).toList(),
      };
      _addText(archive, 'data/api_configs.json', data);
    }

    if (options.includeChatHistory) {
      final messages = await db.query('messages', orderBy: 'timestamp ASC');
      _addText(archive, 'data/messages.json', messages);
    }

    if (options.includePreferences) {
      final prefs = await SharedPreferences.getInstance();
      final prefKeys = <String>[
        'current_background_id',
        'character_sort_by',
        'character_sort_ascending',
        'background_sort_by',
        'background_sort_ascending',
        'wordbook_sort_by',
        'wordbook_sort_ascending',
      ];
      final data = <String, dynamic>{};
      for (final key in prefKeys) {
        final value = prefs.get(key);
        if (value != null) data[key] = value;
      }
      _addText(archive, 'data/preferences.json', data);
    }

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw Exception('备份压缩失败');

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'backups'));

    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final file = File(
      p.join(
        dir.path,
        'LLM_Project_Backup_${_timestampForFile()}.llmbak',
      ),
    );

    await file.writeAsBytes(bytes, flush: true);

    return BackupExportResult(file: file);
  }

  static Future<Map<String, List<int>>> _extractArchive(File backupFile) async {
    final bytes = await backupFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final file in archive.files) {
      if (file.isFile) {
        files[file.name] = List<int>.from(file.content as List<int>);
      }
    }
    return files;
  }

  static dynamic _readJson(Map<String, List<int>> files, String path) {
    final bytes = files[path];
    if (bytes == null) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  static Future<Map<String, String>> _restoreAssets(Map<String, List<int>> files) async {
    final docs = await getApplicationDocumentsDirectory();
    final assetRoot = Directory(p.join(docs.path, 'imported_assets', _timestampForFile()));
    await assetRoot.create(recursive: true);

    final pathMap = <String, String>{};
    for (final entry in files.entries) {
      if (!entry.key.startsWith('assets/')) continue;
      final dest = File(p.join(assetRoot.path, entry.key.substring('assets/'.length)));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(entry.value, flush: true);
      pathMap[entry.key] = dest.path;
    }
    return pathMap;
  }

  static String _restorePath(dynamic value, Map<String, String> pathMap) {
    final s = value?.toString() ?? '';
    if (s.startsWith('assets/')) return pathMap[s] ?? '';
    return s;
  }

  static Future<String> _uniqueName(
      Database db,
      String table,
      String baseName,
      ) async {
    final normalized = baseName.trim().isEmpty ? '导入项目' : baseName.trim();

    final rows = await db.query(
      table,
      columns: ['name'],
    );

    final names = rows
        .map((e) => (e['name'] as String? ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    if (!names.contains(normalized)) return normalized;

    var index = 1;
    while (names.contains('$normalized ($index)')) {
      index++;
    }

    return '$normalized ($index)';
  }

  static Future<void> importBackup(
      File backupFile, {
        BackupImportMode mode = BackupImportMode.merge,
      }) async {
    final files = await _extractArchive(backupFile);
    final manifest = _readJson(files, 'manifest.json');
    if (manifest is! Map) {
      throw Exception('不是有效的 LLM Project 备份文件');
    }

    final manifestMap = Map<String, dynamic>.from(manifest);

    final magic = manifestMap['magic']?.toString();
    final formatValue = manifestMap['format']?.toString();

// 兼容旧备份：旧版本可能没有 magic，但有 format = llm_project_backup
    final isOldBackup = magic == null && formatValue == format;

    final isSupportedBackup =
        AssetMagic.isSupportedBackupMagic(magic) || isOldBackup;

    if (!isSupportedBackup) {
      throw Exception('未识别到 LLM Project 备份标识');
    }

    final pathMap = await _restoreAssets(files);
    final db = await DatabaseService.database;
    final isMergeMode = mode == BackupImportMode.merge;

    final worldBookIdMap = <String, String>{};
    final backgroundIdMap = <String, String>{};
    final characterIdMap = <String, String>{};

    final characters = _readJson(files, 'data/characters.json');
    if (characters is List) {
      for (int i = 0; i < characters.length; i++) {
        final c = Map<String, dynamic>.from(characters[i] as Map);

        final oldId = c['id']?.toString() ?? '';
        final oldWorldBookId = c['world_book_id']?.toString() ?? '';
        final oldBackgroundId = c['background_id']?.toString() ?? '';

        c['avatar'] = _restorePath(c['avatar'], pathMap);
        c['card_image_path'] = _restorePath(c['card_image_path'], pathMap);
        c['user_avatar'] = _restorePath(c['user_avatar'], pathMap);

        if (isMergeMode) {
          final newId = IdUtils.timestampId(20000 + i);
          characterIdMap[oldId] = newId;

          c['id'] = newId;
          c['name'] = await _uniqueName(
            db,
            'characters',
            c['name']?.toString() ?? '导入角色卡',
          );

          c['world_book_id'] = worldBookIdMap[oldWorldBookId] ?? '';
          c['background_id'] = backgroundIdMap[oldBackgroundId] ?? '';
        }

        await db.insert(
          'characters',
          c,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    final worldBooks = _readJson(files, 'data/world_books.json');
    if (worldBooks is List) {
      for (int i = 0; i < worldBooks.length; i++) {
        final wb = Map<String, dynamic>.from(worldBooks[i] as Map);

        final oldId = wb['id']?.toString() ?? '';

        if (wb.containsKey('cover_image_path')) {
          wb['cover_image_path'] = _restorePath(wb['cover_image_path'], pathMap);
        }

        if (isMergeMode) {
          final newId = IdUtils.timestampId(i);
          worldBookIdMap[oldId] = newId;

          wb['id'] = newId;
          wb['name'] = await _uniqueName(
            db,
            'world_books',
            wb['name']?.toString() ?? '导入世界书',
          );
          wb['is_preset'] = 0;
        }

        await db.insert(
          'world_books',
          wb,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    final backgrounds = _readJson(files, 'data/backgrounds.json');
    if (backgrounds is List) {
      for (int i = 0; i < backgrounds.length; i++) {
        final b = Map<String, dynamic>.from(backgrounds[i] as Map);

        final oldId = b['id']?.toString() ?? '';

        b['original_image_path'] = _restorePath(b['original_image_path'], pathMap);

        if (b.containsKey('portrait_crop_path')) {
          b['portrait_crop_path'] = _restorePath(b['portrait_crop_path'], pathMap);
        }

        if (b.containsKey('landscape_crop_path')) {
          b['landscape_crop_path'] = _restorePath(b['landscape_crop_path'], pathMap);
        }

        if (isMergeMode) {
          final newId = IdUtils.timestampId(10000 + i);
          backgroundIdMap[oldId] = newId;

          b['id'] = newId;
          b['name'] = await _uniqueName(
            db,
            'backgrounds',
            b['name']?.toString() ?? '导入背景',
          );
          b['is_preset'] = 0;
        }

        await db.insert(
          'backgrounds',
          b,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      BackgroundService.versionNotifier.value++;
    }

    if (!isMergeMode) {
      final userProfile = _readJson(files, 'data/user_profile.json');
      if (userProfile is Map) {
        final data = Map<String, dynamic>.from(userProfile);
        data['avatar_path'] = _restorePath(data['avatar_path'], pathMap);
        await UserService.saveUser(UserProfile.fromJson(data));
      }
    }

    if (!isMergeMode) {
      final apiData = _readJson(files, 'data/api_configs.json');
      if (apiData is Map) {
        final list = apiData['configs'];
        if (list is List) {
          final configs = list.map((raw) {
            final map = Map<String, dynamic>.from(raw as Map);
            final config = ApiConfig.fromJson(map);
            config.apiKey = map['api_key']?.toString() ?? '';
            return config;
          }).toList();
          await ApiConfigService.saveAllConfigs(configs);
        }

        final activeId = apiData['active_config_id']?.toString();
        if (activeId != null && activeId.isNotEmpty) {
          await ApiConfigService.setActiveConfigId(activeId);
        }
      }
    }

    final messages = _readJson(files, 'data/messages.json');
    if (messages is List) {
      for (final raw in messages) {
        final m = Map<String, dynamic>.from(raw as Map);

        if (isMergeMode) {
          final oldCharacterId = m['character_id']?.toString() ?? '';
          final newCharacterId = characterIdMap[oldCharacterId];

          // 合并模式下，如果对应角色没有被导入，则跳过该消息
          if (newCharacterId == null || newCharacterId.isEmpty) {
            continue;
          }

          m.remove('id');
          m['character_id'] = newCharacterId;
        }

        await db.insert(
          'messages',
          m,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    if (!isMergeMode) {
      final preferences = _readJson(files, 'data/preferences.json');
      if (preferences is Map) {
        final prefs = await SharedPreferences.getInstance();

        for (final entry in preferences.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          if (value is bool) await prefs.setBool(key, value);
          if (value is int) await prefs.setInt(key, value);
          if (value is double) await prefs.setDouble(key, value);
          if (value is String) await prefs.setString(key, value);
          if (value is List<String>) await prefs.setStringList(key, value);
        }
      }
    }
  }
}
