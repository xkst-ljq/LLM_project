import 'package:flutter/material.dart';
import '../models/world_book.dart';
import '../services/database_service.dart';
import 'world_book_edit_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  void _sortWorldBooks() {
    if (_sortBy == 'name') {
      _worldBooks.sort((a, b) => _sortAscending
          ? a.name.compareTo(b.name)
          : b.name.compareTo(a.name));
    } else {
      _worldBooks.sort((a, b) => _sortAscending
          ? a.id.compareTo(b.id)
          : b.id.compareTo(a.id));
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
          // 排序按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序方式',
            onSelected: (value) => _updateSort(value, null),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'name', child: Text('按名称排序')),
              const PopupMenuItem(value: 'time', child: Text('按创建时间排序')),
            ],
          ),
          // 升序/降序切换
          IconButton(
            icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _sortAscending ? '升序' : '降序',
            onPressed: () => _updateSort(null, !_sortAscending),
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _addWorldBook),
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
            onLongPress: () => _deleteWorldBook(wb),
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