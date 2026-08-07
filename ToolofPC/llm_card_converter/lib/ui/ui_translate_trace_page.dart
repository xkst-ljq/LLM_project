import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/ui_translate_trace.dart';

/// AI UI 转译流程实时观察器。
///
/// 测试工具：转译进行中即可打开，实时刷新每一步。
/// - 右边：我们发给 AI 的 prompt（system/user 消息）
/// - 左边：AI 的回复（含原始输出 / 流式 chunk / 思考链 / 诊断）
///
/// 传入 [UiTranslateTraceBuilder]（实时可监听）；页面监听它，每次
/// 步骤开始 / chunk 到达 / 完成都自动刷新。
class UiTranslateTracePage extends StatefulWidget {
  final UiTranslateTraceBuilder traceBuilder;

  const UiTranslateTracePage({super.key, required this.traceBuilder});

  @override
  State<UiTranslateTracePage> createState() => _UiTranslateTracePageState();
}

class _UiTranslateTracePageState extends State<UiTranslateTracePage> {
  VoidCallback? _cancelListener;

  @override
  void initState() {
    super.initState();
    _cancelListener = widget.traceBuilder.addListener(_onTraceChanged);
  }

  void _onTraceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancelListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trace = widget.traceBuilder;
    final steps = trace.steps;
    final theme = Theme.of(context);
    final elapsed = DateTime.now().difference(trace.startedAt).inSeconds;

    return Scaffold(
      appBar: AppBar(
        title: Text('转译过程 · ${trace.cardName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${steps.length} 步 · ${elapsed}s',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: steps.isEmpty
          ? const Center(child: Text('转译进行中，等待第一步请求…'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: steps.length,
              itemBuilder: (context, index) =>
                  _StepCard(step: steps[index]),
            ),
    );
  }
}

/// 单个转译步骤。
///
/// 布局：顶部是步骤头（名称 / 耗时 / 状态），下面左右分栏——
/// 右侧 Prompt（我们发的），左侧 AI 回复。
class _StepCard extends StatelessWidget {
  final TraceStep step;

  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDeterministic = step.stage == 'deterministic';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 步骤头 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  _stageIcon(step.stage),
                  size: 18,
                  color: hasError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _statusLabel(step),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDeterministic
                        ? theme.colorScheme.tertiary
                        : (hasError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${step.elapsedMs ~/ 1000}s',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── 内容 ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: isDeterministic
                ? _buildDeterministic(theme)
                : _buildRequestReply(theme),
          ),
        ],
      ),
    );
  }

  String _statusLabel(TraceStep step) {
    if (step.stage == 'deterministic') return '确定性生成';
    if (step.error != null) return '失败';
    if (!step.parsedOk && step.rawReply.isNotEmpty) return '解析失败';
    if (step.parsedOk) return '成功';
    if (step.finishedAt == null) return '进行中…';
    return '完成';
  }

  Widget _buildDeterministic(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '程序确定性生成（未请求 AI）',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(height: 6),
        if (step.parsedJson != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(step.parsedJson),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          )
        else
          Text(
            '（无输出）',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        _diagnosticsSection(theme),
      ],
    );
  }

  Widget _buildRequestReply(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 左侧：AI 回复 ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 回复 · ${step.rawReply.runes.length} 字符'
                    '${step.streamingChunks.isNotEmpty ? ' · ${step.streamingChunks.length} chunks' : ''}'
                    '${step.gotDone ? ' · [DONE]' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (step.rawReply.isNotEmpty)
                    _replyBox(theme, step.rawReply)
                  else if (step.error != null)
                    Text(
                      '（请求失败）',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    Text(
                      '（等待回复…）',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── 右侧：Prompt ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prompt · ${_requestChars(step)} 字符',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (step.requestMessages.isNotEmpty)
                    _promptBox(theme, step.requestMessages)
                  else
                    Text(
                      '（未发起请求）',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
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
          const SizedBox(height: 4),
          _replyBox(theme, step.reasoningContent),
        ],
        _diagnosticsSection(theme),
      ],
    );
  }

  int _requestChars(TraceStep step) => step.requestMessages.fold<int>(
        0,
        (sum, m) => sum + m.content.runes.length,
      );

  Widget _replyBox(ThemeData theme, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SelectableText(
        content,
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }

  Widget _promptBox(ThemeData theme, List<TraceMessage> messages) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages) ...[
            if (message != messages.first) const Divider(height: 8),
            Text(
              '[${message.role}]',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              message.content,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _diagnosticsSection(ThemeData theme) {
    if (step.diagnostics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _SectionTitle(title: '诊断'),
        const SizedBox(height: 4),
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
    );
  }

  static IconData _stageIcon(String stage) {
    switch (stage) {
      case 'single':
        return Icons.auto_awesome;
      case 'repair':
        return Icons.healing;
      case 'deterministic':
        return Icons.auto_fix_high;
      default:
        return Icons.settings;
    }
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
