// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_card.dart';
import '../services/api_config_service.dart';
import '../services/character_card_asset_service.dart';
import '../services/character_card_png_asset_service.dart';
import '../services/database_service.dart';
import '../tools/character_converter/ai_classifier.dart';
import '../tools/character_converter/ai_refiner.dart';
import '../tools/character_converter/app_settings.dart';
import '../tools/character_converter/converted_card_inserter.dart';
import '../tools/character_converter/pipeline/pipeline.dart';
import '../tools/character_converter/pipeline/pipeline_runner.dart';
import '../shared/theme/app_theme_tokens.dart';
import '../shared/transition/home_transitions.dart';
import '../utils/app_feedback.dart';
import '../utils/default_image.dart';
import '../utils/id_utils.dart';
import '../widgets/page_guide_overlay.dart';
import '../widgets/sub_page_backdrop.dart';
import 'character_edit_page.dart';
import 'chat_page.dart';

class CharacterImportPreview {
  final File file;
  final String sourceType; // llmcard / png_card
  final String name;
  final String cardType;
  final String description;
  final int entryCount;
  final int greetingCount;
  final bool hasWorldBook;
  final List<String> worldBookNames;
  final bool hasUserOverride;
  final List<String> checks;

  CharacterImportPreview({
    required this.file,
    required this.sourceType,
    required this.name,
    required this.cardType,
    required this.description,
    required this.entryCount,
    required this.greetingCount,
    required this.hasWorldBook,
    required this.worldBookNames,
    required this.hasUserOverride,
    required this.checks,
  });
}

class CharacterLibraryPage extends StatefulWidget {
  final bool startGuide;
  final VoidCallback? onExitGuide;

  const CharacterLibraryPage({
    super.key,
    this.startGuide = false,
    this.onExitGuide,
  });

  @override
  State<CharacterLibraryPage> createState() => _CharacterLibraryPageState();
}

