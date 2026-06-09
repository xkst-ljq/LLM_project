// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/character_card.dart';
import '../services/database_service.dart';
import 'character_edit_page.dart';
import '../utils/default_image.dart';
import 'chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/character_card_asset_service.dart';
import '../services/character_card_png_asset_service.dart';
import '../utils/id_utils.dart';
import '../utils/app_feedback.dart';
import '../widgets/page_guide_overlay.dart';

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

class _CharacterLibraryPageState extends State<CharacterLibraryPage> {
  final List<CharacterCard> _characters = [];
  final Set<String> _expandedIds = {};
  final Set<String> _deletingIds = {};

  late bool _showGuide;
  final _sortButtonKey = GlobalKey();
  final _exportButtonKey = GlobalKey();
  final _addButtonKey = GlobalKey();
  final _firstCardGuideKey = GlobalKey();
  final _chatButtonGuideKey = GlobalKey();
  static const String _sortByKey = 'character_sort_by';
  static const String _sortAscendingKey = 'character_sort_ascending';

  @override
  void initState() {
    super.initState();
    _showGuide = widget.startGuide;
    _loadSortPreference();
    _loadCharacters();
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

  void _openSelectedCharacterChat() {
    final character = _getSelectedCharacter();

    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击一个角色卡片')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatPage(character: character)),
    );
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

      floatingActionButton: SizedBox(
        key: _chatButtonGuideKey,
        width: 54,
        height: 54,
        child: FloatingActionButton(
          onPressed: _openSelectedCharacterChat,
          backgroundColor: Theme.of(context).primaryColor,
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
        ),
      ),

      body: NotificationListener<ScrollUpdateNotification>(
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
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _characters.length,
            itemBuilder: (context, index) {
              final character = _characters[index];
              final isDeleting = _deletingIds.contains(character.id);
              final isExpanded = _expandedIds.contains(character.id);

              return Container(
                key: index == 0 ? _firstCardGuideKey : null,
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
                            if (isExpanded)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        character.name.isEmpty ? '未命名' : character.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      if (character.description.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          character.description,
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
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
