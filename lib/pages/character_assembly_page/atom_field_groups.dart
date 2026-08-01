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

  /// 本组持有的控制器，交给对话框统一托管。
  ///
  /// **不要自己在 `await showDialog(...)` 之后 dispose**：
  /// future 在 pop 那一刻就完成，但退场动画还要跑 ~150ms，
  /// 期间 TextField 仍在重建，会抛
  /// 「A TextEditingController was used after being disposed」
  /// （见 HANDOFF 3.5h；本文件也栽过一次）。
  /// 一律传给 `showKeyboardSafeDialog(disposables: ...)`，
  /// 由它在路由彻底移除后释放。
  List<ChangeNotifier> get disposables;
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
  List<ChangeNotifier> get disposables => [
        _textController,
        _fontSizeController,
      ];
}

/// switch 组件：只有一个「默认开启」。
class SwitchFieldGroup extends AtomFieldGroup {
  SwitchFieldGroup(UIModule module)
      : _value = module.properties['value'] != false;

  bool _value;

  /// 供外部回写（数据通道专项页可能改了开关的当前值）。
  ///
  /// 「双写覆盖」陷阱（HANDOFF 3.5b）：专项页写的是 `_elements`，
  /// 而本字段组里的 `_value` 仍是打开对话框那一刻的旧值。
  /// 不回写的话，保存时会用旧值把专项页刚改的覆盖掉。
  set value(bool v) => _value = v;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('默认开启', style: TextStyle(fontSize: 13)),
          value: _value,
          onChanged: (v) => ctx.setDialogState(() => _value = v),
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) => props['value'] = _value;

  @override
  List<ChangeNotifier> get disposables => const [];
}

/// line 组件：方向 / 线型 / 粗细。
class LineFieldGroup extends AtomFieldGroup {
  LineFieldGroup(UIModule module)
      : _thicknessController = TextEditingController(
          text: (_readNum(module.properties['thickness']) ?? 2.0)
              .toStringAsFixed(0),
        ),
        _axis = module.properties['axis']?.toString() == 'vertical'
            ? 'vertical'
            : 'horizontal',
        _style = module.properties['lineStyle']?.toString() == 'dashed'
            ? 'dashed'
            : 'solid';

  final TextEditingController _thicknessController;
  String _axis;
  String _style;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _axis,
          decoration: const InputDecoration(labelText: '方向'),
          items: const [
            DropdownMenuItem(value: 'horizontal', child: Text('横向')),
            DropdownMenuItem(value: 'vertical', child: Text('纵向')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ctx.setDialogState(() => _axis = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _style,
          decoration: const InputDecoration(labelText: '线型'),
          items: const [
            DropdownMenuItem(value: 'solid', child: Text('实线')),
            DropdownMenuItem(value: 'dashed', child: Text('虚线')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ctx.setDialogState(() => _style = v);
          },
        ),
        const SizedBox(height: 12),
        ctx.numberField(_thicknessController, '粗细'),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['axis'] = _axis;
    props['lineStyle'] = _style;
    props['thickness'] =
        double.tryParse(_thicknessController.text.trim()) ?? 2.0;
  }

  @override
  List<ChangeNotifier> get disposables => [_thicknessController];
}

/// indicator 组件：状态点直径 / 默认发光。
///
/// 注意**没有** isOn / onColor 这类键——指示灯的颜色由 `statusRules`
/// 决定（见 LinkerService.resolveIndicatorActiveState），
/// 那套规则在别处编辑，不属于本字段组。
class IndicatorFieldGroup extends AtomFieldGroup {
  IndicatorFieldGroup(UIModule module)
      : _dotSizeController = TextEditingController(
          text: (_readNum(module.properties['dotSize']) ?? 14.0)
              .toStringAsFixed(0),
        ),
        _glow = module.properties['defaultGlow'] == true;

  final TextEditingController _dotSizeController;
  bool _glow;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        ctx.numberField(_dotSizeController, '状态点直径', suffix: '8~28'),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('默认发光', style: TextStyle(fontSize: 13)),
          value: _glow,
          onChanged: (v) => ctx.setDialogState(() => _glow = v),
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['dotSize'] = (double.tryParse(_dotSizeController.text.trim()) ?? 14.0)
        .clamp(8.0, 28.0)
        .toDouble();
    props['defaultGlow'] = _glow;
  }

  @override
  List<ChangeNotifier> get disposables => [_dotSizeController];
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
      case 'switch':
        return SwitchFieldGroup(module);
      case 'line':
        return LineFieldGroup(module);
      case 'indicator':
        return IndicatorFieldGroup(module);
      default:
        return null;
    }
  }
}
