# 子页面 UI 优化方案（对齐主页风格）

> 结论先行：**要优化，但不平均用力。** 主页（`MainMenuPage` / `HomeExperiencePage`）已经建立了完整的视觉体系（语义化设计令牌、玻璃质感、过渡与导览），但多数子页面仍是旧的硬编码样式，造成"主页精致、子页跳变"的割裂感。本方案按**曝光频率 × 视觉落差**分三档推进，核心手段是**把子页面接入已有主题令牌**，而非推翻重画。

---

## 1. 目标与原则

对齐主页风格，具体落实为以下可复用规则（所有子页面统一遵守）：

1. **颜色**：一律从 `AppThemeTokens.of(context)` 取，禁止硬编码 `Color(0x…)` / `Colors.xxx`。
2. **背景**：页面根节点用 `SubPageBackdrop`（Day / Night 自动切换，含舞台光晕与 canvas 体系）。
3. **弹窗 / 底部抽屉**：用 `SubPageBlurBackdrop`（毛玻璃 + `radiusPanel` + 描边）。
4. **卡片 / 列表项**：`surfaceElevated` 或 `surfaceGlass` 底 + `radiusMedium/radiusLarge` + `outline` 描边 + `elevationLow`。
5. **AppBar**：统一为透明/融入背景的样式（去掉默认 Material 的突兀底色与阴影），返回键风格一致。
6. **间距 / 圆角 / 文字色**：用 `space*`、`radius*`、`textPrimary/textSecondary/textMuted`。
7. **空状态 / 加载**：统一占位组件，风格与主页一致。

> 复杂编辑器页面（`character_assembly_page`、`ui_studio_page`）只做"接入令牌 + 不破坏功能"，不重设计、不做大改。

---

## 2. 现状盘点（已实测统计）

