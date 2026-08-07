import 'package:shared_preferences/shared_preferences.dart';

/// 工具的本地设置（持久化）。
///
/// 承载：默认转译保存位置 + AI API 配置（单套，不做多配置管理）。
class AppSettings {
  static const _kOutputDir = 'output_dir';
  static const _kApiBaseUrl = 'api_base_url';
  static const _kApiKey = 'api_key';
  static const _kApiModel = 'api_model';
  static const _kAiUiRefineEnabled = 'ai_ui_refine_enabled';

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

  // ---------- AI UI 精修（慢速，可选） ----------

  /// 是否启用 AI 对 UI 方案做慢速精修。
  ///
  /// 默认关闭：UI 阶段使用确定性 opening/scene 骨架，避免长 prompt 等待
  /// 与模型空返回。打开后才让模型生成/精修 UiDesignPlan。
  static Future<bool> getAiUiRefineEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAiUiRefineEnabled) ?? false;
  }

  static Future<void> setAiUiRefineEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAiUiRefineEnabled, value);
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
