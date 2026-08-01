part of '../character_assembly_page.dart';

/// 复合组件（composite）在 Assembly 编辑器里的全部逻辑。
///
/// ## 为什么单独成文件
///
/// 这些成员原本和画布拖拽、页面路由、联动器、数据通道一起挤在
/// `logic.dart` 里。那个文件不是「有一个巨型方法」，而是
/// **一个 mixin 装了七八件不相干的事**——304 个成员 7896 行，
/// 找一个复合件相关的函数要在整份文件里 grep。
///
/// 这里是按职责切分的第一刀。**纯搬运**：没有改动任何一行逻辑、
/// 没有改任何签名。仍是 `mixin _AssemblyLogic` 的一部分，
/// 通过 `part` 拼回去，私有成员照常互相可见。
///
/// ## 装了什么
///
/// | 区块 | 成员 |
/// |---|---|
/// | 覆写摘要文案 | `_propertyOverrideStatusText` |
/// | 覆写项主列表 | `_showCompositeOverrideEntryDialog`（323 行，最大） |
/// | 暴露数据通道 | `_showExposedDataChannelEditor` |
/// | 子件整页编辑 | 见 `composite_child_editor.dart` |
/// 覆写槽位的增删查（`_ensurePropertyOverride` 等）在
/// `composite_child_editor.dart` —— 两边都要用，放在依赖链下游。
///
/// ## 改这里之前务必知道
///
/// - **HANDOFF 3.5b「双写覆盖」**：从对话框进子页面，返回后必须
///   重新回读**全部**相关状态，且不能用闭包捕获的 `module`。
/// - 复合件是黑盒，外部只能连到 `exposedPorts` 声明的子元素。
/// - 实例覆写**不回写资产库模板**（模板≠实例快照，见 HANDOFF 3.5k）。
/// - `_syncStatusFieldForOverride` 只在**刚建立绑定**时拉取状态字段值，
///   否则会覆盖作者刚改的数值（见 commit `98af02e`）。
///
/// 待办：TRACKER 4.7「复合组件编辑页重做」——用户已反馈交互别扭。

