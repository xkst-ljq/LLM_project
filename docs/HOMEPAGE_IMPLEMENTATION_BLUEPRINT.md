# LLM Project 主页实现蓝图

> **版本：Home Blueprint v1.1**
> **状态：实现前定稿（已区分现有能力与新增任务）**
> **适用范围：** 主页、角色体验入口、角色选择轨道、模块轨道、设置侧滑、进入聊天转场

---

## 0. 实现目标

主页不是功能目录，而是进入 AI 角色体验的第一块舞台。

最终结构：

```text
HomeExperienceShell
├── CurrentRoleEntry       当前角色色块 / 进入聊天
├── AvatarStage            Live2D / 3D 角色预留区
├── ModuleRail             角色库 / 世界书库 / 背景图库 / UI 模组库
├── RoleSelectionRail      点击角色封面后出现的横向角色色面
└── SettingsSideStage      从右侧边缘侧滑出现的设置页
```

核心交互：

```text
角色封面 → 局部角色选择轨道
进入箭头 → 进入聊天
右侧边缘侧滑 → 设置页
模块色面 → 对应功能页面
```

---

## 0.1 与现有项目的边界

这份蓝图不把已有能力当成新功能重新实现。以下能力已经存在，后续只做回归验证和必要的兼容修正：

- 主页 / 聊天页已有右侧设置页侧滑；
- 主页已有设置教程和侧滑手势；
- 聊天页已有角色切换轮盘；
- ChatPage 已有 scene、opening、extra_sticky 等运行层；
- UI Engine 已有角色专属 UI 运行能力。

后续任务只分为三类：

```text
保持：已有功能不能因为主页重构而回归
新增：这次主页设计真正需要实现的能力
预留：为未来模式或模型接入保留接口，但本轮不做
```

蓝图中再次写到已有能力，是为了标明它们是**不可回归的约束**，不是要求重新设计一遍。

---

## 1. 已确定的产品规则

### 1.1 角色卡的两个点击区域

角色卡必须拆成两个语义不同的区域：

```text
封面区域       打开最近角色选择
右下角箭头     进入当前角色聊天
```

点击封面不能直接进入聊天。

### 1.2 角色选择轨道

角色选择不使用普通弹窗、卡片网格或上下堆叠。

规则：

- 使用主页当前角色色块的同一几何形状。
- 选择层不再有额外的大背景色块托底。
- 选中色块保持主页角色卡的原始尺寸。
- 其他色块按比例缩小。
- 初始顺序从左到右为：最新聊天 → 更早聊天。
- 选中旧角色后，旧角色色块移动到主页原始位置。
- 第一次点击只聚焦角色。
- 再次点击当前聚焦色块，才确认换到主页。
- 选择过程中不显示进入聊天箭头。
- 点击局部蒙版外部取消选择，不使用关闭 `×` 图标。

### 1.3 设置页（已有能力，保持不变）

设置继续使用项目现有的右侧边缘侧滑，不新增固定右上角“更多”入口。

```text
从右侧边缘开始拖动
→ 整个主页舞台跟手侧移
→ 右侧设置页同步露出
```

设置是体验舞台旁边的后台空间，不是覆盖在角色上的普通抽屉。

### 1.4 当前模块范围

主页当前只实现：

```text
角色库
世界书库
背景图库
UI 模组库
```

体验模式和体验档案暂不放入主页模块轨道，等对应功能真正设计完成后再加入。

---

## 2. 页面状态模型

主页不能只有一个静态布局，需要明确区分状态：

```dart
enum HomeState {
  loading,
  empty,
  readyToStart,
  resume,
  selectingRole,
  error,
}
```

### 2.1 `loading`

读取以下数据时显示轻量占位：

- 当前角色
- 最近聊天角色
- 角色封面
- 模块预览数据

不使用全屏阻塞 Loading。

### 2.2 `empty`

没有任何角色时：

- 当前角色色块显示“开始第一次体验”。
- AvatarStage 显示空舞台和低频呼吸光。
- 角色库模块显示“从这里开始”。
- 点击当前色块或角色库进入 `CharacterLibraryPage`。
- 不显示“继续聊天”。

### 2.3 `readyToStart`

已有角色但没有聊天历史：

```text
开始体验
```

而不是“继续体验”。

### 2.4 `resume`

有当前角色和聊天历史：

```text
继续体验
```

角色卡底部可以显示：

```text
距上次聊天：根据真实消息时间计算
```

这类记忆信息属于聊天入口状态，不在角色选择轨道中重复展示。

### 2.5 `selectingRole`

点击角色封面后进入局部选择状态：

- 主页面保持在后方。
- 只为角色卡所在的横向区域建立蒙版。
- 角色轨道覆盖在原始色块位置。
- 选择完成或取消后恢复主页状态。

---

## 3. 数据来源和模型

