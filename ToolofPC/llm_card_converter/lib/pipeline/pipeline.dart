import 'dart:convert';

import '../core/conversion_models.dart';
import '../core/conversion_service.dart';

/// 三步转译流水线（纯 Dart，平台无关）。
///
/// 设计目标（PC 工作台）：
///   1. 把转译拆成 3 个独立阶段，每个阶段可单独运行 / 重跑；
///   2. 保留每个阶段的中间结果，便于"原文 vs 各步结果"对照预览；
///   3. 每个阶段的产物都可被用户手动修改后，作为下一阶段的输入；
///   4. 不依赖 UI / 网络实现细节：AI 阶段通过注入的回调完成，方便替换/测试。
///
/// 阶段：
///   - stage1 规则转译：正则/字段映射（已实现，离线）
///   - stage2 AI 智能归类：把 description 等自由文本拆分归位（需外部 AI 回调）
///   - stage3 检查精修：审计（漏转/新增/重复/归类建议），产出问题清单

/// 流水线阶段标识。
enum PipelineStage { rule, aiClassify, refine }

extension PipelineStageLabel on PipelineStage {
  String get label => switch (this) {
        PipelineStage.rule => '规则转译',
        PipelineStage.aiClassify => 'AI 智能归类',
        PipelineStage.refine => '检查精修',
      };
}

/// 一张角色卡的"工作态"——承载原文与三步中间结果。
///
/// [card] 始终表示"当前最新结果"（最后成功阶段的产物，或用户手动修改后的版本）。
/// 各阶段快照保存在 [stageOutputs]，供对照与回退重跑使用。
class CardWorkItem {
  /// 源文件名（显示/命名用）。
  final String sourceName;

  /// 源文件原始字节（PNG/JSON）。重跑 stage1 时需要。
  final List<int> sourceBytes;

  /// 解析出的源角色 JSON（用于"原文预览"与 AI 阶段引用）。
  /// stage1 运行后填充。
  Map<String, dynamic>? sourceJson;

  /// 各阶段输出快照：stage -> 该阶段产出的卡。
  final Map<PipelineStage, CardConversionResult> stageOutputs = {};

  /// 各阶段状态。
  final Map<PipelineStage, StageStatus> stageStatus = {
    PipelineStage.rule: StageStatus.pending,
    PipelineStage.aiClassify: StageStatus.pending,
    PipelineStage.refine: StageStatus.pending,
  };

  /// 第三步产出的审计问题清单（不改内容，只给建议）。
  List<RefineIssue> refineIssues = [];

  /// 卡类型：'character' 人物卡 / 'system' 系统卡。
  /// 默认人物卡；配置 AI 时由第0步判定，第三步可纠正后重跑。
  String cardType;

  CardWorkItem({
    required this.sourceName,
    required this.sourceBytes,
    this.sourceJson,
    this.cardType = 'character',
  });

  /// 当前最新结果：取最后一个已完成阶段的输出。
  CardConversionResult? get current {
    for (final stage in const [
      PipelineStage.refine,
      PipelineStage.aiClassify,
      PipelineStage.rule,
    ]) {
      final out = stageOutputs[stage];
      if (out != null) return out;
    }
    return null;
  }

  /// 当前最新结果所属的阶段（与 [current] 对应）。
  PipelineStage? get currentStage {
    for (final stage in const [
      PipelineStage.refine,
      PipelineStage.aiClassify,
      PipelineStage.rule,
    ]) {
      if (stageOutputs[stage] != null) return stage;
    }
    return null;
  }

  /// 用户手动修改某阶段产物后写回（覆盖该阶段快照）。
  void overrideStageOutput(PipelineStage stage, CardConversionResult edited) {
    stageOutputs[stage] = edited;
    stageStatus[stage] = StageStatus.editedByUser;
  }

  /// 系统级更新当前阶段产物（如图片下载内嵌后处理），不改变阶段状态标记。
  void updateCurrentResult(CardConversionResult updated) {
    final stage = currentStage;
    if (stage != null) stageOutputs[stage] = updated;
  }
}

enum StageStatus { pending, running, done, editedByUser, failed, skipped }

/// 第三步审计问题。
class RefineIssue {
  final RefineIssueType type;

  /// 涉及的目标字段（如 psychology.personality / background.origin / 世界书条目）。
  final List<String> fields;

  /// 相关文本片段。
  final String text;

  /// 给用户的可读说明 + 建议。
  final String suggestion;

  /// 置信度 0~1（AI 给出，低置信度交用户确认）。
  final double confidence;

  /// 是否已被用户处理（应用/忽略）。
  RefineResolution resolution;

  RefineIssue({
    required this.type,
    required this.fields,
    required this.text,
    required this.suggestion,
    this.confidence = 0.0,
    this.resolution = RefineResolution.pending,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'fields': fields,
        'text': text,
        'suggestion': suggestion,
        'confidence': confidence,
        'resolution': resolution.name,
      };
}

enum RefineIssueType {
  duplicate, // 重复归类
  missing, // 疑似漏转
  added, // 疑似新增（幻觉）
  misclassified, // 字段归类建议
}

enum RefineResolution { pending, applied, ignored }

/// AI 归类回调：输入"规则转译结果 + 源 JSON"，输出"重新归类后的卡"。
///
/// 由平台层（PC UI）注入具体实现（调用用户配置的 OpenAI 兼容 API）。
/// 纯 Dart 内核不绑定任何网络库，便于测试与替换。
typedef AiClassifyFn = Future<CardConversionResult> Function(
  CardConversionResult ruleResult,
  Map<String, dynamic> sourceJson,
);

/// AI 精修回调：输入"当前卡 + 源 JSON"，输出"问题清单"。
typedef AiRefineFn = Future<List<RefineIssue>> Function(
  CardConversionResult current,
  Map<String, dynamic> sourceJson,
);

/// 流水线编排器。每个方法只跑一个阶段，可被 UI 单独触发/重跑。
class ConversionPipeline {
  /// 第二步实现（可空：未配置 AI 时该步不可用）。
  final AiClassifyFn? aiClassify;

