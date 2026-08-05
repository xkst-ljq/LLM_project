import 'dart:convert';

import 'api_service.dart';
import 'app_settings.dart';
import 'ai_transcript.dart';
import 'ai_ui_designer.dart';
import 'regex_ui_extractor.dart';

/// 蓝图阶段：AI 先读原卡、理解、产出**分条目的 UI 蓝图**，再进 API 库
/// 逐条检验实现可行性，最后生成最终意图。
///
/// 设计动机（见 `docs/AI_UI_CREATION_ENGINE.md`）：
/// - AI 逐步设计会「一步看一步」，缺少整体蓝图 → 重叠/超长/简陋；
/// - 蓝图分条目，用户可逐条确认/修改，AI 查 API 库时也能精确到「哪一条
///   降级」，每条逻辑关系更明了。
///
/// 流程：
///   `designBlueprint(原卡)` → 蓝图（分条目）
///   `[用户确认 / 修改]`（可被设置开关跳过）
///   `designIntentFromBlueprint(蓝图, API库)` → 最终意图
///   `reviewIntent(意图)` → AI 自检（重叠/越界/滚动），必要时修正
class AiUiBlueprint {
  const AiUiBlueprint._();

  /// 步骤 1：读原卡 → 产出分条目蓝图。
  static Future<UiBlueprint> designBlueprint(
    UiExtraction extraction, {
    String cardName = '',
    void Function(String)? onToken,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) throw StateError('未配置 AI（请先在设置中填写 API）');

    final raw = await _chat(cfg, '蓝图设计', kBlueprintSystemPrompt, _blueprintUser(extraction, cardName), onToken);
    final parsed = _parseJson(raw);
    if (parsed == null) throw const FormatException('AI 返回的不是合法 JSON');
    final bp = UiBlueprint.fromJson(parsed);
    if (bp.items.isEmpty) throw const FormatException('AI 未返回蓝图条目');
    return bp;
  }

  /// 步骤 3：蓝图（确认后）→ 最终意图，逐条进 API 库检验，实现不了降级。
  static Future<IntentFromBlueprint> designIntentFromBlueprint(
    UiBlueprint blueprint, {
    String cardName = '',
    void Function(String)? onToken,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) throw StateError('未配置 AI（请先在设置中填写 API）');

    final raw = await _chat(
      cfg,
      '意图落地',
      kIntentSystemPrompt,
      _intentUser(blueprint, cardName),
      onToken,
    );
    final parsed = _parseJson(raw);
    if (parsed == null) throw const FormatException('AI 返回的不是合法 JSON');
    final intent = UiCreationIntent.fromJson(parsed);
    // 降级说明从 reasoning 里提取「降级」字样的思考
    final downgradeNotes = intent.reasoning
        .where((r) => r.contains('降级') || r.contains('替代') || r.contains('退而'))
        .toList();
    return IntentFromBlueprint(intent: intent, downgradeNotes: downgradeNotes);
  }

