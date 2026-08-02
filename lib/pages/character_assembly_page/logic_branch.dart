part of '../character_assembly_page.dart';

/// 开场分支：在同一份 UI 里为不同开场白设计不同界面。
///
/// ## 需求来源（用户设计）
///
/// > 不同的开场白就应该有不一样的 UI 初始数据才对。
/// > 默认其他 UI 都是主支路方案，如果在 openingUI 创建了分支方案，
/// > 其他 UI 就可以切换方案来设计其他方案会出现的样式，
/// > 有点类似平级层设计。切换时可以选择清空画布或者继承主支路，
/// > 来实现不同的选择有完全不同的 UI 或者是相同的 UI 不同的初始数据。
///
/// ## 三条约束
///
/// 1. **分支平级，没有父子**。「总确认 / 分支确认」只是相对说法——
///    只有一个分支时习惯叫总确认，本质是同一种 keyAction 标记。
/// 2. **分支不依赖 opening UI**。判据是角色卡的开场白条数：
///    ≤1 只有主支路，>1 则每条开场白即一个平级分支。
///    这样没做 opening 页的卡照样能给不同开局配不同界面。
/// 3. **未设计的分支照搬主支路**。作者只改了分支 2，
///    其余仍跟随主支路——主支路改版式，它们自动跟上。
///
/// ## 数据落点
///
/// 主支路存在 `UIAssemblyInfo.pagesJson`；
/// 分支变体存在 `branchVariants`（分支下标 -> pagesJson）。
/// 没有变体的分支不占存储，见 `pagesJsonForBranch`。

