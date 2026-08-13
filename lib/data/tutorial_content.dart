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
  static const characterEdit = 'character_edit';
  static const statusBarHighlight = 'status_bar_highlight';
  static const worldBookLibrary = 'world_book_library';
  static const backgroundLibrary = 'background_library';
  static const chat = 'chat';
  static const apiConfig = 'api_config';
  static const userSettings = 'user_settings';
  static const promptSettings = 'prompt_settings';
  static const backupRestore = 'backup_restore';
  static const uiStudio = 'ui_studio';
  static const uiAssetGallery = 'ui_asset_gallery';
  static const uiAssembly = 'ui_assembly';
}

/// 有序的页面讲解列表（顺序即教程中心的展示顺序）。
final List<Walkthrough> allWalkthroughs = [
  _home,
  _settings,
  _characterLibrary,
  _characterEdit,
  _statusBarHighlight,
  _worldBookLibrary,
  _backgroundLibrary,
  _chat,
  _apiConfig,
  _userSettings,
  _promptSettings,
  _backupRestore,
  _uiStudio,
  _uiAssetGallery,
  _uiAssembly,
];

/// 页面 key → 讲解的映射。教程中心按 key 打开对应讲解。
final Map<String, Walkthrough> _byKey = {
  TutorialPageKey.home: _home,
  TutorialPageKey.settings: _settings,
  TutorialPageKey.characterLibrary: _characterLibrary,
  TutorialPageKey.characterEdit: _characterEdit,
  TutorialPageKey.statusBarHighlight: _statusBarHighlight,
  TutorialPageKey.worldBookLibrary: _worldBookLibrary,
  TutorialPageKey.backgroundLibrary: _backgroundLibrary,
  TutorialPageKey.chat: _chat,
  TutorialPageKey.apiConfig: _apiConfig,
  TutorialPageKey.userSettings: _userSettings,
  TutorialPageKey.promptSettings: _promptSettings,
  TutorialPageKey.backupRestore: _backupRestore,
  TutorialPageKey.uiStudio: _uiStudio,
  TutorialPageKey.uiAssetGallery: _uiAssetGallery,
  TutorialPageKey.uiAssembly: _uiAssembly,
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
      body: '用户设定用于设置「你是谁」。角色会参考这些信息与你互动，例如你的昵称和头像。\n\n'
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
      title: 'AI 智能转译',
      body: '「AI 智能转译」可以把其他平台的角色卡（SillyTavern、TavernAI、PNG 内嵌角色卡）自动转换成本应用的角色。\n\n'
          '选择文件后，可选择用哪个 AI 配置来转译，也可以关闭 AI 只做规则转译（更快，不调用模型）。\n\n'
          '转译会自动完成：规则转译 → AI 智能归类 → AI 理解界面（生成 UI 与状态栏）→ 检查精修，完成后直接加入角色库。',
      imageHint: 'AI 智能转译对话框',
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
      body: '世界书以网格卡片展示，封面为程序生成的渐变色卡，中央是词云（由条目与关键词生成）。\n\n'
          '点击卡片进入世界书编辑页，可以编辑名称、描述和条目。',
      imageHint: '世界书卡片（词云封面）',
    ),
    WalkthroughStep(
      title: '编辑条目',
      body: '世界书编辑页里可以添加多条条目。每条条目可设置：\n\n'
          '• 条目名称与内容\n'
          '• 触发关键词（支持中英文逗号、分号分隔多个）\n'
          '• 启用 / 停用开关（停用的条目不触发）\n'
          '• 常驻：始终注入，不依赖关键词\n'
          '• 递归触发：已触发内容可继续激活其他条目\n'
          '• 注入位置：角色设定之前或之后\n'
          '• 注入优先级：数值越小越靠前，越靠前模型越重视',
      imageHint: '世界书条目编辑器',
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
          '输入内容后点击发送按钮即可发送消息。输入框下方会实时显示估算的 Tokens 消耗。\n\n'
          '如果角色配置了 UI 场景组件，输入可能由场景组件接管；没有配置时使用底部原生输入框。',
      imageHint: '聊天输入区',
    ),
    WalkthroughStep(
      title: 'AI 消息操作',
      body: '最新一条 AI 消息下方有一排功能图标：\n\n'
          '• 重新生成：丢弃当前回复，让模型重新回复一次\n'
          '• 继续回复：在回复末尾继续往下写\n'
          '• 多版本切换：重新生成后的历史版本会保留，用左右箭头在版本间切换\n\n'
          '这些图标仅出现在最新一条 AI 消息上。',
      imageHint: 'AI 消息功能图标行',
    ),
    WalkthroughStep(
      title: '用户消息操作',
      body: '用户消息支持两种操作：\n\n'
          '• 点击消息气泡进入编辑，修改后保存会替换该消息并重建后续回复\n'
          '• 最新一条用户消息旁有「撤回」图标，点击可删除这条用户消息及其后续所有回复\n\n'
          '撤回常用于发错内容后回退对话。',
      imageHint: '用户消息编辑 / 撤回',
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
          '名称旁有「预设」按钮，可以一键填入 DeepSeek、OpenAI、Gemini、SiliconFlow 等常见服务商的 Base URL，再自己补上 Key 和模型名。',
      imageHint: 'API 配置编辑表单 + 预设',
    ),
    WalkthroughStep(
      title: '启用配置',
      body: '可以有多个 API 配置。当前生效的那个是「当前启用配置」。\n\n'
          '列表里每条配置右侧的菜单可以编辑、删除或「设为当前」。切换启用不同的配置即可切换模型服务。',
      imageHint: '启用配置切换',
    ),
    WalkthroughStep(
      title: '测试连接',
      body: '编辑页提供测试连接功能，可以验证配置是否正确。\n\n'
          '测试成功后会尝试拉取可用模型列表供你直接选择；测试失败时仍可手动输入模型名。\n\n'
          '如果测试失败，优先检查 API Key、Base URL 是否完整、账号是否有余额或模型权限、网络能否访问对应服务商。',
      imageHint: '测试连接 + 模型列表',
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
      body: '用户设定描述「你是谁」。角色会参考这些信息与你互动，例如你的昵称和头像。\n\n'
          '新手可以先跳过，开始聊天后再补充。',
      imageHint: '用户设定页',
    ),
    WalkthroughStep(
      title: '用户信息字段',
      body: '可以设置你的用户头像和昵称。\n\n'
          '昵称留空时默认使用「我」。设置后，发送给模型的提示会携带这些信息，让角色认识你。\n\n'
          '这里只保存全局默认信息；更详细的个人简介、以及针对某个角色的专属设定，在聊天页「用户设定」里的角色覆盖设定中填写。',
      imageHint: '用户信息编辑（头像 + 昵称）',
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
      title: '策略项详解',
      body: '策略页可以逐项控制注入内容与频率：\n\n'
          '• 注入角色扮演规则：人物卡 / 系统卡各自的扮演规则文本\n'
          '• 注入连续性提醒：每轮提醒模型保持角色身份与上下文\n'
          '• 注入历史后指令：把角色卡的「历史后指令」放到对话最末尾，贴近模型回复，约束力更强\n'
          '• 摘要设定注入间隔：每隔多少个用户回合注入一次行为摘要（0 关闭）\n'
          '• 完整设定注入间隔：每隔多少个回合注入一次完整详细设定（0 关闭）\n'
          '• 世界书扫描深度：用于触发世界书的最近消息条数，推荐 4\n\n'
          '滑动条与数字框都可调，超出推荐范围会有提示。',
      imageHint: '注入与分频设置',
    ),
    WalkthroughStep(
      title: '角色单独策略',
      body: '从聊天页设置进入 Prompt 策略时，是针对当前角色的版本。\n\n'
          '默认情况下角色沿用全局策略；开启「当前角色使用单独 Prompt 策略」后，改动才只影响这个角色。\n\n'
          '调整前后可以点右上角眼睛图标预览实际发送给模型的 System Prompt。',
      imageHint: '角色单独策略开关 + 预览',
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
          '导出内容可以勾选，默认不包含 API Key、聊天记录、角色用户覆盖设定等敏感项；勾选这些时会再弹一次提醒。\n\n'
          '导入大量资产或恢复前，建议先导出一份完整备份。',
      imageHint: '导出备份（可勾选内容）',
    ),
    WalkthroughStep(
      title: '导入 / 恢复备份',
      body: '点击恢复备份，选择之前导出的备份文件即可恢复数据。\n\n'
          '导入时可以选择两种方式：\n'
          '• 合并导入：生成新 ID、不覆盖现有数据（推荐）\n'
          '• 恢复导入：保留原 ID、同 ID 覆盖现有数据\n\n'
          '恢复会覆盖当前数据，请谨慎操作，务必先确认备份内容。',
      imageHint: '恢复备份（选择导入方式）',
    ),
  ],
);