第一阶段不新增复杂数据库表，优先使用现有数据：

- `CharacterCard`
- `cardImagePath`
- `DatabaseService.getAllCharacters()`
- 当前角色 ID
- 当前角色消息记录

主页需要一个轻量的运行时快照：

```dart
class HomeRoleSnapshot {
  const HomeRoleSnapshot({
    required this.character,
    required this.lastActiveAt,
    this.lastMessagePreview = '',
  });

  final CharacterCard character;
  final DateTime? lastActiveAt;
  final String lastMessagePreview;
}
```

最近角色排序：

```text
有聊天记录的角色：按最后消息时间倒序
没有聊天记录的角色：放在后面，按角色创建 / 数据顺序
```

以后可以由 `CharacterManager` 或 `ExperienceManager` 提供，不让 View 直接拼接数据库查询。

---

## 4. Flutter 组件树

第一阶段建议保留 `MainMenuPage` 作为路由入口，内部逐步拆分：

```text
MainMenuPage
└── HomeExperienceShell
    ├── HomeBackgroundLayer
    ├── HomeBrandMark
    ├── HomeThemeButton
    ├── CurrentRoleEntry
    │   ├── RoleCoverHitArea
    │   ├── RoleCoverSurface
    │   ├── RoleIdentityText
    │   └── EnterChatButton
    ├── AvatarStage
    │   ├── StageLight
    │   ├── StageOrbit
    │   └── AvatarHost       // 未来 Live2D / 3D
    ├── ModuleRail
    │   └── ModulePreviewTile
    ├── RoleSelectionLayer
    │   ├── LocalRowMask
    │   └── HorizontalRolePlaneRail
    └── SettingsSideStage
```

推荐的后续目录：

```text
lib/features/home/
  pages/home_page.dart
  widgets/home_experience_shell.dart
  widgets/current_role_entry.dart
  widgets/avatar_stage.dart
  widgets/module_rail.dart
  widgets/role_selection_layer.dart
  widgets/settings_side_stage.dart
  manager/home_manager.dart
  model/home_role_snapshot.dart
  model/home_module_entry.dart
```

迁移期间可以保留：

```text
lib/pages/main_menu_page.dart
```

让它只负责包装和导航，避免一次性重写整个主页。

---

## 5. ModuleRail 设计

### 5.1 模块外观

每个模块使用同一种几何语言：

```text
上方：图标 + 模块标题 + 进入箭头
下方：内部简短预览
```

示例：

```text
角色库
人物图标 人物图标 人物图标 · 3 个角色
```

```text
世界书库
设定线条 · 3 种世界书
```

```text
背景图库
图片图标 图片图标 图片图标 · 6 个背景
```

```text
UI 模组库
SCENE · OPENING · 4 个模组
```

### 5.2 滚动行为

- 使用正常垂直滚动。
- 平行四边形或斜切只用于视觉外形。
- 不实现真正的斜向拖动。
- 不与右侧设置侧滑争抢水平手势。
- 模块新增时自动向下延展。
- 第一批模块不做持续漂浮，只使用一次性进入和按压反馈。

### 5.3 模块职责

```text
角色库      Navigator.push(CharacterLibraryPage)
世界书库    Navigator.push(WorldBookLibraryPage)
背景图库    Navigator.push(BackgroundLibraryPage)
UI 模组库   Navigator.push(UIAssetGallery / UIStudioPage)
```

视觉上可以使用形变进入，但逻辑上仍然使用正常 Navigator 页面栈。

---

## 6. 角色选择实现

### 6.1 打开

点击 `RoleCoverHitArea`：

```text
记录主页角色卡 RenderBox 坐标
计算设备内容坐标
定位 RoleSelectionLayer
打开局部蒙版
```

不能用固定 viewport 坐标，必须使用实际设备和角色卡的 RenderBox 位置，保证：

- 真机适配；
- 桌面预览手机框适配；
- 安全区变化适配；
- 旋转和不同尺寸适配。

### 6.2 轨道

```text
HorizontalRolePlaneRail
```

每个角色色面：

- 当前选中：使用主页角色卡的原始宽高。
- 非选中：保持宽高比，缩小到约 70%。
- 最新角色初始位于最左侧。
- 选中其他角色后，使用 FLIP / AnimatedBuilder 让它移动到左侧原始槽位。
- 不显示进入聊天箭头。

### 6.3 选择确认

```text
点击非当前色面
→ 只更新 pickerSelection
→ 色面移到左侧并高亮
→ 主页 currentRole 不变

再次点击当前高亮色面
→ currentRole 更新
→ 关闭选择层
→ 主页角色卡替换
→ 不播放主页首次进入动画
```

取消选择：

```text
点击局部蒙版外部
→ 丢弃 pickerSelection
→ 恢复主页 currentRole
```

---

## 7. 动画蓝图

