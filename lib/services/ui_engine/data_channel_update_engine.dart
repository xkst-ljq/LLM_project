import '../../models/session_state.dart';
import '../../models/status_bar_field.dart';
import '../status_bar_engine.dart';
import 'data_channel_prompt_builder.dart';

/// 一条待应用的界面数据更新建议。
///
/// 只描述「引擎算完账后打算改成什么」，是否真的落地由
/// `llmUpdateApplyPolicy` 与用户确认决定。
class DataChannelUpdate {
  final String semanticLabel;

  /// 'session_var' | 'status_field'
  final String targetKind;

  /// 状态字段的内部 id；会话变量为空。
  final String targetId;

  final String oldValue;

  /// 引擎算完 delta + clamp 之后的最终值。
  final String newValue;

  /// LLM 给出的原始建议，例如 '+3'。用于确认弹窗展示。
  final String rawSuggestion;

  /// 'confirm' | 'auto_low_risk' | 'never'
  final String applyPolicy;

  const DataChannelUpdate({
    required this.semanticLabel,
    required this.targetKind,
    required this.targetId,
    required this.oldValue,
    required this.newValue,
    required this.rawSuggestion,
    required this.applyPolicy,
  });

  /// 该更新可以不经用户确认直接应用。
  bool get isAutoApplicable => applyPolicy == 'auto_low_risk';

  /// 该更新需要用户确认。
  bool get needsConfirm => applyPolicy == 'confirm';

  /// 展示用摘要，例如「好感度：45 → 48（+3）」。
  String get summary {
    final suffix =
        rawSuggestion.trim().isEmpty ? '' : '（${rawSuggestion.trim()}）';
    return '$semanticLabel：$oldValue → $newValue$suffix';
  }
}

/// 解析结果：分成「自动应用」「待确认」两组，外加被拒绝的条目数。
class DataChannelUpdateResult {
  final List<DataChannelUpdate> autoApply;
  final List<DataChannelUpdate> needsConfirm;

  /// 因策略为 never / 通道不可写 / 名称不匹配而被丢弃的条数。
  final int rejectedCount;

  const DataChannelUpdateResult({
    this.autoApply = const <DataChannelUpdate>[],
    this.needsConfirm = const <DataChannelUpdate>[],
    this.rejectedCount = 0,
  });

  bool get isEmpty => autoApply.isEmpty && needsConfirm.isEmpty;
}

/// A9.6-4：解析 LLM 回复里的 `<界面状态变化>` 块。
///
/// 与 `StatusBarEngine` 的关系：
///   - 标签不同（`界面状态变化` vs `状态变化`），互不干扰。
///   - 同样坚持「LLM 只当裁判给变化量，引擎确定性算账」。
///   - 额外多一层数据通道权限校验：写策略、应用策略都必须显式允许。
///
/// 安全红线：
///   - 通道 `llmWritePolicy == none` → 一律拒绝，哪怕 LLM 输出了该项。
///   - 通道 `llmUpdateApplyPolicy == never` → 一律拒绝。
///   - `suggest_delta` 只接受 +N/-N，不接受绝对值赋值。
///   - 数值更新由引擎执行 delta + clamp，LLM 不能直接覆盖绝对值。
class DataChannelUpdateEngine {
  static String get tag => DataChannelPromptBuilder.updateTag;

  /// 从回复中剥离技术标记，供展示使用。
  ///
  /// 先做一次容错归一化，保证被代码块包裹或全角括号写法的标签同样能剥干净，
  /// 否则用户会在气泡里看到残留的技术标记。
  static String stripFromReply(String reply) =>
      TaggedBlock.strip(_normalize(reply), tag);

  /// 容错归一化模型输出。
  ///
  /// 实测模型常见偏差（都不改变语义，只是格式走样）：
  ///   - 用 ```或 ```text 代码块包裹标签块
  ///   - 用全角尖括号 `＜界面状态变化＞`
  ///   - 标签内外多余空格，如 `< 界面状态变化 >`
  /// 这些情况下语义完全正确，没理由因为格式挑剔而丢弃更新。
  static String _normalize(String reply) {
    var out = reply;

    // 全角尖括号 → 半角。
    out = out.replaceAll('＜', '<').replaceAll('＞', '>');

    // 去掉标签内部的多余空格：`< 界面状态变化 >` → `<界面状态变化>`。
    out = out.replaceAllMapped(
      RegExp('<\\s*(/?)\\s*$tag\\s*>'),
      (m) => '<${m.group(1)}$tag>',
    );

    // 剥掉包裹标签块的代码围栏。
    out = out.replaceAllMapped(
      RegExp('```[a-zA-Z]*\\s*(<$tag>.*?</$tag>)\\s*```', dotAll: true),
      (m) => m.group(1)!,
    );

    return out;
  }

  /// 解析回复，返回按应用策略分组的更新建议。
  ///
  /// 本方法**不修改**任何状态，只做解析与算账。
  static DataChannelUpdateResult parse({
    required String reply,
    required List<DataChannelPromptItem> items,
    required SessionState session,
    List<StatusBarField> statusFields = const <StatusBarField>[],
  }) {
    final block = TaggedBlock.extract(_normalize(reply), tag);
    if (block == null || block.isEmpty) {
      return const DataChannelUpdateResult();
    }

    // 语义名 -> 通道。LLM 只认识语义名。
    // 状态字段由 StatusBarEngine 解析 <状态变化>，这里只处理会话变量，
    // 保证同一字段不会被两套引擎重复算账。
    final byLabel = <String, DataChannelPromptItem>{};
    for (final item in items) {
      if (item.targetKind == 'status_field') continue;
      byLabel[item.semanticLabel.trim()] = item;
    }

    final autoApply = <DataChannelUpdate>[];
    final needsConfirm = <DataChannelUpdate>[];
    var rejected = 0;
    final handled = <String>{};

    // 同 StatusBarEngine：模型可能把多项写在同一行，
    // 文本项的取值会把后面的数值项一起吞掉，必须先按已知语义名切分。
    final segments = <String>[];
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      segments.addAll(StatusBarEngine.splitSegments(line, byLabel.keys));
    }