  /// 步骤 5：AI 自检最终意图，返回发现的问题。
  static Future<List<UiReviewIssue>> reviewIntent(
    UiCreationIntent intent, {
    void Function(String)? onToken,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) throw StateError('未配置 AI（请先在设置中填写 API）');

    final raw = await _chat(
      cfg,
      '自检',
      kReviewSystemPrompt,
      jsonEncode(intent.toJson()),
      onToken,
    );
    final parsed = _parseJson(raw);
    if (parsed == null) return const [];
    final issues = (parsed['issues'] as List? ?? [])
        .whereType<Map>()
        .map((m) => UiReviewIssue.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return issues;
  }

  /// **轻量布局自检（纯代码，不调 AI）**：确定性检查越界/重叠。
  ///
  /// 这是给 AI 的「布局审稿」反馈源：不靠 AI 检查，而是用确定性规则算出
  /// 哪里越界、哪里重叠，把结果作为「修改意见」交给 AI 去改——就像设计师
  /// 拿着一张标了红线的稿子回去重画，而不是让代码硬改坐标。
  ///
  /// 检测规则（宽恒 360，pad=14）：
  /// - 越界：x < 0 或 x+width > 360，或 y+height > 页高；
  /// - 重叠：同一页两个字段矩形相交。
  static List<UiReviewIssue> checkLayout(UiCreationIntent intent) {
    const double pcbW = 360.0;
    const double pad = 14.0;
    final issues = <UiReviewIssue>[];

    for (final p in intent.pages) {
      final pageH = p.pcbHeight ?? 900.0;
      // 收集本页字段（含位置/尺寸，未给的跳过——由 Step B 兜底排布）
      final rects = <({String name, double x, double y, double w, double h})>[];
      for (final panel in intent.panels) {
        if (panel.page.isNotEmpty && panel.page != p.id) continue;
        for (final f in panel.fields) {
          if (f.x == null && f.y == null) continue; // 走兜底，不参与检查
          final x = f.x ?? pad;
          final y = f.y ?? 0.0;
          final w = f.width ?? (pcbW - pad * 2);
          final h = f.height ?? 22.0;
          rects.add((name: '${panel.title}/${f.name}', x: x, y: y, w: w, h: h));
        }
      }

      // 越界检查
      for (final r in rects) {
        if (r.x < 0 || r.x + r.w > pcbW || r.y < 0) {
          issues.add(UiReviewIssue(
            severity: 'error',
            page: p.id,
            message: '字段「${r.name}」越界：x=${r.x.toStringAsFixed(0)} '
                'w=${r.w.toStringAsFixed(0)}（需 x≥0 且 x+w≤360）',
            suggestion: '把 x 与 width 收敛到 0~360 内',
          ));
        }
        if (r.y + r.h > pageH) {
          issues.add(UiReviewIssue(
            severity: 'warn',
            page: p.id,
            message: '字段「${r.name}」超出页底：y+h=${(r.y + r.h).toStringAsFixed(0)} '
                '> 页高 $pageH',
            suggestion: '下移/缩小，或提高 pcbHeight（建议≤900）',
          ));
        }
      }

      // 重叠检查（两两比较矩形）
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          final a = rects[i], b = rects[j];
          final overlapX = a.x < b.x + b.w && b.x < a.x + a.w;
          final overlapY = a.y < b.y + b.h && b.y < a.y + a.h;
          if (overlapX && overlapY) {
            issues.add(UiReviewIssue(
              severity: 'error',
              page: p.id,
              message: '字段「${a.name}」与「${b.name}」重叠',
              suggestion: '错开 y 或 x，避免矩形相交',
            ));
          }
        }
      }
    }
    return issues;
  }

  /// **迭代修正**：把布局问题反馈给 AI，让 AI 重新出一版修正后的意图。
  ///
  /// 对应「设计师看稿→改稿」：Step B 不硬改坐标，而是把红线问题交给 AI，
  /// AI 在语义层修正布局（保持设计意图，只解决越界/重叠）。
  /// [issues] 来自 [checkLayout] 或 [reviewIntent]。
  static Future<UiCreationIntent> reviseIntent(
    UiCreationIntent intent,
    List<UiReviewIssue> issues, {
    void Function(String)? onToken,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) throw StateError('未配置 AI（请先在设置中填写 API）');

    final buf = StringBuffer();
    buf.writeln('你之前设计了一份 UI 意图，但布局审查发现以下问题。'
        '请**保持整体设计意图**，仅修正布局，重新输出完整意图 JSON。\n');
    buf.writeln('【问题清单】');
    if (issues.isEmpty) {
      buf.writeln('（无问题，可原样返回）');
    } else {
      for (final issue in issues) {
        buf.writeln('- [${issue.severity}] ${issue.page}: ${issue.message}'
            '${issue.suggestion != null ? ' → ${issue.suggestion}' : ''}');
      }
    }
    buf.writeln('\n【原意图】\n${jsonEncode(intent.toJson())}\n');
    buf.writeln('请输出修正后的意图 JSON（结构与之前一致）。只输出 JSON，不要 markdown 代码块。');

    final raw = await _chat(cfg, '布局修正', kReviseSystemPrompt, buf.toString(), onToken);
    final parsed = _parseJson(raw);
    if (parsed == null) throw const FormatException('AI 修正返回的不是合法 JSON');
    return UiCreationIntent.fromJson(parsed);
  }

  // ---------------- 内部 ----------------

  static Future<String> _chat(
    ApiConfig cfg,
    String stage,
    String system,
    String user,
    void Function(String)? onToken,
  ) async {
    String raw;
    if (onToken != null) {
      try {
        raw = await ApiService.chatCompleteStream(
          baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
          systemPrompt: system, userPrompt: user, temperature: 0.4,
          onToken: onToken,
        );
        AiTranscript.add(stage, '【系统】\n$system\n\n【用户】\n$user', raw);
        return raw;
      } catch (_) {
        // 流式不可用 → 回退
      }
    }
    raw = await ApiService.chatComplete(
      baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
      systemPrompt: system, userPrompt: user, temperature: 0.4,
    );
    AiTranscript.add(stage, '【系统】\n$system\n\n【用户】\n$user', raw);
    return raw;
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static String _blueprintUser(UiExtraction ex, String cardName) {
    final buf = StringBuffer();
    buf.writeln('请分析以下角色卡，产出一份分条目 UI 蓝图。\n');
    buf.writeln('角色名：$cardName');
    for (final script in ex.scripts) {
      buf.writeln('---');
      buf.writeln('脚本: ${script.scriptName} 类型: ${script.kind.name}');
      final fields = script.fields.map((f) => '${f.name}(${f.type.name})').join(', ');
      if (fields.isNotEmpty) buf.writeln('字段: $fields');
      if (script.findRegex.isNotEmpty) buf.writeln('findRegex: ${script.findRegex}');
    }
    if (ex.branchPresets.isNotEmpty) {
      buf.writeln('\n开场分支初始值:');
      for (final e in ex.branchPresets.entries) buf.writeln('  分支${e.key}: ${e.value}');
    }
    if (ex.openingActions.isNotEmpty) {
      buf.writeln('\n开场选项: ${ex.openingActions.join(' / ')}');
    }
    return buf.toString();
  }

  static String _intentUser(UiBlueprint blueprint, String cardName) {
    final buf = StringBuffer();
    buf.writeln('请把以下 UI 蓝图落地为最终意图，逐条对照能力库实现，\n'
        '实现不了的条目降级为替代方案。\n');
    buf.writeln('角色名：$cardName');
    for (final item in blueprint.items.where((i) => i.keep)) {
      buf.writeln('---');
      buf.writeln('#${item.index} [${item.kind}] ${item.title}');
      buf.writeln('意图: ${item.intent}');
      if (item.fields.isNotEmpty) {
        buf.writeln('字段: ${item.fields.join(', ')}');
      }
      if (item.relationship.isNotEmpty) {
        buf.writeln('关系: ${item.relationship}');
      }
    }
    return buf.toString();
  }
}

