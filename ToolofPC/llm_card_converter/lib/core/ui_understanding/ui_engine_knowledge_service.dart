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
  ///
  /// 用于「单轮全量注入」——prompt 太大是空返回的根因（黑曜石卡实测
  /// 知识库 23k 字符 + 证据包 57k 字符 ≈ 40k tokens，模型直接空回复）。
  /// 这个版本砍掉大部分散文规则，只留：
  ///   - 硬性输出规则
  ///   - UiDesignPlan schema（字段级）
  ///   - 少量关键指引（mode 语义 / 布局意图 / 常见陷阱）
  ///
  /// 完整版本见 [compactPrompt]（调试/精修时可用）。
  static String compactPromptSlim() => '''
# LLM Project UIEngine — 精简知识库
Knowledge version: $knowledgeVersion

你只输出高层 UiDesignPlan JSON（不要内部 assembly JSON，不要 markdown，不要解释）。
可以输出单个对象，或用顶层 {"assemblies": [...]} 表达多个生命周期（如 opening + scene）。

# UiDesignPlan schema
{
  "hasUi": true/false,
  "confidence": 0.0~1.0,
  "uiMode": "opening|scene|extra_sticky|extra_companion",
  "uiName": "简短名称",
  "evidenceSummary": "为什么有/没有 UI",
  "sourceRefs": ["data..."],
  "visualStyle": {"styleName":"...","pcbColor":"#111318","panelColor":"#1E232B","titleColor":"#FFFFFF","labelColor":"#AAB0BC","valueColor":"#E8EDF5","accentColor":"#4FA3D1","buttonBgColor":"#2A3340","barFillColor":"#4FA3D1","barTrackColor":"#2A2D36","borderRadius":14,"glow":false},
  "layout": {"kind":"opening_choices|scene_dashboard|single_panel","navigation":"tabs|swipe|tabs_and_swipe|none","columns":1,"pages":[{"title":"页面","role":"story|stats|tasks|form","type":"base|overlay","parentPage":"父页","columns":1,"density":"compact|normal|spacious","fill":true}]},
  "fields": [{"name":"字段名","sourceKey":"Key","group":"精确分组","type":"number|text|bool","display":"progress|text|badge","overflow":"ellipsis|wrap|scroll","initialValue":"...","branchInitialValues":{"1":"..."},"min":0,"max":100,"owner":"player|char|neutral","span":1,"page":"页面","sourceRef":"证据路径"}],
  "inputs": [{"name":"输入名","sourceKey":"UserProfile_Name","placeholder":"...","initialValue":"","sendOnSubmit":false,"targetKind":"status_field|none","page":"页面","sourceRef":"证据路径"}],
  "actions": [{"label":"按钮文案","sendText":"发送文本；opening 分支按钮通常留空","keyAction":false,"branchIndex":0,"page":"页面","sourceRef":"证据路径"}],
  "unsupported": [{"kind":"...","reason":"...","sourceRef":"..."}],
  "notes": []
}

# 关键规则
- 原卡没有明确 UI 证据时 hasUi=false。
- 每个字段/动作/输入必须有 sourceRef；没有证据不要生成。
- 不要凭空设计 UI；优先忠实迁移原卡 UI 语义，再做移动端适配。
- opening：只做开场方向选择与少量资料输入；不要放完整状态栏/任务板。
- scene：必须有 role=story 的 base 页以插入 message_flow；任务/状态/羁绊等
  低频详情用 overlay 页。长任务板/好友列表 initialValue 可用
  "__AUTO_QUEST_BOARD__" / "__AUTO_FRIENDS_ALBUM_EMPTY__" 让 Dart 填充。
- 用 columns/density/fill/span 控制空间分配；meaningful text 不要 ellipsis。
- UI 依赖外部 JS 运行时写入 unsupported，除非证据中有静态可还原内容。
- 保持相关内容物理邻近；避免一字段一行的稀疏布局浪费 PCB。
''';
}
