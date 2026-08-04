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
6. 充分利用 UI engine 的完整能力（见下方【UI engine 完整能力库】），做出有特色、有交互的高质量 UI，而不是简单的纵向列表。

【面板类型 kind】（字段特征判断）
- status_bar：状态栏（HP/MP/XP/STR/AGI 等数值 + Name/Class/Weapon 等文本）
- quest_list：任务/委托列表（quest/type/desc/reward/location/time 等）
- option_bar：玩家选项栏（option1_text/option2_text/input_prompt 等）
- friend_list：好友/列表（name1/level1/equip1/status1/loc1 等）
- read_skin：纯阅读皮肤（无数据槽）→ 不转，跳过
- unknown：无法判断 → 保守不转

【UI engine 完整能力库】
## 页面模式（mode）
- scene：场景 UI，全屏接管聊天页，可承载多页、多套面板
- opening：开场白弹窗，开场时全屏，玩家确认后进入
- extra_companion：伴生 UI，内嵌在最新 AI 气泡里（≤212px 宽）
- extra_sticky：常驻 UI，悬浮小窗，可折叠

## 组件原语（21 种）
- surface / base_box：底板 / 面板容器
- text：文本（可绑数据通道 / 富文本 richText / 滚动 overflow:scroll）
- progress：进度条（min/max/current，progressShape: bar·ring·capsule）
- button：点击热区（sendsMessage 点击发消息 / keyAction 关键职责）
- input：文本输入框（回车提交 committedValue）
- select：下拉选择（options[{label,value}] / current）
- switch：开关（value bool）
- slider：滑块（min/max/current/step）
- indicator：指示点 / 状态灯
- image：图片（本地 / 内联 / 网络）
- line：分割线
- linker：逻辑连线（数据流 / 控制流）
- page_router：页面路由（切页 / 打开叠加层）
- math_node：计算节点
- timer：定时器
- message_flow：内嵌消息流（可解析 AI 消息里的 onclick 动态选项）
- primitive_art / surface_art / light_effect：装饰 / 光效

## 联动器方案（linker scheme，让 UI 有交互）
- button_to_page_route：按钮 → 切页 / 打开叠加层
- click_to_surface_press：按钮 → 表面按压动画
- click_to_switch_toggle / _set_true / _set_false：按钮 → 开关
- click_to_input_clear / click_to_slider_reset：重置输入/滑块
- input_commit_to_text / input_live_to_text：输入 → 文本
- input_to_progress / input_to_slider：输入 → 进度/滑块
- input_nonempty_to_button_enable：输入非空才可点按钮
- bool_to_visible / boolean_to_enabled：条件显隐 / 启用
- select_to_text / select_value_to_switch：下拉 → 文本/开关
- slider_to_progress / slider_to_text：滑块 → 进度/文本
- progress_to_text / progress_threshold_to_switch：进度 → 文本/阈值控制
- event_to_animation / event_to_indicator：事件 → 动画 / 指示
- timer_tick_to_progress_increment / _decrement：定时器 → 进度增减
- text_match_to_switch：文本匹配 → 开关

## 动画系统（__anim）
- press：按压凹陷（150ms）
- ripple：水波折射扩散（300ms）
- flash：短暂高亮（300ms）
- number_pop：数值跳动（260ms）
- glow_pulse：发光脉冲（600ms）
- particle_burst：粒子迸发（700ms）
- 曲线：easeInOut / easeOut / easeIn / linear / bounceOut / elasticOut

## 数据通道（Data Channel）
- 组件绑定 status_field，LLM 可读写（实时更新数值）
- 数值字段：suggest_delta（增量更新，引擎 clamp 到 min/max）
- 文本字段：suggest_replace（整值替换）
- 这是「数据值实时更新」的实现机制，务必让数值/文本字段都绑上

## 富文本
- text 组件 richText: true → 渲染 HTML/Markdown
- overflow: scroll → 长文滚动

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
        {"name":"HP","type":"number","display":"progress","min":0,"max":100,"initialValue":"100"},
        {"name":"武器","type":"text","display":"text","initialValue":"木剑"}
      ]
    }
  ],
  "reasoning": ["第1步思考", "第2步思考", ...]
}

【display 允许值】progress(数值条) / text(文本) / button(按钮)
【initialValue】从原卡脚本/开场白里提取该字段的当前初始值（数值取当前值，如 HP 100/100 的 100；文本取原文）。没有就留空字符串。
【设计建议】
- 数值字段（HP/MP/XP/STR 等）用 progress 并给出合理 min/max
- 文本字段（Name/Weapon/称号 等）用 text
- 有明确交互意图的（选项/按钮/输入）用 button/input，并考虑用联动器实现交互
- 多面板时用多页 + page_router 切换，避免一页塞满
- 尽量还原原卡视觉与信息，在此之上用动画/联动器增强体验
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
  final String initialValue; // 从原卡提取的初始值（如 HP 100/100 的当前值）
  const UiFieldIntent({
    required this.name,
    required this.type,
    required this.display,
    this.min,
    this.max,
    this.initialValue = '',
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
    );
  }
}
