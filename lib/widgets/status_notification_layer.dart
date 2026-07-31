import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ui_engine/status_notification.dart';

/// 状态变化通知层：顶部浮窗 + 居中弹窗。
///
/// 挂在聊天页 Stack 的最上层。两种形态的分工：
///
/// | | 弹窗 | 浮窗 |
/// |---|---|---|
/// | 代价 | 打断节奏，必须手动关 | 可能没看到就消失了 |
/// | 适合 | 玩家需要据此做决策（升级去加点） | 知道就行（好感 +2） |
///
/// scene 模式下浮窗照常走顶部（用户确认：盖住就盖住，几秒就没了）。
class StatusNotificationLayer extends StatefulWidget {
  const StatusNotificationLayer({
    super.key,
    required this.queue,
    this.toastDuration = const Duration(milliseconds: 2500),
    this.topInset = 0,
  });

  final StatusNotificationQueue queue;

  /// 单条浮窗的停留时长。
  ///
  /// 2.5 秒：太短来不及读，太长会让「满 5 个」频繁触发。
  final Duration toastDuration;

  /// 顶部额外留白，通常传状态栏高度。
  final double topInset;

  @override
  State<StatusNotificationLayer> createState() =>
      _StatusNotificationLayerState();
}

class _StatusNotificationLayerState extends State<StatusNotificationLayer> {
  /// 每条浮窗各自的自消定时器。
  ///
  /// 必须一条一个：共用一个定时器的话，后来的浮窗会把前面那条的
  /// 剩余时间重置，最早那条永远不消失，队列就卡死了。
  final Map<StatusNotification, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_onQueueChanged);
    _syncTimers();
  }

  @override
  void didUpdateWidget(StatusNotificationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue) {
      oldWidget.queue.removeListener(_onQueueChanged);
      widget.queue.addListener(_onQueueChanged);
      _syncTimers();
    }
  }

  @override
  void dispose() {
    widget.queue.removeListener(_onQueueChanged);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  void _onQueueChanged() {
    if (!mounted) return;
    _syncTimers();
    setState(() {});
  }

  /// 给新上屏的浮窗装定时器，给已下屏的清定时器。
  void _syncTimers() {
    final visible = widget.queue.visibleToasts.toSet();

    // 清理已经不在屏上的。
    final stale = _timers.keys.where((k) => !visible.contains(k)).toList();
    for (final key in stale) {
      _timers.remove(key)?.cancel();
    }

    for (final item in visible) {
      if (_timers.containsKey(item)) continue;
      _timers[item] = Timer(widget.toastDuration, () {
        if (!mounted) return;
        widget.queue.dismissToast(item);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialog = widget.queue.currentDialog;
    final toasts = widget.queue.visibleToasts;

    return Positioned.fill(
      child: IgnorePointer(
        // 没有弹窗时整层不拦触摸：浮窗只是提示，
        // 拦下点击会让玩家以为界面卡住了。
        ignoring: dialog == null,
        child: Stack(
          children: [
            if (toasts.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: widget.topInset + 10,
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    // 最旧的在列表头 → 渲染在最上面；
                    // 新的追加在末尾、排在下方，视觉上就是
                    // 「新浮窗把旧的向上顶」。
                    children: [
                      for (final item in toasts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _ToastCard(item: item),
                        ),
                    ],
                  ),
                ),
              ),
            if (dialog != null)
              Positioned.fill(
                child: _NotificationDialog(
                  item: dialog,
                  remaining: widget.queue.pendingDialogCount - 1,
                  onDismiss: widget.queue.dismissCurrentDialog,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.item});

  final StatusNotification item;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(item),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -10 * (1 - t)), child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B33).withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10)],
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 15, color: Color(0xFF7FD8C8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDialog extends StatelessWidget {
  const _NotificationDialog({
    required this.item,
    required this.remaining,
    required this.onDismiss,
  });

  final StatusNotification item;

  /// 后面还堆着几条。> 0 时按钮文案改为「下一条」，
  /// 让玩家知道还没完，不会以为点完就结束了。
  final int remaining;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.42),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(item),
        tween: Tween(begin: 0.94, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, t, child) =>
            Transform.scale(scale: t, child: child),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 24),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.trending_up_rounded,
                    size: 22, color: Color(0xFF00897B)),
              ),
              const SizedBox(height: 12),
              Text(
                item.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111116),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              // 自定义文案可能只写了「恭喜升级」，看不出具体数值，
              // 这行始终保留变化明细。
              Text(
                '${item.label} · ${item.changeDetail}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF888896),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    remaining > 0 ? '下一条（还有 $remaining 条）' : '知道了',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
