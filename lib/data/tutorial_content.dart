import 'package:flutter/material.dart';

import '../widgets/walkthrough_viewer.dart';

/// 所有页面的图文讲解内容集中定义于此。
///
/// 每个页面一个 [Walkthrough]，覆盖该页面的全部功能。文本讲解先做（1.2.7），
/// 配图在后续版本（1.2.8）补：给对应 [WalkthroughStep.imageAsset] 填上
/// `assets/tutorial/<页面>/<步骤>.png` 的路径，并在 pubspec 注册 assets 目录即可。
///
/// 条目通过 [allWalkthroughs]（有序）与 [walkthroughForPage]（按 key 查）暴露，
/// 供「教程与导览」中心按页面列出并打开。
class TutorialPageKey {
  static const home = 'home';
  static const settings = 'settings';
  static const characterLibrary = 'character_library';
  static const worldBookLibrary = 'world_book_library';
  static const backgroundLibrary = 'background_library';
  static const chat = 'chat';
  static const apiConfig = 'api_config';
  static const userSettings = 'user_settings';
  static const promptSettings = 'prompt_settings';
  static const backupRestore = 'backup_restore';
}

/// 有序的页面讲解列表（顺序即教程中心的展示顺序）。
final List<Walkthrough> allWalkthroughs = [
  _home,
  _settings,
  _characterLibrary,
  _worldBookLibrary,
  _backgroundLibrary,
  _chat,
  _apiConfig,
  _userSettings,
  _promptSettings,
  _backupRestore,
];

/// 页面 key → 讲解的映射。教程中心按 key 打开对应讲解。
final Map<String, Walkthrough> _byKey = {
  TutorialPageKey.home: _home,
  TutorialPageKey.settings: _settings,
  TutorialPageKey.characterLibrary: _characterLibrary,
  TutorialPageKey.worldBookLibrary: _worldBookLibrary,
  TutorialPageKey.backgroundLibrary: _backgroundLibrary,
  TutorialPageKey.chat: _chat,
  TutorialPageKey.apiConfig: _apiConfig,
  TutorialPageKey.userSettings: _userSettings,
  TutorialPageKey.promptSettings: _promptSettings,
  TutorialPageKey.backupRestore: _backupRestore,
};

/// 按页面 key 查询讲解；未找到返回 null。
Walkthrough? walkthroughForPage(String key) => _byKey[key];

const Walkthrough _home = Walkthrough(
  title: '主页',
  subtitle: '当前角色入口、角色切换、模块轨道与侧滑设置。',
  icon: Icons.home_outlined,
  steps: [
    WalkthroughStep(
      title: '主页是什么',
      body: '主页是应用的起点，围绕「当前角色」展开。\n\n'
          '主视觉是一张角色入口卡（当前聊天对象），下方是模块轨道（角色库、世界书库、背景图库、UI 模组库），右上角是主题切换。\n\n'
          '刚开始使用先进入设置页配置 API，再进入角色库新建或导入角色，然后回到主页进入聊天。',
      imageHint: '主页整体界面（角色入口卡 + 模块轨道）',
    ),
    WalkthroughStep(
      title: '当前角色入口卡',
      body: '主页正中是一张「当前角色」入口卡，显示角色名、简介和「继续体验 / 开始新体验」状态。\n\n'
          '点击卡片会进入角色选择层，用来切换当前聊天对象；点击卡片右下角的播放按钮会直接进入聊天页与当前角色对话。',
      imageHint: '主页角色入口卡 + 播放按钮',
    ),
    WalkthroughStep(
      title: '切换当前角色',
      body: '点击当前角色入口卡，会弹出角色选择层。\n\n'
          '卡片按「最近对话时间」固定排序（最近聊过的在最前）。可以左右滑动浏览，也可以直接点某张卡切换。\n\n'
          '选择后该角色会成为新的「当前角色」，入口卡随之更新。',
      imageHint: '角色选择层（卡片轨道）',
    ),
    WalkthroughStep(
      title: '模块轨道',
      body: '主页右下侧是模块轨道，包含四个入口：\n\n'
          '• 角色库：创建 / 导入 / 管理角色\n'
          '• 世界书库：管理背景设定资料\n'
          '• 背景图库：管理聊天 / 页面背景\n'
          '• UI 模组库：查看和复用复合 UI 组件\n\n'
          '点击任意模块即可进入对应页面。',
      imageHint: '主页模块轨道（四个入口）',
    ),
    WalkthroughStep(
      title: '侧滑打开设置页',
      body: '在主页按住右侧边缘的高光框向左滑动，可以打开设置页。\n\n'
          '设置页包含：API 配置、用户设定、Prompt 策略、备份与恢复、教程与导览、检查更新等入口。',
      imageHint: '主页侧滑高光框 / 设置页',
    ),
  ],
);

