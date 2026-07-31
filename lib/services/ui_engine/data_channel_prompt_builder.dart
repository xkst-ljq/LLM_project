import 'dart:convert';

import '../../models/card_entry_target.dart';
import '../../models/character_entry.dart';
import '../../models/session_state.dart';
import '../../models/status_bar_field.dart';
import '../../models/ui_assembly_info.dart';
import '../status_bar_engine.dart';
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
  /// 通知方式：'silent' | 'toast' | 'dialog'。不影响写入，只管提不提醒。
  final String notifyStyle;

  /// 自定义提醒文案，支持 {name} {old} {new}。
  final String notifyTemplate;

  /// 当前值；仅在允许读取时才会被注入。
  final String value;

  /// 数值字段的范围提示，例如「范围 0~100」。无范围时为空。
  final String rangeHint;

  /// A13-2：指向角色卡设定条目时的三级定位；其余情况为 null。
  final CardEntryTarget? cardTarget;

  /// A13-2：该条目在角色卡里的标题，用于生成显示名。
  final String cardEntryTitle;

  /// A13-1：注入到 Prompt 的哪一段。
  ///
  /// `'ui_data'`（默认）→ `[界面数据]`，语义是「玩家操作界面产生的运行时数据」。
  /// `'core_setting'`   → `[玩家档案]`，语义是「本次会话的初始设定」，
  ///                      与 `[核心角色设定]` 并列，权重显著更高。
  ///
  /// 为什么需要这个区分：玩家在 opening UI 里填的姓名 / 职业 / 属性点，
  /// 本质是**角色设定的一部分**，而不是「界面上的一个数值」。
  /// 混在 `[界面数据]` 里模型会当成可有可无的运行时状态而弱化处理。
  final String promptSection;

  const DataChannelPromptItem({
    required this.semanticLabel,
    required this.targetKind,
    required this.targetId,
    required this.llmReadPolicy,
    required this.llmWritePolicy,
    required this.value,
    required this.rangeHint,
    this.notifyStyle = 'silent',
    this.notifyTemplate = '',
    this.promptSection = sectionUiData,
    this.cardTarget,
    this.cardEntryTitle = '',
  });

  /// 注入到 `[界面数据]`（默认）。
  static const String sectionUiData = 'ui_data';

  /// 注入到 `[玩家档案]`，与核心角色设定并列。
  static const String sectionCoreSetting = 'core_setting';

  /// 这条数据是否属于会话初始化档案。
  ///
  /// 角色卡设定天然属于档案——它填的就是角色设定本身，
  /// 不需要作者再去选一次注入位置。
  bool get isCoreSetting =>
      promptSection == sectionCoreSetting || targetKind == 'card_entry';

  /// 展示用名称。角色卡设定显示成「身体数据 · 种族」这种带归属的形式，
  /// 比裸的语义名更能让模型理解它在设定体系里的位置。
  String get displayLabel => cardTarget == null
      ? semanticLabel
      : cardTarget!.displayLabel(cardEntryTitle);

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
    List<CharacterEntry> cardEntries = const <CharacterEntry>[],
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

      // A13-2：角色卡设定条目。三级定位不完整时无处可写，跳过。
      final cardTarget = targetKind == 'card_entry'
          ? CardEntryTarget.fromJson(channel['cardEntryTarget'])
          : null;
      if (targetKind == 'card_entry' &&
          (cardTarget == null || !cardTarget.isValid)) {
        return;
      }

      final dedupeKey = cardTarget != null
          ? 'card_entry::${cardTarget.sessionKey}'
          : '$targetKind::${targetId.isEmpty ? label : targetId}';
      if (!seen.add(dedupeKey)) return;

      final field = targetKind == 'status_field'
          ? _fieldById(statusFields, targetId)
          : null;
      // 角色卡设定按三级定位的专属键取值，与普通会话变量隔开，
      // 避免作者起了同名变量互相覆盖。
      final value = switch (targetKind) {
        'status_field' =>
          session.statusValues[targetId] ?? field?.initialValue ?? '',
        'card_entry' => session.vars[cardTarget!.sessionKey] ?? '',
        _ => session.vars[label] ?? '',
      };

      // 玩家没填时整条不注入：档案项的语义是「玩家做出的选择」，
      // 没选就该让母版里作者写的原值继续生效，而不是覆盖成「（未设置）」。
      if (targetKind == 'card_entry' && value.trim().isEmpty) return;

      items.add(
        DataChannelPromptItem(
          semanticLabel: label,
          targetKind: targetKind,
          targetId: targetId,
          llmReadPolicy: channel['llmReadPolicy']?.toString() ?? 'none',
          llmWritePolicy: channel['llmWritePolicy']?.toString() ?? 'none',
          notifyStyle: channel['notifyStyle']?.toString() ?? 'silent',
          notifyTemplate: channel['notifyTemplate']?.toString() ?? '',
          value: value,
          rangeHint: field == null ? '' : _rangeHint(field),
          promptSection: channel['promptSection']?.toString() ??
              DataChannelPromptItem.sectionUiData,
          cardTarget: cardTarget,
          cardEntryTitle: cardTarget == null
              ? ''
              : _cardEntryTitle(cardEntries, cardTarget),
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

  /// 取角色卡条目的标题；自定义条目直接用玩家填的标题。
  static String _cardEntryTitle(
    List<CharacterEntry> entries,
    CardEntryTarget target,
  ) {
    if (target.isCustomEntry) return target.fieldKey.trim();
    for (final entry in entries) {
      if (entry.id == target.entryId) return entry.title;
    }
    return target.entryId;
  }

  /// 提取「被 UI 数据通道引用的状态字段」的读写策略。
  ///
  /// 状态字段是 SSOT：它同时被状态栏和 UI 视图引用，但只能有一套注入与解析。
  /// 因此这类字段统一交给 `StatusBarEngine` 处理，而作者在数据通道里配置的
  /// 通知强度排序：dialog > toast > silent。
  static String _strongerNotify(String? a, String b) {
    const rank = {'silent': 0, 'toast': 1, 'dialog': 2};
    final ra = rank[a] ?? 0;
    final rb = rank[b] ?? 0;
    return ra >= rb ? (a ?? 'silent') : b;
  }

  /// 读写策略必须传递过去约束它，否则「可写不可读」会被状态栏绕过。
  static Map<String, StatusFieldPolicy> collectStatusFieldPolicies(
    List<DataChannelPromptItem> items,
  ) {
    final out = <String, StatusFieldPolicy>{};
    for (final item in items) {
      if (item.targetKind != 'status_field') continue;
      final id = item.targetId.trim();
      if (id.isEmpty) continue;

      final existing = out[id];
      // 同一状态字段被多个通道引用时取并集：
      // 任一通道允许读/写，该字段就允许读/写。
      // 通知强度取**较强**的那个，不能用 `existing ?? item`：
      // notifyStyle 永远非 null（默认 'silent'），那样写会让第一个
      // 通道的 silent 把后续通道配的 dialog 直接吃掉。
      final strongerStyle = _strongerNotify(existing?.notifyStyle, item.notifyStyle);
      out[id] = StatusFieldPolicy(
        canRead: (existing?.canRead ?? false) || item.canRead,
        canWrite: (existing?.canWrite ?? false) || item.canWrite,
        notifyStyle: strongerStyle,
        // 文案跟着被选中的那一档走，避免出现「用 A 通道的强度、
        // B 通道的文案」这种拼接结果。
        notifyTemplate: strongerStyle == item.notifyStyle
            ? (item.notifyTemplate.isNotEmpty
                ? item.notifyTemplate
                : (existing?.notifyTemplate ?? ''))
            : (existing?.notifyTemplate ?? ''),
      );
    }
    return out;
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

    // 状态字段由状态栏统一注入，这里只处理会话变量，避免同一字段被注入两次、
    // 让模型面对两套标签与两套格式而无所适从。
    final scoped =
        items.where((item) => item.targetKind != 'status_field').toList();
    final readable = scoped.where((item) => item.canRead).toList();
    final writeOnly = scoped.where((item) => item.isWriteOnly).toList();

    final lines = <String>[];

    // A13-1：玩家档案单独成段。
    //
    // 与 `[界面数据]` 分开是刻意的——档案是「本次会话的初始设定」，
    // 语义上与角色设定同级；混在界面数据里会被模型当成可有可无的
    // 运行时数值而弱化处理（玩家填的姓名被无视是最典型的症状）。
    final profile = readable.where((item) => item.isCoreSetting).toList();
    final uiData = readable.where((item) => !item.isCoreSetting).toList();

    if (profile.isNotEmpty) {
      lines.add('[玩家档案]');
      lines.add('以下是本次会话开始时由玩家确定的设定，属于角色设定的一部分，'
          '在整场对话中保持有效。若与前文的角色设定有冲突，以此处为准：');
      for (final item in profile) {
        final value = item.value.trim().isEmpty ? '（未设置）' : item.value;
        final range = item.rangeHint.isEmpty ? '' : '（${item.rangeHint}）';
        lines.add('- ${item.displayLabel}：$value$range');
      }
    }

    if (uiData.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[界面数据]');
      lines.add('以下是界面当前数据（由玩家操作界面产生）：');
      for (final item in uiData) {
        final value = item.value.trim().isEmpty ? '（未设置）' : item.value;
        final range = item.rangeHint.isEmpty ? '' : '（${item.rangeHint}）';
        lines.add('- ${item.displayLabel}：$value$range');
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
    // 同上：状态字段走 <状态变化>，这里只约束会话变量的结算格式。
    final writable = items
        .where((item) => item.targetKind != 'status_field' && item.canWrite)
        .toList();
    if (writable.isEmpty) return '';

    final lines = <String>[];
    lines.add('[界面数据结算 · 每回合必须输出结算块]');
    lines.add('你每一条回复的最后，都必须附上界面数据结算块。这是系统协议，'
        '不是可选项，也不需要用户提出要求。');
    lines.add('');
    // 关键：先把「空结算」立为默认预期，再讲怎么填。
    // 否则「每回合必须输出」会被模型理解成「每回合都得算出点什么」，
    // 导致两三句闲聊就产生数值漂移。
    lines.add('重要：绝大多数回合都应该是空结算块。数据只在剧情中真正发生了'
        '对应事件时才变化，日常对话、寒暄、单纯的信息交流一律不产生变化。');
    lines.add('');
    lines.add('可结算项：');
    for (final item in writable) {
      final format = item.llmWritePolicy == 'suggest_delta'
          ? '- ${item.semanticLabel}：格式 `${item.semanticLabel}:+N` 或 '
              '`${item.semanticLabel}:-N`，只给变化量，不要给最终值'
          : '- ${item.semanticLabel}：格式 `${item.semanticLabel}=新内容`，'
              '直接给变化后的内容';
      lines.add(format);
    }
    lines.add('');
    // 示例一律用空块。写具体数值会被模型当成标准答案照抄，
    // 每回合都输出示例里的那个变化量。
    lines.add('默认输出（本回合无事发生时，也是最常见的情况）：');
    lines.add('<$updateTag>');
    lines.add('</$updateTag>');
    lines.add('');
    lines.add('执行规则：');
    lines.add('- 每回合都要输出 <$updateTag>...</$updateTag> 这一对标签，'
        '即使本回合没有任何变化，也要输出一对空标签。');
    lines.add('- 标签内只写确有变化的项；没有变化的项不写，也不要写未列出的项。');
    lines.add('- 判断标准：只有本回合剧情中确实出现了足以改变该数据的具体事件时'
        '才写入。拿不准时，一律不写。');
    lines.add('- 变化幅度要克制：普通互动最多小幅变动，'
        '大幅变化只保留给剧情中的重大转折。');
    lines.add('- 不要为了让结算块「有内容」而制造变化，空结算块是完全正常的。');
    lines.add('- 同一项在连续多个回合里反复变化是不正常的，除非剧情确实在持续推进。');
    lines.add('- 直接输出标签本身，不要用代码块或引号包裹。');
    lines.add('- 该标记不会展示给用户，正文中不要重复或提及它的内容。');

    return lines.join('\n');
  }

  /// 每回合贴在最后一条用户消息尾部的极短提醒。
  ///
  /// PHI 解决的是「指令离得太远被淡忘」，但部分模型在沉浸式角色扮演时
  /// 仍会忽略系统层的格式要求。紧贴用户消息的一行短提醒是成本最低的补强，
  /// 且因为足够短，不会干扰正文的角色扮演质量。
  static String buildTurnReminder(List<DataChannelPromptItem> items) {
    final writable = items
        .where((item) => item.targetKind != 'status_field' && item.canWrite)
        .toList();
    if (writable.isEmpty) return '';
    return '（系统提醒：本回合回复结束后，附上 '
        '<$updateTag>...</$updateTag> 结算块；本回合无对应事件就输出空标签。）';
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
