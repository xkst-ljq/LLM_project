# LLM Project UI 优化基础框架

> **版本：UI Foundation v1.0**  
> **状态：基础框架定稿**  
> **日期：2026-08-08**  
> **适用范围：** App 外壳、角色体验、聊天运行时、UI Engine、未来 Galgame / RPG / 互动小说 / Live2D / 3D 模式

---

## 0. 定稿结论

LLM Project 不定位为 Agent、助手或效率工具，也不定位为单纯的 UI 创作工具。

本项目的产品定位是：

> **高自由度 AI 互动体验前端 / AI 角色游戏运行时。**

用户进入的是由角色、世界、状态和叙事共同构成的体验。聊天是第一种运行模式，后续可以扩展为 Galgame、RPG、互动小说和 3D 角色互动。

创作能力是底层能力，UI Engine 是体验运行时；创作的目的不是测试创作工具，而是让一个角色或一个互动世界真正可玩。

整体 UI 定义为：

> **应用级稳定骨架 + 游戏级角色体验 + 2.5D 舞台层次 + 事件驱动的戏剧性。**

---

## 1. 设计目标

### 1.1 必须实现

- 角色体验优先于功能菜单。
- 普通使用过程清楚、低负担、可长时间使用。
- 关键时刻具有记忆点和仪式感。
- Day / Night 是稳定的基础主题。
- 未来可以叠加用户自定义主题、角色体验皮肤和模式专属 UI。
- 角色切换功能作为当前项目的视觉与交互母版继续保留。
- 创作和使用可以在同一运行时内切换，而不是割裂成两个产品。
- 为 Live2D / 3D 模型预留舞台层，不让现有聊天布局成为未来扩展的阻碍。

### 1.2 明确不做

- 不把所有页面都做成后台管理系统。
- 不把所有页面都做成赛博朋克 HUD。
- 不把所有组件都做成胶囊或超大圆角。
- 不用持续漂浮、闪烁、发光来制造“高级感”。
- 不为了主题自由度允许用户破坏对比度、触控区域和基本导航。
- 不把 UI Studio 的复杂性直接暴露给普通使用流程。
- 不因为引入新架构而一次性重写现有业务功能。

---

## 2. Design DNA

### 2.1 稳态克制，事件张力，角色异质

界面视觉权重按以下比例控制：

```text
稳定交互骨架       约 80%
角色体验表达       约 15%
关键事件戏剧性     约 5%
```

这不是严格的数值限制，而是设计判断标准：

- 大部分时间，用户应该能够安静地阅读、输入和操作。
- 角色的颜色、材质、身份和状态可以改变界面气质。
- 只有进入角色、切换角色、状态变化、重要选择等事件才使用明显动效。

### 2.2 焦点式交互

角色切换功能体现了本项目最适合的交互语言：

```text
浏览 → 聚焦 → 查看 → 确认 → 进入体验
```

后续页面应优先使用“逐层揭示”和“焦点聚合”，而不是一开始平铺所有内容。

### 2.3 舞台而不是控制台

聊天、Galgame、RPG 和互动小说的主界面是体验舞台；设置、备份、API、编辑器是后台能力。

- 舞台层：可以有氛围、层叠、角色身份、特殊事件。
- 后台层：必须清楚、稳定、可预测。
- 创作层：在体验内部按需呼出，不作为普通用户的常驻负担。

---

## 3. 视觉风格定稿

| 维度 | 定稿方向 |
| --- | --- |
| 硬朗 / 圆润 | **中性偏硬朗，局部圆润** |
| 扁平 / 立体 | **有层次的扁平，接近 2.5D** |
| 拟物 / 非拟物 | **轻材质感，不做重拟物** |
| 霓虹 / 素雅 | **局部霓虹，霓虹只作为信号** |
| 应用 / 工具 / 游戏 | **游戏体验为主，工具能力隐藏其中** |
| 静态 / 动态 | **平时安静，关键时刻有戏剧性** |
| 统一 / 个性 | **交互骨架统一，角色表面可变** |

