# UI engine 知识库（转译 AI 与用户教程的通用底稿）

> 本文件把 UI engine 的**全部可编写面**一五一十地列出来，
> 作为两用底稿：
>   1. **转译 AI 的知识库** —— 后续注入 AI，让它知道能写什么；
>   2. **UI engine 使用教程** —— 供用户学习如何创作 UI。
>
> 覆盖：组件原语 · 通用外观 · 页面 · 联动器 · 数据通道 · 手势 · 模式。
> 状态：`🟡 持续完善中`

---

## 0. 结构总览

UI（`ui_assembly`）的基本结构：

```
UIAssembly（方案）
├── mode            页面模式（scene/opening/extra_companion/extra_sticky）
├── pcbWidth/Height 画布尺寸（设计坐标系）
├── pcbColor/Round   画布背景色 / 圆角
└── pages[]          页面列表
    └── page（type: base/overlay）
        ├── elements[]   元件
        │   ├── offset{x,y} / size{width,height} / rotation
        │   ├── layerIndex / parentSurfaceId
        │   └── module（组件实例，见 §1）
        ├── gestures[]    页面手势（滑动切页等）
        └── propertyOverrides[]  复合件实例覆写
```

---

## 1. 组件原语（21 种）

每个元件都是一个 `module`，带 `type` + `properties`（该类型专属属性）。

### 1.1 通用外观字段（所有组件都有）

| 字段 | 类型 | 说明 |
|---|---|---|
| `material` | int 枚举 | 0=无 / 1=solid / 2=gradient |
| `shape` | int 枚举 | 0=方形 / 1=圆角 / 2=胶囊 / 3=圆形 |
| `color` | ARGB int | 主色（`0xFFRRGGBB`） |
| `opacity` | double | 不透明度 0~1 |
| `borderRadius` | double | 圆角半径 |
| `offset{x,y}` | double | 画布内坐标 |
| `size{width,height}` | double | 尺寸 |
| `rotation` | double | 旋转角度（度） |
| `layerIndex` | int | 层级（越大越靠上） |
| `parentSurfaceId` | String | 所属容器面 id |
| `layoutLocked` / `sealed` | bool | 锁定 / 封存（防误拖/防改） |
| `__anim` | Map | **动画配置**（见 §1.5 动画系统） |
| `boundVariable` | String | 绑定到会话变量（`{{var.xxx}}` 注入 Prompt） |
| `statusFieldMirrorKey` | String | 镜像映射到置顶状态栏字段（只读显示） |
| `displayExpression` | String | 联动显示表达式（如 `{{current}} / {{max}} HP`） |
| `linkedSources` | List | 联动源 id 列表（组件内 scope） |

### 1.2 显示类组件

| 组件 type | 专属属性 | 说明 |
|---|---|---|
| `surface` / `base_box` | —（走通用外观） | 底板 / 面板容器 |
| `text` | `text` / `fontSize` / `textAlign`(left·center·right) / `overflow`(ellipsis·scroll) / `richText`(bool) / `contentPadding` | 文本；scroll=长文滚动，richText=HTML/Markdown |
| `progress` | `min` / `max` / `current` / `progressShape`(bar·ring·capsule) / `strokeWidth` / `trackColor` | 进度条；current 可绑数据通道 |
| `line` | `thickness` / `lineStyle`(solid·dashed) | 分割线 |
| `indicator` | `dotSize` / 颜色 | 指示点 / 状态灯 |
| `image` | `imageSource` / `assetPath` / `url` / `fit`(cover·contain·fill) / `borderRadius` | 图片（本地资产 / 内联 / 网络） |
| `primitive_art` / `surface_art` / `light_effect` | 归一化图层 + 颜色/发光 | 装饰 / 光效（layer 归一化 0~1） |

### 1.3 交互类组件

| 组件 type | 专属属性 | 说明 |
|---|---|---|
| `button` | `sendsMessage`(bool) / `keyAction`(bool) / `text` | 点击热区；sendsMessage=点击发消息，keyAction=关键职责（scene=打开设置 / opening=确认关闭） |
| `input` | `placeholder` / `text`(默认) / `maxLength` / `multiline` / `textVerticalAlign` / `textHorizontalAlign` | 文本输入框；回车/失焦提交 `committedValue` |
| `select` | `options`[{label,value}] / `current` | 下拉选择 |
| `switch` | `value`(bool) | 开关 |
| `slider` | `min` / `max` / `current` / `step` / `knobShape` / `knobSize` / `thumbColor` / `active·inactiveTrackColor` | 滑块 |

### 1.4 逻辑类组件

| 组件 type | 专属属性 | 说明 |
|---|---|---|
| `linker` | `linker{scheme, sourceModuleId, targetModuleId, enabled, priority}` | 逻辑连线（见 §4） |
| `page_router` | `route{targetPageId, action, transition, durationMs}` | 页面路由（切页 / 打开叠加层） |
| `math_node` | 计算表达式 | 计算节点 |
| `timer` | 周期 / 动作 | 定时脉冲 |
| `message_flow` | `showUser` / `showAssistant` / `historyLimit` / `fontSize` / `user·assistantBubbleColor` / `bubbleRadius` / `richText` | 内嵌消息流 |

