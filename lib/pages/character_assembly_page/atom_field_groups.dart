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
/// ## 迁移状态
///
/// 分四批迁完，现已**全部到位**：
///
/// | 批次 | 类型 |
/// |---|---|
/// | 1 | `text` |
/// | 2 | `switch` `line` `indicator` |
/// | 3 | `progress` `slider` |
/// | 4 | `button` `input` `select` `message_flow` `image` |
///
/// 对话框里那条 `if (type == 'xxx')` 长链已彻底消失。
/// [AtomFieldGroupRegistry.of] 返回 null 现在只意味着
/// **该类型没有专属字段**（如 `surface` / `base_box`，
/// 外观走专项页），不再表示「还没迁」。
///
/// `timer` / `math_node` 是纯逻辑件，各有独立编辑器，不走这里。

/// 字段组构建表单时可用的共享工具。
///
/// 这些原本是对话框闭包里的局部函数，抽出来供各字段组复用。
class AtomFieldContext {
  const AtomFieldContext({
    required this.setDialogState,
    required this.numberField,
    required this.readDouble,
    this.usesNonTapGesture = false,
    this.sendsMessage = false,
  });

  /// 触发对话框重建。字段组内部改了自己的可变状态后必须调它。
  final void Function(VoidCallback) setDialogState;

  /// 统一样式的数字输入框。
  final Widget Function(TextEditingController controller, String label,
      {String? suffix}) numberField;

  /// 读数字，解析失败时回落。
  final double Function(TextEditingController controller, double fallback)
      readDouble;

  /// 本 button 是否被双击 / 长按方案引用。
  ///
  /// 手感参数只在真用到时才显示，否则平白多两个数字框，作者还得猜用途。
  /// 这个判断要查全页的联动器，字段组拿不到，只能由对话框传进来。
  final bool usesNonTapGesture;

  /// 本组件是否标了「发送消息」职责。
  ///
  /// input 的多行开关要据此改写副标题：多行下回车只换行，
  /// `onSubmitted` 不再触发，标了发送的输入框就发不出去了。
  final bool sendsMessage;
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

  /// 数值型字段组可实现它，接收来自数据通道专项页的量程回读。
  ///
  /// 「双写覆盖」（HANDOFF 3.5b）：专项页绑定状态字段后会改写
  /// `_elements`，而字段组里的控制器仍是打开那一刻的旧值。
  /// 不回读的话，保存时会用旧量程覆盖掉刚绑好的。
  ///
  /// 返回 null 表示本类型没有量程概念（如 text / switch）。
  RangeControllers? get rangeControllers => null;

  /// 承载「内容文本」的控制器，接收来自数据通道专项页的文本回读。
  ///
  /// 与 [rangeControllers] 同源的问题：绑定文本型状态字段后，
  /// `_fillControllersFromStatusField` 要把字段值写进组件的内容框。
  /// 迁移前它写的是对话框里的 `textController`；类型迁入字段组后
  /// 那个控制器已经不再是显示中的那一个，不暴露的话回读会**静默失效**。
  ///
  /// 返回 null 表示本类型没有文本内容（如 progress / line）。
  TextEditingController? get contentController => null;

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
  TextEditingController get contentController => _textController;

  @override
  List<ChangeNotifier> get disposables => [
        _textController,
        _fontSizeController,
      ];
}

/// 数值型字段组对外暴露的三个量程控制器。
///
/// 让 `_fillControllersFromStatusField` 直接写这些 controller，
/// 而不是让字段组再维护一份影子状态——两份状态必然漂移。
class RangeControllers {
  const RangeControllers({
    required this.min,
    required this.max,
    required this.current,
  });

  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController current;
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

/// progress 组件：最小值 / 最大值 / 当前值。
///
/// 与 [SliderFieldGroup] 的差别**刻意保留**：progress 不做区间夹取，
/// 因为它常被 linker 驱动，作者填的只是初值；
/// slider 是玩家直接拖的，越界会让滑块跑到轨道外。
class ProgressFieldGroup extends AtomFieldGroup {
  ProgressFieldGroup(UIModule module)
      : _min = TextEditingController(
          text: (_readNum(module.properties['min']) ?? 0.0).toStringAsFixed(0),
        ),
        _max = TextEditingController(
          text:
              (_readNum(module.properties['max']) ?? 100.0).toStringAsFixed(0),
        ),
        _current = TextEditingController(
          text: (_readNum(module.properties['current']) ?? 0.0)
              .toStringAsFixed(0),
        );