### 3.1 形状语言

- 普通表面使用 12～16 的中等圆角。
- 详情面板和大型弹窗使用 16～20 的圆角。
- 胶囊形状只用于标签、状态和少量短操作。
- 圆形主要用于头像、徽记和明确的圆形动作按钮。
- 卡片、面板和输入区域必须有清楚的边界，不使用一片无层次的圆角容器。
- 附近的嵌套表面遵守同心圆角原则：外层圆角应大于内层圆角加内边距。

### 3.2 材质语言

使用以下方式表达层级：

- 半透明表面
- 轻微背景模糊
- 低强度边框
- 柔和投影
- 中心焦点放大
- 局部遮罩和渐变

避免：

- 重阴影堆叠
- 所有组件都使用玻璃效果
- 真实金属、皮革、按钮等重拟物
- 大面积持续发光

### 3.3 霓虹规则

霓虹只出现在以下位置：

- 当前焦点
- 角色强调色
- 选中状态
- 关键按钮
- 状态变化
- 特殊转场
- scene / 模式专属表现

霓虹不能成为全局背景或所有边框的默认状态。

---

## 4. 主题架构

主题由四层组成：

```text
BaseTheme              Day / Night
    ↓
UserTheme              用户自定义全局主题
    ↓
RoleExperience         当前角色的体验表达
    ↓
ExperienceMode         Chat / Galgame / RPG / Novel / Scene
    ↓
ComponentState         normal / focused / pressed / disabled / error
```

### 4.1 BaseTheme：基础主题

Day / Night 只负责全局可读性、表面层次和基础色彩，不负责具体角色个性。

### 4.2 UserTheme：用户自定义主题

允许用户改变：

- 全局调色板
- 背景和渐变
- 字体家族
- 材质强度
- 边框和阴影
- 模糊和发光强度
- 动效强度

但必须经过安全范围校验，不能破坏文字对比度和触控区域。

### 4.3 RoleExperience：角色体验

允许当前角色影响：

- 强调色
- 身份层样式
- 消息表面风格
- 状态栏表现
- 角色徽记
- 背景处理方式
- 进入角色时的转场
- 动效强度

角色体验不应随意改变基础导航和基本操作位置。

### 4.4 ExperienceMode：体验模式

模式决定界面如何编排，而不是简单换一套颜色。

计划支持：

```text
chat                 普通角色聊天
opening              开场白体验
scene                角色专属场景 UI
extra_sticky         常驻角色挂件
galgame              立绘、对话框、选项、好感等
rpg                  状态、地图、背包、战斗、指令等
interactive_novel    叙事文本、分支、选择、章节等
```

---

## 5. Day / Night 基础方案

颜色为基础参考值，具体实现必须使用语义 Token，不允许在页面中直接散落色值。

### 5.1 Day

```text
canvas              #F4F2EE
surface             #FFFFFF
surfaceElevated     #FBFAF7
surfaceGlass        rgba(255,255,255,0.72)
textPrimary         #17191D
textSecondary       #6F747C
textMuted           #999EA6
outline             #D9D9D5
divider             #E7E5E1
accent              #5867D8
accentSoft          #E8EAFF
onAccent            #FFFFFF
scrim               rgba(0,0,0,0.42)
```

Day 的观感：

> 温和、清晰、接近纸面和创作台，不做纯白后台。

### 5.2 Night

```text
canvas              #0B0E13
surface             #131820
surfaceElevated     #1B212B
surfaceGlass        rgba(24,29,38,0.72)
textPrimary         #F2F4F8
textSecondary       #A5ACB8
textMuted           #747D8C
outline             #303846
divider             #242B35
accent              #9EA9FF
accentSoft          #282E50
onAccent            #10131A
scrim               rgba(0,0,0,0.52)
```

Night 的观感：

> 安静、深邃、适合进入角色，不使用纯黑和大面积高亮。