### 1.5 动画系统

动画配置在元件的 `__anim` 字段族，参数（时长/曲线/幅度）挂在**元件**上，
连线只负责「什么时候触发」（`event_to_animation`），也可由值变化自动播放。

**动画类型**（`ElementAnimationType`）：

| storageKey | 含义 | 建议时长 |
|---|---|---|
| `press` | 按压凹陷 | 150ms |
| `ripple` | 水波折射扩散 | 300ms |
| `flash` | 短暂高亮 | 300ms |
| `number_pop` | 数值跳动（先放大再回弹） | 260ms |
| `glow_pulse` | 发光脉冲（外发光呼吸） | 600ms |
| `particle_burst` | 粒子迸发 | 700ms |

**曲线**（`ElementAnimationCurve`）：easeInOut 平滑进出 / easeOut 快出慢停 /
easeIn 慢起快收 / linear 匀速 / bounceOut 弹跳 / elasticOut 回弹。

---

## 2. 页面

| 概念 | 说明 |
|---|---|
| 页面类型 | `base`（平级页）/ `overlay`（叠加层页，`parentPageId` 指向父页） |
| 页面切换 | `page_router` 的 `action`：`switch_base_page`（平级）/ `open_overlay`（打开叠加层） |
| 叠加层关闭 | 点击叠加层容器外空白 / `onDismissRequested` |
| 手势 | `gestures[]`：方向 + action + targetPageId |

### 叠加层（overlay）
- 叠加层页可指定**独立画布**（`pcbWidth/pcbHeight`），脱离主画布限制
- 首个 `surface`（`is_overlay_container: true`）作为容器面，成为该层边界
- 组件在容器面内=前台渲染，超出=后台

---

## 3. 数据通道（Data Channel）

让 LLM 能**读写**组件，实现「数据实时更新」。

```json
{
  "semanticLabel": "显示名",
  "semanticPath": "路径",
  "sourceComponentId": "组件id",
  "sourcePort": "端口(text/current/value...)",
  "targetKind": "status_field",
  "targetId": "字段id",
  "llmReadPolicy": "prompt",
  "llmWritePolicy": "suggest_delta | suggest_replace",
  "fieldType": "number | text"
}
```

**`targetKind`（写入目标类型，5 种）**：

| targetKind | 说明 |
|---|---|
| `status_field` | 置顶状态栏字段（注入 Prompt，LLM 可读写） |
| `session_var` | 会话变量（`{{var.xxx}}` 注入） |
| `card_entry` | 角色卡条目字段（group/entryId/fieldKey） |
| `local_ui_state` | 本地 UI 状态（不进入会话，仅界面内） |
| `user_profile` | 玩家档案（昵称/设定） |

| 写策略 | 说明 |
|---|---|
| `suggest_delta` | 数值：LLM 只返回增量，引擎 clamp(旧值+增量, min, max) |
| `suggest_replace` | 文本：LLM 返回新值整值替换 |

| 读策略 | 说明 |
|---|---|
| `prompt` | 值注入 Prompt 供 LLM 读取 |
| `ui_only` | 仅界面显示，不进 Prompt |

---

## 4. 联动器（linker scheme）

逻辑连线，表达「一个组件的事件/值 → 另一个组件的行为」。

### 4.1 页面 / 交互
| scheme | 作用 |
|---|---|
| `button_to_page_route` | 按钮 → 切页 / 打开叠加层 |
| `click_to_surface_press` | 按钮 → 表面按压动画 |

### 4.2 输入
| scheme | 作用 |
|---|---|
| `input_commit_to_text` | 输入提交 → 文本 |
| `input_live_to_text` | 输入实时 → 文本 |
| `input_submit_to_text_clear` | 提交后清空 |
| `input_to_progress` | 输入 → 进度 |
| `input_to_slider` | 输入 → 滑块 |
| `input_change` / `input_commit` | 输入事件源 |
| `click_to_input_clear` | 点击清空输入 |
| `input_length_to_indicator` | 输入长度 → 指示器 |
| `input_nonempty_to_button_enable` / `input_valid_to_button_enable` / `text_nonempty_to_button_enable` | 输入/文本非空才启用按钮 |
| `input_validity_to_indicator` | 输入有效性 → 指示器 |
| `input_value_to_select_filter` / `input_value_to_select_match` / `text_value_to_select_match` | 输入过滤/匹配下拉 |

### 4.3 开关 / 滑块 / 进度
| scheme | 作用 |
|---|---|
| `click_to_switch_toggle` / `_set_true` / `_set_false` | 点击切换/置位开关 |
| `click_to_slider_reset` | 点击重置滑块 |
| `slider_to_progress` / `slider_to_text` / `slider_commit_to_text` / `slider_commit_to_math_param` | 滑块 → 进度/文本/计算参数 |
| `bool_result_to_progress` / `bool_result_to_text` / `bool_to_text` | 布尔 → 进度/文本 |
| `progress_to_text` / `progress_to_math_param` / `progress_threshold_to_switch` / `progress_threshold_to_button_enable` | 进度 → 文本/计算/阈值控制 |
| `boolean_to_enabled` / `_frozen` / `_locked` / `_visible` / `_timer_running` | 布尔条件控制 |

