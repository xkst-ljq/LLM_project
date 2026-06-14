import 'dart:convert';

import 'conversion_models.dart';
import 'png_chara_reader.dart';

/// 识别一份字节内容属于哪种角色卡格式。
///
/// 识别顺序（避免误判自有格式）：
///   1. PNG -> 内嵌 chara -> 再判断 V1/V2；
///   2. ZIP（PK 头）-> 视为 LLM Project .llmcard，交给原生导入；
///   3. JSON -> spec=chara_card_v2 判定 V2；否则尝试 V1。
class CardDetectionResult {
  final ThirdPartyCardFormat format;

  /// 已解析出的角色 JSON（若是 PNG / JSON）。V2 时为外层（含 spec/data）。
  final Map<String, dynamic>? json;

  /// PNG 原始字节（用于保留角色图）。
  final List<int>? pngBytes;

  const CardDetectionResult(this.format, {this.json, this.pngBytes});
}

class ThirdPartyCardDetector {
  static CardDetectionResult detect(List<int> bytes) {
    if (bytes.isEmpty) {
      return const CardDetectionResult(ThirdPartyCardFormat.unknown);
    }

    // PNG
    if (PngCharaReader.isPng(bytes)) {
      final json = PngCharaReader.extractCharacterJson(bytes);
      if (json == null) {
        return CardDetectionResult(ThirdPartyCardFormat.unknown,
            pngBytes: bytes);
      }
      return CardDetectionResult(ThirdPartyCardFormat.png,
          json: json, pngBytes: bytes);
    }

    // ZIP（PK\x03\x04）—— 可能是 LLM Project .llmcard
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return const CardDetectionResult(ThirdPartyCardFormat.llmProjectCard);
    }

    // JSON
    final json = _tryDecodeJson(bytes);
    if (json != null) {
      return CardDetectionResult(detectFromJson(json), json: json);
    }

    return const CardDetectionResult(ThirdPartyCardFormat.unknown);
  }

  /// 仅根据已解析的 JSON 判断（PNG 内层也复用此函数）。
  static ThirdPartyCardFormat detectFromJson(Map<String, dynamic> json) {
    final spec = json['spec']?.toString();
    if (spec == 'chara_card_v2' || spec == 'chara_card_v3') {
      return ThirdPartyCardFormat.sillyTavernV2;
    }
    // V2 通常 data 里有 name；有些导出缺 spec 但有 data.name
    final data = json['data'];
    if (data is Map && data['name'] != null) {
      return ThirdPartyCardFormat.sillyTavernV2;
    }
    // V1：顶层有 name + (description/first_mes/personality)
    if (json['name'] != null &&
        (json.containsKey('description') ||
            json.containsKey('first_mes') ||
            json.containsKey('personality') ||
            json.containsKey('mes_example'))) {
      return ThirdPartyCardFormat.tavernV1;
    }
    return ThirdPartyCardFormat.unknown;
  }

  static Map<String, dynamic>? _tryDecodeJson(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }
}
