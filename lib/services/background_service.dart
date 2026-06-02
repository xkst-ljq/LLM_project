import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/background_card.dart';
import 'database_service.dart';

class BackgroundService {
  static const String _currentBackgroundKey = 'current_background_id';
  static final ValueNotifier<int> _versionNotifier = ValueNotifier<int>(0);
  static ValueNotifier<int> get versionNotifier => _versionNotifier;

  /// 获取所有背景
  static Future<List<BackgroundCard>> getAll() async {
    await DatabaseService.ensureBackgroundsTable();
    final db = await DatabaseService.database;
    final results = await db.query('backgrounds', orderBy: 'id ASC');
    return results.map((r) => BackgroundCard.fromDb(r)).toList();
  }

  /// 获取当前使用的背景
  static Future<BackgroundCard?> getCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_currentBackgroundKey);
    final all = await getAll();
    if (id != null) {
      return all.firstWhere((b) => b.id == id, orElse: () => all.first);
    }
    return all.isNotEmpty ? all.first : null;
  }

  /// 设置当前背景
  static Future<void> setCurrent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentBackgroundKey, id);
  }

  /// 插入背景
  static Future<void> insert(BackgroundCard bg) async {
    final db = await DatabaseService.database;
    await db.insert('backgrounds', bg.toDb());
  }

  /// 更新背景
  static Future<void> update(BackgroundCard bg) async {
    final db = await DatabaseService.database;
    await db.update('backgrounds', bg.toDb(), where: 'id = ?', whereArgs: [bg.id]);
    _versionNotifier.value++; // 通知聊天页刷新
  }

  /// 删除背景（预设不可删）
  static Future<void> delete(String id) async {
    final db = await DatabaseService.database;
    await db.delete('backgrounds', where: 'id = ?', whereArgs: [id]);
  }

  /// 确保预设背景存在（如果没有，自动插入）
  static Future<void> ensurePresetsExist() async {
    try {
      final all = await getAll();
      if (all.isEmpty) {
        final defaultBg = BackgroundCard(
          id: 'default',
          name: '默认背景',
          type: 'gradient',
          colorValue: '{"colors":["#E3F2FD","#F3E5F5"],"begin":"topCenter","end":"bottomCenter"}',
          sceneSetting: '默认聊天背景',
          isPreset: true,
        );
        await insert(defaultBg);
      }
    } catch (e) {
      debugPrint('数据库异常，强制重建: $e');
      await DatabaseService.resetDatabase(); // 删除文件并重置缓存
      _versionNotifier.value++; // 通知UI刷新
      // 重新获取数据库（此时会触发 onCreate）
      final all = await getAll(); // 这会调用 _initDb 并执行 onCreate
      if (all.isEmpty) {
        final defaultBg = BackgroundCard(
          id: 'default',
          name: '默认背景',
          type: 'gradient',
          colorValue: '{"colors":["#E3F2FD","#F3E5F5"],"begin":"topCenter","end":"bottomCenter"}',
          sceneSetting: '默认聊天背景',
          isPreset: true,
        );
        await insert(defaultBg);
      }
    }
  }
}