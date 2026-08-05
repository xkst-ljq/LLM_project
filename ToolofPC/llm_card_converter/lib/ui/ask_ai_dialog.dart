import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_settings.dart';
import '../core/api_service.dart';

/// 全局保存的「询问 AI」对话历史：关闭对话框后仍保留，
/// 以便用户对照 AI 做的 UI 再提问。
final List<({String role, String text})> _persistedDialogue = [];

/// 「询问 AI」对话框：把本轮转译的完整上下文（prompt + 回复）喂给 AI，
/// 让用户持续追问「为什么这样设计、你知道什么、不知道什么」。
///
/// 这是诊断功能：通过对话让 AI 解释自己的设计决策与信息边界，
/// 帮助定位「AI 看起来傻」的根源。
class AskAiDialog extends StatefulWidget {
  /// 本轮转译 AI 收到的全部 prompt + 回复（AiTranscript.buildContext()）。
  final String contextText;
  const AskAiDialog({super.key, required this.contextText});

  @override
  State<AskAiDialog> createState() => _AskAiDialogState();
}

class _AskAiDialogState extends State<AskAiDialog> {
  final TextEditingController _input = TextEditingController();
  bool _asking = false;
  bool _showContext = false;

  /// 引用全局持久对话（关闭后不丢，重开继续）。
  List<({String role, String text})> get _messages => _persistedDialogue;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _input.text.trim();
    if (q.isEmpty || _asking) return;
    setState(() {
      _messages.add((role: 'user', text: q));
      _asking = true;
      _input.clear();
    });

    try {
      final cfg = await AppSettings.getApiConfig();
      if (!cfg.isComplete) throw StateError('未配置 AI');

      // 组装追问 prompt：本次转译完整上下文 + 对话历史 + 新问题
      final buf = StringBuffer()
        ..writeln('以下是你本次角色卡转译过程中「收到过的完整 prompt」和'
            '「你产出的完整回复」。请如实回答用户对你设计过程的追问。')
        ..writeln()
        ..writeln('【你的完整上下文】')
        ..writeln(widget.contextText)
        ..writeln()
        ..writeln('【对话历史】');
      for (final m in _messages) {
        buf.writeln('${m.role == 'user' ? '用户' : '你'}: ${m.text}');
      }
      buf.writeln();
      buf.writeln('请回答以上对话中「用户」最新的问题。要诚实、具体，'
          '基于你真正看到的信息回答；看不到就说「我没有看到这部分」。');

      final answer = await ApiService.chatComplete(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        systemPrompt: '你是这个角色卡转译工具的 AI 设计引擎。回答用户对你'
            '设计过程的追问，诚实说明你知道什么、不知道什么、为什么这么设计。',
        userPrompt: buf.toString(),
        temperature: 0.3,
      );
      if (!mounted) return;
      setState(() => _messages.add((role: 'ai', text: answer)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add((role: 'ai', text: '（追问失败：$e）')));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// 复制全部对话（含说话方），方便对照 UI 提问时引用。
  Future<void> _copyDialogue() async {
    final buf = StringBuffer();
    if (_messages.isEmpty) {
      buf.writeln('（尚无对话）');
    } else {
      for (final m in _messages) {
        final who = m.role == 'user' ? '用户' : 'AI';
        buf.writeln('【$who】');
        buf.writeln(m.text);
        buf.writeln();
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('全部对话已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 560,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('询问 AI 为什么这样设计',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _showContext = !_showContext),
                    child: Text(_showContext ? '隐藏上下文' : '查看上下文'),
                  ),
                  IconButton(
                    tooltip: '复制全部对话',
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    onPressed: _copyDialogue,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 上下文（可展开查看）
            if (_showContext)
              Container(
                height: 160,
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(widget.contextText,
                      style: const TextStyle(fontSize: 10, height: 1.3)),
                ),
              ),
            // 对话区
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length + (_asking ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 14, height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('AI 思考中…', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  }
                  final m = _messages[i];
                  final isUser = m.role == 'user';
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      constraints: const BoxConstraints(maxWidth: 480),
                      decoration: BoxDecoration(
                        color: isUser
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(m.text,
                          style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // 输入区
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_asking,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '问 AI：你为什么把 read_skin 建成空页？…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _asking ? null : _ask,
                    child: const Text('询问'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