  final TextEditingController _min;
  final TextEditingController _max;
  final TextEditingController _current;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ctx.numberField(_min, '最小值')),
            const SizedBox(width: 10),
            Expanded(child: ctx.numberField(_max, '最大值')),
          ],
        ),
        const SizedBox(height: 12),
        ctx.numberField(_current, '当前值'),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['min'] = double.tryParse(_min.text.trim()) ?? 0.0;
    props['max'] = double.tryParse(_max.text.trim()) ?? 100.0;
    props['current'] = double.tryParse(_current.text.trim()) ?? 0.0;
  }

  @override
  RangeControllers get rangeControllers =>
      RangeControllers(min: _min, max: _max, current: _current);

  @override
  List<ChangeNotifier> get disposables => [_min, _max, _current];
}

/// slider 组件：最小值 / 最大值 / 当前值 / 步长。
///
/// 保存时做三重校正（与迁移前一致）：
///   1. max < min 时把 max 抬到 min，避免出现负区间；
///   2. current 夹取到 [min, max]，否则滑块会跑到轨道外；
///   3. step 取绝对值，且 0 回落为 1——步长为 0 会让滑块拖不动。
class SliderFieldGroup extends AtomFieldGroup {
  SliderFieldGroup(UIModule module)
      : _min = TextEditingController(
          text: (_readNum(module.properties['min']) ?? 0.0).toStringAsFixed(0),
        ),
        _max = TextEditingController(
          text:
              (_readNum(module.properties['max']) ?? 100.0).toStringAsFixed(0),
        ),
        _current = TextEditingController(
          text: (_readNum(module.properties['current']) ?? 0.0)
              .toStringAsFixed(0),
        ),
        _step = TextEditingController(
          text: (_readNum(module.properties['step']) ?? 1.0).toStringAsFixed(2),
        );

  final TextEditingController _min;
  final TextEditingController _max;
  final TextEditingController _current;
  final TextEditingController _step;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ctx.numberField(_min, '最小值')),
            const SizedBox(width: 10),
            Expanded(child: ctx.numberField(_max, '最大值')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ctx.numberField(_current, '当前值')),
            const SizedBox(width: 10),
            Expanded(child: ctx.numberField(_step, '步长')),
          ],
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    final minVal = double.tryParse(_min.text.trim()) ?? 0.0;
    var maxVal = double.tryParse(_max.text.trim()) ?? 100.0;
    if (maxVal < minVal) maxVal = minVal;
    props['min'] = minVal;
    props['max'] = maxVal;
    props['current'] = (double.tryParse(_current.text.trim()) ?? minVal)
        .clamp(minVal, maxVal)
        .toDouble();
    final step = (double.tryParse(_step.text.trim()) ?? 1.0).abs();
    props['step'] = step <= 0 ? 1.0 : step;
  }

  @override
  RangeControllers get rangeControllers =>
      RangeControllers(min: _min, max: _max, current: _current);

  @override
  List<ChangeNotifier> get disposables => [_min, _max, _current, _step];
}

/// button 组件：手势判定手感。
///
/// button 本身是**不显形的点击热区**，没有文案、颜色之类的外观字段，
/// 所以这里只有两个毫秒数，而且只在真的用到双击 / 长按时才出现。
class ButtonFieldGroup extends AtomFieldGroup {
  ButtonFieldGroup(UIModule module)
      : _doubleTapInterval = TextEditingController(
          text: (_readNum(module.properties['doubleTapIntervalMs'])?.toInt() ??
                  300)
              .toString(),
        ),
        _longPressThreshold = TextEditingController(
          text:
              (_readNum(module.properties['longPressThresholdMs'])?.toInt() ??
                      500)
                  .toString(),
        );

