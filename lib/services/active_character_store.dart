import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// Single source of truth for the "current role" that both the home page and
/// the chat page rely on.
///
/// Home selects a role and chat switches roles mid-session; both must write to
/// the same key so the two pages never diverge (spec §12.3).
class ActiveCharacterStore {
  static const _key = 'home_active_character_id';

  static Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key);
  }

  static Future<void> write(String? characterId) async {
    final preferences = await SharedPreferences.getInstance();
    if (characterId == null) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, characterId);
    }
  }

  /// Resolves the current role id: the persisted choice first, then the most
  /// recently messaged character from the database.
  static Future<String?> resolve() async {
    final persisted = await read();
    if (persisted != null) return persisted;
    return DatabaseService.getLastActiveCharacterId();
  }
}
