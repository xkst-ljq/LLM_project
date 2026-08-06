/// UIEngine 知识库（给 AI 的压缩版能力说明）。
///
/// 第一版不依赖模型 tool calling：由代码主动把知识库压进 prompt，
/// 对 OpenAI 兼容、本地模型、代理模型都更稳。
class UiEngineKnowledgeService {
  const UiEngineKnowledgeService._();

  static String compactPrompt() => r'''
# LLM Project UIEngine capabilities

You are NOT allowed to output internal assembly JSON. You must output high-level UiDesignPlan data only. Dart code will compile it.

You may output either:
1. A single UiDesignPlan object, or
2. One top-level JSON object with "assemblies": [UiDesignPlan, UiDesignPlan, ...].

Use multiple assemblies when the original card has distinct lifecycle UI, e.g. opening identity selection + scene runtime terminal.

## Modes
- opening: full-screen opening UI. It must provide a keyAction button to confirm/close. Best for first-message branch choices. Opening can coexist with later companion/sticky/scene assemblies; after it is dismissed the normal runtime UI continues.
- scene: full-screen takeover UI. It must provide a keyAction button; in scene this semantic button opens the chat settings/menu panel, it is not an invented story action. Scene can contain message_flow to render the real chat history inside the custom UI. Scene replaces the native chat list/input area, so it is mutually exclusive with extra_companion.
- extra_sticky: persistent UI. It should provide a key action button to collapse.
- extra_companion: companion UI embedded around AI message bubbles. Width limit is 212 px. Best for compact status panels that do not need to own the whole narrative surface.

Default: choose extra_companion for compact status bars / dashboards that follow character replies. If the original card wraps narrative body + status + actions into one immersive terminal/card, consider scene with message_flow instead of companion.

## Visual primitives available through UiDesignPlan
- surface/base_box: panel/background/card/button visual base. Materials: glass, solid, gradient, outline. Shapes: rectangle, rounded, capsule, circle, heart, star5, star4. The compiler keeps the top-level PCB color visible as an outer frame and places the main background surface inset inside it; use pcbColor for frame/outer material and panelColor for inner paper/card surface.
- text: labels, titles, values. Supports fontSize, textAlign = left/center/right, overflow = ellipsis/clip/scroll, richText Markdown/HTML. Use scroll for long descriptions or task details; use center/right only when the original visible layout supports it. The compiler also auto-upgrades obviously long text values to scroll blocks so content is not clipped.
- progress: numeric status bar with min/max/current, trackColor and progressShape. Good for HP/MP/XP/percent. Do not assume runtime max changes unless API explicitly maps it.
- button: invisible touch area. Use with a surface/text visual behind it. Emits tap/double_tap/long_press. Can carry keyAction, sendsMessage, targetBranchIndex.
- input: free text field. Supports placeholder, default text, maxLength, multiline, vertical/horizontal text alignment. Single-line input can submit text to chat flow when marked sendsMessage.
- select: option list [{label,value}], current/defaultValue. Can be filtered/matched from input via linker.
- switch: boolean value.
- slider: user-draggable number with min/max/current/step.
- line: divider, axis horizontal/vertical, styles solid/dashed/dotted/curve/double.
- indicator: status dot with dotSize/defaultGlow/defaultColor/statusRules. Do not use fake isOn/onColor keys.
- image: custom URL/asset/data URI, character avatar, user avatar; fit cover/contain/fill; borderRadius.
- message_flow: scrollable real chat history / AI正文 flow, supplied by MessageFlowScope in runtime. Use it in scene when the original ST UI wraps the narrative body inside a custom terminal/card.

## Logic/linker concepts the compiler can create
- page_router + button_to_page_route: tab button switches pages or opens/closes overlay pages.
- page gestures: base pages can switch by swipe_left/swipe_right/swipe_up/swipe_down through AssemblyPage.gestures. The compiler can create tabs plus swipe navigation; do not claim gestures are unsupported. Opening mode should rely on keyAction/buttons, not swipe.
- overlay pages: AssemblyPage type can be overlay with parentPageId. Use this for detail drawers, dossiers, expanded status panels, and non-primary information.
- click_to_surface_press: button click gives the backing surface press feedback.
- button_to_message_action: scene UI can expose regenerate/continue/edit/delete/version navigation for latest AI message.
- dataChannel: bind text/progress/slider/input/select/switch to status_bar_fields, session vars, card entries, or user_profile so the LLM/runtime can read/update values.
- input sendsMessage: a single-line input can send the typed text on submit, useful for ST input_prompt.
- scene keyAction: mark a normal button with keyAction=true to open the chat settings/menu panel. Do not claim this system action is unsupported.
- math_node + linker: use value_to_math_param, click_to_math_trigger, result_to_text/result_to_progress for native arithmetic instead of JS.
- timer + linker: timer_tick can drive progress/switch/math/text for cooldowns, decay, regeneration.
- indicator + statusRules + linker: represent simple condition/status lights.
- animation: click_to_surface_press and event_to_animation can trigger press/glow/ripple/flash style animations when configured on the target element.

## Confirmed runtime facts (do not present these as unknown)
- message_flow is a normal UI module rendered in a SizedBox; it can be visually placed over/inside surfaces by absolute layout. It is not restricted to a top-level-only slot.
- extra_companion has a hard width cap of 212px, but height can grow within PCB limits and the surrounding chat list scrolls. It can use pages/tabs/gestures, but dense layouts are discouraged because the width is narrow.
- line color comes from module.color; thickness/axis/solid/dashed/dotted/curve/double are supported. Use line for borders, dividers, ornaments, and terminal/codex styling.
- overlay pages open via page_router route action open_overlay and can contain their own text/input/buttons/scroll areas. They are suitable for dossiers, quest details, friend lists, and expanded status panels.
- status_bar_fields are LLM Project native state fields. They are not an automatic SillyTavern parser: the translator must map ST keys into fields/sourceKey/dataChannel. Once mapped, the app prompt/update mechanism lets the LLM read and update them.
- Tabs are a visual pattern built from surface/text/button plus page_router/linker. page_router is the mechanism; there is no conflict between tabs and overlay buttons.
- Multiple assemblies can coexist when lifecycles differ: opening + scene is valid. scene suppresses native chat/extra_companion; sticky remains a tool layer; opening is shown until dismissed.
- Logic components are optional. Use math_node/timer/indicator/linker only when source evidence or confirmed author intent requires native computation/condition/automation. Pure visual upgrades may use line/surface/animation without changing gameplay.

## What to extract from a SillyTavern card
- regex_scripts findRegex/replaceString may define UI fields and HTML/CSS layout.
- IMPORTANT: use the human-facing labels from replaceString / rendered HTML as field.name. If the transport key is English (HP/MP/STR) but the rendered label is Chinese (生命值 (HP)), use the Chinese display label as name and put the raw key in sourceKey. Do not throw away the original display translation.
- first_mes / alternate_greetings may contain initial status tags, e.g. <生命>84%</生命>.
- onclick="send('...')" or send('...') means an action button.
- input_prompt in a choice box means a free input field. Put it in inputs[] for opening/scene UIs. For extra_companion, usually DO NOT generate an input component because the normal chat input already exists; record the input_prompt in notes unless the author explicitly wants an in-panel input.
- tavern_helper external JS import means the UI may be runtime-generated; mark unsupported instead of inventing.
- world book entries may contain variable definitions or initvar sections; use them as evidence if relevant.

## Strict anti-hallucination rules
- If the original card has no explicit UI evidence, return hasUi=false.
- Do not design a UI just because a character would look good with one.
- Every field/action/input should include sourceRef.
- Do not invent fields absent from source evidence.
- Do not translate source text unless the source itself is translated, but do preserve display labels that already exist in the original HTML/CSS.
- Preserve {{char}} / {{user}} placeholders.
- Current compiler emits card-level assemblies. It cannot yet render arbitrary ST regex HTML as per-message temporary UI. However scene mode can include message_flow, so it can place the real AI/user messages inside a custom frame. If a component is only a message-scoped card (quest cards, friends album, etc.), either mark it unsupported or include it only if there is evidence/author intent that it should become a persistent panel/tab.
- Arbitrary JavaScript-like conditional style is not supported in UiDesignPlan. If you see conditional coloring, record it in notes/unsupported unless it can be represented as a simple status/indicator later.
- Progress max is currently compile-time/status-field range. If source has current/max (HP:50/120), set max from evidence, but do not assume max can dynamically change at runtime unless explicitly supported.
- Opening branches: UIEngine has branchVariants and status fields have branch_initial_values. If alternate_greetings share the same UI structure but have different starting values, fill fields[].branchInitialValues. The current AI compiler does not yet generate fully separate UI layouts per branch; if a branch has a truly different UI structure, record it in notes/unsupported instead of pretending all branches are covered.

## UiDesignPlan schema
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
    "pages": [
      {"title": "属性", "role": "stats"},
      {"title": "档案", "role": "profile"},
      {"title": "选项", "role": "actions"}
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
      "page": "属性",
      "sourceRef": "data.first_mes:<生命>84%</生命>"
    }
  ],
  "inputs": [
    {
      "placeholder": "在此输入你的决定...",
      "sendOnSubmit": true,
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
}