  final TextEditingController _doubleTapInterval;
  final TextEditingController _longPressThreshold;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '按钮是一块「点击热区」，运行时不显形。\n'
            '想让玩家看到按下的反馈，请用联动器把它连到一个'
            ' surface，选择按压或涟漪方案。',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF555562),
              height: 1.4,
            ),
          ),
        ),
        if (ctx.usesNonTapGesture) ...[
          const SizedBox(height: 12),
          ctx.numberField(_doubleTapInterval, '双击判定间隔（毫秒，100~1000）'),
          const SizedBox(height: 12),
          ctx.numberField(_longPressThreshold, '长按判定时长（毫秒，150~3000）'),
        ],
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    // 热区不再承载文案：清掉历史遗留键，
    // 否则旧卡里存着的 text 会在升级后继续被渲染端误读。
    props
      ..remove('text')
      ..remove('showTextOnRuntime')
      ..remove('active_gesture');
    final interval = int.tryParse(_doubleTapInterval.text.trim());
    if (interval == null) {
      props.remove('doubleTapIntervalMs');
    } else {
      props['doubleTapIntervalMs'] = interval.clamp(100, 1000);
    }
    final threshold = int.tryParse(_longPressThreshold.text.trim());
    if (threshold == null) {
      props.remove('longPressThresholdMs');
    } else {
      props['longPressThresholdMs'] = threshold.clamp(150, 3000);
    }
  }

  @override
  List<ChangeNotifier> get disposables =>
      [_doubleTapInterval, _longPressThreshold];
}

/// input 组件：占位提示 / 默认文本 / 字数上限 / 多行 / 文字落点。
class InputFieldGroup extends AtomFieldGroup {
  InputFieldGroup(UIModule module)
      : _placeholder = TextEditingController(
          text: module.properties['placeholder']?.toString() ?? '',
        ),
        _text = TextEditingController(
          text: module.properties['text']?.toString() ?? '',
        ),
        _maxLength = TextEditingController(
          text: _readNum(module.properties['maxLength'])?.toInt().toString() ??
              '',
        ),
        _multiline = module.properties['multiline'] == true,
        _vAlign =
            module.properties['textVerticalAlign']?.toString() ?? 'center',
        _hAlign = module.properties['textHorizontalAlign']?.toString() ?? 'left';

  final TextEditingController _placeholder;
  final TextEditingController _text;
  final TextEditingController _maxLength;
  bool _multiline;
  String _vAlign;
  String _hAlign;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        TextField(
          controller: _placeholder,
          decoration: const InputDecoration(labelText: '占位提示'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          decoration: const InputDecoration(labelText: '默认文本（可留空）'),
        ),
        const SizedBox(height: 12),
        ctx.numberField(_maxLength, '最大字数（留空不限制）'),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('多行输入', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            // 多行时回车用于换行，onSubmitted 不再触发，
            // 标了「发送消息」的输入框就发不出去了。
            // 这个冲突不拦，只提示——作者可能就是想要个
            // 多行草稿框，再配个确认按钮来提交。
            ctx.sendsMessage
                ? '开启后可换行、文字自动贴顶。\n'
                    '注意：本组件已标记「发送消息」，'
                    '多行下回车只换行，需另配确认按钮提交。'
                : '开启后可换行、文字自动贴顶；回车不再提交。',
            style: const TextStyle(fontSize: 11),
          ),
          value: _multiline,
          onChanged: (v) => ctx.setDialogState(() => _multiline = v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _vAlign,
          decoration: const InputDecoration(
            labelText: '文字垂直位置',
            // 多行时强制贴顶，下拉不可用，说明原因免得作者疑惑。
            helperText: '把输入框拉高后，决定文字从哪里开始',
          ),
          items: const [
            DropdownMenuItem(value: 'top', child: Text('顶部')),
            DropdownMenuItem(value: 'center', child: Text('居中')),
            DropdownMenuItem(value: 'bottom', child: Text('底部')),
          ],
          onChanged: _multiline
              ? null
              : (value) {
                  if (value == null) return;
                  ctx.setDialogState(() => _vAlign = value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _hAlign,
          decoration: const InputDecoration(labelText: '文字水平位置'),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('靠左')),
            DropdownMenuItem(value: 'center', child: Text('居中')),
            DropdownMenuItem(value: 'right', child: Text('靠右')),
          ],
          onChanged: (value) {
            if (value == null) return;
            ctx.setDialogState(() => _hAlign = value);
          },
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['placeholder'] = _placeholder.text.trim();
    props['text'] = _text.text;
    final maxLen = int.tryParse(_maxLength.text.trim());
    if (maxLen == null || maxLen <= 0) {
      props.remove('maxLength');
    } else {
      props['maxLength'] = maxLen;
    }
    // 默认值不落盘，保持 properties 精简——
    // 渲染器读不到时用的正是同一组默认（center / left / 单行）。
    if (_multiline) {
      props['multiline'] = true;
    } else {
      props.remove('multiline');
    }
    if (_vAlign == 'center') {
      props.remove('textVerticalAlign');
    } else {
      props['textVerticalAlign'] = _vAlign;
    }
    if (_hAlign == 'left') {
      props.remove('textHorizontalAlign');
    } else {
      props['textHorizontalAlign'] = _hAlign;
    }
  }

  @override
  TextEditingController get contentController => _text;

  @override
  List<ChangeNotifier> get disposables => [_placeholder, _text, _maxLength];
}

/// select 组件：选项列表 + 默认选中值。
class SelectFieldGroup extends AtomFieldGroup {
  SelectFieldGroup(UIModule module)
      : _options = TextEditingController(
          text: SelectOption.parseList(module.properties['options'])
              .map((option) => option.label == option.value
                  ? option.label
                  : '${option.label}|${option.value}')
              .join('\n'),
        ),
        _defaultValue = TextEditingController(
          text: module.properties['current']?.toString() ??
              module.properties['defaultValue']?.toString() ??
              '',
        );

