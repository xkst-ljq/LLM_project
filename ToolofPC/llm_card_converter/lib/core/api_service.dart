import 'package:dio/dio.dart';

/// OpenAI 兼容 API 调用（获取模型列表 / 后续聊天补全）。
class ApiService {
  /// 规范化 Base URL：去掉结尾斜杠与多余的 /v1，返回不含 /v1 的根地址。
  static String normalizeBase(String baseUrl) {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.toLowerCase().endsWith('/v1')) {
      u = u.substring(0, u.length - 3);
    }
    return u;
  }

  /// 拉取可用模型列表。失败抛异常。
  static Future<List<String>> fetchModels(String baseUrl, String apiKey) async {
    final base = normalizeBase(baseUrl);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    final response = await dio.get(
      '$base/v1/models',
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    if (response.statusCode == 200) {
      final data = response.data['data'] as List;
      final ids = data
          .map<String>((m) => (m['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      ids.sort();
      return ids;
    }
    throw Exception('请求失败：HTTP ${response.statusCode}');
  }

  /// 聊天补全（非流式）。返回模型输出的文本内容。
  ///
  /// [systemPrompt] 系统指令；[userPrompt] 用户内容。
  /// [temperature] 默认较低，便于结构化稳定输出。
  static Future<String> chatComplete({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final base = normalizeBase(baseUrl);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: timeout,
    ));
    final response = await dio.post(
      '$base/v1/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': model,
        'temperature': temperature,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );
    if (response.statusCode != 200) {
      throw Exception('请求失败：HTTP ${response.statusCode}');
    }
    final data = response.data;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('模型未返回内容');
    }
    final content = choices.first['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw Exception('模型返回为空');
    }
    return content;
  }

  /// 粗略判断模型返回是否为"拒绝/审核拦截"（常见于 NSFW 内容触发内容政策）。
  /// 用于让 AI 步骤在被拒时优雅跳过，而不是当成普通失败。
  static bool looksLikeRefusal(String text) {
    final t = text.toLowerCase();
    const markers = [
      "i can't", "i cannot", "i can not", "i'm unable", "i am unable",
      "i won't", "i will not",
      "can't assist", "cannot assist", "can't help with", "cannot help with",
      "not able to help", "unable to help",
      "against my", "content policy", "usage policies", "violates",
      "i'm sorry, but", "i am sorry, but", "as an ai",
      '无法协助', '无法帮助', '无法提供', '不能提供', '抱歉，我不能', '抱歉，我无法',
      '违反', '内容政策', '不适当', '不当内容', '无法处理该请求',
    ];
    // 只在文本较短（典型拒绝信）时才判定，避免长正文里偶含关键词被误杀
    if (text.trim().length > 400) return false;
    return markers.any(t.contains);
  }
}
