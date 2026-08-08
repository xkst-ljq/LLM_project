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
      if (plan.uiMode == 'scene') {
        if (!_hasSceneMessagePage(plan)) {
          errors.add('scene 会抑制原生聊天列表，必须声明一个 layout.pages role=story/message/narrative/content/log 的正文页，让编译器插入 message_flow；只在 notes 里说“建议使用 message_flow”不会生成组件。');
        } else if (_messagePageIsOvercrowded(plan, sourcePack)) {
          errors.add('scene 正文/message_flow 页面过于拥挤：不要把完整状态栏、任务板、羁绊名录等低频详情全部堆在正文与选项之间。请保留正文页 + 当前选项/自由输入，把完整状态/任务/羁绊改为 type=overlay 的叠加页或少量详情页。');
        }
        final baseDetailPages = _baseDetailPagesThatShouldBeOverlay(plan, sourcePack);
        if (baseDetailPages.isNotEmpty) {
          errors.add('scene 中以下低频详情页不应作为稀疏 base tab 撑大 PCB：${baseDetailPages.join('、')}。请在 layout.pages 中设置 type="overlay" 并指定 parentPage 为正文/message_flow 页面。');
        }
        final branchDataErrors = _branchRuntimeDataErrors(plan, sourcePack);
        errors.addAll(branchDataErrors);
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
    if (plan.uiMode == 'scene' && plan.layout.pages.length > 9) {
      errors.add('scene 页面过多（${plan.layout.pages.length} 页），容易形成稀疏空页。请优先参考原卡长卡/网格结构，合并为主正文页 + 状态/任务/羁绊等少量页面，或使用 overlay 承载低频详情。');
    }
    final sparsePages = _sparsePages(plan);
    if (sparsePages.isNotEmpty) {
      errors.add("以下页面内容过少，容易导致 PCB 大面积空白：${sparsePages.join('、')}。请合并到相关页面、改为 overlay，或放入大规格 scroll/message_flow 内容区。");
    }
    errors.addAll(_layoutIntentErrors(plan));
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

    // ── 分支变体（branchPlans）递归校验 ──
    // 变体是完整 UiDesignPlan，复用同一套校验；额外约束：
    // uiMode 必须与主支路一致（引擎一个 assembly 只有一个 mode）；
    // 不允许嵌套 branchPlans（不支持递归变体）。
    for (final entry in plan.branchPlans.entries) {
      final branch = entry.key;
      final vp = entry.value;
      if (vp.uiMode != plan.uiMode) {
        errors.add('branchPlans[$branch] 的 uiMode（${vp.uiMode}）与主支路（${plan.uiMode}）不一致；同一 assembly 只能有一个 mode。');
      }
      if (vp.branchPlans.isNotEmpty) {
        errors.add('branchPlans[$branch] 不允许再嵌套 branchPlans（不支持递归变体）。');
      }
      if (vp.hasUi) {
        final sub = validate(vp, sourcePack);
        errors.addAll(sub.errors.map((e) => '[branch$branch] $e'));
        warnings.addAll(sub.warnings.map((e) => '[branch$branch] $e'));
      }
    }

    return UiPlanValidationResult(
      ok: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// 跨 assembly 的强制校验：多套 UI 之间的组合关系必须成立。
  ///
  /// 与 [validate]（单 plan 结构校验）互补，由 AiUiInterpreter 在收集完各
  /// plan 的校验结果后调用一次。涵盖：
  /// 1. 多开场白（alternate_greetings 非空）时**必须**存在 uiMode=opening。
  /// 2. 多开场白时 opening 必须做分支差异化（branchIndex 映射 +
  ///    branchInitialValues/branchPlans），不能是空壳按钮。
  /// 3. 高信息密度卡只用 extra_companion 而无 scene 时给出 warning
  ///    （companion 212px 多页签仍可承载，故不强杀）。
  static UiPlanValidationResult validateAssemblies(
    List<UiDesignPlan> plans,
    UiSourcePack sourcePack,
  ) {
    final errors = <String>[];
    final warnings = <String>[];
    final hasMultiGreeting = sourcePack.alternateGreetings.isNotEmpty;
    final openings = plans.where((p) => p.uiMode == 'opening').toList();
    final hasScene = plans.any((p) => p.uiMode == 'scene');
    final hasCompanion = plans.any((p) => p.uiMode == 'extra_companion');

    // 同一 uiMode 不应重复出现：两张伴生栏 / 两个 scene 会让玩家看到重复 UI，
    // 且无法判断哪套是作者想要的。这是修复轮绝不能"补回"的错误。
    final modeCounts = <String, int>{};
    for (final p in plans) {
      final mode = p.uiMode;
      if (mode.isEmpty) continue;
      modeCounts[mode] = (modeCounts[mode] ?? 0) + 1;
    }
    for (final entry in modeCounts.entries) {
      if (entry.value > 1) {
        errors.add('uiMode=${entry.key} 重复出现 ${entry.value} 次：同一生命周期只应编译一份 UI，请合并或删除多余的方案。');
      }
    }

    // scene 与 extra_companion 互斥：scene 接管整个聊天屏幕，会抑制
    // 原生伴生栏；两者并存时玩家会同时看到两套常驻 UI。
    if (hasScene && hasCompanion) {
      errors.add('scene 与 extra_companion 互斥——scene 全屏接管聊天页并抑制原生伴生栏；'
          '一张卡不应同时输出两个常驻生命周期。请把低频详情合并进 scene 的 overlay 页，删除 extra_companion。');
    }

    if (hasMultiGreeting && openings.isEmpty) {
      errors.add('角色卡存在多个开场白（alternate_greetings 共 ${sourcePack.alternateGreetings.length} 条），'
          'assemblies 必须包含 uiMode=opening 供玩家选择开场方向；只给伴生/场景 UI 会让玩家错过开场白。');
    } else if (openings.isNotEmpty) {
      for (var i = 0; i < openings.length; i++) {
        final openingErrors =
            _openingBranchDifferentiationErrors(openings[i], sourcePack);
        for (final e in openingErrors) {
          errors.add('[opening#$i] $e');
        }
      }
    }

    if (hasMultiGreeting && !hasScene && hasCompanion) {
      // 多开场白 + 高密度但只给了 companion：场景信息密度足以支撑 scene，
      // 但 212px 多页签伴生栏也能承载，降级为提示性警告。
      final density = sourcePack.densityAssessment();
      if (density.isHigh) {
        warnings.add('原卡信息密度高（${density.reasons.join('; ')}），但转译结果只用 extra_companion。'
            '若原卡是沉浸式终端/正文被 UI 包裹，建议改用 scene 全屏承载，'
            '否则请确认 212px 伴生栏多页签足够承载全部信息。');
      }
    }

    return UiPlanValidationResult(
      ok: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// 单个 opening 在"多开场白"场景下的差异化校验。
  static List<String> _openingBranchDifferentiationErrors(
    UiDesignPlan opening,
    UiSourcePack sourcePack,
  ) {
    final errors = <String>[];
    final branchCount = 1 + sourcePack.alternateGreetings.length;
    final branchIndices = <int>{
      for (final a in opening.actions)
        if (a.branchIndex != null) a.branchIndex!,
    };
    if (branchIndices.isEmpty) {
      errors.add('多开场白时 opening 的 actions 必须用 branchIndex 对应每个开场方向'
          '（0=first_mes，1..N-1=alternate_greetings），不能只给空壳按钮。');
      return errors;
    }
    for (var branch = 0; branch < branchCount; branch++) {
      if (!branchIndices.contains(branch)) {
        errors.add('opening 缺少开场白方向 branchIndex=$branch（first_mes=0，'
            'alternate_greetings 依次为 1..${branchCount - 1}）对应的按钮。');
      }
    }
    // 差异化：branchPlans 或 branchInitialValues 至少出现一种，才算真的
    // 对多开场白做了分支适配。仅当各分支初始状态确实存在数值差异时才强制。
    final hasBranchPlans = opening.branchPlans.isNotEmpty;
    final hasBranchValues = opening.fields.any((f) => f.branchInitialValues.isNotEmpty);
    if (!hasBranchPlans && !hasBranchValues && _anyBranchStatusDiffers(sourcePack)) {
      errors.add('多开场白各分支的初始状态数据不同，opening 必须用 '
          'fields[].branchInitialValues 表达分支差异（或 branchPlans 表达结构差异），'
          '否则选择不同开场白后状态栏仍显示同一套初始值。');
    }
    return errors;
  }

  /// 各开场分支的持久状态（PlayerStatus 格式）是否存在可证的数值差异。
  static bool _anyBranchStatusDiffers(UiSourcePack sourcePack) {
    final branchCount = 1 + sourcePack.alternateGreetings.length;
    if (branchCount < 2) return false;
    final branch0 = sourcePack.playerStatusForBranchIndex(0);
    if (branch0.isEmpty) return false;
    for (var branch = 1; branch < branchCount; branch++) {
      final b = sourcePack.playerStatusForBranchIndex(branch);
      if (b.isEmpty) continue;
      for (final entry in branch0.entries) {
        final v0 = entry.value;
        final vb = b[entry.key];
        if (vb != null && vb != v0) return true;
      }
    }
    return false;
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
      final isOverlay = page.type == 'overlay';
      if (componentCount == 0) {
        result.add('$title(空页)');
      } else if (!isOverlay && componentCount <= 2 && !hasLargeScrollField && !isActionOnly) {
        result.add('$title($componentCount 项)');
      }
    }
    return result;
  }

  /// 校验 AI 布局意图字段的合法性（columns / density / fill）。
  static List<String> _layoutIntentErrors(UiDesignPlan plan) {
    final errors = <String>[];
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isEmpty) continue;
      final columns = page.columns;
      if (columns > 6) {
        errors.add('页面「$title」columns 超出上限 6。');
      }
      final density = page.density;
      if (density.isNotEmpty &&
          !const {'compact', 'normal', 'spacious'}.contains(density)) {
        errors.add('页面「$title」density 非法：$density（应为 compact/normal/spacious）。');
      }
    }
    for (final field in plan.fields) {
      if (field.span > 2) {
        errors.add('字段「${field.name}」span 超出上限 2。');
      }
      if (field.layout.isNotEmpty &&
          !const {'standard', 'grid', 'progress', 'badge'}.contains(field.layout)) {
        errors.add('字段「${field.name}」layout 非法：${field.layout}。');
      }
    }
    return errors;
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
    final usesAutoQuestBoard = values.any((v) => v.trim() == '__AUTO_QUEST_BOARD__');
    if (usesAutoQuestBoard) return const [];
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

  static bool _hasSceneMessagePage(UiDesignPlan plan) {
    return plan.layout.pages.any((page) =>
        page.type != 'overlay' && _isMessagePage(page.title, page.role));
  }

  static bool _messagePageIsOvercrowded(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    final messagePages = <String>{
      for (final page in plan.layout.pages)
        if (page.type != 'overlay' && _isMessagePage(page.title, page.role))
          page.title.trim(),
    }..removeWhere((e) => e.isEmpty);
    if (messagePages.isEmpty) return false;

    for (final page in messagePages) {
      final fields = plan.fields.where((f) => f.page.trim() == page).toList();
      final controlsOnPage = plan.actions.any((a) => a.page.trim() == page) ||
          plan.inputs.any((input) => input.page.trim() == page);
      if (!controlsOnPage) continue;
      final hasDetailScroll = fields.any((f) {
        final text = '${f.name} ${f.sourceKey} ${f.group}'.toLowerCase();
        return f.overflow == 'scroll' &&
            (text.contains('任务') ||
                text.contains('quest') ||
                text.contains('task') ||
                text.contains('羁绊') ||
                text.contains('好友') ||
                text.contains('friends') ||
                text.contains('album'));
      });
      final hasManyRuntimeFields = fields.length >= 9 &&
          (sourcePack.hasQuestSchema ||
              sourcePack.hasFriendsAlbumSchema ||
              fields.any((f) => f.display == 'progress'));
      if (hasDetailScroll || hasManyRuntimeFields) return true;
    }
    return false;
  }

  static List<String> _baseDetailPagesThatShouldBeOverlay(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    if (!_hasSceneMessagePage(plan)) return const [];
    if (!(sourcePack.hasQuestSchema ||
        sourcePack.hasFriendsAlbumSchema ||
        plan.fields.any((f) => f.display == 'progress'))) {
      return const [];
    }
    final out = <String>[];
    for (final page in plan.layout.pages) {
      final title = page.title.trim();
      if (title.isEmpty || page.type == 'overlay') continue;
      if (_isMessagePage(title, page.role)) continue;
      final fields = plan.fields.where((f) => f.page.trim() == title).toList();
      final controls = plan.inputs.any((input) => input.page.trim() == title) ||
          plan.actions.any((action) => action.page.trim() == title);
      if (fields.isEmpty || controls) continue;
      final text = '$title ${page.role} ${fields.map((f) => '${f.name} ${f.group}').join(' ')}'.toLowerCase();
      final isLowFrequencyDetail = title.contains('状态') ||
          title.contains('任务') ||
          title.contains('伙伴') ||
          title.contains('羁绊') ||
          title.contains('好友') ||
          title.contains('档案') ||
          text.contains('stats') ||
          text.contains('quest') ||
          text.contains('task') ||
          text.contains('companion') ||
          text.contains('friend') ||
          text.contains('album');
      if (isLowFrequencyDetail) out.add(title);
    }
    return out;
  }

  static List<String> _branchRuntimeDataErrors(
    UiDesignPlan plan,
    UiSourcePack sourcePack,
  ) {
    if (sourcePack.alternateGreetings.isEmpty) return const [];
    final branch0Quests = sourcePack.questSummariesForBranchIndex(0);
    if (branch0Quests.isEmpty) return const [];

    final branchesWithoutQuest = <int>[];
    for (var branch = 1; branch <= sourcePack.alternateGreetings.length; branch++) {
      if (sourcePack.questSummariesForBranchIndex(branch).isEmpty) {
        branchesWithoutQuest.add(branch);
      }
    }
    if (branchesWithoutQuest.isEmpty) return const [];

    final taskFields = plan.fields.where((field) {
      final text = '${field.name} ${field.sourceKey} ${field.group} ${field.page}'.toLowerCase();
      return text.contains('quest') || text.contains('task') || text.contains('任务');
    }).toList();
    if (taskFields.isEmpty) return const [];

    final missing = <String>[];
    for (final field in taskFields) {
      if (field.initialValue.trim() == '__AUTO_QUEST_BOARD__') continue;
      final missingBranches = branchesWithoutQuest
          .where((branch) => !field.branchInitialValues.containsKey('$branch'))
          .toList();
      if (missingBranches.isNotEmpty) {
        missing.add('${field.name}(缺少 branchInitialValues: ${missingBranches.join('/')})');
      }
    }
    if (missing.isEmpty) return const [];
    return [
      '多开场分支的任务数据不对称：branch 0 有初始任务，${branchesWithoutQuest.map((b) => 'branch $b').join('、')}没有任务 schema。任务板字段必须用 branchInitialValues 标出无任务/待剧情更新，避免选择第二开场后仍显示第一开场的公会任务：${missing.join('、')}。',
    ];
  }

  static bool _hasStandaloneActionPage(UiDesignPlan plan) {
    if (plan.actions.isEmpty && plan.inputs.isEmpty) return false;
    final actionPages = <String>{
      for (final page in plan.layout.pages)
        if (page.type != 'overlay' && _isActionPage(page.title, page.role))
          page.title.trim(),
    }..removeWhere((e) => e.isEmpty);
    if (actionPages.isEmpty) return false;
    final messagePages = <String>{
      for (final page in plan.layout.pages)
        if (page.type != 'overlay' && _isMessagePage(page.title, page.role))
          page.title.trim(),
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