  final TextEditingController _options;
  final TextEditingController _defaultValue;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        TextField(
          controller: _options,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '选项列表',
            helperText: '每行一个：显示文本 或 显示文本|值',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _defaultValue,
          decoration: const InputDecoration(labelText: '默认选中值（留空取第一项）'),
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    final parsed = <Map<String, dynamic>>[];
    for (final rawLine in _options.text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('|');
      final label = parts.first.trim();
      if (label.isEmpty) continue;
      final value = parts.length > 1 && parts[1].trim().isNotEmpty
          ? parts[1].trim()
          : label;
      parsed.add({'label': label, 'value': value});
    }
    if (parsed.isNotEmpty) {
      props['options'] = parsed;
    }
    final options = SelectOption.parseList(props['options']);
    final wanted = _defaultValue.text.trim();
    final valid = options.any((option) => option.value == wanted);
    props['current'] = valid ? wanted : options.first.value;
    props['defaultValue'] = props['current'];
  }

  /// select 的「内容」是当前选中值。
  ///
  /// 注意状态字段回读到这里**不保证生效**：`applyTo` 有一道
  /// `valid ? wanted : options.first.value` 的校验，
  /// 字段值不在选项列表里就会被打回第一项。这是 select 的固有约束。
  @override
  TextEditingController get contentController => _defaultValue;

  @override
  List<ChangeNotifier> get disposables => [_options, _defaultValue];
}

/// message_flow 组件：显示条数 / 字号 / 显示哪一方 / 富文本。
class MessageFlowFieldGroup extends AtomFieldGroup {
  MessageFlowFieldGroup(UIModule module)
      : _historyLimit = TextEditingController(
          text: (_readNum(module.properties['historyLimit'])?.toInt() ?? 0) == 0
              ? ''
              : '${_readNum(module.properties['historyLimit'])!.toInt()}',
        ),
        _fontSize = TextEditingController(
          text: (_readNum(module.properties['fontSize']) ?? 12.5)
              .toStringAsFixed(0),
        ),
        _showUser = module.properties['showUser'] != false,
        _showAssistant = module.properties['showAssistant'] != false,
        // A11-2 富文本开关。默认开——LLM 回复里带 Markdown 是常态，
        // 关掉会看到满屏的 ** 和 #。
        _richText = module.properties['richText'] != false;

  final TextEditingController _historyLimit;
  final TextEditingController _fontSize;
  bool _showUser;
  bool _showAssistant;
  bool _richText;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        ctx.numberField(_historyLimit, '显示条数（留空显示全部）'),
        const SizedBox(height: 12),
        ctx.numberField(_fontSize, '字号'),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('显示玩家消息', style: TextStyle(fontSize: 13)),
          value: _showUser,
          onChanged: (v) => ctx.setDialogState(() => _showUser = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('显示角色消息', style: TextStyle(fontSize: 13)),
          value: _showAssistant,
          onChanged: (v) => ctx.setDialogState(() => _showAssistant = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('富文本渲染', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '识别 Markdown 与 HTML。默认开启——'
            '关闭后 LLM 回复里的 ** 和 # 会原样显示。',
            style: TextStyle(fontSize: 11, height: 1.3),
          ),
          value: _richText,
          onChanged: (v) => ctx.setDialogState(() => _richText = v),
        ),
        const Text(
          '窗口内可滚动；新消息自动滚到底，向上翻看历史时不会被拽回。',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF777783),
            height: 1.35,
          ),
        ),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    final limit = int.tryParse(_historyLimit.text.trim());
    // 留空或非正数一律视为「显示全部」。
    props['historyLimit'] = (limit == null || limit <= 0) ? 0 : limit;
    props['fontSize'] = double.tryParse(_fontSize.text.trim()) ?? 12.5;
    props['showUser'] = _showUser;
    props['showAssistant'] = _showAssistant;
    props['richText'] = _richText;
  }

  @override
  List<ChangeNotifier> get disposables => [_historyLimit, _fontSize];
}

