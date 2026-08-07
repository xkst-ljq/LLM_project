import 'ui_design_plan.dart';
import 'ui_source_pack.dart';

class UiPlanValidationResult {
  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  const UiPlanValidationResult({
    required this.ok,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// 对 AI 输出的 UiDesignPlan 做防幻觉和结构校验。
class UiPlanValidator {
  const UiPlanValidator._();

  static UiPlanValidationResult validate(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    final errors = <String>[];
    final warnings = <String>[];

    if (!plan.hasUi) {
      if (plan.evidenceSummary.trim().isEmpty) {
        warnings.add('AI 判断无 UI，但没有说明原因。');
      }
      return UiPlanValidationResult(ok: true, warnings: warnings);
    }

    const modes = {'opening', 'scene', 'extra_sticky', 'extra_companion'};
    if (!modes.contains(plan.uiMode)) {
      errors.add('非法 uiMode：${plan.uiMode}');
    }

    if (plan.fields.isEmpty && plan.inputs.isEmpty && plan.actions.isEmpty) {
      if (plan.uiMode == 'scene') {
        warnings.add('scene 未输出字段/输入/动作，将只生成 message_flow 与系统设置按钮。');
      } else {
        errors.add('AI 判断有 UI，但没有输出任何字段、输入框或动作。');
      }
    }
    if (plan.uiMode == 'opening' && plan.actions.isEmpty && plan.inputs.isEmpty) {
      errors.add('opening UI 必须至少有一个开场按钮或输入框。');
    }
    if (plan.uiMode == 'opening' && sourcePack.alternateGreetings.isNotEmpty) {
      final branchActions = plan.actions.where((a) => a.branchIndex != null).length;
      if (branchActions == 0) {
        errors.add('角色卡存在多个开场白，opening actions 必须用 branchIndex 对应 first_mes / alternate_greetings；不要把某条开场内部的 DQ/任务选项当作 opening 选择。');
      }
    }
    if (plan.uiMode == 'opening' && plan.fields.length > 8) {
      errors.add('opening UI 字段过多：opening 只应承载简介、少量人物信息与开场方向选择；完整 PlayerStatus 应放入 scene/companion/sticky。');
    }
    if (plan.uiMode == 'opening' && plan.layout.pages.length > 1) {
      errors.add('opening UI 不应把“角色设定填写”和“开场方向选择”拆成多个稀疏 tab；请合并为一张可滚动的档案/登记卡。');
    }
    if (plan.uiMode == 'opening' && _sourceSuggestsProfilePool(sourcePack)) {
      final profileInputs = plan.inputs
          .where((input) => input.targetKind == 'status_field' && !input.sendOnSubmit)
          .length;
      if (profileInputs < 3) {
        errors.add('源卡允许/要求玩家指定姓名、年龄、外貌、性格等信息；opening UI 应提供多个绑定到 status_field 的角色设定输入框，而不是只给开场方向按钮。');
      }
    }

    if (plan.uiMode != 'opening') {
      if (sourcePack.hasQuestSchema && !_hasFieldLike(plan, const ['quest', 'task', '任务'])) {
        errors.add('检测到稳定 {quest...} 任务 schema；除非作者明确拒绝，运行时 UI 应提供 task_board/任务板 滚动文本字段或页面，供 LLM 更新任务，而不是只标 unsupported。');
      } else if (sourcePack.hasQuestSchema) {
        final questErrors = _questDisplayErrors(plan, sourcePack);
        errors.addAll(questErrors);
      }
      if (sourcePack.hasFriendsAlbumSchema &&
          !_hasFieldLike(plan, const ['friends', 'album', 'friend', '羁绊', '好友'])) {
        errors.add('检测到稳定 FriendsAlbumPage schema；运行时 UI 应提供 friends_album/羁绊名录 滚动文本字段或页面，供 LLM 更新。');
      }
      if (sourcePack.hasChoiceBoxSchema && plan.actions.isEmpty) {
        errors.add('检测到稳定 DQ_ChoiceBox schema；应在合理情况下生成 sendsMessage actions/buttons，让玩家可点击选择。若确实不能点击，也必须在 notes 说明原因并提供替代交互。');
      }
      if (plan.uiMode == 'scene' && _hasStandaloneActionPage(plan)) {
        errors.add('scene 不应把行动/选项做成稀疏独立 tab。请把当前选项按钮/自由输入放在故事/message_flow 页面底部，或做成 overlay/sticky 行动坞。');
      }
    }

    if (plan.sourceRefs.isEmpty && plan.fields.every((f) => f.sourceRef.isEmpty) &&
        plan.inputs.every((i) => i.sourceRef.isEmpty) &&
        plan.actions.every((a) => a.sourceRef.isEmpty)) {
      errors.add('AI 判断有 UI，但没有提供任何 sourceRef 证据。');
    }

    if (!sourcePack.hasEvidence && plan.confidence >= 0.6) {
      warnings.add('证据包没有明显 UI 证据，但 AI 仍给出较高置信度，请人工复核。');
    }

    if (plan.fields.length > 40) {
      errors.add('字段过多（${plan.fields.length}），可能把正文/世界书误识别成 UI。');
    }
    if (plan.uiMode == 'scene' && plan.layout.pages.length > 5) {
      errors.add('scene 页面过多（${plan.layout.pages.length} 页），容易形成稀疏空页。请优先参考原卡长卡/网格结构，合并为主正文页 + 状态/任务/羁绊等少量页面，或使用 overlay 承载低频详情。');
    }
    final sparsePages = _sparsePages(plan);
    if (sparsePages.isNotEmpty) {
      errors.add("以下页面内容过少，容易导致 PCB 大面积空白：${sparsePages.join('、')}。请合并到相关页面、改为 overlay，或放入大规格 scroll/message_flow 内容区。");
    }
    if (plan.inputs.length > 4) {
      warnings.add('输入框较多（${plan.inputs.length}），编译时会压缩布局。');
    }
    if (plan.actions.length > 24) {
      warnings.add('动作按钮较多（${plan.actions.length}），编译时会压缩布局。');
    }

    final seen = <String>{};
    for (final f in plan.fields) {
      if (f.name.trim().isEmpty) {
        errors.add('存在空字段名。');
        continue;
      }
      final key = f.name.trim().toLowerCase();
      if (!seen.add(key)) {
        warnings.add('字段「${f.name}」重复，编译时会自动去重。');
      }
      if (f.sourceRef.trim().isEmpty) {
        warnings.add('字段「${f.name}」缺少 sourceRef。');
      }
      if (_badEllipsisField(f)) {
        errors.add('字段「${f.name}」包含有意义的状态/长文本信息，不应使用 ellipsis 截断。请改用 overflow=wrap 或 scroll，并确保文本框高度足够。');
      }
      if (f.isNumber) {
        final min = f.min ?? 0.0;
        final max = f.max ?? 100.0;
        if (max <= min) {
          errors.add('字段「${f.name}」max 必须大于 min。');
        }
        final v = _cleanNumber(f.initialValue);
        if (f.initialValue.trim().isNotEmpty && v == null) {
          warnings.add('数值字段「${f.name}」初值无法解析，将按 0 处理。');
        }
      }
    }

    final splitGroups = _groupsSplitAcrossPages(plan);
    if (splitGroups.isNotEmpty) {
      errors.add("以下字段组被拆散到多个页面：${splitGroups.join('、')}。语义关联紧密的信息应尽量放在同一页或同一 overlay 中，避免玩家来回切页。");
    }

    for (final input in plan.inputs) {
      if (input.placeholder.trim().isEmpty) {
        errors.add('存在空输入框占位提示。');
      }
      if (input.sourceRef.trim().isEmpty) {
        warnings.add('输入框「${input.placeholder}」缺少 sourceRef。');
      }
    }

    for (final a in plan.actions) {
      if (a.label.trim().isEmpty && a.sendText.trim().isEmpty) {
        errors.add('存在空动作按钮。');
      }
      if (a.sourceRef.trim().isEmpty) {
        warnings.add('动作「${a.label.isEmpty ? a.sendText : a.label}」缺少 sourceRef。');
      }
    }

    return UiPlanValidationResult(
      ok: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  static List<String> _sparsePages(UiDesignPlan plan) {
    if (plan.layout.pages.length <= 1) return const [];
    final result = <String>[];
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isEmpty) continue;
      if (_isMessagePage(title, page.role)) continue;
      final fields = plan.fields.where((f) => f.page.trim() == title).toList();
      final inputs = plan.inputs.where((i) => i.page.trim() == title).toList();
      final actions = plan.actions.where((a) => a.page.trim() == title).toList();
      final componentCount = fields.length + inputs.length + actions.length;
      final hasLargeScrollField = fields.any((f) => f.overflow == 'scroll');
      final isActionOnly = fields.isEmpty && (inputs.isNotEmpty || actions.isNotEmpty);
      if (componentCount == 0) {
        result.add('$title(空页)');
      } else if (componentCount <= 2 && !hasLargeScrollField && !isActionOnly) {
        result.add('$title($componentCount 项)');
      }
    }
    return result;
  }

  static List<String> _groupsSplitAcrossPages(UiDesignPlan plan) {
    final pagesByGroup = <String, Set<String>>{};
    for (final field in plan.fields) {
      final group = field.group.trim();
      final page = field.page.trim();
      if (group.isEmpty || page.isEmpty) continue;
      pagesByGroup.putIfAbsent(group, () => <String>{}).add(page);
    }
    final result = <String>[];
    pagesByGroup.forEach((group, pages) {
      // 泛词有时被 AI 当作大类，避免误伤；真正需要约束的是
      // 核心状态/装备与状态/羁绊名录/任务板这类明确小组。
      const broadGroups = {'状态', '数据', '信息', '记录', '冒险记录', '详情', '其他'};
      if (pages.length > 1 && group.runes.length > 1 && !broadGroups.contains(group)) {
        result.add("$group(${pages.join('/')})");
      }
    });
    result.sort();
    return result;
  }

  static List<String> _questDisplayErrors(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    final taskFields = plan.fields.where((field) {
      final text = '${field.name} ${field.sourceKey} ${field.group} ${field.page}'.toLowerCase();
      return text.contains('quest') || text.contains('task') || text.contains('任务');
    }).toList();
    if (taskFields.isEmpty) return const [];

    final values = <String>[
      for (final f in taskFields) f.initialValue,
      for (final f in taskFields) ...f.branchInitialValues.values,
    ].where((v) => v.trim().isNotEmpty).toList();
    final joined = values.join('\n');
    final errors = <String>[];
    if (RegExp(r'\{\s*quest\s*:|\|desc\s*:|\|reward\s*:|\|risk\s*:')
        .hasMatch(joined)) {
      errors.add('任务板不应直接显示原始 `{quest:...|desc:...}` 语段。请把任务格式化为玩家可读的任务卡/任务清单文本，并保留字段顺序和分隔。');
    }
    final names = sourcePack.questSummaries
        .map((q) => q.name.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (names.length > 1 && joined.trim().isNotEmpty) {
      final missing = names.where((name) => !joined.contains(name)).toList();
      if (missing.isNotEmpty) {
        errors.add("任务板初始内容缺少任务：${missing.join('、')}。如果 first_mes 提供多条任务，应全部纳入初始任务板，而不是只显示一条。");
      }
    }
    for (final f in taskFields) {
      if (f.overflow != 'scroll') {
        errors.add('任务字段「${f.name}」应使用 overflow=scroll 并给足高度，避免任务详情显示不全。');
      }
    }
    return errors;
  }

  static bool _hasFieldLike(UiDesignPlan plan, List<String> needles) {
    bool hit(String value) {
      final lower = value.toLowerCase();
      return needles.any((needle) => lower.contains(needle.toLowerCase()));
    }

    return plan.fields.any((field) =>
        hit(field.name) || hit(field.sourceKey) || hit(field.group) || hit(field.page));
  }

  static bool _hasStandaloneActionPage(UiDesignPlan plan) {
    if (plan.actions.isEmpty && plan.inputs.isEmpty) return false;
    final actionPages = <String>{
      for (final page in plan.layout.pages)
        if (_isActionPage(page.title, page.role)) page.title.trim(),
    }..removeWhere((e) => e.isEmpty);
    if (actionPages.isEmpty) return false;
    final messagePages = <String>{
      for (final page in plan.layout.pages)
        if (_isMessagePage(page.title, page.role)) page.title.trim(),
    }..removeWhere((e) => e.isEmpty);
    if (messagePages.isEmpty) return false;
    final actionHasFields = plan.fields.any((field) => actionPages.contains(field.page.trim()));
    final actionHasControls = plan.actions.any((a) => actionPages.contains(a.page.trim())) ||
        plan.inputs.any((input) => actionPages.contains(input.page.trim()));
    return actionHasControls && !actionHasFields;
  }

  static bool _isActionPage(String title, String role) {
    final r = role.toLowerCase();
    final t = title.toLowerCase();
    return const {'actions', 'choice', 'choices', 'input'}.contains(r) ||
        title.contains('行动') ||
        title.contains('指令') ||
        title.contains('选项') ||
        title.contains('抉择') ||
        t.contains('action') ||
        t.contains('choice');
  }

  static bool _isMessagePage(String title, String role) {
    final r = role.toLowerCase();
    final t = title.toLowerCase();
    return const {'story', 'log', 'message', 'messages', 'content', 'narrative'}
            .contains(r) ||
        title.contains('日志') ||
        title.contains('正文') ||
        title.contains('剧情') ||
        title.contains('故事') ||
        t.contains('log') ||
        t.contains('story');
  }

  static bool _badEllipsisField(UiPlanField field) {
    if (field.overflow != 'ellipsis') return false;
    if (field.display == 'progress') return false;
    final values = [field.initialValue, ...field.branchInitialValues.values]
        .where((v) => v.trim().isNotEmpty)
        .toList();
    final text = '${field.name} ${field.sourceKey} ${field.group} ${field.page}';
    const meaningfulMarkers = [
      '物品',
      'items',
      '声望',
      'reputation',
      '点数',
      'pts',
      'money',
      '位置',
      'location',
      '关系',
      'relation',
      '选项',
      'choice',
      '任务',
      'quest',
      '羁绊',
      '好友',
      'friends',
      '罪名',
      '称号',
      '当前',
      '状态效果',
      '备注',
      '说明',
    ];
    if (meaningfulMarkers.any((m) => text.toLowerCase().contains(m.toLowerCase()))) {
      return true;
    }
    return values.any((v) => v.runes.length > 18) || field.name.runes.length > 14;
  }

  static bool _sourceSuggestsProfilePool(UiSourcePack sourcePack) {
    final text = '${sourcePack.description}\n${sourcePack.systemPrompt}\n'
            '${sourcePack.firstMes}\n${sourcePack.alternateGreetings.join('\n')}'
        .toLowerCase();
    const markers = [
      '未指定',
      '随机生成',
      '姓名',
      '年龄',
      '服装',
      '外貌',
      '性格',
      '玩家指定',
      '无设定user',
      '无具体设定',
      '自定义',
      '出场方式',
      '身份',
      'user profile',
      'appearance',
      'personality',
    ];
    return markers.any(text.contains);
  }

  static double? _cleanNumber(String raw) {
    if (raw.trim().isEmpty) return null;
    if (RegExp(r'[万亿千百]').hasMatch(raw)) return null;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    if (m == null) return null;
    return double.tryParse(m.group(0)!);
  }
}