### 5.3 语义颜色

以下颜色不随页面风格随意变化：

```text
success             成功 / 完成
warning             警告 / 等待确认
danger              删除 / 失败 / 高风险
info                普通提示
focusRing           键盘焦点 / 可访问性焦点
```

角色强调色可以覆盖 `accent`，但不能覆盖 `danger`、`success` 的基本语义，除非有完整的对比度校验。

---

## 6. Design Tokens

### 6.1 间距

```text
space1      4
space2      8
space3      12
space4      16
space5      20
space6      24
space7      32
space8      40
```

页面布局优先使用这些 Token，不在页面中大量出现无法解释的 13、17、29 等间距。

### 6.2 圆角

```text
radiusSmall     8
radiusMedium    12
radiusLarge     16
radiusPanel     20
radiusPill      999
```

### 6.3 触控区域

- 普通交互控件最小命中区域：40×40。
- 主要按钮和高频操作：优先 44×44 或更大。
- 视觉图标可以小于命中区域，但命中区域不能互相重叠。
- 角色切换中的播放按钮继续保留足够大的确认区域。

### 6.4 字体层级

```text
display      28 / 34       仅用于重要身份或模式标题
headline     22 / 28       页面标题
title        18 / 24       卡片和面板标题
body         15 / 22       主体阅读文本
label        13 / 18       控件标签
caption      12 / 16       辅助信息
```

- 聊天正文优先保证阅读，不使用过度装饰字体。
- 角色专属字体只能用于身份标题、章节标题和少量装饰文字。
- 动态数值、状态、计时器使用等宽数字或等宽数字特性，避免跳动。

### 6.5 动效

```text
quick         140ms
normal        240ms
emphasis      360ms
```

建议曲线：

```text
普通反馈      easeOut
进入          easeOutCubic
退出          easeInCubic
聚焦          easeOutBack（谨慎使用）
拖动          直接跟手，不使用延迟动画
```

规则：

- 进入可以有透明度 + 小幅位移 + 可选轻微模糊。
- 退出要比进入短且安静。
- 交互动画必须可以被下一次操作打断或重新定向。
- 默认不使用持续循环动画。
- 支持关闭或降低动效。

---

## 7. 体验运行时层

为了适配未来的 Live2D / 3D 和不同游戏模式，体验页面按舞台层组织：

```text
WorldLayer          背景、地点、天气、场景氛围
AtmosphereLayer     粒子、光、雾、渐变、特殊效果
AvatarLayer         头像、立绘、Live2D、3D 模型
NarrativeLayer      对话、旁白、章节、消息流
InteractionLayer    输入、选项、按钮、状态操作
SystemLayer         返回、设置、通知、加载、错误
CreatorOverlay      运行中的编辑和调试入口
```

当前聊天页可以先映射为：

```text
背景图              WorldLayer
scene / opening     NarrativeLayer + InteractionLayer
角色头像            AvatarLayer 的简化形态
输入栏              InteractionLayer
聊天设置            SystemLayer
UI 编辑入口         CreatorOverlay 的未来实现
```

未来增加 Live2D / 3D 时，优先新增 `AvatarLayer` 实现，不应重写整个聊天页。

---

## 8. 页面与信息架构

### 8.1 体验入口

首页的第一优先级不是列出所有功能，而是让用户继续体验：

```text
继续上次体验
当前角色 / 当前世界
最近使用的角色
体验模式入口
角色库 / 世界书库
```

API、备份、Prompt 和创作工具属于次级或后台入口。

### 8.2 角色切换

角色切换轮盘是项目的视觉母版，保留以下特征：

- 弧形角色卡排列
- 中心焦点
- 拖动和惯性
- 吸附聚焦
- 详情渐进展开
- 模糊背景层
- 明确的最终确认按钮

后续可以增强与聊天页之间的 Hero / 身份转场，但不能把它退化成普通列表。

### 8.3 聊天运行时

聊天页的优先级：

