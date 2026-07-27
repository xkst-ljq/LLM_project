import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PromptPreviewData {
  final int userTurnCount;
  final bool injectedSummary;
  final bool injectedFullDetail;
  final int estimatedTokens;
  final String systemPrompt;

  /// 实际发送给模型的消息列表（含对话历史、PHI、结算格式约束、回合提醒）。
  ///
  /// 这些内容不在 [systemPrompt] 里，但确实会发出去。预览页必须完整展示，
  /// 否则作者无法核对真实请求——历史上因为只看 systemPrompt 而误判过问题。
  final List<Map<String, String>> messages;

  const PromptPreviewData({
    required this.userTurnCount,
    required this.injectedSummary,
    required this.injectedFullDetail,
    required this.estimatedTokens,
    required this.systemPrompt,
    this.messages = const [],
  });

  /// 对话历史之后追加的 system 消息（PHI / 结算格式约束等）。
  ///
  /// 判定方式：从末尾往前取连续的 system 消息。这些是「历史后注入」，
  /// 与开头的 systemPrompt 分开展示，便于确认强约束是否真的发出去了。
  List<Map<String, String>> get postHistorySystemMessages {
    final out = <Map<String, String>>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] != 'system') break;
      out.insert(0, messages[i]);
    }
    return out;
  }

  /// 对话历史部分（不含末尾的历史后注入）。
  List<Map<String, String>> get historyMessages {
    return messages.sublist(0, messages.length - postHistorySystemMessages.length);
  }

  String toFullText() {
    final buffer = StringBuffer();
    buffer.writeln('用户回合数：$userTurnCount');
    buffer.writeln('摘要设定：${injectedSummary ? '本轮注入' : '本轮不注入'}');
    buffer.writeln('完整设定：${injectedFullDetail ? '本轮注入' : '本轮不注入'}');
    buffer.writeln('估算 Tokens：$estimatedTokens');
    buffer.writeln('\n===== System Prompt =====\n');
    buffer.writeln(systemPrompt);

    final history = historyMessages;
    if (history.isNotEmpty) {
      buffer.writeln('\n===== 对话历史（${history.length} 条）=====\n');
      for (final msg in history) {
        buffer.writeln('[${msg['role']}]');
        buffer.writeln(msg['content'] ?? '');
        buffer.writeln();
      }
    }

    final phi = postHistorySystemMessages;
    if (phi.isNotEmpty) {
      buffer.writeln('\n===== 历史后注入（${phi.length} 条）=====\n');
      for (final msg in phi) {
        buffer.writeln(msg['content'] ?? '');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}

class PromptPreviewPage extends StatelessWidget {
  final PromptPreviewData data;

  const PromptPreviewPage({super.key, required this.data});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phi = data.postHistorySystemMessages;
    final history = data.historyMessages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt 预览'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all),
            onPressed: () => _copy(context, data.toFullText()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(context),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'System Prompt（开头）',
            content: data.systemPrompt,
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMessagesSection(
              context,
              title: '对话历史（${history.length} 条）',
              messages: history,
              showRole: true,
            ),
          ],
          if (phi.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMessagesSection(
              context,
              title: '历史后注入 · PHI（${phi.length} 条）',
              messages: phi,
              showRole: false,
              highlight: true,
              hint: '这些内容排在对话历史之后发送，'
                  '状态结算格式约束等强指令放在这里遵从度更高。',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('用户回合数：${data.userTurnCount}'),
          Text('摘要设定：${data.injectedSummary ? '本轮注入' : '本轮不注入'}'),
          Text('完整设定：${data.injectedFullDetail ? '本轮注入' : '本轮不注入'}'),
          Text('估算 Tokens：${data.estimatedTokens}'),
          Text('消息条数：${data.messages.length}'),
        ],
      ),
    );
  }

  Widget _buildMessagesSection(
    BuildContext context, {
    required String title,
    required List<Map<String, String>> messages,
    required bool showRole,
    bool highlight = false,
    String? hint,
  }) {
    final joined = messages
        .map((m) => showRole
            ? '[${m['role']}]\n${m['content'] ?? ''}'
            : (m['content'] ?? ''))
        .join('\n\n');

    return Container(
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF8E1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFFFFECB3) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: highlight
                  ? const Color(0xFFFFECB3)
                  : Colors.grey.shade200,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copy(context, joined),
                ),
              ],
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                hint,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8D6E00),
                  height: 1.35,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              joined.isEmpty ? '暂无内容' : joined,
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, {
        required String title,
        required String content,
      }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copy(context, content),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              content.isEmpty ? '暂无内容' : content,
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