### 7.1 首次进入主页

```text
品牌状态灯
→ 当前角色卡
→ AvatarStage 光晕
→ ModuleRail 模块逐项出现
```

仅首次进入或主页真正创建时播放。

### 7.2 角色卡呼吸

- 封面内部：约 16 秒低幅缩放 / 平移。
- 不移动文本和箭头。
- 角色切换后可以重置封面呼吸，但不能重播整页入口动画。

### 7.3 AvatarStage

- 光晕：5～7 秒呼吸。
- 轨道：9 秒低幅变化。
- 角色切换：一次短脉冲。
- 未来接入 Live2D / 3D 后，由 AvatarLayer 接管待机动作。

### 7.4 进入聊天

```text
只由 EnterChatButton 触发：
角色封面扩展
→ 角色身份信息移动
→ AvatarStage 淡出
→ ChatPage / Scene UI 进入
```

角色选择、换角色和主题切换不能重复播放这一段入口动画。

### 7.5 设置侧滑（已有能力，作为回归项）

- 保留现有的右侧边缘手势和整页侧移行为。
- 主页舞台和设置页必须继续跟手移动。
- 到达阈值后吸附，反向拖动关闭，点击遮罩关闭。
- 主页重构时不得把它替换成固定抽屉或右上角“更多”按钮。
- 只有在坐标、命中测试或动画同步出现回归时才修正实现。
- 不使用右上角的“更多设置”作为主入口。

---

## 8. 主题接入

基础主题已经由以下文件提供：

```text
lib/shared/theme/app_theme.dart
lib/shared/theme/app_theme_manager.dart
lib/shared/theme/app_theme_tokens.dart
```

主页组件只读取语义 Token：

```text
surface
textPrimary
outline
accent
scrim
stageColor
```

不得在主页组件内直接散落：

```dart
Colors.white
Colors.black
Colors.grey
Colors.blue
```

角色封面和角色强调色属于 `RoleExperience` 层，不能破坏 Day / Night 的文字对比和触控区域。

---

## 9. 分阶段实施

### Phase 1：主页真实数据

- 将原型中的角色数据替换为 `CharacterCard`。
- 读取当前角色。
- 读取最近消息时间。
- 读取角色封面。
- 判断 `empty / readyToStart / resume`。

### Phase 2：主页组件拆分

- 从 `MainMenuPage` 提取 `HomeExperienceShell`。
- 提取 `CurrentRoleEntry`。
- 提取 `AvatarStage`。
- 提取 `ModuleRail`。
- 保持现有导航行为不变。

### Phase 3：角色选择

- 实现 RenderBox 对齐。
- 实现局部蒙版。
- 实现水平色面轨道。
- 实现选择聚焦和二次确认。
- 实现取消恢复。

### Phase 4：进入聊天转场

- 从角色卡封面建立 Hero / 自定义 Route。
- 连接 `ChatPage`。
- 保留 scene / opening 的现有运行逻辑。
- 确保选择角色后不重复播放主页入场动画。

### Phase 5：现有设置侧滑回归

- 不重新设计设置侧滑。
- 验证主页拆分后主页 / 聊天页的侧移行为仍然一致。
- 只处理坐标、命中测试、阈值和动画同步回归。

### Phase 6：无障碍和性能

- 所有图标保持 44×44 左右的命中区。
- 支持减少动效。
- 对 AvatarStage 和复杂封面使用 RepaintBoundary。
- 避免动画期间整棵主页树 setState。
- 增加主页状态、角色选择、返回和动画回归测试。

---

## 10. 验收标准

### 空状态

- 没有角色时不显示假的当前角色。
- 角色库模块明确提示“从这里开始”。
- 不会直接显示“继续聊天”。

### 角色选择

- 点击封面不进入聊天。
- 选中色面与主页原始位置对齐。
- 非选中色面等比例缩小。
- 选中旧角色时不刷新主页入场动画。
- 二次点击当前色面才确认替换。
- 点击局部蒙版外部可以取消。

### 进入聊天

- 只有箭头按钮进入。
- 封面可以使用角色卡封面。
- 转场可反向返回或有安全降级动画。

### 模块

- 模块标题和图标位于上方。
- 内部预览位于下方。
- 世界书显示世界书数量，而不是条目数量。
- 模块滚动为垂直滚动。
- 新模块可以继续向下添加。

### 设置

- 设置由右侧边缘侧滑打开。
- 主页和设置页保持空间上的邻接关系。
- 不依赖常驻“更多”按钮。

---

## 11. 当前不实现

本轮主页实现暂不包含：

- 体验模式模块；
- 体验档案模块；
- Live2D 真实接入；
- 3D 模型真实接入；
- 全量自定义主题编辑器；
- 完整的 flutter_it 架构迁移；
- 新增数据库表。

这些能力在主页骨架稳定后分别接入。
