part of '../character_assembly_page.dart';

/// 元件操作：删除 · 复制 · 图层顺序 · 锁定
///
/// 从 `logic.dart` 按职责拆出。**纯搬运**：未改动任何一行逻辑与签名。
///
/// ## 为什么是独立 mixin
///
/// Dart 的 `part` 文件**不能续写另一个 part 里打开的类体**——
/// 每个 part 必须自成完整的顶层声明。因此本文件独立成一个 mixin，
/// 由 `_CharacterAssemblyPageState` 一并 `with` 进去；
/// 私有成员在同一个库内仍互相可见，调用关系不受影响。
///
/// `on` 子句的依赖由脚本按实际引用算出，并已验证整个依赖图无环。
/// 被多个分组共用的成员留在 `logic.dart`（依赖链根部），避免形成环。
mixin _AssemblyElementsLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _AssemblyCanvasLogic, _AssemblyPageLogic {
  /// 找出指向某元素的所有 linker（作为源或目标都算）。
  List<UIElement> _linkersReferencing(String elementId) {
    return _elements.where((element) {
      final module = element.module;
      if (module == null || module.type != 'linker') return false;
      final data =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data == null) return false;
      return data['sourceModuleId']?.toString() == elementId ||
          data['targetModuleId']?.toString() == elementId;
    }).toList();
  }

  /// 删除元素，并连带清理指向它的联动器。
  ///
  /// 留着悬空连线比删掉更糟：`isSchemeSelectable` 仍判为合法，
  /// 运行端却找不到源/目标，表现为「配了但没反应」，极难排查。
  Future<void> _confirmDeleteElement(UIElement element) async {
    final orphans = _linkersReferencing(element.id);
    final name = element.module?.name ?? element.composite?.name ?? '该组件';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「$name」？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删除后无法撤销。'),
            if (orphans.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '还有 ${orphans.length} 个联动器连着它，会一并删除。\n'
                  '（保留悬空连线会导致运行时静默失效，比删掉更难排查）',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE65100),
                    height: 1.4,
                  ),
                ),
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removeIds = {element.id, ...orphans.map((e) => e.id)};
    setState(() {
      _elements.removeWhere((e) => removeIds.contains(e.id));
      // A14-1c：删掉的若是容器面，组员会指向一个不存在的父级，
      // 导致运行时 `isElementVisibleInSurfaceHierarchy` 判定失败而整组隐身。
      // 解除它们的归属，就地留在当前层级（与「出组保留显示层级」一致）。
      for (var i = 0; i < _elements.length; i++) {
        final parent = _elements[i].parentSurfaceId;
        if (parent != null && removeIds.contains(parent)) {
          _elements[i] = _elements[i].copyWith(clearParentSurface: true);
        }
      }
      // 覆写槽位随复合组件一起消失，否则会留下指向不存在组件的孤儿配置。
      _activePropertyOverrides
          .removeWhere((o) => removeIds.contains(o.componentId));
      _selectedCompositeId = null;
    });
    _setupEventBusListener();
    _persistAssemblyElements();
  }

  /// 复制元素。新元素稍作偏移，避免与原件完全重叠而看不出来。
  void _duplicateElement(UIElement element) {
    // 联动器不复制：它的源/目标指向具体元素，复制出来必然是重复连线，
    // 作者要的几乎总是「再连一条新的」而不是「同一条来两遍」。
    if (element.module?.type == 'linker') {
      _showSnack('联动器请重新拖入并配置，复制会产生重复连线');
      return;
    }

    final copy = _cloneElementWithNewIds(element);
    setState(() {
      _elements.add(copy.copyWith(
        offset: element.offset + const Offset(12, 12),
      ));
      _selectedCompositeId = copy.id;
    });
    _persistAssemblyElements();
  }

  /// 深拷贝元素并重新分配 id。
  ///
  /// `UIElement.copyWith` 不接受 id（它是 final、不可改），
  /// 因此在 JSON 层面替换后再反序列化。
  ///
  /// 用 `jsonEncode/Decode` 而不是 `_deepCloneValue`：后者对嵌套 Map
  /// 返回 `Map<dynamic, dynamic>`，而 `UIElement.fromJson` 里
  /// `json['offset'] as Map<String, dynamic>?` 是硬类型转换，会直接抛
  /// `_TypeError`（复制时崩溃）。JSON 往返能保证嵌套层的键类型。
  UIElement _cloneElementWithNewIds(UIElement source) {
    final json = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(source.toJson())) as Map,
    );
    json['id'] = _generateElementId();
    return UIElement.fromJson(json);
  }

  /// 调整元素在绘制顺序中的位置。
  ///
  /// `_elements` 的顺序即 Stack 的绘制顺序：**越靠后越上层**。
  /// 因此界面上的「上移一层」= 在列表里往后挪一位（delta = +1）。
  ///
  /// A14-1c 之后分三种情况：
  ///   - 组内成员 → 只在同组兄弟之间移动（规则 1）
  ///   - 父级面   → 整组一起移动（规则 2）
  ///   - 顶层元素 → 在顶层元素之间移动，跨组时整组跳过
  void _moveElementLayer(UIElement element, int delta) {
    final parentId = element.parentSurfaceId;
    if (parentId != null && parentId.isNotEmpty) {
      _moveMemberWithinGroup(element, parentId, delta);
      return;
    }
    if (_isSurfaceElement(element) && _surfaceGroupIds(element.id).length > 1) {
      _moveSurfaceGroupOrder(element.id, delta);
      return;
    }
    _moveTopLevelElement(element, delta);
  }

  /// 该元素在其所属层级里还能否朝指定方向移动。
  ///
  /// 与 `_moveElementLayer` 用同一套分支，避免按钮可点却没反应。
  bool _canMoveElementLayer(UIElement element, int delta) {
    final parentId = element.parentSurfaceId;
    if (parentId != null && parentId.isNotEmpty) {
      final siblings =
          _elements.where((e) => e.parentSurfaceId == parentId).toList();
      final i = siblings.indexWhere((e) => e.id == element.id);
      final t = i + delta;
      return i != -1 && t >= 0 && t < siblings.length;
    }

    if (_isSurfaceElement(element) && _surfaceGroupIds(element.id).length > 1) {
      final groupIds = _surfaceGroupIds(element.id);
      final others = _elements.where((e) => !groupIds.contains(e.id)).length;
      final firstIndex = _elements.indexWhere((e) => groupIds.contains(e.id));
      if (firstIndex == -1) return false;
      final blockStart = _elements
          .take(firstIndex)
          .where((e) => !groupIds.contains(e.id))
          .length;
      final target = blockStart + delta;
      return target >= 0 && target <= others;
    }

    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return false;
    return index + delta >= 0 && index + delta < _elements.length;
  }

  /// 规则 1：组内成员只与同组兄弟换位，不会窜出组外。
  void _moveMemberWithinGroup(UIElement element, String parentId, int delta) {
    final siblings = _elements
        .where((e) => e.parentSurfaceId == parentId)
        .toList();
    final memberIndex = siblings.indexWhere((e) => e.id == element.id);
    final targetMember = memberIndex + delta;
    if (memberIndex == -1 ||
        targetMember < 0 ||
        targetMember >= siblings.length) {
      return;
    }

    final fromIndex = _elements.indexWhere((e) => e.id == element.id);
    final toIndex =
        _elements.indexWhere((e) => e.id == siblings[targetMember].id);
    if (fromIndex == -1 || toIndex == -1) return;

    setState(() {
      final moved = _elements.removeAt(fromIndex);
      _elements.insert(toIndex, moved);
      // 换位后重整一次，保证父面仍在块首（规则 3）。
      _normalizeSurfaceGroupOrder(parentId);
    });
    _persistAssemblyElements();
  }

  /// 规则 2：父级面变换层级 = 整组一起变换。
  void _moveSurfaceGroupOrder(String surfaceId, int delta) {
    _normalizeSurfaceGroupOrder(surfaceId);
    final groupIds = _surfaceGroupIds(surfaceId);
    final grouped = _elements.where((e) => groupIds.contains(e.id)).toList();
    if (grouped.isEmpty) return;

    final others = _elements.where((e) => !groupIds.contains(e.id)).toList();
    final firstIndex = _elements.indexWhere((e) => groupIds.contains(e.id));
    final blockStart =
        _elements.take(firstIndex).where((e) => !groupIds.contains(e.id)).length;
    // 整块在 others 中的落点前后各挪一格。
    final target = blockStart + delta;
    if (target < 0 || target > others.length) return;

    setState(() {
      _elements
        ..clear()
        ..addAll(others.take(target))
        ..addAll(grouped)
        ..addAll(others.skip(target));
    });
    _persistAssemblyElements();
  }

  /// 顶层元素之间移动。跨越某个组时整组一起跳过，
  /// 避免顶层元素卡在别人的组中间把组切断。
  void _moveTopLevelElement(UIElement element, int delta) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;

    var target = index + delta;
    while (target >= 0 && target < _elements.length) {
      final crossed = _elements[target];
      final crossedRoot = _rootSurfaceOf(crossed) ??
          (_isSurfaceElement(crossed) ? crossed.id : null);
      if (crossedRoot == null) break;
      // 落点在某个组内部：继续往同方向跨，直到越过整组。
      final groupIds = _surfaceGroupIds(crossedRoot);
      if (groupIds.length <= 1) break;
      target += delta;
    }
    if (target < 0 || target >= _elements.length) return;

    setState(() {
      final moved = _elements.removeAt(index);
      _elements.insert(target, moved);
    });
    _persistAssemblyElements();
  }

  /// 切换半锁定（`layoutLocked`）：锁住位置 / 形变 / 旋转。
  ///
  /// 用模型上已有的 `layoutLocked` 字段而不是自造 `properties['locked']`——
  /// Studio 侧本来就用它，两边共用同一份数据，方案在两个编辑器间迁移时
  /// 锁定状态才不会丢。
  void _toggleElementLayoutLock(UIElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    setState(() {
      _elements[index] =
          element.copyWith(layoutLocked: !element.layoutLocked);
    });
    _persistAssemblyElements();
  }

  /// 切换全锁定（`sealed`）：在半锁定基础上额外锁死联动。
  ///
  /// 全锁定后：已有连线不能切换或断开，没有连线则连不上，
  /// 配置联动器时该元素会被跳过（与 Studio 的 `sealed` 语义一致）。
  void _toggleElementSealed(UIElement element) {
    final index = _elements.indexWhere((e) => e.id == element.id);
    if (index == -1) return;
    final next = !element.sealed;
    setState(() {
      _elements[index] = element.copyWith(
        sealed: next,
        // 全锁定必然包含半锁定的约束，一起打开更符合直觉；
        // 解除全锁定时保留半锁定，让作者自己决定要不要一并解开。
        layoutLocked: next ? true : element.layoutLocked,
      );
    });
    _persistAssemblyElements();
  }

  /// 元素是否被任一档锁定禁止结构性改动（删除 / 复制 / 层级）。
  bool _isStructureLocked(UIElement element) =>
      element.layoutLocked || element.sealed;
}
