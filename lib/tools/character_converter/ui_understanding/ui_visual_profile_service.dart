import '../ai_visual_extractor.dart';
import 'ui_source_pack.dart';
import 'ui_visual_profile.dart';

/// 原卡视觉分析服务：从证据包生成 [UiVisualProfile]。
///
/// 规则扫描是**纯 Dart、零 API 调用**的默认路径——统计原卡 replaceString /
/// 内联 CSS 的渐变/描边/发光/明暗特征，产出给 AI 的参考证据。AI 深化
/// （用模型从 CSS 提取精确色值）由 [enrich] 提供，失败即静默回落规则结果，
/// 不进失败路径。
class UiVisualProfileService {
  const UiVisualProfileService._();

  /// 规则扫描：不调用模型，纯确定性统计。
  static UiVisualProfile scan(UiSourcePack pack) {
    final cssParts = <String>[];
    for (final e in pack.regexScripts.where((e) => e.enabled)) {
      cssParts.add(e.replaceString);
    }
    for (final e in pack.htmlSnippets) {
      cssParts.add(e.text);
    }
    final css = cssParts.join('\n');
    if (css.trim().isEmpty) return UiVisualProfile.none;

    final hasGradient =
        RegExp(r'linear-gradient', caseSensitive: false).hasMatch(css);
    final hasStroke = RegExp(
      r'border\s*:\s*[^;]*(?:solid|1px|2px)',
      caseSensitive: false,
    ).hasMatch(css);
    final hasGlow =
        RegExp(r'box-shadow\s*:\s*[^;]*\d+', caseSensitive: false)
            .hasMatch(css);

    // 底板材质倾向：渐变优先，其次描边（浅色底才能看清 outline）。
    String materialHint = 'auto';
    if (hasGradient) {
      materialHint = 'gradient';
    } else if (hasStroke) {
      materialHint = 'outline';
    }

    // 主色：从 background 找第一个有实质内容的 hex。
    String? primaryColor;
    for (final m in RegExp(
      r'(?:background|background-color)\s*:\s*[^;]*?(#[0-9a-fA-F]{6})',
      caseSensitive: false,
    ).allMatches(css)) {
      primaryColor = m.group(1)!.substring(1).toUpperCase();
      break;
    }

    // 渐变第二色：linear-gradient(... , #hex  ...) 里最后一个 hex。
    String? gradientSecondColor;
    for (final m in RegExp(
      r'linear-gradient\([^)]*?(#[0-9a-fA-F]{6})',
      caseSensitive: false,
    ).allMatches(css)) {
      final inner = m.group(0) ?? '';
      final colors = RegExp(r'#[0-9a-fA-F]{6}').allMatches(inner).toList();
      if (colors.isNotEmpty) {
        gradientSecondColor =
            colors.last.group(0)!.substring(1).toUpperCase();
      }
      break;
    }

    // 描边色：border 声明里的 hex（没有则回落到主色旁的路由色）。
    String? strokeColor;
    for (final m in RegExp(
      r'border[^;]{0,80}?(#[0-9a-fA-F]{6})',
      caseSensitive: false,
    ).allMatches(css)) {
      strokeColor = m.group(1)!.substring(1).toUpperCase();
      break;
    }

    // 明暗：统计背景色系里的亮/暗样本数。没有样本时用主色亮度近似。
    final lightTheme = _isLightPalette(css, primaryColor);

    final notes = <String>[];
    if (hasGlow && primaryColor == null) {
      notes.add('检测到 box-shadow 发光，但没找到明确的背景色，发光色可由 AI 从语境推断。');
    }

    return UiVisualProfile(
      sourceSummary: '规则扫描 regex_scripts + 内联 HTML/CSS',
      hasGradient: hasGradient,
      hasStroke: hasStroke,
      hasGlow: hasGlow,
      materialHint: materialHint,
      primaryColor: primaryColor,
      gradientSecondColor: gradientSecondColor,
      strokeColor: strokeColor,
      lightTheme: lightTheme,
      notes: notes,
      source: 'rule',
    );
  }

  /// 可选 AI 深化：用模型从 CSS 提取精确视觉语义。
  ///
  /// 未配置 API / 调用失败时静默回落 [rule]（不进失败路径）。返回的
  /// profile 只作为参考注入 prompt，模型仍可自主决定是否采用。
  static Future<UiVisualProfile> enrich(
    UiVisualProfile rule,
    UiSourcePack pack,
  ) async {
    if (!rule.isEmpty && pack.hasEvidence) {
      // 只挑 replaceString 最长的证据给模型，避免长卡超 prompt 上限。
      final longest = pack.regexScripts
          .where((e) => e.enabled)
          .fold<UiRegexEvidence?>(null, (acc, e) {
        return (acc == null || e.replaceString.length > acc.replaceString.length)
            ? e
            : acc;
      });
      final css = longest?.replaceString;
      if (css != null && css.trim().isNotEmpty) {
        final theme = await AiVisualThemeExtractor.extractVisualProfile(css);
        if (theme != null && theme.source == 'ai') {
          return theme;
        }
      }
    }
    return rule;
  }

  static bool _isLightPalette(String css, String? primaryColor) {
    var lightSamples = 0;
    var darkSamples = 0;
    // 只统计明显偏亮 / 偏暗的 hex。
    for (final m in RegExp(r'#[0-9a-fA-F]{6}').allMatches(css)) {
      final hex = m.group(0)!.substring(1);
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      if (lum > 0.7) {
        lightSamples++;
      } else if (lum < 0.3) {
        darkSamples++;
      }
    }
    if (lightSamples != darkSamples) return lightSamples > darkSamples;
    if (primaryColor != null) {
      final r = int.parse(primaryColor.substring(0, 2), radix: 16);
      final g = int.parse(primaryColor.substring(2, 4), radix: 16);
      final b = int.parse(primaryColor.substring(4, 6), radix: 16);
      return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.45;
    }
    return false;
  }
}
