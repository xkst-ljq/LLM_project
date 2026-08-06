import 'api_service.dart';
import 'ai_json_utils.dart';
import 'app_settings.dart';

class JsonAiResult {
  final Map<String, dynamic> json;

  /// 本次结构化调用的完整消息转录：输入上下文 + AI 原始输出 + 修复轮次。
  ///
  /// UI 转译完成后的“与转译 AI 对话”会把它作为隐藏上下文继续发送，
  /// 但复制对话时不会复制这些内部 prompt。
  final List<ChatMessage> transcript;

  const JsonAiResult({required this.json, required this.transcript});
}

/// 面向结构化任务的 AI JSON 客户端。
///
/// 它在底层 OpenAI 兼容 API 之上提供三件事：
/// 1. 优先尝试 `response_format: json_object`；
/// 2. 不兼容 JSON mode 时自动降级为普通 chat completions；
/// 3. 模型输出非 JSON 时自动请求修复一次。
class JsonAiClient {
  const JsonAiClient._();

  static Future<Map<String, dynamic>> completeObject({
    required String taskName,
    required List<ChatMessage> messages,
    double temperature = 0.15,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 240),
    int repairAttempts = 1,
  }) async {
    return (await completeObjectWithTranscript(
      taskName: taskName,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
      repairAttempts: repairAttempts,
    ))
        .json;
  }

  static Future<JsonAiResult> completeObjectWithTranscript({
    required String taskName,
    required List<ChatMessage> messages,
    double temperature = 0.15,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 240),
    int repairAttempts = 1,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    String raw;
    try {
      raw = await ApiService.chatMessages(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        messages: messages,
        options: ChatCompleteOptions(
          temperature: temperature,
          maxTokens: maxTokens,
          jsonMode: true,
          timeout: timeout,
        ),
      );
    } catch (_) {
      // 很多 OpenAI 兼容服务并不支持 response_format；这里直接降级，
      // 不让“JSON mode 不兼容”阻断整条 UI 理解链路。
      raw = await ApiService.chatMessages(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        messages: messages,
        options: ChatCompleteOptions(
          temperature: temperature,
          maxTokens: maxTokens,
          jsonMode: false,
          timeout: timeout,
        ),
      );
    }

    if (ApiService.looksLikeRefusal(raw)) {
      throw StateError('模型拒绝执行 $taskName。请尝试更换无审核或本地模型。');
    }

    final transcript = <ChatMessage>[
      ...messages,
      ChatMessage(role: 'assistant', content: raw),
    ];
    final parsed = AiJsonUtils.tryParseObject(raw);
    if (parsed != null) {
      return JsonAiResult(json: parsed, transcript: transcript);
    }

    var lastRaw = raw;
    for (var attempt = 0; attempt < repairAttempts; attempt++) {
      const repairPrompt = ChatMessage(
        role: 'user',
        content: '上一次回复不是合法 JSON 对象。请只输出修复后的 JSON 对象，'
            '不要解释、不要 markdown 代码块、不要新增字段含义。',
      );
      final repairedRaw = await ApiService.chatMessages(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        messages: [...transcript, repairPrompt],
        options: ChatCompleteOptions(
          temperature: 0.0,
          maxTokens: maxTokens,
          jsonMode: false,
          timeout: timeout,
        ),
      );
      transcript
        ..add(repairPrompt)
        ..add(ChatMessage(role: 'assistant', content: repairedRaw));
      if (ApiService.looksLikeRefusal(repairedRaw)) {
        throw StateError('模型拒绝修复 $taskName 的 JSON 输出。');
      }
      final repaired = AiJsonUtils.tryParseObject(repairedRaw);
      if (repaired != null) {
        return JsonAiResult(json: repaired, transcript: transcript);
      }
      lastRaw = repairedRaw;
    }

    throw FormatException(
      'AI $taskName 返回的不是合法 JSON 对象。最后一次输出：$lastRaw',
    );
  }
}
