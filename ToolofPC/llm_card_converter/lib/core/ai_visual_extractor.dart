import 'dart:convert';
import 'api_service.dart';
import 'app_settings.dart';

class AiVisualThemeExtractor {
  static Future<Map<String, dynamic>?> extractTheme(String rawReplace) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) return null;

    const systemPrompt = '''
You are a CSS and HTML design analyst. Your task is to analyze a raw HTML/CSS replace template from a character card and extract its visual design and color theme.

You must output a JSON object containing the extracted color palette (as 6-character hex values like "#RRGGBB") and design properties. Do not invent styles; read them from the CSS (e.g. background-color, border-radius, box-shadow, linear-gradient, color, etc.).

Output JSON structure (all fields must exist):
{
  "pcbColor": "#RRGGBB",       // Overall background/wrapper/device color
  "panelColor": "#RRGGBB",     // Status container/panel/card background color
  "titleColor": "#RRGGBB",     // Title/header text color
  "labelColor": "#RRGGBB",     // Label/descriptor text color
  "valueColor": "#RRGGBB",     // Value/status text color
  "barFillColor": "#RRGGBB",   // Progress bar fill/foreground color
  "barTrackColor": "#RRGGBB",  // Progress bar background track/groove color
  "accentColor": "#RRGGBB",    // Interactive elements/buttons primary color
  "buttonBgColor": "#RRGGBB",  // Background color for buttons/options
  "borderRadius": 12.0,        // Rounded corner radius in pixels (typically 0.0 to 32.0)
  "glow": false                // Whether the panel/text has glowing effects (box-shadow, glow, text-shadow pulsing, etc.)
}

Rules:
1. Return ONLY the JSON block. Do not write any markdown code blocks, explanation, or notes.
2. If any color is not specified or cannot be found, use a reasonable fallback from a cohesive theme that matches the overall style (e.g. dark cyberpunk, fantasy parchment, sci-fi terminal, cute pastel).
3. If the card design is primarily dark, use dark fallbacks. If it's light, use light fallbacks.
''';

    final userPrompt = 'Please analyze this raw HTML/CSS template and extract its visual theme:\n\n$rawReplace';

    try {
      final raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: 0.1,
      );

      final parsed = _parseJson(raw);
      return parsed;
    } catch (_) {
      return null;
    }
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
}