| 页面 | 主题令牌引用 | 硬编码颜色 | 观感 | 判定 |
|---|---|---|---|---|
| `main_menu_page` / `home_experience_page` | 高 | 低 | 精致、成体系 | ✅ 已完成（基准） |
| `chat_page` | 17 | ~101 | 旧、杂乱 | 🟢 核心区已令牌化（气泡/列表/输入栏） |
| `character_library_page` | 2 | ~18 | 旧 | 🔴 第一梯队 |
| `world_book_library_page` | 0 | ~33 | 旧 | 🔴 第一梯队 |
| `background_library_page` | 5 | ~105 | 旧 | 🟠 第二梯队 |
| `prompt_settings_page` | 1 | ~8 | 旧 | 🟠 第二梯队 |
| `user_settings_page` | 0 | 0 | 简单 | 🟠 第二梯队 |
| `backup_restore_page` | — | — | 旧 | 🟠 第二梯队 |
| `api_config_page` / `api_config_edit_page` | — | — | 旧 | 🟠 第二梯队 |
| `settings_page` | — | — | 极简雏形 | 🟠 第二梯队 |
| `character_assembly_page`（含 logic_* 系列） | 部分 | 多 | 复杂编辑器 | ⚪ 第三梯队（仅接轨） |
| `ui_studio_page`（含 editors/*） | 部分 | 多 | 复杂编辑器 | ⚪ 第三梯队（仅接轨） |
| `tutorial_home_page` | — | — | 简单 | ⚪ 第三梯队（仅接轨） |

---

## 3. 共享设施建设（地基，先做这一层）

改造前先补齐/固化以下设施，让各页面"接上就能对齐"：

- **A. 主题令牌完整性**：确认 `app_theme_tokens.dart` 已覆盖所需角色（canvas / surface / surfaceElevated / surfaceGlass / outline / divider / textPrimary / textSecondary / textMuted / accent / accentSoft / radius* / elevation* / space* / stage）。缺失角色在令牌层补，不要在各页面 `withValues` 硬造。
- **B. 统一页面脚手架 Widget**（可选，推荐新建）：一个 `AppSubPage` 包装，内部自动包 `SubPageBackdrop` + 统一 AppBar + 安全区，减少各页重复。
- **C. 统一列表项 / 卡片组件**：`SurfaceCard`（surfaceElevated + radiusMedium + outline + elevationLow），供角色库 / 世界书 / 背景库复用。
- **D. 统一空状态 / 加载 / 空按钮**组件，风格与主页对齐。
- **E. 代码规范辅助**：把"禁止硬编码颜色"写进 `.cursorrules` / `analysis_options.yaml` 的 lint，防止回归。

---

## 4. 分页改造清单

### 第一梯队（优先：高频访问 + 落差最大）

**① `chat_page.dart`（核心聊天场景，落差最大）— 核心区已完成 ✅**
- ✅ 已完成：消息气泡（用户 `accentSoft` / 助手 `surface`+描边，Night 统一 `surfaceElevated`）、
  输入栏、角色名胶囊、Tokens 标签、头像占位、功能图标、气泡正文颜色全部令牌化。
- 后续可选：背景层接入 `SubPageBackdrop`；右侧聊天设置面板；扇形角色切换面板；扩展菜单。
- 风险点：聊天是核心路径，改完需重点回归发送、滚动、键盘避让。

**② `character_library_page.dart`（角色库）**
- 列表项套用统一 `SurfaceCard`；背景换 `SubPageBackdrop`。
- AppBar 统一为透明融入式；按钮/弹窗用 `SubPageBlurBackdrop`。

**③ `world_book_library_page.dart`（世界书）**
- 0 处令牌引用，33 处硬编码 → 全量接入令牌；卡片与列表项统一。

### 第二梯队（跟随对齐，工作量中等）

**④ `background_library_page.dart`**：硬编码最多（~105），重点是把颜色/圆角/间距接入令牌；注意背景缩略图与预览的对比度。

**⑤ `prompt_settings_page.dart` / `user_settings_page.dart` / `api_config_page.dart` / `api_config_edit_page.dart`**：表单类页面，统一输入框、AppBar、背景。

**⑥ `backup_restore_page.dart`**：统一卡片与按钮层级。

**⑦ `settings_page.dart`**：目前是极简雏形，可顺势对齐主页（该页与 `settings_menu_page` 需确认哪份在用，避免重复维护）。

### 第三梯队（复杂编辑器，只做接轨，不重设计）

**⑧ `character_assembly_page` / `logic_*` 系列**：替换硬编码颜色为令牌、背景接入，**保持布局与交互不变**。
**⑨ `ui_studio_page` / `editors/*`**：同上，仅令牌接轨；编辑器是高改动风险区，谨慎最小改动。
**⑩ `tutorial_home_page`**：简单接轨。

---

## 5. 落地顺序与工作量

建议按 地基 → 第一梯队 → 第二梯队 → 第三梯队 推进，每层完成后整体截图对比：

| 阶段 | 内容 | 相对工作量 |
|---|---|---|
| 0 | 共享设施（A–E） | 小 |
| 1 | 第一梯队 3 页 | 中（含核心回归） |
| 2 | 第二梯队 ~5 页 | 中 |
| 3 | 第三梯队 ~3 页（仅接轨） | 小–中 |

每一页改动遵循：**先纯接入令牌（色/圆角/间距）→ 截图自检 → 再补背景/弹窗等结构件**，把"对齐"和"重设计"分开，降低风险。

---

## 6. 验收标准

- `grep` 检查目标页面：`Color(0x` / `Colors.` 命中降至 0（令牌化完成）。
- 目标页面全部使用 `SubPageBackdrop`（或统一脚手架）作背景。
- Day / Night 两套主题下截图对比无明显的灰阶/色块断裂。
- 交互（聊天发送、库的增删改查、编辑器保存）回归通过。
- 桌面 / 移动宽度下无溢出、无布局回归。