const Walkthrough _settings = Walkthrough(
  title: '设置页',
  subtitle: 'API 配置、用户设定、Prompt 策略、备份、教程、更新。',
  icon: Icons.settings_outlined,
  steps: [
    WalkthroughStep(
      title: '设置页概览',
      body: '设置页按功能分组：\n\n'
          '• 连接与数据：API 配置、备份与恢复\n'
          '• 角色与内容：用户设定、Prompt 策略\n'
          '• 外观与创作：UI 创作工作室、教程与导览\n'
          '• 关于：检查更新、关于\n\n'
          '从主页向右滑打开设置页，再次向右滑返回主页。',
      imageHint: '设置页整体分组',
    ),
    WalkthroughStep(
      title: 'API 配置',
      body: 'API 配置用于填写模型服务的地址与密钥，是聊天的前提。\n\n'
          '没有有效 API 配置时，聊天通常无法回复。首次使用建议先配置这里。',
      imageHint: 'API 配置入口',
    ),
    WalkthroughStep(
      title: '用户设定',
      body: '用户设定用于设置「你是谁」。角色会参考这些信息与你互动，例如你的昵称、头像和个人简介。\n\n'
          '新手可以先跳过，开始聊天后再补充。',
      imageHint: '用户设定页',
    ),
    WalkthroughStep(
      title: 'Prompt 策略',
      body: 'Prompt 策略控制最终发送给模型的系统提示结构，属于进阶功能。\n\n'
          '这里是全局默认策略，所有未单独设置的角色都会使用它。熟悉基础聊天后再调整更稳妥。',
      imageHint: 'Prompt 策略页',
    ),
    WalkthroughStep(
      title: '备份与恢复',
      body: '备份用于迁移整个应用数据（换手机、重装、升级前保存）。\n\n'
          '导入大量资产或恢复备份前，建议先导出一份完整备份，避免误操作丢失数据。',
      imageHint: '备份与恢复页',
    ),
    WalkthroughStep(
      title: '检查更新',
      body: '「检查更新」会联网查看是否有新版本。\n\n'
          '发现新版本时弹出更新提示，点击可前往发布页下载。更新检测优先走国内可直连的源，失败会提示「检查更新失败」，与「确无更新」区分开。',
      imageHint: '关于分组 + 检查更新',
    ),
  ],
);

