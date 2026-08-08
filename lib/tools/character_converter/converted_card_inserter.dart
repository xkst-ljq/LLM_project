import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../services/character_card_asset_service.dart';
import '../../services/database_service.dart';
import '../../utils/id_utils.dart';
import 'conversion_models.dart';

/// 把转译结果直接写入角色库数据库。
///
/// 复用 App 既有导入路径（`CharacterCardAssetService.importCharacterCard` /
/// `CharacterCardPngAssetService.importCharacterCardPng`）的持久化模式：
/// 重分配 id、去重命名、内嵌世界书重映射、图片落地、复合件收录。
class ConvertedCardInserter {
  static String _timestampForDir() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<String> _uniqueCharacterName(String baseName) async {
    final all = await DatabaseService.getAllCharacters();
    final names = all.map((e) => (e['name'] as String? ?? '').trim()).toSet();

    final normalized = baseName.trim().isEmpty ? '转译角色' : baseName.trim();
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

  /// 把内嵌世界书写入库，返回 oldId -> newId 映射。
  static Future<Map<String, String>> _insertWorldBooks(
    List<Map<String, dynamic>> worldBooks,
  ) async {
    final idMap = <String, String>{};
    for (int i = 0; i < worldBooks.length; i++) {
      final wb = Map<String, dynamic>.from(worldBooks[i]);

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

  /// 把封面图字节落地为本地文件，返回文件路径（无图返回空串）。
  static Future<String> _persistCardImage(List<int>? imageBytes) async {
    if (imageBytes == null || imageBytes.isEmpty) return '';

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(
        docs.path,
        'imported_assets',
        'characters',
        _timestampForDir(),
      ),
    );
    await dir.create(recursive: true);

    final file = File(p.join(dir.path, 'card_image.png'));
    await file.writeAsBytes(imageBytes, flush: true);
    return file.path;
  }

  /// 把一张转译结果写入角色库。返回插入后的角色信息（含最终 id / 名称）。
  static Future<Map<String, dynamic>> insert(
    CardConversionResult result,
  ) async {
    final data = result.characterData;
    if (data == null) {
      throw StateError('该结果没有可入库的角色数据。');
    }

    final c = Map<String, dynamic>.from(data);

    // 内嵌世界书：重映射 id 后入库，并把角色绑定到新世界书。
    final idMap = await _insertWorldBooks(result.worldBooks);
    final oldWorldBookId = c['world_book_id']?.toString() ?? '';
    c['world_book_id'] = idMap[oldWorldBookId] ?? '';

    // 封面图落地。
    final cardImagePath = await _persistCardImage(result.imageBytes);
    c['card_image_path'] = cardImagePath;
    c['avatar'] = '';

    // 背景绑定是本机环境资源，转译入库时默认清空。
    c['background_id'] = '';

    final newId = IdUtils.timestampId();
    final newName = await _uniqueCharacterName(c['name']?.toString() ?? '');
    c['id'] = newId;
    c['name'] = newName;

    await DatabaseService.insertCharacter(c);

    // 与导入路径一致：把卡里的复合组件收进 UI 资产库。
    await CharacterCardAssetService.harvestComposites(
      c['meta_json']?.toString() ?? '',
    );

    return c;
  }
}
