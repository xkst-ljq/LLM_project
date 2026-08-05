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
  ///
  /// [barInitialValues] 是从开场白里解析出的字段初始值（`{Xxx|key:val|...}` 与
  /// `{key:val|...}` 两种格式），喂给 AI 让它把 `initialValue` 填上真实值，
  /// 而不是因为「原卡模板是 $n 占位符」就全部留空。
  ///
  /// [greetingsText] 是原卡开场白（`first_mes` + `alternate_greetings`）的
  /// **完整原文**。让 AI 直接读连贯的原始结构化标记（`{PlayerStatus|HP:100|...}`），
  /// 而非只读被提取/截断后的摘要——避免自动化正则把连贯信息拆散或删掉，
  /// 导致 AI 读不到本应存在的内容。
  ///
  /// [onToken] 若提供，则走**流式**生成：边生成边回调增量文本，让 UI 能
  /// 实时展示「AI 正在思考」。流式端点不可用时自动回退到非流式（不中断）。
  static Future<UiCreationIntent> design(
    UiExtraction extraction, {
    Map<String, String> barInitialValues = const {},
    List<String> greetingsText = const [],
    void Function(String token)? onToken,
  }) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      throw StateError('未配置 AI（请先在设置中填写 API）');
    }

    final system = _systemPrompt;
    final user = _buildUserPrompt(extraction, barInitialValues, greetingsText);

    String raw;
    if (onToken != null) {
      try {
        raw = await ApiService.chatCompleteStream(
          baseUrl: cfg.baseUrl,
          apiKey: cfg.apiKey,
          model: cfg.model,
          systemPrompt: system,
          userPrompt: user,
          temperature: 0.4,
          onToken: onToken,
        );
      } catch (_) {
        // 端点不支持流式 → 回退非流式，保证不中断。
        raw = await ApiService.chatComplete(
          baseUrl: cfg.baseUrl,
          apiKey: cfg.apiKey,
          model: cfg.model,
          systemPrompt: system,
          userPrompt: user,
          temperature: 0.4,
        );
      }
    } else {
      raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: system,
        userPrompt: user,
        temperature: 0.4, // 创作可稍高，但仍是结构化输出
      );
    }

    final parsed = _parseJson(raw);
    if (parsed == null) {
      throw const FormatException('AI 返回的不是合法 JSON');
    }
    return UiCreationIntent.fromJson(parsed);
  }

  // ---------------- Prompt ----------------

  static const String _systemPrompt = '''
你是一名高水平的 UI 设计师与角色卡转译专家。你的任务：分析酒馆(SillyTavern)角色卡的正则脚本，识别出它们描述的不同 UI 面板，并产出一份「UI 创作意图」。**你只输出意图 JSON，装配由转译代码完成。**

【最重要的一条布局铁律】
页面是「全屏等比缩放」渲染的：整个设计画布（PCB）会被等比缩放到手机屏幕。
- **不要靠无限拉高 PCB 来塞内容**——PCB 越高，缩放后整页字越小、越挤。
- 一页的高度建议控制在 **650~900** 之间（接近手机竖屏比例）。内容多时：
  - 拆成多页（用 page_router 切换）；
  - 长文本用**滚动框**（固定高度，见下），而不是让文本撑高页面；
  - 用横向排布 / 两列，而不是每个字段一行。
- 这就是「PCB 太长 / 重叠 / 简陋」三个问题的共同解：**页高有限 + 紧凑布局 + 长文滚动**。

【面板类型 kind】（字段特征判断）
- status_bar：状态栏（HP/MP/XP/STR/AGI 等数值 + Name/Class/Weapon 等文本）
- quest_list：任务/委托列表（quest/type/desc/reward/location/time 等）
- option_bar：玩家选项栏（option1_text/option2_text/input_prompt 等）
- friend_list：好友/列表（name1/level1/equip1/status1/loc1 等）
- read_skin：纯阅读皮肤（无数据槽）→ 不转，跳过
- unknown：无法判断 → 保守不转

【UI engine 完整能力库：每个 API 能干什么 + 参数 + 在意图里怎么写】

## 页面（pages）
scene 是「全屏场景」，含多个平级页，页面间用 page_router 切换。
意图里每页可给：`id`(页id)、`name`(显示名)、`pcbHeight`(页设计高度，建议 650~900)。
示例：{"id":"lobby","name":"公会大厅","pcbHeight":800}

## 字段 display（组件选型）
- `progress`：数值进度条。参数：`type:"number"` + `min`(下限) + `max`(上限)。适合 HP/MP/XP/属性 等会增减的数值。
- `text`：文本。参数：`type:"text"`。适合名字/职业/描述/备注等。
- `button`：可点击按钮。参数：`type:"text"`（点击发送该文本）。适合选项、行动。

## 滚动长文本（解决 PCB 变长的关键）
`text` 字段可加 `"scroll":true` 声明为「固定高度滚动框」：
- 用法：`{"name":"desc","type":"text","display":"text","scroll":true,"height":60}`
- 效果：该字段固定 height 高度，内容超出就在框内滚动显示，**不撑高 PCB**。
- 长描述/备注/正文/风险/奖励说明 等一律用 scroll，不要让它占 11 行。

## 布局（position/size）
每个字段可给 `x` / `y` / `width` / `height`（设计坐标，与页面同坐标系）：
- 给了就按指定位置放置（Step B 会 clamp 进 PCB 并校验不重叠）。
- 不给就 Step B 自动纵向排布（兜底）。
- 想横向排布/两列：给不同的 x + 合适 width 即可。
- 用字段的 y 控间距，x + width 控横向布局。

## 页面外壳（chrome）——你决定每页的交互外壳
每页可用 `chrome` 声明三类外壳组件（不放则整页纯内容）：
- `messageFlow`: 消息流，显示对话历史。给 `x/y/width/height`。
- `input`: 玩家输入框（发送行动）。给 `x/y/width/height`。
- `settingsButton`: 打开聊天设置的按钮。给 `x/y/width/height`。
**重要**：这些不是强制，由你按本页该不该有来设计。scene 唯一硬性要求是
**整卡至少一个 settingsButton**（否则引擎不启用），你只需在某页声明即可。
示例：
"chrome": {
  "messageFlow": {"x":14,"y":30,"width":332,"height":200},
  "input": {"x":14,"y":820,"width":284,"height":40},
  "settingsButton": {"x":306,"y":820,"width":40,"height":40}
}
若某页不需要消息流/输入框，就不写对应键（纯内容页完全合法）。
给 chrome 留出空间：字段布局不要与 chrome 区域重叠。

## 数据通道（让 LLM 能读写、数值实时更新）
- 数值字段（progress）：绑定 status_field，写策略 suggest_delta（LLM 只给增量，引擎 clamp 到 min/max）。**所有数值 progress 都应绑定**。
- 文本字段（text）：绑定 status_field，写策略 suggest_replace（整值替换）。**所有会变化的文本都应绑定**。
- 意图里你只要声明 display 与 type，绑定由代码自动完成——**不用你写通道 JSON**，但请明确区分数值(text 用 progress)与文本。

## 交互组件（在意图里如何表达）
- `button`：display:"button"，type:"text"，initialValue 填点击要发送的文本。适合任务选择、行动选项。
- `input`：用 `option_bar` 面板的 input_prompt 字段表达（type:"text"，display:"text"，initialValue 填占位提示）。
- 交互联动（按钮→切页、输入→文本、开关控制显隐等）由代码按面板语义自动生成，你只需把字段语义设计清楚。

## 动画（可选增强）
进度条数值变化可用 `number_pop`（数值跳动）；按钮可用 `press`（按压）。意图里无需你写动画配置，标注「此字段建议动画」即可，代码会补。

【输出 JSON 结构】（字段合法，字段值来自原卡/开场白）
{
  "scene": {
    "mode": "scene",
    "pages": [
      {"id":"lobby","name":"公会大厅","pcbHeight":800,"chrome":{
        "messageFlow":{"x":14,"y":30,"width":332,"height":200},
        "input":{"x":14,"y":820,"width":284,"height":40},
        "settingsButton":{"x":306,"y":820,"width":40,"height":40}
      }},
      {"id":"status","name":"冒险者档案","pcbHeight":700,"chrome":{}}
    ],
    "activePage": "lobby"
  },
  "panels": [
    {
      "kind": "status_bar",
      "page": "lobby",
      "title": "冒险者状态",
      "fields": [
        {"name":"HP","type":"number","display":"progress","min":0,"max":100,"initialValue":"100","x":14,"y":30,"width":160,"height":14},
        {"name":"武器","type":"text","display":"text","initialValue":"木剑","x":14,"y":50,"width":160,"height":22}
      ]
    },
    {
      "kind":"quest_list","page":"lobby","title":"任务·采集安神草",
      "fields":[
        {"name":"quest","type":"text","display":"text","initialValue":"采集安神草","scroll":true,"height":26},
        {"name":"desc","type":"text","display":"text","initialValue":"为药剂师采集二十株安神草。","scroll":true,"height":60}
      ]
    }
  ],
  "reasoning": ["第1步思考", "第2步思考", ...]
}

【display 允许值】progress / text / button
【scroll】text 字段长内容时给 true + 固定 height，避免撑高 PCB。
【pcbHeight】每页设计高度，建议 650~900，勿超 1200。
【设计清单】
- 长文本(desc/note/risk/reward/正文)一律 scroll，绝不占多行
- 一页字段数多时用两列/紧凑排布或拆多页，别让单页超 900
- 每页高度有限 → 拆页、滚动、横排，宁可信息分页也不要一个超长 PCB
- 数值用 progress 绑数据通道，文本用 text 绑数据通道
只输出 JSON，不要 markdown 代码块。
''';

  static String _buildUserPrompt(
    UiExtraction extraction, [
    Map<String, String> barInitialValues = const {},
    List<String> greetingsText = const [],
  ]) {
    final buf = StringBuffer();
    buf.writeln('请分析以下角色卡的正则脚本，设计 UI 创作意图。\n');

    // 把从开场白解析出的字段初始值喂给 AI：这些就是各字段此刻的真实值，
    // 必须填进 initialValue，而不是留空。字段名可能和脚本里的不同（大小写、
    // 中英），按语义对应即可。
    if (barInitialValues.isNotEmpty) {
      buf.writeln('【开场白中的字段初始值】（务必填入对应字段的 initialValue）：');
      final keys = barInitialValues.keys.toList()..sort();
      buf.writeln(keys.map((k) => '$k=$barInitialValues[$k]').join(' | '));
      buf.writeln();
    }

    // 原卡开场白完整原文：让 AI 直接读连贯的结构化标记，而不是只读被
    // 提取/截断的摘要。这是「字段值从哪来」的第一手来源。
    if (greetingsText.isNotEmpty) {
      buf.writeln('【原卡开场白原文】（含结构化标记，字段初始值第一手来源，'
          '请据此填充 initialValue）：');
      for (final g in greetingsText) {
        final t = g.trim();
        if (t.isEmpty) continue;
        buf.writeln('--- 开场白 ---');
        buf.writeln(t.length > 4000 ? t.substring(0, 4000) : t);
      }
      buf.writeln();
    }

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
      // 原始 findRegex：字段捕获结构，让 AI 看到字段间的连贯关系
      if (script.findRegex.isNotEmpty) {
        buf.writeln('原始匹配正则(findRegex): ${script.findRegex}');
      }
      // 给 AI 原始 CSS，让它能还原原卡视觉形态（配色/进度条/布局）
      if (script.rawReplace.isNotEmpty) {
        final css = script.rawReplace.length > 3000
            ? script.rawReplace.substring(0, 3000)
            : script.rawReplace;
        buf.writeln('原始替换模板(CSS/HTML，截断): $css');
      }
    }

    // 各开场分支的初始状态：让 AI 能据此填写 initialValue
    if (extraction.branchPresets.isNotEmpty) {
      buf.writeln('\n各开场分支的初始状态（字段初始值来源）：');
      for (final entry in extraction.branchPresets.entries) {
        buf.writeln('分支${entry.key}: ${entry.value}');
      }
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

  /// 序列化为 JSON（供 AI 自检阶段把意图喂回 AI 检查）。
  Map<String, dynamic> toJson() => {
        'scene': {
          'mode': mode,
          'pages': pages
              .map((p) => {
                    'id': p.id,
                    'name': p.name,
                    if (p.pcbHeight != null) 'pcbHeight': p.pcbHeight,
                    if (p.pcbWidth != null) 'pcbWidth': p.pcbWidth,
                    'chrome': p.chrome.toJson(),
                  })
              .toList(),
          'activePage': activePage,
        },
        'panels': panels.map((p) => p.toJson()).toList(),
        'reasoning': reasoning,
      };
}

