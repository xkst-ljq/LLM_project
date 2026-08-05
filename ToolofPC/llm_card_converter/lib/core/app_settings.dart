import 'package:shared_preferences/shared_preferences.dart';

/// 工具的本地设置（持久化）。
///
/// 承载：默认转译保存位置 + AI API 配置（单套，不做多配置管理）。
class AppSettings {
  static const _kOutputDir = 'output_dir';
  static const _kApiBaseUrl = 'api_base_url';
  static const _kApiKey = 'api_key';
  static const _kApiModel = 'api_model';
  static const _kConfirmBlueprint = 'confirm_blueprint';

  /// 默认转译保存目录。空字符串表示未设置（首次保存时会询问）。
  static Future<String> getOutputDir() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOutputDir) ?? '';
  }

  static Future<void> setOutputDir(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOutputDir, dir);
  }

  static Future<void> clearOutputDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOutputDir);
  }

  // ---------- AI API 配置（单套） ----------

  static Future<ApiConfig> getApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiConfig(
      baseUrl: prefs.getString(_kApiBaseUrl) ?? '',
      apiKey: prefs.getString(_kApiKey) ?? '',
      model: prefs.getString(_kApiModel) ?? '',
    );
  }

  static Future<void> setApiConfig(ApiConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiBaseUrl, c.baseUrl);
    await prefs.setString(_kApiKey, c.apiKey);
    await prefs.setString(_kApiModel, c.model);
  }

  // ---------- 蓝图确认开关（默认开启） ----------

  /// 是否在生成 UI 前让 AI 先出「分条目蓝图」并等待用户确认。
  /// 默认开启；关闭则跳过确认、AI 直接生成最终意图。
  static Future<bool> getConfirmBlueprint() async {
    final prefs = await SharedPreferences.getInstance();
    // 默认 true（开启确认）
    return prefs.getBool(_kConfirmBlueprint) ?? true;
  }

  static Future<void> setConfirmBlueprint(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConfirmBlueprint, v);
  }
}

/// AI API 配置（OpenAI 兼容）。
class ApiConfig {
  String baseUrl;
  String apiKey;
  String model;

  ApiConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
          apiKey.trim().isNotEmpty &&
          model.trim().isNotEmpty;
}
