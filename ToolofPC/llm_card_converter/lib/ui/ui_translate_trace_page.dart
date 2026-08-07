import 'package:flutter/material.dart';

import '../core/ui_translate_trace.dart';

/// AI UI 转译流程观察器。
///
/// 以聊天风格展示一次转译的完整过程：右侧是我们发出的 prompt，
/// 左侧是 AI 的回复。每个步骤可展开查看请求参数、流式 chunk、
/// 诊断信息、思考链与解析结果。
///
/// 定位是「完整的流程观察用」，不加交互开关——成功验证后这段能力
/// 可保留或封装，不影响主流程。
class UiTranslateTracePage extends StatelessWidget {
  final UiTranslateTrace trace;

  const UiTranslateTracePage({super.key, required this.trace});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('转译过程观察 · ${trace.cardName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${trace.elapsedMs ~/ 1000}s · ${trace.hasFailure ? '有失败' : '正常'}',
                style: TextStyle(
                  fontSize: 13,
                  color: trace.hasFailure
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: trace.steps.isEmpty
          ? const Center(child: Text('没有记录到任何转译步骤。'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: trace.steps.length,
              itemBuilder: (context, index) => _StepCard(step: trace.steps[index]),
            ),
    );
  }
}

/// 单个转译步骤的卡片。
class _StepCard extends StatelessWidget {
  final TraceStep step;

  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = step.error != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasError
              ? theme.colorScheme.error.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Icon(
              _stageIcon(step.stage),
              size: 18,
              color: hasError ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                step.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${step.elapsedMs ~/ 1000}s',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        children: [
          // 请求消息（右侧 = 我们发的 prompt）
          for (final message in step.requestMessages)
            _MessageBubble(
              role: message.role,
              content: message.content,
              maxHeight: 220,
            ),
          const Divider(height: 1),
          // AI 回复（左侧）
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 回复 · ${step.rawReply.runes.length} 字符'
                  '${step.gotDone ? ' · [DONE]' : ''}'
                  '${step.streamingChunks.isNotEmpty ? ' · ${step.streamingChunks.length} chunks' : ''}'
                  '${step.parsedOk ? ' · 解析成功' : ''}'
                  '${step.parseError != null ? ' · 解析失败' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: step.parsedOk
                        ? theme.colorScheme.primary
                        : (step.error != null
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 6),
                if (step.rawReply.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      step.rawReply,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  )
                else
                  Text(
                    '（空回复）',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (step.error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '错误：${step.error}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (step.reasoningContent.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionTitle(title: '思考链'),
                  SelectableText(
                    step.reasoningContent,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
                if (step.diagnostics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionTitle(title: '诊断'),
                  for (final line in step.diagnostics)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _stageIcon(String stage) {
    switch (stage) {
      case 'scout':
        return Icons.radar;
      case 'detailer':
        return Icons.construction;
      case 'repair':
        return Icons.healing;
      case 'deterministic':
        return Icons.auto_fix_high;
      default:
        return Icons.settings;
    }
  }
}

/// 一条消息气泡：role=user/system 靠右（我们发的），assistant 靠左（AI 回复）。
class _MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final double maxHeight;

  const _MessageBubble({
    required this.role,
    required this.content,
    this.maxHeight = 220,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = role == 'user';
    final bg = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final name = isUser ? 'Prompt' : '系统';
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