const Walkthrough _characterEdit = Walkthrough(
  title: '角色编辑页',
  subtitle: '角色卡创作核心：设定条目、开场白、角色信息与 UI 能力。',
  icon: Icons.edit_outlined,
  steps: [
    WalkthroughStep(
      title: '角色编辑页是什么',
      body: '角色编辑页是浮层表单，点击角色卡即可进入。\n\n'
          '从上到下依次是：头像、名称、简短描述、卡片类型、封面、绑定世界书、状态栏与 UI 入口、文本着色、设定条目、开场白、角色信息。\n\n'
          '未保存的修改在退出时会静默存为草稿，下次进入同一条目会提示是否恢复。',
      imageHint: '角色编辑页整体',
    ),
    WalkthroughStep(
      title: '头像 / 名称 / 描述',
      body: '点击头像可选择头像图片；名称不能与其他角色重复，重名会提示；简短描述会显示在卡片和主页入口卡上。',
      imageHint: '头像 / 名称 / 描述编辑',
    ),
    WalkthroughStep(
      title: '卡片类型',
      body: '卡片分「人物卡」和「系统卡」两种：\n\n'
          '• 人物卡：适合普通角色扮演对象，默认有名称、关系、身体、心理、背景等条目\n'
          '• 系统卡：适合世界 / 游戏 / 剧本 / 系统流设定，默认有系统名称、概要、详情、主角设定、剧情等条目\n\n'
          '切换类型会重置默认条目。系统卡启用「主角设定」后，聊天时可用主角设定作为你的默认设定。',
      imageHint: '人物卡 / 系统卡切换',
    ),
    WalkthroughStep(
      title: '设定条目',
      body: '条目按「简单介绍」和「详细设定」分组，每个条目都有启用开关，可以展开内联编辑。\n\n'
          '还可以添加自定义条目，自定义条目拥有独立编辑页。\n\n'
          '条目内容会注入到发送给模型的提示中。',
      imageHint: '设定条目列表',
    ),
    WalkthroughStep(
      title: '开场白',
      body: '开场白是角色对你的第一句话，支持添加多条。\n\n'
          '点击条目可编辑内容，也可以插入本地图片（以 <img> 标签形式随角色卡导出）。\n\n'
          '新对话没有历史时，自动插入第一条开场白；在聊天页可以对开场白消息切换不同版本。',
      imageHint: '多开场白管理',
    ),
    WalkthroughStep(
      title: '角色信息',
      body: '角色信息区用于填写标签、作者、版本、作者备注和历史后指令。\n\n'
          '• 标签：逗号分隔，角色库顶部的筛选栏据此显示\n'
          '• 历史后指令：放在对话最末尾的强约束指令，如「只用中文、不要旁白」\n\n'
          '这些信息默认不注入 Prompt（历史后指令除外），主要用于展示、筛选与资料保留。',
      imageHint: '角色信息字段',
    ),
    WalkthroughStep(
      title: '绑定世界书',
      body: '在编辑页可以给角色绑定一份世界书。\n\n'
          '绑定后，聊天时世界书中被关键词命中的条目会随提示注入，为角色补充世界观设定。',
      imageHint: '绑定世界书面板',
    ),
    WalkthroughStep(
      title: '未保存草稿',
      body: '角色编辑页是浮层，点击外部就会关闭，改到一半很容易误关。\n\n'
          '现在退出时会静默保存草稿（有效 24 小时），下次进入同一张卡时弹窗询问是否恢复，选择「不保存」才会彻底丢弃。',
      imageHint: '恢复草稿对话框',
    ),
  ],
);

