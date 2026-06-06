import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/world_book.dart';
import '../services/database_service.dart';
import '../services/world_book_asset_service.dart';
import 'world_book_edit_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/id_utils.dart';
import '../utils/app_feedback.dart';

class WorldBookImportPreview {
  final File file;
  final String name;
  final String description;
  final int entryCount;
  final List<String> checks;

  WorldBookImportPreview({
    required this.file,
    required this.name,
    required this.description,
    required this.entryCount,
    required this.checks,
  });
}

class WorldBookLibraryPage extends StatefulWidget {
  const WorldBookLibraryPage({super.key});

  @override
  State<WorldBookLibraryPage> createState() => _WorldBookLibraryPageState();
}

class _WorldBookLibraryPageState extends State<WorldBookLibraryPage> {
  List<WorldBook> _worldBooks = [];
  final Set<String> _expandedIds = {}; // 记录当前展开彩带的卡片ID
  bool _sortAscending = true; // 默认升序（时间从旧到新，名称A-Z）
  static const String _sortByKey = 'wordbook_sort_by';
  static const String _sortAscendingKey = 'wordbook_sort_ascending';

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _loadWorldBooks();
  }

  Widget _buildSortButton() {
    return Builder(
      builder: (buttonContext) {
        return InkWell(
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

  void _showCreateOrImportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建世界书'),
              onTap: () {
                Navigator.pop(ctx);
                _addWorldBook();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('导入世界书'),
              subtitle: const Text('导入 LLM Project 世界书 JSON'),
              onTap: () {
                Navigator.pop(ctx);
                _importWorldBookWithPreview();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportWorldBook(WorldBook wb) async {
    try {
      final file = await WorldBookAssetService.exportWorldBook(wb);

      final downloadsPath =
      await WorldBookAssetService.saveWorldBookToDownloads(file);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: Text(
            downloadsPath != null
                ? '世界书已保存到：\n$downloadsPath'
                : '世界书已导出到应用目录：\n${file.path}',
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
                  text: 'LLM Project 世界书',
                );
              },
              child: const Text('分享'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      await AppFeedback.showErrorDialog(
        context,
        title: '导出世界书失败',
        error: e,
        message: '世界书导出过程中出现错误。',
      );
    }
  }

  void _showWorldBookActions(WorldBook wb) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('导出世界书'),
              onTap: () {
                Navigator.pop(ctx);
                _exportWorldBook(wb);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                '删除世界书',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteWorldBook(wb);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<WorldBookImportPreview> _buildWorldBookImportPreview(File file) async {
    final wb = await WorldBookAssetService.readWorldBookAsset(file);

    int entryCount = 0;
    try {
      entryCount = (jsonDecode(wb.entriesJson) as List).length;
    } catch (_) {}

    return WorldBookImportPreview(
      file: file,
      name: wb.name,
      description: wb.description,
      entryCount: entryCount,
      checks: const [
        '内部识别标识完整',
        '世界书数据完整',
      ],
    );
  }

  Future<bool> _showWorldBookImportPreview(
      WorldBookImportPreview preview,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入世界书'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('条目数量：${preview.entryCount} 个'),
              if (preview.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '描述：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  preview.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '完整性检查：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...preview.checks.map(
                    (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
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

  Future<void> _importWorldBookWithPreview() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LLM Project 世界书文件',
      type: FileType.any,
      allowMultiple: false,
    );

    if (!mounted) return;

    if (picked == null || picked.files.isEmpty) return;

    final path = picked.files.single.path;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件')),
      );
      return;
    }

    final file = File(path);
    late WorldBookImportPreview preview;

    try {
      preview = await _buildWorldBookImportPreview(file);
    } catch (e) {
      if (!mounted) return;
      await AppFeedback.showErrorDialog(
        context,
        title: '读取世界书失败',
        error: e,
        message: '无法识别该世界书文件。',
        suggestion: '请选择由 LLM Project 导出的 .llmworld.json 文件。不要直接导入其他软件的世界书 JSON。',
      );
      return;
    }

    if (!mounted) return;

    final confirmed = await _showWorldBookImportPreview(preview);
    if (!confirmed) return;

    try {
      await WorldBookAssetService.importWorldBook(file);
      await _loadWorldBooks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('世界书导入成功')),
      );
    } catch (e) {
      if (!mounted) return;

      await AppFeedback.showErrorDialog(
        context,
        title: '导入世界书失败',
        error: e,
        message: '世界书数据读取成功，但写入本地数据库时失败。',
      );
    }
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sortBy = prefs.getString(_sortByKey) ?? 'time';
      _sortAscending = prefs.getBool(_sortAscendingKey) ?? true;
    });
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
      _sortWorldBooks();
    });
  }

  Future<void> _loadWorldBooks() async {
    final data = await DatabaseService.getAllWorldBooks();
    setState(() {
      _worldBooks = data.map((e) => WorldBook.fromDb(e)).toList();
      _sortWorldBooks();
    });
  }

  void _addWorldBook() async {
    final newId = IdUtils.timestampId();
    await DatabaseService.insertWorldBook({
      'id': newId,
      'name': '新世界书 ${_worldBooks.length + 1}',
      'description': '',
      'detailed_setting': '',
      'cover_image_path': '',
    });
    _loadWorldBooks();
  }

  int _createdTimeOf(String id) {
    return int.tryParse(id) ?? 0;
  }

  int _compareWorldBookByTime(WorldBook a, WorldBook b) {
    final at = _createdTimeOf(a.id);
    final bt = _createdTimeOf(b.id);

    if (at != bt) {
      return _sortAscending ? at.compareTo(bt) : bt.compareTo(at);
    }

    final nameCompare = a.name.compareTo(b.name);
    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    return a.id.compareTo(b.id);
  }

  int _compareWorldBookByName(WorldBook a, WorldBook b) {
    final nameCompare = a.name.trim().compareTo(b.name.trim());

    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    return _compareWorldBookByTime(a, b);
  }

  void _sortWorldBooks() {
    if (_sortBy == 'name') {
      _worldBooks.sort(_compareWorldBookByName);
    } else {
      _worldBooks.sort(_compareWorldBookByTime);
    }
  }

  Color _worldBookColor(String seed) {
    const colors = [
      Color(0xFF6D5DF6), // 紫
      Color(0xFF00A7A7), // 青
      Color(0xFFE57373), // 红
      Color(0xFFFFB74D), // 橙
      Color(0xFF81C784), // 绿
      Color(0xFF64B5F6), // 蓝
      Color(0xFFBA68C8), // 紫粉
      Color(0xFF4DB6AC), // 蓝绿
      Color(0xFF9575CD), // 深紫
      Color(0xFFFF8A65), // 暖橙
    ];

    final source = seed.trim().isEmpty ? 'world_book' : seed.trim();
    final index = source.hashCode.abs() % colors.length;
    return colors[index];
  }

  String _worldBookInitial(WorldBook wb) {
    final name = wb.name.trim();
    if (name.isEmpty) return '书';

    // 用 runes 避免 emoji / 部分特殊字符截断
    return String.fromCharCode(name.runes.first);
  }

  List<String> _worldBookTags(WorldBook wb) {
    final tags = <String>[];

    for (final entry in wb.entries) {
      final keyword = entry.keyword.trim();
      if (keyword.isEmpty) continue;

      final parts = keyword
          .split(RegExp(r'[,，、\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);

      for (final part in parts) {
        if (!tags.contains(part)) {
          tags.add(part);
        }

        if (tags.length >= 4) {
          return tags;
        }
      }
    }

    return tags;
  }

  Widget _buildWorldBookCover(WorldBook wb) {
    final color = _worldBookColor(wb.name.isNotEmpty ? wb.name : wb.id);
    final entries = wb.entries;

    final entryCount = entries.length;
    final alwaysActiveCount = entries.where((e) => e.alwaysActive).length;
    final keywordCount =
        entries.where((e) => e.keyword.trim().isNotEmpty).length;

    final tags = _worldBookTags(wb);
    final initial = _worldBookInitial(wb);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.58),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 背景装饰圆
          Positioned(
            right: -36,
            top: -28,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            left: -28,
            bottom: -34,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部类型标识
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'WORLD BOOK',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // 中间首字标识
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 名称
                Text(
                  wb.name.trim().isEmpty ? '未命名世界书' : wb.name.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 4),

                // 描述
                if (wb.description.trim().isNotEmpty)
                  Text(
                    wb.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  )
                else
                  Text(
                    '暂无描述',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),

                const SizedBox(height: 8),

                // 关键词标签
                if (tags.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: tags.take(3).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          '#$tag',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.90),
                            fontSize: 9,
                            height: 1.1,
                          ),
                        ),
                      );
                    }).toList(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '无关键词',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 9,
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // 底部统计
                Text(
                  '条目 $entryCount · 关键词 $keywordCount · 常驻 $alwaysActiveCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _deleteWorldBook(WorldBook wb) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除世界书“${wb.name}”吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseService.deleteWorldBook(wb.id);
              _loadWorldBooks();
              _expandedIds.remove(wb.id);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openWorldBookEdit(WorldBook wb, int index) {
    // 计算卡片网格位置
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

    Navigator.of(context)
        .push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        barrierLabel: '关闭',
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => WorldBookEditOverlay(
          worldBook: wb,
          cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    )
        .then((_) => _loadWorldBooks());
  }

  String _sortBy = 'time'; // 默认按创建时间

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('世界书库'),
        actions: [
          _buildSortButton(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建或导入',
            onPressed: _showCreateOrImportSheet,
          ),
        ],
      ),
      body: _worldBooks.isEmpty
          ? const Center(child: Text('暂无世界书，点击 + 添加'))
          : GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _worldBooks.length,
        itemBuilder: (context, index) {
          final wb = _worldBooks[index];
          final isExpanded = _expandedIds.contains(wb.id);

          return GestureDetector(
            onTap: () => _openWorldBookEdit(wb, index),
            onLongPress: () => _showWorldBookActions(wb),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                children: [
                  // 纯封面图（暂时用灰色背景 + 世界书图标）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildWorldBookCover(wb),
                  ),
                  // 名称彩带
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
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}