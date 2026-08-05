/// 一次 AI 调用的完整记录（prompt + 回复）。
class AiTurnRecord {
  final String stage;
  final String prompt;
  final String reply;
  const AiTurnRecord({required this.stage, required this.prompt, required this.reply});
}

/// 本轮转译的 AI 会话记录收集器（静态，供 UI 在转译后「询问 AI」）。
///
/// 记录每次 AI 调用的「阶段 + 完整 prompt（系统+用户） + 完整回复」，
/// 构成 AI 的完整上下文。UI 在转译完成后读取它，把上下文喂回 AI
/// 以追问「为什么这样设计、你知道什么、不知道什么」。
class AiTranscript {
  AiTranscript._();

  static final List<AiTurnRecord> turns = [];

  /// 新一轮转译开始时清空。
  static void clear() => turns.clear();

  /// 记录一次 AI 调用。默认保留最近 N 轮，避免无限增长。
  static void add(String stage, String prompt, String reply) {
    turns.add(AiTurnRecord(stage: stage, prompt: prompt, reply: reply));
    if (turns.length > 20) {
      turns.removeAt(0);
    }
  }

  /// 组装成「AI 本次看到的全部上下文」文本，供追问时喂回。
  static String buildContext() {
    if (turns.isEmpty) return '';
    final buf = StringBuffer();
    for (final t in turns) {
      buf.writeln('========== 阶段：${t.stage} ==========');
      buf.writeln('【AI 收到的 prompt】');
      buf.writeln(t.prompt);
      buf.writeln();
      buf.writeln('【AI 的输出】');
      buf.writeln(t.reply);
      buf.writeln();
    }
    return buf.toString();
  }
}
