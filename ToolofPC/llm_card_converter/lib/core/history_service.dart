import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一条转译历史记录（轻量清单，不存转换结果本身）。
class HistoryEntry {
  final String id; // 唯一 id（时间戳）
  final String name; // 角色名
  final DateTime time; // 转译时间
  final bool success; // 转译状态：成功 / 失败
  bool saved; // 保存状态：已保存 / 未保存
  String savedPath; // 保存位置（已保存才有）
  final String thumbPath; // 封面缩略图文件路径（有立绘才有，否则空）

  HistoryEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.success,
    this.saved = false,
    this.savedPath = '',
    this.thumbPath = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time.toIso8601String(),
        'success': success,
        'saved': saved,
        'saved_path': savedPath,
        'thumb_path': thumbPath,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
        success: j['success'] == true,
        saved: j['saved'] == true,
        savedPath: j['saved_path']?.toString() ?? '',
        thumbPath: j['thumb_path']?.toString() ?? '',
      );
}

/// 历史记录存储：索引 JSON + 缩略图文件，存于应用私有目录。
class HistoryService {
  static Directory? _dir;

  static Future<Directory> _historyDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'history'));
    if (!d.existsSync()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static Future<File> _indexFile() async {
    final d = await _historyDir();
    return File(p.join(d.path, 'index.json'));
  }

  /// 读取全部历史（按时间倒序）。
  static Future<List<HistoryEntry>> getAll() async {
    try {
      final f = await _indexFile();
      if (!f.existsSync()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      final entries =
          list.map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList();
      entries.sort((a, b) => b.time.compareTo(a.time));
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<HistoryEntry> entries) async {
    final f = await _indexFile();
    await f.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// 新增一条记录。[imageBytes] 有则存一份缩略图（原样存 PNG 字节即可，文件不大）。
  /// 返回新记录 id。
  static Future<String> add({
    required String name,
    required bool success,
    List<int>? imageBytes,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    var thumbPath = '';
    if (imageBytes != null && imageBytes.isNotEmpty) {
      try {
        final d = await _historyDir();
        final tf = File(p.join(d.path, '$id.png'));
        await tf.writeAsBytes(imageBytes, flush: true);
        thumbPath = tf.path;
      } catch (_) {}
    }
    final entries = await getAll();
    entries.insert(
      0,
      HistoryEntry(
        id: id,
        name: name,
        time: DateTime.now(),
        success: success,
        thumbPath: thumbPath,
      ),
    );
    await _saveAll(entries);
    return id;
  }

  /// 标记某条为已保存，并记录保存路径。
  static Future<void> markSaved(String id, String savedPath) async {
    final entries = await getAll();
    for (final e in entries) {
      if (e.id == id) {
        e.saved = true;
        e.savedPath = savedPath;
        break;
      }
    }
    await _saveAll(entries);
  }

  /// 删除一条（连带缩略图）。
  static Future<void> remove(String id) async {
    final entries = await getAll();
    final target = entries.where((e) => e.id == id).toList();
    for (final e in target) {
      if (e.thumbPath.isNotEmpty) {
        try {
          final f = File(e.thumbPath);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
    entries.removeWhere((e) => e.id == id);
    await _saveAll(entries);
  }

  /// 清空全部历史。
  static Future<void> clear() async {
    final entries = await getAll();
    for (final e in entries) {
      if (e.thumbPath.isNotEmpty) {
        try {
          final f = File(e.thumbPath);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
    await _saveAll([]);
  }
}
