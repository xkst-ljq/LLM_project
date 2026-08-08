import '../ui_engine_api/ui_engine_api_dictionary.dart';

/// UIEngine 知识库（给 AI 的压缩版能力说明）。
///
/// 知识来源不再是手写散文，而是 [UiEngineApiDictionary] 这份组件/API 字典。
/// 后续新增组件或属性时优先改字典，再由这里生成 prompt。
class UiEngineKnowledgeService {
  const UiEngineKnowledgeService._();

  static const String knowledgeVersion = 'ui_engine_api_dictionary_v2026-08-07.7';

  static String compactPrompt() => '''
# LLM Project UIEngine capabilities

Knowledge version: $knowledgeVersion

You are NOT allowed to output internal assembly JSON. You must output high-level UiDesignPlan data only. Dart code will compile it.

You may output either:
1. A single UiDesignPlan object, or
2. One top-level JSON object with "assemblies": [UiDesignPlan, UiDesignPlan, ...].

Use multiple assemblies when the original card has distinct lifecycle UI, e.g. opening identity selection + scene runtime terminal.

${UiEngineApiDictionary.compactReferenceForTranslator()}

# Confirmed runtime facts (do not present these as unknown)
- message_flow is a normal UI module rendered in a SizedBox; it can be visually placed over/inside surfaces by absolute layout. It is not restricted to a top-level-only slot.
- extra_companion has a hard width cap of 212px, but height can grow within PCB limits and the surrounding chat list scrolls. It can use pages/tabs/gestures, but dense layouts are discouraged because the width is narrow.
- line color comes from module.color; thickness/axis/solid/dashed/dotted/curve/double are supported. Use line for borders, dividers, ornaments, and terminal/codex styling.
- overlay pages open via page_router route action open_overlay and can contain their own text/input/buttons/scroll areas. They are suitable for dossiers, quest details, friend lists, and expanded status panels.
- status_bar_fields are LLM Project native state fields. They are not an automatic SillyTavern parser: the translator must map ST keys into fields/sourceKey/dataChannel. Once mapped, the app prompt/update mechanism lets the LLM read and update them.
- Tabs are a visual pattern built from surface/text/button plus page_router/linker. page_router is the mechanism; there is no conflict between tabs and overlay buttons.
- Multiple assemblies can coexist when lifecycles differ: opening + scene is valid. scene suppresses native chat/extra_companion; sticky remains a tool layer; opening is shown until dismissed.
- In scene mode, notes that "message_flow should be used" are not enough. To actually get message_flow, declare a base layout page whose role is story/message/narrative/content/log. Put current DQ choices and free input on that same page so they stay physically close to the story.
- Logic components are optional. Use math_node/timer/indicator/linker only when source evidence or confirmed author intent requires native computation/condition/automation. Pure visual upgrades may use line/surface/animation without changing gameplay.
- UIEngine runtime supports ElementAnimation / event_to_animation, but the current high-level UiDesignPlan compiler only emits automatic button press feedback and page transitions. Do not invent an animations[] schema; CSS loop/hover animations should be recorded as unsupported or as future enhancement unless they can be expressed by existing fields/notes without promising compiler output.

# Layout fidelity and mobile adaptation policy
- First reconstruct the original rendered UI structure: section order, grouping, columns/grid/flex, header/body/status/actions/footer, and which blocks are simultaneously visible.
- Preserve the original semantic reading order by default. Do NOT split a single long original card into many sparse tabs just because groups exist.
- Only adapt when there is an actual mobile/UIEngine conflict: narrow width, huge text, repeated low-frequency details, or interaction ergonomics. When adapting, prefer: keep main flow as a scrollable scene page; move low-frequency details into overlay pages; keep status grids compact.
- If the original has two-column progress rows or grid attributes, express that intention in layout/notes and avoid one-field-per-row designs that waste PCB area.
- Keep semantically related items physically close. Do not scatter fields from the same original section/group across unrelated pages. Use precise group names, not broad catch-all groups. Examples: HP/MP/XP and survival stats belong together; task details and task actions belong together; story/message_flow and current choices should be adjacent; equipment and status effects belong together; opening profile inputs and opening direction choices should be in one coherent registration page unless the UI would become unusably dense.
- Fill the PCB intentionally. Avoid pages that contain only one or two small fields unless they are overlay detail pages. Every tab must either have dense structured content, a large scrollable text/message_flow area, or a clear overlay/detail purpose.
- Opening UI should usually be one coherent scrollable registration card: title/introduction, profile input groups, then branch choices. Do not split “profile form” and “choose opening” into separate sparse tabs unless the source explicitly has separate pages.
- Text sizing is part of the design: do not use ellipsis for meaningful state values, task text, item lists, reputation, money, locations, or action choices. Use wrap/scroll and allocate enough height. Ellipsis is only acceptable for short IDs or decorative labels.
- Reasonable interaction enhancement is allowed when it preserves gameplay: clickable choice text may become sendsMessage buttons; stable schemas may become LLM-updatable persistent panels; details may open in overlay pages. Do not add mechanics that change the original rules.
- Do not create a sparse standalone “actions/options” tab in scene. Put current choice buttons and free input near the story/message_flow page bottom, or use an overlay/sticky action dock.
- Use overlay pages for low-frequency detail panels in scene (full status, task board, friends album, dossier) when they would crowd the story page. In layout.pages set {"type":"overlay", "parentPage":"公会大厅"}; Dart will generate open-overlay buttons on the parent page.
- Overlay pages are still pages inside the same PCB: they must have enough vertical space for all internal components. Use scroll fields for long task/friend text, keep status grids compact, and do not design overlays as tiny badges/popups that cannot contain their fields.
- TaskBoard/FriendsAlbum text fields are compiled as status_field dataChannels with LLM write policy, so they can be continuously updated by the LLM. Keep them as scroll fields for dynamic content; do not describe them as dead static text unless the source explicitly forbids updates.
- For multi-opening cards with asymmetric runtime data, express available data differences with branchInitialValues where possible. Example: if branch 0 has three quest cards but branch 1 has no quest schema, TaskBoard.branchInitialValues["1"] should be “暂无公会任务，待剧情更新”, not a copy of branch 0 tasks.

# Layout intent fields (AI-driven space allocation)
You can influence how the compiler lays out the PCB by setting layout hints. These are optional; the compiler falls back to heuristics when absent, but explicit intent produces denser, better-filled layouts.

Page-level (in layout.pages[]):
- "columns": integer 1-6. Number of columns for the page's field grid. 1 = single-column rows, 2 = two-column grid, 3 = three-column compact grid. Set 2 or 3 for attribute/stat grids that originally were multi-column. Leave 0/unset to let the compiler decide from field count.
- "density": "compact" | "normal" | "spacious". Row vertical spacing. compact for dense stat boards, spacious for readable dossier pages.
- "fill": true | false. Whether this page should stretch its scrollable content to fill the PCB height. Default true for scene story pages; set false for short action pages that should stay compact.

Field-level (in fields[]):
- "span": 1 | 2. Column span within a multi-column page. 2 = occupy the full row. Use 2 for long text fields, task boards, item lists, relationship descriptions. Ignored when the page is single-column.
- "layout": "standard" | "grid" | "progress" | "badge". Optional per-field layout override. "progress" renders a number field as a progress bar; "grid" renders it as a compact grid cell. Empty/unset lets the compiler decide from display/type.

Guidelines for good space allocation:
- Attribute/stat groups (STR/AGI/INT or 力量/敏捷/智力) that were 2-column in the original should set layout.pages[] columns:2 (or 3 for very dense grids). Do NOT force one-field-per-row on multi-column sources.
- Long text fields (task boards, item lists, dossiers) should set "span":2 and overflow:"scroll" so they own a full row and expand to fill remaining PCB height.
- Do NOT put 1-2 small fields alone on a page; merge them or move to overlay. The compiler auto-detects sparse pages and reports them.
- Keep total content height reasonable: the compiler clamps PCB height to 2000. Extremely dense cards should split into overlay pages rather than one towering PCB.
- Progress clusters (HP/MP/XP) already render as a special compact cluster; you do not need columns for them, but setting "density":"compact" tightens spacing.

# What to extract from a SillyTavern card
- regex_scripts findRegex/replaceString may define UI fields and HTML/CSS layout.
- IMPORTANT: use the human-facing labels from replaceString / rendered HTML as field.name. If the transport key is English (HP/MP/STR) but the rendered label is Chinese (生命值 (HP)), use the Chinese display label as name and put the raw key in sourceKey. Do not throw away the original display translation.
- first_mes / alternate_greetings may contain initial status tags, e.g. <生命>84%</生命>.
- onclick="send('...')" or send('...') means an action button.
- input_prompt in a choice box means a free input field. Put it in inputs[] for opening/scene UIs. For extra_companion, usually DO NOT generate an input component because the normal chat input already exists; record the input_prompt in notes unless the author explicitly wants an in-panel input.
- tavern_helper external JS import means the UI may be runtime-generated; mark unsupported instead of inventing.
- world book entries may contain variable definitions or initvar sections; use them as evidence if relevant.
- Stable message-level schemas like `{quest:...}`, `{DQ_ChoiceBox|...}` and `{FriendsAlbumPage|...}` may be represented as persistent LLM-updatable UI fields/pages (for example scroll text task_board/friends_album or action buttons) when that improves usability and does not change gameplay. Prefer this over unsupported when the schema is clear and recurring.
- When converting `{quest:...}` into a task_board text field, do not display raw schema text. Format every available initial quest into readable sections/cards, include all quests found in first_mes, preserve source order, and use overflow=scroll.
- When converting `FriendsAlbumPage`, prefer a persistent friends_album scroll field/page or structured slots that can be updated by LLM. Do not show raw `{FriendsAlbumPage|...}` text.

# Strict anti-hallucination rules
- If the original card has no explicit UI evidence, return hasUi=false.
- Do not design a UI just because a character would look good with one.
- Every field/action/input should include sourceRef.
- Do not invent fields absent from source evidence.
- Do not translate source text unless the source itself is translated, but do preserve display labels that already exist in the original HTML/CSS.
- Preserve {{char}} / {{user}} placeholders.
- Current compiler emits card-level assemblies. It cannot yet render arbitrary ST regex HTML as per-message temporary UI. However scene mode can include message_flow, so it can place the real AI/user messages inside a custom frame. If a component is only a message-scoped card (quest cards, friends album, etc.), either mark it unsupported or convert it into an LLM-updatable persistent page/field when the source provides a stable schema or the author intent says it should be retained.
- Arbitrary JavaScript-like conditional style is not supported in UiDesignPlan. If you see conditional coloring, record it in notes/unsupported unless it can be represented as a simple status/indicator later.
- Progress max is currently compile-time/status-field range. If source has current/max (HP:50/120), set max from evidence, but do not assume max can dynamically change at runtime unless explicitly supported.
- Opening branches: UIEngine has branchVariants and status fields have branch_initial_values. If alternate_greetings share the same UI structure but have different starting values, fill fields[].branchInitialValues. The current AI compiler does not yet generate fully separate UI layouts per branch; if a branch has a truly different UI structure, record it in notes/unsupported instead of pretending all branches are covered.
- Opening UI purpose: introduce the card/world, collect minimal player/profile info if needed, and choose the opening greeting direction by branchIndex. Do NOT put a branch-internal DQ_ChoiceBox or quest choice into opening unless there is only one greeting and the author explicitly intends it as the opening choice. Opening branch buttons usually need branchIndex and label only; leave sendText empty unless the source has explicit onclick/send evidence.
- If the source says the player may specify name/age/gender/appearance/personality/background or otherwise be randomly generated, opening should include multiple profile input fields. Use inputs[] with targetKind="status_field", sendOnSubmit=false, sourceKey like UserProfile_Name/UserProfile_Age/UserProfile_Gender/UserProfile_Appearance/UserProfile_Personality/UserProfile_Background/UserProfile_Extra.
- Runtime status fields like HP/MP/XP/STR belong in scene/companion/sticky, not in opening. Opening may collect/edit profile fields, but should not duplicate a full PlayerStatus dashboard.

# UiDesignPlan schema
Return exactly one JSON object. For a simple card, return a single plan. For opening + scene or opening + companion, prefer:
{
  "hasUi": true,
  "evidenceSummary": "...",
  "sourceRefs": ["..."],
  "visualStyle": {"pcbColor":"#111318", "panelColor":"#1E232B"},
  "assemblies": [
    {"uiMode":"opening", "uiName":"开场选择", "actions":[...]},
    {"uiMode":"scene", "uiName":"运行终端", "fields":[...]}
  ]
}

Single UiDesignPlan object shape:
{
  "hasUi": true,
  "confidence": 0.0,
  "uiMode": "extra_companion|opening|scene|extra_sticky",
  "uiName": "short UI name",
  "evidenceSummary": "why this card has UI, or why not",
  "sourceRefs": ["data.extensions.regex_scripts[0]"],
  "visualStyle": {
    "styleName": "dark cyberpunk terminal",
    "pcbColor": "#111318",
    "panelColor": "#1E232B",
    "titleColor": "#FFFFFF",
    "labelColor": "#AAB0BC",
    "valueColor": "#E8EDF5",
    "accentColor": "#4FA3D1",
    "buttonBgColor": "#2A3340",
    "barFillColor": "#4FA3D1",
    "barTrackColor": "#2A2D36",
    "borderRadius": 14,
    "glow": false
  },
  "layout": {
    "kind": "tabbed_companion_panel|single_panel|opening_choices|scene_dashboard",
    "navigation": "tabs|swipe|tabs_and_swipe",
    "columns": 2,
    "pages": [
      {"title": "公会大厅", "role": "story", "type": "base", "columns": 1, "density": "normal", "fill": true},
      {"title": "冒险者档案", "role": "stats", "type": "overlay", "parentPage": "公会大厅", "columns": 2, "density": "compact"},
      {"title": "任务板", "role": "tasks", "type": "overlay", "parentPage": "公会大厅"}
    ]
  },
  "fields": [
    {
      "name": "生命值 (HP)",
      "sourceKey": "HP",
      "group": "核心状态",
      "type": "number|text|bool",
      "display": "progress|text|badge",
      "textAlign": "left|center|right",
      "overflow": "ellipsis|wrap|scroll",
      "initialValue": "84",
      "branchInitialValues": {"0": "84", "1": "90"},
      "min": 0,
      "max": 100,
      "owner": "player|char|neutral",
      "span": 1,
      "layout": "",
      "page": "属性",
      "sourceRef": "data.first_mes:<生命>84%</生命>"
    }
  ],
  "inputs": [
    {
      "name": "姓名",
      "sourceKey": "UserProfile_Name",
      "placeholder": "留空则随机生成",
      "initialValue": "",
      "sendOnSubmit": false,
      "targetKind": "status_field",
      "page": "角色设定",
      "sourceRef": "description: 若{{user}}未指定...随机生成"
    },
    {
      "name": "自由行动",
      "placeholder": "在此输入你的决定...",
      "sendOnSubmit": true,
      "targetKind": "none",
      "page": "选项",
      "sourceRef": "data.first_mes DQ_ChoiceBox input_prompt"
    }
  ],
  "actions": [
    {
      "label": "新人入狱",
      "sendText": "选择开场1：新人入狱",
      "keyAction": false,
      "branchIndex": 0,
      "page": "选项",
      "sourceRef": "data.first_mes onclick send"
    }
  ],
  "unsupported": [
    {"kind": "external_js_plugin", "reason": "...", "sourceRef": "data.extensions.tavern_helper"}
  ],
  "notes": []
}

If hasUi=false, still return evidenceSummary, sourceRefs, unsupported and notes; fields/actions may be empty.
''';