class _CharacterLibraryPageState extends State<CharacterLibraryPage>
    with TickerProviderStateMixin {
  final List<CharacterCard> _characters = [];
  final Set<String> _expandedIds = {};
  final Set<String> _deletingIds = {};
  String? _activeTagFilter; // 当前选中的标签筛选，null 表示全部

  /// 当前所有角色身上出现过的标签（去重 + 保持稳定顺序）。
  List<String> get _allTags {
    final seen = <String>{};
    final result = <String>[];
    for (final c in _characters) {
      for (final t in c.meta.tags) {
        final tag = t.trim();
        if (tag.isEmpty) continue;
        if (seen.add(tag)) result.add(tag);
      }
    }
    return result;
  }

  /// 按当前标签筛选后的角色列表。
  List<CharacterCard> get _visibleCharacters {
    final filter = _activeTagFilter;
    if (filter == null || filter.isEmpty) return _characters;
    return _characters
        .where((c) => c.meta.tags.map((e) => e.trim()).contains(filter))
        .toList();
  }

  late bool _showGuide;
  final _sortButtonKey = GlobalKey();
  final _exportButtonKey = GlobalKey();
  final _addButtonKey = GlobalKey();
  final _firstCardGuideKey = GlobalKey();
  final _chatButtonGuideKey = GlobalKey();
  // 当前选中卡片放大进入聊天页的转场源 Key（仅绑定到 _expandedIds 里的那张卡）。
  final _selectedCardKey = GlobalKey();
  // 播放按钮的加载动画（旋转 + 史莱姆弹跳循环），等待 UIEngine 就绪时播放。
  late final AnimationController _playLoadingController;
  // 等待 UIEngine 就绪：offstage 预加载一个 ChatPage 触发真实初始化，
  // 就绪后（onReady）播放键才消失并立即放大跳转。
  bool _launchingChat = false;
  CharacterCard? _launchCharacter;
  Widget? _chatPreloadHost;
  static const String _sortByKey = 'character_sort_by';
  static const String _sortAscendingKey = 'character_sort_ascending';

  @override
  void initState() {
    super.initState();
    _playLoadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _showGuide = widget.startGuide;
    _loadSortPreference();
    _loadCharacters();
  }

  @override
  void dispose() {
    _playLoadingController.dispose();
    super.dispose();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sortBy = prefs.getString(_sortByKey) ?? 'time';
      _sortAscending = prefs.getBool(_sortAscendingKey) ?? true;
    });
  }

  Future<void> _exportSelectedCharacterCard() async {
    if (_expandedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击一个角色卡片')),
      );
      return;
    }

    final expandedId = _expandedIds.first;
    final character = _characters.firstWhere((c) => c.id == expandedId);

    bool includeUserOverride = false;
    bool includeBoundWorldBook = character.worldBookId.trim().isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('导出角色卡'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: includeUserOverride,
                    onChanged: (v) {
                      setDialogState(() {
                        includeUserOverride = v ?? false;
                      });
                    },
                    title: const Text('包含当前角色用户覆盖设定'),
                    subtitle: const Text(
                      '通常不建议分享，可能包含你的个人设定。',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: includeBoundWorldBook,
                    onChanged: character.worldBookId.trim().isEmpty
                        ? null
                        : (v) {
                      setDialogState(() {
                        includeBoundWorldBook = v ?? false;
                      });
                    },
                    title: const Text('包含绑定世界书'),
                    subtitle: Text(
                      character.worldBookId.trim().isEmpty
                          ? '当前角色没有绑定世界书。'
                          : '导入角色卡时会自动新建世界书并重新绑定。',
                      style: const TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('导出'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      final file = await CharacterCardAssetService.exportCharacterCard(
        character: character,
        includeUserOverride: includeUserOverride,
        includeBoundWorldBook: includeBoundWorldBook,
      );

      final downloadsPath =
      await CharacterCardAssetService.saveCharacterCardToDownloads(file);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: Text(
            downloadsPath != null
                ? '角色卡已保存到：\n$downloadsPath'
                : '角色卡已导出到应用目录：\n${file.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Share.shareXFiles(
                  [XFile(file.path)],
                  text: 'LLM Project 角色卡',
                );
              },
              child: const Text('分享'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _importCharacterCardWithPreview() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LLM Project 角色卡文件或角色卡图片',
      type: FileType.any,
      allowMultiple: false,
    );

    if (picked == null || picked.files.isEmpty) return;

    final filePath = picked.files.single.path;
    if (filePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件')),
      );
      return;
    }

    final file = File(filePath);
    late CharacterImportPreview preview;

    try {
      preview = await _buildCharacterImportPreview(file);
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showErrorDialog(
        context,
        title: '读取角色卡失败',
        error: e,
        message: '无法识别该角色卡文件。',
        suggestion: '请选择由 LLM Project 导出的 .llmcard 文件或角色卡图片。如果图片来自聊天软件，请确认发送时使用了“原图”或“文件”方式。',
      );
      return;
    }

    if (!mounted) return;

    final confirmed = await _showCharacterImportPreview(preview);
    if (!confirmed) return;

    try {
      if (preview.sourceType == 'png_card') {
        await CharacterCardPngAssetService.importCharacterCardPng(file);
      } else {
        await CharacterCardAssetService.importCharacterCard(file);
      }

      await _loadCharacters();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色卡导入成功')),
      );
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showErrorDialog(
        context,
        title: '导入角色卡失败',
        error: e,
        message: '角色卡数据读取成功，但写入本地数据库时失败。',
        suggestion: '可以尝试重新导入，或先导出完整备份后重启应用再试。',
      );
    }
  }

  /// AI 智能转译：选第三方角色卡（PNG / JSON）→ 选转译 AI → 转译 → 直接入库。
  Future<void> _aiConvertCharacterCard() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要转译的第三方角色卡',
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
      allowMultiple: false,
    );

    if (picked == null || picked.files.isEmpty) return;

    final filePath = picked.files.single.path;
    if (filePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件')),
      );
      return;
    }

    final file = File(filePath);
    final fileName = p.basename(filePath);

    // 收集可选 AI 配置，默认选中当前启用配置。
    final configs = await ApiConfigService.getAllConfigs();
    final activeId = await ApiConfigService.getActiveConfigId();
    var selectedIndex = configs.indexWhere((c) => c.id == activeId);
    if (selectedIndex < 0) selectedIndex = configs.isEmpty ? -1 : 0;
    var useAi = configs.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('AI 智能转译'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('文件：$fileName'),
                const SizedBox(height: 4),
                Text(
                  '将自动完成 规则转译 → AI 智能归类 → AI UI 理解 → 检查精修，'
                  '转译完成后直接加入角色库。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (configs.isEmpty) ...[
                  const Text('当前没有已保存的 AI 配置，将以「仅规则转译」进行。',
                      style: TextStyle(color: Colors.orange)),
                ] else ...[
                  DropdownButtonFormField<int>(
                    initialValue: selectedIndex,
                    decoration: const InputDecoration(
                      labelText: '转译 AI',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('使用当前启用配置'),
                      ),
                      for (var i = 0; i < configs.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${configs[i].name}（${configs[i].model}）',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        selectedIndex = v ?? 0;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: useAi,
                    title: const Text('启用 AI 转译'),
                    subtitle: const Text('关闭后仅做规则转译（更快，不调用模型）'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setDialogState(() => useAi = v),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('开始转译'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    // 设置本次转译的 AI 覆盖配置（默认项 / 关闭时走 null → 当前启用配置）。
    AppSettings.conversionAiOverride =
        (useAi && selectedIndex >= 0 && selectedIndex < configs.length)
            ? configs[selectedIndex]
            : null;

    if (!mounted) return;

    // 转译进度框（不可取消）。用 ValueNotifier 让日志行实时刷新。
    final progressLine = ValueNotifier<String>('');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('正在转译…'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progressLine,
                builder: (_, line, _) => Text(
                  line.isEmpty ? '准备中…' : line,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('文件内容为空，无法转译。');
      }

      final pipeline = ConversionPipeline(
        aiClassify: AiClassifier.classify,
        aiRefine: AiRefiner.refine,
      );
      final item = pipeline.createItem(fileName, bytes);

      final runner = PipelineRunner(
        pipeline: pipeline,
        useAi: useAi,
        onLog: (line) => progressLine.value = line,
        onProgress: (_) {},
      );

      final ok = await runner.run(item);
      if (!ok) {
        final note = item.current?.notes.isNotEmpty == true
            ? item.current!.notes.first.message
            : '未知错误';
        throw Exception('规则转译失败：$note');
      }

      final current = item.current;
      if (current == null || current.characterData == null) {
        throw Exception('转译未产生可用结果。');
      }

      await ConvertedCardInserter.insert(current);
      await _loadCharacters();

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转译完成：${current.characterName} 已加入角色库')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度框
      await AppFeedback.showErrorDialog(
        context,
        title: '转译失败',
        error: e,
        message: '未能完成转译并写入角色库。',
        suggestion: '可尝试重新选择文件，或在弹窗中关闭 AI 后仅做规则转译。',
      );
    } finally {
      AppSettings.conversionAiOverride = null;
    }
  }

  Future<void> _exportSelectedCharacterCardPng() async {
    if (_expandedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击一个角色卡片')),
      );
      return;
    }

    final expandedId = _expandedIds.first;
    final character = _characters.firstWhere((c) => c.id == expandedId);

    bool includeUserOverride = false;
    bool includeBoundWorldBook = character.worldBookId.trim().isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('导出角色卡图片'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '图片角色卡适合展示和分享。\n'
                        '通过聊天软件发送时请使用“原图”或“文件”方式，否则内部数据可能丢失。',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: includeUserOverride,
                    onChanged: (v) {
                      setDialogState(() {
                        includeUserOverride = v ?? false;
                      });
                    },
                    title: const Text('包含当前角色用户覆盖设定'),
                    subtitle: const Text(
                      '通常不建议分享，可能包含你的个人设定。',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: includeBoundWorldBook,
                    onChanged: character.worldBookId.trim().isEmpty
                        ? null
                        : (v) {
                      setDialogState(() {
                        includeBoundWorldBook = v ?? false;
                      });
                    },
                    title: const Text('包含绑定世界书'),
                    subtitle: Text(
                      character.worldBookId.trim().isEmpty
                          ? '当前角色没有绑定世界书。'
                          : '导入角色卡图片时会自动新建世界书并重新绑定。',
                      style: const TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('导出'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      final file = await CharacterCardPngAssetService.exportCharacterCardPng(
        character: character,
        includeUserOverride: includeUserOverride,
        includeBoundWorldBook: includeBoundWorldBook,
      );

      final downloadsPath =
      await CharacterCardPngAssetService.saveCharacterPngToDownloads(file);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: Text(
            downloadsPath != null
                ? '角色卡图片已保存到：\n$downloadsPath\n\n发送给别人时请使用“原图”或“文件”方式。'
                : '角色卡图片已导出到应用目录：\n${file.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Share.shareXFiles(
                  [XFile(file.path)],
                  text: 'LLM Project 角色卡图片',
                );
              },
              child: const Text('分享'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _loadCharacters() async {
    final characters = await DatabaseService.getAllCharacters();
    setState(() {
      _characters.clear();
      _characters.addAll(characters.map((c) => CharacterCard(
        id: c['id'] as String,
        name: c['name'] as String,
        avatar: c['avatar'] as String? ?? '',
        cardImagePath: c['card_image_path'] as String? ?? '',
        description: c['description'] as String? ?? '',
        systemPrompt: c['system_prompt'] as String? ?? '',
        userName: c['user_name'] as String? ?? '',
        userAvatar: c['user_avatar'] as String? ?? '',
        backgroundId: c['background_id'] as String? ?? '',
        worldBookId: c['world_book_id'] as String? ?? '',
        userDetailSetting: c['user_detail_setting'] as String? ?? '',
        cardType: c['card_type'] as String? ?? 'character',
        entriesJson: c['entries_json'] as String? ?? '[]',
        openingGreetings: c['opening_greetings'] as String? ?? '[]',
        metaJson: c['meta_json'] as String? ?? '{}',
      )));
      _sortCharacters();
    });
  }

  Future<CharacterImportPreview> _buildCharacterImportPreview(File file) async {
    try {
      final data = await CharacterCardAssetService.readCharacterCardData(file);
      return _previewFromCharacterData(file, data);
    } catch (_) {
      final data =
      await CharacterCardPngAssetService.readCharacterCardPngData(file);
      return _previewFromCharacterData(file, data);
    }
  }

  CharacterImportPreview _previewFromCharacterData(
      File file,
      Map<String, dynamic> data,
      ) {
    final character = Map<String, dynamic>.from(data['character'] as Map);

    final worldBooks = (data['world_books'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    int entryCount = 0;
    int greetingCount = 0;

    try {
      entryCount =
          (jsonDecode(character['entries_json'] as String? ?? '[]') as List)
              .length;
    } catch (_) {}

    try {
      greetingCount =
          (jsonDecode(character['opening_greetings'] as String? ?? '[]') as List)
              .length;
    } catch (_) {}

    final hasUserOverride =
        (character['user_name']?.toString().isNotEmpty ?? false) ||
            (character['user_detail_setting']?.toString().isNotEmpty ?? false);

    final sourceType = data['container']?.toString() ?? 'unknown';

    return CharacterImportPreview(
      file: file,
      sourceType: sourceType,
      name: character['name']?.toString() ?? '未命名角色卡',
      cardType: character['card_type']?.toString() ?? 'character',
      description: character['description']?.toString() ?? '',
      entryCount: entryCount,
      greetingCount: greetingCount,
      hasWorldBook: worldBooks.isNotEmpty,
      worldBookNames: worldBooks
          .map((e) => e['name']?.toString() ?? '未命名世界书')
          .toList(),
      hasUserOverride: hasUserOverride,
      checks: [
        '内部识别标识完整',
        '角色卡数据完整',
        if (sourceType == 'png_card') '图片角色卡数据完整',
        if (worldBooks.isNotEmpty) '包含世界书依赖',
      ],
    );
  }

  Future<bool> _showCharacterImportPreview(
      CharacterImportPreview preview,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入角色卡'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                preview.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '来源类型：${preview.sourceType == 'png_card' ? '角色卡图片' : '完整角色卡文件'}',
              ),
              Text('卡片类型：${preview.cardType == 'system' ? '系统卡' : '人物卡'}'),
              Text('设定条目：${preview.entryCount} 个'),
              Text('开场白：${preview.greetingCount} 条'),
              const SizedBox(height: 8),

              if (preview.description.isNotEmpty) ...[
                const Text('简短描述：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  preview.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],

              if (preview.hasWorldBook) ...[
                const Text('包含世界书：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...preview.worldBookNames.map((name) => Text('• $name')),
                const SizedBox(height: 8),
              ],

              if (preview.hasUserOverride) ...[
                const Text(
                  '包含当前用户覆盖设定',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const Text('完整性检查：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...preview.checks.map(
                    (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _updateSort(String? sortBy, bool? ascending) async {
    final prefs = await SharedPreferences.getInstance();
    if (sortBy != null) {
      _sortBy = sortBy;
      await prefs.setString(_sortByKey, sortBy);
    }
    if (ascending != null) {
      _sortAscending = ascending;
      await prefs.setBool(_sortAscendingKey, ascending);
    }
    setState(() {
      _sortCharacters();
    });
  }

  CharacterCard? _getSelectedCharacter() {
    if (_expandedIds.isEmpty) return null;
    final id = _expandedIds.first;
    try {
      return _characters.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 播放按钮（进入聊天）。等待 UIEngine 就绪期间，按钮像史莱姆一样
  /// 「旋转一圈 → 压扁 → 弹起 → 歇几秒」循环，就绪后由 stagedRole 转场收尾。
  Widget _buildPlayFab() {
    return AnimatedBuilder(
      animation: _playLoadingController,
      builder: (context, child) {
        final t = _playLoadingController.value;
        // 一次完整循环 = 旋转一圈 → 压扁 → 弹起 → 停歇（然后 repeat）
        final spinning = _playLoadingController.isAnimating;
        final tokens = AppThemeTokens.of(context);

        // 旋转角度：0%–25% 转一整圈
        double angle = 0;
        // 压扁/弹起：竖向缩放（scaleY），横向略微补偿（scaleX）
        double scaleY = 1;
        double scaleX = 1;

        if (spinning) {
          final spin = (t / 0.25).clamp(0.0, 1.0);
          angle = Curves.easeInOutCubic.transform(spin) * 2 * math.pi;

          if (t >= 0.25 && t < 0.45) {
            // 压扁
            final s = ((t - 0.25) / 0.20).clamp(0.0, 1.0);
            final e = Curves.easeInOut.transform(s);
            scaleY = 1 - 0.28 * e;
            scaleX = 1 + 0.14 * e;
          } else if (t >= 0.45 && t < 0.70) {
            // 弹起（overshoot 回弹到 1）
            final s = ((t - 0.45) / 0.25).clamp(0.0, 1.0);
            final e = Curves.easeOutBack.transform(s);
            scaleY = 0.72 + 0.28 * e;
            scaleX = 1.14 - 0.14 * e;
          } else {
            // 停歇 / 静止
            scaleY = 1;
            scaleX = 1;
          }
        }

        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scaleX: scaleX,
            scaleY: scaleY,
            child: FloatingActionButton(
              onPressed: _openSelectedCharacterChat,
              backgroundColor: tokens.accent,
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _openSelectedCharacterChat() {
    if (_launchingChat) return; // 防止重复点击

    final character = _getSelectedCharacter();
    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击一个角色卡片')),
      );
      return;
    }

    _launchingChat = true;
    _launchCharacter = character;
    // 开始史莱姆加载动画：等待封面图 + UIEngine 就绪（按钮保持转圈）。
    _playLoadingController.repeat();

    // 并行：预热 DB 缓存 + 封面图，并 offstage 预加载一个 ChatPage 触发真实
    // 初始化；等 onReady 后播放键消失并立即放大跳转。
    _preloadForChat(character);
    _preloadCover(character);
    _preloadChatForReady(character);
  }

  /// 预加载封面图，避免放大过程中封面还是空白/未加载。
  Future<void> _preloadCover(CharacterCard character) async {
    final path = character.cardImagePath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        // 把封面图解码进 Flutter 图片缓存；放大转场里的 Image.file 会命中
        // 同一缓存，即可立即显示完整封面。
        await precacheImage(FileImage(file), context);
      }
    } catch (_) {
      // 封面加载失败不阻塞，转场内部有兜底（accent 渐变）。
    }
  }

  /// offstage 挂载一个 ChatPage 触发真实 UIEngine 初始化。
  ///
  /// ChatPage 的 onReady 在重型初始化完成后回调，那时才算「UIEngine 就绪」。
  /// 就绪前播放键保持转圈；就绪后卸载 offstage、播放键消失、立即放大跳转。
  void _preloadChatForReady(CharacterCard character) {
    setState(() {
      _chatPreloadHost = ChatPage(
        character: character,
        onReady: _onChatPreloaded,
      );
    });
  }

  void _onChatPreloaded() {
    if (!mounted) return;

    final character = _launchCharacter;

    // UIEngine 就绪：播放键消失，卸载 offstage 预加载。
    if (_playLoadingController.isAnimating) {
      _playLoadingController.stop();
      _playLoadingController.value = 0;
    }
    setState(() => _chatPreloadHost = null);

    if (character == null) return;

    // ready 已就绪：转场用已完成的 future，放大立即连续进行、不等待。
    final ready = Completer<void>()..complete();
    final tokens = AppThemeTokens.of(context);
    Navigator.push<void>(
      context,
      HomeTransitions.cardToChat(
        context: context,
        sourceKey: _selectedCardKey,
        accent: tokens.accent,
        character: character,
        readyFuture: ready.future,
        page: ChatPage(character: character, onReady: () {}),
      ),
    ).then((_) {
      if (mounted) _launchingChat = false;
    });
  }

  /// 转场前预热聊天页要用的重数据，避免转场结束后主线程被 DB/JSON 阻塞。
  Future<void> _preloadForChat(CharacterCard character) async {
    try {
      // 触发热 meta 解析（缓存一次，ChatPage 里 hasAssembly 不再重复解码）
      character.meta;
      await Future.wait([
        DatabaseService.getSessionStateJson(character.id),
        DatabaseService.getMessages(character.id),
      ]);
    } catch (_) {}
    await Future.delayed(Duration.zero);
  }

  void _showCreateOrImportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建角色卡'),
              onTap: () {
                Navigator.pop(ctx);
                _addCharacter();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('导入角色卡'),
              subtitle: const Text('支持 .llmcard 和 LLM Project 角色卡图片'),
              onTap: () {
                Navigator.pop(ctx);
                _importCharacterCardWithPreview();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI 智能转译角色卡'),
              subtitle: const Text('自动转译第三方角色卡并直接加入角色库'),
              onTap: () {
                Navigator.pop(ctx);
                _aiConvertCharacterCard();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportCharacterSheet() {
    final character = _getSelectedCharacter();

    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击一个角色卡片')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('导出完整角色卡文件'),
              subtitle: const Text('稳定格式，推荐迁移或正式分享'),
              onTap: () {
                Navigator.pop(ctx);
                _exportSelectedCharacterCard();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('导出角色卡图片'),
              subtitle: const Text('适合展示分享，发送时请使用原图或文件'),
              onTap: () {
                Navigator.pop(ctx);
                _exportSelectedCharacterCardPng();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exitGuide() {
    setState(() => _showGuide = false);
    widget.onExitGuide?.call();
  }

  Rect? _rectForKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) return null;

    final renderObject = keyContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Rect _fallbackCardRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 32;
    return Rect.fromLTWH(32, top, size.width * 0.38, size.width * 0.58);
  }

  Rect _backButtonRect(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Rect.fromLTWH(
      4,
      top + 2,
      58,
      kToolbarHeight,
    );
  }

  Rect _badgeBelowRect(Rect rect) {
    const badgeSize = 30.0;

    return Rect.fromLTWH(
      rect.center.dx - badgeSize / 2,
      rect.bottom + 8,
      badgeSize,
      badgeSize,
    );
  }

  List<PageGuideTarget> _guideTargets(BuildContext context) {
    final targets = <PageGuideTarget>[
      PageGuideTarget(
        id: 'character_back',
        order: 0,
        rect: _backButtonRect(context),
        title: '返回上一页',
        description: '点击这里返回上一页。返回只会切换页面，不会关闭教程模式。',
        actionLabel: '返回上一页',
        onAction: () => Navigator.of(context).maybePop(),
        showBadge: false,
      ),
    ];

    final firstCardRect =
        _rectForKey(_firstCardGuideKey) ?? _fallbackCardRect(context);
    targets.add(
      PageGuideTarget(
        id: 'character_card',
        order: 1,
        rect: firstCardRect,
        title: '角色卡片',
        description: '这里是角色卡片列表。点击角色卡片一次会展开简介；再次点击已展开的角色卡片会进入角色预览 / 编辑页面；长按角色卡片可进入删除状态。',
        showHighlight: false,
      ),
    );

    final sortRect = _rectForKey(_sortButtonKey);
    if (sortRect != null) {
      targets.add(
        PageGuideTarget(
          id: 'character_sort',
          order: 2,
          rect: sortRect,
          badgeRect: _badgeBelowRect(sortRect),
          title: '排序',
          description: '点击这里可以选择排序方式；长按可以切换正序 / 倒序。',
          showHighlight: false,
        ),
      );
    }

    final exportRect = _rectForKey(_exportButtonKey);
    if (exportRect != null) {
      targets.add(
        PageGuideTarget(
          id: 'character_export',
          order: 3,
          rect: exportRect,
          badgeRect: _badgeBelowRect(exportRect),
          title: '导出角色卡',
          description: '先点击一个角色卡片选中角色，再点击这里可以导出角色卡。可导出完整角色卡文件或角色卡图片。',
          showHighlight: false,
        ),
      );
    }

    final addRect = _rectForKey(_addButtonKey);
    if (addRect != null) {
      targets.add(
        PageGuideTarget(
          id: 'character_add',
          order: 4,
          rect: addRect,
          badgeRect: _badgeBelowRect(addRect),
          title: '新建 / 导入角色',
          description: '点击这里可以新建角色卡，也可以导入已有角色卡。导入支持 LLM Project 角色卡文件和角色卡图片。',
          showHighlight: false,
        ),
      );
    }

    final chatRect = _rectForKey(_chatButtonGuideKey);
    if (chatRect != null) {
      targets.add(
        PageGuideTarget(
          id: 'character_chat',
          order: 5,
          rect: chatRect,
          title: '进入聊天',
          description: '先点击一个角色卡片选中角色，再点击这里可以进入聊天页与该角色对话。',
          showHighlight: false,
        ),
      );
    }

    return targets;
  }

  /// 顶部标签筛选栏。无标签时不显示，避免占位。
  Widget _buildTagFilterBar() {
    final tags = _allTags;
    if (tags.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: const Text('全部'),
          selected: _activeTagFilter == null,
          onSelected: (_) => setState(() => _activeTagFilter = null),
        ),
      ),
      ...tags.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(tag),
              selected: _activeTagFilter == tag,
              onSelected: (sel) => setState(() {
                _activeTagFilter = sel ? tag : null;
              }),
            ),
          )),
    ];

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips,
      ),
    );
  }

  Widget _buildSortButton({Key? key}) {
    return Builder(
      builder: (buttonContext) {
        return InkWell(
          key: key,
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final renderObject = buttonContext.findRenderObject();
            if (renderObject is! RenderBox) return;

            final overlay = Overlay.of(buttonContext).context.findRenderObject();
            if (overlay is! RenderBox) return;

            final offset = renderObject.localToGlobal(
              Offset.zero,
              ancestor: overlay,
            );

            final rect = Rect.fromLTWH(
              offset.dx,
              offset.dy,
              renderObject.size.width,
              renderObject.size.height,
            );

            final selected = await showMenu<String>(
              context: buttonContext,
              position: RelativeRect.fromRect(
                rect,
                Offset.zero & overlay.size,
              ),
              items: [
                CheckedPopupMenuItem(
                  value: 'time',
                  checked: _sortBy == 'time',
                  child: const Text('默认顺序 / 创建时间'),
                ),
                CheckedPopupMenuItem(
                  value: 'name',
                  checked: _sortBy == 'name',
                  child: const Text('按名称排序'),
                ),
              ],
            );

            if (!mounted || selected == null) return;
            await _updateSort(selected, null);
          },
          onLongPress: _toggleSortOrder,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Icon(Icons.sort),
          ),
        );
      },
    );
  }

  Future<void> _toggleSortOrder() async {
    final newAscending = !_sortAscending;

    await _updateSort(null, newAscending);

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newAscending ? '已切换为正序' : '已切换为倒序'),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _addCharacter() async {
    final newId = IdUtils.timestampId();
    await DatabaseService.insertCharacter({
      'id': newId,
      'name': '',
      'avatar': '',
      'card_image_path': '',
      'description': '',
      'system_prompt': '',
    });
    final colors = [
      '#FFCDD2', '#C8E6C9', '#BBDEFB', '#FFF9C4',
      '#D1C4E9', '#F8BBD0', '#B2EBF2', '#FFE0B2',
    ];
    final randomColor = colors[DateTime.now().millisecond % colors.length];

    final imageFileName = 'default_card_$newId.png';
    final defaultImagePath = await generateDefaultCardImage(
      colorHex: randomColor,
      fileName: imageFileName,
    );
    await DatabaseService.updateCharacter({
      'id': newId,
      'card_image_path': defaultImagePath,
      'user_name': '',
      'user_avatar': '',
    });
    _loadCharacters();
    setState(() {
      _deletingIds.clear();
      _expandedIds.clear();
    });
  }

  void _deleteCharacter(String id) async {
    await DatabaseService.deleteCharacter(id);
    _loadCharacters();
    setState(() {
      _deletingIds.remove(id);
    });
  }

  void _openCharacterEdit(CharacterCard character, int index) {
    final col = index % 2;
    final row = index ~/ 2;
    const cardWidth = 160.0;
    const cardHeight = 240.0;
    const crossSpacing = 12.0;
    const mainSpacing = 12.0;
    const padding = 16.0;

    final cardLeft = padding + col * (cardWidth + crossSpacing);
    final cardTop = kToolbarHeight +
        MediaQuery.of(context).padding.top +
        padding +
        row * (cardHeight + mainSpacing);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        barrierLabel: '关闭',
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => CharacterEditOverlay(
          character: character,
          cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    ).then((_) => _loadCharacters());
  }

  String _sortBy = 'time'; // 默认按创建时间
  bool _sortAscending = true;

  int _createdTimeOf(String id) {
    return int.tryParse(id) ?? 0;
  }

  int _compareCharacterByTime(CharacterCard a, CharacterCard b) {
    final at = _createdTimeOf(a.id);
    final bt = _createdTimeOf(b.id);

    if (at != bt) {
      return _sortAscending ? at.compareTo(bt) : bt.compareTo(at);
    }

    // 时间相同或都是非时间戳 id 时，用名称兜底，避免排序不稳定
    final nameCompare = a.name.compareTo(b.name);
    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    return a.id.compareTo(b.id);
  }

  int _compareCharacterByName(CharacterCard a, CharacterCard b) {
    final nameCompare = a.name.trim().compareTo(b.name.trim());

    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    // 名称相同，比如都是空名时，继续按创建时间排序
    return _compareCharacterByTime(a, b);
  }

  void _sortCharacters() {
    if (_sortBy == 'name') {
      _characters.sort(_compareCharacterByName);
    } else {
      _characters.sort(_compareCharacterByTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Stack(
        children: [
          // offstage 预加载 ChatPage：触发真实 UIEngine 初始化但不显示，
          // 就绪后（_onChatPreloaded）才移除并放大跳转。
          if (_chatPreloadHost != null)
            Offstage(offstage: true, child: _chatPreloadHost!),
          Scaffold(
            appBar: AppBar(
        title: const Text('角色库'),
        actions: [
          _buildSortButton(key: _sortButtonKey),
          IconButton(
            key: _exportButtonKey,
            icon: const Icon(Icons.ios_share),
            tooltip: '导出角色卡',
            onPressed: _showExportCharacterSheet,
          ),
          IconButton(
            key: _addButtonKey,
            icon: const Icon(Icons.add),
            tooltip: '新建或导入',
            onPressed: _showCreateOrImportSheet,
          ),
        ],
      ),

      floatingActionButton: _expandedIds.isNotEmpty
          ? SizedBox(
              key: _chatButtonGuideKey,
              width: 54,
              height: 54,
              child: _buildPlayFab(),
            )
          : null,

      body: SubPageBackdrop(
        child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (_deletingIds.isNotEmpty || _expandedIds.isNotEmpty) {
            setState(() {
              _deletingIds.clear();
              _expandedIds.clear();
            });
          }
          return false;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_deletingIds.isNotEmpty || _expandedIds.isNotEmpty) {
              setState(() {
                _deletingIds.clear();
                _expandedIds.clear();
              });
            }
          },
          child: Column(
            children: [
              _buildTagFilterBar(),
              Expanded(
                child: Builder(builder: (context) {
                  final visible = _visibleCharacters;
                  if (visible.isEmpty && _activeTagFilter != null) {
                    return Center(
                      child: Text(
                        '没有带「$_activeTagFilter」标签的角色',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }
                  return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final character = visible[index];
              final isDeleting = _deletingIds.contains(character.id);
              final isExpanded = _expandedIds.contains(character.id);

              return Container(
                key: isExpanded
                    ? _selectedCardKey
                    : (index == 0 ? _firstCardGuideKey : null),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isDeleting) return;
                        if (isExpanded) {
                          _openCharacterEdit(character, index);
                        } else {
                          setState(() {
                            _expandedIds.clear();
                            _expandedIds.add(character.id);
                          });
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          if (isDeleting) {
                            _deletingIds.remove(character.id);
                          } else {
                            _expandedIds.remove(character.id);
                            _deletingIds.add(character.id);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        constraints: BoxConstraints.expand(),
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isDeleting ? Colors.red.shade100 : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: character.cardImagePath.isNotEmpty
                                    ? Image.file(File(character.cardImagePath), fit: BoxFit.cover)
                                    : Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Icon(Icons.person, size: 80, color: Colors.white54),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: _SelectedOverlay(
                                character: character,
                                active: isExpanded,
                              ),
                            ),
                            if (isDeleting)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('确认删除'),
                                        content: Text('确定要删除角色“${character.name}”吗？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              _deleteCharacter(character.id);
                                            },
                                            child: const Text('删除', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                                    child: const Icon(Icons.delete, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
               );
            },
          );
                }),
              ),
            ],
          ),
        ),
          ),
        ),
        ),
          if (_showGuide)
            Positioned.fill(
              child: PageGuideOverlay(
                title: '角色库导览',
                hint: '点击紫色编号查看说明。本页主要介绍角色卡片、排序、导出、新建/导入和进入聊天。',
                targets: _guideTargets(context),
                onExit: _exitGuide,
              ),
            ),
        ],
      ),
    );
  }
}

/// 选中角色的信息浮层（三块玻璃抽屉），叠加在卡片上。
///
/// 贴边设计（不独立圆角）：名字贴左上、标签贴右上、介绍贴左下；
/// 玻璃片带主题紫色调（亮主题深紫、暗主题浅紫）。自持动画控制器：
/// active 变 true → 正向展开；变 false → 反向收回；换选角色（character
/// 变化）→ 重新正向播放。始终挂载在卡片上，以便关闭/切换都能补播动画。
class _SelectedOverlay extends StatefulWidget {
  final CharacterCard character;
  final bool active;
  const _SelectedOverlay({required this.character, required this.active});

  @override
  State<_SelectedOverlay> createState() => _SelectedOverlayState();
}

class _SelectedOverlayState extends State<_SelectedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _SelectedOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换选另一张角色：无论当前方向如何都重新正向播放。
    if (widget.character.id != oldWidget.character.id) {
      _controller.forward(from: 0);
      return;
    }
    // 选中状态翻转：开 → 正向，关 → 反向。
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    } else if (!widget.active && oldWidget.active) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 贴边玻璃：与卡片拐角重合的那一角用卡片圆角（16），其余角直角贴边。
  // - nameDrawer 贴左上：仅左上角圆角
  // - tagDrawer 贴右上：仅右上角圆角
  // - descDrawer 贴左下：仅左下角圆角
  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;

    // 玻璃片颜色：亮主题深紫、暗主题浅紫
    final glassColor = isNight
        ? const Color(0x88A79CFF) // 暗主题：浅紫
        : const Color(0x883E3A8A); // 亮主题：深紫
    final glassBorder = isNight
        ? const Color(0x66C9C4FF)
        : const Color(0x66B3AFFF);

    // 玻璃上的文字色：与玻璃反着来——亮主题深紫玻璃→白字，暗主题浅紫玻璃→深字
    final glassText = isNight ? const Color(0xFF1A1B2E) : Colors.white;
    // 介绍文字：比主文字稍透一点，但保证高对比、清晰
    final glassTextSoft =
        isNight ? const Color(0xFF24263B) : Colors.white.withValues(alpha: 0.92);

        // 卡片自身圆角
        const cardRadius = 16.0;
        // 梯形斜切量：贴边一侧拉长，另一侧向内斜切
        const slant = 18.0;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _anim.value;
            if (t <= 0.001 && !widget.active) {
              // 未选中且动画已完成反向 → 完全隐藏，节省模糊开销。
              return const SizedBox.shrink();
            }

            // 梯形玻璃片：贴卡片边缘的一侧拉长成梯形，另一侧斜切。
            // 填充用半透明玻璃色（BackdropFilter 提供模糊），描边用
            // CustomPainter 沿梯形路径绘制。
            Widget glass({required Widget child, required _DrawerShape shape}) {
              return ClipPath(
                clipper: _TrapezoidClipper(
                  shape: shape,
                  slant: slant,
                  radius: cardRadius,
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(color: glassColor),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _TrapezoidStrokePainter(
                              shape: shape,
                              slant: slant,
                              radius: cardRadius,
                              color: glassBorder,
                            ),
                          ),
                        ),
                      ),
                      child,
                    ],
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final cardW = constraints.maxWidth;
                final cardH = constraints.maxHeight;

                final name = widget.character.name.isEmpty
                    ? '未命名'
                    : widget.character.name;
                final tags = widget.character.meta.tags;
                final desc = widget.character.description;

                // 名字：贴左上，梯形（顶边贴顶拉长，右下斜切），从左往右展开
                final nameDrawer = Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scaleX: t.clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: glass(
                      shape: _DrawerShape.name,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardW * 0.5),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: glassText,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 标签：贴右上，梯形（右边缘贴右拉长，左下斜切），从上往下展开。
                // 无标签时整个抽屉不渲染（否则残留小点）。
                final tagDrawer = tags.isEmpty
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scaleY: t.clamp(0.0, 1.0),
                          alignment: Alignment.topCenter,
                          child: glass(
                            shape: _DrawerShape.tag,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: cardW * 0.5,
                                maxHeight: cardH * 0.66,
                              ),
                              child: _buildTags(tags, glassText: glassText, glassTextSoft: glassTextSoft),
                            ),
                          ),
                        ),
                      );

                // 介绍：贴左下，梯形（底边贴底拉长，右上斜切），从左往右展开
                final descDrawer = Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scaleX: t.clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: glass(
                      shape: _DrawerShape.desc,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardW * 0.85),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            desc.trim().isEmpty ? '暂无介绍' : desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: glassTextSoft,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                return IgnorePointer(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(top: 0, left: 0, child: nameDrawer),
                      Positioned(top: 0, right: 0, child: tagDrawer),
                      Positioned(bottom: 0, left: 0, child: descDrawer),
                    ],
                  ),
                );
              },
            );
          },
        );
  }

  /// 标签垂直排版：每个标签文字竖排（字符自上而下），最多两列，超出 +x。
  Widget _buildTags(
    List<String> tags, {
    required Color glassText,
    required Color glassTextSoft,
  }) {
    // 每列最多 4 个 → 两列最多 8 个，超出显示 +N
    const perCol = 4;
    const maxShown = perCol * 2;
    final shown = tags.take(maxShown).toList();
    final extra = tags.length - shown.length;

    final col1 = shown.take(perCol).toList();
    final col2 = shown.skip(perCol).toList();

    // 竖排文字：把字符串按字符竖排成一列
    Widget verticalText(String text, {double fontSize = 9}) {
      final chars = text.characters.toList();
      if (chars.length == 1) {
        return Text(
          text,
          style: TextStyle(color: glassText, fontSize: fontSize, height: 1.1),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in chars)
            Text(
              c,
              style: TextStyle(color: glassText, fontSize: fontSize, height: 1.1),
            ),
        ],
      );
    }

    Widget chip(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: glassTextSoft.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: verticalText(text),
      );
    }

    Widget column(List<String> list) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tg in list) Padding(padding: const EdgeInsets.only(bottom: 3), child: chip(tg)),
        ],
      );
    }

    if (shown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column(col1),
          if (col2.isNotEmpty) ...[
            const SizedBox(width: 5),
            column(col2),
          ],
          if (extra > 0) ...[
            const SizedBox(width: 5),
            chip('+$extra'),
          ],
        ],
      ),
    );
  }
}

