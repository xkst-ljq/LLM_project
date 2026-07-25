import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../models/character_entry.dart';
import '../models/character_meta.dart';
import '../models/status_bar_field.dart';
import '../models/ui_assembly_info.dart';
import '../services/database_service.dart';
import '../services/image_pick_service.dart';
import '../utils/id_utils.dart';
import 'character_assembly_list_page.dart';
import 'status_bar_fields_edit_page.dart';

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
  // 角色扩展元信息（标签 / 作者 / 作者备注 / 版本）
  late TextEditingController _tagsCtrl;
  late TextEditingController _creatorCtrl;
  late TextEditingController _creatorNotesCtrl;
  late TextEditingController _versionCtrl;
  late TextEditingController _postHistoryCtrl;
  late CharacterMeta _meta;
  String _avatarPath = '';
  String _cardImagePath = '';
  String _cardType = 'character';
  late List<CharacterEntry> _entries;
  final Set<String> _expandedEntryIds = {};
  // 子级抽屉折叠状态：默认展开；加入集合表示该子级被折叠
  final Set<String> _collapsedTreeNodeIds = {};
  late List<OpeningGreeting> _greetings;
  String? _worldBookId;
  String _worldBookName = '';
  bool _showNameError = false;
  String _nameErrorText = '';
  bool _isClosing = false;

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
    _meta = widget.character.meta;
    _tagsCtrl = TextEditingController(text: _meta.tags.join('，'));
    _creatorCtrl = TextEditingController(text: _meta.creator);
    _creatorNotesCtrl = TextEditingController(text: _meta.creatorNotes);
    _versionCtrl = TextEditingController(text: _meta.characterVersion);
    _postHistoryCtrl =
        TextEditingController(text: _meta.postHistoryInstructions);
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
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    _creatorCtrl.dispose();
    _creatorNotesCtrl.dispose();
    _versionCtrl.dispose();
    _postHistoryCtrl.dispose();
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

  Future<void> _closeWithAnimation() async {
    if (_isClosing || !mounted) return;

    _isClosing = true;
    FocusScope.of(context).unfocus();

    Navigator.pop(context);
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

    // 写回扩展元信息（标签 / 作者 / 作者备注 / 版本）。
    // 保留转换器带来的其他字段（source_format / post_history / mes_example）。
    _meta.tags = _tagsCtrl.text
        .split(RegExp(r'[，,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    _meta.creator = _creatorCtrl.text.trim();
    _meta.creatorNotes = _creatorNotesCtrl.text.trim();
    _meta.characterVersion = _versionCtrl.text.trim();
    _meta.postHistoryInstructions = _postHistoryCtrl.text.trim();
    widget.character.applyMeta(_meta);

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
      'meta_json': widget.character.metaJson,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      await _closeWithAnimation();
    }
  }

  Future<void> _pickImage(bool isAvatar) async {
    String? savedPath;

    if (isAvatar) {
      savedPath = await ImagePickService.pickAvatar(context);
    } else {
      savedPath = await ImagePickService.pickCharacterCard(context);
    }

    if (!mounted) return;

    final path = savedPath;

    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未选择图片或图片保存失败')),
      );
      return;
    }

    setState(() {
      if (isAvatar) {
        _avatarPath = path;
      } else {
        _cardImagePath = path;
      }
    });
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
    final newEntry = CharacterEntry(
        id: IdUtils.timestampId(), title: '新条目', content: '', enabled: false, isCustom: true, sortOrder: _entries.where((e) => e.isCustom).length);
    setState(() => _entries.add(newEntry));
  }

  void _deleteEntry(CharacterEntry entry) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('确认删除'), content: Text('确定要删除条目"${entry.title}"吗？'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _entries.removeWhere((e) => e.id == entry.id)); }, child: const Text('删除', style: TextStyle(color: Colors.red))),
    ]));
  }

  void _addGreeting() => setState(() => _greetings.add(
    OpeningGreeting(
      id: IdUtils.timestampId(),
      content: '',
    ),
  ));

  void _editGreeting(OpeningGreeting greeting) async {
    final controller = TextEditingController(text: greeting.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑开场白'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '输入开场白内容...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _insertImageIntoController(controller),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('插入图片'),
              ),
            ),
            Text(
              '图片会保存到本地、随角色卡导出，聊天时显示在开场白中。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
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

  /// 选择本地图片并把 <img> 标签插入到文本光标处（纯本地，符合本地优先理念）。
  Future<void> _insertImageIntoController(
      TextEditingController controller) async {
    final path = await ImagePickService.pickInsertImage(context);
    if (path == null || path.isEmpty) return;
    // 用 <img> 标签承载本地路径，聊天页 HTML 渲染会以 Image.file 显示。
    final tag = '<img src="$path">';
    final sel = controller.selection;
    final text = controller.text;
    if (sel.isValid && sel.start >= 0) {
      final newText =
          text.replaceRange(sel.start, sel.end, tag);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + tag.length),
      );
    } else {
      // 无有效光标：追加到末尾。
      controller.text = text.isEmpty ? tag : '$text\n$tag';
    }
  }

  void _deleteGreeting(OpeningGreeting greeting) => setState(() => _greetings.removeWhere((g) => g.id == greeting.id));

  void _pickWorldBook() async {
    final books = await DatabaseService.getAllWorldBooks();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('选择世界书', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  ...books.map((b) => ListTile(
                    title: Text(b['name'] as String? ?? '未命名'),
                    selected: b['id'] == _worldBookId,
                    onTap: () { setState(() { _worldBookId = b['id'] as String; _worldBookName = b['name'] as String? ?? ''; }); Navigator.pop(ctx); },
                  )),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.clear, color: Colors.red),
                    title: const Text('解除绑定', style: TextStyle(color: Colors.red)),
                    onTap: () { setState(() { _worldBookId = null; _worldBookName = ''; }); Navigator.pop(ctx); },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeWithAnimation();
      },
      child: AnimatedOpacity(
        opacity: _isClosing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Stack(
            children: [
              GestureDetector(
                onTap: _closeWithAnimation,
                child: const SizedBox.expand(),
              ),
              AnimatedBuilder(
                animation: _rectAnimation!,
                builder: (context, child) {
                  final rect = _rectAnimation!.value!;
                  if (rect.width <= 0 || rect.height <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: GestureDetector(
                      onTap: () {},
                      child: Material(
                        borderRadius: BorderRadius.circular(20), elevation: 16,
                        child: Container(
                          decoration: BoxDecoration(color: Theme
                              .of(context)
                              .scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20)),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '编辑角色卡',
                                        style: TextStyle(fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _isClosing ? null : _save,
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(50, 30),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                      ),
                                      child: const Text(
                                          '保存', style: TextStyle(fontSize: 14)),
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
                                      Row(crossAxisAlignment: CrossAxisAlignment
                                          .start, children: [
                                        GestureDetector(
                                            onTap: () => _pickImage(true),
                                            child: CircleAvatar(radius: 40,
                                                backgroundColor: Colors.grey
                                                    .shade300,
                                                backgroundImage: _avatarPath
                                                    .isNotEmpty ? FileImage(
                                                    File(_avatarPath)) : null,
                                                child: _avatarPath.isEmpty
                                                    ? Icon(Icons.person, size: 40,
                                                    color: Colors.grey.shade600)
                                                    : null)),
                                        const SizedBox(width: 16),
                                        Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment
                                                .start, children: [
                                          TextField(controller: _nameCtrl,
                                              decoration: InputDecoration(
                                                  labelText: '角色卡名称',
                                                  isDense: true,
                                                  errorText: _showNameError
                                                      ? _nameErrorText
                                                      : null)),
                                          const SizedBox(height: 8),
                                          TextField(controller: _descCtrl,
                                              decoration: const InputDecoration(
                                                  labelText: '简短描述',
                                                  isDense: true)),
                                          const SizedBox(height: 8),
                                          Row(children: [
                                            Expanded(child: _buildTypeButton(
                                                '人物卡', 'character')),
                                            const SizedBox(width: 8),
                                            Expanded(child: _buildTypeButton(
                                                '系统卡', 'system'))
                                          ]),
                                        ])),
                                      ]),
                                      const SizedBox(height: 12),

                                      // ===== 封面 + 世界书 =====
                                      SizedBox(
                                        height: 120,
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(width: 80, child: _buildCardImagePreview()),
                                            const SizedBox(width: 8),
                                            Expanded(child: _buildWorldBookBindPanel()),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // ===== 状态栏 + UI 拼装（双栏） =====
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: _buildStatusBarEntry()),
                                          const SizedBox(width: 8),
                                          Expanded(child: _buildUIAssemblyEntry()),
                                        ],
                                      ),

                                      const SizedBox(height: 12),
                                      const Divider(),
                                      _buildSectionHeader('简单介绍'),
                                      ..._entries.where((e) {
                                        if (_cardType == 'system') {
                                          return ['system_name', 'system_summary']
                                              .contains(e.id);
                                        }
                                        return ['name_entry', 'relationship']
                                            .contains(e.id);
                                      }).map((e) => _buildEntryCard(e)),
                                      _buildSectionHeader('详细设定'),
                                      ..._entries.where((e) {
                                        if (_cardType == 'system') {
                                          return [
                                            'system_details',
                                            'protagonist',
                                            'plot'
                                          ].contains(e.id);
                                        }
                                        return ['body', 'psychology', 'background']
                                            .contains(e.id);
                                      }).map((e) => _buildEntryCard(e)),
                                      if (_entries.any((e) => e.isCustom)) ...[
                                        _buildSectionHeader('自定义条目'),
                                        ..._entries.where((e) => e.isCustom).map((
                                            e) => _buildEntryCard(e))
                                      ],
                                      TextButton.icon(onPressed: _addCustomEntry,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('添加自定义条目')),
                                      const SizedBox(height: 16), const Divider(),
                                      _buildSectionHeader('开场白'),
                                      ..._greetings.map((g) =>
                                          _buildGreetingTile(g)),
                                      TextButton.icon(onPressed: _addGreeting,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('添加开场白')),
                                      const SizedBox(height: 16),
                                      const Divider(),
                                      _buildSectionHeader('角色信息'),
                                      ..._buildMetaFields(),
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
          ),
        ),
    );
  }

  Widget _buildTypeButton(String label, String type) {
    final selected = _cardType == type;
    return GestureDetector(onTap: () => _switchCardType(type), child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: selected ? Theme.of(context).primaryColor : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: Center(child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)))));
  }

  Widget _buildSectionHeader(String title) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));

  // 角色信息（标签 / 作者 / 版本 / 作者备注）编辑字段。
  // 这些信息默认不注入 Prompt，仅用于角色库展示、筛选与资料保留。
  List<Widget> _buildMetaFields() {
    final hint = (_meta.sourceFormat.trim().isNotEmpty)
        ? '来源：${_meta.sourceFormat.trim()}'
        : null;
    return [
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(hint,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ),
      TextField(
        controller: _tagsCtrl,
        decoration: const InputDecoration(
          labelText: '标签',
          hintText: '用逗号分隔，例如：傲娇，校园，原创',
          isDense: true,
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _creatorCtrl,
            decoration: const InputDecoration(
                labelText: '作者', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _versionCtrl,
            decoration: const InputDecoration(
                labelText: '版本', isDense: true),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _creatorNotesCtrl,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          labelText: '作者备注',
          hintText: '使用建议、注意事项等（不会发送给模型）',
          isDense: true,
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _postHistoryCtrl,
        maxLines: 5,
        minLines: 2,
        decoration: const InputDecoration(
          labelText: '历史后指令',
          hintText: '放在对话最末尾的强约束指令，如「只用中文、不要旁白、保持角色」。'
              '支持 {{char}} {{user}}。兼容酒馆 post_history_instructions。',
          isDense: true,
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    ];
  }

  // 状态栏字段定义入口：显示当前字段数，点击进入专门编辑页。
  Widget _buildStatusBarEntry() {
    final fields = _meta.statusBarFields;
    String summary;
    if (fields.isEmpty) {
      summary = '未设置';
    } else {
      final textCount = fields.where((f) => f.type == 'text').length;
      final numCount = fields.where((f) => f.type == 'number').length;
      final parts = <String>[];
      if (textCount > 0) parts.add('$textCount 文本');
      if (numCount > 0) parts.add('$numCount 数值');
      summary = parts.isEmpty ? '$fields.length 字段' : parts.join(' · ');
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.04))),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: _editStatusBarFields,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            const Icon(Icons.speed_outlined, size: 20, color: Color(0xFF651FFF)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('状态栏', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(summary, style: const TextStyle(fontSize: 10, color: Color(0xFF888896))),
            ])),
          ]),
        ),
      ),
    );
  }

  Future<void> _editStatusBarFields() async {
    final result = await Navigator.push<List<StatusBarField>>(
      context,
      MaterialPageRoute(
        builder: (_) => StatusBarFieldsEditPage(fields: _meta.statusBarFields),
      ),
    );
    if (result != null) {
      setState(() => _meta.statusBarFields = result);
    }
  }

  Widget _buildUIAssemblyEntry() {
    final assemblies = _meta.uiAssemblies.map((s) => UIAssemblyInfo.fromJsonString(s)).where((a) => a.id.isNotEmpty).toList();
    String summary;
    if (assemblies.isEmpty) {
      summary = '未设置';
    } else {
      final parts = <String>[];
      for (final mode in ['opening', 'scene', 'extra_sticky', 'extra_companion']) {
        final count = assemblies.where((a) => a.mode == mode).length;
        if (count > 0) {
          final label = mode == 'opening' ? '弹窗' : mode == 'scene' ? '场景' : mode == 'extra_sticky' ? '常驻' : '伴生';
          parts.add('$count $label');
        }
      }
      summary = parts.join(' · ');
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.04))),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: _editUIAssemblyList,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            const Icon(Icons.dashboard_customize_rounded, size: 20, color: Color(0xFF651FFF)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('UI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(summary, style: const TextStyle(fontSize: 10, color: Color(0xFF888896))),
            ])),
          ]),
        ),
      ),
    );
  }

  Future<void> _editUIAssemblyList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UIAssemblyListPage(
          meta: _meta.copy(),
          onMetaChanged: (m) => setState(() => _meta = m),
        ),
      ),
    );
  }

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