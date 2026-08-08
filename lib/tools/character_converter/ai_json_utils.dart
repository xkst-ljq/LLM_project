import 'dart:convert';

/// AI JSON 输出的容错解析工具。
class AiJsonUtils {
  const AiJsonUtils._();

  /// 尝试解析 JSON 对象。
  ///
  /// 兼容模型常见输出：
  /// - ```json ... ``` 代码块；
  /// - JSON 前后夹少量说明；
  /// - 顶层必须是对象（Map），数组等不接受。
  static Map<String, dynamic>? tryParseObject(String raw) {
    final text = _stripCodeFence(raw.trim());
    final body = _extractObject(text);
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// 尝试解析 JSON 数组。
  static List<dynamic>? tryParseArray(String raw) {
    final text = _stripCodeFence(raw.trim());
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  static String _stripCodeFence(String input) {
    var t = input;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    return t.trim();
  }

  /// 提取第一个平衡的 JSON 对象。
  ///
  /// 比 `indexOf('{') + lastIndexOf('}')` 稍稳：若模型在后文解释里又写了
  /// `{foo}`，不会把它误拼进 JSON 主体。
  static String? _extractObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == 0x5C) { // \
          escape = true;
        } else if (c == 0x22) { // "
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) { // {
        depth++;
      } else if (c == 0x7D) { // }
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }
}
