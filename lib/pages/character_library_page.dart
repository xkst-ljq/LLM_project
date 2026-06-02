// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/character_card.dart';
import '../services/database_service.dart';
import 'character_edit_page.dart';
import 'character_system_prompt_edit_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/default_image.dart';
import 'chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CharacterLibraryPage extends StatefulWidget {
  const CharacterLibraryPage({super.key});

  @override
  State<CharacterLibraryPage> createState() => _CharacterLibraryPageState();
}

class _CharacterLibraryPageState extends State<CharacterLibraryPage> {
  final List<CharacterCard> _characters = [];
  final Set<String> _expandedIds = {};
  final Set<String> _deletingIds = {};
  static const String _sortByKey = 'character_sort_by';
  static const String _sortAscendingKey = 'character_sort_ascending';

  @override
  void initState() {
    super.initState();
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

  void _addCharacter() async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
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
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => CharacterEditOverlay(
          character: character,
          cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
        ),
      ),
    ).then((_) => _loadCharacters());
  }

  String _sortBy = 'time'; // 默认按创建时间
  bool _sortAscending = true;

  void _sortCharacters() {  // 对应 _sortBackgrounds / _sortWorldBooks
    if (_sortBy == 'name') {
      _characters.sort((a, b) => _sortAscending
          ? a.name.compareTo(b.name)
          : b.name.compareTo(a.name));
    } else {
      _characters.sort((a, b) => _sortAscending
          ? a.id.compareTo(b.id)
          : b.id.compareTo(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色库'),
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
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              if (_expandedIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先点击一个角色卡片')),
                );
                return;
              }
              final expandedId = _expandedIds.first;
              final character = _characters.firstWhere((c) => c.id == expandedId);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatPage(character: character)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCharacter,
          ),
        ],
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

              return AspectRatio(
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
              );
            },
          ),
        ),
      ),
    );
  }
}

// ========================= 预览悬浮窗 =========================
class _CharacterEditOverlay extends StatefulWidget {
  final CharacterCard character;
  final Rect cardRect;
  final Function(CharacterCard) onSave;
  final Set<String> existingNames;

  const _CharacterEditOverlay({
    required this.character,
    required this.cardRect,
    required this.onSave,
    required this.existingNames,
  });

  @override
  State<_CharacterEditOverlay> createState() => _CharacterEditOverlayState();
}