const Walkthrough _statusBarHighlight = Walkthrough(
  title: '状态栏与文本着色',
  subtitle: '角色卡顶部的玩法状态栏，以及消息文本的正则着色。',
  icon: Icons.speed_outlined,
  steps: [
    WalkthroughStep(
      title: '是什么',
      body: '这是角色编辑页里的两个附属编辑器入口：\n\n'
          '• 状态栏：在聊天页顶部定义一排玩法数值 / 文本（生命、好感、地点等），可由 AI 或 UI 组件读写\n'
          '• 文本着色：用正则规则给消息里的台词、旁白等片段上色，只影响显示、不改写原文\n\n'
          '两者都随角色卡保存、导入导出。',
      imageHint: '角色编辑页里的入口',
    ),
    WalkthroughStep(
      title: '定义状态栏字段',
      body: '在状态栏字段页点击「添加字段」，每个字段可设置：\n\n'
          '• 字段名称（如 生命、好感、地点）\n'
          '• 类型：数值 或 文本\n'
          '• 归属：玩家的属性 / 角色自己的属性 / 中立环境，注入时带上主语帮助 AI 判断增减\n'
          '• 初始值，数值型可设最小 / 最大值\n\n'
          '聊天时展开状态栏，每个块顶部有小滑块可固定它在长条的左 / 右侧。',
      imageHint: '状态栏字段编辑',
    ),
    WalkthroughStep(
      title: '文本着色规则',
      body: '文本着色页用正则表达式匹配片段并着色。\n\n'
          '每条规则可设名称、开关、正则、颜色（固定色板或沿用正文色）、加粗 / 斜体，并可用上下箭头调整优先级——靠前的规则先占位。\n\n'
          '顶部有实时预览框，可以粘贴实际文本查看效果。没配过时使用内置默认规则。',
      imageHint: '文本着色规则编辑',
    ),
  ],
);

