import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/character_card.dart';
import '../services/android_download_service.dart';
import '../services/database_service.dart';
import '../services/ui_engine/element_animation.dart';
import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../utils/asset_magic.dart';
import '../utils/id_utils.dart';

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

  /// 把一段文本里引用的本地图片（<img src="本地路径"> 或 url(本地路径)）
  /// 打包进 archive 的 assets/embedded/，并把引用改写为 assets/embedded/xxx。
  /// 返回改写后的文本。[counter] 用于跨多段文本统一编号、避免重名。
  static Future<String> _embedLocalImagesInText(
    String text,
    Archive archive,
    List<int> counter,
  ) async {
    if (text.isEmpty) return text;

    // 收集 <img src> 与 css url() 中的本地路径（非 http/https/data/assets）。
    final imgRe = RegExp(
      r'''<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s">]+))''',
      caseSensitive: false,
      dotAll: true,
    );
    final urlRe = RegExp(
      r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]+))\s*\)''',
      caseSensitive: false,
    );

    final localPaths = <String>[];
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
        if (!localPaths.contains(s)) localPaths.add(s);
      }
    }

    collect(imgRe);
    collect(urlRe);
    if (localPaths.isEmpty) return text;

    var result = text;
    for (final path in localPaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final bytes = await file.readAsBytes();
        final ext = p.extension(path).isEmpty ? '.png' : p.extension(path);
        final assetPath = 'assets/embedded/img_${counter[0]}$ext';
        counter[0]++;
        archive.addFile(ArchiveFile(assetPath, bytes.length, bytes));
        result = result.replaceAll(path, assetPath);
      } catch (e) {
        debugPrint('打包内嵌图片失败: $path $e');
      }
    }
    return result;
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

    // 开场白 / 描述里用户插入的本地图片，打包进卡并改写引用路径，
    // 使角色卡可跨设备分享（导入时再落地为本机路径）。
    final embedCounter = <int>[0];
    characterJson['opening_greetings'] = await _embedLocalImagesInText(
      characterJson['opening_greetings']?.toString() ?? '[]',
      archive,
      embedCounter,
    );
    characterJson['description'] = await _embedLocalImagesInText(
      characterJson['description']?.toString() ?? '',
      archive,
      embedCounter,
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

  /// 把一段文本里所有对 assets/ 资产的引用（如开场白内嵌图片
  /// src="assets/embedded/img_0.png"）替换为导入后的本地文件路径。
  static String _restoreAssetRefsInText(
    dynamic value,
    Map<String, String> pathMap,
  ) {
    var s = value?.toString() ?? '';
    if (s.isEmpty) return s;
    pathMap.forEach((assetKey, localPath) {
      if (s.contains(assetKey)) {
        s = s.replaceAll(assetKey, localPath);
      }
    });
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

    // 开场白 / 描述里内嵌图片（assets/embedded/xxx）的引用，重写为本地文件路径。
    c['opening_greetings'] =
        _restoreAssetRefsInText(c['opening_greetings'], pathMap);
    c['description'] = _restoreAssetRefsInText(c['description'], pathMap);

    // 如果包内包含世界书，则绑定新世界书 ID；否则清空，避免无效绑定
    c['world_book_id'] = worldBookIdMap[oldWorldBookId] ?? '';

    // 背景绑定是本机环境资源，导入角色卡时默认清空
    c['background_id'] = '';

    await DatabaseService.insertCharacter(c);

    // 把卡里用到的复合组件收进资产库。
    //
    // 用户反馈：「复合组件我觉得在人物卡导入后就应该放进 UI 组件库里面」。
    // 在此之前导入只写 characters 表，卡里的复合件对作者完全不可见——
    // 想拿来改一改、或在 Studio 里拆开看构造都做不到。
    await harvestComposites(c['meta_json']?.toString() ?? '');
  }

  /// 从角色卡的 meta 里提取全部复合组件，存入资产库。
  ///
  /// 失败不影响导入本身：角色卡已经入库了，
  /// 收不收得到复合件只是锦上添花，不该让整个导入报错。
  static Future<void> harvestComposites(String metaJson) async {
    if (metaJson.trim().isEmpty) return;
    try {
      final meta = jsonDecode(metaJson);
      if (meta is! Map) return;
      final assemblies = meta['ui_assemblies'];
      if (assemblies is! List) return;

      final service = UIAssetService();
      await service.ensureLoaded();
      // 按**内容指纹**去重。
      //
      // 不能用角色卡 id 做键：导入时 `c['id'] = newId` 会换一个新 id
      // （见上方 importCharacterCard），同一张卡导入两次得到两个不同 id，
      // 照样会重复收录。
      //
      // 指纹只看复合件自身的内容，因此：
      //   · 同一张卡反复导入 → 指纹相同 → 只存一份（用户诉求）
      //   · 不同卡里用了同一个复合件 → 也只存一份
      //   · 作者改过内容再导出 → 指纹变了 → 作为新资产收录
      final existing = <String>{
        for (final c in service.getAllComposites()) _compositeFingerprint(c),
      };

      var added = 0;
      var skipped = 0;
      for (final raw in assemblies) {
        final info = jsonDecode(raw is String ? raw : jsonEncode(raw));
        if (info is! Map) continue;
        final pagesRaw = info['pages'];
        if (pagesRaw == null) continue;
        final pages = jsonDecode(
          pagesRaw is String ? pagesRaw : jsonEncode(pagesRaw),
        );
        if (pages is! List) continue;
        for (final page in pages) {
          if (page is! Map) continue;
          final elements = page['elements'];
          if (elements is! List) continue;
          for (final el in _walkComposites(elements)) {
            final composite = UIComposite.fromJson(
              Map<String, dynamic>.from(el['composite'] as Map),
            );
            // 指纹只取骨架特征（类型/几何/配色/linker 方案），
            // 本就不含 dataChannel 等实例键——所以同一个骨架配了不同
            // 数据通道的两份，作为模板看是同一个，不会重复收录。
            if (!existing.add(_compositeFingerprint(composite))) {
              skipped++;
              continue;
            }
            // 换新 id，避免与库里既有资产撞号。
            // UIComposite.copyWith **不接受 id**（id 是 final 且原样继承），
            // 只能走构造函数重建。
            service.addComposite(UIComposite(
              id: 'imp_${IdUtils.timestampId()}_$added',
              name: composite.name,
              layoutType: composite.layoutType,
              // 净化成**可复用模板**：剥掉那张卡特有的实例数据。
              children: composite.children
                  .map(sanitizeForTemplate)
                  .toList(),
              material: composite.material,
              borderRadius: composite.borderRadius,
              color: composite.color,
              opacity: composite.opacity,
              renderingMode: composite.renderingMode,
              exposedPorts: composite.exposedPorts,
            ));
            added++;
          }
        }
      }
      if (added > 0 || skipped > 0) {
        debugPrint('导入角色卡：收录 $added 个复合组件'
            '${skipped > 0 ? '，跳过 $skipped 个已存在的（内容指纹相同）' : ''}');
      }
    } catch (e) {
      debugPrint('收录复合组件失败（不影响角色卡导入）: $e');
    }
  }

  /// **仅 Assembly 有编辑入口**的属性键。
  ///
  /// 这些是「这张卡怎么用这个组件」的实例数据，不是组件本身的一部分：
  ///   · dataChannel   —— 绑到哪个状态字段 / 会话变量
  ///   · keyAction     —— 是不是这套 UI 的关闭 / 设置按钮
  ///   · sendsMessage  —— 点了要不要发消息
  ///   · __anim        —— Assembly 的触发动画（Studio 没有这个编辑器）
  ///
  /// 混进资产库模板会造成两个问题（用户反馈）：
  ///   1. **专一性过强**：模板带着某张卡的状态字段绑定，
  ///      拖到别的卡里全是失效引用，可复用性极低；
  ///   2. **语义污染**：Studio 能渲染 __anim 却提供不了编辑入口，
  ///      作者看得见改不了。
  static const Set<String> _instanceOnlyPropKeys = {
    'dataChannel',
    'keyAction',
    'sendsMessage',
    ElementAnimation.propsKey, // '__anim'
  };

  /// 把实例元素净化成可复用的模板元素。
  ///
  /// 只剥离实例级绑定，**保留一切外观与内部联动**——
  /// 尺寸、配色、圆角、linker 连线、暴露端口都是组件的骨架，
  /// 剥掉就不成其为组件了。
  static UIElement sanitizeForTemplate(UIElement element) {
    if (element.isComposite && element.composite != null) {
      final inner = element.composite!;
      return element.copyWith(
        composite: UIComposite(
          id: inner.id,
          name: inner.name,
          layoutType: inner.layoutType,
          children: inner.children.map(sanitizeForTemplate).toList(),
          material: inner.material,
          borderRadius: inner.borderRadius,
          color: inner.color,
          opacity: inner.opacity,
          renderingMode: inner.renderingMode,
          exposedPorts: inner.exposedPorts,
        ),
      );
    }
    final module = element.module;
    if (module == null) return element;

    final props = Map<String, dynamic>.from(module.properties);
    var touched = false;
    for (final key in _instanceOnlyPropKeys) {
      if (props.remove(key) != null) touched = true;
    }
    // 这两个是 UIModule 的顶层字段，不在 properties 里。
    final hasBinding = module.boundVariable != null ||
        module.statusFieldMirrorKey != null;
    if (!touched && !hasBinding) return element;

    return element.copyWith(
      module: module.copyWith(
        properties: props,
        // copyWith 的可空参数遇 null 会保留原值，
        // 所以要显式传空串来清除（模型里空串等价于「未绑定」）。
        boundVariable: '',
        statusFieldMirrorKey: '',
      ),
    );
  }

  /// 复合件的内容指纹。
  ///
  /// **刻意排除 id**：每次导入都会重新分配 id，算进去的话指纹永远不同，
  /// 去重就失效了。子元素 id 同理——它们只是内部引用，
  /// 换一批 id 不改变「这是同一个组件」的事实。
  ///
  /// 名称也排除在外：作者可能只是改了个名字，内容一模一样，
  /// 不该因此多存一份。
  static String _compositeFingerprint(UIComposite c) {
    final buffer = StringBuffer()
      ..write(c.layoutType)
      ..write('|')
      ..write(c.material.index)
      ..write('|')
      ..write(c.borderRadius.toStringAsFixed(1))
      ..write('|')
      ..write(c.color.toARGB32())
      ..write('|')
      ..write(c.opacity.toStringAsFixed(2))
      ..write('|')
      ..write(c.renderingMode.index)
      ..write('|ports:')
      ..write((c.exposedPorts ?? const []).length)
      ..write('|kids:');
    for (final child in c.children) {
      buffer
        ..write(child.isComposite ? 'C' : (child.module?.type ?? '?'))
        ..write('@')
        ..write(child.offset.dx.toStringAsFixed(1))
        ..write(',')
        ..write(child.offset.dy.toStringAsFixed(1))
        ..write(':')
        ..write(child.size.width.toStringAsFixed(1))
        ..write('x')
        ..write(child.size.height.toStringAsFixed(1));
      final module = child.module;
      if (module != null) {
        buffer
          ..write('#')
          ..write(module.name)
          ..write('#')
          ..write(module.color.toARGB32());
        // linker 只取方案名：source/target 存的是会被重映射的元素 id，
        // 算进指纹会让「同一个组件」在每次导入后都算成新的。
        final linker = module.properties['linker'];
        if (linker is Map) {
          buffer
            ..write('#lk:')
            ..write(linker['scheme'])
            ..write('/')
            ..write(linker['sourcePort'] ?? '');
        }
      }
      buffer.write(';');
    }
    // 取长度 + 简单散列，避免键过长撑大内存。
    final raw = buffer.toString();
    var hash = 0;
    for (var i = 0; i < raw.length; i++) {
      hash = (hash * 31 + raw.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return '${c.children.length}:${raw.length}:$hash';
  }

  /// 递归找出所有复合件节点（含嵌套在别的复合件里的）。
  static Iterable<Map<String, dynamic>> _walkComposites(
    List<dynamic> elements,
  ) sync* {
    for (final el in elements) {
      if (el is! Map) continue;
      final m = Map<String, dynamic>.from(el);
      if (m['isComposite'] == true && m['composite'] is Map) {
        yield m;
        final kids = (m['composite'] as Map)['children'];
        if (kids is List) yield* _walkComposites(kids);
      }
    }
  }
}