class ScenePage {
  final String id;
  final String name;

  /// 该页设计高度（可选）。AI 指定后，页面按此高度设计，内容超高时
  /// 用滚动/紧凑布局容纳，而不是无限拉高 PCB。缺省由 Step B 推算。
  final double? pcbHeight;

  /// 该页设计宽度（可选，默认 360）。
  final double? pcbWidth;

  /// 页面外壳组件（消息流/输入框/设置按钮）声明。
  ///
  /// AI 决定本页要不要这些「外壳」元素、放哪、多大。
  /// 不声明 = 本页不放（纯内容页）。设置按钮是引擎唯一硬性要求，
  /// 若 AI 整卡都没声明，Step B 会兜底补一个不碍事的位置并提示。
  final SceneChrome chrome;

  const ScenePage({
    required this.id,
    required this.name,
    this.pcbHeight,
    this.pcbWidth,
    this.chrome = const SceneChrome(),
  });

  factory ScenePage.fromJson(Map<String, dynamic> json) => ScenePage(
        id: json['id']?.toString() ?? 'page_${json['name'] ?? DateTime.now().millisecondsSinceEpoch}',
        name: json['name']?.toString() ?? '页面',
        pcbHeight: (json['pcbHeight'] as num?)?.toDouble(),
        pcbWidth: (json['pcbWidth'] as num?)?.toDouble(),
        chrome: SceneChrome.fromJson(json['chrome']),
      );
}

