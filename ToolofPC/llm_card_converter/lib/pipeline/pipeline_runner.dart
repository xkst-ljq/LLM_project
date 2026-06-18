import '../core/app_settings.dart';
import '../core/card_type_detector.dart';
import '../core/image_embed_service.dart';
import 'pipeline.dart';

/// 把"完整三步流水线 + 类型判断/复核 + 自动重跑"封装成可复用逻辑。
///
/// 单张工作区与批量转译共用，避免重复实现。
/// 通过 [onLog] / [onProgress] 回调上报进度，UI 自行展示。
class PipelineRunner {
  final ConversionPipeline pipeline;

  /// 是否启用 AI（批量时可整体关闭，只跑规则转译）。
  final bool useAi;

  /// 日志回调。
  final void Function(String line)? onLog;

  /// 进度回调（0~1）。
  final void Function(double progress)? onProgress;

  PipelineRunner({
    required this.pipeline,
    this.useAi = true,
    this.onLog,
    this.onProgress,
  });

  void _log(String s) => onLog?.call(s);
  void _progress(double p) => onProgress?.call(p);
  String _typeLabel(String t) => t == 'system' ? '系统卡' : '人物卡';

  /// 完整跑一张卡。返回是否第一步成功（成功即可保存）。
  Future<bool> run(CardWorkItem item) async {
    _log('${item.sourceName} 转译开始：');

    // 步骤一：规则转译
    _log('步骤一：规则转译');
    final rule = pipeline.runRuleStage(item);
    if (!rule.success) {
      _log('  失败：${rule.notes.isNotEmpty ? rule.notes.first.message : "未知错误"}');
      _progress(1);
      return false;
    }
    _log('  已完成');
    _progress(1 / 3);

    final apiCfg = await AppSettings.getApiConfig();
    final aiOn = useAi && apiCfg.isComplete;

    // 步骤零：AI 判断卡类型
    if (aiOn && item.sourceJson != null) {
      _log('判断卡类型…');
      final type = await CardTypeDetector.detect(item.sourceJson!);
      if (type != item.cardType) {
        item.cardType = type;
        pipeline.runRuleStage(item);
      }
      _log('  类型：${_typeLabel(item.cardType)}');
    }

    await _runAiStages(item, apiCfg, aiOn: aiOn, allowRetry: true);

    // 后处理：下载开场白 / 描述里的外链图片并内嵌成卡内资产（本地优先）。
    final cur = item.current;
    if (cur != null && cur.characterData != null) {
      _log('图片内嵌：扫描开场白外链图片…');
      try {
        final embedded = await ImageEmbedService.process(cur);
        item.updateCurrentResult(embedded);
        final n = embedded.embeddedImages.length;
        _log(n > 0 ? '  已内嵌 $n 张图片' : '  无可内嵌的外链图片');
      } catch (e) {
        _log('  跳过（图片内嵌失败）：$e');
      }
    }

    _progress(1);
    _log('全部完成');
    return true;
  }

  Future<void> _runAiStages(
    CardWorkItem item,
    ApiConfig apiCfg, {
    required bool aiOn,
    required bool allowRetry,
  }) async {
    // 步骤二：AI 智能归类
    _log('步骤二：AI 智能归类（${_typeLabel(item.cardType)}）');
    if (!aiOn) {
      _log(useAi ? '  跳过（未配置 AI）' : '  跳过（已关闭 AI）');
    } else {
      _log('  请求中…（模型：${apiCfg.model}）');
      try {
        await pipeline.runAiClassifyStage(item);
        _log('  已完成');
      } catch (e) {
        _log('  失败，已保留规则转译结果：$e');
      }
    }
    _progress(2 / 3);

    // 步骤三：检查精修 + 类型复核
    _log('步骤三：检查精修');
    if (!aiOn) {
      _log('  跳过');
      return;
    }

    if (allowRetry && item.sourceJson != null) {
      final rechecked =
          await CardTypeDetector.recheck(item.sourceJson!, item.cardType);
      if (rechecked != item.cardType) {
        _log('  类型复核：应为${_typeLabel(rechecked)}，按新类型重跑…');
        item.cardType = rechecked;
        pipeline.runRuleStage(item);
        _progress(1 / 3);
        await _runAiStages(item, apiCfg, aiOn: aiOn, allowRetry: false);
        return;
      }
      _log('  类型复核：${_typeLabel(item.cardType)}，正确');
    }

    _log('  审计中…');
    try {
      final issues = await pipeline.runRefineStage(item);
      _log(issues.isEmpty
          ? '  完成：未发现明显问题'
          : '  完成：发现 ${issues.length} 处可关注项');
    } catch (e) {
      _log('  跳过（审计失败）：$e');
    }
  }
}
