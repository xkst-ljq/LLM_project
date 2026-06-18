import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/character_card.dart';
import '../services/android_download_service.dart';
import '../services/database_service.dart';
import '../utils/asset_magic.dart';
import '../utils/id_utils.dart';

class CharacterCardPngAssetService {
  static const String magic = AssetMagic.assetV1;
  static const String assetType = AssetMagic.characterCard;
  static const String container = 'png_card';
  static const int formatVersion = 1;

  static final List<int> _startMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_START---\n');
  static final List<int> _endMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_END---\n');

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

  static int _indexOfBytes(List<int> bytes, List<int> pattern, [int start = 0]) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;

    for (int i = start; i <= bytes.length - pattern.length; i++) {
      bool matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }

    return -1;
  }

  static int _lastIndexOfBytes(List<int> bytes, List<int> pattern) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;

    for (int i = bytes.length - pattern.length; i >= 0; i--) {
      bool matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }

    return -1;
  }

  static Future<Map<String, dynamic>> readCharacterCardPngData(File file) async {
    final bytes = await file.readAsBytes();

    final start = _lastIndexOfBytes(bytes, _startMarker);
    if (start == -1) {
      throw Exception('未识别到 LLM Project 角色卡图片标识');
    }

    final payloadStart = start + _startMarker.length;
    final end = _indexOfBytes(bytes, _endMarker, payloadStart);

    if (end == -1 || end <= payloadStart) {
      throw Exception('角色卡图片数据不完整或已损坏');
    }

    final payloadBase64 = utf8.decode(bytes.sublist(payloadStart, end)).trim();

    Map<String, dynamic> root;
    try {
      final jsonText = utf8.decode(base64Decode(payloadBase64));
      root = Map<String, dynamic>.from(jsonDecode(jsonText) as Map);
    } catch (_) {
      throw Exception('角色卡图片数据解析失败');
    }

    if (!AssetMagic.isSupportedAssetMagic(root['magic']?.toString()) ||
        root['asset_type'] != assetType ||
        root['container'] != container) {
      throw Exception('这不是 LLM Project 角色卡图片');
    }

    final version = root['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('角色卡图片版本过高，请升级 App 后再导入');
    }

    final payload = root['payload'];
    if (payload is! Map) {
      throw Exception('角色卡图片载荷缺失');
    }

    final rawCharacter = payload['character'];
    if (rawCharacter is! Map) {
      throw Exception('角色卡数据缺失');
    }

    final dependencies = payload['dependencies'];
    final worldBooks = dependencies is Map && dependencies['world_books'] is List
        ? (dependencies['world_books'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        : <Map<String, dynamic>>[];

    return {
      'container': 'png_card',
      'manifest': root,
      'character': Map<String, dynamic>.from(rawCharacter),
      'world_books': worldBooks,
    };
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
        required bool includeUserOverride,
        required bool includeBoundWorldBook,
      }) {
    return {
      'id': character.id,
      'name': character.name,

      // 图片卡本身就是 card_image_path，导入时会重新生成路径
      'avatar': '',
      'card_image_path': '',

      'description': character.description,
      'system_prompt': character.systemPrompt,
      'world_book_id': includeBoundWorldBook ? character.worldBookId : '',
      'background_id': '',
      'card_type': character.cardType,
      'entries_json': character.entriesJson,
      'opening_greetings': character.openingGreetings,
      // 扩展元信息（标签 / 作者 / 来源 / post_history / 状态栏字段等）
      'meta_json': character.metaJson,

      // 默认不导出用户覆盖设定
      'user_name': includeUserOverride ? character.userName : '',
      'user_avatar': '',
      'user_detail_setting':
      includeUserOverride ? character.userDetailSetting : '',
    };
  }

  /// 图片角色卡是纯 JSON 载荷，无法另存 asset 文件。
  /// 因此把开场白 / 描述里用户插入的本地图片转成 data URI 内联进文本，
  /// 使卡片可跨设备分享（导入端的 HTML 渲染可直接显示 data URI）。
  static Future<Map<String, dynamic>> _inlineLocalImages(
    Map<String, dynamic> character,
  ) async {
    final imgRe = RegExp(
      r'''<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s">]+))''',
      caseSensitive: false,
      dotAll: true,
    );
    final urlRe = RegExp(
      r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]+))\s*\)''',
      caseSensitive: false,
    );

    final cache = <String, String?>{}; // 本地路径 -> data URI（null 表示读取失败）

    Future<String?> toDataUri(String path) async {
      if (cache.containsKey(path)) return cache[path];
      String? uri;
      try {
        final file = File(path);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          final ext = p.extension(path).toLowerCase();
          String mime = 'image/png';
          if (ext == '.gif') {
            mime = 'image/gif';
          } else if (ext == '.webp') {
            mime = 'image/webp';
          } else if (ext == '.jpg' || ext == '.jpeg') {
            mime = 'image/jpeg';
          }
          uri = 'data:$mime;base64,${base64Encode(bytes)}';
        }
      } catch (e) {
        debugPrint('内联本地图片失败: $path $e');
      }
      cache[path] = uri;
      return uri;
    }

    Future<String> rewrite(String text) async {
      if (text.isEmpty) return text;
      final paths = <String>[];
      void collect(RegExp re) {
        for (final m in re.allMatches(text)) {
          final s = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
          if (s.isEmpty) continue;
          if (s.startsWith('http://') ||
              s.startsWith('https://') ||
              s.startsWith('data:') ||
              s.startsWith('assets/')) {
            continue;
          }
          if (!paths.contains(s)) paths.add(s);
        }
      }

      collect(imgRe);
      collect(urlRe);
      var result = text;
      for (final path in paths) {
        final uri = await toDataUri(path);
        if (uri != null) result = result.replaceAll(path, uri);
      }
      return result;
    }

    final c = Map<String, dynamic>.from(character);
    c['opening_greetings'] =
        await rewrite(c['opening_greetings']?.toString() ?? '[]');
    c['description'] = await rewrite(c['description']?.toString() ?? '');
    return c;
  }

  static Future<File> exportCharacterCardPng({
    required CharacterCard character,
    bool includeUserOverride = false,
    bool includeBoundWorldBook = false,
  }) async {
    if (character.cardImagePath.trim().isEmpty) {
      throw Exception('角色卡封面为空');
    }

    final source = File(character.cardImagePath);
    if (!source.existsSync()) {
      throw Exception('角色卡封面文件不存在');
    }

    final sourceBytes = await source.readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw Exception('无法读取角色卡封面图片');
    }

    // 重新编码为 PNG，保证导出文件是标准 PNG 图片
    final pngBytes = img.encodePng(decoded);

    final shouldIncludeWorldBook =
        includeBoundWorldBook && character.worldBookId.trim().isNotEmpty;

    final dependencies = <String, dynamic>{
      'world_books': <Map<String, dynamic>>[],
    };

    if (shouldIncludeWorldBook) {
      final wb = await _findWorldBookRaw(character.worldBookId);
      if (wb != null) {
        wb['cover_image_path'] = '';
        wb['is_preset'] = 0;
        (dependencies['world_books'] as List).add(wb);
      }
    }

    final payload = {
      'magic': magic,
      'asset_type': assetType,
      'container': container,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
      'contains': {
        'user_override': includeUserOverride,
        'world_book': shouldIncludeWorldBook,
      },
      'payload': {
        'character': await _inlineLocalImages(_characterToExportMap(
          character,
          includeUserOverride: includeUserOverride,
          includeBoundWorldBook: shouldIncludeWorldBook,
        )),
        'dependencies': dependencies,
      },
    };

    final payloadJson = jsonEncode(payload);
    final payloadBase64 = base64Encode(utf8.encode(payloadJson));

    final outputBytes = <int>[
      ...pngBytes,
      ..._startMarker,
      ...utf8.encode(payloadBase64),
      ..._endMarker,
    ];

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'character_png'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final fileName =
        '${_safeFileName(character.name)}_${_timestampForFile()}.llmchar.png';

    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(outputBytes, flush: true);

    return file;
  }

  static Future<String?> saveCharacterPngToDownloads(File file) {
    return AndroidDownloadService.saveFileToDownloads(
      sourcePath: file.path,
      fileName: file.uri.pathSegments.last,
      subDir: 'LLM Project/Characters',
      mimeType: 'image/png',
    );
  }

  static Future<Map<String, String>> _importWorldBookDependencies(
      Map<String, dynamic> root,
      ) async {
    final idMap = <String, String>{};

    final payload = root['payload'];
    if (payload is! Map) return idMap;

    final dependencies = payload['dependencies'];
    if (dependencies is! Map) return idMap;

    final worldBooks = dependencies['world_books'];
    if (worldBooks is! List) return idMap;

    for (int i = 0; i < worldBooks.length; i++) {
      final wb = Map<String, dynamic>.from(worldBooks[i] as Map);

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

  static Future<void> importCharacterCardPng(File file) async {
    final bytes = await file.readAsBytes();

    final start = _lastIndexOfBytes(bytes, _startMarker);
    if (start == -1) {
      throw Exception('未识别到 LLM Project 角色卡图片标识');
    }

    final payloadStart = start + _startMarker.length;
    final end = _indexOfBytes(bytes, _endMarker, payloadStart);

    if (end == -1 || end <= payloadStart) {
      throw Exception('角色卡图片数据不完整或已损坏');
    }

    final imageBytes = bytes.sublist(0, start);
    final payloadBase64 = utf8.decode(bytes.sublist(payloadStart, end)).trim();

    Map<String, dynamic> root;
    try {
      final jsonText = utf8.decode(base64Decode(payloadBase64));
      root = Map<String, dynamic>.from(jsonDecode(jsonText) as Map);
    } catch (_) {
      throw Exception('角色卡图片数据解析失败');
    }

    if (!AssetMagic.isSupportedAssetMagic(root['magic']?.toString()) ||
        root['asset_type'] != assetType ||
        root['container'] != container) {
      throw Exception('这不是 LLM Project 角色卡图片');
    }

    final version = root['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('角色卡图片版本过高，请升级 App 后再导入');
    }

    final payload = root['payload'];
    if (payload is! Map) {
      throw Exception('角色卡图片载荷缺失');
    }

    final rawCharacter = payload['character'];
    if (rawCharacter is! Map) {
      throw Exception('角色卡数据缺失');
    }

    final worldBookIdMap = await _importWorldBookDependencies(root);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'imported_assets', 'character_png', _timestampForFile()),
    );
    await dir.create(recursive: true);

    final imageFile = File(p.join(dir.path, 'card_image.png'));
    await imageFile.writeAsBytes(imageBytes, flush: true);

    final c = Map<String, dynamic>.from(rawCharacter);

    final oldWorldBookId = c['world_book_id']?.toString() ?? '';

    final newId = IdUtils.timestampId();
    final newName = await _uniqueCharacterName(c['name']?.toString() ?? '');

    c['id'] = newId;
    c['name'] = newName;
    c['card_image_path'] = imageFile.path;
    c['avatar'] = '';
    c['user_avatar'] = '';

    c['world_book_id'] = worldBookIdMap[oldWorldBookId] ?? '';
    c['background_id'] = '';

    await DatabaseService.insertCharacter(c);
  }
}