/// 选中浮层抽屉的梯形形状。
///
/// 贴卡片边缘的那一侧拉长成梯形，另一侧斜切：
/// - name：贴左上 → 顶边（贴顶）拉长，右下斜切
/// - tag：贴右上 → 右边缘（贴右）拉长，左下斜切
/// - desc：贴左下 → 底边（贴底）拉长，右上斜切
enum _DrawerShape { name, tag, desc }

/// 梯形裁剪器：按形状生成梯形 Path（贴边角保留卡片圆角）。
class _TrapezoidClipper extends CustomClipper<Path> {
  final _DrawerShape shape;
  final double slant;
  final double radius;
  const _TrapezoidClipper({
    required this.shape,
    required this.slant,
    required this.radius,
  });

  Path _buildPath(Size s) {
    final w = s.width;
    final h = s.height;
    final r = radius;
    final sl = slant;

    switch (shape) {
      case _DrawerShape.name:
        // 贴左上：顶边全长（贴顶），右下斜切，左上圆角
        return Path()
          ..moveTo(0, r)
          ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
          ..lineTo(w, 0)
          ..lineTo(w - sl, h)
          ..lineTo(0, h)
          ..close();
      case _DrawerShape.tag:
        // 贴右上：右边缘全长（贴右），左下斜切，右上圆角
        return Path()
          ..moveTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
          ..lineTo(w, h)
          ..lineTo(sl, h)
          ..lineTo(0, 0)
          ..close();
      case _DrawerShape.desc:
        // 贴左下：底边全长（贴底），右上斜切，左下圆角
        return Path()
          ..moveTo(0, 0)
          ..lineTo(w - sl, 0)
          ..lineTo(w, h)
          ..lineTo(r, h)
          ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
          ..close();
    }
  }

  @override
  Path getClip(Size size) => _buildPath(size);

  @override
  bool shouldReclip(covariant _TrapezoidClipper oldClipper) =>
      oldClipper.shape != shape ||
      oldClipper.slant != slant ||
      oldClipper.radius != radius;
}

/// 梯形描边绘制器：沿梯形 Path 画描边（贴边角保留卡片圆角）。
class _TrapezoidStrokePainter extends CustomPainter {
  final _DrawerShape shape;
  final double slant;
  final double radius;
  final Color color;
  const _TrapezoidStrokePainter({
    required this.shape,
    required this.slant,
    required this.radius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final clipper = _TrapezoidClipper(
      shape: shape,
      slant: slant,
      radius: radius,
    );
    canvas.drawPath(
      clipper.getClip(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrapezoidStrokePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.slant != slant ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}