const Walkthrough _uiStudio = Walkthrough(
  title: 'UI 创作工作室',
  subtitle: '可视化搭建自定义界面：原子组件、画布、联动器、复合组件。',
  icon: Icons.palette_outlined,
  steps: [
    WalkthroughStep(
      title: '是什么',
      body: 'UI 创作工作室（设置 → UI 创作工作室）是一个可视化搭建工具，用来制作可复用的界面组件。\n\n'
          '可以把它理解成「搭积木」：从左侧原材料库把一个个「原子组件」拖到画布上摆放，再用「联动器」把它们的数值、状态、事件连起来，组成一个完整的界面小组件。\n\n'
          '搭好的组件可以保存成「复合组件」进 UI 模组库，之后在角色编辑页的「UI 拼装方案」里挂到聊天页使用。',
      imageHint: 'UI 工作台整体（原材料库 + 画布 + 工具栏）',
    ),
    WalkthroughStep(
      title: '原子组件分四类',
      body: '左侧原材料库的原子按用途分四组：\n\n'
          '1. 外观（纯视觉，不产生数据）：面板、图片、线条\n'
          '2. 显示（展示数据，不接受输入）：文本、进度条、指示灯\n'
          '3. 交互（玩家可操作）：输入框、下拉、滑块、开关、按钮\n'
          '4. 逻辑（后台件，运行时不显形）：联动器、计算节点、定时器\n\n'
          '逻辑组是让界面「活起来」的关键——它们看不见，但负责数值计算、定时、以及把数据在组件间搬运。',
      imageHint: '左侧原材料库四组分类',
    ),
    WalkthroughStep(
      title: '外观组件：面板 / 图片 / 线条',
      body: '外观组件负责界面的视觉底座，本身不产生数据：\n\n'
          '• 面板：带形状 / 圆角 / 填充色 / 描边的容器，作为摆放其他元件的底面\n'
          '• 图片：显示图片，可设来源、缩放方式、形状、圆角\n'
          '• 线条：一条分割线，可设粗细、样式（实线/虚线）、方向、颜色\n\n'
          '保存复合组件时需要一个「容器底面」来承载元件，通常就是放一块面板。',
      imageHint: '面板 / 图片 / 线条',
    ),
    WalkthroughStep(
      title: '显示组件：文本 / 进度条 / 指示灯',
      body: '显示组件用于把数据展示给玩家，本身不接收输入：\n\n'
          '• 文本：显示文字，可用模板（如 {{current}}）引用来源数值，实时更新\n'
          '• 进度条：显示一个数值条，可设最小/最大/当前值、颜色、形状（含胶囊、圆环等）\n'
          '• 指示灯：一个会变色的状态灯，可设多个状态规则（按传入值显示不同颜色）\n\n'
          '它们的数值通常由别的组件通过联动器驱动。',
      imageHint: '文本 / 进度条 / 指示灯',
    ),
    WalkthroughStep(
      title: '交互组件：输入框 / 下拉 / 滑块 / 开关 / 按钮',
      body: '交互组件是玩家能操作的控件：\n\n'
          '• 输入框：玩家输入文字，可设占位符、必填、多行、最大长度、对齐、颜色\n'
          '• 下拉：玩家从选项里选一个，可设选项列表、展开方向、是否由输入控制\n'
          '• 滑块：玩家拖一个数值，可设范围、步长、当前值、形状\n'
          '• 开关：一个 true/false 开关，可设颜色、形状（胶囊）\n'
          '• 按钮：可点击触发事件的逻辑热区（本身透明），可设单击/双击/长按\n\n'
          '它们的交互结果（输入的文字、选中的值、开关状态、点击事件）通过联动器驱动其它组件。',
      imageHint: '输入框 / 下拉 / 滑块 / 开关 / 按钮',
    ),
    WalkthroughStep(
      title: '逻辑组件：定时器 / 计算节点',
      body: '逻辑组件是后台运算件，运行时不显示在界面上：\n\n'
          '• 定时器：按间隔持续触发。可设触发方式（定时开关/增量/倒计时等）、间隔、步长，运行时可点按钮或由开关控制启停\n'
          '• 计算节点：做数值运算。可设多个参数口（数字/文本），用加减乘除、比较、取最大值等逻辑算出结果\n\n'
          '它们常被用来做持续变化的数值（比如血量随时间回复）或复杂的数值换算。',
      imageHint: '定时器 / 计算节点',
    ),
    WalkthroughStep(
      title: '画布与拖放',
      body: '工作台是带网格的无限画布，可以双指平移 / 缩放。\n\n'
          '从左侧原材料库**长按拖入**元件放到画布上。\n\n'
          '选中元件后可以：\n'
          '• 用 D-Pad 方向键微调位置\n'
          '• 编辑精确的几何数值（x/y/宽/高）\n'
          '• 调整图层顺序（上移/下移）\n'
          '• 复制、删除\n\n'
          '画布顶部有撤销 / 重做（最多 100 步）和清空画布。',
      imageHint: '画布拖放元件 + D-Pad + 图层操作',
    ),
    WalkthroughStep(
      title: '编辑元件',
      body: '双击元件打开它的编辑器，每种元件的可配置项不同：\n\n'
          '• 面板：形状 / 圆角 / 填充 / 描边\n'
          '• 文本：内容 / 模板 / 字体大小 / 对齐 / 颜色\n'
          '• 进度条 / 滑块：范围 / 步长 / 形状 / 颜色\n'
          '• 指示灯：状态规则（不同颜色）\n'
          '• 输入框：必填 / 多行 / 最大长度 / 颜色\n'
          '• 定时器：触发方式 / 间隔 / 步长\n'
          '• 计算节点：运算类型 / 参数口\n\n'
          '编辑完成后元件在画布上即时更新。',
      imageHint: '元件编辑器',
    ),
    WalkthroughStep(
      title: '联动器是什么',
      body: '联动器是「把 A 的变化接到 B」的连线。它是逻辑组里的一个原子，也是让界面动起来的核心。\n\n'
          '把联动器放到画布上，会出现一个可拖拽的连线端口：从一个组件的输出口拉线到另一个组件的输入口，就建立了一条「协议」。\n\n'
          '例如：滑块 → 联动器 → 进度条，拖动滑块进度条就跟着变。',
      imageHint: '联动器连线',
    ),
    WalkthroughStep(
      title: '联动协议：按钮（click）',
      body: '按钮触发「点击」事件，可连接到：\n\n'
          '• 面板：按压凹陷反馈\n'
          '• 开关：翻转 / 强制开 / 强制关\n'
          '• 输入框：清空\n'
          '• 滑块：重置到默认\n'
          '• 定时器：启动/停止切换 / 重置归零\n'
          '• 计算节点：手动触发立即算一次\n\n'
          '按钮本身是透明热区，常盖在一个面板上，做成「点面板某块区域」的交互。',
      imageHint: '按钮点击协议',
    ),
    WalkthroughStep(
      title: '联动协议：开关（switch）',
      body: '开关的「开/关」状态可驱动：\n\n'
          '• 文本：开显示一段文案，关显示另一段\n'
          '• 任意组件：控制可见性（开显示/关隐藏）、使能（开可用/关禁用并淡化）、锁定、数值冻结\n'
          '• 定时器：开时运行，关时停止\n\n'
          '常用于「高级选项开关」——开了才显示/启用某个区域。',
      imageHint: '开关协议',
    ),
    WalkthroughStep(
      title: '联动协议：输入框（input）',
      body: '输入框的文字 / 校验状态可驱动：\n\n'
          '• 文本：实时同步 / 提交（回车/失焦）后同步 / 提交后清空\n'
          '• 按钮：输入非空时启用 / 通过校验时启用\n'
          '• 指示灯：按校验状态（空/有效/无效）或字符长度变色\n'
          '• 下拉：输入与某选项匹配时自动选中 / 实时过滤选项列表\n'
          '• 进度条 / 滑块：把输入的数值喂给它\n\n'
          '常用于表单校验、搜索过滤、数值输入。',
      imageHint: '输入框协议',
    ),
    WalkthroughStep(
      title: '联动协议：滑块 / 下拉 / 进度 / 文本',
      body: '滑块 / 下拉 / 进度条 / 文本 作为数据源：\n\n'
          '• 滑块：当前值实时→文本 / 进度条；松手才→文本 / 计算参数\n'
          '• 下拉：选中项→文本；选中值→控制某面板显隐 / 开关状态\n'
          '• 进度条：当前值/最大/百分比→文本；满足阈值→启用按钮 / 开开关\n'
          '• 文本：取数（纯数值/第一个数/第N个/关键字）→计算参数；非空/匹配→启用按钮；匹配→开开关 / 切下拉选项\n\n'
          '这些都是「把数据源接到目标」的常用接线。',
      imageHint: '滑块/下拉/进度/文本协议',
    ),
    WalkthroughStep(
      title: '联动协议：定时器 / 指示灯 / 计算节点',
      body: '定时器 / 指示灯 / 计算节点 也各有协议：\n\n'
          '• 定时器：每次 Tick → 翻转/开/关开关、进度加减、触发计算、数值→文本\n'
          '• 指示灯：当前颜色匹配 → 控制开关/文本/使能/锁定/冻结/显隐；收到事件→短暂闪烁\n'
          '• 计算节点：结果→文本（含条件文案）/ 进度条（含百分比/布尔跳满）；布尔→文本/进度条；数值→注入另一个计算参数\n\n'
          '计算节点之间可以串联，做多步运算。',
      imageHint: '定时器/指示灯/计算节点协议',
    ),
    WalkthroughStep(
      title: '特殊协议：配额分配与求和汇总',
      body: '两个把「多个组件当整体」的协议：\n\n'
          '• 配额分配（pool → allocation）：把一个组件当作「可分配总量」，其它组件（滑块/输入框）从中分配点数。总量组件写「10」，连到力量/敏捷/智力三个滑块，即做成属性点分配面板；分配组件自动归零并被限制在剩余额度内\n'
          '• 数值求和（sum → display）：把多个数值加起来显示到一处\n\n'
          '这两个协议让多个组件协同工作，是较进阶的用法。',
      imageHint: '配额分配 / 求和汇总',
    ),
    WalkthroughStep(
      title: '保存为复合组件',
      body: '搭好的界面可以点「保存为复合组件」，命名后存入 UI 模组库。\n\n'
          '保存前需要有一个**容器底面**（面板）来承载元件。复合组件可以设置**暴露端口**，这样在别处复用时能把这些端口连到其它组件。\n\n'
          '工作台会自动保存草稿，退出后重新进入可继续编辑。',
      imageHint: '保存复合组件 + 暴露端口',
    ),
  ],
);

