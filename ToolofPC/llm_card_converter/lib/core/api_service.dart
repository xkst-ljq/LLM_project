import 'dart:convert';

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

  /// 聊天补全（流式 / SSE）。返回完整文本，边生成边通过 [onToken] 回调。
  ///
  /// 与 [chatComplete] 语义一致，只是走 `stream: true` + SSE 解析，
  /// 让调用方能实时拿到增量 token（展示「AI 正在思考」的进度）。
  /// [onToken] 按解码后的文本块回调（可能含半句/半个 JSON，不必逐字拆分）。
  ///
  /// **关键**：这里必须把 SSE 的 `data: {...}` 外衣剥掉，只抽 `delta.content`
  /// 拼成真正的响应文本返回——否则调用方 `_parseJson` 拿到的是夹满
  /// `data:` 前缀的非法 JSON，解析必然失败（表现为「流式有字但最终没结果」）。
  static Future<String> chatCompleteStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 180),
    void Function(String token)? onToken,
  }) async {
    final base = normalizeBase(baseUrl);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: timeout,
    ));
    final response = await dio.post<ResponseBody>(
      '$base/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
      data: {
        'model': model,
        'temperature': temperature,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    final body = response.data;
    if (body == null) {
      throw Exception('请求失败：无响应体');
    }

    final content = StringBuffer();
    // 跨 chunk 缓冲：SSE 的 `data:` 行可能被网络分包切开，
    // 必须按行缓冲，凑齐一整行再解析。
    final lineBuf = StringBuffer();
    // utf8.decoder 能正确处理跨 chunk 的 UTF-8 序列（多字节字符被切开）。
    await for (final decoded in utf8.decoder.bind(body.stream)) {
      lineBuf.write(decoded);
      _drainSseLines(lineBuf, content, onToken);
    }
    // 处理残留（无换行结尾的最后一行）
    _drainSseLines(lineBuf, content, onToken, force: true);

    final result = content.toString();
    if (result.trim().isEmpty) {
      throw Exception('模型未返回内容');
    }
    return result;
  }

  /// 从行缓冲里榨出所有完整的 SSE `data:` 行，抽取增量内容。
  ///
  /// [force] 为 true 时，即使最后没有换行结尾，也把剩余内容当最后一行处理
  ///（用于流结束时的残留）。
  static void _drainSseLines(
    StringBuffer lineBuf,
    StringBuffer content,
    void Function(String)? onToken, {
    bool force = false,
  }) {
    final text = lineBuf.toString();
    var rest = text;
    // 处理所有带换行结尾的完整行
    while (true) {
      final idx = rest.indexOf('\n');
      if (idx < 0) break;
      final line = rest.substring(0, idx).trim();
      rest = rest.substring(idx + 1);
      _consumeSseData(line, content, onToken);
    }
    lineBuf.clear();
    // 剩余无换行的部分：非 force 时留到下一批再拼，force 时立即处理
    if (rest.isNotEmpty && rest.trim().isNotEmpty) {
      if (force) {
        _consumeSseData(rest.trim(), content, onToken);
      } else {
        lineBuf.write(rest);
      }
    }
  }

  /// 处理单条 SSE 行：剥掉 `data:` 前缀，抽 delta/message 的 content。
  static void _consumeSseData(
    String line,
    StringBuffer content,
    void Function(String)? onToken,
  ) {
    if (!line.startsWith('data:')) return;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return;
    try {
      final decoded = jsonDecode(data);
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is! List || choices.isEmpty) return;
      final first = choices.first;
      if (first is! Map) return;
      final msg = first['delta'] is Map ? first['delta'] : first['message'];
      if (msg is! Map) return;
      final c = msg['content'];
      if (c is String && c.isNotEmpty) {
        content.write(c);
        onToken?.call(c);
      }
    } catch (_) {
      // 单行解析失败则跳过（如注释行），不影响其它行。
    }
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
