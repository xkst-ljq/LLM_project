import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 应用内自绘标题栏：可拖动移动窗口 + 最小化 / 最大化 / 关闭。
///
/// 用法：放进 Scaffold 的 body 顶部（配合系统标题栏已隐藏）。
class AppTitleBar extends StatelessWidget {
  /// 标题文字。
  final String title;

  /// 左侧自定义内容（如返回按钮）；为空则显示应用图标。
  final Widget? leading;

  const AppTitleBar({super.key, this.title = 'LLM 角色卡转换工具', this.leading});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (leading != null)
            leading!
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.transform, size: 18),
            ),
          // 中间可拖动区域
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
          _WinButton(
            icon: Icons.remove,
            onTap: () => windowManager.minimize(),
          ),
          _WinButton(
            icon: Icons.crop_square,
            iconSize: 14,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
          ),
          _WinButton(
            icon: Icons.close,
            hoverColor: Colors.red,
            hoverIconColor: Colors.white,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color? hoverColor;
  final Color? hoverIconColor;

  const _WinButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
    this.hoverColor,
    this.hoverIconColor,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hovering = _hover;
    final bg = hovering
        ? (widget.hoverColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest)
        : Colors.transparent;
    final iconColor = hovering && widget.hoverIconColor != null
        ? widget.hoverIconColor
        : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
        ),
      ),
    );
  }
}
