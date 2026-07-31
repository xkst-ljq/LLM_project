part of '../character_assembly_page.dart';

/// 数据通道页的共用表单控件（4.3 HUD 优化）。
///
/// 抽出来单独成文件的原因：`logic.dart` 已经 7700 行，
/// 而这几个控件是纯展示、无状态依赖，混进去只会让那个文件更难找东西。
///
/// 设计取向来自用户：
/// - 选项少（3~4 个）的**直接平铺**，不用下拉——一眼看全，点一下就选中
/// - 通知方式用**状态灯**表达
/// - 项数不定的（如文本标签）才用下拉，且**统一向下展开 + 圆角**
///
/// 原来九个 `DropdownButtonFormField` 平铺的问题：
/// 1. 弹出方向不可控（靠近屏幕底部往上弹、中间盖住自己），眼睛要重新找
/// 2. 选项列表是系统菜单，圆角/间距/选中态都不受控
/// 3. 只有 3~4 项却要点开才知道有什么

/// 分段选择器：选项平铺成一排，点中即选。
///
/// 超过一行会自动换行（`Wrap`）——中文选项标签长度差异大，
/// 强行等分会让「不发送」和「发送到 Prompt」宽度一样，浪费横向空间。
class SegmentedFieldOption {
  const SegmentedFieldOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;
}

class SegmentedField extends StatelessWidget {
  const SegmentedField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.accent = const Color(0xFF00897B),
    this.helper,
  });

  final String label;
  final String value;
  final List<SegmentedFieldOption> options;
  final ValueChanged<String> onChanged;
  final Color accent;

  /// 选中项下方的补充说明。随选择变化时传进来即可。
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF555562),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              _SegmentChip(
                option: option,
                selected: option.value == value,
                accent: accent,
                onTap: () => onChanged(option.value),
              ),
          ],
        ),
        if (helper != null && helper!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF777783),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final SegmentedFieldOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.12) : const Color(0xFFF4F4F7),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? accent : Colors.black.withValues(alpha: 0.07),
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(
                  option.icon,
                  size: 14,
                  color: selected ? accent : const Color(0xFF888896),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? accent : const Color(0xFF555562),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆角下拉：**固定向下展开**，样式与页面统一。
///
/// 只用于项数不定的场景（如「标签文本」，数量取决于画布上有几个 Text）。
/// 项数固定且少的一律用 [SegmentedField]。
///
/// 用 `MenuAnchor` 而不是 `DropdownButtonFormField`：
/// 后者的弹出方向由 Flutter 按可用空间决定，同一页九个下拉方向各不相同。
/// `MenuAnchor` 的 `alignmentOffset` 能钉死在触发器正下方。
class RoundedDropdownOption {
  const RoundedDropdownOption({required this.value, required this.label});

  final String value;
  final String label;
}

class RoundedDropdownField extends StatelessWidget {
  const RoundedDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.accent = const Color(0xFF00897B),
  });

  final String label;
  final String value;
  final List<RoundedDropdownOption> options;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final matched = options.where((o) => o.value == value);
    final currentLabel = matched.isEmpty ? '请选择' : matched.first.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF555562),
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return MenuAnchor(
              // 钉在触发器正下方：不加这个偏移会盖住触发器自身，
              // 作者看不到「我正在改哪一项」。
              alignmentOffset: const Offset(0, 4),
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(Colors.white),
                elevation: const WidgetStatePropertyAll(8),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 6),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.black.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                // 菜单宽度跟随触发器，避免长短选项导致宽度跳动。
                maximumSize: WidgetStatePropertyAll(
                  Size(constraints.maxWidth, 320),
                ),
                minimumSize: WidgetStatePropertyAll(
                  Size(constraints.maxWidth, 0),
                ),
              ),
              menuChildren: [
                for (final option in options)
                  MenuItemButton(
                    onPressed: () => onChanged(option.value),
                    style: ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        option.value == value
                            ? accent.withValues(alpha: 0.10)
                            : Colors.transparent,
                      ),
                    ),
                    child: SizedBox(
                      width: constraints.maxWidth - 24,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: option.value == value
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: option.value == value
                              ? accent
                              : const Color(0xFF333340),
                        ),
                      ),
                    ),
                  ),
              ],
              builder: (context, controller, child) => Material(
                color: const Color(0xFFF4F4F7),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333340),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Color(0xFF888896),
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
}

