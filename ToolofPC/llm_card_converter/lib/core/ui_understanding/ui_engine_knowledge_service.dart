/// UIEngine 知识库（给 AI 的压缩版能力说明）。
///
/// 第一版不依赖模型 tool calling：由代码主动把知识库压进 prompt，
/// 对 OpenAI 兼容、本地模型、代理模型都更稳。
class UiEngineKnowledgeService {
  const UiEngineKnowledgeService._();

  static String compactPrompt() => r'''
# LLM Project UIEngine capabilities

You are NOT allowed to output internal assembly JSON. You must output a high-level UiDesignPlan only. Dart code will compile it.

## Modes
- opening: full-screen opening UI. It must provide a key action button to confirm/close. Best for first-message branch choices.
- scene: full-screen takeover UI. It must provide a key action button for settings/exit. Best only if the original card clearly has a full interactive scene UI.
- extra_sticky: persistent UI. It should provide a key action button to collapse.
- extra_companion: companion UI embedded around AI message bubbles. Width limit is 212 px. Best for status panels and compact dashboards.

Default: choose extra_companion for status bars / dashboards that follow character replies.

## Visual primitives available through UiDesignPlan
- surface: panel/background/card/button visual base. The compiler keeps the top-level PCB color visible as an outer frame and places the main background surface inset inside it; use pcbColor for frame/outer material and panelColor for inner paper/card surface.
- text: labels, titles, values. Supports textAlign = left/center/right and overflow = ellipsis/wrap/scroll. Use scroll for long descriptions or task details; use center/right only when the original visible layout supports it.
- progress: numeric status bar, usually min/max/current.
- button: invisible touch area. Use with a surface/text visual behind it.
- input: free text field. Single-line input can submit text to the chat flow when marked as sendsMessage.
- line: divider.

## Logic/linker concepts the compiler can create
- button_to_page_route: tab button switches pages.
- page gestures: base pages can switch by swipe_left/swipe_right/swipe_up/swipe_down through AssemblyPage.gestures. The compiler can create tabs plus swipe navigation; do not claim gestures are unsupported. Opening mode currently should rely on keyAction/buttons, not swipe.
- click_to_surface_press: button click gives the backing surface press feedback.
- dataChannel: bind text/progress to status_bar_fields so the LLM can read/update values.
- input sendsMessage: a single-line input can send the typed text on submit, useful for ST input_prompt.

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
- Current compiler emits card-level assemblies. It cannot yet render arbitrary ST regex HTML as per-message temporary UI. If a component is only a message-scoped card (quest cards, friends album, etc.), either mark it unsupported or include it only if there is evidence/author intent that it should become a persistent panel/tab.
- Arbitrary JavaScript-like conditional style is not supported in UiDesignPlan. If you see conditional coloring, record it in notes/unsupported unless it can be represented as a simple status/indicator later.
- Progress max is currently compile-time/status-field range. If source has current/max (HP:50/120), set max from evidence, but do not assume max can dynamically change at runtime unless explicitly supported.
- Opening branches: UIEngine has branchVariants and status fields have branch_initial_values, but the current AI compiler does not yet generate fully separate UI layouts per alternate_greetings. If alternate greetings contain different UI evidence, record it in notes/unsupported instead of pretending all branches are covered.

## UiDesignPlan schema
Return exactly one JSON object:
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
