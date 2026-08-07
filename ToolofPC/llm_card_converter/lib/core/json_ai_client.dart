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
    void Function(String delta)? onDelta,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    // 云端 API 在 json_object 模式 + 超长上下文下偶发空 content。
    // 这里做两层兜底：
    //   1. 解析失败且修复轮次耗尽后，用普通模式整体重跑一次任务；
    //   2. 普通模式仍失败，再做一次完整重试。
    // 空返回往往是瞬时的，重试成功率很高。
    var lastFormatError = <Object?>[];
    for (var overall = 0; overall < 2; overall++) {
      try {
        return await _completeOnce(
          taskName: taskName,
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
          timeout: timeout,
          repairAttempts: repairAttempts,
          onDelta: onDelta,
        );
      } catch (e) {
        lastFormatError = [e];
        // 可恢复的错误：解析失败（FormatException）或模型返回空。
        // 这两种都是瞬时的，整体重试一次往往就成功。
        final isRetryable = e is FormatException ||
            (e is Exception &&
                (e.toString().contains('模型返回为空') ||
                    e.toString().contains('模型未返回内容')));
        if (isRetryable) {
          continue;
        }
        rethrow;
      }
    }
    throw lastFormatError.first!;
  }

  /// 缩短错误信息，避免把整段 Dio 异常堆栈刷进 UI 日志。
  static String _shortError(String message) {
    final firstLine = message.split('\n').first.trim();
    if (firstLine.length <= 120) return firstLine;
    return '${firstLine.substring(0, 120)}…';
  }

  static Future<JsonAiResult> _completeOnce({    required String taskName,
    required List<ChatMessage> messages,
    required double temperature,
    required int? maxTokens,
    required Duration timeout,
    required int repairAttempts,
    void Function(String delta)? onDelta,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    String raw;
    // 优先流式：模型边生成边吐 chunk，数据包持续到达，
    // `receiveTimeout` 不会在长上下文生成期间触发。
    //
    // 关键：流式请求**不带 response_format**。很多云端 API 不支持
    // 「stream + json_object」组合，带了会直接 400，导致流式一路回落
    // 到普通请求——那正是大上下文超时/空返回的高发路径。
    // JSON 解析靠 AiJsonUtils 容错 + 修复轮次兜底。
    String? streamError;
    try {
      raw = await ApiService.chatMessagesStreaming(
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
        onDelta: onDelta,
      );
    } catch (e) {
      streamError = e.toString();
      // 流式失败（服务不支持 / 网络 / 超时），回落普通请求。
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
      onDelta?.call('\n[流式不可用，已回落普通请求] ${_shortError(streamError)}\n');
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
