import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class UserService {
  static const String _key = 'user_profile';

  /// 全局用户设定版本号。
  /// 主菜单用户设定保存后 +1，聊天页可监听它来刷新当前显示的用户昵称/头像。
  static final ValueNotifier<int> versionNotifier = ValueNotifier<int>(0);

  static Future<UserProfile> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return UserProfile();
    return UserProfile.fromJson(jsonDecode(json));
  }

  static Future<void> saveUser(UserProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(user.toJson()));

    // 通知已打开的聊天页刷新全局用户设定
    versionNotifier.value++;
  }
}