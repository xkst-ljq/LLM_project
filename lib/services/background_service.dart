import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/background_card.dart';
import 'database_service.dart';

class BackgroundService {
  static const String _currentBackgroundKey = 'current_background_id';
  static final ValueNotifier<int> _versionNotifier = ValueNotifier<int>(0);
  static ValueNotifier<int> get versionNotifier => _versionNotifier;
  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ===== 同步缓存 =====
  //
  // 背景查询本身很轻，但它前面挂着三段一次性的异步开销：
  // 打开 sqlite（首次 openDatabase 要建表 / 跑 migration）、
  // SharedPreferences 首次 getInstance（要把整个 plist/xml 读进来）、
  // 以及 ensureBackgroundsTable 每次都查一遍 sqlite_master。
  // 加起来在真机冷启动能到 100ms 量级，表现就是进聊天页背景空一拍。
  //
  // 背景数据极小且全进程共用，缓存在内存里即可。所有写入口
  // (insert/update/delete/setCurrent) 都会刷新缓存，不存在读到旧值。
  static List<BackgroundCard>? _cache;
  static String? _cachedCurrentId;
  static bool get isWarm => _cache != null;

  /// 同步取当前背景。缓存未就绪时返回 null（调用方需回退到异步路径）。
  static BackgroundCard? peekCurrent() {
    final all = _cache;
    if (all == null || all.isEmpty) return null;
    final id = _cachedCurrentId;
    if (id != null && id.isNotEmpty) {
      for (final bg in all) {
        if (bg.id == id) return bg;
      }
    }
    return _findDefaultBackground(all);
  }

  /// 同步按 id 取背景（角色绑定的独立背景走这里）。
  /// 缓存未就绪或 id 不存在时返回 null。
  static BackgroundCard? peekById(String id) {
    final all = _cache;
    if (all == null || id.isEmpty) return null;
    for (final bg in all) {
      if (bg.id == id) return bg;
    }
    return null;
  }

  /// 预热缓存。在 main() 里尽早调用，让聊天页首帧就能同步拿到背景。
  static Future<void> warmUp() async {
    try {
      await ensurePresetsExist();
      _cache = await getAll();
      final prefs = await SharedPreferences.getInstance();
      _cachedCurrentId = prefs.getString(_currentBackgroundKey);
    } catch (e) {
      debugPrint('背景预热失败: $e');
    }
  }

  /// 数据变更后重建缓存，并通知监听者。
  static Future<void> _refreshCache() async {
    try {
      _cache = await getAll();
    } catch (e) {
      debugPrint('背景缓存刷新失败: $e');
    }
    _versionNotifier.value++;
  }

  /// 获取所有背景
  static Future<List<BackgroundCard>> getAll() async {
    await DatabaseService.ensureBackgroundsTable();
    final db = await DatabaseService.database;
    final results = await db.query('backgrounds', orderBy: 'id ASC');
    final list = results.map((r) => BackgroundCard.fromDb(r)).toList();
    // 顺带刷新同步缓存：任何一次异步读都能让后续的 peek 命中。
    _cache = list;
    return list;
  }

  /// 获取当前使用的背景
  static BackgroundCard? _findDefaultBackground(List<BackgroundCard> all) {
    if (all.isEmpty) return null;

    for (final bg in all) {
      if (bg.id == 'default') return bg;
    }

    for (final bg in all) {
      if (bg.isPreset) return bg;
    }

    return all.first;
  }

  static Future<BackgroundCard?> getDefault() async {
    await ensurePresetsExist();

    final all = await getAll();
    return _findDefaultBackground(all);
  }

  /// 获取当前使用的背景
  static Future<BackgroundCard?> getCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_currentBackgroundKey);
    _cachedCurrentId = id;
    final all = await getAll();

    if (all.isEmpty) return null;

    final defaultBg = _findDefaultBackground(all);

    if (id != null && id.isNotEmpty) {
      for (final bg in all) {
        if (bg.id == id) return bg;
      }

      // 当前记录的背景 ID 已失效，回退默认背景
      if (defaultBg != null) {
        await prefs.setString(_currentBackgroundKey, defaultBg.id);
      }
      return defaultBg;
    }

    // 没有设置过当前背景时，优先使用 default
    if (defaultBg != null) {
      await prefs.setString(_currentBackgroundKey, defaultBg.id);
    }

    return defaultBg;
  }

  /// 设置当前背景
  static Future<void> setCurrent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentBackgroundKey, id);
    _cachedCurrentId = id;
    _versionNotifier.value++;
  }

  /// 插入背景
  static Future<void> insert(BackgroundCard bg) async {
    await DatabaseService.ensureBackgroundsTable();

    final db = await DatabaseService.database;
    final data = bg.toDb();
    final now = _nowMs();

    data.putIfAbsent('created_at', () => now);
    data['updated_at'] = now;

    await db.insert('backgrounds', data);
    await _refreshCache();
  }

  /// 更新背景
  static Future<void> update(BackgroundCard bg) async {
    await DatabaseService.ensureBackgroundsTable();

    final db = await DatabaseService.database;
    final data = bg.toDb();

    data['updated_at'] = _nowMs();

    await db.update(
      'backgrounds',
      data,
      where: 'id = ?',
      whereArgs: [bg.id],
    );

    await _refreshCache();
  }

  /// 删除背景（预设不可删）
  static Future<void> delete(String id) async {
    final db = await DatabaseService.database;
    await db.delete('backgrounds', where: 'id = ?', whereArgs: [id]);
    await _refreshCache();
  }

  /// 确保预设背景存在（如果没有，自动插入）
  static Future<void> ensurePresetsExist() async {
    try {
      await DatabaseService.ensureBackgroundsTable();

      final all = await getAll();
      final hasDefault = all.any((b) => b.id == 'default');

      if (!hasDefault) {
        final defaultBg = BackgroundCard(
          id: 'default',
          name: '默认背景',
          type: 'gradient',
          colorValue:
          '{"colors":["#E3F2FD","#F3E5F5"],"begin":"topCenter","end":"bottomCenter"}',
          sceneSetting: '默认聊天背景',
          isPreset: true,
        );

        await insert(defaultBg);
        _versionNotifier.value++;
      }
    } catch (e) {
      // 绝对不要在这里 resetDatabase。
      // 预设背景修复失败不应该导致用户角色卡、世界书、聊天记录被清空。
      debugPrint('确保预设背景存在失败: $e');
    }
  }
}