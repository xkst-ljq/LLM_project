import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PromptPreviewData {
  final int userTurnCount;
  final bool injectedSummary;
  final bool injectedFullDetail;
  final int estimatedTokens;
  final String systemPrompt;

  /// 保留字段用于兼容 ChatPage 现有构造逻辑，但预览页不展示 messages。
  final List<Map<String, String>> messages;

  const PromptPreviewData({
    required this.userTurnCount,
    required this.injectedSummary,
    required this.injectedFullDetail,
    required this.estimatedTokens,
    required this.systemPrompt,
    this.messages = const [],
  });

  String toFullText() {
    final buffer = StringBuffer();
    buffer.writeln('用户回合数：$userTurnCount');
    buffer.writeln('摘要设定：${injectedSummary ? '本轮注入' : '本轮不注入'}');
    buffer.writeln('完整设定：${injectedFullDetail ? '本轮注入' : '本轮不注入'}');
    buffer.writeln('估算 Tokens：$estimatedTokens');
    buffer.writeln('\n===== System Prompt =====\n');
    buffer.writeln(systemPrompt);
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
            title: 'System Prompt',
            content: data.systemPrompt,
          ),
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
