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

  Rect _backButtonRect(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Rect.fromLTWH(
      4,
      top + 2,
      58,
      kToolbarHeight,
    );
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 子页面允许系统返回键返回上一页。
      // 这只是页面导航，不代表关闭教程模式。
      canPop: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_showGuide)
            Positioned.fill(
              child: PageGuideOverlay(
                title: '${widget.pageName}导览',
                hint: '${widget.pageDescription}\n\n'
                    '点击高亮返回按钮或系统返回键可返回上一页；顶部“退出”才会结束教程。',
                targets: _targets(context),
                onExit: _exitGuide,
              ),
            ),
        ],
      ),
    );
  }
}