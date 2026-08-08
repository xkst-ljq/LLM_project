/// 第三方角色卡转换核心 —— 数据结构定义。
///
/// 本文件是纯 Dart（不依赖 Flutter / dart:io），方便：
///   - PC 端转换工具直接调用；
///   - 移动端裁剪后调用；
///   - 单元测试。
///
/// 设计原则（与项目讨论一致）：
///   1. 规则转换为基础，离线可用，不依赖网络与模型；
///   2. 不执行酒馆脚本 / 正则 / 扩展插件，只解析与保留；
///   3. 转换忠实于原文，不新增设定（AI 智能归类作为后续增强层）。
library;

/// 识别到的源角色卡格式。
enum ThirdPartyCardFormat {
  /// LLM Project 自有 .llmcard（不需要转换）。
  llmProjectCard,

  /// SillyTavern / Character Card V2（spec=chara_card_v2）。
  sillyTavernV2,

  /// SillyTavern / TavernAI V1（顶层 name/description/...）。
  tavernV1,

  /// PNG 容器内嵌 chara（具体内部再判断 V1/V2）。
  png,

  /// 未能识别。
  unknown,
}

extension ThirdPartyCardFormatLabel on ThirdPartyCardFormat {
  String get label {
    switch (this) {
      case ThirdPartyCardFormat.llmProjectCard:
        return 'LLM Project 角色卡';
      case ThirdPartyCardFormat.sillyTavernV2:
        return 'SillyTavern / Character Card V2';
      case ThirdPartyCardFormat.tavernV1:
        return 'TavernAI / SillyTavern V1';
      case ThirdPartyCardFormat.png:
        return 'PNG 角色卡';
      case ThirdPartyCardFormat.unknown:
        return '未识别格式';
    }
  }
}

/// 转换报告中的单条提示。
enum ConversionNoteLevel { info, warning, error }

class ConversionNote {
  final ConversionNoteLevel level;
  final String message;

  const ConversionNote(this.level, this.message);

  static ConversionNote info(String m) =>
      ConversionNote(ConversionNoteLevel.info, m);
  static ConversionNote warning(String m) =>
      ConversionNote(ConversionNoteLevel.warning, m);
  static ConversionNote error(String m) =>
      ConversionNote(ConversionNoteLevel.error, m);

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'message': message,
      };
}

/// 单个文件的转换结果。
///
/// [characterData] 与 [worldBooks] 已经是 LLM Project 内部结构（与
/// CharacterCardAssetService 导出的 data/character.json /
/// data/dependencies/world_books.json 字段一致），可以直接写入 .llmcard。
class CardConversionResult {
  /// 源文件名（仅用于显示与命名）。
  final String sourceName;

  /// 识别到的源格式。
  final ThirdPartyCardFormat format;

  /// 是否成功（至少拿到角色名 + 一项有效内容）。
  final bool success;

  /// 是否部分转换（成功，但有降级 / 未支持字段）。
  final bool partial;

  /// LLM Project 角色 JSON（data/character.json 形态）。
  final Map<String, dynamic>? characterData;

  /// 转换出的世界书（data/dependencies/world_books.json 形态）。
  final List<Map<String, dynamic>> worldBooks;

  /// 角色图（PNG 字节）。来自 PNG 卡本身，可用作头像 / 卡图。
  final List<int>? imageBytes;

  /// 成功映射的字段（用于报告与对照）。
  final List<String> convertedFields;

  /// 已识别但当前不支持 / 已降级的字段。
  final List<String> unsupportedFields;

  /// 提示信息。
  final List<ConversionNote> notes;

  /// 开场白等文本里下载内嵌的图片：卡内资产路径(assets/embedded/xxx) -> 图片字节。
  /// 写卡时打包进 assets/，导入时落地为本地文件。
  final Map<String, List<int>> embeddedImages;

  const CardConversionResult({
    required this.sourceName,
    required this.format,
    required this.success,
    this.partial = false,
    this.characterData,
    this.worldBooks = const [],
    this.imageBytes,
    this.convertedFields = const [],
    this.unsupportedFields = const [],
    this.notes = const [],
    this.embeddedImages = const {},
  });