/// 单页的「外壳」组件声明：消息流 / 输入框 / 设置按钮。
///
/// 这些都是 scene 的交互外壳。Step B 不再擅自硬塞——**AI 声明什么就放什么**，
/// 没声明就不放，把设计感交还给 AI。唯一硬性要求是设置按钮（引擎不启用
/// 的条件），AI 漏了时 Step B 兜底。
class SceneChrome {
  /// 消息流：显示对话。null = 本页不放。
  final MessageFlowIntent? messageFlow;

  /// 玩家输入框（发送行动）。null = 本页不放。
  final InputBarIntent? input;

  /// 打开聊天设置的按钮。null = 本页不放（整卡需至少一页有，否则 Step B 兜底）。
  final SettingsButtonIntent? settingsButton;

  const SceneChrome({
    this.messageFlow,
    this.input,
    this.settingsButton,
  });

  factory SceneChrome.fromJson(dynamic json) {
    if (json is! Map) return const SceneChrome();
    final m = Map<String, dynamic>.from(json);
    return SceneChrome(
      messageFlow: MessageFlowIntent.fromJson(m['messageFlow']),
      input: InputBarIntent.fromJson(m['input']),
      settingsButton: SettingsButtonIntent.fromJson(m['settingsButton']),
    );
  }

  bool get hasAny =>
      messageFlow != null || input != null || settingsButton != null;

