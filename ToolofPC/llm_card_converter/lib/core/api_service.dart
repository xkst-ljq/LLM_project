import 'dart:io';

import 'package:dio/dio.dart';

/// 一条聊天消息。
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

/// 聊天补全调用参数。
class ChatCompleteOptions {
  final double temperature;
  final int? maxTokens;
  final bool jsonMode;
  final Duration timeout;

  /// 网络瞬断 / 握手失败 / 5xx / 429 的自动重试次数。
  ///
  /// 注意：400 这类请求结构错误不会重试——例如某些服务不支持
  /// `response_format` 时，上层会直接降级为普通请求。
  final int retryCount;

  /// 首次重试等待时间；后续按 2x 简单退避。
  final Duration retryDelay;

  /// 预留扩展：不同 OpenAI 兼容服务的自定义字段。
  ///
  /// 例如部分服务支持 `top_p` / `presence_penalty` / `seed` 等，
  /// 调用方可在不改底层 API 的情况下传入。
  final Map<String, dynamic> extraBody;

  const ChatCompleteOptions({
    this.temperature = 0.2,
    this.maxTokens,
    this.jsonMode = false,
    this.timeout = const Duration(seconds: 120),
    this.retryCount = 2,
    this.retryDelay = const Duration(milliseconds: 900),
    this.extraBody = const {},
  });
}

/// OpenAI 兼容 API 调用（获取模型列表 / 聊天补全）。
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
  /// 新的 UI 理解链路需要多段消息、JSON mode 与额外 body 字段，
  /// 因此后续任务层应优先调用本方法；旧的 [chatComplete] 只是兼容包装。
  static Future<String> chatMessages({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    ChatCompleteOptions options = const ChatCompleteOptions(),
  }) async {
    Object? lastError;
    final attempts = options.retryCount < 0 ? 1 : options.retryCount + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _chatMessagesOnce(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          options: options,
        );
      } catch (e) {
        lastError = e;
        final canRetry = attempt + 1 < attempts && _isRetryableError(e);
        if (!canRetry) rethrow;
        final multiplier = 1 << attempt;
        await Future<void>.delayed(
          Duration(milliseconds: options.retryDelay.inMilliseconds * multiplier),
        );
      }
    }
    throw lastError ?? Exception('请求失败：未知错误');
  }

  static Future<String> _chatMessagesOnce({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    required ChatCompleteOptions options,
  }) async {
    final base = normalizeBase(baseUrl);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: options.timeout,
    ));

    final body = <String, dynamic>{
      'model': model,
      'temperature': options.temperature,
      'messages': messages.map((e) => e.toJson()).toList(),
      if (options.maxTokens != null) 'max_tokens': options.maxTokens,
      if (options.jsonMode) 'response_format': {'type': 'json_object'},
      ...options.extraBody,
    };

    final response = await dio.post(
      '$base/v1/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
      data: body,
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

  static bool _isRetryableError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode ?? 0;
          return code == 408 || code == 409 || code == 425 || code == 429 ||
              (code >= 500 && code <= 599);
        case DioExceptionType.unknown:
          final inner = error.error;
          return inner is SocketException || inner is HandshakeException;
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
          return false;
      }
    }
    // 「模型返回为空 / 未返回内容」是可恢复的：常见于云端 API 在
    // json_object 模式 + 超长上下文下偶发空 content，重试往往就成功。
    if (error is FormatException ||
        (error is Exception &&
            (error.toString().contains('模型返回为空') ||
                error.toString().contains('模型未返回内容')))) {
      return true;
    }
    return error is SocketException || error is HandshakeException;
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
  }) {
    return chatMessages(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: userPrompt),
      ],
      options: ChatCompleteOptions(
        temperature: temperature,
        timeout: timeout,
      ),
    );
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