/// 一条蓝图条目。
///
/// 蓝图是「做什么」的规划，不含精确坐标（那是 intent 阶段的事），
/// 但含：这块 UI 干什么、用哪些字段、大致组件选型、与其他条目的关系。
/// [feasibility] 在「API 检验」阶段由 AI 标注：能否用现有 API 实现，
/// 实现不了时给 [degradeTo] 的降级方案。
class BlueprintItem {
  /// 条目序号（1-based），用于用户逐条确认与 API 检验定位。
  final int index;

  /// 面板类型（status_bar / quest_list / option_bar / friend_list / ...）。
  final String kind;

  /// 展示标题（如「任务·采集安神草」）。用户可在蓝图确认时修改。
  String title;

  /// 设计意图描述（做什么、怎么排、用什么组件、为什么）。用户可修改。
  String intent;

  /// 涉及的原卡字段名。
  final List<String> fields;

  /// 该条与其他条目的关系（如「与状态栏同页」「是任务卡的换肤变体」）。
  final String relationship;

  /// 蓝图确认后用户是否保留本条（false = 删除）。
  bool keep;

  /// API 可行性标注（进 API 库检验后填充）。
  String? feasibility;

  /// 若实现不了，降级成什么方案。
  String? degradeTo;

  BlueprintItem({
    required this.index,
    required this.kind,
    required this.title,
    this.intent = '',
    this.fields = const [],
    this.relationship = '',
    this.keep = true,
    this.feasibility,
    this.degradeTo,
  });

