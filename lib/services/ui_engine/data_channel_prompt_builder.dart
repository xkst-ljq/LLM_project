import 'dart:convert';

import '../../models/session_state.dart';
import '../../models/status_bar_field.dart';
import '../../models/ui_assembly_info.dart';
import 'ui_models.dart';

/// 一条参与 Prompt 的数据通道描述。
///
/// 与 `DataChannelWrite` 的区别：那个描述「UI 往哪写」，
/// 这个描述「哪些数据、以什么语义、用什么策略出现在 Prompt 里」。
class DataChannelPromptItem {
  /// 语义名称，例如「好感度」。LLM 只能看到语义名，不接收裸值。
  final String semanticLabel;

  /// 'local_ui_state' | 'session_var' | 'status_field'
  final String targetKind;

  /// 状态字段命中时的内部 id。
  final String targetId;

  /// 'none' | 'prompt' | 'hidden_context'
  final String llmReadPolicy;

  /// 'none' | 'suggest_delta' | 'suggest_replace'
  final String llmWritePolicy;

  /// 'confirm' | 'auto_low_risk' | 'never'
  ///
  /// Prompt 本身不需要这个字段，但 A9.6-4 解析 LLM 回复时要用它决定
  /// 是自动应用还是弹确认，因此在收集阶段一并带出来。
  final String applyPolicy;

  /// 当前值；仅在允许读取时才会被注入。
  final String value;

  /// 数值字段的范围提示，例如「范围 0~100」。无范围时为空。
  final String rangeHint;

  const DataChannelPromptItem({
    required this.semanticLabel,
    required this.targetKind,
    required this.targetId,
    required this.llmReadPolicy,
    required this.llmWritePolicy,
    required this.value,
    required this.rangeHint,
    this.applyPolicy = 'confirm',
  });

  /// 当前值可以出现在 Prompt 里。
  bool get canRead => llmReadPolicy == 'prompt' || llmReadPolicy == 'hidden_context';

  /// LLM 可以对这条数据提出更新建议。
  bool get canWrite => llmWritePolicy != 'none';

  /// 只允许写、不允许读：注入规则但不注入当前值。
  bool get isWriteOnly => !canRead && canWrite;
}

/// A9.6-3：把数据通道 + SessionState 渲染成 Prompt 片段。
///
/// 设计红线（见 ASSEMBLY_IMPLEMENTATION_TRACKER A9.6 章节）：
///   - LLM 绝不接收裸值，每个值都必须带 semanticLabel。
///   - 只有 `llmReadPolicy != none` 的通道才注入当前值。
///   - 只有 `llmWritePolicy != none` 的通道才允许出现在可更新清单里。
///   - `local_ui_state` 通道永不注入。
///   - 允许「可写不可读」：只注入更新规则，不暴露当前值。
///   - 本类只负责生成文本，不修改任何状态。
class DataChannelPromptBuilder {
  /// LLM 回报状态更新时使用的标签，与状态栏引擎的标签区分开。
  static const String updateTag = '界面状态变化';

  /// 从角色卡的 UI 方案里收集所有数据通道，并结合会话副本解析当前值。
  static List<DataChannelPromptItem> collectItems({
    required List<String> uiAssemblyJsons,
    required SessionState session,
    List<StatusBarField> statusFields = const <StatusBarField>[],
  }) {
    final items = <DataChannelPromptItem>[];
    final seen = <String>{};

    void addChannel(Map<String, dynamic> channel) {
      final label = channel['semanticLabel']?.toString().trim() ?? '';
      if (label.isEmpty) return;

      final targetKind = channel['targetKind']?.toString() ?? 'local_ui_state';
      // UI 内部状态永不参与 Prompt。
      if (targetKind == 'local_ui_state') return;

      final targetId = channel['targetId']?.toString() ?? '';
      // 状态字段还没匹配到卡片定义时没有可靠取值来源，跳过。
      if (targetKind == 'status_field' && targetId.trim().isEmpty) return;

      final dedupeKey = '$targetKind::${targetId.isEmpty ? label : targetId}';
      if (!seen.add(dedupeKey)) return;

      final field = targetKind == 'status_field'
          ? _fieldById(statusFields, targetId)
          : null;
      final value = targetKind == 'status_field'
          ? (session.statusValues[targetId] ?? field?.initialValue ?? '')
          : (session.vars[label] ?? '');

      items.add(
        DataChannelPromptItem(
          semanticLabel: label,
          targetKind: targetKind,
          targetId: targetId,
          llmReadPolicy: channel['llmReadPolicy']?.toString() ?? 'none',
          llmWritePolicy: channel['llmWritePolicy']?.toString() ?? 'none',
          applyPolicy:
              channel['llmUpdateApplyPolicy']?.toString() ?? 'confirm',
          value: value,
          rangeHint: field == null ? '' : _rangeHint(field),
        ),
      );
    }

    void visitElements(List<UIElement> nodes) {
      for (final node in nodes) {
        final raw = node.module?.properties['dataChannel'];
        if (raw is Map) addChannel(Map<String, dynamic>.from(raw));
        if (node.isComposite && node.composite != null) {
          visitElements(node.composite!.children);
        }
      }
    }

    for (final rawInfo in uiAssemblyJsons) {
      final info = UIAssemblyInfo.fromJsonString(rawInfo);
      if (info.id.isEmpty) continue;
      for (final page in _restorePages(info)) {
        visitElements(page.elements);
        for (final override in page.propertyOverrides) {
          final raw = override.overrides['dataChannel'];
          if (raw is Map) addChannel(Map<String, dynamic>.from(raw));
        }
      }
    }

    return items;
  }