  factory CardConversionResult.failure(
    String sourceName,
    ThirdPartyCardFormat format,
    String message,
  ) {
    return CardConversionResult(
      sourceName: sourceName,
      format: format,
      success: false,
      notes: [ConversionNote.error(message)],
    );
  }

  CardConversionResult copyWith({
    Map<String, dynamic>? characterData,
    List<Map<String, dynamic>>? worldBooks,
    List<String>? convertedFields,
    List<String>? unsupportedFields,
    List<ConversionNote>? notes,
    Map<String, List<int>>? embeddedImages,
  }) {
    return CardConversionResult(
      sourceName: sourceName,
      format: format,
      success: success,
      partial: partial,
      characterData: characterData ?? this.characterData,
      worldBooks: worldBooks ?? this.worldBooks,
      imageBytes: imageBytes,
      convertedFields: convertedFields ?? this.convertedFields,
      unsupportedFields: unsupportedFields ?? this.unsupportedFields,
      notes: notes ?? this.notes,
      embeddedImages: embeddedImages ?? this.embeddedImages,
    );
  }

  String get characterName =>
      (characterData?['name'] as String?)?.trim().isNotEmpty == true
          ? characterData!['name'] as String
          : '未命名角色';

  /// 输出文件名主干：沿用原始文件名（去掉扩展名），
  /// 这样 小灰.png 转出 小灰.llmchar.png，不受 AI 改名影响。
  String get outputBaseName {
    var n = sourceName.trim();
    // 去掉最后一个扩展名（.png / .json）
    final dot = n.lastIndexOf('.');
    if (dot > 0) n = n.substring(0, dot);
    return n.trim().isEmpty ? '未命名角色卡' : n;
  }

  Map<String, dynamic> toReportJson() => {
        'source': sourceName,
        'format': format.label,
        'success': success,
        'partial': partial,
        'character_name': success ? characterName : null,
        'converted_fields': convertedFields,
        'unsupported_fields': unsupportedFields,
        'world_book_count': worldBooks.length,
        'has_image': imageBytes != null,
        'notes': notes.map((e) => e.toJson()).toList(),
      };
}

/// 一批文件的转换结果汇总。
class BatchConversionReport {
  final List<CardConversionResult> results;
  final DateTime generatedAt;

  BatchConversionReport(this.results, {DateTime? generatedAt})
      : generatedAt = generatedAt ?? DateTime.now();

  int get total => results.length;
  int get successCount => results.where((r) => r.success).length;
  int get partialCount => results.where((r) => r.success && r.partial).length;
  int get failureCount => results.where((r) => !r.success).length;

  Map<String, dynamic> toJson() => {
        'generated_at': generatedAt.toIso8601String(),
        'app': 'LLM Project Converter',
        'summary': {
          'total': total,
          'success': successCount,
          'partial': partialCount,
          'failure': failureCount,
        },
        'results': results.map((e) => e.toReportJson()).toList(),
      };

  /// 生成人类可读的纯文本报告。
  String toPlainText() {
    final b = StringBuffer();
    b.writeln('LLM Project 角色卡转换报告');
    b.writeln('生成时间：${generatedAt.toIso8601String()}');
    b.writeln('总数：$total  成功：$successCount  '
        '其中降级：$partialCount  失败：$failureCount');
    b.writeln('=' * 48);
    for (final r in results) {
      b.writeln();
      b.writeln('文件：${r.sourceName}');
      b.writeln('格式：${r.format.label}');
      if (r.success) {
        b.writeln('角色：${r.characterName}');
        b.writeln('状态：${r.partial ? "成功（部分字段降级）" : "成功"}');
        if (r.convertedFields.isNotEmpty) {
          b.writeln('已转换：${r.convertedFields.join("、")}');
        }
        if (r.unsupportedFields.isNotEmpty) {
          b.writeln('未支持/降级：${r.unsupportedFields.join("、")}');
        }
        if (r.worldBooks.isNotEmpty) {
          b.writeln('内嵌世界书：${r.worldBooks.length} 本');
        }
      } else {
        b.writeln('状态：失败');
      }
      for (final n in r.notes) {
        final tag = switch (n.level) {
          ConversionNoteLevel.info => '提示',
          ConversionNoteLevel.warning => '注意',
          ConversionNoteLevel.error => '错误',
        };
        b.writeln('  [$tag] ${n.message}');
      }
    }
    return b.toString();
  }
}
