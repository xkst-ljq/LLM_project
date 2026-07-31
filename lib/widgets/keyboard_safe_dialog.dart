import 'package:flutter/material.dart';

/// 弹出一个「关闭前先收起键盘」的对话框。
///
/// ## 为什么需要它
///
/// 带 `TextField(autofocus: true)` 的 `AlertDialog` 如果在**输入法仍持有
/// 焦点**时被 pop，会抛：
///
/// ```
/// Duplicate GlobalKeys detected in widget tree.
/// - [LabeledGlobalKey<_OverlayEntryWidgetState>#...]
/// The specific parent that did not update ... *Theater(skipCount: 4 ...)
/// ```
///
/// 成因：输入法的候选栏 / 放大镜等是挂在 `Overlay`（`Theater`）上的
/// `OverlayEntry`，每个带 `GlobalKey`。对话框被移除时，如果焦点还在
/// TextField 上，框架会在同一帧里既销毁对话框、又试图把这些 OverlayEntry
/// 重新挂载到新位置，于是同一个 GlobalKey 在一帧内出现两次。
///
/// 用户触发路径：**改图层名时不点输入法的「确认」，直接点对话框按钮 /
/// 点遮罩 / 按返回键**。
///
/// ## 三次迭代才找对时机（务必读完再改）
///
/// **① 在每个按钮里 `unfocus()` + `await Future.delayed(16ms)`** —— 两个洞：
///    点遮罩（`barrierDismissible`）、系统返回键、输入法自带的「完成」
///    全都绕过按钮；且 16ms 只有一帧，键盘收起动画是 200~300ms。
///
/// **② 在 host 的 `dispose()` 里 `FocusScope.of(context).unfocus()`** ——
///    `of()` 走 `dependOnInheritedWidgetOfExactType` 会注册依赖，
///    而此刻元素正被停用，触发
///    `'_dependents.isEmpty': is not true`。
///
/// **③（当前）监听路由退场动画，在动画**刚开始**时 unfocus** ——
///    这才是正确时机：它发生在 widget 树拆除**之前**，
///    既不碰 teardown 期的 context，又天然覆盖所有退出路径
///    （按钮 / 遮罩 / 返回键 / 输入法完成都会驱动同一个退场动画）。
///
/// ## 关于 controller 的销毁
///
/// **不要**在 `await showDialog(...)` 返回后立刻 `controller.dispose()`。
/// future 在 pop 的那一刻就完成了，但退场动画还要跑 ~150ms，
/// 期间 TextField 仍在重建，于是抛
/// `A TextEditingController was used after being disposed`
/// （并连锁引发 `attached: is not true` 和 `_dependents.isEmpty`）。
///
/// 把 controller 交给 [disposables]，由 host 在自己的 `dispose` 里销毁——
/// 那时路由已彻底移除，不会再有人用它。
///
/// ## 用法
///
/// ```dart
/// final controller = TextEditingController(text: page.name);
/// final result = await showKeyboardSafeDialog<String>(
///   context: context,
///   disposables: [controller],   // ← 不要自己 dispose
///   builder: (ctx) => AlertDialog(...),
/// );
/// ```
Future<T?> showKeyboardSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  List<ChangeNotifier> disposables = const <ChangeNotifier>[],
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _KeyboardSafeDialogHost(
      disposables: disposables,
      child: Builder(builder: builder),
    ),
  );
}

/// 在路由开始退场时收起键盘，并在彻底销毁后释放 controller。
class _KeyboardSafeDialogHost extends StatefulWidget {
  const _KeyboardSafeDialogHost({
    required this.child,
    required this.disposables,
  });

  final Widget child;
  final List<ChangeNotifier> disposables;

  @override
  State<_KeyboardSafeDialogHost> createState() =>
      _KeyboardSafeDialogHostState();
}

class _KeyboardSafeDialogHostState extends State<_KeyboardSafeDialogHost> {
  Animation<double>? _routeAnimation;
  bool _unfocused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里取路由是安全的——didChangeDependencies 正是允许建立
    // InheritedWidget 依赖的时机（dispose 里则会触发断言，见类文档 ②）。
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    _routeAnimation = animation;
    _routeAnimation?.addStatusListener(_handleRouteStatus);
  }

  /// 退场动画一开始就收键盘。
  ///
  /// 此时 widget 树还完好，unfocus 引发的重建是正常的一帧，
  /// 不会和「正在拆除」的状态打架。
  void _handleRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.reverse || _unfocused) return;
    _unfocused = true;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    // 到这里路由已彻底移除，没有人会再用这些 controller 了。
    for (final item in widget.disposables) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
