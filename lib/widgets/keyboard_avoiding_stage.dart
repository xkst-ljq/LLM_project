import 'package:flutter/material.dart';

/// 键盘弹出时给全屏 UI「接一段可上翻的空白」。
///
/// ## 为什么需要它
///
/// 全屏运行时 UI（scene / opening）的输入框可能摆在页面很靠下的位置，
/// 键盘弹出后就被盖住。此前试过两种做法，都不行：
///
/// 1. **让 Scaffold 收缩**（`resizeToAvoidBottomInset: true`）——
///    `UIAssemblyRuntimeView` 按可用高度算 `safeContainScale` 等比缩放
///    整张 PCB，可用高度一变，作者摆好的界面在打字时整体缩小。
/// 2. **把高度补回去**（`bottom: -keyboardInset`）——
///    界面确实不缩了，但输入框依旧被键盘盖住，等于没解决。
///
/// 症结在于：**改变可用尺寸必然触发 PCB 重算缩放**。
///
/// ## 这里的做法
///
/// 给舞台保持**原始尺寸**（缩放完全不变），只在键盘弹出时把它整体
/// 向上平移。等价于在屏幕下方接了一段与键盘等高的空白渲染区，
/// 而当前视口在这条更长的「卷轴」上滑动。
///
/// - 自动平移到刚好让焦点组件露出键盘上沿，不多推一像素；
/// - 平移期间玩家可以**用手指上下拖动**微调，就像翻卷轴一样；
/// - 键盘收起后自动归位。
///
/// 平移不改变布局约束，所以 `LayoutBuilder` 拿到的 constraints 恒定，
/// PCB 的 `safeContainScale` 自始至终不变——这正是我们要的。
class KeyboardAvoidingStage extends StatefulWidget {
  const KeyboardAvoidingStage({
    super.key,
    required this.child,
    required this.stageHeight,
    required this.keyboardInset,
    this.enabled = true,
  });

  /// 被平移的内容（通常是整个 scene / opening 层）。
  final Widget child;

  /// 舞台的原始高度。平移不改变它，只改变它的绘制位置。
  final double stageHeight;

  /// 真实键盘高度，由调用方在 **Scaffold 之外**取得后传入。
  ///
  /// 不能在本组件内部读 `MediaQuery.viewInsetsOf`：聊天页的 Scaffold
  /// 是默认的 `resizeToAvoidBottomInset: true`，它会消费掉 viewInsets，
  /// body 内部读到的恒为 0，导致整个避让逻辑静默失效。
  final double keyboardInset;

  /// 关掉后完全不介入（保持原样，便于出问题时快速回退）。
  final bool enabled;

  @override
  State<KeyboardAvoidingStage> createState() => _KeyboardAvoidingStageState();
}

class _KeyboardAvoidingStageState extends State<KeyboardAvoidingStage>
    with SingleTickerProviderStateMixin {
  /// 当前平移量（正值 = 向上移动的像素数）。
  double _offset = 0.0;

  /// 玩家手动拖动产生的额外偏移，叠加在自动偏移之上。
  /// 键盘收起时清零。
  double _manualOffset = 0.0;

  /// 上一次看到的键盘高度，用来识别「键盘刚弹出 / 刚收起」。
  double _lastInset = 0.0;

  /// 自动平移的动画。手动拖动期间不跑动画（要跟手）。
  late final AnimationController _anim;
  Animation<double>? _tween;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      // 与主流系统键盘的弹出时长接近，观感上是「界面跟着键盘一起走」。
      duration: const Duration(milliseconds: 250),
    );
    _anim.addListener(() {
      final t = _tween;
      if (t == null) return;
      setState(() => _offset = t.value);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KeyboardAvoidingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncToInset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncToInset();
  }

  /// 键盘高度变化时重新计算目标平移量。
  void _syncToInset() {
    if (!widget.enabled) return;

    final inset = widget.keyboardInset;
    if ((inset - _lastInset).abs() < 1.0) return;

    final opening = inset > _lastInset;
    _lastInset = inset;

    if (!opening && inset <= 0) {
      // 键盘收起：连同手动偏移一起归零。
      _manualOffset = 0.0;
      _animateTo(0.0);
      return;
    }

    // 键盘弹出 / 高度变化：等这一帧布局完成后再量焦点位置，
    // 此刻 viewInsets 已更新但焦点组件的 RenderBox 还没重排完。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateTo(_desiredOffsetFor(inset));
    });
  }

  /// 算出「刚好让焦点组件露出键盘」所需的平移量。
  ///
  /// 找不到焦点组件时回退为 0——宁可不动，也不要在玩家没聚焦
  /// 任何输入框时无缘无故把界面推上去。
  double _desiredOffsetFor(double inset) {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return 0.0;

    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0.0;

    // localToGlobal 得到的是**当前已平移之后**的屏幕坐标。
    // 加回 _offset + _manualOffset 还原成未平移时的位置，
    // 否则第二次计算会把已经推上去的量又算一遍（越推越多）。
    final topLeft = box.localToGlobal(Offset.zero);
    final fieldBottom =
        topLeft.dy + box.size.height + _offset + _manualOffset;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardTop = screenHeight - inset;

    // 留一点余量，别让输入框正好贴着键盘边缘。
    const gap = 16.0;
    final overlap = fieldBottom + gap - keyboardTop;
    if (overlap <= 0) return 0.0;

    // 不允许推过头：最多推到「舞台底部与键盘顶部齐平」。
    // 否则输入框在页面极靠下时会把整个界面顶出屏幕。
    final maxShift = inset;
    return overlap.clamp(0.0, maxShift).toDouble();
  }

  void _animateTo(double target) {
    if ((target - _offset).abs() < 0.5) return;
    _tween = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _anim.forward(from: 0.0);
  }

  /// 手动拖动的允许范围：0 ~ 键盘高度。
  /// 上界就是那段「多接出来的空白」的高度。
  double get _maxManual => widget.keyboardInset;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final total = (_offset + _manualOffset).clamp(0.0, _maxManual + 0.0);

    return GestureDetector(
      // deferToChild：输入框、按钮等子组件优先拿到手势，
      // 只有落在空白处的竖直拖动才由这里接管。
      behavior: HitTestBehavior.deferToChild,
      // 只在键盘弹出时才接管竖直拖动。键盘没弹出时这几个回调为 null，
      // 完全不参与手势竞技场，不会干扰 PCB 自己的翻页手势
      // （PCB 翻页走 Listener，本就不参与竞技场；但消息流的滚动
      //  走的是竞技场，这里不加判断会把它抢走）。
      onVerticalDragStart:
          widget.keyboardInset > 0 ? (_) => _dragging = true : null,
      onVerticalDragUpdate: widget.keyboardInset > 0
          ? (d) {
              if (!_dragging) return;
              setState(() {
                // 向上拖 delta.dy 为负，对应偏移增大。
                _manualOffset = (_manualOffset - d.delta.dy)
                    .clamp(-_offset, _maxManual - _offset)
                    .toDouble();
              });
            }
          : null,
      onVerticalDragEnd:
          widget.keyboardInset > 0 ? (_) => _dragging = false : null,
      child: Transform.translate(
        offset: Offset(0, -total),
        child: SizedBox(
          height: widget.stageHeight,
          child: widget.child,
        ),
      ),
    );
  }
}
