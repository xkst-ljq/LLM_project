import 'package:flutter/material.dart';

import 'background_library_page.dart';
import 'character_library_page.dart';
import 'chat_page.dart';
import 'world_book_library_page.dart';

class TutorialHomePage extends StatelessWidget {
  final VoidCallback? onStartNewUserGuide;
  final VoidCallback? onStartSettingsGuide;

  const TutorialHomePage({
    super.key,
    this.onStartNewUserGuide,
    this.onStartSettingsGuide,
  });

  void _startHomeGuide(BuildContext context) {
    if (onStartNewUserGuide == null) return;
    Navigator.pop(context);
    onStartNewUserGuide!();
  }

  void _startSettingsGuide(BuildContext context) {
    if (onStartSettingsGuide == null) return;
    Navigator.pop(context);
    onStartSettingsGuide!();
  }

  void _pushGuidePage(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _openArticle(BuildContext context, _EncyclopediaArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EncyclopediaArticlePage(article: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeEnabled = onStartNewUserGuide != null;
    final settingsEnabled = onStartSettingsGuide != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('教程与导览'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.route_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '推荐路线',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '新用户快速导览会按推荐顺序介绍主页、设置页和常用功能入口。你也可以在下面单独打开某个页面导览。',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: routeEnabled ? () => _startHomeGuide(context) : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始新用户快速导览'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('页面导览'),
          _GuidePageTile(
            icon: Icons.home_outlined,
            title: '主页导览',
            subtitle: '聊天、角色库、世界书库、背景图库和侧滑设置页。',
            enabled: routeEnabled,
            onTap: routeEnabled ? () => _startHomeGuide(context) : null,
          ),
          _GuidePageTile(
            icon: Icons.settings_outlined,
            title: '设置页导览',
            subtitle: 'API 配置、用户设定、Prompt 策略、备份和教程入口。',
            enabled: settingsEnabled,
            onTap: settingsEnabled ? () => _startSettingsGuide(context) : null,
          ),
          _GuidePageTile(
            icon: Icons.people_outline,
            title: '角色库导览',
            subtitle: '角色卡片、排序、导出、新建/导入和进入聊天。',
            onTap: () => _pushGuidePage(
              context,
              const CharacterLibraryPage(startGuide: true),
            ),
          ),
          _GuidePageTile(
            icon: Icons.auto_stories_outlined,
            title: '世界书库导览',
            subtitle: '世界书卡片、排序、新建/导入、长按操作。',
            onTap: () => _pushGuidePage(
              context,
              const WorldBookLibraryPage(startGuide: true),
            ),
          ),
          _GuidePageTile(
            icon: Icons.image_outlined,
            title: '背景图库导览',
            subtitle: '背景卡片、排序、新建/导入、长按操作。',
            onTap: () => _pushGuidePage(
              context,
              const BackgroundLibraryPage(startGuide: true),
            ),
          ),
          _GuidePageTile(
            icon: Icons.chat_outlined,
            title: '聊天页导览',
            subtitle: '聊天设置侧滑入口、角色名称说明和输入发送说明。',
            onTap: () => _pushGuidePage(
              context,
              const ChatPage(startGuide: true),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('功能百科'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '百科用于解释概念和使用建议；具体怎么操作请看上面的页面导览。',
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
            ),
          ),
          for (final entry in _groupArticles(_encyclopediaArticles).entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final article in entry.value)
              _ArticleTile(
                article: article,
                onTap: () => _openArticle(context, article),
              ),
          ],
          const SizedBox(height: 24),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GuidePageTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _GuidePageTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.play_circle_outline)
            : const Text('待加入', style: TextStyle(fontSize: 12)),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  final _EncyclopediaArticle article;
  final VoidCallback onTap;

  const _ArticleTile({
    required this.article,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(article.title),
        subtitle: Text(article.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EncyclopediaArticlePage extends StatelessWidget {
  final _EncyclopediaArticle article;

  const _EncyclopediaArticlePage({required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(article.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            article.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            article.subtitle,
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const Divider(height: 28),
          Text(
            article.content,
            style: const TextStyle(fontSize: 15, height: 1.65),
          ),
        ],
      ),
    );
  }
}

class _EncyclopediaArticle {
  final String category;
  final String title;
  final String subtitle;
  final String content;

  const _EncyclopediaArticle({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.content,
  });
}

Map<String, List<_EncyclopediaArticle>> _groupArticles(
  List<_EncyclopediaArticle> articles,
) {
  final result = <String, List<_EncyclopediaArticle>>{};
  for (final article in articles) {
    result.putIfAbsent(article.category, () => <_EncyclopediaArticle>[]);
    result[article.category]!.add(article);
  }
  return result;
}

const _encyclopediaArticles = <_EncyclopediaArticle>[
  _EncyclopediaArticle(
    category: '基础概念',
    title: 'LLM Project 是什么',
    subtitle: '本地 LLM 角色聊天工具，不提供官方社区或内容服务器。',
    content: '''LLM Project 是一个本地角色聊天 App。

它的定位是“本地工具 + 资产导入导出”，而不是官方内容社区。应用本身不提供官方角色市场、内容服务器或在线审核服务。

你可以在本地创建角色、世界书、背景和用户设定，也可以导入或导出 LLM Project 自己的资产格式。聊天时需要你自己配置可用的 API 服务。''',
  ),
  _EncyclopediaArticle(
    category: '基础概念',
    title: '第一次使用的推荐顺序',
    subtitle: '先配置 API，再创建或导入角色，最后进入聊天。',
    content: '''第一次使用建议按这个顺序：

1. 打开设置页，进入 API 配置。
2. 新增 API 配置，填写 Base URL、API Key 和模型。
3. 返回主页，进入角色库。
4. 新建角色或导入角色卡。
5. 返回主页，进入聊天页开始对话。

如果你只是想熟悉界面，可以先看页面导览，不需要一次学完所有功能。''',
  ),
  _EncyclopediaArticle(
    category: '角色系统',
    title: '人物卡和系统卡有什么区别',
    subtitle: '人物卡描述角色是谁，系统卡描述更底层的规则。',
    content: '''人物卡主要描述“这个角色是谁”，适合填写姓名、身份、外貌、性格、经历、关系和说话方式。

系统卡更适合放底层规则，例如扮演要求、回复格式、世界规则、主角设定或长期约束。

简单建议：

和角色本人有关的内容放人物卡。
和模型行为规则、世界规则有关的内容放系统卡或 Prompt 策略。''',
  ),
  _EncyclopediaArticle(
    category: '角色系统',
    title: '开场白是什么',
    subtitle: '角色第一次进入聊天时自动出现的起始消息。',
    content: '''开场白用于给聊天一个起点。

一个角色可以有多个开场白。新聊天没有历史记录时，应用会插入开场白作为第一条角色消息。

开场白适合写当前场景、角色第一句话、两人关系的初始状态。不要把所有角色设定都塞进开场白，长期设定更适合放在人物卡、系统卡或世界书中。''',
  ),
  _EncyclopediaArticle(
    category: 'API',
    title: 'API Key、Base URL 和模型名是什么',
    subtitle: '配置模型服务时最常见的三个字段。',
    content: '''API Key 是服务商给你的调用密钥，相当于密码，不要分享给别人。

Base URL 是服务商的接口地址，通常可以在服务商文档中找到。

模型名是你要调用的具体模型，例如 deepseek-chat 或其他服务商提供的模型名称。

如果测试连接失败，优先检查 API Key 是否正确、Base URL 是否完整、账号是否有余额或模型权限。''',
  ),
  _EncyclopediaArticle(
    category: '世界书',
    title: '世界书是什么',
    subtitle: '用于保存背景设定、地点、组织、术语等资料。',
    content: '''世界书适合保存不会一直写在聊天里的背景资料，例如世界观、地点、组织、术语、道具、长期剧情信息。

世界书条目通常通过关键词触发。当最近聊天内容命中关键词时，对应条目会加入 Prompt，帮助模型记起相关设定。

建议一个条目只写一个主题，关键词不要过多，内容尽量清晰。''',
  ),
  _EncyclopediaArticle(
    category: 'Prompt',
    title: 'Prompt 策略是什么',
    subtitle: '控制系统提示词如何组织和注入。',
    content: '''Prompt 策略用于控制最终发送给模型的系统提示结构。

设置页中的 Prompt 策略是全局默认策略。所有没有单独设置的角色都会使用它。

聊天页里的 Prompt 策略可以为当前角色启用单独策略。只有特殊角色需要特殊规则时，才建议开启角色单独策略。''',
  ),
  _EncyclopediaArticle(
    category: '资产与备份',
    title: '导入导出和备份有什么区别',
    subtitle: '资产导入导出用于单个内容迁移，备份用于整体数据迁移。',
    content: '''角色卡、世界书、背景卡的导入导出，适合迁移或分享单个资产。

备份与恢复适合迁移整个应用数据，例如换手机、重装应用或升级前保存当前状态。

导入大量资产或恢复备份前，建议先导出一次完整备份，避免误操作导致数据丢失。''',
  ),
  _EncyclopediaArticle(
    category: '常见问题',
    title: 'API 不回复怎么办',
    subtitle: '按 API Key、Base URL、模型权限和网络顺序排查。',
    content: '''如果发送消息后没有回复，可以按顺序检查：

1. API 配置是否已保存。
2. API Key 是否正确。
3. Base URL 是否符合服务商文档。
4. 模型名是否存在，账号是否有权限。
5. 服务商账号是否有余额或额度。
6. 网络是否可以访问对应服务商。

如果只有某个模型失败，可以换一个模型测试。''',
  ),
  _EncyclopediaArticle(
    category: '常见问题',
    title: '为什么角色没有按设定说话',
    subtitle: '通常和设定不清晰、上下文过长或 Prompt 冲突有关。',
    content: '''角色表现不稳定时，可以检查：

1. 人物卡是否写清楚身份、性格、关系和说话方式。
2. 系统卡或 Prompt 策略是否有冲突规则。
3. 世界书关键词是否真的被触发。
4. 聊天上下文是否过长，重要设定是否被稀释。
5. 当前使用的模型是否擅长角色扮演。

建议先查看聊天页的 Prompt 预览，确认最终 System Prompt 中是否包含你期望的设定。''',
  ),
];
