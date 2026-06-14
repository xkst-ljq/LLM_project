import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseService {
  static Database? _db;
  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'chat_history.db');
    return await openDatabase(
      path,
      version: 3, // 升级版本号
      onCreate: (db, version) async {
        // 消息表
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            version INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
  CREATE TABLE characters (
 id TEXT PRIMARY KEY,
 name TEXT NOT NULL,
 avatar TEXT DEFAULT '',
 card_image_path TEXT DEFAULT '',
 description TEXT DEFAULT '',
 system_prompt TEXT DEFAULT '',
 world_book_id TEXT DEFAULT '',
 background_id TEXT DEFAULT '',
 user_name TEXT DEFAULT '',
 user_avatar TEXT DEFAULT '',
 user_detail_setting TEXT DEFAULT '',
 card_type TEXT DEFAULT 'character',
 entries_json TEXT DEFAULT '[]',
 opening_greetings TEXT DEFAULT '[]',
 meta_json TEXT DEFAULT '{}',
 state_json TEXT DEFAULT '{}',
 created_at INTEGER DEFAULT 0,
 updated_at INTEGER DEFAULT 0
 )
''');
        await db.execute('''
    CREATE TABLE backgrounds (
 id TEXT PRIMARY KEY,
 name TEXT NOT NULL,
 type TEXT NOT NULL,
 color_value TEXT DEFAULT '',
 original_image_path TEXT DEFAULT '',
 portrait_crop_path TEXT DEFAULT '',
 landscape_crop_path TEXT DEFAULT '',
 scene_setting TEXT DEFAULT '',
 is_preset INTEGER DEFAULT 0,
 created_at INTEGER DEFAULT 0,
 updated_at INTEGER DEFAULT 0
 )
  ''');
        await db.insert('backgrounds', {
          'id': 'default',
          'name': '默认背景',
          'type': 'gradient',
          'color_value':
              '{"colors":["#E3F2FD","#F3E5F5"],"begin":"topCenter","end":"bottomCenter"}',
          'original_image_path': '',
          'portrait_crop_path': '',
          'landscape_crop_path': '',
          'scene_setting': '默认聊天背景',
          'is_preset': 1,
        });
        await db.execute('''
          CREATE TABLE world_books (
 id TEXT PRIMARY KEY,
 name TEXT NOT NULL,
 description TEXT DEFAULT '',
 detailed_setting TEXT DEFAULT '',
 entries_json TEXT DEFAULT '[]',
 cover_image_path TEXT DEFAULT '',
 is_preset INTEGER DEFAULT 0,
 created_at INTEGER DEFAULT 0,
 updated_at INTEGER DEFAULT 0
 )
        ''');
        // 插入默认角色
        await db.insert('characters', {
          'id': 'default',
          'name': '默认助手',
          'avatar': '',
          'card_image_path': '',
          'description': '初始角色',
          'system_prompt': '你是一个测试助手。请用简短的语言回复用户，每句回复不超过一句话。避免冗长。',
          'world_book_id': '',
          'background_id': '',
          'user_name': '',
          'user_avatar': '',
          'user_detail_setting': '',
          'card_type': 'character',
          'entries_json': '[]',
          'opening_greetings': '[]',
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _safeAddColumn(
            db,
            'characters',
            'state_json',
            "TEXT DEFAULT '{}'",
          );
          await _safeAddColumn(
            db,
            'characters',
            'created_at',
            'INTEGER DEFAULT 0',
          );
          await _safeAddColumn(
            db,
            'characters',
            'updated_at',
            'INTEGER DEFAULT 0',
          );

          await _safeAddColumn(
            db,
            'backgrounds',
            'created_at',
            'INTEGER DEFAULT 0',
          );
          await _safeAddColumn(
            db,
            'backgrounds',
            'updated_at',
            'INTEGER DEFAULT 0',
          );

          await _safeAddColumn(
            db,
            'world_books',
            'created_at',
            'INTEGER DEFAULT 0',
          );
          await _safeAddColumn(
            db,
            'world_books',
            'updated_at',
            'INTEGER DEFAULT 0',
          );
        }

        if (oldVersion < 3) {
          // 角色扩展元信息（标签、作者、来源、post_history、示例对话等）
          await _safeAddColumn(
            db,
            'characters',
            'meta_json',
            "TEXT DEFAULT '{}'",
          );
        }
      },
    );
  }

  static Future<void> _safeAddColumn(
      Database db,
      String table,
      String column,
      String definition,
      ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);

    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// 确保 backgrounds 表存在（用于旧版本升级）
  static Future<void> ensureBackgroundsTable() async {
    final db = await database;

    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='backgrounds'",
    );

    if (result.isEmpty) {
      await db.execute('''
      CREATE TABLE backgrounds (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        color_value TEXT DEFAULT '',
        original_image_path TEXT DEFAULT '',
        portrait_crop_path TEXT DEFAULT '',
        landscape_crop_path TEXT DEFAULT '',
        scene_setting TEXT DEFAULT '',
        is_preset INTEGER DEFAULT 0,
        created_at INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT 0
      )
    ''');

      final now = _nowMs();

      await db.insert('backgrounds', {
        'id': 'default',
        'name': '默认背景',
        'type': 'gradient',
        'color_value':
        '{"colors":["#E3F2FD","#F3E5F5"],"begin":"topCenter","end":"bottomCenter"}',
        'scene_setting': '默认聊天背景',
        'is_preset': 1,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await _safeAddColumn(
        db,
        'backgrounds',
        'created_at',
        'INTEGER DEFAULT 0',
      );
      await _safeAddColumn(
        db,
        'backgrounds',
        'updated_at',
        'INTEGER DEFAULT 0',
      );
    }
  }

  static Future<void> resetDatabase() async {
    _db = null; // 清除缓存
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'chat_history.db');
    await deleteDatabase(path); // 删除数据库文件
  }

  // ========== 消息相关 ==========

  static Future<int> insertMessage({
    required String characterId,
    required String role,
    required String content,
    int version = 1,
  }) async {
    final db = await database;
    return await db.insert('messages', {
      'character_id': characterId,
      'role': role,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'version': version,
    });
  }

  static Future<List<Map<String, dynamic>>> getMessages(
    String characterId,
  ) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'timestamp ASC',
    );
  }

  static Future<int> deleteMessage(int id) async {
    final db = await database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteMessagesByCharacterId(String characterId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'character_id = ?',
      whereArgs: [characterId],
    );
  }

  static Future<int> deleteMessagesAfter(
      String characterId,
      int afterTimestamp,
      ) async {
    final db = await database;
    return await db.delete(
      'messages',
      where: 'character_id = ? AND timestamp >= ?',
      whereArgs: [characterId, afterTimestamp],
    );
  }

  static Future<void> updateMessageContent(int id, String newContent) async {
    final db = await database;
    await db.update(
      'messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========== 世界书相关 ==========

  static Future<List<Map<String, dynamic>>> getAllWorldBooks() async {
    final db = await database;
    return await db.query('world_books', orderBy: 'id ASC');
  }

  static Future<void> insertWorldBook(Map<String, dynamic> worldBook) async {
    final db = await database;
    final data = Map<String, dynamic>.from(worldBook);
    final now = _nowMs();

    data.putIfAbsent('created_at', () => now);
    data['updated_at'] = now;

    await db.insert(
      'world_books',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateWorldBook(Map<String, dynamic> worldBook) async {
    final db = await database;
    final data = Map<String, dynamic>.from(worldBook);
    data['updated_at'] = _nowMs();

    await db.update(
      'world_books',
      data,
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  static Future<void> deleteWorldBook(String id) async {
    final db = await database;
    await db.delete('world_books', where: 'id = ?', whereArgs: [id]);
  }

  // ========== 角色相关 ==========

  static Future<List<Map<String, dynamic>>> getAllCharacters() async {
    final db = await database;
    return await db.query('characters', orderBy: 'id ASC');
  }

  static Future<void> insertCharacter(Map<String, dynamic> character) async {
    final db = await database;
    final data = Map<String, dynamic>.from(character);
    final now = _nowMs();

    data.putIfAbsent('created_at', () => now);
    data['updated_at'] = now;

    await db.insert(
      'characters',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateCharacter(Map<String, dynamic> character) async {
    final db = await database;
    final data = Map<String, dynamic>.from(character);
    data['updated_at'] = _nowMs();

    await db.update(
      'characters',
      data,
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  static Future<void> deleteCharacter(String id) async {
    final db = await database;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取最近有对话记录的角色 ID
  static Future<String?> getLastActiveCharacterId() async {
    final db = await database;
    final result = await db.query(
      'messages',
      columns: ['character_id'],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['character_id'] as String?;
    }
    return null;
  }
}