/// image 组件：来源 / 地址 / 资产路径 / 填充方式 / 圆角。
///
/// 圆角这里读的是 `properties['borderRadius']`，回落到 `module.borderRadius`：
/// image 允许实例单独盖掉模板的圆角，别的类型没有这层覆写。
class ImageFieldGroup extends AtomFieldGroup {
  ImageFieldGroup(UIModule module)
      : _url = TextEditingController(
          text: module.properties['url']?.toString() ?? '',
        ),
        _assetPath = TextEditingController(
          text: module.properties['assetPath']?.toString() ?? '',
        ),
        _radius = TextEditingController(
          text: (_readNum(module.properties['borderRadius']) ??
                  module.borderRadius)
              .toStringAsFixed(0),
        ),
        // A11-2：选了头像时路径由运行时提供，作者填的静态值被忽略。
        _source = switch (module.properties['imageSource']?.toString()) {
          AvatarScope.sourceCharacter => AvatarScope.sourceCharacter,
          AvatarScope.sourceUser => AvatarScope.sourceUser,
          _ => AvatarScope.sourceCustom,
        },
        _fit = switch (module.properties['fit']?.toString()) {
          'contain' => 'contain',
          'fill' => 'fill',
          _ => 'cover',
        };

  final TextEditingController _url;
  final TextEditingController _assetPath;
  final TextEditingController _radius;
  String _source;
  String _fit;

  @override
  List<Widget> buildFields(AtomFieldContext ctx) => [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _source,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '图片来源',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(
                value: AvatarScope.sourceCustom, child: Text('自定义（下方填写）')),
            DropdownMenuItem(
                value: AvatarScope.sourceCharacter, child: Text('角色头像')),
            DropdownMenuItem(
                value: AvatarScope.sourceUser, child: Text('用户头像')),
          ],
          onChanged: (value) {
            if (value == null) return;
            ctx.setDialogState(() => _source = value);
          },
        ),
        if (AvatarScope.isDynamic(_source))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '头像路径在运行时才确定，下面的地址与路径会被忽略。'
              '玩家没设置头像时这里显示为空。',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF777783),
                height: 1.35,
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          enabled: !AvatarScope.isDynamic(_source),
          decoration: const InputDecoration(labelText: '网络图片地址（可留空）'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _assetPath,
          enabled: !AvatarScope.isDynamic(_source),
          decoration:
              const InputDecoration(labelText: '本地/内部资产路径（可留空）'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _fit,
          decoration: const InputDecoration(labelText: '填充方式'),
          items: const [
            DropdownMenuItem(value: 'cover', child: Text('裁剪填满 cover')),
            DropdownMenuItem(value: 'contain', child: Text('完整显示 contain')),
            DropdownMenuItem(value: 'fill', child: Text('拉伸铺满 fill')),
          ],
          onChanged: (value) {
            if (value == null) return;
            ctx.setDialogState(() => _fit = value);
          },
        ),
        const SizedBox(height: 12),
        ctx.numberField(_radius, '圆角'),
      ];

  @override
  void applyTo(Map<String, dynamic> props) {
    props['imageSource'] = _source;
    // 静态地址照常保存：作者切回「自定义」时不用重填。
    props['url'] = _url.text.trim();
    props['assetPath'] = _assetPath.text.trim();
    props['fit'] = _fit;
    props['borderRadius'] =
        (double.tryParse(_radius.text.trim()) ?? 8.0).clamp(0.0, 999.0).toDouble();
  }

  @override
  List<ChangeNotifier> get disposables => [_url, _assetPath, _radius];
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
      case 'progress':
        return ProgressFieldGroup(module);
      case 'slider':
        return SliderFieldGroup(module);
      case 'button':
        return ButtonFieldGroup(module);
      case 'input':
        return InputFieldGroup(module);
      case 'select':
        return SelectFieldGroup(module);
      case 'message_flow':
        return MessageFlowFieldGroup(module);
      case 'image':
        return ImageFieldGroup(module);
      default:
        return null;
    }
  }
}