const Walkthrough _characterLibrary = Walkthrough(
  title: '角色库',
  subtitle: '创建、导入、编辑、管理、切换角色。',
  icon: Icons.people_outline,
  steps: [
    WalkthroughStep(
      title: '角色库是什么',
      body: '角色库用于管理你的所有角色。每个角色是一张卡片，包含名字、封面、简介、人物设定、开场白等。\n\n'
          '可以在这里新建角色、导入角色卡（含图片角色卡）、AI 转译第三方角色卡，或编辑已有角色。',
      imageHint: '角色库整体界面',
    ),
    WalkthroughStep(
      title: '角色卡片与展开',
      body: '角色以网格卡片展示。\n\n'
          '点击卡片一次会展开简介；再次点击已展开的卡片会进入角色预览 / 编辑页。\n\n'
          '展开后卡片上会浮出名字、标签和简介。',
      imageHint: '展开的角色卡片（名字/标签/简介）',
    ),
    WalkthroughStep(
      title: '标签筛选',
      body: '角色顶部有标签筛选栏（仅当存在标签时显示）。\n\n'
          '点击某个标签，只显示带该标签的角色；点击「全部」恢复显示。\n\n'
          '标签在角色编辑页的「角色信息」里填写，多个标签用逗号分隔。',
      imageHint: '角色库顶部标签筛选栏',
    ),
    WalkthroughStep(
      title: '排序',
      body: '点击顶部的排序图标可以选择排序方式：\n\n'
          '• 默认顺序 / 创建时间\n'
          '• 按名称排序\n\n'
          '长按排序图标可以切换正序 / 倒序。',
      imageHint: '排序菜单',
    ),
    WalkthroughStep(
      title: '新建 / 导入 / AI 转译',
      body: '点击右上角的 + 按钮，会弹出三个选项：\n\n'
          '• 新建角色卡：手动创建\n'
          '• 导入角色卡：导入 .llmcard 或图片角色卡\n'
          '• AI 智能转译角色卡：自动转译第三方角色卡并直接加入角色库\n\n'
          '导入时会先弹出预览，确认无误后写入。',
      imageHint: '新建/导入/AI 转译 底部菜单',
    ),
    WalkthroughStep(
      title: '导出角色卡',
      body: '先点击一张角色卡选中它，再点击顶部的导出图标。\n\n'
          '可以导出：\n'
          '• 完整角色卡文件（.llmcard，稳定格式，推荐迁移或分享）\n'
          '• 角色卡图片（适合展示分享）\n\n'
          '导出时可选是否包含用户覆盖设定和绑定世界书。',
      imageHint: '导出角色卡底部菜单',
    ),
    WalkthroughStep(
      title: '删除角色',
      body: '长按一张角色卡片进入删除状态（卡片变红，出现删除图标）。\n\n'
          '可以长按多张标记；标记后顶部出现带数量的「批量删除」按钮，确认后一次性删除所有标记的角色。\n\n'
          '也可以点击单张卡片的删除图标单独删除。删除后不可恢复，请谨慎操作。',
      imageHint: '角色删除状态 + 批量删除',
    ),
    WalkthroughStep(
      title: '进入聊天',
      body: '先点击一张角色卡片选中它，再点击卡片右下角的播放按钮即可进入聊天页与该角色对话。\n\n'
          '进入前应用会预加载角色封面和会话数据，等待 UI 引擎就绪后平滑跳转。',
      imageHint: '播放按钮（进入聊天）',
    ),
  ],
);

const Walkthrough _worldBookLibrary = Walkthrough(
  title: '世界书库',
  subtitle: '管理背景设定、地点、组织、术语等资料。',
  icon: Icons.auto_stories_outlined,
  steps: [
    WalkthroughStep(
      title: '世界书是什么',
      body: '世界书用于保存不会一直写在聊天里的背景资料，例如世界观、地点、组织、术语、道具和长期剧情信息。\n\n'
          '世界书条目通常通过关键词触发：当最近聊天内容命中关键词时，对应条目会加入 Prompt，帮助模型记起相关设定。',
      imageHint: '世界书库整体界面',
    ),
    WalkthroughStep(
      title: '世界书卡片',
      body: '世界书以列表卡片展示。\n\n'
          '点击卡片进入世界书编辑页，可以编辑名称、描述和条目。',
      imageHint: '世界书卡片',
    ),
    WalkthroughStep(
      title: '排序',
      body: '点击顶部排序图标选择排序方式（默认顺序 / 创建时间、按名称）。\n\n'
          '长按排序图标切换正序 / 倒序。',
      imageHint: '世界书排序菜单',
    ),
    WalkthroughStep(
      title: '新建 / 导入世界书',
      body: '点击右上角 + 按钮，可以：\n\n'
          '• 新建世界书\n'
          '• 导入世界书（LLM Project 世界书 JSON）\n\n'
          '导入时会先预览确认。导入同内容的角色卡时，世界书会自动去重，重复的只保留一份并复用绑定。',
      imageHint: '新建/导入世界书菜单',
    ),
    WalkthroughStep(
      title: '导出 / 删除',
      body: '长按一张世界书卡片，会弹出操作菜单：\n\n'
          '• 导出世界书：保存为可分享 / 迁移的 JSON\n'
          '• 删除世界书：确认后删除，不可恢复\n\n'
          '删除前会弹出统一的确认对话框。',
      imageHint: '世界书长按操作菜单',
    ),
  ],
);

