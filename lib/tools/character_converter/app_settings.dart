import '../../models/api_config.dart' as app;
import '../../services/api_config_service.dart';

/// PC 转译内核需要的 AI 配置形态。
///
/// 与 PC 工具的 `app_settings.dart` 里的 [ApiConfig] 结构一致，
/// 供 `lib/tools/character_converter` 各 AI 阶段消费。
class ApiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  ApiConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

/// App 内嵌转译工具的环境适配层。
///
/// PC 独立工具用 SharedPreferences 存自己的 API 配置；移植进 App 后改为
/// 直接读 App 的 API 配置管理（[ApiConfigService]）。各 AI 阶段仍调用
/// [getApiConfig]，无需改动内核。
class AppSettings {
  /// 本次转译指定的 AI 覆盖配置；null 表示使用 App 正在启用的配置。
  ///
  /// 转译开始前设置、结束（成功/失败/取消）后务必复位为 null，
  /// 保证下一次转译默认回到当前启用配置。
  static app.ApiConfig? conversionAiOverride;

  static Future<ApiConfig> getApiConfig() async {
    final src = conversionAiOverride ?? await ApiConfigService.getActiveConfig();
    if (src == null) return ApiConfig();
    return ApiConfig(
      baseUrl: src.baseUrl,
      apiKey: src.apiKey,
      model: src.model,
    );
  }
}