  /// 第三步实现（可空）。
  final AiRefineFn? aiRefine;

  ConversionPipeline({this.aiClassify, this.aiRefine});

  /// 从字节创建工作项（不立即转换）。
  CardWorkItem createItem(String sourceName, List<int> bytes) {
    return CardWorkItem(sourceName: sourceName, sourceBytes: bytes);
  }

  /// 第一步：规则转译。可重复调用（重跑）。
  CardConversionResult runRuleStage(CardWorkItem item) {
    item.stageStatus[PipelineStage.rule] = StageStatus.running;
    try {
      final result = CharacterConversionService.convertBytes(
        item.sourceBytes,
        sourceName: item.sourceName,
        cardType: item.cardType,
      );
      item.stageOutputs[PipelineStage.rule] = result;
      item.stageStatus[PipelineStage.rule] =
          result.success ? StageStatus.done : StageStatus.failed;

      // 记录源 JSON（从 raw 条目里取，便于后续 AI 阶段引用）
      item.sourceJson ??= _extractSourceJson(result);
      return result;
    } catch (e) {
      item.stageStatus[PipelineStage.rule] = StageStatus.failed;
      final fail = CardConversionResult.failure(
        item.sourceName,
        ThirdPartyCardFormat.unknown,
        '规则转译异常：$e',
      );
      item.stageOutputs[PipelineStage.rule] = fail;
      return fail;
    }
  }

  /// 第二步：AI 智能归类。基于第一步（或用户修改后的第一步）产物。可重跑。
  Future<CardConversionResult> runAiClassifyStage(CardWorkItem item) async {
    final fn = aiClassify;
    if (fn == null) {
      throw StateError('未配置 AI 归类实现');
    }
    final base = item.stageOutputs[PipelineStage.rule];
    if (base == null || !base.success) {
      throw StateError('请先成功完成第一步（规则转译）');
    }
    final src = item.sourceJson ?? _extractSourceJson(base) ?? const {};

    item.stageStatus[PipelineStage.aiClassify] = StageStatus.running;
    try {
      final result = await fn(base, src);
      item.stageOutputs[PipelineStage.aiClassify] = result;
      item.stageStatus[PipelineStage.aiClassify] =
          result.success ? StageStatus.done : StageStatus.failed;
      return result;
    } catch (e) {
      item.stageStatus[PipelineStage.aiClassify] = StageStatus.failed;
      rethrow;
    }
  }

  /// 第三步：检查精修。基于"当前最新结果"。可重跑。
  Future<List<RefineIssue>> runRefineStage(CardWorkItem item) async {
    final fn = aiRefine;
    if (fn == null) {
      throw StateError('未配置 AI 精修实现');
    }
    final current = item.current;
    if (current == null || !current.success) {
      throw StateError('没有可供检查的转译结果');
    }
    final src = item.sourceJson ?? _extractSourceJson(current) ?? const {};

    item.stageStatus[PipelineStage.refine] = StageStatus.running;
    try {
      final issues = await fn(current, src);
      item.refineIssues = issues;
      item.stageStatus[PipelineStage.refine] = StageStatus.done;
      return issues;
    } catch (e) {
      item.stageStatus[PipelineStage.refine] = StageStatus.failed;
      rethrow;
    }
  }

  /// 一键跑完可用阶段（批量场景用）。AI 阶段缺失则自动跳过。
  Future<void> runAll(CardWorkItem item) async {
    final rule = runRuleStage(item);
    if (!rule.success) return;
    if (aiClassify != null) {
      try {
        await runAiClassifyStage(item);
      } catch (_) {
        item.stageStatus[PipelineStage.aiClassify] = StageStatus.skipped;
      }
    } else {
      item.stageStatus[PipelineStage.aiClassify] = StageStatus.skipped;
    }
    if (aiRefine != null) {
      try {
        await runRefineStage(item);
      } catch (_) {
        item.stageStatus[PipelineStage.refine] = StageStatus.skipped;
      }
    } else {
      item.stageStatus[PipelineStage.refine] = StageStatus.skipped;
    }
  }

  /// 从规则转译结果里取回原始第三方 JSON（mapper 会把它存进禁用条目 tp_raw）。
  Map<String, dynamic>? _extractSourceJson(CardConversionResult result) {
    final data = result.characterData;
    if (data == null) return null;
    try {
      final entries = jsonDecode(data['entries_json'] as String? ?? '[]') as List;
      for (final e in entries) {
        if (e is Map && e['id'] == 'tp_raw') {
          final content = e['content'] as String? ?? '';
          final parsed = jsonDecode(content);
          if (parsed is Map<String, dynamic>) return parsed;
          if (parsed is Map) return Map<String, dynamic>.from(parsed);
        }
      }
    } catch (_) {}
    return null;
  }
}
