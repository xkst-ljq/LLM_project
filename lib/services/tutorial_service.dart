import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const String _newUserGuideDialogShownKey =
      'tutorial.new_user_guide_dialog_shown';

  static Future<bool> shouldShowNewUserGuideDialog() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_newUserGuideDialogShownKey) ?? false);
  }

  static Future<void> markNewUserGuideDialogShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_newUserGuideDialogShownKey, true);
  }

  static Future<void> resetNewUserGuideDialogShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_newUserGuideDialogShownKey);
  }
}
