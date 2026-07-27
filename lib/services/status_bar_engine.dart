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

/// 状态字段的 LLM 访问策略。
///
/// 来源是 UI 数据通道（`module.properties['dataChannel']`）。
/// 状态栏字段本身不带策略，但当某个字段被 UI 数据通道引用时，
/// 作者在通道里配置的读写策略必须同样约束状态栏的注入与解析——
/// 否则「可写不可读」这类配置会被状态栏从侧面绕过。
class StatusFieldPolicy {
  /// 当前值可以出现在 Prompt 里。
  final bool canRead;

  /// LLM 可以建议更新该字段。
  final bool canWrite;

  /// 'confirm' | 'auto_low_risk' | 'never'
  final String applyPolicy;

  const StatusFieldPolicy({
    this.canRead = true,
    this.canWrite = true,
    this.applyPolicy = 'auto_low_risk',
  });
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
    Map<String, String> values, {
    Map<String, StatusFieldPolicy> policies = const {},
  }) {
    if (fields.isEmpty) return '';

    final sorted = [...fields]..sort((a, b) => a.order.compareTo(b.order));

    // 按策略分三类：可读、只可写不可读、完全不参与。
    final readable = <StatusBarField>[];
    final writeOnly = <StatusBarField>[];
    final writable = <StatusBarField>[];
    for (final f in sorted) {
      final policy = policies[f.id] ?? const StatusFieldPolicy();
      if (policy.canRead) readable.add(f);
      if (policy.canWrite) {
        writable.add(f);
        if (!policy.canRead) writeOnly.add(f);
      }
    }

    if (readable.isEmpty && writable.isEmpty) return '';
    // writable 仅用于判断是否有可注入内容；格式约束由 PHI 负责。

    final lines = <String>[];

    if (readable.isNotEmpty) {
      lines.add('[状态栏]');
      lines.add('以下是最新状态值，已包含此前所有回合的结算结果'
          '（请结合剧情判断本回合各项应如何变化）：');
      // 先肯定「你能看到」，再约束「照抄而非推算」。
      // 只写否定句会被模型泛化成「我无权读取状态」，反而拒绝回答。
      lines.add('你可以看到下面这些数值。用户询问某项当前值时，'
          '请直接读出下面对应的数字，不要再加上历史消息里的变化量。');
      for (final f in readable) {
        final v = values[f.id] ?? f.initialValue;
        if (f.isNumber) {
          final range = _rangeHint(f);
          lines.add('- ${f.name}：$v${range.isNotEmpty ? '（$range）' : ''}');
        } else {
          lines.add('- ${f.name}：$v');
        }
      }
    }

    // 可写不可读：只告诉 LLM 可以建议变化，绝不暴露当前值。
    if (writeOnly.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[可建议更新的隐藏状态]');
      lines.add('以下状态的当前值对你隐藏，你只能根据剧情建议其变化：');
      for (final f in writeOnly) {
        lines.add('- ${f.name}：只可输出 +N/-N，不要在正文中提及当前值。');
      }
    }

    // 更新格式约束已移到 buildUpdateFormatInstruction()，由 PHI 在
    // 对话历史之后注入——放在这里（system 开头）会被长对话淡忘。
    return lines.join('\n');
  }

  /// 状态更新格式约束，供历史后注入（PHI）使用。
  ///
  /// 与 `buildInjection` 的分工：那个负责「当前值是多少」，放在 system 开头即可；
  /// 这个负责「你必须怎么回报变化」，必须放到对话历史之后。
  /// 格式约束放在 system 开头时，长对话中模型会忽略它而只在正文里口头声称
  /// 「已修改」，实际不输出标签块，导致状态纹丝不动。
  static String buildUpdateFormatInstruction(
    List<StatusBarField> fields,
    Map<String, String> values, {
    Map<String, StatusFieldPolicy> policies = const {},
  }) {
    final writable = <StatusBarField>[];
    for (final f in fields) {
      if (f.name.trim().isEmpty) continue;
      final policy = policies[f.id] ?? const StatusFieldPolicy();
      if (policy.canWrite) writable.add(f);
    }
    if (writable.isEmpty) return '';

    final lines = <String>[];
    lines.add('[状态结算 · 每回合必须输出结算块]');
    lines.add('你每一条回复的最后，都必须附上状态结算块。这是系统协议，'
        '不是可选项。');
    lines.add('');
    // 最关键的一条：模型最常见的失败模式不是格式错，
    // 而是在正文里说「已修改」却不输出标签块，导致状态实际没变。
    lines.add('特别注意：只有输出下面的标签块才会真正改变状态。'
        '仅在正文里说「已修改」「已上升」是无效的，状态不会有任何变化。'
        '如果用户要求你修改某项状态，你必须在标签块里写出对应的变化量。');
    lines.add('');
    lines.add('可结算项：');
    for (final f in writable) {
      if (f.isNumber) {
        final range = _rangeHint(f);
        lines.add('- ${f.name}：格式 `${f.name}:+N` 或 `${f.name}:-N`，'
            '只给变化量，不要给最终值${range.isEmpty ? '' : '（$range）'}');
      } else {
        lines.add('- ${f.name}：格式 `${f.name}=新内容`，直接给变化后的内容');
      }
    }
    lines.add('');
    // 示例一律用空块：写具体数值会被模型当成标准答案照抄。
    lines.add('默认输出（本回合无事发生时，也是最常见的情况）：');
    lines.add('<$tag>');
    lines.add('</$tag>');
    lines.add('');
    lines.add('执行规则：');
    lines.add('- 每回合都要输出 <$tag>...</$tag> 这一对标签，'
        '即使没有任何变化，也要输出一对空标签。');
    lines.add('- 每项单独占一行，不要把多项写在同一行。');
    lines.add('- 标签内只写确有变化的项；没有变化的项不写，也不要写未列出的项。');
    lines.add('- 日常对话、寒暄、单纯的信息交流一律不产生变化；拿不准时不写。');
    lines.add('- 用户明确要求修改某项时，必须在标签块里如实写出。');
    lines.add('- 直接输出标签本身，不要用代码块或引号包裹。');
    lines.add('- 该标记不会展示给用户，正文中不要重复或提及它的内容。');
    lines.add('');
    // 当前值在这里重复一遍。
    // system prompt 开头的 [状态栏] 距离太远（世界书往往上千 token），
    // 模型报数时更容易采信近处对话历史里自己说过的旧数字。
    // 把权威值放到紧邻本回合的位置，是解决报错数最有效的手段。
    final readable = <StatusBarField>[];
    for (final f in fields) {
      if (f.name.trim().isEmpty) continue;
      if ((policies[f.id] ?? const StatusFieldPolicy()).canRead) {
        readable.add(f);
      }
    }

    if (readable.isNotEmpty) {
      lines.add('');
      // 必须说清「这是最新结果」而非「起点」。
      // 只写「当前值」时，模型会把它当成本轮变化前的初始值，
      // 再把历史里看到的请求量加一遍，导致报数虚高（如 50 报成 75）。
      lines.add('最新状态值（已包含此前所有回合的结算结果）：');
      for (final f in readable) {
        lines.add('- ${f.name}：${values[f.id] ?? f.initialValue}');
      }
      lines.add('');
      lines.add('关于在正文里提到数值：');
      // 措辞以肯定句为主。纯否定句会被模型泛化成「我无权读取状态」而拒绝回答。
      lines.add('- 上面这几个数字是系统结算后的最新结果，你能够看到它们。');
      lines.add('- 用户询问当前状态时，直接读出上面对应的数字即可，'
          '不要做任何加减。');
      lines.add('- 这些数字**已经包含**了此前每一轮的变化，'
          '包括你上一条回复里刚刚结算的那次。'
          '不要再把历史消息里出现过的变化量加到它们上面。');
      lines.add('- 如果你在更早的对话里说过不同的数字，那是过时或错误的，'
          '一律以上面这份为准，不要沿用历史消息里的旧数字。');
      lines.add('- 本回合若还要产生新变化，只需写进结算块，'
          '系统会在你回复之后自动累加，你不需要在正文里预告结果。');
      lines.add('- 例外：[可建议更新的隐藏状态] 里的项没有给出当前值，'
          '这类项才需要说明你无法得知其数值。');
      lines.add('');
      // 允许推理，但把「推理结果」和「事实」严格分开。
      // 完全禁止推理会让对话变机械；放任推理则会为不一致编造理由
      //（历史被撤回 / 编辑后，数值必然无法从对话记录推导出来）。
      // 让模型把分歧说出来而不是抹平，分歧反而成了排查问题的信号。
      lines.add('当你的推算与上面的数字不一致时：');
      lines.add('- 上面的数字是唯一事实，一律以它为准，'
          '不要为了自圆其说而修改它或编造推导过程。');
      lines.add('- 推不出来是正常的：历史消息可能被用户撤回或编辑过，'
          '此时数值本来就无法从对话记录推导出来。');
      lines.add('- 这种情况下不要猜测原因，'
          '可以直接说明你无法从对话记录还原这个数值的由来。');
      lines.add('- 如果你有充分理由怀疑系统数据有误，'
          '可以简短说出你的疑问和你的推算依据，但仍要以系统数字为准。');
    }

    return lines.join('\n');
  }

  /// 每回合贴在最后一条用户消息尾部的极短提醒。
  static String buildTurnReminder(
    List<StatusBarField> fields, {
    Map<String, StatusFieldPolicy> policies = const {},
  }) {
    final hasWritable = fields.any((f) {
      if (f.name.trim().isEmpty) return false;
      return (policies[f.id] ?? const StatusFieldPolicy()).canWrite;
    });
    if (!hasWritable) return '';
    return '（系统提醒：本回合回复结束后，附上 <$tag>...</$tag> 结算块；'
        '只有写进标签块的变化才会生效，无对应事件则输出空标签。）';
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
  /// 解析并算账。
  ///
  /// [commit] 为 false 时只计算不写入 [values]，用于「需要用户确认」的字段：
  /// 先把结果拿出来给用户看，确认后再由调用方写回。
  static List<StatusChange> applyFromReply(
    String reply,
    List<StatusBarField> fields,
    Map<String, String> values, {
    Map<String, StatusFieldPolicy> policies = const {},
    bool commit = true,
  }) {
    final changes = <StatusChange>[];
    final block = TaggedBlock.extract(reply, tag);
    if (block == null || block.isEmpty) return changes;

    // 名称 -> 字段（按显示名匹配，LLM 用的是 name）。
    // 被数据通道标记为不可写的字段直接排除，哪怕 LLM 输出了也不生效。
    final byName = <String, StatusBarField>{};
    for (final f in fields) {
      if (f.name.trim().isEmpty) continue;
      final policy = policies[f.id] ?? const StatusFieldPolicy();
      if (!policy.canWrite) continue;
      byName[f.name.trim()] = f;
    }

    // 模型有时会把多项写在同一行（如 `心情=平静，好感度:+3`）。
    // 文本字段的取值是「等号后的全部内容」，会把后面的数值项一起吞掉，
    // 导致好感度的增量跑进心情里。这里先按已知字段名把每行切成多个片段。
    final segments = <String>[];
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      segments.addAll(splitSegments(line, byName.keys));
    }

    for (final body in segments) {

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
          if (commit) values[f.id] = nextStr;
          changes.add(StatusChange(f.id, f.name, old, nextStr));
        }
      } else {
        // 文本字段（或对数值字段误用了 = 赋值，也按替换处理但仅文本字段允许）。
        if (!f.isNumber) {
          if (rawValue != old) {
            if (commit) values[f.id] = rawValue;
            changes.add(StatusChange(f.id, f.name, old, rawValue));
          }
        }
      }
    }
    return changes;
  }

  /// 把一行拆成若干「字段名 + 值」片段。
  ///
  /// 只在**已知字段名**出现的位置切分，避免误伤文本值里的正常标点。
  /// 例如已知字段为 心情 / 好感度 时：
  ///   `心情=平静，好感度:+3` → [`心情=平静`, `好感度:+3`]
  ///   `心情=有点复杂，说不清` → 整行保留（逗号后不是字段名）
  static List<String> splitSegments(
    String line,
    Iterable<String> fieldNames,
  ) {
    // 去掉可能的列表符号 "- "。
    final body = line.replaceFirst(RegExp(r'^[-*•]\s*'), '');
    if (body.isEmpty) return const [];

    // 收集所有「字段名紧跟分隔符」的起始位置。
    final cuts = <int>[];
    for (final name in fieldNames) {
      if (name.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = body.indexOf(name, from);
        if (at == -1) break;
        from = at + name.length;
        // 字段名后面必须紧跟 = 或 :（允许空格），否则只是正文里的普通词。
        final rest = body.substring(from).trimLeft();
        if (rest.startsWith('=') ||
            rest.startsWith(':') ||
            rest.startsWith('：')) {
          cuts.add(at);
        }
      }
    }

    if (cuts.length <= 1) return [body];

    cuts.sort();
    final out = <String>[];
    for (var i = 0; i < cuts.length; i++) {
      final start = cuts[i];
      final end = i + 1 < cuts.length ? cuts[i + 1] : body.length;
      // 切出的片段可能以分隔标点结尾（如 `心情=平静，`），一并清掉。
      final seg = body
          .substring(start, end)
          .trim()
          .replaceFirst(RegExp(r'[，,、;；]+$'), '');
      if (seg.isNotEmpty) out.add(seg);
    }
    return out;
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
