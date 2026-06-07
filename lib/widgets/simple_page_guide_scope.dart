import 'package:flutter/material.dart';

import 'page_guide_overlay.dart';

class SimplePageGuideScope extends StatefulWidget {
  final bool startGuide;
  final String pageName;
  final String pageDescription;
  final Widget child;
  final VoidCallback? onExitGuide;

  const SimplePageGuideScope({
    super.key,
    required this.startGuide,
    required this.pageName,
    required this.pageDescription,
    required this.child,
    this.onExitGuide,
  });

  @override
  State<SimplePageGuideScope> createState() => _SimplePageGuideScopeState();
}

class _SimplePageGuideScopeState extends State<SimplePageGuideScope> {
  late bool _showGuide;

  @override
  void initState() {
    super.initState();
    _showGuide = widget.startGuide;
  }

  @override
  void didUpdateWidget(covariant SimplePageGuideScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.startGuide && widget.startGuide) {
      _showGuide = true;
    }
  }

  void _exitGuide() {
    setState(() {
      _showGuide = false;
    });
    widget.onExitGuide?.call();
  }

  void _showBackBlockedTip() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('教程模式中，请使用高亮的返回按钮，或点击顶部“退出”结束教程。'),
      ),
    );
  }

  Rect _backButtonRect(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Rect.fromLTWH(6, top + 2, 56, kToolbarHeight);
  }

  Rect _pageInfoRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top;
    return Rect.fromLTWH(76, top + 14, size.width - 152, 32);
  }

  List<PageGuideTarget> _targets(BuildContext context) {
    return [
      PageGuideTarget(
        id: 'page_back',
        order: 1,
        rect: _backButtonRect(context),
        title: '返回上一页',
        description: '点击这里返回上一页。返回只会切换页面，不会关闭教程模式。',
        actionLabel: '返回上一页',
        onAction: () => Navigator.of(context).maybePop(),
      ),
      PageGuideTarget(
        id: 'page_info',
        order: 2,
        rect: _pageInfoRect(context),
        title: widget.pageName,
        description: widget.pageDescription,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showGuide,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_showGuide) _showBackBlockedTip();
      },
      child: Stack(
        children: [
          widget.child,
          if (_showGuide)
            PageGuideOverlay(
              title: '${widget.pageName}导览',
              hint: '点击高光区域执行对应操作；点击紫色编号展开说明。教程模式只能通过顶部“退出”关闭。',
              targets: _targets(context),
              onExit: _exitGuide,
            ),
        ],
      ),
    );
  }
}