### 4.4 下拉 / 选择
| scheme | 作用 |
|---|---|
| `select_to_text` | 下拉 → 文本 |
| `select_value_to_switch` | 下拉值 → 开关 |
| `select_value_to_surface_visible` | 下拉值 → 表面显隐 |
| `select` 选项 | `options: [{label, value}]` |

### 4.5 逻辑 / 数学 / 定时器
| scheme | 作用 |
|---|---|
| `click_to_math_trigger` | 点击触发计算 |
| `value_to_math_param` / `result_to_progress` / `result_to_text` / `sum_to_display` / `pool_to_allocation` | 值 → 计算参数 / 结果展示 / 配额分配 |
| `text_extract_to_math_param` | 文本提取 → 计算参数 |
| `name_to_text` | 名称 → 文本 |
| `timer_tick_to_math_trigger` / `timer_value_to_text` / `timer_tick_to_progress_increment` / `timer_tick_to_progress_decrement` / `timer_tick_to_switch_toggle` / `_set_true` / `_set_false` / `click_to_timer_toggle` / `_reset` | 定时器相关 |
| `event_to_animation` | 事件 → 动画 |
| `event_to_indicator` / `indicator_color_to_*` | 事件 → 指示器 / 指示器颜色控制 |

### 4.6 文本匹配
| scheme | 作用 |
|---|---|
| `text_match_to_switch` / `text_match_to_button_enable` | 文本匹配 → 开关/启用 |

---
---

## 5. 页面模式（mode）

| mode | 定位 | 特点 |
|---|---|---|
| `scene` | 场景 UI | 全屏接管聊天页，可多页、多面板 |
| `opening` | 开场白弹窗 | 开场全屏，确认后进入 |
| `extra_companion` | 伴生 UI | 内嵌最新 AI 气泡（≤212px 宽） |
| `extra_sticky` | 常驻 UI | 悬浮小窗，可折叠 |

### 5.1 语义角色（keyAction / sendsMessage）

| 概念 | 说明 |
|---|---|
| `keyAction: true` | 关键职责按钮。opening=「确认并关闭」；scene=「打开聊天设置」；extra_sticky=「折叠」 |
| `sendsMessage: true` | 发送消息按钮（仅 scene 支持，button/input 可标记） |
| `canMark` | 仅 button 可标记关键职责 |

---

## 6. 其它能力

### 6.1 文本高亮规则（TextHighlightRule）
正则匹配文本 → 着色 / 加粗 / 斜体（`regex` + `colorValue` + `bold` + `italic` + `enabled`）。只做样式，不替换文本。

### 6.2 状态栏字段（StatusBarField）
| 字段 | 说明 |
|---|---|
| `id` / `name` | 标识 / 显示名（name 也用于向 LLM 标识） |
| `type` | `number` / `text` |
| `initialValue` | 主支路初值（兜底） |
| `minValue` / `maxValue` | 数值量程 |
| `pinSide` | `none` / `left` / `right`（折叠条固定侧） |
| `owner` | `player` / `char` / `neutral`（Prompt 主语） |
| `branchInitialValues` | 各开场分支初值 |

### 6.3 数学节点（math_node）
运算（`operation` + 操作数）：`set` / `+` / `-` / `*` / `/`（除零兜底）/ 比较 `>` `<` `>=` `<=` `==`。与 `*_to_math_param` 联动器配合。

### 6.4 消息操作（message_action）
`regenerate` 重新生成 / `continueWrite` 继续写 / `edit` 编辑 / `delete` 删除——由 button 经 `button_to_message_action` 触发。

### 6.5 富文本（richText）
- `text` 组件 `richText: true` → 渲染 HTML（`flutter_html`）或 Markdown
- 支持标签：img/div/span/h1-6/p/br/b/i/strong/em/a/ul/ol/li/center/font/hr/table
- `overflow: scroll` → 长文滚动

### 6.6 message_flow 动态选项（AI 生成的交互按钮）
`message_flow` 组件运行时解析 AI 消息里的 `onclick="send('...')"`：
- 提取 `onclick` 指令 + 标签文本 → 渲染成可点按钮
- **只在最新一条 AI 消息下方显示**（历史消息不显示，防误触）
- 点击经 `onSendMessage` 把指令发回 LLM
- AI 可在对话中更新/新增选项（动态）
- 这是「原卡动作选项 / 玩家后续可选项」的运行时载体

### 6.7 头像（AvatarScope）
`image` 组件可通过 `characterAvatar` / `userAvatar` 同步显示角色 / 玩家头像。

---

## 7. 转译 AI 的使用原则

1. **AI 出「设计意图」，代码出「JSON」**（避免静默错误）
2. 优先用数据通道让数值实时更新（还原原卡动态）
3. 面板识别靠语义（字段特征），不靠脚本数量
4. 还原原卡为主，优化为辅；原卡没有的不硬造
5. 思考过程写入日志
