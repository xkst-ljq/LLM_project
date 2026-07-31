import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/android_download_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../utils/asset_magic.dart';

/// 复合组件的导出 / 导入。
///
/// **为什么只分享复合件、不分享整套 UI 方案**（用户判断）：
/// 整套方案对角色卡绑定太深——页面路由、状态字段 `targetId`、
/// 开场白/常驻等 mode 归属，换一张卡全部失效。
/// 而复合件存在**全局资产库**里、不属于任何角色卡，
/// 本来就是自包含的「零件」，天然适合独立流通。
///
/// 文件形态：纯 JSON（`.llmui`）。不做缩略图载体是因为那需要先实现
/// 「渲染复合件到图片」，属于另一件事；先把链路跑通。
class UICompositeAssetService {
  static const String magic = AssetMagic.assetV1;
  static const String assetType = AssetMagic.uiComposite;
  static const int formatVersion = 1;

  static String _safeFileName(String input) {
    final value = input.trim().isEmpty ? '未命名组件' : input.trim();
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

  // ==========================================================================
  // 导出
  // ==========================================================================

  static Future<File> exportComposite(UIComposite composite) async {
    final payload = {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
      'payload': {
        'composite': await _prepareForExport(composite.toJson()),
      },
    };

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'ui_composites'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final fileName =
        '${_safeFileName(composite.name)}_${_timestampForFile()}.llmui';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  static Future<String?> saveCompositeToDownloads(File file) {
    return AndroidDownloadService.saveFileToDownloads(
      sourcePath: file.path,
      fileName: file.uri.pathSegments.last,
      subDir: 'LLM Project/UIComposites',
      mimeType: 'application/json',
    );
  }

  /// 导出前的清洗：内联图片 + 降级数据通道。
  static Future<Map<String, dynamic>> _prepareForExport(
    Map<String, dynamic> raw,
  ) async {
    final json = Map<String, dynamic>.from(raw);
    final children = json['children'];
    if (children is List) {
      await _visitChildren(children, _sanitizeForExport);
    }
    return json;
  }

  /// 单个子元素的导出前处理。
  static Future<void> _sanitizeForExport(Map<dynamic, dynamic> props) async {
    // 1. 本地图片内联成 data URI，否则到别人机器上路径不存在。
    final assetPath = props['assetPath']?.toString().trim() ?? '';
    if (assetPath.isNotEmpty &&
        !assetPath.startsWith('data:') &&
        !assetPath.startsWith('http://') &&
        !assetPath.startsWith('https://') &&
        !assetPath.startsWith('assets/')) {
      final uri = await _fileToDataUri(assetPath);
      if (uri != null) props['assetPath'] = uri;
    }

    // 2. 数据通道降级为「预绑定」。
    //
    // targetId 指向**原作者卡里的**状态字段内部 id，
    // 到别人机器上必然失效。清空 id、保留字段名记为 pendingName，
    // 对方进状态栏编辑页就会看到「界面里引用了 N 个还未创建的字段」，
    // 一键按组件当前值创建——这条链路是现成的。
    final channel = props['dataChannel'];
    if (channel is Map && channel['targetKind']?.toString() == 'status_field') {
      final name = (channel['semanticLabel']?.toString() ??
              channel['pendingName']?.toString() ??
              '')
          .trim();
      channel['targetId'] = '';
      channel['pendingName'] = name;
    }
    // 角色卡设定通道同理：cardEntryTarget 里的 entryId 也是卡内 id。
    if (channel is Map && channel['targetKind']?.toString() == 'card_entry') {
      channel.remove('cardEntryTarget');
    }
  }

  static Future<String?> _fileToDataUri(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final ext = p.extension(path).toLowerCase();
      final mime = switch (ext) {
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.jpg' || '.jpeg' => 'image/jpeg',
        _ => 'image/png',
      };
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // 导入
  // ==========================================================================

  /// 读取并校验文件，返回**已重映射 id** 的复合件。
  ///
  /// 调用方拿到后直接 `UIAssetService.saveComposite` 即可。
  static Future<UIComposite> readCompositeAsset(File file) async {
    final text = await file.readAsString();

    Map<String, dynamic> root;
    try {
      root = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      throw Exception('文件解析失败，可能已损坏');
    }

    if (!AssetMagic.isSupportedAssetMagic(root['magic']?.toString()) ||
        root['asset_type'] != assetType) {
      throw Exception('这不是 LLM Project 复合组件文件');
    }

    final version = root['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('组件版本过高，请升级 App 后再导入');
    }

    final payload = root['payload'];
    if (payload is! Map) throw Exception('组件载荷缺失');
    final rawComposite = payload['composite'];
    if (rawComposite is! Map) throw Exception('组件数据缺失');

    final remapped = remapIds(Map<String, dynamic>.from(rawComposite));
    return UIComposite.fromJson(remapped);
  }

  /// 重新生成全部 id，并同步改写内部引用。
  ///
  /// **必须做**：id 是时间戳生成的，导入方可能已有同 id 的复合件，
  /// 直接存会静默覆盖对方的东西。
  ///
  /// 内部引用有两处，漏改任何一处都会让组件「看起来正常但连线断了」：
  /// - `exposedPorts[].elementId` → 暴露端口指向哪个子元素
  /// - 子元素 linker 的 `sourceId` / `targetId` → 内部连线
  static Map<String, dynamic> remapIds(Map<String, dynamic> raw) {
    final json = Map<String, dynamic>.from(raw);
    final idMap = <String, String>{};
    var seed = 0;

    String freshId(String oldId) {
      return idMap.putIfAbsent(
        oldId,
        () => 'imp_${DateTime.now().microsecondsSinceEpoch}_${seed++}',
      );
    }

    // 外壳 id。
    final oldRootId = json['id']?.toString() ?? '';
    if (oldRootId.isNotEmpty) json['id'] = freshId(oldRootId);

    // 第一遍：给所有子元素与其 module 分配新 id。
    void collect(List<dynamic> nodes) {
      for (final node in nodes) {
        if (node is! Map) continue;
        final oldId = node['id']?.toString() ?? '';
        if (oldId.isNotEmpty) node['id'] = freshId(oldId);

        final module = node['module'];
        if (module is Map) {
          final oldModuleId = module['id']?.toString() ?? '';
          if (oldModuleId.isNotEmpty) module['id'] = freshId(oldModuleId);
        }

        final composite = node['composite'];
        if (composite is Map) {
          final oldCid = composite['id']?.toString() ?? '';
          if (oldCid.isNotEmpty) composite['id'] = freshId(oldCid);
          if (composite['children'] is List) {
            collect(composite['children'] as List);
          }
        }
      }
    }

    final children = json['children'];
    if (children is List) collect(children);

    // 第二遍：改写引用。必须等所有 id 都分配完再做，
    // 否则先遇到的引用查不到后面才登记的映射。
    void rewrite(List<dynamic> nodes) {
      for (final node in nodes) {
        if (node is! Map) continue;
        final module = node['module'];
        if (module is Map && module['properties'] is Map) {
          final props = module['properties'] as Map;
          final linker = props['linker'];
          if (linker is Map) {
            for (final key in ['sourceId', 'targetId', 'sourceElementId',
                'targetElementId']) {
              final old = linker[key]?.toString() ?? '';
              if (old.isNotEmpty && idMap.containsKey(old)) {
                linker[key] = idMap[old];
              }
            }
          }
          // 数据通道里记录的来源组件 id 同样要跟着换。
          final channel = props['dataChannel'];
          if (channel is Map) {
            final old = channel['sourceComponentId']?.toString() ?? '';
            if (old.isNotEmpty && idMap.containsKey(old)) {
              channel['sourceComponentId'] = idMap[old];
            }
          }
        }
        final composite = node['composite'];
        if (composite is Map && composite['children'] is List) {
          rewrite(composite['children'] as List);
          _rewriteExposedPorts(composite, idMap);
        }
      }
    }

    if (children is List) rewrite(children);
    _rewriteExposedPorts(json, idMap);

    return json;
  }

  static void _rewriteExposedPorts(
    Map<dynamic, dynamic> compositeJson,
    Map<String, String> idMap,
  ) {
    final ports = compositeJson['exposedPorts'];
    if (ports is! List) return;
    for (final port in ports) {
      if (port is! Map) continue;
      final old = port['elementId']?.toString() ?? '';
      if (old.isNotEmpty && idMap.containsKey(old)) {
        port['elementId'] = idMap[old];
      }
    }
  }

  /// 遍历子元素的 properties。复合件可以嵌套，要递归。
  static Future<void> _visitChildren(
    List<dynamic> nodes,
    Future<void> Function(Map<dynamic, dynamic> props) action,
  ) async {
    for (final node in nodes) {
      if (node is! Map) continue;
      final module = node['module'];
      if (module is Map && module['properties'] is Map) {
        await action(module['properties'] as Map);
      }
      final composite = node['composite'];
      if (composite is Map && composite['children'] is List) {
        await _visitChildren(composite['children'] as List, action);
      }
    }
  }
}