  Map<String, dynamic> toJson() => {
        if (messageFlow != null)
          'messageFlow': {
            if (messageFlow!.x != null) 'x': messageFlow!.x,
            if (messageFlow!.y != null) 'y': messageFlow!.y,
            if (messageFlow!.width != null) 'width': messageFlow!.width,
            if (messageFlow!.height != null) 'height': messageFlow!.height,
          },
        if (input != null)
          'input': {
            if (input!.x != null) 'x': input!.x,
            if (input!.y != null) 'y': input!.y,
            if (input!.width != null) 'width': input!.width,
            if (input!.height != null) 'height': input!.height,
          },
        if (settingsButton != null)
          'settingsButton': {
            if (settingsButton!.x != null) 'x': settingsButton!.x,
            if (settingsButton!.y != null) 'y': settingsButton!.y,
            if (settingsButton!.width != null) 'width': settingsButton!.width,
            if (settingsButton!.height != null) 'height': settingsButton!.height,
          },
      };
}

/// 消息流声明。
class MessageFlowIntent {
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  const MessageFlowIntent({this.x, this.y, this.width, this.height});

  factory MessageFlowIntent.fromJson(dynamic json) {
    if (json is! Map) return const MessageFlowIntent();
    final m = Map<String, dynamic>.from(json);
    return MessageFlowIntent(
      x: (m['x'] as num?)?.toDouble(),
      y: (m['y'] as num?)?.toDouble(),
      width: (m['width'] as num?)?.toDouble(),
      height: (m['height'] as num?)?.toDouble(),
    );
  }
}

