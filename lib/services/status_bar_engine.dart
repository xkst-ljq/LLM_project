import '../models/status_bar_field.dart';

/// 标签块工具（通用：将来背包 / 动态设定演化等"LLM 返回变更指令"的场景共用）。
///
/// 约定：LLM 把机器可读的变更指令放进一对标签里，例如
///   `<状态变化> ... </状态变化>`
/// 引擎负责把它从展示文本里剥离（用户看不到技术标记），并解析其中的指令。
class TaggedBlock {
  /// 提取 `<tag>...</tag>` 之间的内容（取最后一个块；找不到返回 null）。
  static String? extract(String text, String tag) {
    final re = RegExp('<$tag>(.*?)</$tag>', dotAll: true);
    final matches = re.allMatches(text).toList();
    if (matches.isEmpty) return null;
    return matches.last.group(1)?.trim();
  }

  /// 从展示文本中剥离所有 `<tag>...</tag>` 块（含标签本身），并清理多余空行。
  static String strip(String text, String tag) {
    final re = RegExp('<$tag>.*?</$tag>', dotAll: true);
    var out = text.replaceAll(re, '');
    // 清理因剥离产生的连续空行 / 首尾空白。
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return out;
  }
}

/// 单个状态变更的记录（用于 UI 反馈 / 调试）。
class StatusChange {
  final String fieldId;
  final String fieldName;
  final String oldValue;
  final String newValue;
  StatusChange(this.fieldId, this.fieldName, this.oldValue, this.newValue);
}

/// 状态栏增量引擎。
///
/// 核心理念（用户定）：**LLM 只当裁判出"变化量"，引擎确定性地算账**。
///   - 数值字段：LLM 给 delta（+/-），引擎做 clamp(旧值 + delta, min, max)，
///     绝不让 LLM 直接给绝对值（防止与上下文不符）。
///   - 文本字段：LLM 给新值（=），引擎直接替换。
///
/// 设计为可复用骨架：解析 / 算账分离，标签块工具独立，
/// 将来背包（物品增删）、动态设定演化可沿用同样的"标签 + 变更指令"模式。
class StatusBarEngine {
  static const String tag = '状态变化';

  /// 注入文本：把"当前状态值 + 输出格式约定"加进 system prompt，
  /// 让 LLM 知道现状，并约束它如何回报变化。无字段时返回空串。
  static String buildInjection(
    List<StatusBarField> fields,
    Map<String, String> values,
  ) {
    if (fields.isEmpty) return '';

    final sorted = [...fields]..sort((a, b) => a.order.compareTo(b.order));

    final lines = <String>[];
    lines.add('[状态栏]');
    lines.add('以下是当前状态值（请结合剧情判断本回合各项应如何变化）：');
    for (final f in sorted) {
      final v = values[f.id] ?? f.initialValue;
      if (f.isNumber) {
        final range = _rangeHint(f);
        lines.add('- ${f.name}：$v${range.isNotEmpty ? '（$range）' : ''}');
      } else {
        lines.add('- ${f.name}：$v');
      }
    }

    lines.add('');
    lines.add('回复正文之后，另起一段输出状态变化（仅在确有变化时输出对应行）：');
    lines.add('<$tag>');
    lines.add('数值项格式：名称:+N 或 名称:-N（只给变化量，不要给最终值）');
    lines.add('文本项格式：名称=新内容（直接给变化后的内容）');
    lines.add('</$tag>');
    lines.add('注意：变化量需与剧情合理对应；没有变化的项不要输出。该标记不会展示给用户。');

    return lines.join('\n');
  }

  static String _rangeHint(StatusBarField f) {
    final hasMin = f.minValue != null;
    final hasMax = f.maxValue != null;
    if (hasMin && hasMax) return '范围 ${_num(f.minValue!)}~${_num(f.maxValue!)}';
    if (hasMax) return '上限 ${_num(f.maxValue!)}';
    if (hasMin) return '下限 ${_num(f.minValue!)}';
    return '';
  }

  /// 解析 LLM 回复中的 `<状态变化>` 块，对 values 应用变更（原地修改 values）。
  /// 返回变更记录列表（无变化 / 无块时为空）。
  static List<StatusChange> applyFromReply(
    String reply,
    List<StatusBarField> fields,
    Map<String, String> values,
  ) {
    final changes = <StatusChange>[];
    final block = TaggedBlock.extract(reply, tag);
    if (block == null || block.isEmpty) return changes;

    // 名称 -> 字段（按显示名匹配，LLM 用的是 name）。
    final byName = <String, StatusBarField>{};
    for (final f in fields) {
      if (f.name.trim().isNotEmpty) byName[f.name.trim()] = f;
    }

    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      // 去掉可能的列表符号 "- "。
      final body = line.replaceFirst(RegExp(r'^[-*•]\s*'), '');

      // 文本字段：名称=新值
      final eq = body.indexOf('=');
      final colon = _firstColon(body);

      String? name;
      String? rawValue;
      bool isAssign = false;
      if (eq != -1 && (colon == -1 || eq < colon)) {
        name = body.substring(0, eq).trim();
        rawValue = body.substring(eq + 1).trim();
        isAssign = true;
      } else if (colon != -1) {
        name = body.substring(0, colon).trim();
        rawValue = body.substring(colon + 1).trim();
      }
      if (name == null || rawValue == null) continue;

      final f = byName[name];
      if (f == null) continue;

      final old = values[f.id] ?? f.initialValue;

      if (f.isNumber && !isAssign) {
        final delta = _parseDelta(rawValue);
        if (delta == null) continue;
        final base = double.tryParse(old.trim()) ??
            double.tryParse(f.initialValue.trim()) ??
            0;
        var next = base + delta;
        if (f.minValue != null && next < f.minValue!) next = f.minValue!;
        if (f.maxValue != null && next > f.maxValue!) next = f.maxValue!;
        final nextStr = _num(next);
        if (nextStr != old) {
          values[f.id] = nextStr;
          changes.add(StatusChange(f.id, f.name, old, nextStr));
        }
      } else {
        // 文本字段（或对数值字段误用了 = 赋值，也按替换处理但仅文本字段允许）。
        if (!f.isNumber) {
          if (rawValue != old) {
            values[f.id] = rawValue;
            changes.add(StatusChange(f.id, f.name, old, rawValue));
          }
        }
      }
    }
    return changes;
  }

  /// 从展示文本剥离 `<状态变化>` 块（用户看到的回复里不含技术标记）。
  static String stripFromReply(String reply) => TaggedBlock.strip(reply, tag);

  // ---- 内部小工具 ----

  /// 解析 "+5" / "-3" / "5" / "+5.0" 为 double（带正负号）。
  static double? _parseDelta(String raw) {
    var s = raw.trim();
    // 去掉可能的单位 / 百分号等尾巴，只取开头的数字部分。
    final m = RegExp(r'^[+\-]?\d+(\.\d+)?').firstMatch(s);
    if (m == null) return null;
    return double.tryParse(m.group(0)!);
  }

  /// 找到第一个用于分隔的冒号（中英文）。
  static int _firstColon(String s) {
    final a = s.indexOf(':');
    final b = s.indexOf('：');
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }

  /// 数值转字符串：整数不带小数点，小数保留必要位。
  static String _num(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}