const Walkthrough _backgroundLibrary = Walkthrough(
  title: '背景图库',
  subtitle: '管理聊天背景和页面背景。',
  icon: Icons.image_outlined,
  steps: [
    WalkthroughStep(
      title: '背景图库是什么',
      body: '背景图库用于管理聊天背景和页面背景，属于外观相关功能，不影响基础聊天流程。\n\n'
          '背景有纯色、渐变、图片等类型，可以应用到聊天页和主页。',
      imageHint: '背景图库整体界面',
    ),
    WalkthroughStep(
      title: '背景卡片',
      body: '背景以卡片展示。\n\n'
          '点击卡片一次展开名称；再次点击已展开的卡片进入编辑页面，可以调整颜色、渐变或图片。',
      imageHint: '背景卡片',
    ),
    WalkthroughStep(
      title: '排序',
      body: '点击顶部排序图标选择排序方式；长按切换正序 / 倒序。',
      imageHint: '背景排序菜单',
    ),
    WalkthroughStep(
      title: '新建 / 导入背景',
      body: '点击右上角 + 按钮，可以新建背景或导入背景卡文件。\n\n'
          '新建时可以选择纯色、渐变或从相册 / 文件选择图片。',
      imageHint: '新建/导入背景菜单',
    ),
    WalkthroughStep(
      title: '导出 / 删除',
      body: '长按一张背景卡片弹出操作菜单。\n\n'
          '图片背景支持导出背景卡（可恢复背景设定）；非预设背景可以删除（删除前有确认对话框）。',
      imageHint: '背景长按操作菜单',
    ),
  ],
);

const Walkthrough _chat = Walkthrough(
  title: '聊天页',
  subtitle: '与角色对话、侧滑设置、角色切换、输入发送。',
  icon: Icons.chat_outlined,
  steps: [
    WalkthroughStep(
      title: '聊天页是什么',
      body: '聊天页是与当前角色对话的界面。\n\n'
          '中部是消息列表，底部是输入区；输入区上方还有一个当前角色名称胶囊。\n\n'
          '新聊天没有历史时，会自动插入开场白作为第一条角色消息。',
      imageHint: '聊天页整体界面（消息列表 + 底部输入区）',
    ),
    WalkthroughStep(
      title: '输入与发送',
      body: '点击底部输入按钮展开输入框。\n\n'
          '输入内容后点击发送按钮即可发送消息。\n\n'
          '如果角色配置了 UI 场景组件，输入可能由场景组件接管；没有配置时使用底部原生输入框。',
      imageHint: '聊天输入区',
    ),
    WalkthroughStep(
      title: '切换角色',
      body: '聊天页底部的角色名称胶囊（输入区上方，输入框未展开时显示）显示当前角色名。\n\n'
          '点击它会在屏幕下半部展开一个弧形角色轮盘，左右滑动浏览，点击某张卡即可切换当前聊天对象，不需要退出聊天页。\n\n'
          '输入框展开时胶囊会淡出，收起后恢复。',
      imageHint: '底部角色名称胶囊 + 弧形切换轮盘',
    ),
    WalkthroughStep(
      title: '侧滑打开聊天设置',
      body: '在聊天页按住右侧边缘的高光框向左滑动，打开聊天设置面板。\n\n'
          '里面可以进入当前角色的用户设定、Prompt 策略、背景设置，以及清空历史等操作。',
      imageHint: '聊天设置面板',
    ),
    WalkthroughStep(
      title: '清空历史与重置',
      body: '聊天设置里提供「清空历史」操作，可以把当前角色的对话历史清空。\n\n'
          '清空时可以选择是否同时把用户设定重置为角色卡默认。',
      imageHint: '清空历史对话框',
    ),
    WalkthroughStep(
      title: 'Prompt 预览',
      body: '可以在聊天设置里查看最终发送给模型的 System Prompt（Prompt 预览）。\n\n'
          '如果角色表现不符合设定，先看这里确认期望的设定是否真的被注入。',
      imageHint: 'Prompt 预览',
    ),
  ],
);

