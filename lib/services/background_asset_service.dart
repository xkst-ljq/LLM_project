import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/id_utils.dart';
import '../models/background_card.dart';
import '../services/android_download_service.dart';
import '../services/background_service.dart';

class BackgroundAssetService {
  static const String magic = 'LLM_PROJECT_ASSET_V1';
  static const String assetType = 'background_card';
  static const int formatVersion = 1;

  static final List<int> _startMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_START---\n');
  static final List<int> _endMarker =
  utf8.encode('\n---LLM_PROJECT_ASSET_END---\n');

  static String _safeFileName(String input) {
    final value = input.trim().isEmpty ? '未命名背景' : input.trim();
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

  static String _mimeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.png':
      default:
        return 'image/png';
    }
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

  static Future<String> _uniqueBackgroundName(String baseName) async {
    final all = await BackgroundService.getAll();
    final names = all.map((e) => e.name.trim()).toSet();

    final normalized = baseName.trim().isEmpty ? '导入背景' : baseName.trim();
    if (!names.contains(normalized)) return normalized;

    var index = 1;
    while (names.contains('$normalized ($index)')) {
      index++;
    }
    return '$normalized ($index)';
  }

  static Map<String, dynamic> _buildPayload(BackgroundCard bg) {
    final data = bg.toDb();

    // 图片文件本身就是原图，所以 JSON 里不需要保存旧路径
    data['original_image_path'] = '';

    // 导出的背景卡不应作为预设导入
    data['is_preset'] = 0;

    return {
      'magic': magic,
      'asset_type': assetType,
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'LLM Project',
      'payload': {
        'background': data,
      },
    };
  }

  static Future<File> exportBackgroundCard(BackgroundCard bg) async {
    if (bg.type != 'image') {
      throw Exception('当前仅支持导出图片背景卡');
    }

    if (bg.originalImagePath.trim().isEmpty) {
      throw Exception('背景原图路径为空');
    }

    final source = File(bg.originalImagePath);
    if (!source.existsSync()) {
      throw Exception('背景原图不存在');
    }

    final imageBytes = await source.readAsBytes();

    final payloadJson = jsonEncode(_buildPayload(bg));
    final payloadBase64 = base64Encode(utf8.encode(payloadJson));

    final outputBytes = <int>[
      ...imageBytes,
      ..._startMarker,
      ...utf8.encode(payloadBase64),
      ..._endMarker,
    ];

    final ext = p.extension(bg.originalImagePath).isEmpty
        ? '.png'
        : p.extension(bg.originalImagePath);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports', 'backgrounds'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final fileName = '${_safeFileName(bg.name)}_${_timestampForFile()}.llmbg$ext';
    final file = File(p.join(dir.path, fileName));

    await file.writeAsBytes(outputBytes, flush: true);
    return file;
  }

  static Future<String?> saveBackgroundCardToDownloads(File file) {
    final ext = p.extension(file.path).toLowerCase();

    return AndroidDownloadService.saveFileToDownloads(
      sourcePath: file.path,
      fileName: file.uri.pathSegments.last,
      subDir: 'LLM Project/Backgrounds',
      mimeType: _mimeForExtension(ext),
    );
  }

  static Future<BackgroundCard> readBackgroundAsset(File file) async {
    final bytes = await file.readAsBytes();

    final start = _lastIndexOfBytes(bytes, _startMarker);
    if (start == -1) {
      throw Exception('未识别到 LLM Project 背景卡标识');
    }

    final payloadStart = start + _startMarker.length;
    final end = _indexOfBytes(bytes, _endMarker, payloadStart);

    if (end == -1 || end <= payloadStart) {
      throw Exception('背景卡数据不完整或已损坏');
    }

    final payloadBase64 = utf8.decode(bytes.sublist(payloadStart, end)).trim();

    Map<String, dynamic> root;
    try {
      final jsonText = utf8.decode(base64Decode(payloadBase64));
      root = Map<String, dynamic>.from(jsonDecode(jsonText) as Map);
    } catch (_) {
      throw Exception('背景卡数据解析失败');
    }

    if (root['magic'] != magic || root['asset_type'] != assetType) {
      throw Exception('这不是 LLM Project 背景卡文件');
    }

    final version = root['format_version'];
    if (version is! int || version > formatVersion) {
      throw Exception('背景卡版本过高，请升级 App 后再导入');
    }

    final payload = root['payload'];
    if (payload is! Map) {
      throw Exception('背景卡载荷缺失');
    }

    final rawBg = payload['background'];
    if (rawBg is! Map) {
      throw Exception('背景卡数据缺失');
    }

    return BackgroundCard.fromDb(Map<String, dynamic>.from(rawBg));
  }

  static Future<BackgroundCard> importBackgroundCard(File file) async {
    final bytes = await file.readAsBytes();

    final start = _lastIndexOfBytes(bytes, _startMarker);
    if (start == -1) {
      throw Exception('未识别到 LLM Project 背景卡标识');
    }

    // 先解析数据，确保确实是背景卡
    final bg = await readBackgroundAsset(file);

    if (bg.type != 'image') {
      throw Exception('当前仅支持导入图片背景卡');
    }

    final imageBytes = bytes.sublist(0, start);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'imported_assets', 'backgrounds', _timestampForFile()),
    );
    await dir.create(recursive: true);

    final ext = p.extension(file.path).isEmpty ? '.png' : p.extension(file.path);
    final imageFile = File(p.join(dir.path, 'original$ext'));
    await imageFile.writeAsBytes(imageBytes, flush: true);

    final newId = IdUtils.timestampId();
    final newName = await _uniqueBackgroundName(bg.name);

    final imported = BackgroundCard(
      id: newId,
      name: newName,
      type: 'image',
      colorValue: bg.colorValue,
      originalImagePath: imageFile.path,
      sceneSetting: bg.sceneSetting,
      isPreset: false,
    );

    await BackgroundService.insert(imported);
    BackgroundService.versionNotifier.value++;

    return imported;
  }
}