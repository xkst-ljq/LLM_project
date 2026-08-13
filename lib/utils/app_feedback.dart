import 'dart:async';

import 'package:flutter/material.dart';

/// 统一的轻提示工具。
///
/// `showSnack` / `showSuccessSnack` 用「顶层 Overlay 半透明胶囊气泡」呈现：
/// 细长、文字居中、显示在其它所有界面之上（最优先、不会被遮挡），
/// 带淡入淡出，避免一闪而过看不清。颜色随主题令牌（深浅自动适配）。
class AppFeedback {
  /// 上一次提示的 Overlay 入口，用于收起旧的再显示新的（避免叠堆）。
  static OverlayEntry? _activeToast;

  static void showSnack(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    bool success = false,
  }) {
    _showToast(context, message, duration: duration, success: success);
  }

  static void showSuccessSnack(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _showToast(context, message, duration: duration, success: true);
  }

  /// 顶层半透明胶囊气泡。
  static void _showToast(
    BuildContext context,
    String message, {
    required Duration duration,
    bool success = false,
  }) {
    final overlay = Overlay.of(context);

    // 收起上一次的提示，保证「顶层最优先」只显示最新一条。
    _activeToast?.remove();

    // 用半透明玻璃色：跟随当前主题（深浅自动）。
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final bg = (success ? const Color(0xFF3FC6C2) : const Color(0xFF3A4158))
        .withValues(alpha: 0.86);
    final fg = Colors.white;

    final entry = OverlayEntry(
      builder: (_) => _ToastBubble(
        message: message,
        bg: bg,
        fg: fg,
        onDismissed: () {
          if (identical(_activeToast, entry)) _activeToast = null;
        },
      ),
    );
    _activeToast = entry;
    overlay.insert(entry);

    Timer(duration, () {
      if (identical(_activeToast, entry)) _activeToast = null;
      entry.remove();
    });
  }

  static Future<void> showErrorDialog(
      BuildContext context, {
        required String title,
        required Object error,
        String? message,
        String? suggestion,
      }) {
    final errorText = error.toString();

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null && message.trim().isNotEmpty) ...[
                Text(message),
                const SizedBox(height: 12),
              ],
              const Text(
                '错误详情：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SelectableText(
                errorText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
              ),
              if (suggestion != null && suggestion.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '建议：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  suggestion,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 顶层细长半透明气泡。淡入淡出，文字居中，贴底部安全区上方。
class _ToastBubble extends StatefulWidget {
  final String message;
  final Color bg;
  final Color fg;
  final VoidCallback onDismissed;

  const _ToastBubble({
    required this.message,
    required this.bg,
    required this.fg,
    required this.onDismissed,
  });

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().whenComplete(() {
      widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom + 32,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.bg,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.fg,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}