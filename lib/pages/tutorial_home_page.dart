import 'package:flutter/material.dart';

import '../data/tutorial_content.dart';
import '../shared/theme/app_theme_tokens.dart';
import '../widgets/sub_page_backdrop.dart';
import '../widgets/surface_card.dart';
import '../widgets/walkthrough_viewer.dart';

class TutorialHomePage extends StatelessWidget {
  const TutorialHomePage({super.key});

  void _openWalkthrough(BuildContext context, String key) {
    final w = walkthroughForPage(key);
    if (w == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalkthroughViewer(walkthrough: w),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(title: const Text('教程与导览')),
      body: SubPageBackdrop(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PageIntroCard(tokens: tokens),
            const SizedBox(height: 20),
            const _SectionTitle('页面讲解'),
            const SizedBox(height: 8),
            for (final key in allTutorialKeys)
              _GuideTile(
                walkthrough: walkthroughForPage(key),
                onTap: () => _openWalkthrough(context, key),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 教程中心的页面顺序（与讲解数据一致）。
const List<String> allTutorialKeys = [
  TutorialPageKey.home,
  TutorialPageKey.settings,
  TutorialPageKey.characterLibrary,
  TutorialPageKey.characterEdit,
  TutorialPageKey.statusBarHighlight,
  TutorialPageKey.worldBookLibrary,
  TutorialPageKey.backgroundLibrary,
  TutorialPageKey.chat,
  TutorialPageKey.apiConfig,
  TutorialPageKey.userSettings,
  TutorialPageKey.promptSettings,
  TutorialPageKey.backupRestore,
  TutorialPageKey.uiStudio,
  TutorialPageKey.uiAssetGallery,
  TutorialPageKey.uiAssembly,
];

class _PageIntroCard extends StatelessWidget {
  final AppThemeTokens tokens;
  const _PageIntroCard({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, color: tokens.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                '图文讲解',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '按页面分步讲解每个功能的用法。点开任意一个页面，可以像翻书一样逐条阅读：上面是配图（后续版本补充），下面是详细说明，底部可上一步 / 下一步或左右滑动切换。',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GuideTile extends StatelessWidget {
  final Walkthrough? walkthrough;
  final VoidCallback onTap;
  const _GuideTile({required this.walkthrough, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final w = walkthrough;
    if (w == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          onTap: onTap,
          child: SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(w.icon, color: tokens.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.title,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        w.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: tokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