  /// 精简版知识库：只保留让 AI 输出合法 UiDesignPlan 的最小必需信息。
  static String compactPromptSlim() => '''
# LLM Project UIEngine — 核心知识库
Knowledge version: $knowledgeVersion

你负责输出高层 UiDesignPlan JSON。

# 视觉与布局核心契约
1. **视觉风格 (visualStyle)**：**严禁无脑使用默认配色**。必须根据角色描述（description/personality）定制主题色。
   - `pcbColor`: PCB 底板色；`panelColor`: 容器面板色。
   - `accentColor`: 交互高亮色；`barFillColor`: 进度条填充色。
   - 示例：黑暗地牢卡可用 #1A1A1A 底 + #8B0000 鲜血红；清新校园卡可用 #F0F8FF 底 + #87CEEB 天空蓝。
2. **布局意图 (layout)**：
   - `columns`: 页面的网格列数 (1-3)。数值类字段多时，设为 2 或 3 以紧凑显示。
   - `pages`: 合理划分子页面。`role=story` 的 base 页是 scene 的核心；低频详情（任务、档案）用 `type=overlay` 叠加页。
   - `span`: 字段跨度。长文本字段（任务板、描述）设为 2（占满行）。
3. **多生命周期 (assemblies)**：
   - 原卡有开场分支按钮 → 必须包含 `uiMode=opening`。
   - 原卡有常驻状态栏/面板/正文包裹 → 必须包含 `uiMode=scene`。
   - 识别 scene 信号：`<生命>` 等标签、`{PlayerStatus|...}`、`<正文>` 包裹、regex 仪表盘。

# UI 生命周期模式 (uiMode) 核心指南
1. **opening** (开场登记)：仅用于对话开始前的身份选择、资料填写。
2. **scene** (沉浸终端)：**接管整个聊天屏幕**。适合 RPG 大作、全屏游戏终端。必须包含 `role=story` 的页面以承载 `message_flow`。
3. **extra_companion** (常驻伴生栏)：**在聊天框侧边显示的持久面板**（宽 212px）。这是 SillyTavern 绝大多数“常驻状态栏”的最佳转译目标。
4. **extra_sticky** (悬浮工具栏)：顶部/底部的窄条。

# 组合策略 (多 UI 决策)
- 如果原卡有开场按钮 + 常驻状态栏：**必须**输出 `assemblies: [opening方案, extra_companion方案]`。
- 如果原卡是沉浸式 RPG：**必须**输出 `assemblies: [opening方案, scene方案]`。
- **不要把开场按钮和常驻状态混在一个 UI 里**，那不符合 UIEngine 的物理生命周期。

# UiDesignPlan schema
{
  "hasUi": true/false,
  "confidence": 0.0~1.0,
  "uiMode": "opening|scene|extra_sticky|extra_companion",
  "uiName": "主题名",
  "evidenceSummary": "...",
  "sourceRefs": ["data..."],
  "visualStyle": {"styleName":"主题风格名","pcbColor":"#RRGGBB","panelColor":"#RRGGBB","titleColor":"#FFFFFF","labelColor":"#AAB0BC","valueColor":"#E8EDF5","accentColor":"#RRGGBB","buttonBgColor":"#RRGGBB","barFillColor":"#RRGGBB","barTrackColor":"#RRGGBB","borderRadius":14,"glow":false},
  "layout": {"kind":"scene_dashboard|opening_choices|single_panel","navigation":"tabs_and_swipe|swipe|none","columns":1,"pages":[{"title":"页面名","role":"story|stats|tasks|form","type":"base|overlay","parentPage":"父页ID","columns":1,"density":"compact|normal|spacious","fill":true}]},
  "fields": [{"name":"名","sourceKey":"Key","group":"分组","type":"number|text","display":"progress|text|badge","overflow":"ellipsis|wrap|scroll","initialValue":"...","span":1,"page":"页面名","sourceRef":"..."}],
  "inputs": [{"name":"名","sourceKey":"UserProfile_Name","placeholder":"...","initialValue":"","sendOnSubmit":false,"targetKind":"status_field|none","page":"页面名","sourceRef":"..."}],
  "actions": [{"label":"文案","sendText":"...","branchIndex":0,"page":"页面名","sourceRef":"..."}],
  "unsupported": [], "notes": []
}

# 严禁事项
- 没有 UI 证据时 hasUi=false。
- 不要凭空捏造字段；每个元素必须有 sourceRef。
- 不要让布局太稀疏，一字段一行在移动端很丑。
''';

}
