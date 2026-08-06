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
- surface: panel/background/card/button visual base.
- text: labels, titles, values.
- progress: numeric status bar, usually min/max/current.
- button: invisible touch area. Use with a surface/text visual behind it.
- line: divider.

## Logic/linker concepts the compiler can create
- button_to_page_route: tab button switches pages.
- click_to_surface_press: button click gives the backing surface press feedback.
- dataChannel: bind text/progress to status_bar_fields so the LLM can read/update values.

## What to extract from a SillyTavern card
- regex_scripts findRegex/replaceString may define UI fields and HTML/CSS layout.
- first_mes / alternate_greetings may contain initial status tags, e.g. <生命>84%</生命>.
- onclick="send('...')" or send('...') means an action button.
- tavern_helper external JS import means the UI may be runtime-generated; mark unsupported instead of inventing.
- world book entries may contain variable definitions or initvar sections; use them as evidence if relevant.

## Strict anti-hallucination rules
- If the original card has no explicit UI evidence, return hasUi=false.
- Do not design a UI just because a character would look good with one.
- Every field and action should include sourceRef.
- Do not invent fields absent from source evidence.
- Do not translate source text unless the source itself is translated.
- Preserve {{char}} / {{user}} placeholders.

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
    "pages": [
      {"title": "属性", "role": "stats"},
      {"title": "档案", "role": "profile"},
      {"title": "选项", "role": "actions"}
    ]
  },
  "fields": [
    {
      "name": "生命",
      "type": "number|text|bool",
      "display": "progress|text|badge",
      "initialValue": "84",
      "min": 0,
      "max": 100,
      "owner": "player|char|neutral",
      "page": "属性",
      "sourceRef": "data.first_mes:<生命>84%</生命>"
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
