import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ai_classifier.dart';
import '../core/ai_refiner.dart';
import '../core/api_service.dart';
import '../core/app_settings.dart';
import '../core/conversion_writer.dart';
import '../core/history_service.dart';
import '../core/ui_understanding/ui_engine_knowledge_service.dart';
import '../pipeline/pipeline.dart';
import '../pipeline/pipeline_runner.dart';
import 'card_preview.dart';
import 'compare_page.dart';
import 'entry_editor_page.dart';
import 'assembly_preview.dart';

/// 待转译文件项（主页选择 → 工作区转译）。
class PickedCard {
  final String name;
  final List<int> bytes;
  const PickedCard(this.name, this.bytes);
}

enum _WorkStatus { waiting, running, done, failed }

class _WorkItem {
  final PickedCard card;
  final CardWorkItem work;
  _WorkStatus status = _WorkStatus.waiting;
  String? error;
  bool saved = false;
  double progress = 0; // 单卡进度 0~1
  Set<String> highlightIds = {};
  String? historyId; // 对应的历史记录 id

  /// 预览区当前看的是文本还是 UI。
  /// 逐卡记忆：批量转译时挨个展开查看，不该被别的卡重置。
  bool showUiPreview = false;

  /// 与“转译 AI”的追问对话。只保存作者主动发问与 AI 回复；
  /// UI 理解阶段的隐藏上下文在 [work.uiAiConversationContext]。
  final List<_AiChatTurn> aiChatTurns = [];

  _WorkItem(this.card, this.work);
}

class _AiChatTurn {
  final String role; // user / assistant
  final String content;

  const _AiChatTurn({
    required this.role,
    required this.content,
  });
}

/// 统一工作区：处理 1~N 张卡。逐张串行转译，列表展示，可展开看预览、编辑、比对。
class WorkspacePage extends StatefulWidget {
  final List<PickedCard> cards;
  const WorkspacePage({super.key, required this.cards});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final ConversionPipeline _pipeline;
  final List<_WorkItem> _items = [];
  final List<String> _log = [];

  bool _running = false;
  int _doneCount = 0;
  int _runningIndex = 0;
  int? _expanded; // 当前展开的卡片索引

  @override
  void initState() {
    super.initState();
    _pipeline = ConversionPipeline(
      aiClassify: AiClassifier.classify,
      aiRefine: AiRefiner.refine,
    );
    for (final c in widget.cards) {
      _items.add(_WorkItem(c, _pipeline.createItem(c.name, c.bytes)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _doneCount = 0;
      _log.clear();
    });

    for (var i = 0; i < _items.length; i++) {
      if (!mounted) return;
      final item = _items[i];
      setState(() {
        _runningIndex = i;
        _expanded = i; // 正在转的自动展开
        item.status = _WorkStatus.running;
        item.progress = 0;
      });

      final runner = PipelineRunner(
        pipeline: _pipeline,
        useAi: true,
        onLog: _addLog,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => item.progress = p);
        },
      );

      try {
        final ok = await runner.run(item.work);
        item.status = ok ? _WorkStatus.done : _WorkStatus.failed;
        if (!ok) {
          item.error =
              item.work.current?.notes.map((e) => e.message).join('；');
        }
      } catch (e) {
        item.status = _WorkStatus.failed;
        item.error = '$e';
      }

      // 记一条历史（成功/失败 + 未保存）
      try {
        final success = item.status == _WorkStatus.done;
        item.historyId = await HistoryService.add(
          name: success
              ? (item.work.current?.characterName ?? item.card.name)
              : item.card.name,
          success: success,
          imageBytes: item.work.current?.imageBytes,
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        item.progress = 1;
        _doneCount++;
      });
    }

    if (mounted) setState(() => _running = false);
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  int get _successCount =>
      _items.where((e) => e.status == _WorkStatus.done).length;

  _WorkItem? get _chatTargetItem {
    if (_expanded != null && _expanded! >= 0 && _expanded! < _items.length) {
      final item = _items[_expanded!];
      if (item.work.uiAiConversationContext.isNotEmpty) return item;
    }
    for (final item in _items.reversed) {
      if (item.work.uiAiConversationContext.isNotEmpty) return item;
    }
    return null;
  }