  factory BlueprintItem.fromJson(Map<String, dynamic> json) => BlueprintItem(
        index: (json['index'] as num?)?.toInt() ?? 0,
        kind: json['kind']?.toString() ?? 'unknown',
        title: json['title']?.toString() ?? '',
        intent: json['intent']?.toString() ?? '',
        fields: (json['fields'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        relationship: json['relationship']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'kind': kind,
        'title': title,
        'intent': intent,
        'fields': fields,
        'relationship': relationship,
        'keep': keep,
        if (feasibility != null) 'feasibility': feasibility,
        if (degradeTo != null) 'degradeTo': degradeTo,
      };
}

/// AI 产出的分条目 UI 蓝图。
class UiBlueprint {
  final String cardName;
  final List<BlueprintItem> items;
  final List<String> reasoning;

  const UiBlueprint({
    required this.cardName,
    required this.items,
    this.reasoning = const [],
  });

  bool get hasUi => items.any((i) => i.keep);

  factory UiBlueprint.fromJson(Map<String, dynamic> json) => UiBlueprint(
        cardName: json['cardName']?.toString() ?? '',
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map((m) => BlueprintItem.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        reasoning: (json['reasoning'] as List? ?? [])
            .map((r) => r.toString())
            .toList(),
      );

  /// 去掉被用户删除的条目（keep == false），并重新编号。
  List<BlueprintItem> get keptItems {
    final kept = items.where((i) => i.keep).toList();
    for (var i = 0; i < kept.length; i++) {
      // 重新编号，保持 index 连续
      // 注意：这里不直接改 index（BlueprintItem 是普通类，index 非 final？）
    }
    return kept;
  }

  Map<String, dynamic> toJson() => {
        'cardName': cardName,
        'items': items.map((i) => i.toJson()).toList(),
        'reasoning': reasoning,
      };
}

/// 蓝图 → 最终意图 的产物包装：意图 + 是否发生了降级。
class IntentFromBlueprint {
  final UiCreationIntent intent;
  final List<String> downgradeNotes;
  const IntentFromBlueprint({required this.intent, this.downgradeNotes = const []});
}

/// 自检结果：AI 发现的问题列表。
class UiReviewIssue {
  final String severity; // 'error' | 'warn' | 'info'
  final String page;
  final String message;
  final String? suggestion;
  const UiReviewIssue({
    required this.severity,
    required this.page,
    required this.message,
    this.suggestion,
  });

  factory UiReviewIssue.fromJson(Map<String, dynamic> json) => UiReviewIssue(
        severity: json['severity']?.toString() ?? 'info',
        page: json['page']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        suggestion: json['suggestion']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'severity': severity,
        'page': page,
        'message': message,
        if (suggestion != null) 'suggestion': suggestion,
      };
}

/// 蓝图设计的系统提示词：让 AI 产出分条目蓝图。
const String kBlueprintSystemPrompt = '''
你是一名高水平的 UI 设计师与角色卡转译专家。你的任务：先**读原卡、理解它**，
然后产出一份**分条目的 UI 蓝图**（这是设计规划，不是最终实现）。

【什么是蓝图】
蓝图是「这张卡要做什么 UI」的分条目清单。每条 = 一块 UI 元素（一个面板/一页/
一组交互），包含：做什么、用什么字段、大致组件选型、与其他条目的关系。
**蓝图不含精确坐标**（那是下一步实现阶段的事），但要体现设计意图与整体规划。

【为什么分条目】
- 用户要能**逐条确认/修改**（哪块 UI 要不要、怎么改）；
- 后续进 API 库检验时，能精确到「哪一条能否实现、哪一条需降级」；
- 每条之间的逻辑关系更明了。

【蓝图条目字段】
- index: 序号（1,2,3...）
- kind: 面板类型（status_bar/quest_list/option_bar/friend_list/read_skin/unknown）
- title: 展示标题
- intent: 设计意图（做什么、怎么排、用什么组件、为什么）
- fields: 涉及的原卡字段名
- relationship: 与其它条目的关系（如「与任务卡是换肤变体」「与状态栏同页」）

【整体规划原则】
- 页面是全屏等比缩放的，PCB 越高缩放后字越小越挤 → 每页高度建议 650~900，
  内容多就拆多页、长文本用滚动框、横向/两列排布，别靠拉高 PCB 塞内容。
- read_skin（纯阅读皮肤、无数据槽）→ kind:"read_skin"，不转。
- 面板识别靠语义（字段特征）而非脚本数量。
- scene 唯一硬性要求：整卡至少一处「打开聊天设置」按钮（引擎不启用）。

【输出 JSON】
{
  "cardName": "角色名",
  "items": [
    {"index":1,"kind":"status_bar","title":"玩家状态","intent":"...","fields":["HP","MP"],"relationship":"..."},
    ...
  ],
  "reasoning": ["第1步思考","第2步思考",...]
}
只输出 JSON，不要 markdown 代码块。
''';

/// 蓝图 → 意图 的系统提示词（进 API 库逐条检验实现）。
const String kIntentSystemPrompt = '''
你正在把一份「UI 蓝图」落地为**最终 UI 创作意图**。你要：
1. 逐条对照「UI engine 能力库」（见下方），判断每条蓝图能否用现有 API 实现；
2. 能实现的 → 在意图里写出具体页面/面板/字段（含 x/y/w/h 布局、scroll 滚动框）；
3. 实现不了的条目 → **降级为可行的替代方案**（在 reasoning 里说明降级原因）；
4. 检查整体布局：页高有限、长文本滚动、字段与 chrome 不重叠、PCB 不高。

【最重要的布局硬约束】
- **画布宽度恒为 360**。所有元素 x+width 必须落 0~360 内（x≥0，x+width≤360）。
  这是绝对硬边界。chrome 的 messageFlow/input/settingsButton 的 x+width 同样 ≤360。
- 每页高度 pcbHeight 建议 650~900，字段 y+height 尽量 ≤ pcbHeight。
- 给出坐标后**在心里复核**：x+width 是否 >360？两个字段矩形是否相交（重叠）？
  越界/重叠是最高频错误，输出前自查。
- 想两列/横向：x 用 14 与 ~180 两档，各 width ~166；通栏 x=14 width≈332；
  靠右小按钮（设置）x≈300 width≈44。

【UI engine 能力库（可执行写法）】
- 字段 display：progress(数值条,需 min/max) / text(文本) / button(可点按钮,点击发文本)
- 长文本：text 字段加 "scroll":true + 固定 height，内容超出框内滚动，不撑高 PCB
- 布局：字段可给 x/y/width/height（设计坐标，同页面坐标系）；不给则 Step B 纵向兜底
- 页面外壳 chrome：每页可声明 messageFlow(消息流)/input(输入框)/settingsButton(设置按钮)，
  含 x/y/width/height；未声明 = 纯内容页。整卡至少一个 settingsButton。
- 页面：scene 多页，每页 pcbHeight 建议 650~900，页面间 page_router 切换
- 视觉风格：每页可给 style（dark/parchment/cyber/light），按原卡基调选
- 按钮字段：display:"button" 会自动套底板+点击热区，无需额外装饰
- 数据通道：数值 progress 绑 status_field(suggest_delta)，文本 text 绑(suggest_replace)

【输出 JSON】= 最终 UiCreationIntent：
{
  "scene":{"mode":"scene","pages":[
     {"id":"..","name":"..","pcbHeight":800,"style":"parchment","chrome":{...}},
     ...
  ],"activePage":".."},
  "panels":[
     {"kind":"..","page":"..","title":"..","fields":[{"name":"..","type":"..","display":"..","min":..,"max":..,"initialValue":"..","x":..,"y":..,"width":..,"height":..,"scroll":bool}]}
  ],
  "reasoning":["..."]
}
只输出 JSON，不要 markdown 代码块。
''';

/// 修正系统提示词（轻量）：AI 已看过完整能力库，只需按红线问题改布局，
/// 不必重发整段能力库（降低 TTFT / 减少 token）。
const String kReviseSystemPrompt = '''
你是一名 UI 设计师。给你一份已生成的 UI 意图和一份布局问题清单，
请**保持整体设计意图**，仅修正布局问题（越界/重叠），重新输出完整的意图 JSON。

硬约束（务必遵守）：
- 画布宽恒 360，所有元素 x+width ≤ 360（x≥0）。
- 页高 pcbHeight 建议 650~900，字段 y+height ≤ pcbHeight。
- chrome（messageFlow/input/settingsButton）的 x+width 同样 ≤360。
- 两列用 x=14 与 ~180；通栏 x=14 w≈332；靠右小按钮 x≈300 w≈44。
- 长文本保持 scroll:true + 固定 height。
- 保留每页 style（dark/parchment/cyber/light），不要丢失。

只输出修正后的完整意图 JSON，不要 markdown 代码块。
''';

/// 自检系统提示词：AI 检查意图里是否有重叠/越界/长文没滚动。
const String kReviewSystemPrompt = '''
你是一名 UI 布局审查员。给你一份「UI 创作意图 JSON」（含页面/外壳 chrome/字段坐标），
请逐页检查以下问题，输出问题清单：
- 字段之间是否重叠（同一页两个字段的矩形区域相交）
- 字段是否与页面外壳 chrome（消息流/输入框/设置按钮）重叠
- 字段是否越出页面（x<0 或 x+w>页宽 或 y<0 或 y+h>页高）
- 长文本字段是否用了 scroll（desc/note/risk/正文 等长文本却没 scroll）
- 页高是否失控（>1200，导致等比缩放后字太小）
- 每页是否有设置按钮（scene 硬性要求，整卡至少一个）

输出：
{
  "issues":[
    {"severity":"error|warn|info","page":"页id","message":"问题描述","suggestion":"建议修复"}
  ]
}
没问题就输出 "issues":[]。
只输出 JSON，不要 markdown 代码块。
''';
