part of '../character_assembly_page.dart';

/// 原子组件实例编辑器的「字段组」。
///
/// ## 解决什么问题
///
/// `_showAtomInstanceEditorDialog` 曾是一个 **1123 行**的方法，
/// 13 种组件类型的编辑逻辑全塞在里面，而且是**分三处**写的：
///
/// ```
/// L5382  final textController = TextEditingController(...)   ← 建控制器
/// L5638  if (type == 'text') ...[ TextField(...) ]           ← 构建表单
/// L6271  if (type == 'text') { props['text'] = ... }         ← 保存写回
/// ```
///
/// 三处相隔几百上千行，改一种类型要在三个地方各找一遍。
/// 本项目已经因此栽过多次（见 HANDOFF 3.5b「双写覆盖」）：
/// 加了字段却忘了写回、写回了却没 dispose、改了保存忘了改表单……
///
/// ## 这里的做法
///
/// 每种类型一个 [AtomFieldGroup] 子类，把**四件事关在一起**：
///
/// | 职责 | 方法 |
/// |---|---|
/// | 从 module 读初值、建控制器 | 构造函数 |
/// | 构建表单控件 | [buildFields] |
/// | 把编辑结果写回 properties | [applyTo] |
/// | 释放控制器 | [dispose] |
///
/// 改一种类型只需动一个类，**从结构上消除了「漏改一处」的可能**。
///
/// ## 迁移策略
///
/// 存量类型逐个迁移，未迁移的仍走对话框里的老分支
/// （[AtomFieldGroupRegistry.of] 返回 null 即表示「还没迁」）。
/// 这样每迁一种都能单独验证，不必一次性重写全部 13 种。

/// 字段组构建表单时可用的共享工具。
///
/// 这些原本是对话框闭包里的局部函数，抽出来供各字段组复用。
class AtomFieldContext {
  const AtomFieldContext({
    required this.setDialogState,
    required this.numberField,
    required this.readDouble,
  });

  /// 触发对话框重建。字段组内部改了自己的可变状态后必须调它。
  final void Function(VoidCallback) setDialogState;

  /// 统一样式的数字输入框。
  final Widget Function(TextEditingController controller, String label,
      {String? suffix}) numberField;

  /// 读数字，解析失败时回落。
  final double Function(TextEditingController controller, double fallback)
      readDouble;
}

/// 某种组件类型的编辑字段组。
abstract class AtomFieldGroup {
  /// 构建该类型专属的表单控件。
  ///
  /// 返回的列表会被插进对话框的 Column 里；空列表表示该类型没有专属字段。
  List<Widget> buildFields(AtomFieldContext ctx);

  /// 把当前编辑状态写回 [props]。
  ///
  /// [props] 是 module.properties 的深拷贝，直接改即可。
  void applyTo(Map<String, dynamic> props);

  /// 释放持有的控制器。
  ///
  /// **不要在这里做别的事**：调用方是在对话框关闭后统一调的，
  /// 此时 widget 树已经拆掉。
  void dispose();
}

/// text 组件的字段组。
///
/// 覆盖：文本内容 / 字号 / 超出处理 / 对齐 / 富文本开关。
class TextFieldGroup extends AtomFieldGroup {
  TextFieldGroup(UIModule module)
      : _textController = TextEditingController(
          text: module.properties['text']?.toString() ?? '',
        ),
        _fontSizeController = TextEditingController(
          text: (_readNum(module.properties['fontSize']) ?? 14.0)
              .toStringAsFixed(0),
        ) {
    _overflow = switch (module.properties['overflow']?.toString()) {
      'scroll' => 'scroll',
      'clip' => 'clip',
      _ => 'ellipsis',
    };
    // A11-2 富文本开关。默认值随显示模式而定：
    //   滚动模式 → 开。readme / 道具说明几乎都带标题和列表。
    //   其余模式 → 关。这类 text 多被 linker 指向来显示数值或短标签，
    //              解析反而会把「HP<50」误判成 HTML 标签。
    // 作者显式设过就以存档为准，不再按模式推断。
    _richText = module.properties.containsKey('richText')
        ? module.properties['richText'] == true
        : _overflow == 'scroll';
    _align = switch (module.properties['textAlign']?.toString()) {
      'left' => 'left',
      'right' => 'right',
      _ => 'center',
    };
  }

  final TextEditingController _textController;
  final TextEditingController _fontSizeController;
  late String _overflow;
  late bool _richText;
  late String _align;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        TextField(
          controller: _textController,
          // 长文说明可能很长，给足编辑空间。
          maxLines: _overflow == 'scroll' ? 10 : 3,
          minLines: _overflow == 'scroll' ? 6 : 1,
          decoration: const InputDecoration(labelText: '文本内容'),
        ),
        const SizedBox(height: 12),
        ctx.numberField(_fontSizeController, '字号'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _overflow,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '超出显示区时',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'ellipsis', child: Text('省略号截断')),
            DropdownMenuItem(value: 'clip', child: Text('直接裁切')),
            DropdownMenuItem(value: 'scroll', child: Text('可滚动（长文说明）')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ctx.setDialogState(() => _overflow = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _align,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '对齐方式',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('左对齐')),
            DropdownMenuItem(value: 'center', child: Text('居中')),
            DropdownMenuItem(value: 'right', child: Text('右对齐')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ctx.setDialogState(() => _align = v);
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('富文本渲染', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '识别 Markdown 标题 / 列表 / 表格与 HTML 排版。'
            '显示纯数值或短标签时建议关闭。',
            style: TextStyle(fontSize: 11, height: 1.3),
          ),
          value: _richText,
          onChanged: (v) => ctx.setDialogState(() => _richText = v),
        ),
        if (_overflow == 'scroll')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '滚动模式：内容从顶部开始、可选中复制、带滚动条。'
              '适合角色说明、道具描述等长文；'
              '内容也可由联动器或数据通道动态注入。'
              '富文本默认开启——readme 与道具说明几乎都带标题和列表。',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF777783),
                height: 1.35,
              ),
            ),
          ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['text'] = _textController.text;
    props['fontSize'] =
        double.tryParse(_fontSizeController.text.trim()) ?? 14.0;
    props['overflow'] = _overflow;
    props['textAlign'] = _align;
    props['richText'] = _richText;
  }

  @override
  void dispose() {
    _textController.dispose();
    _fontSizeController.dispose();
  }
}

/// 宽松读数值。
///
/// 与 `_numProp` 同款：**字符串形式的数字也要认**。
/// 历史存档里 fontSize 可能存成 `"14"` 而非 `14`，
/// 只写 `as num?` 会让它回落默认值，等于打开编辑器就把字号改了。
double? _readNum(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

/// 类型 → 字段组的工厂表。
///
/// 未登记的类型返回 null，调用方回落到对话框里的老分支。
/// 迁移一种类型 = 写一个子类 + 在这里加一行。
class AtomFieldGroupRegistry {
  static AtomFieldGroup? of(UIModule module) {
    switch (module.type) {
      case 'text':
        return TextFieldGroup(module);
      default:
        return null;
    }
  }
}