const Walkthrough _uiAssetGallery = Walkthrough(
  title: 'UI 模组库',
  subtitle: '查看、试用、导出、导入自定义 UI 组件。',
  icon: Icons.widgets_outlined,
  steps: [
    WalkthroughStep(
      title: '是什么',
      body: 'UI 模组库（主页右下模块轨道里的「UI 模组库」）集中展示你保存的界面资产：\n\n'
          '• 自定义模组：旧格式的模块\n'
          '• 复合组件：在 UI 创作工作室保存的组件，按设计比例展示，可直接在卡片里点击、拖动试用交互\n\n'
          '没有保存过资产时显示空状态提示。',
      imageHint: 'UI 模组库列表',
    ),
    WalkthroughStep(
      title: '导出 / 导入',
      body: '每张复合组件卡片右下有导出和删除按钮。\n\n'
          '导出会保存为 .llmui 文件（到下载目录），可分享或迁移；右上角可导入其他 .llmui 文件。\n\n'
          '删除时提示「已经用到角色卡里的实例不受影响」——组件在角色卡里是值拷贝，删除模板不会让已摆好的界面变空。',
      imageHint: '导出 / 导入复合组件',
    ),
  ],
);

const Walkthrough _uiAssembly = Walkthrough(
  title: '角色 UI 拼装',
  subtitle: '给角色设计会动的聊天界面：四种 UI 方案、拼装画布、数据通道、页面路由。',
  icon: Icons.dashboard_customize_outlined,
  steps: [
    WalkthroughStep(
      title: '是什么',
      body: '角色 UI 拼装（角色编辑页 → UI 入口）给角色设计「会动的聊天界面」，这是本应用最进阶的功能。\n\n'
          '可以新建四种 UI 方案，**每种只能有一个**：\n\n'
          '• 开场白弹窗：首次进入聊天时全屏展现（适合角色创建界面、属性加点）\n'
          '• 场景 UI：全屏接管整个聊天页，替代对话气泡（适合战斗界面、养成面板）\n'
          '• 常驻 UI：浮在聊天上方，可折叠为悬浮球（适合好感条、状态指示器）\n'
          '• 伴生 UI：嵌入最新消息气泡下方跟随滚动（适合评论区、记录面板）\n\n'
          '**场景 UI 与伴生 UI 互斥**——场景接管整屏后没有消息气泡可供伴生依附。',
      imageHint: 'UI 拼装方案列表 + 新建菜单',
    ),
    WalkthroughStep(
      title: '拼装画布与页面',
      body: '选择 UI 类型后进入拼装画布，这是一块可平移 / 缩放的「PCB」电路板。\n\n'
          '画布支持多页面：\n'
          '• 平级页：并列的页面，可互相切换\n'
          '• 叠加页：浮在当前页之上的一层弹窗\n\n'
          '每个页面有自己的元件。叠加页通常需要放一块「面板」作为弹层容器。',
      imageHint: '拼装画布 + 平级页/叠加页',
    ),
    WalkthroughStep(
      title: '放置元件',
      body: '从画布底部或侧边栏拖入元件（按钮、输入框、开关、滑块、进度条、图片、面板等），也可以拖入已保存的复合组件。\n\n'
          '元件摆放后可以像在 UI 工作室里一样：选中、拖动、D-Pad 微调、编辑属性、调整图层、复制删除。\n\n'
          '元件之间可以用「联动器」连线，做组件内部的联动。',
      imageHint: '放置元件 + 连线',
    ),
    WalkthroughStep(
      title: '数据通道',
      body: '双击元件可编辑**数据通道**——这是拼装最核心的部分，让界面和角色/对话联动：\n\n'
          '• 绑定字段：组件读写哪个数据（角色卡设定条目、状态栏字段、会话变量等）\n'
          '• AI 读写策略：这个字段允许 AI 读取还是写入，或只读\n'
          '• 通知方式：值变化时如何通知 / 触发\n\n'
          '例如开场白弹窗里的输入框，绑定到角色的「主角设定」，玩家填的内容就写进角色卡。',
      imageHint: '数据通道编辑器',
    ),
    WalkthroughStep(
      title: '页面路由（换页）',
      body: '用按钮连接「页面路由器」，实现点击切换页面：\n\n'
          '放一个「页面路由器」逻辑组件，把按钮的点击连线到它，设置切换目标页。\n\n'
          '可以切换平级页，或打开 / 关闭叠加页——适合做「下一步」「打开设置弹层」这类流程。',
      imageHint: '页面路由连线',
    ),
    WalkthroughStep(
      title: '消息操作',
      body: '把按钮连到「消息流」，可以控制聊天页本身：\n\n'
          '按钮点击对最新一条 AI 消息执行：重新生成 / 继续写 / 编辑 / 撤回该轮 / 切到上一个版本 / 切到下一个版本。\n\n'
          '当场景 UI 接管整屏、原生气泡消失后，这些操作就用作者自己摆的按钮来表达。',
      imageHint: '按钮连消息流',
    ),
    WalkthroughStep(
      title: '与 LLM 联动',
      body: '除了玩家操作，界面还能和 AI 联动：\n\n'
          '状态栏 / 数据通道里的字段可以配置 AI 读写策略，让模型在回复时更新界面数值（比如扣血、好感度变化）。\n\n'
          '这样界面不只是静态摆设，而是会随对话推进动态变化。',
      imageHint: 'AI 读写联动',
    ),
    WalkthroughStep(
      title: '在聊天页生效',
      body: '保存 UI 方案后，进入聊天页即可看到效果：\n\n'
          '• 开场白弹窗会在首次进入时弹出\n'
          '• 场景 UI 接管整屏\n'
          '• 常驻 UI 浮在聊天上方（可长按拖动、折叠）\n'
          '• 伴生 UI 跟随最新消息\n\n'
          '配置了场景 / 常驻 UI 时，输入可能由场景组件接管。',
      imageHint: '聊天页中的 UI 效果',
    ),
  ],
);