class _CharacterEditOverlayState extends State<_CharacterEditOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<Rect?>? _rectAnimation;

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _systemPromptCtrl;

  bool _editingName = false;
  bool _editingDesc = false;

  bool _showNameError = false;
  String _nameErrorText = '';
  String? _selectedWorldBookId;
  String _selectedWorldBookName = '';
  late String _cardImagePath;
  late String _avatarImagePath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _nameCtrl = TextEditingController(text: widget.character.name);
    _descCtrl = TextEditingController(text: widget.character.description);
    _systemPromptCtrl = TextEditingController(text: widget.character.systemPrompt);
    _cardImagePath = widget.character.cardImagePath;
    _avatarImagePath = widget.character.avatar;
    _selectedWorldBookId = widget.character.worldBookId;
    if (_selectedWorldBookId != null && _selectedWorldBookId!.isNotEmpty) {
      _loadWorldBookName(_selectedWorldBookId!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rectAnimation != null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final targetWidth = screenWidth * 0.9;
    final targetHeight = screenHeight * 0.65;
    final targetRect = Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: targetWidth,
      height: targetHeight,
    );
    _rectAnimation = RectTween(
      begin: widget.cardRect,
      end: targetRect,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    final newName = _nameCtrl.text.trim();
    if (widget.existingNames.contains(newName) && newName != widget.character.name) {
      setState(() {
        _nameErrorText = '角色名“$newName”已存在，请换一个名字。';
        _showNameError = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showNameError = false);
      });
      return;
    }

    final updated = CharacterCard(
      id: widget.character.id,
      name: newName,
      avatar: _avatarImagePath,
      cardImagePath: _cardImagePath,
      description: _descCtrl.text.trim(),
      systemPrompt: _systemPromptCtrl.text.trim(),
        worldBookId: _selectedWorldBookId ?? '',
    );
    widget.onSave(updated);
    await _animController.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() async {
    await _animController.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  void _showImageSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('自定义外观', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () => _pickAndCropImage(isAvatar: true),
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: _avatarImagePath.isNotEmpty
                                ? DecorationImage(image: FileImage(File(_avatarImagePath)), fit: BoxFit.cover)
                                : null,
                            color: _avatarImagePath.isEmpty ? Colors.grey[300] : null,
                          ),
                          child: _avatarImagePath.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('头像', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () => _pickAndCropImage(isAvatar: false),
                        child: Container(
                          width: 80, height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: _cardImagePath.isNotEmpty
                                ? DecorationImage(image: FileImage(File(_cardImagePath)), fit: BoxFit.cover)
                                : null,
                            color: _cardImagePath.isEmpty ? Colors.grey[300] : null,
                          ),
                          child: _cardImagePath.isEmpty ? const Icon(Icons.photo, size: 40, color: Colors.grey) : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('卡片封面', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWorldBookPicker() async {
    final books = await DatabaseService.getAllWorldBooks();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择世界书', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...books.map((b) => ListTile(
            title: Text(b['name'] as String? ?? '未命名'),
            selected: b['id'] == _selectedWorldBookId,
            onTap: () {
              setState(() {
                _selectedWorldBookId = b['id'] as String;
                _selectedWorldBookName = b['name'] as String? ?? '';
              });
              Navigator.pop(ctx);
            },
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.clear, color: Colors.red),
            title: const Text('解除绑定', style: TextStyle(color: Colors.red)),
            onTap: () {
              setState(() {
                _selectedWorldBookId = null;
                _selectedWorldBookName = '';
              });
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _loadWorldBookName(String id) async {
    final books = await DatabaseService.getAllWorldBooks();
    final book = books.firstWhere(
          (b) => b['id'] == id,
      orElse: () => {'name': ''},
    );
    if (mounted) {
      setState(() {
        _selectedWorldBookName = book['name'] as String? ?? '';
      });
    }
  }

  Future<void> _pickAndCropImage({required bool isAvatar}) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(isAvatar ? '选择头像来源' : '选择卡片来源'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              child: const Text('从相册选择'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Text('拍照'),
            ),
          ],
        ),
      );
      if (source == null) return;

      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return;

      CroppedFile? croppedFile;
      if (isAvatar) {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(toolbarTitle: '裁剪头像', toolbarColor: Colors.blue, lockAspectRatio: true),
            IOSUiSettings(title: '裁剪头像'),
          ],
        );
      } else {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 2, ratioY: 3),
          uiSettings: [
            AndroidUiSettings(toolbarTitle: '裁剪卡片', toolbarColor: Colors.blue, lockAspectRatio: true),
            IOSUiSettings(title: '裁剪卡片'),
          ],
        );
      }
      if (croppedFile == null) return;

      final savedPath = await _saveImageToLocal(croppedFile.path);
      if (savedPath != null) {
        setState(() {
          if (isAvatar) {
            _avatarImagePath = savedPath;
          } else {
            _cardImagePath = savedPath;
          }
        });
        // 关闭旧的自定义外观对话框
        Navigator.of(context).pop();
        // 重新打开，显示新图片
        _showImageSourceDialog(context);
      }
    } catch (e) {
      debugPrint('图片处理出错: $e');
    }
  }

  Future<String?> _saveImageToLocal(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'card_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = p.join(dir.path, fileName);
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rectAnimation == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cancel,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black54),
            ),
          ),
          AnimatedBuilder(
            animation: _rectAnimation!,
            builder: (context, child) {
              final rect = _rectAnimation!.value!;
              return Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: Material(
                  elevation: 16,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: EdgeInsets.zero,
                    child: GestureDetector(
                      onTap: () {},
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onLongPress: () => _showImageSourceDialog(context),
                                        child: CircleAvatar(
                                          radius: 30,
                                          backgroundImage: _avatarImagePath.isNotEmpty
                                              ? FileImage(File(_avatarImagePath))
                                              : null,
                                          child: _avatarImagePath.isEmpty
                                              ? const Icon(Icons.person, size: 40)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text('角色名称', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                                const SizedBox(width: 4),
                                                GestureDetector(
                                                  onTap: () => setState(() => _editingName = !_editingName),
                                                  child: Icon(_editingName ? Icons.check : Icons.edit, size: 16, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            _editingName
                                                ? TextField(controller: _nameCtrl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true))
                                                : Text(
                                              _nameCtrl.text.isEmpty ? '输入角色名称' : _nameCtrl.text,
                                              style: TextStyle(fontSize: 18, fontWeight: _nameCtrl.text.isEmpty ? FontWeight.normal : FontWeight.bold, color: _nameCtrl.text.isEmpty ? Colors.grey : null),
                                            ),
                                            if (_showNameError)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                                  child: Text(_nameErrorText, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text('简短描述', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                                const SizedBox(width: 4),
                                                GestureDetector(
                                                  onTap: () => setState(() => _editingDesc = !_editingDesc),
                                                  child: Icon(_editingDesc ? Icons.check : Icons.edit, size: 16, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            _editingDesc
                                                ? TextField(controller: _descCtrl, autofocus: true, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true))
                                                : Text(
                                              _descCtrl.text.isEmpty ? '暂无简述' : _descCtrl.text,
                                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      const Text('角色详细设定', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      const Spacer(),
                                      TextButton.icon(
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: const Text('编辑'),
                                        onPressed: () async {
                                          final result = await Navigator.push<String>(
                                            context,
                                            MaterialPageRoute(builder: (_) => CharacterSystemPromptEditPage(initialText: _systemPromptCtrl.text)),
                                          );
                                          if (result != null) {
                                            _systemPromptCtrl.text = result;
                                            setState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  Container(
                                    height: 120,
                                    width: double.infinity,
                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.all(8),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        _systemPromptCtrl.text.isEmpty ? '未设置角色详细设定' : _systemPromptCtrl.text,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 绑定世界书
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.book, size: 20, color: Colors.grey),
                            title: Text(
                              _selectedWorldBookId != null && _selectedWorldBookId!.isNotEmpty
                                  ? _selectedWorldBookName
                                  : '绑定世界书',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedWorldBookId != null && _selectedWorldBookId!.isNotEmpty
                                    ? Colors.black87
                                    : Colors.grey,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                            onTap: () => _showWorldBookPicker(),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(onPressed: _cancel, child: const Text('取消')),
                                ElevatedButton(onPressed: _save, child: const Text('保存')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
