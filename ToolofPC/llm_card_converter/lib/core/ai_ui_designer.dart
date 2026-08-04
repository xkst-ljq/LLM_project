import 'dart:convert';

import 'api_service.dart';
import 'app_settings.dart';
import 'regex_ui_extractor.dart';

/// Step A：AI 深度思考 —— 把提取结果设计成「UI 创作意图」。
///
/// 本类**只产出语义化意图**（`UiCreationIntent`），不直接生成 assembly JSON。
/// 真正生成 JSON 交给 `UiAssemblyBuilder.buildSceneFromIntent`（Step B 代码），
/// 避免 AI 直接写三层嵌套 JSON 的静默错误（见 `docs/AI_UI_CREATION_ENGINE.md`）。
///
/// ## 输入（纯净源数据）
/// 只给原卡的正则脚本/字段语义，**不给**任何已生成的实例或 assembly JSON，
/// 避免 AI 参考旧结构而失去创意或产出不匹配当前引擎的意图。
///
/// ## 输出（设计意图）
/// ```json
/// {
///   "scene": {"mode":"scene","pages":[{"id":"status","name":"状态"},...],"activePage":"status"},
///   "panels": [
///     {"kind":"status_bar","page":"status","title":"...","fields":[{"name":"HP","type":"number","display":"progress","min":0,"max":100},...]}
///   ],
///   "reasoning": ["...AI 思考过程..."]
/// }
/// ```
class AiUiDesigner {
  const AiUiDesigner._();

  /// 对提取结果做 AI 深度创作设计。失败时抛异常（由调用方回退到确定性模板）。
  static Future<UiCreationIntent> design(UiExtraction extraction) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    final raw = await ApiService.chatComplete(
      baseUrl: cfg.baseUrl,
      apiKey: cfg.apiKey,
      model: cfg.model,
      systemPrompt: _systemPrompt,
      userPrompt: _buildUserPrompt(extraction),
      temperature: 0.4, // 创作可稍高，但仍是结构化输出
    );

    final parsed = _parseJson(raw);
    if (parsed == null) {
      throw const FormatException('AI 返回的不是合法 JSON');
    }
    return UiCreationIntent.fromJson(parsed);
  }

  // ---------------- Prompt ----------------

  static const String _systemPrompt = '''
你是一名高水平的 UI 设计师与角色卡转译专家。你的任务：分析酒馆(SillyTavern)角色卡的正则脚本，识别出它们描述的不同 UI 面板，并产出一份「UI 创作意图」。

【重要原则】
1. 你只输出「意图」——用什么面板、什么字段、放哪页、大概怎么排、用什么组件。**不要输出具体的 JSON 装配**（坐标/颜色/枚举等由转译代码负责）。
2. 识别面板靠「语义」而非脚本数量：同样的脚本名/字段可能是换肤(皮肤)，也可能是不同功能。只有字段结构不同的才算不同面板。
3. 尽可能还原原卡，在此之上优化；原卡没有的不要硬造。
4. 数据值应绑定数据通道实时更新（数值用 progress，文本用 text）。
5. 思考过程逐条写入 reasoning，让用户明白你如何判断这张卡。

【面板类型 kind】（字段特征判断）
- status_bar：状态栏（HP/MP/XP/STR/AGI 等数值 + Name/Class/Weapon 等文本）
- quest_list：任务/委托列表（quest/type/desc/reward/location/time 等）
- option_bar：玩家选项栏（option1_text/option2_text/input_prompt 等）
- friend_list：好友/列表（name1/level1/equip1/status1/loc1 等）
- read_skin：纯阅读皮肤（无数据槽）→ 不转，跳过
- unknown：无法判断 → 保守不转

【UI engine 可用能力】
- 组件：surface/text/progress/button/input/select/switch/slider/indicator/image/line
- progress：min/max/current，适合数值条（如 HP/MP/XP）
- text：可绑数据通道，textAlign/overflow(ellipsis·scroll)/richText
- button：sendsMessage（点击发消息）
- 数据通道：status_field（绑到置顶状态栏，LLM 可读写，数值 suggest_delta / 文本 suggest_replace）
- 页面：scene 可多页，page_router 切换；overlay 叠加层

【输出 JSON 结构】（必须完整，字段合法）
{
  "scene": {
    "mode": "scene",
    "pages": [{"id":"...","name":"..."}, ...],   // 2~5 页
    "activePage": "第一个页id"
  },
  "panels": [
    {
      "kind": "status_bar",
      "page": "页id",
      "title": "面板标题",
      "fields": [
        {"name":"HP","type":"number","display":"progress","min":0,"max":100},
        {"name":"武器","type":"text","display":"text"}
      ]
    }
  ],
  "reasoning": ["第1步思考", "第2步思考", ...]
}

【display 允许值】progress(数值条) / text(文本) / button(按钮)
只输出 JSON，不要 markdown 代码块。
''';

  static String _buildUserPrompt(UiExtraction extraction) {
    final buf = StringBuffer();
    buf.writeln('请分析以下角色卡的正则脚本，设计 UI 创作意图。\n');
    buf.writeln('可用的脚本如下：');
    for (final script in extraction.scripts) {
      buf.writeln('---');
      buf.writeln('脚本名: ${script.scriptName}');
      buf.writeln('类型: ${script.kind.name}  替换长度: ${script.replaceLength}');
      final fields = script.fields
          .map((f) => '${f.name}(${f.type.name})')
          .join(', ');
      if (fields.isNotEmpty) buf.writeln('字段: $fields');
      if (script.sections.isNotEmpty) {
        buf.writeln('分区注释: ${script.sections.join(' / ')}');
      }
      buf.writeln('视觉线索: ${script.visuals.toJson()}');
    }
    if (extraction.openingActions.isNotEmpty) {
      buf.writeln('\n开场选项: ${extraction.openingActions.join(' / ')}');
    }
    return buf.toString();
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final body = t.substring(start, end + 1);
    try {
      final v = jsonDecode(body);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }
}

