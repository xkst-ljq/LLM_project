import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ai_classifier.dart';
import '../core/ai_refiner.dart';
import '../core/ai_ui_blueprint.dart';
import '../core/app_settings.dart';
import '../core/conversion_writer.dart';
import '../core/history_service.dart';
import '../pipeline/pipeline.dart';
import '../pipeline/pipeline_runner.dart';
import 'card_preview.dart';
import 'compare_page.dart';
import 'entry_editor_page.dart';
import 'assembly_preview.dart';
import 'blueprint_confirm_dialog.dart';

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

  /// 展开卡片的预览区高度（可拖拽底部把手调节）。
  double previewHeight = 480;

  _WorkItem(this.card, this.work);
}

/// 一次 AI 阶段（如「蓝图」「意图」「修正」）的完整流式输出。
class _AiStageOutput {
  final String title;
  final StringBuffer text;
  bool collapsed;
  _AiStageOutput(this.title, this.text, {this.collapsed = true});
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

  /// 每个 AI 阶段的一份完整流式输出（标题 + 全文 + 是否折叠）。
  final List<_AiStageOutput> _aiOutputs = [];

  /// 当前正在流式累积的 AI 阶段（标题 + 已累积全文）。
  _AiStageOutput? _liveOutput;
  int _thinkingFrame = 0;
  @override
  void initState() {
    super.initState();
    _pipeline = ConversionPipeline(
      aiClassify: AiClassifier.classify,
      aiRefine: AiRefiner.refine,
      // 蓝图确认：UI 层弹出分条目蓝图供用户逐条确认/修改。
      blueprintConfirmer: _confirmBlueprint,
    );
    for (final c in widget.cards) {
      _items.add(_WorkItem(c, _pipeline.createItem(c.name, c.bytes)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  /// 蓝图确认回调：弹出蓝图对话框，让用户逐条确认/修改。
  Future<UiBlueprint?> _confirmBlueprint(UiBlueprint blueprint) async {
    // 先读设置：若用户关闭了「蓝图确认」，直接放行（返回原蓝图）。
    final enabled = await AppSettings.getConfirmBlueprint();
    if (!enabled) return blueprint;
    if (!mounted) return blueprint;
    return showDialog<UiBlueprint>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlueprintConfirmDialog(blueprint: blueprint),
    );
  }

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _doneCount = 0;
      _log.clear();
      _aiOutputs.clear();
      _liveOutput = null;
      _thinkingFrame = 0;
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
        // 流式：把完整 token 累积进当前阶段，节流刷新。
        onThinking: (partial) {
          if (!mounted) return;
          _liveOutput ??= _AiStageOutput('AI 输出', StringBuffer());
          _liveOutput!.text.write(partial);
          _thinkingFrame++;
          // 每 2 帧刷新一次，让流式更连贯（原 4 帧）。
          if (_thinkingFrame % 2 == 0) setState(() {});
        },
        // 阶段切换：把上一个阶段归档为可折叠块，开新阶段并立刻显示「思考中」。
        onStage: (stage) {
          if (!mounted) return;
          setState(() {
            if (_liveOutput != null && _liveOutput!.text.isNotEmpty) {
              _aiOutputs.add(_liveOutput!);
            }
            _liveOutput = _AiStageOutput(stage, StringBuffer());
          });
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
        // 归档当前未结束的流式阶段（若还有残留）
        if (_liveOutput != null && _liveOutput!.text.isNotEmpty) {
          _aiOutputs.add(_liveOutput!);
          _liveOutput = null;
        }
      });
    }

    if (mounted) {
      setState(() {
        _running = false;
        if (_liveOutput != null && _liveOutput!.text.isNotEmpty) {
          _aiOutputs.add(_liveOutput!);
        }
        _liveOutput = null;
      });
    }
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  int get _successCount =>
      _items.where((e) => e.status == _WorkStatus.done).length;

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('简短日志：',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        if (_liveOutput != null)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'AI 思考中… ${_liveOutput!.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.teal),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '复制全部日志与 AI 输出',
                          iconSize: 16,
                          icon: const Icon(Icons.copy_all_outlined),
                          onPressed: _copyAllLog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final line in _log)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(line,
                            style: const TextStyle(fontSize: 12, height: 1.4)),
                      ),
                    // 各阶段的完整 AI 输出（可折叠，默认折叠）
                    for (final out in _aiOutputs) _aiOutputTile(out),
                    // 当前正在流式的阶段：即使尚未收到 token 也显示「思考中」
                    // 占位，避免用户以为卡死（TTFT 期间首 token 还没到）。
                    if (_liveOutput != null) _liveOutputTile(_liveOutput!),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 完整复制：日志 + 所有阶段 AI 输出的全文。
  Future<void> _copyAllLog() async {
    final buf = StringBuffer()
      ..writeln(_log.join('\n'));
    if (_aiOutputs.isNotEmpty || (_liveOutput?.text.isNotEmpty ?? false)) {
      buf.writeln('\n—— AI 完整输出 ——');
      for (final out in _aiOutputs) {
        buf.writeln('【${out.title}】');
        buf.writeln(out.text);
      }
      if (_liveOutput != null && _liveOutput!.text.isNotEmpty) {
        buf.writeln('【${_liveOutput!.title}】');
        buf.writeln(_liveOutput!.text);
      }
    }
    final text = buf.toString();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日志 + AI 完整输出已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 已归档的某个 AI 阶段输出（默认折叠，点击展开/收起）。
  Widget _aiOutputTile(_AiStageOutput out) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        initiallyExpanded: !out.collapsed,
        onExpansionChanged: (v) => setState(() => out.collapsed = !v),
        title: Text(
          '【${out.title}】',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.teal),
        ),
        subtitle: Text(
          '${out.text.length} 字符（点击展开）',
          style: const TextStyle(fontSize: 10, color: Colors.black45),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              out.text.toString(),
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前正在流式的阶段输出（实时展开显示全文；未收到 token 时显示思考中）。
  Widget _liveOutputTile(_AiStageOutput out) {
    final text = out.text.toString();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: text.isEmpty
          ? Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '【${out.title}】正在推理，等待首次输出…',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.teal),
                  ),
                ),
              ],
            )
          : SelectableText(
              '【${out.title}】\n$text',
              style: const TextStyle(
                  fontSize: 11, height: 1.4, color: Colors.teal),
            ),
    );
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
            Column(
              children: [
                const Divider(height: 1),
                SizedBox(
                  height: item.previewHeight,
                  child: Column(
                    children: [
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
                                            placeholder: item.status ==
                                                    _WorkStatus.running
                                                ? '转译中…'
                                                : '预览',
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            // 右侧：编辑 / 比对（作用于本卡），仅完成后可用
                            if (item.status == _WorkStatus.done)
                              _sideButtons(item),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 底部把手：上下拖动调整预览区高度
                _resizeHandle(item),
              ],
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

  /// 预览区底部的拖拽把手，上下拖动改变预览区高度。
  Widget _resizeHandle(_WorkItem item) {
    return Tooltip(
      message: '拖动调整预览区高度',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) {
          setState(() {
            item.previewHeight =
                (item.previewHeight + d.delta.dy).clamp(280, 1000);
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: Container(
            height: 20,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
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