/// 输入框声明。
class InputBarIntent {
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  const InputBarIntent({this.x, this.y, this.width, this.height});

  factory InputBarIntent.fromJson(dynamic json) {
    if (json is! Map) return const InputBarIntent();
    final m = Map<String, dynamic>.from(json);
    return InputBarIntent(
      x: (m['x'] as num?)?.toDouble(),
      y: (m['y'] as num?)?.toDouble(),
      width: (m['width'] as num?)?.toDouble(),
      height: (m['height'] as num?)?.toDouble(),
    );
  }
}

/// 设置按钮声明。
class SettingsButtonIntent {
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  const SettingsButtonIntent({this.x, this.y, this.width, this.height});

  factory SettingsButtonIntent.fromJson(dynamic json) {
    if (json is! Map) return const SettingsButtonIntent();
    final m = Map<String, dynamic>.from(json);
    return SettingsButtonIntent(
      x: (m['x'] as num?)?.toDouble(),
      y: (m['y'] as num?)?.toDouble(),
      width: (m['width'] as num?)?.toDouble(),
      height: (m['height'] as num?)?.toDouble(),
    );
  }
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

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'page': page,
        'title': title,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

class UiFieldIntent {
  final String name;
  final String type; // number | text
  final String display; // progress | text | button
  final double? min;
  final double? max;
  final String initialValue; // 从原卡提取的初始值（如 HP 100/100 的当前值）

  /// 布局：在页面内的位置与尺寸（设计坐标，与 pcb 同一坐标系）。
  /// 可选。给定了 Step B 就按此放置（校验+clamp）；没给则 Step B 兜底纵向排布。
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  /// 长文本滚动：true 时该字段用固定高度 + overflow:scroll 显示，
  /// 内容再多也不撑高 PCB（解决「长文本导致 PCB 失控变长」）。
  final bool scroll;

  const UiFieldIntent({
    required this.name,
    required this.type,
    required this.display,
    this.min,
    this.max,
    this.initialValue = '',
    this.x,
    this.y,
    this.width,
    this.height,
    this.scroll = false,
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
      initialValue: json['initialValue']?.toString() ?? '',
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      scroll: json['scroll'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'display': display,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        'initialValue': initialValue,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (scroll) 'scroll': true,
      };
}