```text
角色身份和场景
    > 对话阅读
    > 当前状态
    > 输入和选择
    > 设置和管理
```

聊天页不应该出现长期占据屏幕的复杂工具栏。工具和创作入口按需呼出。

### 8.4 后台页面

角色编辑、世界书、API、备份和 UI Studio 保持更强的可读性和操作效率：

- 降低装饰密度
- 保持一致的表单和列表组件
- 使用统一的 Token
- 不强行套用聊天页的玻璃和霓虹效果

---

## 9. 组件规则

### 9.1 Surface

所有卡片、面板、弹窗和输入区域使用语义表面：

```text
surface
surfaceElevated
surfaceGlass
surfaceInteractive
```

不允许每个页面自行选择白色、灰色或黑色作为背景。

### 9.2 Button

按钮分为：

```text
primary       主要确认
secondary     次要操作
text          低强调操作
danger        删除、清空等高风险操作
icon          小型工具操作
```

主要按钮必须有：

- normal
- pressed
- disabled
- loading
- focus

状态变化使用颜色、透明度、轻微缩放或阴影变化表达，不使用夸张跳动。

### 9.3 Card

角色卡、世界书卡和背景卡可以有封面，但信息层级必须固定：

```text
封面 / 视觉识别
角色或条目名称
一行辅助信息
主要动作
```

角色卡可以有更强的层次和阴影；普通设置卡不使用同等强度的视觉效果。

### 9.4 Overlay / Dialog

弹层必须明确属于以下一种：

- 信息确认
- 选择
- 详情
- 编辑
- 运行时舞台

不把多个职责混在一个巨大弹窗中。

### 9.5 图片

图片边缘使用中性内描边，避免在浅色表面上融掉；不使用与品牌色绑定的图片边框。

---

## 10. 角色体验预设

为避免每个角色都完全自定义导致视觉失控，先提供有限的体验预设：

### Daily：日常型

- 温和色调
- 普通卡片和轻量圆角
- 很少的发光和转场
- 适合长时间聊天

### Dossier：档案型

- 细边框和标签
- 编号、章节、状态信息
- 更硬朗的排版
- 适合调查、世界观、跑团

### Signal：信号型

- 冷色强调
- 小面积发光
- 信号线和状态脉冲
- 适合系统、科幻、AI 角色

### Stage：舞台型

- 更明显的背景层和角色层
- 进入和退出有仪式感
- 对话和选择占据舞台中心
- 适合 Galgame、互动小说和重要剧情

预设共享相同的导航、返回、输入和基础控件位置，只改变角色表现层。

---

## 11. Flutter 实现框架

### 11.1 运行时主题

使用 Flutter 原生主题承载组件基础样式，并通过 `ThemeExtension` 扩展项目语义：

```text
ThemeData
  ├── ColorScheme
  ├── TextTheme
  ├── AppThemeTokens
  ├── AppSurfaceTokens
  ├── AppMotionTokens
  └── AppEffectTokens
```

自定义主题的持久化数据不能直接保存 `ThemeData`，应使用单独的可序列化规格：

```text
AppThemeSpec
├── id
├── name
├── baseMode: day / night
├── palette
├── typography
├── effects
├── motion
└── schemaVersion
```

### 11.2 推荐目录

后续可新增：

```text
lib/shared/theme/
  app_theme.dart
  app_theme_tokens.dart
  app_theme_spec.dart
  app_theme_manager.dart
  day_theme.dart
  night_theme.dart
  role_experience_profile.dart
```

功能模块逐步向以下形式迁移：

```text
lib/features/
  chat/
  character/
  world_book/
  background/
  experience/
  ui_studio/
```

当前项目仍可保留 Provider，先完成主题抽离和组件迁移；后续再按 Manager / Services / Views 逐步引入 flutter_it 架构，不为主题改造强行重写全部状态管理。

### 11.3 状态管理边界