  /// 生成注入片段。无可注入内容时返回空串。
  ///
  /// 产出结构（结构化状态段，便于调试，也不要求作者手写占位符）：
  /// ```text
  /// [界面数据]
  /// 好感度：45（范围 0~100）
  /// 主角姓名：林
  ///
  /// [可建议更新的隐藏状态]
  /// 敌方警觉度：只可输出 +N/-N，不要在正文中提及当前值。
  ///
  /// [界面数据更新格式]
  /// ...
  /// ```
  static String buildInjection(List<DataChannelPromptItem> items) {
    if (items.isEmpty) return '';

    final readable = items.where((item) => item.canRead).toList();
    final writeOnly = items.where((item) => item.isWriteOnly).toList();

    final lines = <String>[];

    if (readable.isNotEmpty) {
      lines.add('[界面数据]');
      lines.add('以下是界面当前数据（由玩家操作界面产生）：');
      for (final item in readable) {
        final value = item.value.trim().isEmpty ? '（未设置）' : item.value;
        final range = item.rangeHint.isEmpty ? '' : '（${item.rangeHint}）';
        lines.add('- ${item.semanticLabel}：$value$range');
      }
    }

    if (writeOnly.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[可建议更新的隐藏状态]');
      lines.add('以下数据当前值对你隐藏，你只能根据剧情建议其变化：');
      for (final item in writeOnly) {
        final rule = item.llmWritePolicy == 'suggest_delta'
            ? '只可输出 +N/-N，不要在正文中提及当前值。'
            : '只可给出新内容，不要在正文中提及当前值。';
        lines.add('- ${item.semanticLabel}：$rule');
      }
    }

    return lines.join('\n');
  }

  /// 更新格式约束，供历史后注入（PHI）使用。
  ///
  /// 单独拆出来的原因：格式约束放在 system prompt 开头时，
  /// 长对话中模型经常忽略它而不输出标签块。与酒馆 PHI 的思路一致，
  /// 把这类强约束放到对话历史「之后」显著提升遵从度。
  static String buildUpdateFormatInstruction(
    List<DataChannelPromptItem> items,
  ) {
    final writable = items.where((item) => item.canWrite).toList();
    if (writable.isEmpty) return '';

    final lines = <String>[];
    lines.add('[界面数据更新格式 · 必须遵守]');
    lines.add('本回合回复正文结束后，如果以下数据确有变化，'
        '必须另起一行输出变化块（没有变化则完全不输出该块）：');
    lines.add('<$updateTag>');
    for (final item in writable) {
      final format = item.llmWritePolicy == 'suggest_delta'
          ? '${item.semanticLabel}:+N 或 ${item.semanticLabel}:-N（只给变化量，不要给最终值）'
          : '${item.semanticLabel}=新内容（直接给变化后的内容）';
      lines.add(format);
    }
    lines.add('</$updateTag>');
    lines.add('规则：');
    lines.add('- 变化量需与本回合剧情合理对应。');
    lines.add('- 没有变化的项不要输出，不要输出未列出的项。');
    lines.add('- 该标记块不会展示给用户，请勿在正文中重复其内容。');
    lines.add('- 不要用代码块包裹该标记，直接输出标签本身。');

    return lines.join('\n');
  }

  /// 渲染 `{{ui.xxx}}` 占位符。
  ///
  /// 只替换 `llmReadPolicy != none` 的通道；不可读或不存在的占位符替换为空串，
  /// 避免把原始占位符或受保护的值泄漏给模型。
  static String renderPlaceholders(
    String template,
    List<DataChannelPromptItem> items,
  ) {
    if (template.isEmpty) return template;
    final byLabel = <String, DataChannelPromptItem>{};
    for (final item in items) {
      byLabel[item.semanticLabel] = item;
    }

    return template.replaceAllMapped(
      RegExp(r'\{\{\s*ui\.([^}]+?)\s*\}\}'),
      (match) {
        final key = match.group(1)!.trim();
        final item = byLabel[key];
        if (item == null || !item.canRead) return '';
        return item.value;
      },
    );
  }

  static StatusBarField? _fieldById(List<StatusBarField> fields, String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  static String _rangeHint(StatusBarField field) {
    if (!field.isNumber) return '';
    final min = field.minValue;
    final max = field.maxValue;
    if (min != null && max != null) return '范围 ${_num(min)}~${_num(max)}';
    if (max != null) return '上限 ${_num(max)}';
    if (min != null) return '下限 ${_num(min)}';
    return '';
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  static List<AssemblyPage> _restorePages(UIAssemblyInfo info) {
    final pages = <AssemblyPage>[];
    final raw = info.pagesJson.trim();
    if (raw.isNotEmpty && raw != '[]') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          pages.addAll(
            decoded.whereType<Map>().map(
                  (item) =>
                      AssemblyPage.fromJson(Map<String, dynamic>.from(item)),
                ),
          );
        }
      } catch (_) {
        pages.clear();
      }
    }

    if (pages.isNotEmpty) return pages;

    // 兼容旧版单页结构。
    final legacyRaw = info.elementsJson.trim();
    if (legacyRaw.isEmpty || legacyRaw == '[]') return pages;
    try {
      final decoded = jsonDecode(legacyRaw);
      if (decoded is List) {
        pages.add(
          AssemblyPage(
            id: 'legacy',
            name: '主页面',
            type: 'base',
            elements: decoded
                .whereType<Map>()
                .map((item) => UIElement.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList(),
          ),
        );
      }
    } catch (_) {}
    return pages;
  }
}
