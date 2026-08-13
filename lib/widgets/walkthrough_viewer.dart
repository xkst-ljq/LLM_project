import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';

/// 图文分步讲解的「一步」。
///
/// 每个功能 = 一个 [WalkthroughStep]：标题 + 详细说明 + 可选的配图。
/// [imageAsset] 是对应截图在 assets/tutorial/... 下的路径；图未放入项目时
/// 显示 [imageHint]（配图说明占位框），不影响文字讲解。
class WalkthroughStep {
  final String title;
  final String body;
  final String? imageAsset;
  final String? imageHint;

  const WalkthroughStep({
    required this.title,
    required this.body,
    this.imageAsset,
    this.imageHint,
  });
}

/// 一个页面的图文讲解：页面标题 + 图标 + 若干步。
class Walkthrough {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<WalkthroughStep> steps;

  const Walkthrough({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.steps,
  });
}

/// 图文分步讲解查看器。
///
/// 整页形式（适合作为 tutorial 中心 push 出来）：顶部标题栏带「完成/退出」，
/// 中部为可左右滑动的分步卡片（图片区 + 标题 + 可滚动正文），底部「上一步 /
/// 下一步」按钮与页码圆点。用主题令牌（玻璃卡片 + accent 高亮）统一风格。
class WalkthroughViewer extends StatefulWidget {
  final Walkthrough walkthrough;

  const WalkthroughViewer({super.key, required this.walkthrough});

  @override
  State<WalkthroughViewer> createState() => _WalkthroughViewerState();
}

class _WalkthroughViewerState extends State<WalkthroughViewer> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _count => widget.walkthrough.steps.length;

  void _goTo(int index) {
    final i = index.clamp(0, _count - 1);
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final w = widget.walkthrough;

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(w.icon, size: 20, color: tokens.accent),
            const SizedBox(width: 8),
            Text(w.title),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('完成', style: TextStyle(color: tokens.accent)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _count,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) =>
                  _StepCard(step: w.steps[i], index: i, total: _count),
            ),
          ),
          _buildBottomBar(tokens),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppThemeTokens tokens) {
    final isFirst = _page == 0;
    final isLast = _page == _count - 1;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border(top: BorderSide(color: tokens.outline.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            // 上一步
            Expanded(
              child: OutlinedButton(
                onPressed: isFirst ? null : () => _goTo(_page - 1),
                child: const Text('上一步'),
              ),
            ),
            // 页码圆点
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? tokens.accent
                            : tokens.outline.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            // 下一步 / 完成
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (isLast) {
                    Navigator.of(context).pop();
                  } else {
                    _goTo(_page + 1);
                  }
                },
                child: Text(isLast ? '完成' : '下一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单步卡片：顶部配图区（或配图占位）+ 标题 + 可滚动正文。
class _StepCard extends StatelessWidget {
  final WalkthroughStep step;
  final int index;
  final int total;

  const _StepCard({
    required this.step,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final hasImage = step.imageAsset != null && step.imageAsset!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 步数徽标
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${index + 1} / $total',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 配图区 / 占位
          _buildImageArea(tokens, hasImage),
          const SizedBox(height: 16),

          // 标题
          Text(
            step.title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),

          // 正文
          Text(
            step.body,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 15,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildImageArea(AppThemeTokens tokens, bool hasImage) {
    final aspect = 16 / 10;
    if (hasImage) {
      return AspectRatio(
        aspectRatio: aspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Image.asset(
            step.imageAsset!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _buildPlaceholder(tokens),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: aspect,
      child: _buildPlaceholder(tokens),
    );
  }

  Widget _buildPlaceholder(AppThemeTokens tokens) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.outline.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 40, color: tokens.textMuted),
          const SizedBox(height: 8),
          Text(
            '配图占位',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (step.imageHint != null && step.imageHint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              step.imageHint!,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