    for (final body in segments) {
      final parsed = _splitNameAndValue(body);
      if (parsed == null) continue;
      final (name, rawValue, isAssign) = parsed;

      final item = byLabel[name];
      // 未知语义名：LLM 编造的字段，直接丢弃。
      if (item == null) {
        rejected++;
        continue;
      }
      // 通道不允许写入，或明确禁止应用。
      if (!item.canWrite) {
        rejected++;
        continue;
      }

      final applyPolicy = item.applyPolicy;
      if (applyPolicy == 'never') {
        rejected++;
        continue;
      }

      // 同一项重复输出只取第一条，避免叠加算账。
      if (!handled.add(name)) continue;

      final field = item.targetKind == 'status_field'
          ? _fieldById(statusFields, item.targetId)
          : null;
      final oldValue = _currentValue(item, session, field);

      String? newValue;
      if (item.llmWritePolicy == 'suggest_delta') {
        // 增量通道只接受 +N/-N，赋值语法一律拒绝。
        if (isAssign) {
          rejected++;
          continue;
        }
        newValue = _applyDelta(oldValue, rawValue, field);
      } else {
        // suggest_replace：直接替换，数值型仍做 clamp 兜底。
        newValue = field != null && field.isNumber
            ? _clampNumeric(rawValue, field)
            : rawValue;
      }

      if (newValue == null || newValue == oldValue) continue;

      final update = DataChannelUpdate(
        semanticLabel: item.semanticLabel,
        targetKind: item.targetKind,
        targetId: item.targetId,
        oldValue: oldValue,
        newValue: newValue,
        rawSuggestion: rawValue,
        applyPolicy: applyPolicy,
      );

      if (update.isAutoApplicable) {
        autoApply.add(update);
      } else {
        needsConfirm.add(update);
      }
    }

    return DataChannelUpdateResult(
      autoApply: autoApply,
      needsConfirm: needsConfirm,
      rejectedCount: rejected,
    );
  }

  /// 把已确认的更新写进会话副本。返回 true 表示确实发生了变化。
  static bool apply(SessionState session, List<DataChannelUpdate> updates) {
    var changed = false;
    for (final update in updates) {
      if (update.targetKind == 'status_field') {
        if (update.targetId.trim().isEmpty) continue;
        if (session.statusValues[update.targetId] != update.newValue) {
          session.statusValues[update.targetId] = update.newValue;
          changed = true;
        }
      } else if (update.targetKind == 'session_var') {
        if (session.vars[update.semanticLabel] != update.newValue) {
          session.vars[update.semanticLabel] = update.newValue;
          changed = true;
        }
      }
    }
    return changed;
  }

  // ---- 内部工具 ----

  static (String, String, bool)? _splitNameAndValue(String body) {
    final eq = body.indexOf('=');
    final colon = _firstColon(body);

    if (eq != -1 && (colon == -1 || eq < colon)) {
      final name = body.substring(0, eq).trim();
      final value = body.substring(eq + 1).trim();
      if (name.isEmpty || value.isEmpty) return null;
      return (name, value, true);
    }
    if (colon != -1) {
      final name = body.substring(0, colon).trim();
      final value = body.substring(colon + 1).trim();
      if (name.isEmpty || value.isEmpty) return null;
      return (name, value, false);
    }
    return null;
  }

  static int _firstColon(String s) {
    final a = s.indexOf(':');
    final b = s.indexOf('：');
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }

  static String _currentValue(
    DataChannelPromptItem item,
    SessionState session,
    StatusBarField? field,
  ) {
    if (item.targetKind == 'status_field') {
      return session.statusValues[item.targetId] ?? field?.initialValue ?? '0';
    }
    return session.vars[item.semanticLabel] ?? '';
  }

  static String? _applyDelta(
    String oldValue,
    String rawValue,
    StatusBarField? field,
  ) {
    final delta = _parseDelta(rawValue);
    if (delta == null) return null;
    final base = double.tryParse(oldValue.trim()) ??
        double.tryParse(field?.initialValue.trim() ?? '') ??
        0;
    var next = base + delta;
    if (field != null) {
      final min = field.minValue;
      final max = field.maxValue;
      if (min != null && next < min) next = min;
      if (max != null && next > max) next = max;
    }
    return _num(next);
  }

  static String? _clampNumeric(String raw, StatusBarField field) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return null;
    var value = parsed;
    final min = field.minValue;
    final max = field.maxValue;
    if (min != null && value < min) value = min;
    if (max != null && value > max) value = max;
    return _num(value);
  }

  static double? _parseDelta(String raw) {
    final match = RegExp(r'^[+\-]?\d+(\.\d+)?').firstMatch(raw.trim());
    if (match == null) return null;
    final parsed = double.tryParse(match.group(0)!);
    if (parsed == null) return null;
    // 增量必须带符号语义；纯数字视为正增量（与状态栏引擎一致）。
    return parsed;
  }

  static StatusBarField? _fieldById(List<StatusBarField> fields, String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
