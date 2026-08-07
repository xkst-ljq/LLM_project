import 'api_service.dart';

/// 一次「AI UI 转译」的完整过程记录（流程观察器用）。
///
/// 目标：把一次转译里每个 AI 请求的完整输入、参数、流式过程、原始输出、
/// 解析结果、失败原因全部结构化记录下来，供人直观地逐轮查看，
/// 而不是靠零散日志猜。
///
/// 纯 Dart，不依赖 Flutter UI，方便测试与复用。
class UiTranslateTrace {
  final String cardName;
  final List<TraceStep> steps;
  final DateTime startedAt;
  final DateTime? finishedAt;

  UiTranslateTrace({
    required this.cardName,
    List<TraceStep>? steps,
    required this.startedAt,
    this.finishedAt,
  }) : steps = steps ?? <TraceStep>[];

  /// 累计耗时（毫秒）。未结束时为到现在的耗时。
  int get elapsedMs => (finishedAt ?? DateTime.now()).difference(startedAt).inMilliseconds;

  /// 是否有任何步骤失败。
  bool get hasFailure => steps.any((s) => s.error != null);
}

/// 转译过程中的一个步骤（一次 AI 请求，或一次确定性生成）。
class TraceStep {
  /// 阶段标识：'scout' | 'detailer' | 'repair' | 'deterministic'。
  final String stage;

  /// 目标生命周期：'opening' | 'scene' | 'extra_sticky' | 'extra_companion'。
  final String targetMode;

  /// 展示名，如「UI 侦察」「UI 精修/opening」。
  final String label;

  final DateTime startedAt;
  final DateTime? finishedAt;

  /// 本次请求的完整消息（system + user，原始文本）。
  final List<TraceMessage> requestMessages;

  /// 本次请求的参数。
  final TraceRequestParams params;

  /// 流式模式下收到的内容 chunk（按序）。
  final List<String> streamingChunks;

  /// 是否收到 `data: [DONE]` 结束标记。
  final bool gotDone;

  /// AI 原始回复全文（流式拼装后的结果；失败时可能为空）。
  final String rawReply;

  /// 思考链（`reasoning_content` 等字段），可能为空。
  final String reasoningContent;

  /// JSON 是否解析成功。
  final bool parsedOk;

  /// 解析失败原因。
  final String? parseError;

  /// 解析出的 JSON（成功时）。
  final Map<String, dynamic>? parsedJson;

  /// 本步骤最终错误（请求失败 / 解析失败 / 校验失败等）。
  final String? error;

  /// 诊断信息：首 token 耗时、收到几个 data frame、HTTP 状态等。
  final List<String> diagnostics;

  const TraceStep({
    required this.stage,
    required this.targetMode,
    required this.label,
    required this.startedAt,
    this.finishedAt,
    required this.requestMessages,
    required this.params,
    this.streamingChunks = const <String>[],
    this.gotDone = false,
    this.rawReply = '',
    this.reasoningContent = '',
    this.parsedOk = false,
    this.parseError,
    this.parsedJson,
    this.error,
    this.diagnostics = const <String>[],
  });

  /// 本步骤耗时（毫秒）。
  int get elapsedMs =>
      (finishedAt ?? DateTime.now()).difference(startedAt).inMilliseconds;
}

/// 一条请求消息。
class TraceMessage {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  const TraceMessage({required this.role, required this.content});

  factory TraceMessage.fromChat(ChatMessage message) =>
      TraceMessage(role: message.role, content: message.content);

  factory TraceMessage.fromRoleContent(String role, String content) =>
      TraceMessage(role: role, content: content);
}

/// 一次请求的参数。
class TraceRequestParams {
  final int? maxTokens;
  final Duration timeout;
  final bool jsonMode;
  final bool stream;

  const TraceRequestParams({
    this.maxTokens,
    this.timeout = const Duration(seconds: 120),
    this.jsonMode = false,
    this.stream = false,
  });
}

/// 逐步构建 [UiTranslateTrace] 的可变构造器。
///
/// [AiUiInterpreter] 在转译过程中调用它的方法记录每个请求/步骤，
/// 结束后 `build()` 产出不可变快照。不依赖 Flutter。
class UiTranslateTraceBuilder {
  final String cardName;
  final DateTime startedAt;
  final List<TraceStep> steps = <TraceStep>[];

  UiTranslateTraceBuilder({
    required this.cardName,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  /// 开始一个新步骤，返回该步骤的可变上下文供后续填充。
  TraceStepBuilder beginStep({
    required String stage,
    required String targetMode,
    required String label,
  }) {
    final step = TraceStepBuilder(
      stage: stage,
      targetMode: targetMode,
      label: label,
      startedAt: DateTime.now(),
    );
    steps.add(step.build());
    return step;
  }

  UiTranslateTrace build() => UiTranslateTrace(
        cardName: cardName,
        steps: List<TraceStep>.unmodifiable(steps),
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
}

/// 单个 [TraceStep] 的可变构建上下文。
class TraceStepBuilder {
  final String stage;
  final String targetMode;
  final String label;
  final DateTime startedAt;
  DateTime? finishedAt;
  final List<TraceMessage> requestMessages = <TraceMessage>[];
  TraceRequestParams? params;
  final List<String> streamingChunks = <String>[];
  bool gotDone = false;
  String rawReply = '';
  String reasoningContent = '';
  bool parsedOk = false;
  String? parseError;
  Map<String, dynamic>? parsedJson;
  String? error;
  final List<String> diagnostics = <String>[];

  TraceStepBuilder({
    required this.stage,
    required this.targetMode,
    required this.label,
    required this.startedAt,
  });

  void addRequestMessage(String role, String content) {
    requestMessages.add(TraceMessage.fromRoleContent(role, content));
  }

  void setParams({
    int? maxTokens,
    Duration? timeout,
    bool jsonMode = false,
    bool stream = false,
  }) {
    params = TraceRequestParams(
      maxTokens: maxTokens,
      timeout: timeout ?? const Duration(seconds: 120),
      jsonMode: jsonMode,
      stream: stream,
    );
  }

  void addStreamingChunk(String chunk) => streamingChunks.add(chunk);

  void addDiagnostic(String line) => diagnostics.add(line);

  void markDone() => gotDone = true;

  void complete({
    String rawReply = '',
    String reasoningContent = '',
    bool parsedOk = false,
    String? parseError,
    Map<String, dynamic>? parsedJson,
    String? error,
  }) {
    this.rawReply = rawReply;
    this.reasoningContent = reasoningContent;
    this.parsedOk = parsedOk;
    this.parseError = parseError;
    this.parsedJson = parsedJson;
    this.error = error;
    finishedAt ??= DateTime.now();
  }

  TraceStep build() => TraceStep(
        stage: stage,
        targetMode: targetMode,
        label: label,
        startedAt: startedAt,
        finishedAt: finishedAt,
        requestMessages: List<TraceMessage>.unmodifiable(requestMessages),
        params: params ??
            const TraceRequestParams(),
        streamingChunks: List<String>.unmodifiable(streamingChunks),
        gotDone: gotDone,
        rawReply: rawReply,
        reasoningContent: reasoningContent,
        parsedOk: parsedOk,
        parseError: parseError,
        parsedJson: parsedJson,
        error: error,
        diagnostics: List<String>.unmodifiable(diagnostics),
      );
}