  double get _overallProgress {
    if (_items.isEmpty) return 0;
    return (_doneCount + (_running ? _items[_runningIndex].progress : 0))
        .clamp(0, _items.length) /
        _items.length;
  }

  // ---------------- 保存 ----------------

  Future<void> _finish() async {
    if (_successCount == 0) return;
    var dir = await AppSettings.getOutputDir();
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存位置（将作为默认位置记住）',
      );
      if (picked == null) return;
      dir = picked;
      await AppSettings.setOutputDir(dir);
    }

    final outDir = Directory(dir);
    var ok = 0, fail = 0;
    for (final item in _items) {
      final r = item.work.current;
      if (item.status != _WorkStatus.done || r == null || !r.success) continue;
      try {
        File file;
        if (r.imageBytes != null && r.imageBytes!.isNotEmpty) {
          file = await ConversionWriter.writeLlmCharPng(r, outputDir: outDir);
        } else {
          file = await ConversionWriter.writeLlmCard(r, outputDir: outDir);
        }
        item.saved = true;
        ok++;
        // 更新历史为「已保存」+ 路径
        if (item.historyId != null) {
          await HistoryService.markSaved(item.historyId!, file.path);
        }
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {});
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存完成'),
        content: Text('成功保存 $ok 张${fail > 0 ? '，失败 $fail 张' : ''}。\n位置：$dir'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // 回主页
            },
            child: const Text('返回主页'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  // ---------------- 编辑 ----------------

  Future<void> _editItem(_WorkItem item) async {
    final result = item.work.current;
    final stage = item.work.currentStage;
    if (result == null || result.characterData == null || stage == null) return;
    final entriesJson =
        result.characterData!['entries_json'] as String? ?? '[]';

    final edited = await showGeneralDialog<(String, Set<String>)>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '编辑条目',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => EntryEditorPage(entriesJson: entriesJson),
      transitionBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
    if (edited == null) return;
    final (newJson, changedIds) = edited;
    final newData = Map<String, dynamic>.from(result.characterData!);
    newData['entries_json'] = newJson;
    item.work.overrideStageOutput(stage, result.copyWith(characterData: newData));
    setState(() => item.highlightIds = changedIds);
  }

  @override
  Widget build(BuildContext context) {
    final allDone = !_running;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_items.length == 1
            ? '转译'
            : '批量转译（${_items.length} 张）'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 300, child: _logPanel()),
          const VerticalDivider(width: 1),
          Expanded(child: _cardListPanel()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: (allDone && _successCount > 0) ? _finish : null,
                child: Text('完成并保存（$_successCount）'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 长进度条：整体
          const Text('整体进度', style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: _overallProgress, minHeight: 10),
          ),
          const SizedBox(height: 2),
          Text(
            _running ? '转译中… $_doneCount / ${_items.length}'
                : '完成：成功 $_successCount / ${_items.length}',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          // 短进度条：当前卡
          const Text('当前卡片', style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _running ? _items[_runningIndex].progress : 1,
              minHeight: 8,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('简短日志：',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final line in _log)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(line,
                            style: const TextStyle(fontSize: 12, height: 1.4)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _aiChatButton(),
        ],
      ),
    );
  }

  Widget _aiChatButton() {
    final item = _chatTargetItem;
    if (_running || item == null) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.forum_outlined, size: 18),
        label: Text(_running ? '等待转译完成后可追问 AI' : '暂无 AI UI 上下文'),
      );
    }
    return FilledButton.icon(
      onPressed: () => _openAiChat(item),
      icon: const Icon(Icons.forum_outlined, size: 18),
      label: const Text('与转译 AI 对话'),
    );
  }

  Future<void> _openAiChat(_WorkItem item) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AiDebugChatDialog(
        item: item,
        onRetryUi: () => _retryAiUiStage(item),
      ),
    );
    if (!mounted) return;
    // 对话保存在 item 内，关闭弹窗不清空；刷新一下按钮/预览状态。
    setState(() {});
  }

  Widget _cardListPanel() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, i) => _cardTile(i),
    );
  }

  Widget _cardTile(int i) {
    final item = _items[i];
    final expanded = _expanded == i;
    final result = item.work.current;

    final (icon, color, label) = switch (item.status) {
      _WorkStatus.waiting => (Icons.schedule, Colors.black38, '等待'),
      _WorkStatus.running => (Icons.autorenew, Colors.blue, '转译中'),
      _WorkStatus.done => (Icons.check_circle, Colors.green, '完成'),
      _WorkStatus.failed => (Icons.error_outline, Colors.red, '失败'),
    };
    final title = item.status == _WorkStatus.done
        ? (result?.characterName ?? item.card.name)
        : item.card.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          // 栏目头
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = expanded ? null : i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          item.status == _WorkStatus.failed
                              ? (item.error ?? '失败')
                              : item.card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  if (item.saved)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.save, size: 14, color: Colors.green),
                    ),
                  Text(label,
                      style: TextStyle(fontSize: 11, color: color)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.black45),
                ],
              ),
            ),
          ),
          // 展开内容：预览 + 编辑/比对
          if (expanded)
            SizedBox(
              height: 420,
              child: Column(
                children: [
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _previewTabs(item),
                              Expanded(
                                child: item.showUiPreview
                                    // UI 预览用的是主 App 同一套渲染引擎
                                    // （packages/llm_ui_engine），
                                    // 所以这里看到的就是玩家实际看到的。
                                    ? AssemblyPreview(
                                        characterData: result?.characterData,
                                        emptyHint: item.status ==
                                                _WorkStatus.running
                                            ? '转译中…'
                                            : '这张卡没有 UI',
                                      )
                                    : CardPreview(
                                        result: result,
                                        highlightEntryIds: item.highlightIds,
                                        placeholder:
                                            item.status == _WorkStatus.running
                                                ? '转译中…'
                                                : '预览',
                                      ),
                              ),
                            ],
                          ),
                        ),
                        // 右侧：编辑 / 比对（作用于本卡），仅完成后可用
                        if (item.status == _WorkStatus.done) _sideButtons(item),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  /// 预览区的「文本 / UI」切换。
  ///
  /// UI 单独一栏而不是塞进文本预览里：两者信息密度差别太大，
  /// 混在一起会让 UI 被挤成一小块，失去「看效果」的意义。
  Widget _previewTabs(_WorkItem item) {
    Widget tab(String label, IconData icon, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Theme.of(context).primaryColor
                                : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected
                      ? Theme.of(context).primaryColor
                      : Colors.black45),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  color: selected
                      ? Theme.of(context).primaryColor
                      : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E6))),
      ),
      child: Row(
        children: [
          tab('文本', Icons.article_outlined, !item.showUiPreview,
              () => setState(() => item.showUiPreview = false)),
          tab('UI', Icons.dashboard_customize_outlined, item.showUiPreview,
              () => setState(() => item.showUiPreview = true)),
        ],
      ),
    );
  }

  Future<void> _retryAiUiStage(_WorkItem item) async {
    if (_running) return;
    final cfg = await AppSettings.getApiConfig();
    if (!cfg.isComplete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置 AI API，请先在设置中填写 API。')),
      );
      return;
    }

    _addLog('${item.card.name}：重试 AI UI 理解');
    setState(() {
      item.progress = 0;
      item.error = null;
      item.showUiPreview = true;
      item.work.stageStatus[PipelineStage.buildUi] = StageStatus.running;
    });

    try {
      await _pipeline.runBuildUiStage(item.work);
      final after = item.work.current?.characterData;
      final count = _countAssemblies(after);
      _addLog(count == 0 ? '  未生成（AI 判断无 UI）' : '  已重新生成 $count 份 UI');
      if (item.status == _WorkStatus.failed) item.status = _WorkStatus.done;
      item.progress = 1;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI UI 理解已重试完成')),
      );
    } catch (e) {
      item.error = 'AI UI 重试失败：$e';
      item.work.stageStatus[PipelineStage.buildUi] = StageStatus.failed;
      _addLog('  重试失败：$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI UI 重试失败：$e')),
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  int _countAssemblies(Map<String, dynamic>? card) {
    if (card == null) return 0;
    final raw = card['meta_json'];
    if (raw is! String || raw.isEmpty) return 0;
    try {
      final meta = jsonDecode(raw);
      if (meta is! Map) return 0;
      final list = meta['ui_assemblies'];
      return list is List ? list.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Widget _sideButtons(_WorkItem item) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: () => _editItem(item),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
            child: const Column(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(height: 4),
                Text('编辑', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _running ? null : () => _retryAiUiStage(item),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
            child: const Column(
              children: [
                Icon(Icons.refresh, size: 18),
                SizedBox(height: 4),
                Text('重试UI', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComparePage(item: item.work),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
            child: const Column(
              children: [
                Icon(Icons.compare_arrows, size: 18),
                SizedBox(height: 4),
                Text('比对', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDebugChatDialog extends StatefulWidget {
  final _WorkItem item;
  final Future<void> Function()? onRetryUi;

  const _AiDebugChatDialog({
    required this.item,
    this.onRetryUi,
  });

  @override
  State<_AiDebugChatDialog> createState() => _AiDebugChatDialogState();
}

class _AiDebugChatDialogState extends State<_AiDebugChatDialog> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final FocusNode _inputFocusNode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode(onKeyEvent: _handleInputKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest(jump: true));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    // Enter 发送；Shift+Enter 保留换行能力。
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!_busy && _inputCtrl.text.trim().isNotEmpty) {
      _send();
    }
    return KeyEventResult.handled;
  }

  void _jumpToLatest({bool jump = false}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (jump) {
      _scrollCtrl.jumpTo(target);
    } else {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool get _contextLooksCurrent => widget.item.work.uiAiConversationContext.any(
        (message) => message.content.contains(
          UiEngineKnowledgeService.knowledgeVersion,
        ),
      );

  List<ChatMessage> _requestMessages() {
    return [
      ...widget.item.work.uiAiConversationContext,
      const ChatMessage(
        role: 'user',
        content: '【模式切换】UI 转译结构化阶段已经结束。接下来请作为“转译 AI”'
            '与卡片制作者对话，基于刚才的 UI 理解上下文回答问题。'
            '请用自然语言解释你为什么这样转、缺少哪些原卡证据、需要制作者补充什么。'
            '不要再强制输出 UiDesignPlan JSON，除非制作者明确要求。',
      ),
      const ChatMessage(
        role: 'assistant',
        content: '好的。我会基于刚才的 UI 转译上下文回答制作者的问题，并指出我缺少的证据或不确定之处。',
      ),
      for (final turn in widget.item.aiChatTurns)
        ChatMessage(role: turn.role, content: turn.content),
    ];
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    _inputCtrl.clear();
    widget.item.aiChatTurns.add(_AiChatTurn(
      role: 'user',
      content: text,
    ));
    setState(() => _busy = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());

    try {
      final cfg = await AppSettings.getApiConfig();
      if (!cfg.isComplete) {
        throw StateError('未配置 AI API，请先在设置中填写 API。');
      }
      final reply = await ApiService.chatMessages(
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        model: cfg.model,
        messages: _requestMessages(),
        options: const ChatCompleteOptions(
          temperature: 0.25,
          timeout: Duration(seconds: 240),
        ),
      );
      widget.item.aiChatTurns.add(_AiChatTurn(
        role: 'assistant',
        content: reply,
      ));
    } catch (e) {
      widget.item.aiChatTurns.add(_AiChatTurn(
        role: 'assistant',
        content: '请求失败：$e',
      ));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    }
  }

  Future<void> _copyVisibleConversation() async {
    final turns = widget.item.aiChatTurns;
    final text = turns.isEmpty
        ? '（还没有制作者与转译 AI 的对话）'
        : turns.map((t) {
            final who = t.role == 'user' ? '制作者' : '转译AI';
            return '【$who】\n${t.content.trim()}';
          }).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制当前对话（不包含隐藏上下文）')),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'system':
        return '系统提示';
      case 'assistant':
        return '转译AI';
      case 'user':
        return '制作者/上下文';
      default:
        return role;
    }
  }

  String _translationLogText() {
    final context = widget.item.work.uiAiConversationContext;
    if (context.isEmpty) return '（没有可显示的 UI 转译日志 / 隐藏上下文）';
    final title = widget.item.work.current?.characterName ?? widget.item.card.name;
    final current = _contextLooksCurrent;
    final versionState = current ? '当前' : '可能过旧（建议点击“重试UI”重新生成上下文）';
    final buffer = StringBuffer()
      ..writeln('LLM Project UI 转译日志')
      ..writeln('卡片：$title')
      ..writeln('上下文消息数：${context.length}')
      ..writeln('当前知识库版本：${UiEngineKnowledgeService.knowledgeVersion}')
      ..writeln('上下文版本状态：$versionState')
      ..writeln('说明：这是“与转译 AI 对话”时注入的隐藏上下文；不包含你后续追问的可见对话。')
      ..writeln(''.padLeft(60, '='));
    for (var i = 0; i < context.length; i++) {
      final m = context[i];
      buffer
        ..writeln()
        ..writeln('【${i + 1}. ${_roleLabel(m.role)} / ${m.role}】')
        ..writeln(m.content.trim());
    }
    return buffer.toString();
  }

  Future<void> _copyTranslationLog() async {
    await Clipboard.setData(ClipboardData(text: _translationLogText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制转译日志（隐藏上下文）')),
    );
  }

  Future<void> _openTranslationLogDialog() async {
    final logText = _translationLogText();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('UI 转译日志 / 隐藏上下文'),
        content: SizedBox(
          width: 820,
          height: 560,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E6)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                logText,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logText));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('已复制转译日志')),
              );
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('复制日志'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final turns = widget.item.aiChatTurns;
    final title = widget.item.work.current?.characterName ?? widget.item.card.name;
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('与转译 AI 对话 · $title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          _contextLooksCurrent
                              ? '已载入本次 UI 转译的隐藏上下文 ${widget.item.work.uiAiConversationContext.length} 条；复制时不会包含上下文。'
                              : '⚠ 当前隐藏上下文可能是旧版知识库生成的；建议点“重试UI”刷新后再追问。',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: _contextLooksCurrent
                                ? Colors.black54
                                : const Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onRetryUi != null)
                    IconButton(
                      tooltip: '重试 AI UI 理解，刷新隐藏上下文',
                      icon: const Icon(Icons.refresh),
                      onPressed: _busy
                          ? null
                          : () async {
                              await widget.onRetryUi?.call();
                              if (mounted) setState(() {});
                            },
                    ),
                  IconButton(
                    tooltip: '查看 UI 转译日志（隐藏上下文）',
                    icon: const Icon(Icons.article_outlined),
                    onPressed: _openTranslationLogDialog,
                  ),
                  IconButton(
                    tooltip: '一键复制 UI 转译日志（隐藏上下文）',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: _copyTranslationLog,
                  ),
                  IconButton(
                    tooltip: '复制制作者与 AI 的对话（不含上下文）',
                    icon: const Icon(Icons.forum_outlined),
                    onPressed: _copyVisibleConversation,
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: turns.isEmpty
                  ? _emptyHint()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      itemCount: turns.length + (_busy ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_busy && index == turns.length) {
                          return _bubble(
                            role: 'assistant',
                            content: '正在思考…',
                            pending: true,
                          );
                        }
                        final turn = turns[index];
                        return _bubble(role: turn.role, content: turn.content);
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _inputFocusNode,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '问问转译 AI：为什么这样做？还缺什么证据？哪里不确定？',
                        helperText: 'Enter 发送，Shift+Enter 换行',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, size: 18),
                    label: Text(_busy ? '等待' : '发送'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.psychology_alt_outlined, size: 44, color: Colors.black38),
            SizedBox(height: 12),
            Text('可以开始追问转译 AI',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              '它已经带着本次 UI 转译 prompt、UIEngine 知识库、原卡证据和结构化输出作为隐藏上下文。\n'
              '你可以问它为什么生成这些字段、为什么跳过某段 UI、还需要你补充什么。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble({
    required String role,
    required String content,
    bool pending = false,
  }) {
    final isUser = role == 'user';
    final bg = isUser ? const Color(0xFFE3F2FD) : const Color(0xFFF3F3F7);
    final fg = isUser ? const Color(0xFF0D47A1) : const Color(0xFF202027);
    final name = isUser ? '制作者' : '转译AI';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: fg.withValues(alpha: 0.72),
                )),
            const SizedBox(height: 4),
            SelectableText(
              content,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: fg.withValues(alpha: pending ? 0.62 : 1),
                fontStyle: pending ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
