import 'character_card_mapper.dart';
import 'conversion_models.dart';
import 'third_party_card_detector.dart';

/// 角色卡转换核心入口（纯 Dart，无 IO / 无 Flutter 依赖）。
///
/// 平台层（PC 工具 / 移动端）负责：读字节、选文件、写 .llmcard、写报告；
/// 本类只负责：识别 + 规则映射。
class CharacterConversionService {
  /// 转换单份字节内容。
  ///
  /// [sourceName] 仅用于显示与命名（例如原文件名）。
  static CardConversionResult convertBytes(
    List<int> bytes, {
    required String sourceName,
  }) {
    if (bytes.isEmpty) {
      return CardConversionResult.failure(
        sourceName,
        ThirdPartyCardFormat.unknown,
        '文件为空。',
      );
    }

    final detection = ThirdPartyCardDetector.detect(bytes);

    switch (detection.format) {
      case ThirdPartyCardFormat.llmProjectCard:
        return CardConversionResult.failure(
          sourceName,
          detection.format,
          '这已经是 LLM Project 角色卡（.llmcard），无需转换，可直接导入。',
        );

      case ThirdPartyCardFormat.unknown:
        return CardConversionResult.failure(
          sourceName,
          detection.format,
          '无法识别为受支持的第三方角色卡（PNG 内嵌 chara / SillyTavern / TavernAI JSON）。',
        );

      case ThirdPartyCardFormat.png:
        {
          final json = detection.json;
          if (json == null) {
            return CardConversionResult.failure(
              sourceName,
              detection.format,
              'PNG 中未找到角色卡元数据（chara / ccv3）。',
            );
          }
          final innerFormat = ThirdPartyCardDetector.detectFromJson(json);
          return CharacterCardMapper.map(
            outerJson: json,
            format: innerFormat == ThirdPartyCardFormat.unknown
                ? ThirdPartyCardFormat.png
                : innerFormat,
            sourceName: sourceName,
            imageBytes: detection.pngBytes,
          );
        }

      case ThirdPartyCardFormat.sillyTavernV2:
      case ThirdPartyCardFormat.tavernV1:
        {
          final json = detection.json;
          if (json == null) {
            return CardConversionResult.failure(
              sourceName,
              detection.format,
              'JSON 解析失败。',
            );
          }
          return CharacterCardMapper.map(
            outerJson: json,
            format: detection.format,
            sourceName: sourceName,
          );
        }
    }
  }

  /// 批量转换，返回汇总报告。
  static BatchConversionReport convertBatch(
    Iterable<({String name, List<int> bytes})> inputs,
  ) {
    final results = <CardConversionResult>[];
    for (final input in inputs) {
      try {
        results.add(convertBytes(input.bytes, sourceName: input.name));
      } catch (e) {
        results.add(CardConversionResult.failure(
          input.name,
          ThirdPartyCardFormat.unknown,
          '转换异常：$e',
        ));
      }
    }
    return BatchConversionReport(results);
  }
}