/// AI 产出的 UI 创作意图（语义层）。
class UiCreationIntent {
  final String mode;
  final List<ScenePage> pages;
  final String activePage;
  final List<UiPanel> panels;
  final List<String> reasoning;

  const UiCreationIntent({
    required this.mode,
    required this.pages,
    required this.activePage,
    required this.panels,
    this.reasoning = const [],
  });

  factory UiCreationIntent.fromJson(Map<String, dynamic> json) {
    final scene = Map<String, dynamic>.from(json['scene'] as Map? ?? {});
    final pages = (scene['pages'] as List? ?? [])
        .whereType<Map>()
        .map((p) => ScenePage.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    if (pages.isEmpty) {
      throw const FormatException('AI 未返回有效页面');
    }
    final panels = (json['panels'] as List? ?? [])
        .whereType<Map>()
        .map((p) => UiPanel.fromJson(Map<String, dynamic>.from(p)))
        .where((p) => p.kind != 'read_skin' && p.kind != 'unknown')
        .toList();
    final reasoning = (json['reasoning'] as List? ?? [])
        .map((r) => r.toString())
        .toList();
    return UiCreationIntent(
      mode: scene['mode']?.toString() ?? 'scene',
      pages: pages,
      activePage: scene['activePage']?.toString() ?? pages.first.id,
      panels: panels,
      reasoning: reasoning,
    );
  }

  bool get hasUi => panels.isNotEmpty;
}

class ScenePage {
  final String id;
  final String name;
  const ScenePage({required this.id, required this.name});
  factory ScenePage.fromJson(Map<String, dynamic> json) => ScenePage(
        id: json['id']?.toString() ?? 'page_${json['name'] ?? DateTime.now().millisecondsSinceEpoch}',
        name: json['name']?.toString() ?? '页面',
      );
}

class UiPanel {
  final String kind;
  final String page;
  final String title;
  final List<UiFieldIntent> fields;
  const UiPanel({
    required this.kind,
    required this.page,
    required this.title,
    required this.fields,
  });
  factory UiPanel.fromJson(Map<String, dynamic> json) => UiPanel(
        kind: json['kind']?.toString() ?? 'unknown',
        page: json['page']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        fields: (json['fields'] as List? ?? [])
            .whereType<Map>()
            .map((f) => UiFieldIntent.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
      );
}

class UiFieldIntent {
  final String name;
  final String type; // number | text
  final String display; // progress | text | button
  final double? min;
  final double? max;
  const UiFieldIntent({
    required this.name,
    required this.type,
    required this.display,
    this.min,
    this.max,
  });
  factory UiFieldIntent.fromJson(Map<String, dynamic> json) {
    final display = json['display']?.toString() ?? 'text';
    return UiFieldIntent(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      display: const {'progress', 'text', 'button'}.contains(display)
          ? display
          : 'text',
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
    );
  }
}
