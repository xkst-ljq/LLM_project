import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/module_interface.dart';
import '../services/api_config_service.dart';

class ChatModule extends AppModule {
  @override
  String get id => 'text_chat';
  @override
  String get name => '文本对话';

  late FlutterSecureStorage _storage;
  final Dio _dio = Dio();

  int estimateTokens(String modelId, List<Map<String, String>> messages) {
    // TODO: 后期接入各模型的精确 Tokenizer
    int totalChars = messages.fold(0, (sum, m) => sum + (m['content']?.length ?? 0));
    return (totalChars / 2).ceil();
  }

  @override
  void initialize() {
    _storage = const FlutterSecureStorage();
    _dio.options.connectTimeout = const Duration(seconds: 10);
  }

  @override
  void dispose() {}

  @override
  void setPerformanceLevel(ModulePerformanceLevel level) {
    // TODO: 后期实现角色模型的精度切换
  }

  Future<void> sendBackgroundMessage(String message) async {
    // TODO: 后期接入后台推送 / 前台沉浸式搭话
  }

  void updateStatusBar({int? affection, String? sceneTime}) {
    // TODO: 后期更新伪状态栏的好感度、情景时间等
  }

  Future<String?> get apiKey => _storage.read(key: 'api_key');
  Future<String?> get baseUrl => _storage.read(key: 'base_url');
  Future<void> saveSettings(String apiKey, String baseUrl) async {
    await _storage.write(key: 'api_key', value: apiKey);
    await _storage.write(key: 'base_url', value: baseUrl);
  }

  Stream<String> sendMessage(String systemPrompt, List<Map<String, String>> history) async* {
    // 1. 尝试从 ApiConfigService 获取活动配置
    final config = await ApiConfigService.getActiveConfig();
    String? key;
    String? url;

    if (config != null && config.apiKey.isNotEmpty && config.baseUrl.isNotEmpty) {
      key = config.apiKey;
      url = config.baseUrl;
    } else {
      // 2. 回退到旧版安全存储（兼容旧数据）
      key = await _storage.read(key: 'api_key');
      url = await _storage.read(key: 'base_url');
    }

    if (key == null || key.isEmpty || url == null || url.isEmpty) {
      throw Exception('未配置 API Key 或 Base URL');
    }

    final response = await _dio.post(
      '$url/v1/chat/completions',
      data: {
        'model': config?.model ?? 'deepseek-chat',  // 使用配置的模型
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...history,
        ],
        'stream': true,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $key'},
        responseType: ResponseType.stream,
      ),
    );
    final lineStream = response.data.stream
        .map<List<int>>((chunk) => List<int>.from(chunk))
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final rawLine in lineStream) {
      final line = rawLine.trim();

      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;

      final data = line.substring(5).trim();

      if (data == '[DONE]') return;

      try {
        final parsed = jsonDecode(data);
        final content = parsed['choices']?[0]?['delta']?['content'];

        if (content != null) {
          yield content.toString();
        }
      } catch (_) {
        // 可选：调试时再打开
        // debugPrint('SSE 解析失败: $data');
      }
    }
  }
}