/// 段落卡片：把相关字段圈成一块，配序号与标题。
///
/// 原来九个下拉等宽平铺、间距均匀，第 1 项和第 7 项看起来一样重，
/// 作者反馈「整页都是列排列，容易眼花缭乱，每一条的关系连接上也不大」。
class DataChannelSection extends StatelessWidget {
  const DataChannelSection({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.children,
  });

  final int index;
  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111116),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9999A6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// 名称输入框 + 状态字段建议。
///
/// 用户诉求：绑定状态字段时不用手打名字，点一下从状态栏已有字段里选。
/// **但不能影响手动输入**——所以：
/// - 输入框本身始终是普通 `TextField`，随便打
/// - 建议列表只由右侧按钮触发，聚焦、输入都不会弹出来打扰
/// - 没有可选字段时按钮直接不显示，避免点开一片空白
class NameSuggestion {
  const NameSuggestion({
    required this.name,
    required this.detail,
    this.matched = false,
  });

  final String name;

  /// 副标题：类型 / 归属等，帮作者区分同名难辨的字段。
  final String detail;

  /// 是否与当前输入完全一致。
  final bool matched;
}

class SuggestibleNameField extends StatefulWidget {
  const SuggestibleNameField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.onChanged,
    this.accent = const Color(0xFF00897B),
    this.emptyHint,
  });

  final TextEditingController controller;
  final String label;
  final List<NameSuggestion> suggestions;
  final ValueChanged<String>? onChanged;
  final Color accent;

  /// 没有可选字段时，点按钮给出的说明。为空则连按钮都不显示。
  final String? emptyHint;

  @override
  State<SuggestibleNameField> createState() => _SuggestibleNameFieldState();
}

class _SuggestibleNameFieldState extends State<SuggestibleNameField> {
  final MenuController _menu = MenuController();

  void _pick(String name) {
    widget.controller.text = name;
    // 光标移到末尾：不设的话选完再点输入框，光标会跳回开头，
    // 想接着改就得先按一堆右方向键。
    widget.controller.selection =
        TextSelection.collapsed(offset: name.length);
    widget.onChanged?.call(name);
    _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    final hasSuggestions = widget.suggestions.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            elevation: const WidgetStatePropertyAll(8),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 6),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
              ),
            ),
            maximumSize:
                WidgetStatePropertyAll(Size(constraints.maxWidth, 300)),
            minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          ),
          menuChildren: [
            for (final s in widget.suggestions)
              MenuItemButton(
                onPressed: () => _pick(s.name),
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    s.matched
                        ? widget.accent.withValues(alpha: 0.10)
                        : Colors.transparent,
                  ),
                ),
                child: SizedBox(
                  width: constraints.maxWidth - 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: s.matched
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: s.matched
                                    ? widget.accent
                                    : const Color(0xFF333340),
                              ),
                            ),
                            if (s.detail.isNotEmpty)
                              Text(
                                s.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF9999A6),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (s.matched)
                        Icon(Icons.check_rounded,
                            size: 15, color: widget.accent),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, child) => TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: widget.label,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: (!hasSuggestions && widget.emptyHint == null)
                  ? null
                  : IconButton(
                      tooltip: hasSuggestions ? '从状态栏字段中选择' : widget.emptyHint,
                      icon: Icon(
                        Icons.playlist_add_check_rounded,
                        size: 19,
                        color: hasSuggestions
                            ? widget.accent
                            : const Color(0xFFBDBDC6),
                      ),
                      onPressed: !hasSuggestions
                          ? null
                          : () {
                              // 先收键盘：菜单从输入框正下方展开，
                              // 键盘占着半屏时菜单会被挤到看不见。
                              FocusManager.instance.primaryFocus?.unfocus();
                              controller.isOpen
                                  ? controller.close()
                                  : controller.open();
                            },
                    ),
            ),
            onChanged: (_) => widget.onChanged?.call(widget.controller.text),
          ),
        );
      },
    );
  }
}