/// ## 为什么是独立 mixin 而不是接着写 `_AssemblyLogic`
///
/// Dart 的 `part` 文件**不能续写另一个 part 里打开的类体**——
/// 每个 part 各自都必须是完整的顶层声明。第一版切分时我把方法体
/// 直接裸放在这里，语法上根本不成立。
///
/// 正确做法是本文件自成一个 mixin，由 `_CharacterAssemblyPageState`
/// 一并 `with` 进去。私有成员在同一个库（part 组成的整体）内
/// 仍然互相可见，因此调用关系不受影响。
///
/// `on _AssemblyLogic` 声明了依赖：本文件用到 `_activePropertyOverrides`
/// / `_persistAssemblyElements` / `_deepCloneValue` 等成员，
/// 它们都定义在 `logic.dart` 里。
mixin _AssemblyCompositeLogic
    on State<CharacterAssemblyPage>, _AssemblyLogic, _CompositeChildEditor {

  String _propertyOverrideStatusText(PropertyOverride override) {
    final parts = <String>[];
    final fieldKeys = override.overrides.keys
        .where((key) => key != 'dataChannel')
        .toList();
    if (fieldKeys.isNotEmpty) parts.add('字段覆写');
    if (override.overrides['dataChannel'] is Map) parts.add('已配通道');
    if (parts.isEmpty) return '空槽位';
    return parts.join(' + ');
  }

  Widget _buildCompositeEditorSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111116),
        ),
      ),
    );
  }

  Widget _buildCompositeInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF777783),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF33333A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 复合件内**全部**可编辑的原子子件（递归展开嵌套复合件）。
  ///
  /// 与 `_exposedChildrenOfComposite` 的区别：
  /// 那个按 `exposedPorts` 过滤，用于**对外连线**；
  /// 这个不过滤，用于**实例内编辑**。
  ///
  /// 复合件对外仍是黑盒（外部只能连到暴露端口），
  /// 但作者点进实例编辑器后，理应能调整里面每一个零件——
  /// 就像拆开机箱后每颗螺丝都拧得动，不代表机箱外壳多了接口。
  List<UIElement> _editableChildrenOfComposite(UIElement compositeElement) {
    final composite = compositeElement.composite;
    if (!compositeElement.isComposite || composite == null) return const [];
    final result = <UIElement>[];
    void walk(List<UIElement> nodes) {
      for (final node in nodes) {
        if (node.isComposite && node.composite != null) {
          walk(node.composite!.children);
          continue;
        }
        final module = node.module;
        if (module == null) continue;
        // linker / page_router 是纯逻辑件，没有实例级可调项。
        if (const {'linker', 'page_router'}.contains(module.type)) continue;
        result.add(node);
      }
    }

    walk(composite.children);
    return result;
  }

  Future<void> _showCompositeOverrideEntryDialog(UIElement compositeElement) async {
    if (!compositeElement.isComposite || compositeElement.composite == null) return;
    // 列出**全部**原子子件，不再只限暴露项。
    //
    // exposedPorts 的本职是「对外连线时允许接到哪个子元素」，
    // 拿它兼任「哪些子件可编辑」是历史误用：
    // 作者想改复合件里某个文字的字号，却因为模板没暴露它而改不了。
    // 现在两者解耦——连线仍受 exposedPorts 约束，编辑不再受限。
    final editableChildren = _editableChildrenOfComposite(compositeElement);

    await showKeyboardSafeDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          List<PropertyOverride> overridesOf(UIElement child) {
            return _propertyOverridesForComposite(compositeElement.id)
                .where((override) => override.componentId == child.id)
                .toList();
          }

          // 13 种原子类型现在全部可编辑（走字段组），
          // 不再有「该类型不支持」的死角。
          final hasEditableChildren = editableChildren.isNotEmpty;

          return AlertDialog(
            title: const Text('复合组件实例编辑器'),
            content: SizedBox(
              width: 430,
              // AlertDialog 内部使用 IntrinsicWidth 测量内容，
              // 因此这里必须给定确定宽度；高度只限制上限，超出由外层滚动。
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompositeEditorSectionTitle('实例信息'),
                  _buildCompositeInfoLine(
                    '模板名',
                    compositeElement.composite?.name ?? '未命名复合组件',
                  ),
                  _buildCompositeInfoLine('实例 ID', compositeElement.id),
                  _buildCompositeInfoLine('所在页面', _displayPageName(_activePage)),
                  _buildCompositeInfoLine(
                    '尺寸 / 位置',
                    '${compositeElement.size.width.toStringAsFixed(0)}×${compositeElement.size.height.toStringAsFixed(0)} · '
                    '(${compositeElement.offset.dx.toStringAsFixed(0)}, ${compositeElement.offset.dy.toStringAsFixed(0)})',
                  ),
                  const SizedBox(height: 10),
                  _buildCompositeEditorSectionTitle('子件设置'),
                  Text(
                    hasEditableChildren
                        ? '点进任一子件即可像编辑画布上的独立组件那样，'
                            '调整它的专属设置、外观、动画与数据通道。'
                            '所有改动只作用于当前这个实例，不回写资产库模板。'
                        : '该复合组件内没有可编辑的原子子件。',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF777783),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (editableChildren.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFECB3)),
                      ),
                      child: const Text(
                        '没有可编辑的原子子件。当前实例仍可移动、缩放和参与页面布局。',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8D6E00),
                          height: 1.35,
                        ),
                      ),
                    )
                  else
                    // 用 Column 而非 ListView：AlertDialog 会对内容做 intrinsic 测量，
                    // 而 ListView 不支持 intrinsic 尺寸，会触发 hasSize 断言。
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      for (var index = 0; index < editableChildren.length; index++)
                        Builder(builder: (context) {
                        final child = editableChildren[index];
                        final type = child.module?.type ?? 'unknown';
                        final overrides = overridesOf(child);
                        final hasSlot = overrides.isNotEmpty;
                        final statusText = hasSlot
                            ? _propertyOverrideStatusText(overrides.first)
                            : '未创建覆写槽位';
                        return Container(
                          margin: EdgeInsets.only(
                            bottom:
                                index == editableChildren.length - 1 ? 0 : 8,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasSlot
                                ? const Color(0xFFF3E5F5)
                                : const Color(0xFFF6F6F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasSlot
                                  ? const Color(0xFFD1C4E9)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _compositeChildAccentColor(type),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          child.module?.name ?? child.id,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF111116),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$type · $statusText',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF777783),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 不再区分「创建槽位」与「编辑」两步：
                                  // 槽位是实现细节，作者只想改这个零件。
                                  // 需要时按需创建，全改回默认时自动移除。
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      final target = hasSlot
                                          ? overrides.first
                                          : _ensurePropertyOverride(
                                              componentId: child.id,
                                              sourceElementId:
                                                  compositeElement.id,
                                              sourceCompositeId:
                                                  compositeElement
                                                      .composite?.id,
                                            );
                                      await _openCompositeChildEditor(
                                        compositeElement: compositeElement,
                                        child: child,
                                        propertyOverride: target,
                                      );
                                      setDialogState(() {});
                                    },
                                    child: Text(hasSlot ? '编辑' : '设置'),
                                  ),
                                ],
                              ),
                              // 覆写槽位的操作按钮独占一行并允许换行，
                              // 避免与名称同行时在窄弹窗里挤压导致溢出。
                              if (hasSlot)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: -8,
                                  children: [
                                    // 外观 / 字段 / 动画 / 通道 / 改名
                                    // 已全部并入整页编辑器，这里只留「清除覆写」。
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _removePropertyOverride(child.id);
                                        });
                                        setDialogState(() {});
                                      },
                                      child: const Text('清除覆写'),
                                    ),
                                  ],
                                ),
                              if (hasSlot &&
                                  overrides.first.overrides['dataChannel']
                                      is Map)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '数据通道：${_dataChannelSummary(Map<String, dynamic>.from(overrides.first.overrides['dataChannel'] as Map))}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF00897B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                        }),
                      ],
                    ),
                  const SizedBox(height: 12),
                  _buildCompositeEditorSectionTitle('数据通道'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: const Text(
                      '每个已创建覆写槽位的暴露项都可以通过“通道”按钮配置数据通道与 AI 读写策略。通道配置随实例覆写保存，不回写资产库模板。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777783),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCompositeEditorSectionTitle('高级'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFECB3)),
                    ),
                    child: const Text(
                      '重置覆写、查看模板来源、另存为新模板等高级操作后续开放。本编辑器默认只修改当前实例，不回写资产库模板。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8D6E00),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  UIElement _applyPropertyOverridesToElement(
    UIElement element,
    List<PropertyOverride> overrides,
  ) {
    if (!element.isComposite || element.composite == null || overrides.isEmpty) {
      return element;
    }

    UIElement patchNode(UIElement node) {
      if (!node.isComposite && node.module != null) {
        final matched = overrides
            .where((override) => override.componentId == node.id)
            .toList();
        if (matched.isEmpty) return node;
        final props = Map<String, dynamic>.from(
          _deepCloneValue(node.module!.properties) as Map,
        );
        // 先把多条覆写合并成一张表，再分「外观键」与「普通属性」两路套用。
        //
        // 外观五项不在 properties 里，是 UIModule 的独立字段；
        // 直接 addAll 进 props 不会报错但**渲染时读不到**
        // （HANDOFF 3.5j 那类静默失效）。见 AppearanceOverrideKeys。
        final merged = <String, dynamic>{};
        for (final override in matched) {
          merged.addAll(
            Map<String, dynamic>.from(
              _deepCloneValue(override.overrides) as Map,
            )..remove('dataChannel'),
          );
        }
        // null 表示「模板里有、覆写要求删掉」（字段组的 props.remove 路径）。
        // 直接 addAll 会把值设成 null，渲染端多半按「有这个键」处理，
        // 与「回落默认」不是一回事，因此显式 remove。
        final plain = AppearanceOverrideKeys.stripFrom(merged)
          ..remove(kCompositeChildNameOverrideKey);
        for (final entry in plain.entries) {
          if (entry.value == null) {
            props.remove(entry.key);
          } else {
            props[entry.key] = entry.value;
          }
        }
        var patched = node.module!.copyWith(properties: props);
        patched = AppearanceOverrideKeys.applyTo(patched, merged);
        // 实例改名：与外观同理，name 也是独立字段。
        final overriddenName = merged[kCompositeChildNameOverrideKey]?.toString();
        if (overriddenName != null && overriddenName.trim().isNotEmpty) {
          patched = patched.copyWith(name: overriddenName.trim());
        }
        return node.copyWith(module: patched);
      }
      if (node.isComposite && node.composite != null) {
        return node.copyWith(
          composite: node.composite!.copyWith(
            children: node.composite!.children.map(patchNode).toList(),
          ),
        );
      }
      return node;
    }

    return element.copyWith(
      composite: element.composite!.copyWith(
        children: element.composite!.children.map(patchNode).toList(),
      ),
    );
  }

  Color _compositeChildAccentColor(String type) {
    switch (type) {
      case 'progress':
      case 'slider':
        return const Color(0xFF00E676);
      case 'text':
      case 'input':
      case 'select':
        return const Color(0xFF651FFF);
      case 'switch':
        return const Color(0xFFFFA726);
      case 'button':
        return const Color(0xFFFFD740);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

}
