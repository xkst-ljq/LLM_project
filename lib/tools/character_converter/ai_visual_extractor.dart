import 'dart:convert';

import 'api_service.dart';
import 'app_settings.dart';
import 'ui_understanding/ui_visual_profile.dart';

/// AI 视觉主题提取器：分析原卡 HTML/CSS，产出结构化视觉语义。
///
/// 早期版本只提取 11 个 hex 色（[extractTheme]），且全仓库无调用点（死代码）。
/// 现复活并扩宽：新增 [extractVisualProfile]，输出 [UiVisualProfile]——
/// 渐变/描边/发光/明暗/气泡色等，供 [UiVisualProfileService.enrich] 使用。
///
/// 失败策略：未配置 API / 网络错误 / 解析失败一律返回 null，由调用方静默
/// 回落规则扫描结果，不进失败路径。
class AiVisualThemeExtractor {
  /// 从原始 CSS 提取完整视觉档案。失败返回 null。
  static Future<UiVisualProfile?> extractVisualProfile(
    String rawReplace,
  ) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) return null;

    try {
      final raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: _systemPrompt,
        userPrompt:
            '请分析这张角色卡的原卡 HTML/CSS，输出视觉档案 JSON。\n\n$rawReplace',
        temperature: 0.1,
      );
      final json = _parseJson(raw);
      if (json == null) return null;

      return UiVisualProfile(
        sourceSummary: 'AI 视觉深化（模型分析 replaceString）',
        hasGradient: json['hasGradient'] == true ||
            RegExp(r'linear-gradient', caseSensitive: false)
                .hasMatch(rawReplace),
        hasStroke: json['hasStroke'] == true,
        hasGlow: json['hasGlow'] == true,
        materialHint: _materialOf(json['surfaceMaterial']),
        primaryColor: _hexOf(json['pcbColor'] ?? json['primaryColor']),
        gradientSecondColor: _hexOf(json['gradientSecondColor'] ?? json['gradientTo']),
        strokeColor: _hexOf(json['strokeColor']),
        lightTheme: json['lightTheme'] == true,
        notes: [
          if (json['notes'] is List)
            ...(json['notes'] as List).whereType<String>().take(4),
        ],
        source: 'ai',
      );
    } catch (_) {
      return null;
    }
  }

  /// 旧接口：提取 11 个 hex 色。保留供参考，新路径走 [extractVisualProfile]。
  static Future<Map<String, dynamic>?> extractTheme(String rawReplace) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) return null;

    try {
      final raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: _legacyThemeSystemPrompt,
        userPrompt: 'Please analyze this raw HTML/CSS template and extract its visual theme:\n\n$rawReplace',
        temperature: 0.1,
      );
      return _parseJson(raw);
    } catch (_) {
      return null;
    }
  }

  static String _materialOf(dynamic raw) {
    final v = (raw ?? '').toString().toLowerCase().trim();
    const allowed = {'auto', 'solid', 'gradient', 'outline', 'glass'};
    return allowed.contains(v) ? v : 'auto';
  }

  /// hex（允许带 #）→ 无 # 的 6 位大写；非法返回 null。
  static String? _hexOf(dynamic raw) {
    if (raw is! String) return null;
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return s.toUpperCase();
    return null;
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
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static const String _systemPrompt = '''
你是 CSS/HTML 视觉设计师。分析角色卡的原卡 HTML/CSS，提取它的视觉设计档案（不只 hex 色）。

必须输出一个 JSON 对象，结构如下（字段可选，不确定就省略，不要瞎编）：
{
  "hasGradient": false,
  "hasStroke": false,
  "hasGlow": false,
  "lightTheme": false,
  "surfaceMaterial": "auto|solid|gradient|outline|glass",
  "pcbColor": "#RRGGBB",
  "gradientSecondColor": "#RRGGBB",
  "strokeColor": "#RRGGBB",
  "glowColor": "#RRGGBB",
  "glowIntensity": 0.0,
  "userBubbleColor": "#RRGGBB",
  "assistantBubbleColor": "#RRGGBB",
  "notes": ["自由文本"]
}

规则：
1. 只从 CSS 里读（background-color / linear-gradient / border / box-shadow / color），不发明。
2. hasGradient = 出现 linear-gradient；hasStroke = 出现 border solid 描框；hasGlow = 出现 box-shadow 发光。
3. lightTheme = 整体底色偏亮（白色/米色/浅灰背景）。
4. surfaceMaterial：底板材质倾向。渐变底 → gradient；描边框 → outline。
5. glowIntensity 0~1，发光强度；无发光就省略。
6. userBubbleColor / assistantBubbleColor：原卡聊天气泡底色（如有）。
7. 只输出 JSON，不要 markdown 代码块、解释或备注。
''';

  static const String _legacyThemeSystemPrompt = '''
You are a CSS and HTML design analyst. Your task is to analyze a raw HTML/CSS replace template from a character card and extract its visual design and color theme.

You must output a JSON object containing the extracted color palette (as 6-character hex values like "#RRGGBB") and design properties. Do not invent styles; read them from the CSS (e.g. background-color, border-radius, box-shadow, linear-gradient, color, etc.).

Output JSON structure (all fields must exist):
{
  "pcbColor": "#RRGGBB",
  "panelColor": "#RRGGBB",
  "titleColor": "#RRGGBB",
  "labelColor": "#RRGGBB",
  "valueColor": "#RRGGBB",
  "barFillColor": "#RRGGBB",
  "barTrackColor": "#RRGGBB",
  "accentColor": "#RRGGBB",
  "buttonBgColor": "#RRGGBB",
  "borderRadius": 12.0,
  "glow": false
}

Rules:
1. Return ONLY the JSON block. Do not write any markdown code blocks, explanation, or notes.
2. If any color is not specified or cannot be found, use a reasonable fallback from a cohesive theme that matches the overall style (e.g. dark cyberpunk, fantasy parchment, sci-fi terminal, cute pastel).
3. If the card design is primarily dark, use dark fallbacks. If it's light, use light fallbacks.
''';
}