- `ThemeManager`：当前 Day / Night、自定义主题、动效偏好。
- `CharacterManager`：当前角色和角色切换状态。
- `ExperienceManager`：当前体验模式、场景和运行时状态。
- `Services`：数据库、文件、API、系统能力，不直接改变 UI 状态。
- `Views`：读取 Manager，负责呈现和用户交互。
- `UI Engine`：作为运行时渲染和交互层，不直接承担数据库职责。

---

## 12. 实施顺序

### Phase 0：现状清理

- 统计页面中直接使用的 `Colors.*`。
- 统计散落的 `BorderRadius`、间距和阴影。
- 标记聊天页、角色切换、UI Engine 中已有的优秀视觉模式。
- 不改变业务行为。

### Phase 1：主题基础

- 在 `MaterialApp` 配置 Day / Night `ThemeData`。
- 增加 `ThemeExtension<AppThemeTokens>`。
- 建立间距、圆角、字体、动效和表面 Token。
- 先迁移 AppBar、按钮、输入框、ListTile、Dialog。

### Phase 2：通用组件

- 建立 AppSurface、AppButton、AppCard、AppDialog、AppSection。
- 统一命中区域、焦点、禁用和加载状态。
- 首页、设置页、角色库优先迁移。

### Phase 3：角色体验

- 保持角色切换轮盘交互逻辑。
- 提取角色身份层和角色强调色。
- 迁移聊天页的背景、蒙版、消息表面和状态栏。
- 将聊天页的硬编码视觉参数替换为 Token。

### Phase 4：体验模式

- 统一 opening / scene / extra_sticky 的舞台层。
- 为 Galgame、RPG、互动小说预留模式接口。
- 不提前实现所有模式，只保证层和导航不会阻碍扩展。

### Phase 5：创作融合

- 增加运行时 CreatorOverlay 概念。
- 支持从体验页面进入编辑，再返回当前体验。
- 逐步让 UI Studio 与运行时共享组件和主题 Token。

### Phase 6：Avatar Layer

- 先定义 AvatarLayer 的布局和生命周期。
- 后续接入 Live2D。
- 再扩展 3D 模型、镜头和表情状态。

---

## 13. 验收标准

### 视觉

- Day / Night 下主要页面结构和语义保持一致。
- 页面中不再大面积直接使用 `Colors.white`、`Colors.black`、`Colors.grey`。
- 普通页面不会被玻璃、阴影和霓虹淹没。
- 角色切换仍然是最有记忆点的交互之一。
- 角色个性可以变化，但不会破坏阅读和导航。

### 交互

- 主要操作命中区域不小于 44×44。
- 面板、弹窗和角色切换动画可以连续操作和中断。
- 进入、退出和确认的动效语义清楚。
- 没有必要的循环动画。
- 支持降低或关闭动效。

### 架构

- 自定义主题可以序列化、导入和导出。
- 页面通过语义 Token 获取视觉值。
- 角色体验和全局主题可以独立变化。
- ExperienceMode 不与 ChatPage 的具体布局硬编码绑定。
- UI Engine 不直接访问业务数据库。

### 扩展

- 新增一个角色体验预设不需要修改所有页面。
- 新增 Galgame / RPG 模式不需要重写基础主题。
- 新增 Live2D / 3D 只需要实现 AvatarLayer，不需要推翻聊天运行时。

---

## 14. 最终设计原则

1. **体验是产品，创作是能力。**
2. **角色是视觉变化的主要来源，而不是全局主题到处变化。**
3. **基础主题负责耐看，自定义主题负责个性，Scene UI 负责特殊。**
4. **平时保持安静，关键时刻才制造戏剧性。**
5. **交互骨架稳定，表现层可以异质。**
6. **角色切换是设计母版，不是需要被普通列表替代的旧功能。**
7. **先建立运行时和主题框架，再增加更多游戏模式。**
8. **任何视觉效果都必须服务于焦点、叙事或状态。**

> **最终目标：让用户感觉自己是在进入和经历一个角色世界，而不是在操作一个功能很多的工具。**