mixin _AssemblyBranchLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _AssemblyPageLogic {

  /// 分支总数。开场白 ≤1 时只有主支路。
  int get _branchCount {
    final n = widget.branchNames.length;
    return n < 1 ? 1 : n;
  }

  bool get _hasBranches => _branchCount > 1;

  String _branchLabel(int index) {
    if (index < widget.branchNames.length) {
      return widget.branchNames[index];
    }
    return index == 0 ? '主线' : '分支 $index';
  }

  /// 该分支是否已有专属设计（而非照搬主支路）。
  bool _branchHasVariant(int index) =>
      index != 0 && _info.branchVariants.containsKey('$index');

  /// 切换到另一个分支。
  ///
  /// ## 为什么先存后读
  ///
  /// 画布上的元件在 `_elements`，只有调 `_syncCanvasStateIntoActivePage`
  /// 才会回写进 `_pages`。切分支前不存，当前分支的改动就没了——
  /// 这类「切走再回来发现白改了」的丢数据最伤。
  Future<void> _switchBranch(int target) async {
    if (target == _editingBranch) return;
    if (target < 0 || target >= _branchCount) return;

    // ① 存当前分支
    _persistCurrentBranch();

    // ② 目标分支若还没有专属设计，问作者要怎么起步
    if (target != 0 && !_branchHasVariant(target)) {
      final choice = await _askBranchInitMode(target);
      if (choice == null) return; // 取消，留在原分支
      if (choice == _BranchInitMode.blank) {
        // 空白画布：只保留一个空的基础页，不能连页面都没有。
        _info.branchVariants['$target'] = jsonEncode([
          AssemblyPage(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}',
            name: '主页',
            type: 'base',
          ).toJson(),
        ]);
      } else {
        // 继承主支路：深拷贝一份，之后各改各的互不影响。
        //
        // **必须换 id**：页面与元件 id 若与主支路重复，
        // 引擎按 id 索引时会张冠李戴（HANDOFF 3.5h 那类问题）。
        _info.branchVariants['$target'] = _cloneWithNewIds(_info.pagesJson);
      }
    }

    // ③ 载入目标分支
    setState(() {
      _editingBranch = target;
      _restorePagesFromJson(_info.pagesJsonForBranch(target));
    });
  }

  /// 把画布现状写回当前分支。
  void _persistCurrentBranch() {
    _syncCanvasStateIntoActivePage();
    final json = jsonEncode(
      _orderedPages().map((page) => page.toJson()).toList(),
    );
    if (_editingBranch == 0) {
      _info.pagesJson = json;
    } else {
      _info.branchVariants['$_editingBranch'] = json;
    }
  }

  /// 用给定的 pagesJson 重建画布。
  void _restorePagesFromJson(String raw) {
    _pages.clear();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _pages.addAll(
          decoded.whereType<Map>().map(
                (item) => AssemblyPage.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              ),
        );
      }
    } catch (_) {
      // 解析失败不能留空 —— 至少给一个可用的空白页，
      // 否则画布会进入没有 activePage 的非法状态。
    }
    if (_pages.isEmpty) {
      _pages.add(AssemblyPage(
        id: 'page_${DateTime.now().millisecondsSinceEpoch}',
        name: '主页',
        type: 'base',
      ));
    }
    _activePageId = _pages.first.id;
    _loadActivePageState();
  }

  /// 深拷贝 pagesJson 并重新分配所有 id。
  String _cloneWithNewIds(String raw) {
    late final List<dynamic> pages;
    try {
      final decoded = jsonDecode(raw);
      pages = decoded is List ? decoded : const [];
    } catch (_) {
      return '[]';
    }
    var seed = DateTime.now().millisecondsSinceEpoch;
    final idMap = <String, String>{};

    String remap(String old) =>
        idMap.putIfAbsent(old, () => '${old.split('_').first}_${seed++}');

    dynamic walk(dynamic node) {
      if (node is List) return node.map(walk).toList();
      if (node is! Map) return node;
      final out = Map<String, dynamic>.from(node);
      for (final key in const ['id', 'parentPageId', 'parentSurfaceId']) {
        final v = out[key];
        if (v is String && v.isNotEmpty) out[key] = remap(v);
      }
      out.forEach((k, v) {
        if (v is List || v is Map) out[k] = walk(v);
      });
      return out;
    }

    final cloned = walk(pages);
    // 第二遍：把 linker / 覆写里指向旧 id 的引用也换掉。
    // 这些引用散在 properties 深处，靠字符串替换最省事且不会漏。
    var text = jsonEncode(cloned);
    idMap.forEach((oldId, newId) {
      text = text.replaceAll('"$oldId"', '"$newId"');
    });
    return text;
  }

  Future<_BranchInitMode?> _askBranchInitMode(int target) async {
    return showDialog<_BranchInitMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设计「${_branchLabel(target)}」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '这个分支还没有专属界面，目前跟随主线显示。\n'
              '要怎么开始设计？',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            _initModeTile(
              ctx,
              mode: _BranchInitMode.inherit,
              icon: Icons.copy_all_rounded,
              title: '继承主线',
              detail: '复制主线的全部元件，在此基础上改。\n'
                  '适合「界面相同、只是初始数据不同」。',
            ),
            const SizedBox(height: 8),
            _initModeTile(
              ctx,
              mode: _BranchInitMode.blank,
              icon: Icons.crop_square_outlined,
              title: '空白画布',
              detail: '从零开始摆。适合这个开局需要完全不同的界面。',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _initModeTile(
    BuildContext ctx, {
    required _BranchInitMode mode,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF5C6BC0)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF666672),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏的分支指示 + 切换入口。
  ///
  /// 用户特意提过要「找一个比较空的位置来显示当前编辑的方案」——
  /// 多分支时改错地方是很难自查的错误（改了半天发现改的是别的分支），
  /// 所以做成**常驻显示**而不是藏在菜单里。
  Widget buildBranchIndicator() {
    if (!_hasBranches) return const SizedBox.shrink();
    final isMain = _editingBranch == 0;
    final color = isMain ? const Color(0xFF5C6BC0) : const Color(0xFFE65100);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: _showBranchPicker,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  _branchLabel(_editingBranch),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 13, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBranchPicker() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择要编辑的开场分支',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '各分支平级。没有专属设计的分支会照搬主线，'
                  '主线改版式它们自动跟随。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF777783),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _branchCount,
                itemBuilder: (ctx, i) {
                  final selected = i == _editingBranch;
                  final custom = _branchHasVariant(i);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      i == 0
                          ? Icons.star_rounded
                          : (custom
                              ? Icons.edit_rounded
                              : Icons.subdirectory_arrow_right_rounded),
                      size: 18,
                      color: selected
                          ? const Color(0xFF5C6BC0)
                          : Colors.black38,
                    ),
                    title: Text(
                      _branchLabel(i),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      i == 0
                          ? '主线（其余分支的兜底）'
                          : (custom ? '已有专属设计' : '跟随主线'),
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: Color(0xFF5C6BC0))
                        : null,
                    onTap: () => Navigator.pop(ctx, i),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _switchBranch(picked);
  }
}

/// 新分支的起步方式。
enum _BranchInitMode {
  /// 复制主线的全部元件。
  inherit,

  /// 从空白画布开始。
  blank,
}
