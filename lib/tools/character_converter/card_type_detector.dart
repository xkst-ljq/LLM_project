import 'api_service.dart';
import 'app_settings.dart';

/// 第0步：用 AI 判断卡类型（人物卡 / 系统卡）。
///
/// - 人物卡（character）：扮演单一具体角色。
/// - 系统卡（system）：扮演一个世界 / 系统 / 一群角色 / 剧情引擎，
///   {{char}} 不指代单一个体。
///
/// 未配置 AI 时不应调用（调用方默认按人物卡处理）。
class CardTypeDetector {
  /// 返回 'character' 或 'system'。判断失败时回退 'character'。
  static Future<String> detect(Map<String, dynamic> sourceJson) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) return 'character';

    final base = (sourceJson['data'] is Map)
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;

    String s(String k) => (base[k] ?? '').toString().trim();
    final userPrompt = '''
请判断下面这张角色卡属于哪一类，只回答一个词：character 或 system。

判定标准：
- character：扮演单一具体角色（一个人/一只生物），{{char}} 指代这一个个体。
- system：扮演一个世界、系统、剧情引擎，或一次包含多个角色；
  {{char}} 不指代单一个体（例如"你是一部动画里的所有角色""你是任务系统"）。

角色名：${s('name')}
描述：${s('description')}
${s('personality').isNotEmpty ? '性格：${s('personality')}' : ''}

只输出 character 或 system，不要解释。''';

    try {
      final raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: '你是角色卡分类助手，只输出 character 或 system。',
        userPrompt: userPrompt,
        temperature: 0.0,
      );
      final t = raw.toLowerCase();
      if (t.contains('system')) return 'system';
      return 'character';
    } catch (_) {
      return 'character';
    }
  }

  /// 第三步复核：判断当前选定的类型是否恰当。
  /// 返回它认为正确的类型（'character' / 'system'）。判断失败回退当前类型。
  static Future<String> recheck(
      Map<String, dynamic> sourceJson,
      String currentType,
      ) async {
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) return currentType;

    final base = (sourceJson['data'] is Map)
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;
    String s(String k) => (base[k] ?? '').toString().trim();

    final userPrompt = '''
这张角色卡当前被判定为：${currentType == 'system' ? 'system（系统卡）' : 'character（人物卡）'}。
请复核这个判定是否正确。

判定标准：
- character：扮演单一具体角色，{{char}} 指代一个个体。
- system：扮演一个世界/系统/剧情引擎，或一次包含多个角色，{{char}} 不指代单一个体。

角色名：${s('name')}
描述：${s('description')}

只输出最终正确的类型：character 或 system，不要解释。''';

    try {
      final raw = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: '你是角色卡分类复核助手，只输出 character 或 system。',
        userPrompt: userPrompt,
        temperature: 0.0,
      );
      final t = raw.toLowerCase();
      if (t.contains('system')) return 'system';
      if (t.contains('character')) return 'character';
      return currentType;
    } catch (_) {
      return currentType;
    }
  }
}
