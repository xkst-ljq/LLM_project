import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/character_card.dart';
import '../models/character_entry.dart';
import '../services/database_service.dart';

class CharacterEditOverlay extends StatefulWidget {
  final CharacterCard character;
  final Rect? cardRect;

  const CharacterEditOverlay({super.key, required this.character, this.cardRect});

  @override
  State<CharacterEditOverlay> createState() => _CharacterEditOverlayState();
}

class _CharacterEditOverlayState extends State<CharacterEditOverlay>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  String _avatarPath = '';
  String _cardImagePath = '';
  String _cardType = 'character';
  late List<CharacterEntry> _entries;
  final Set<String> _expandedEntryIds = {};
  // 子级抽屉折叠状态：默认展开；加入集合表示该子级被折叠
  final Set<String> _collapsedTreeNodeIds = {};
  late List<OpeningGreeting> _greetings;
  final ImagePicker _picker = ImagePicker();
  String? _worldBookId;
  String _worldBookName = '';
  bool _showNameError = false;
  String _nameErrorText = '';

  late AnimationController _animController;
  Animation<Rect?>? _rectAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _nameCtrl = TextEditingController(text: widget.character.name);
    _descCtrl = TextEditingController(text: widget.character.description);
    _avatarPath = widget.character.avatar;
    _cardImagePath = widget.character.cardImagePath;
    _cardType = widget.character.cardType.isEmpty ? 'character' : widget.character.cardType;
    _worldBookId = widget.character.worldBookId;
    if (_worldBookId != null && _worldBookId!.isNotEmpty) {
      _loadWorldBookName();
    }
    _entries = _parseEntries(widget.character.entriesJson);
    _greetings = _parseGreetings(widget.character.openingGreetings);
    for (final entry in _entries) {
      if (entry.enabled) _expandedEntryIds.add(entry.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rectAnimation != null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final targetWidth = screenWidth * 0.92;
    final targetHeight = screenHeight * 0.85;
    final targetRect = Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: targetWidth,
      height: targetHeight,
    );
    final beginRect = widget.cardRect ?? Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: 0,
      height: 0,
    );
    _rectAnimation = RectTween(begin: beginRect, end: targetRect).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<CharacterEntry> _parseEntries(String json) {
    try {
      final list = jsonDecode(json) as List;
      if (list.isEmpty) return _createDefaultEntries();
      return list.map((e) => CharacterEntry.fromJson(e)).toList();
    } catch (_) {
      return _createDefaultEntries();
    }
  }

  List<CharacterEntry> _createDefaultEntries() {
    if (_cardType == 'system') {
      return [
        CharacterEntry(id: 'system_name', title: '系统名称', content: '', enabled: true, isCustom: false, sortOrder: 0),
        CharacterEntry(id: 'system_summary', title: '系统概要', content: '', enabled: true, isCustom: false, sortOrder: 1),
        CharacterEntry(id: 'system_details', title: '系统详情', content: jsonEncode({'world_setting': '', 'worldview': '', 'system_mechanism': ''}), enabled: false, isCustom: false, sortOrder: 2),
        CharacterEntry(id: 'protagonist', title: '主角设定', content: jsonEncode({'name': '', 'detail': {'race': '', 'gender': '', 'age': '', 'body': '', 'background': ''}}), enabled: false, isCustom: false, sortOrder: 3),
        CharacterEntry(id: 'plot', title: '剧情', content: jsonEncode({'cause': '', 'events': '', 'goal': '', 'possible_endings': ''}), enabled: false, isCustom: false, sortOrder: 4),
      ];
    } else {
      return [
        CharacterEntry(id: 'name_entry', title: '名称', content: jsonEncode({'last_name': '', 'first_name': '', 'other': ''}), enabled: true, isCustom: false, sortOrder: 0),
        CharacterEntry(id: 'relationship', title: '与用户关系', content: '', enabled: true, isCustom: false, sortOrder: 1),
        CharacterEntry(id: 'body', title: '身体数据', content: jsonEncode({'race': '', 'gender': '', 'age': '', 'height': '', 'weight': '', 'measurements': '', 'other': ''}), enabled: false, isCustom: false, sortOrder: 2),
        CharacterEntry(id: 'psychology', title: '心理数据', content: jsonEncode({'personality': '', 'thoughts': '', 'interests': ''}), enabled: false, isCustom: false, sortOrder: 3),
        CharacterEntry(id: 'background', title: '背景数据', content: jsonEncode({'origin': '', 'experiences': '', 'current': ''}), enabled: false, isCustom: false, sortOrder: 4),
      ];
    }
  }

  List<OpeningGreeting> _parseGreetings(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => OpeningGreeting.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadWorldBookName() async {
    final books = await DatabaseService.getAllWorldBooks();
    final book = books.firstWhere((b) => b['id'] == _worldBookId, orElse: () => {'name': ''});
    if (mounted) setState(() => _worldBookName = book['name'] as String? ?? '');
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

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    final all = await DatabaseService.getAllCharacters();
    final existingNames = all.where((c) => c['id'] != widget.character.id).map((c) => c['name'] as String).toSet();
    if (existingNames.contains(newName)) {
      setState(() { _nameErrorText = '角色名"$newName"已存在，请换一个名字。'; _showNameError = true; });
      Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _showNameError = false); });
      return;
    }
    widget.character.name = newName;
    widget.character.description = _descCtrl.text.trim();
    widget.character.avatar = _avatarPath;
    widget.character.cardImagePath = _cardImagePath;
    widget.character.cardType = _cardType;
    widget.character.worldBookId = _worldBookId ?? '';
    widget.character.entriesJson = jsonEncode(_entries.map((e) => e.toJson()).toList());
    widget.character.openingGreetings = jsonEncode(_greetings.map((g) => g.toJson()).toList());
    await DatabaseService.updateCharacter({
      'id': widget.character.id,
      'name': widget.character.name,
      'description': widget.character.description,
      'avatar': widget.character.avatar,
      'card_image_path': widget.character.cardImagePath,
      'system_prompt': widget.character.systemPrompt,
      'world_book_id': widget.character.worldBookId,
      'background_id': widget.character.backgroundId,
      'user_name': widget.character.userName,
      'user_avatar': widget.character.userAvatar,
      'user_detail_setting': widget.character.userDetailSetting,
      'card_type': widget.character.cardType,
      'entries_json': widget.character.entriesJson,
      'opening_greetings': widget.character.openingGreetings,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _pickImage(bool isAvatar) async {
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

    if (source == null || !mounted) return;

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: isAvatar ? 1024 : 2048,
      );

      if (pickedFile == null || !mounted) return;

      CroppedFile? croppedFile;

      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: isAvatar
              ? const CropAspectRatio(ratioX: 1, ratioY: 1)
              : const CropAspectRatio(ratioX: 2, ratioY: 3),
          maxWidth: isAvatar ? 512 : 1200,
          maxHeight: isAvatar ? 512 : 1800,
          compressQuality: 90,
          compressFormat: ImageCompressFormat.jpg,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isAvatar ? '裁剪头像' : '裁剪卡片',
              toolbarColor: Colors.blue,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: isAvatar ? '裁剪头像' : '裁剪卡片',
            ),
          ],
        );
      } catch (e, s) {
        debugPrint('裁剪失败，使用原图: $e');
        debugPrint('$s');
      }

      if (!mounted) return;

      final String sourcePath = croppedFile?.path ?? pickedFile.path;
      final savedPath = await _saveImageToLocal(sourcePath);

      if (!mounted) return;

      if (savedPath != null) {
        setState(() {
          if (isAvatar) {
            _avatarPath = savedPath;
          } else {
            _cardImagePath = savedPath;
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片保存失败')),
        );
      }
    } catch (e, s) {
      debugPrint('选择图片失败: $e');
      debugPrint('$s');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  void _toggleExpand(String id) => setState(() { if (_expandedEntryIds.contains(id)) { _expandedEntryIds.remove(id); } else { _expandedEntryIds.add(id); } });
  void _toggleEntryEnabled(CharacterEntry entry) => setState(() { entry.enabled = !entry.enabled; if (entry.enabled) { _expandedEntryIds.add(entry.id); } else { _expandedEntryIds.remove(entry.id); } });

  void _editEntry(CharacterEntry entry) async {
    CharacterEntry? result;
    if (entry.isCustom) {
      result = await Navigator.push<CharacterEntry>(context, MaterialPageRoute(builder: (_) => _CustomEntryEditPage(entry: entry)));
    } else {
      result = await _showFixedEntryEditor(entry);
    }
    if (result != null) {
      setState(() { final index = _entries.indexWhere((e) => e.id == result!.id); if (index != -1) _entries[index] = result!; });
    }
  }

  Future<CharacterEntry?> _showFixedEntryEditor(CharacterEntry entry) async {
    Map<String, dynamic> fields;
    try {
      fields = jsonDecode(entry.content.isEmpty ? '{}' : entry.content) as Map<String, dynamic>;
    } catch (_) {
      fields = {};
    }
    // 如果字段为空，添加一个默认字段来承载纯文本
    if (fields.isEmpty) {
      fields['内容'] = entry.content;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _FixedEntryEditDialog(entry: entry, fields: fields),
    );

    if (result != null) {
      // 如果只有一个字段且键名为'内容'，保存为纯文本（非 JSON）
      if (result.keys.length == 1 && result.containsKey('内容')) {
        entry.content = result['内容'] as String;
      } else {
        entry.content = jsonEncode(result);
      }
      return entry;
    }
    return null;
  }

  void _addCustomEntry() {
    final newEntry = CharacterEntry(id: DateTime.now().millisecondsSinceEpoch.toString(), title: '新条目', content: '', enabled: false, isCustom: true, sortOrder: _entries.where((e) => e.isCustom).length);
    setState(() => _entries.add(newEntry));
  }

  void _deleteEntry(CharacterEntry entry) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('确认删除'), content: Text('确定要删除条目"${entry.title}"吗？'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _entries.removeWhere((e) => e.id == entry.id)); }, child: const Text('删除', style: TextStyle(color: Colors.red))),
    ]));
  }

  void _addGreeting() => setState(() => _greetings.add(OpeningGreeting(id: DateTime.now().millisecondsSinceEpoch.toString(), content: '')));

  void _editGreeting(OpeningGreeting greeting) async {
    final controller = TextEditingController(text: greeting.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑开场白'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '输入开场白内容...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 延迟 dispose，确保对话框完全关闭
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (result != null && mounted) {
      setState(() => greeting.content = result);
    }
  }

  void _deleteGreeting(OpeningGreeting greeting) => setState(() => _greetings.removeWhere((g) => g.id == greeting.id));

  void _pickWorldBook() async {
    final books = await DatabaseService.getAllWorldBooks();
    if (!mounted) return;
    showModalBottomSheet(context: context, builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('选择世界书', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      ...books.map((b) => ListTile(title: Text(b['name'] as String? ?? '未命名'), selected: b['id'] == _worldBookId, onTap: () { setState(() { _worldBookId = b['id'] as String; _worldBookName = b['name'] as String? ?? ''; }); Navigator.pop(ctx); })),
      const Divider(),
      ListTile(leading: const Icon(Icons.clear, color: Colors.red), title: const Text('解除绑定', style: TextStyle(color: Colors.red)), onTap: () { setState(() { _worldBookId = null; _worldBookName = ''; }); Navigator.pop(ctx); }),
      const SizedBox(height: 8),
    ]));
  }

  void _switchCardType(String type) {
    if (type == _cardType) return;
    setState(() { _cardType = type; _entries = _createDefaultEntries(); _expandedEntryIds.clear(); for (final entry in _entries) { if (entry.enabled) _expandedEntryIds.add(entry.id); } });
  }

  String _getEntryPreview(CharacterEntry entry) {
    if (entry.content.trim().isEmpty) return '未填写';

    final values = <String>[];
    void collect(dynamic value) {
      if (value is Map) {
        for (final v in value.values) {
          collect(v);
        }
      } else if (value is List) {
        for (final v in value) {
          collect(v);
        }
      } else {
        final s = value?.toString().trim() ?? '';
        if (s.isNotEmpty) values.add(s);
      }
    }

    if (entry.content.trimLeft().startsWith('{')) {
      try {
        collect(jsonDecode(entry.content));
        if (values.isEmpty) return '未填写';
        final preview = values.join(', ');
        return preview.length > 40 ? '${preview.substring(0, 40)}...' : preview;
      } catch (_) {
        return '格式错误';
      }
    }

    return entry.content.length > 40
        ? '${entry.content.substring(0, 40)}...'
        : entry.content;
  }

  Map<String, dynamic> _entryContentToMap(CharacterEntry entry) {
    final raw = entry.content.trim();
    if (raw.isEmpty) return {'内容': ''};

    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    // 非 JSON 的纯文本条目，统一包装成一个“内容”字段来编辑
    return {'内容': entry.content};
  }

  void _writeEntryContentFromMap(
      CharacterEntry entry,
      Map<String, dynamic> data,
      ) {
    if (data.keys.length == 1 && data.containsKey('内容')) {
      entry.content = data['内容']?.toString() ?? '';
    } else {
      entry.content = jsonEncode(data);
    }
  }

  void _setNestedValue(
      Map<String, dynamic> root,
      List<String> path,
      String value,
      ) {
    Map<String, dynamic> current = root;
    for (int i = 0; i < path.length - 1; i++) {
      final key = path[i];
      final next = current[key];
      if (next is Map<String, dynamic>) {
        current = next;
      } else if (next is Map) {
        current[key] = Map<String, dynamic>.from(next);
        current = current[key] as Map<String, dynamic>;
      } else {
        current[key] = <String, dynamic>{};
        current = current[key] as Map<String, dynamic>;
      }
    }
    current[path.last] = value;
  }

  String _treeFieldLabel(String entryId, List<String> path) {
    final key = path.last;

    // protagonist.detail 下的字段属于“主角详细设定”，不能再按 protagonist 顶层字段显示
    if (entryId == 'protagonist' && path.length >= 2 && path.first == 'detail') {
      const detailMap = {
        'race': '种族',
        'gender': '性别',
        'age': '年龄',
        'body': '身体数据',
        'background': '背景',
      };
      return detailMap[key] ?? key;
    }

    return _fieldLabel(entryId, key);
  }

  int _suggestMaxLines(String entryId, List<String> path) {
    final key = path.last;
    const longKeys = {
      '内容',
      'other',
      'background',
      'origin',
      'experiences',
      'current',
      'personality',
      'thoughts',
      'interests',
      'world_setting',
      'worldview',
      'system_mechanism',
      'events',
      'possible_endings',
      'body',
    };
    return longKeys.contains(key) ? 4 : 2;
  }

  String _treeNodeId(CharacterEntry entry, List<String> path) {
    return '${entry.id}:${path.join('.')}';
  }

  void _toggleTreeNode(CharacterEntry entry, List<String> path) {
    final id = _treeNodeId(entry, path);
    setState(() {
      if (_collapsedTreeNodeIds.contains(id)) {
        _collapsedTreeNodeIds.remove(id);
      } else {
        _collapsedTreeNodeIds.add(id);
      }
    });
  }

  Widget _buildCardImagePreview() {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: GestureDetector(
        onTap: () => _pickImage(false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(14),
              image: _cardImagePath.isNotEmpty
                  ? DecorationImage(
                image: FileImage(File(_cardImagePath)),
                fit: BoxFit.cover,
              )
                  : null,
            ),
            child: _cardImagePath.isEmpty
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo, size: 34, color: Colors.grey.shade600),
                const SizedBox(height: 6),
                Text(
                  '卡片封面\n2:3',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.25,
                  ),
                ),
              ],
            )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildWorldBookBindPanel() {
    final bound = _worldBookId != null && _worldBookId!.isNotEmpty;
    final primaryColor = Theme.of(context).primaryColor;

    return GestureDetector(
      onTap: _pickWorldBook,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.book,
                  size: 20,
                  color: bound ? primaryColor : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '绑定世界书',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: bound ? Colors.black87 : Colors.grey.shade700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              bound ? _worldBookName : '未绑定世界书',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: bound ? Colors.black87 : Colors.grey,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bound
                    ? primaryColor.withValues(alpha: 0.10)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: bound
                      ? primaryColor.withValues(alpha: 0.25)
                      : Colors.grey.shade300,
                ),
              ),
              child: Text(
                bound ? '点击更换' : '点击绑定',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: bound ? primaryColor : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryInlineDrawerEditor(CharacterEntry entry) {
    final data = _entryContentToMap(entry);
    final primaryColor = Theme.of(context).primaryColor;

    return GestureDetector(
      // 防止点击输入框时触发外层卡片手势
      behavior: HitTestBehavior.translucent,
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 16, color: primaryColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '编辑',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._buildDrawerNodes(
              entry: entry,
              root: data,
              current: data,
              path: const [],
              depth: 0,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDrawerNodes({
    required CharacterEntry entry,
    required Map<String, dynamic> root,
    required Map<String, dynamic> current,
    required List<String> path,
    required int depth,
  }) {
    final widgets = <Widget>[];

    for (final key in current.keys) {
      final value = current[key];
      final childPath = [...path, key];

      if (value is Map) {
        final childMap = value is Map<String, dynamic>
            ? value
            : Map<String, dynamic>.from(value);
        current[key] = childMap;

        final nodeId = _treeNodeId(entry, childPath);
        final expanded = !_collapsedTreeNodeIds.contains(nodeId);

        widgets.add(
          _buildDrawerGroupHeader(
            entry: entry,
            path: childPath,
            depth: depth,
            expanded: expanded,
          ),
        );

        if (expanded) {
          widgets.addAll(
            _buildDrawerNodes(
              entry: entry,
              root: root,
              current: childMap,
              path: childPath,
              depth: depth + 1,
            ),
          );
        }
      } else {
        widgets.add(
          _buildDrawerFieldEditor(
            entry: entry,
            root: root,
            path: childPath,
            value: value?.toString() ?? '',
            depth: depth,
          ),
        );
      }
    }

    if (widgets.isEmpty) {
      widgets.add(
        const Text('未填写', style: TextStyle(fontSize: 13, color: Colors.grey)),
      );
    }

    return widgets;
  }

  Widget _buildDrawerGroupHeader({
    required CharacterEntry entry,
    required List<String> path,
    required int depth,
    required bool expanded,
  }) {
    final primaryColor = Theme.of(context).primaryColor;
    final isChild = depth > 0;

    return Padding(
      padding: EdgeInsets.only(left: isChild ? 10.0 : 0, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => _toggleTreeNode(entry, path),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isChild
                ? Colors.grey.shade100
                : primaryColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isChild
                  ? Colors.grey.shade300
                  : primaryColor.withValues(alpha: 0.22),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 80;

              return Row(
                children: [
                  if (!compact) ...[
                    Icon(
                      expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
                      size: 16,
                      color: isChild ? Colors.grey.shade700 : primaryColor,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      _treeFieldLabel(entry.id, path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isChild ? Colors.black87 : primaryColor,
                      ),
                    ),
                  ),
                  if (!compact)
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: Colors.grey.shade700,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerFieldEditor({
    required CharacterEntry entry,
    required Map<String, dynamic> root,
    required List<String> path,
    required String value,
    required int depth,
  }) {
    final primaryColor = Theme.of(context).primaryColor;
    final isChild = depth > 0;

    return Container(
      margin: EdgeInsets.only(left: isChild ? 10.0 : 0, bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: isChild ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isChild
              ? primaryColor.withValues(alpha: 0.12)
              : Colors.grey.shade200,
        ),
        boxShadow: isChild
            ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isChild
                      ? primaryColor.withValues(alpha: 0.58)
                      : Colors.grey.shade500,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _treeFieldLabel(entry.id, path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('${entry.id}:${path.join('.')}'),
            initialValue: value,
            minLines: 1,
            maxLines: _suggestMaxLines(entry.id, path),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '请输入${_treeFieldLabel(entry.id, path)}',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1.4),
              ),
            ),
            onChanged: (text) {
              _setNestedValue(root, path, text.trim());
              _writeEntryContentFromMap(entry, root);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_rectAnimation == null) {
      // 动画未就绪时不渲染，但确保已初始化
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        GestureDetector(onTap: () => Navigator.pop(context), child: Container(color: Colors.black54)),
        AnimatedBuilder(
          animation: _rectAnimation!,
          builder: (context, child) {
            final rect = _rectAnimation!.value!;
            return Positioned(
              left: rect.left, top: rect.top, width: rect.width, height: rect.height,
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  borderRadius: BorderRadius.circular(20), elevation: 16,
                  child: Container(
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '编辑角色卡',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _save,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(50, 30),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                child: const Text('保存', style: TextStyle(fontSize: 14)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  GestureDetector(onTap: () => _pickImage(true), child: CircleAvatar(radius: 40, backgroundColor: Colors.grey.shade300, backgroundImage: _avatarPath.isNotEmpty ? FileImage(File(_avatarPath)) : null, child: _avatarPath.isEmpty ? Icon(Icons.person, size: 40, color: Colors.grey.shade600) : null)),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: '角色卡名称', isDense: true, errorText: _showNameError ? _nameErrorText : null)),
                                    const SizedBox(height: 8),
                                    TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: '简短描述', isDense: true)),
                                    const SizedBox(height: 8),
                                    Row(children: [Expanded(child: _buildTypeButton('人物卡', 'character')), const SizedBox(width: 8), Expanded(child: _buildTypeButton('系统卡', 'system'))]),
                                  ])),
                                ]),
                                const SizedBox(height: 12),

                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final maxW = constraints.maxWidth;

                                    // 宽度太窄时，不做左右布局，改成上下布局
                                    if (maxW < 300) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Center(
                                            child: SizedBox(
                                              width: 120,
                                              child: _buildCardImagePreview(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            height: 120,
                                            child: _buildWorldBookBindPanel(),
                                          ),
                                        ],
                                      );
                                    }

                                    // 正常宽度下使用左右布局
                                    final previewHeight = maxW < 380 ? 160.0 : 180.0;

                                    return SizedBox(
                                      height: previewHeight,
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _buildCardImagePreview(),
                                          const SizedBox(width: 12),
                                          Expanded(child: _buildWorldBookBindPanel()),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 12),
                                const Divider(),
                                _buildSectionHeader('简单介绍'),
                                ..._entries.where((e) { if (_cardType == 'system') return ['system_name', 'system_summary'].contains(e.id); return ['name_entry', 'relationship'].contains(e.id); }).map((e) => _buildEntryCard(e)),
                                _buildSectionHeader('详细设定'),
                                ..._entries.where((e) { if (_cardType == 'system') return ['system_details', 'protagonist', 'plot'].contains(e.id); return ['body', 'psychology', 'background'].contains(e.id); }).map((e) => _buildEntryCard(e)),
                                if (_entries.any((e) => e.isCustom)) ...[_buildSectionHeader('自定义条目'), ..._entries.where((e) => e.isCustom).map((e) => _buildEntryCard(e))],
                                TextButton.icon(onPressed: _addCustomEntry, icon: const Icon(Icons.add, size: 18), label: const Text('添加自定义条目')),
                                const SizedBox(height: 16), const Divider(),
                                _buildSectionHeader('开场白'),
                                ..._greetings.map((g) => _buildGreetingTile(g)),
                                TextButton.icon(onPressed: _addGreeting, icon: const Icon(Icons.add, size: 18), label: const Text('添加开场白')),
                                const SizedBox(height: 80),
                              ],
                            ),
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
    );
  }

  Widget _buildTypeButton(String label, String type) {
    final selected = _cardType == type;
    return GestureDetector(onTap: () => _switchCardType(type), child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: selected ? Theme.of(context).primaryColor : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: Center(child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)))));
  }

  Widget _buildSectionHeader(String title) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));

  Widget _buildEntryCard(CharacterEntry entry) {
    final isExpanded = _expandedEntryIds.contains(entry.id);
    final enabled = entry.enabled;
    return Card(
      color: enabled ? null : Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 启用开关
                  GestureDetector(
                    onTap: () => _toggleEntryEnabled(entry),
                    child: Container(
                      width: 20, height: 20,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enabled ? Colors.green : Colors.red.shade300,
                      ),
                      child: Icon(enabled ? Icons.check : Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                  // 标题
                  Expanded(
                    child: Text(
                      entry.title,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: enabled ? null : Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 自定义条目仍保留独立编辑按钮；固定条目展开后直接在卡片内编辑
                  if (entry.isCustom)
                    GestureDetector(
                      onTap: enabled ? () => _editEntry(entry) : null,
                      child: Icon(
                        Icons.edit,
                        size: 16,
                        color: enabled ? Colors.grey : Colors.grey.shade400,
                      ),
                    ),
                  // 删除按钮（仅自定义条目显示）
                  if (entry.isCustom) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _deleteEntry(entry),
                      child: const Icon(Icons.delete, size: 16, color: Colors.red),
                    ),
                  ],
                  // 展开/收起箭头
                  if (enabled) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _toggleExpand(entry.id),
                      child: Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
              if (enabled && !isExpanded && _getEntryPreview(entry).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 26),
                  child: Text(_getEntryPreview(entry), style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              if (enabled && isExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 26),
                  child: _buildEntryInlineDrawerEditor(entry),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingTile(OpeningGreeting greeting) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _editGreeting(greeting),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  greeting.content.isEmpty ? '空开场白' : greeting.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: greeting.content.isEmpty ? Colors.grey : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 编辑按钮
              GestureDetector(
                onTap: () => _editGreeting(greeting),
                child: const Icon(Icons.edit, size: 16, color: Colors.grey),
              ),
              const SizedBox(width: 6),
              // 删除按钮
              GestureDetector(
                onTap: () => _deleteGreeting(greeting),
                child: const Icon(Icons.delete, size: 16, color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fieldLabel(String entryId, String fieldKey) {
  const map = {
    'name_entry': {'last_name': '姓', 'first_name': '名', 'other': '其他'},
    'body': {'race': '种族', 'gender': '性别', 'age': '年龄', 'height': '身高', 'weight': '体重', 'measurements': '三围', 'other': '其他数据'},
    'psychology': {'personality': '性格', 'thoughts': '思想', 'interests': '兴趣/爱好/癖好'},
    'background': {'origin': '出身背景', 'experiences': '经历事件', 'current': '当前背景'},
    'system_details': {'world_setting': '世界设定', 'worldview': '世界观设定', 'system_mechanism': '系统机制设定'},
    'protagonist': {'name': '主角名称', 'detail': '主角详细设定'},
    'plot': {'cause': '起因', 'events': '中途特定触发事件', 'goal': '目标', 'possible_endings': '可能结局设定'},
  };
  return map[entryId]?[fieldKey] ?? fieldKey;
}

class _FixedEntryEditDialog extends StatefulWidget {
  final CharacterEntry entry;
  final Map<String, dynamic> fields;
  const _FixedEntryEditDialog({required this.entry, required this.fields});
  @override State<_FixedEntryEditDialog> createState() => _FixedEntryEditDialogState();
}

class _FixedEntryEditDialogState extends State<_FixedEntryEditDialog> {
  late Map<String, dynamic> _fields;
  late List<TextEditingController> _controllers;

  @override void initState() { super.initState(); _fields = Map.from(widget.fields); _controllers = _fields.keys.map((key) => TextEditingController(text: _fields[key]?.toString() ?? '')).toList(); }
  @override void dispose() { for (var c in _controllers) { c.dispose(); } super.dispose(); }

  void _save() {
    for (int i = 0; i < _fields.keys.length; i++) {
      final key = _fields.keys.elementAt(i);
      final value = _controllers[i].text.trim();
      if (_fields[key] is Map) { try { _fields[key] = jsonDecode(value); } catch (_) { _fields[key] = value; } }
      else { _fields[key] = value; }

    }
    Navigator.pop(context, _fields);
  }

  @override Widget build(BuildContext context) {
    final keys = _fields.keys.toList();
    return AlertDialog(
      title: Text('编辑${widget.entry.title}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: List.generate(keys.length, (index) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: _controllers[index], decoration: InputDecoration(labelText: widget.entry.id == 'protagonist' && keys[index] == 'detail' ? '详细设定' : _fieldLabel(widget.entry.id, keys[index]))))))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), TextButton(onPressed: _save, child: const Text('保存'))],
    );
  }
}

class _CustomEntryEditPage extends StatefulWidget {
  final CharacterEntry entry;
  const _CustomEntryEditPage({required this.entry});
  @override State<_CustomEntryEditPage> createState() => _CustomEntryEditPageState();
}

class _CustomEntryEditPageState extends State<_CustomEntryEditPage> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;

  @override void initState() { super.initState(); _titleCtrl = TextEditingController(text: widget.entry.title); _contentCtrl = TextEditingController(text: widget.entry.content); }
  @override void dispose() { _titleCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  void _save() { Navigator.pop(context, widget.entry.copyWith(title: _titleCtrl.text.trim().isEmpty ? widget.entry.title : _titleCtrl.text.trim(), content: _contentCtrl.text.trim())); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('编辑自定义条目'), actions: [TextButton(onPressed: _save, child: const Text('保存'))]),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '条目名称')),
        const SizedBox(height: 12),
        Expanded(child: TextField(controller: _contentCtrl, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(labelText: '内容', border: OutlineInputBorder(), alignLabelWithHint: true))),
      ])),
    );
  }
}