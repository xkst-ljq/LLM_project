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
/// ## 为什么不在按钮里各贴一次 unfocus
///
/// 那是原先的写法，有两个洞：
/// 1. **只覆盖了按钮**。点遮罩关闭（`barrierDismissible`）、系统返回键、
///    输入法自己的「完成」都绕过按钮，照样炸。
/// 2. **延迟给得不够**。原来是 `Future.delayed(16ms)`，只有一帧；
///    而键盘收起动画是 200~300ms，OverlayEntry 远没销毁完。
///
/// 正确做法是把「收焦点」放在**对话框自身的生命周期**里，覆盖所有出口。
///
/// ## 用法
///
/// 与 `showDialog` 同签名，直接替换即可：
/// ```dart
/// final result = await showKeyboardSafeDialog<String>(
///   context: context,
///   builder: (ctx) => AlertDialog(...),
/// );
/// ```
Future<T?> showKeyboardSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _KeyboardSafeDialogHost(child: Builder(builder: builder)),
  );
  return result;
}

/// 在自己被 dispose 时收起键盘。
///
/// 放在对话框内容**外面**一层：无论从哪个出口关闭（按钮 / 遮罩 /
/// 返回键 / 输入法完成），只要这棵子树被拆，`dispose` 必定执行。
class _KeyboardSafeDialogHost extends StatefulWidget {
  const _KeyboardSafeDialogHost({required this.child});

  final Widget child;

  @override
  State<_KeyboardSafeDialogHost> createState() =>
      _KeyboardSafeDialogHostState();
}

class _KeyboardSafeDialogHostState extends State<_KeyboardSafeDialogHost> {
  @override
  void dispose() {
    // 这里**不能** await——dispose 是同步的。
    //
    // 但也不需要 await：unfocus 会立刻把焦点摘掉，
    // 输入法的 OverlayEntry 随之进入销毁流程，
    // 不会再和正在拆除的对话框争抢同一个 GlobalKey。
    //
    // 用 `of(context)` 而非 `FocusManager.instance.primaryFocus`：
    // 后者可能已经指向对话框之外的节点（例如画布上原本的焦点），
    // 误摘会让用户回到页面后发现别处的输入框失焦了。
    FocusScope.of(context).unfocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