const Walkthrough _apiConfig = Walkthrough(
  title: 'API 配置',
  subtitle: '管理模型服务地址与密钥，是聊天的前提。',
  icon: Icons.api,
  steps: [
    WalkthroughStep(
      title: 'API 配置是什么',
      body: 'API 配置用于填写模型服务的调用信息。聊天时，应用会把你的消息发送到你配置的模型服务，再取回回复。\n\n'
          '没有可用的 API 配置，聊天无法正常回复。',
      imageHint: 'API 配置列表',
    ),
    WalkthroughStep(
      title: '三个关键字段',
      body: '新增或编辑 API 配置时，主要填写三个字段：\n\n'
          '• API Key：服务商给你的调用密钥，不要分享给别人\n'
          '• Base URL：服务商的接口地址\n'
          '• 模型名：要调用的具体模型，例如 deepseek-chat\n\n'
          '三个字段都正确填写后才能正常使用。',
      imageHint: 'API 配置编辑表单',
    ),
    WalkthroughStep(
      title: '启用配置',
      body: '可以有多个 API 配置。当前生效的那个是「当前启用配置」。\n\n'
          '切换启用不同的配置即可切换模型服务。',
      imageHint: '启用配置切换',
    ),
    WalkthroughStep(
      title: '测试连接',
      body: '编辑页提供测试连接功能，可以验证配置是否正确。\n\n'
          '如果测试失败，优先检查 API Key、Base URL 是否完整、账号是否有余额或模型权限、网络能否访问对应服务商。',
      imageHint: '测试连接',
    ),
  ],
);

const Walkthrough _userSettings = Walkthrough(
  title: '用户设定',
  subtitle: '设置「你是谁」，角色会参考这些信息与你互动。',
  icon: Icons.person_outline,
  steps: [
    WalkthroughStep(
      title: '用户设定是什么',
      body: '用户设定描述「你是谁」。角色会参考这些信息与你互动，例如你的昵称、头像、性格和背景。\n\n'
          '新手可以先跳过，开始聊天后再补充。',
      imageHint: '用户设定页',
    ),
    WalkthroughStep(
      title: '用户信息字段',
      body: '可以填写你的昵称、头像和个人简介。\n\n'
          '设置后，发送给模型的提示会携带这些信息，让角色认识你。',
      imageHint: '用户信息编辑',
    ),
  ],
);

const Walkthrough _promptSettings = Walkthrough(
  title: 'Prompt 策略',
  subtitle: '控制系统提示词如何组织与注入。',
  icon: Icons.tune,
  steps: [
    WalkthroughStep(
      title: 'Prompt 策略是什么',
      body: 'Prompt 策略控制最终发送给模型的系统提示结构，属于进阶功能。\n\n'
          '设置页中的是全局默认策略，所有没有单独设置的角色都会使用它。',
      imageHint: 'Prompt 策略页',
    ),
    WalkthroughStep(
      title: '注入与分频',
      body: '策略里可以控制角色设定、世界书、用户设定等内容的注入方式与频率。\n\n'
          '熟悉基础聊天后再调整更稳妥。',
      imageHint: '注入与分频设置',
    ),
  ],
);

const Walkthrough _backupRestore = Walkthrough(
  title: '备份与恢复',
  subtitle: '迁移整个应用数据（换手机、重装、升级前保存）。',
  icon: Icons.backup_outlined,
  steps: [
    WalkthroughStep(
      title: '备份与恢复是什么',
      body: '备份用于迁移整个应用数据，例如换手机、重装应用或升级前保存当前状态。\n\n'
          '和「单个资产导出导入」不同，备份恢复的是全部数据。',
      imageHint: '备份与恢复页',
    ),
    WalkthroughStep(
      title: '导出备份',
      body: '点击导出备份，可以把全部数据（角色、世界书、背景、用户设定、Prompt 策略等）保存为一份备份文件。\n\n'
          '导入大量资产或恢复前，建议先导出一份完整备份。',
      imageHint: '导出备份',
    ),
    WalkthroughStep(
      title: '导入 / 恢复备份',
      body: '点击恢复备份，选择之前导出的备份文件即可恢复全部数据。\n\n'
          '恢复会覆盖当前数据，请谨慎操作，务必先确认备份内容。',
      imageHint: '恢复备份',
    ),
  ],
);
