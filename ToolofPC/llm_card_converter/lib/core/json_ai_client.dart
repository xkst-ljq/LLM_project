import 'dart:async';
import 'api_service.dart';
import 'ai_json_utils.dart';
import 'app_settings.dart';
import 'ui_translate_trace.dart';

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
    int overallAttempts = 2,
  }) async {
    return (await completeObjectWithTranscript(
      taskName: taskName,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
      repairAttempts: repairAttempts,
      overallAttempts: overallAttempts,
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
    int overallAttempts = 2,
    void Function(String delta)? onDelta,
    void Function(String line)? onLog,
    TraceStepBuilder? trace,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    // 记录请求消息与参数到 trace。
    final t = trace;
    if (t != null) {
      t.requestMessages
        ..clear()
        ..addAll(messages.map(TraceMessage.fromChat));
      t.setParams(
        maxTokens: maxTokens,
        timeout: timeout,
        jsonMode: true,
        stream: true,
      );
      t.addDiagnostic(
          'completeObjectWithTranscript: repairAttempts=$repairAttempts overallAttempts=$overallAttempts');
    }

    // 云端 API 在 json_object 模式 + 超长上下文下偶发空 content。
    // 这里做两层兜底：
    //   1. 解析失败且修复轮次耗尽后，用普通模式整体重跑一次任务；
    //   2. 普通模式仍失败，再做一次完整重试。
    // 空返回往往是瞬时的，重试成功率很高。
    var lastFormatError = <Object?>[];
    final attempts = overallAttempts < 1 ? 1 : overallAttempts;
    for (var overall = 0; overall < attempts; overall++) {
      try {
        return await _completeOnce(
          taskName: taskName,
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
          timeout: timeout,
          repairAttempts: repairAttempts,
          onDelta: onDelta,
          onLog: onLog,
          trace: trace,
        );
      } catch (e) {
        lastFormatError = [e];
        // 可恢复的错误：解析失败（FormatException）或模型返回空。
        // 这两种都是瞬时的，整体重试一次往往就成功。
        final isRetryable = e is FormatException ||
            (e is Exception &&
                (e.toString().contains('模型返回为空') ||
                    e.toString().contains('模型未返回内容')));
        final canRetry = isRetryable && overall + 1 < attempts;
        if (canRetry) {
          onLog?.call('    $taskName：${_shortError(e.toString())}，准备整体重试 ${overall + 2}/$attempts…');
          trace?.addDiagnostic('整体重试 ${overall + 2}/$attempts：${_shortError(e.toString())}');
          continue;
        }
        if (!isRetryable) rethrow;
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

  static Future<T> _withHeartbeat<T>(
    Future<T> future, {
    required String label,
    required Duration every,
    void Function(String line)? onLog,
  }) async {
    if (onLog == null) return future;
    var elapsed = 0;
    final timer = Timer.periodic(every, (_) {
      elapsed += every.inSeconds;
      onLog('    $label：仍在等待模型响应（${elapsed}s）…');
    });
    try {
      return await future;
    } finally {
      timer.cancel();
    }
  }

  static Future<JsonAiResult> _completeOnce({
    required String taskName,
    required List<ChatMessage> messages,
    required double temperature,
    required int? maxTokens,
    required Duration timeout,
    required int repairAttempts,
    void Function(String delta)? onDelta,
    void Function(String line)? onLog,
    TraceStepBuilder? trace,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    // 让流式 onDelta 同时喂给 trace 记录器。
    void onDeltaAndTrace(String delta) {
      onDelta?.call(delta);
      trace?.addStreamingChunk(delta);
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
    final started = DateTime.now();
    try {
      onLog?.call('    $taskName：开始流式请求（timeout=${timeout.inSeconds}s, maxTokens=${maxTokens ?? '默认'}）');
      raw = await _withHeartbeat(
        ApiService.chatMessagesStreaming(
          baseUrl: cfg.baseUrl,
          apiKey: cfg.apiKey,
          model: cfg.model,
          messages: messages,
          options: ChatCompleteOptions(
            temperature: temperature,
            maxTokens: maxTokens,
            jsonMode: false,
            timeout: timeout,
            retryCount: 0,
          ),
          onDelta: onDeltaAndTrace,
          onLog: onLog,
        ),
        label: '$taskName/流式',
        every: const Duration(seconds: 30),
        onLog: onLog,
      );
      onLog?.call('    $taskName：流式完成，收到 ${raw.runes.length} 字符');
      final chunksSoFar = trace?.streamingChunks.length ?? 0;
      trace?.addDiagnostic('流式成功，收到 ${raw.runes.length} 字符，chunk 数 $chunksSoFar');
    } catch (e) {
      streamError = e.toString();
      onLog?.call('    $taskName：流式失败/空返回：${_shortError(streamError)}；回落普通请求…');
      trace?.addDiagnostic('流式失败：${_shortError(streamError)}；回落普通请求');
      // 流式失败（服务不支持 / 网络 / 超时），回落普通请求。
      raw = await _withHeartbeat(
        ApiService.chatMessages(
          baseUrl: cfg.baseUrl,
          apiKey: cfg.apiKey,
          model: cfg.model,
          messages: messages,
          options: ChatCompleteOptions(
            temperature: temperature,
            maxTokens: maxTokens,
            jsonMode: false,
            timeout: timeout,
            retryCount: 0,
          ),
          onLog: onLog,
        ),
        label: '$taskName/普通回落',
        every: const Duration(seconds: 30),
        onLog: onLog,
      );
      onLog?.call('    $taskName：普通请求完成，收到 ${raw.runes.length} 字符');
      trace?.addDiagnostic('普通回落成功，收到 ${raw.runes.length} 字符');
      onDelta?.call('\n[流式不可用，已回落普通请求] ${_shortError(streamError)}\n');
    }
    trace?.addDiagnostic('首 token/总等待：${DateTime.now().difference(started).inSeconds}s');

    if (raw.trim().isEmpty) {
      onLog?.call('    $taskName：模型返回空文本');
      trace?.addDiagnostic('模型返回空文本');
    }
    if (ApiService.looksLikeRefusal(raw)) {
      trace?.addDiagnostic('模型拒绝（审核拦截）');
      throw StateError('模型拒绝执行 $taskName。请尝试更换无审核或本地模型。');
    }

    final transcript = <ChatMessage>[
      ...messages,
      ChatMessage(role: 'assistant', content: raw),
    ];
    final parsed = AiJsonUtils.tryParseObject(raw);
    if (parsed != null) {
      onLog?.call('    $taskName：JSON 解析成功');
      trace?.complete(
        rawReply: raw,
        parsedOk: true,
        parsedJson: parsed,
      );
      return JsonAiResult(json: parsed, transcript: transcript);
    }

    onLog?.call('    $taskName：收到 ${raw.runes.length} 字符，但不是合法 JSON，准备修复…');
    trace?.addDiagnostic('收到 ${raw.runes.length} 字符但非合法 JSON，准备修复');
    var lastRaw = raw;
    for (var attempt = 0; attempt < repairAttempts; attempt++) {
      const repairPrompt = ChatMessage(
        role: 'user',
        content: '上一次回复不是合法 JSON 对象。请只输出修复后的 JSON 对象，'
            '不要解释、不要 markdown 代码块、不要新增字段含义。',
      );
      onLog?.call('    $taskName：JSON 修复请求 ${attempt + 1}/$repairAttempts…');
      trace?.addDiagnostic('JSON 修复请求 ${attempt + 1}/$repairAttempts');
      final repairedRaw = await _withHeartbeat(
        ApiService.chatMessages(
          baseUrl: cfg.baseUrl,
          apiKey: cfg.apiKey,
          model: cfg.model,
          messages: [...transcript, repairPrompt],
          options: ChatCompleteOptions(
            temperature: 0.0,
            maxTokens: maxTokens,
            jsonMode: false,
            timeout: timeout,
            retryCount: 0,
          ),
          onLog: onLog,
        ),
        label: '$taskName/JSON修复',
        every: const Duration(seconds: 30),
        onLog: onLog,
      );
      transcript
        ..add(repairPrompt)
        ..add(ChatMessage(role: 'assistant', content: repairedRaw));
      if (ApiService.looksLikeRefusal(repairedRaw)) {
        trace?.addDiagnostic('修复被模型拒绝');
        throw StateError('模型拒绝修复 $taskName 的 JSON 输出。');
      }
      final repaired = AiJsonUtils.tryParseObject(repairedRaw);
      if (repaired != null) {
        onLog?.call('    $taskName：JSON 修复成功，收到 ${repairedRaw.runes.length} 字符');
        trace?.complete(
          rawReply: repairedRaw,
          parsedOk: true,
          parsedJson: repaired,
          error: streamError,
        );
        return JsonAiResult(json: repaired, transcript: transcript);
      }
      onLog?.call('    $taskName：JSON 修复仍不可解析，收到 ${repairedRaw.runes.length} 字符');
      trace?.addDiagnostic('修复仍不可解析，收到 ${repairedRaw.runes.length} 字符');
      lastRaw = repairedRaw;
    }

    trace?.complete(
      rawReply: lastRaw,
      parsedOk: false,
      parseError: '不是合法 JSON 对象',
      error: streamError ?? 'JSON 解析失败',
    );
    throw FormatException(
      'AI $taskName 返回的不是合法 JSON 对象。最后一次输出：$lastRaw',
    );
  }
}
