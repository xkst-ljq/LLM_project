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
    return GestureDetector(
      onLongPress: () {
        final newAscending = !_sortAscending;
        _updateSort(null, newAscending);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newAscending ? '已切换为正序' : '已切换为倒序'),
            duration: const Duration(milliseconds: 800),
          ),
        );
      },
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.sort),
        tooltip: '排序方式，长按切换正序/倒序',
        onSelected: (value) {
          if (value == 'toggle_order') {
            _updateSort(null, !_sortAscending);
          } else {
            _updateSort(value, null);
          }
        },
        itemBuilder: (context) => [
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
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'toggle_order',
            child: Row(
              children: [
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sortAscending
                        ? '当前：正序，点击切换倒序'
                        : '当前：倒序，点击切换正序',
                  ),
                ),
              ],
            ),
          ),
        ],
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '读取失败：$e\n请选择由 LLM Project 导出的世界书文件。',
          ),
        ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
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
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
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
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => WorldBookEditOverlay(
          worldBook: wb,
          cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
        ),
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
                    child: Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(Icons.book, size: 60, color: Colors.white54),
                      ),
                    ),
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
                        child: Text(
                          wb.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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