# UI engine 默认渲染规则 + 完整可覆盖字段字典

> 本文档把 UI engine 的**全部默认渲染行为**和**每个组件可覆盖的字段**一五一十列出来。
> 目的：让转译 AI **不再盲猜**——它知道引擎默认渲染什么、能覆盖哪些字段，
> 从而为每张卡量身定制，而不是被同一套固定模板限制。

---

## 0. 核心原则

- 引擎有一套**默认渲染**（某个字段没写时用什么值）。这些默认是「通用兜底」，
  不该被当作设计模板——**AI 应当主动用「可覆盖字段」为每张卡定制**。
- `mode` 有 4 种：`scene`（全屏场景）/ `opening`（开场白弹窗）/
  `extra_companion`（伴生 UI，内嵌 AI 气泡）/ `extra_sticky`（常驻悬浮条）。
  不同卡适合不同 mode，不是只有 scene。
- `button` **运行期是纯透明热区，没有任何可视外观**。所有按钮必须由 AI 配一个
  `surface` 底板 + 文字，否则玩家看不见按钮。
- 组件默认值详见下表。**覆盖 = 显式写该 props 字段**。

---

## 1. PCB（画布）默认与规则

| 项 | 默认 | 说明 |
|---|---|---|
| 宽度 `pcbWidth` | 360 | 场景/开场默认。伴生 UI 上限 212。 |
| 高度 `pcbHeight` | scene/opening 默认 800；extra_sticky 120；extra_companion 200 | **建议显式指定**，避免被默认拖长。 |
| 高度上限 | 2000 | 超过会按屏幕等比缩小，字变小。 |
| 背景色 `pcbColorValue` | 0xFFFFFFFF | 引擎默认白色底。 |
| 圆角 `pcbRadius` | 20 | 0~40。 |
| 等比缩放 | 引擎把整张 PCB 等比缩放到屏幕 | PCB 越高缩放后字越小，控制高度在 650~900。 |

---

## 2. 通用外观字段（所有组件都可写）

| 字段 | 默认 | 说明 |
|---|---|---|
| `material` | 1 | 0=无 / 1=solid / 2=gradient |
| `shape` | 1 | 0=方形 / 1=圆角 / 2=胶囊 / 3=圆形 |
| `color` | 各组件不同（见下） | ARGB int，`0xFFRRGGBB` |
| `opacity` | 1.0 | 0~1 |
| `borderRadius` | 各组件不同 | 圆角半径 |

---

## 3. 组件默认渲染 + 可覆盖字段

### 3.1 text 文本
- 默认字号 `fontSize` 14，`textAlign` center，`overflow` ellipsis，`richText` false。
- 可覆盖：`text` / `fontSize` / `textAlign`(left·center·right) / `overflow`(ellipsis·scroll) /
  `richText`(bool) / `color` / `fontWeight`。
- **长文本**：`overflow:"scroll"` + 固定 `height`，内容在框内滚动，不撑 PCB。
- **文本颜色必须配页面背景**，否则可能和背景同色看不见。

### 3.2 progress 进度条
- 默认 `min` 0，`max` 100，`current`=min，`progressShape` rounded。
- 可覆盖：`min` / `max` / `current` / `progressShape`(bar·ring·capsule·rounded) /
  `trackColor` / `color`(填充色) / `strokeWidth`。
- 绑定数值：`dataChannel` → status_field，`llmWritePolicy:"suggest_delta"`。

### 3.3 button 按钮
- **运行期纯透明热区，无视觉。必须配 surface 底板 + 文字。**
- 可覆盖：`sendsMessage`(bool，点击发送) / `keyAction`(bool) / `text`(发送内容) /
  `targetBranchIndex`(opening 切分支)。
- 可视：需要 AI 单独放一个 `surface` 在按钮下层作底板。
- 跳转：`page_router` 组件 + `click_to_surface_press`/`button_to_page_route` 联动器。

### 3.4 input 输入框
- 默认 `placeholder`「请输入...」，`visualMode` filled，`textHorizontalAlign` left，
  `textVerticalAlign` center，multiline false。
- 可覆盖：`placeholder` / `text` / `maxLength` / `multiline` / `visualMode`(filled·outline·transparent) /
  `textHorizontalAlign` / `textVerticalAlign` / `sendsMessage`(回车发送)。
- 提交值存 `committedValue`，供数据通道读取。

### 3.5 surface 表面 / base_box 底板
- 纯视觉表面。可覆盖：`color` / `material` / `shape` / `borderRadius` / `opacity` /
  `is_overlay_container`(叠加层容器)。
- **是给 button / 面板做底板的组件。**

### 3.6 select 下拉
- 默认 `current` 无。可覆盖：`options:[{label,value}]` / `current` / `color` / `knobShape`。

### 3.7 switch 开关
- 默认 `value` false。可覆盖：`value` / `color` / `inactiveColor`。

### 3.8 slider 滑块
- 默认 `min`0 `max`100 `current`=min `step`1 `knobShape`circle `knobSize`18。
- 可覆盖：`min`/`max`/`current`/`step`/`knobShape`/`knobSize`/`thumbColor`/`activeTrackColor`/`inactiveTrackColor`。

### 3.9 indicator 指示点 / 状态灯
- 可覆盖：`color` / `dotSize` / `activeColor` / `inactiveColor`。

### 3.10 image 图片
- 默认 `fit` cover，`shape` rectangle，`borderRadius` 8。
- 可覆盖：`url` / `assetPath` / `imageSource`(network·asset·inline) / `fit`(cover·contain·fill) /
  `borderRadius` / `shape`。

### 3.11 line 分割线
- 默认 `thickness`2 `lineStyle`solid `axis`horizontal `dashLength`6 `gapLength`3。
- 可覆盖：以上全部 + `color`。

### 3.12 message_flow 消息流
- 默认：`showUser`/`showAssistant` true，`historyLimit` 0(不限)，`fontSize` 12.5，
  `userBubbleColor` 0xFFDCF8C6，`assistantBubbleColor` 0xFFF1F1F4，`bubbleRadius` 12，`richText` true。
- 可覆盖：`showUser` / `showAssistant` / `historyLimit` / `fontSize` / `userBubbleColor` /
  `assistantBubbleColor` / `bubbleRadius` / `richText` / `module.color`(消息流整体底色)。
- **注意：气泡文字色引擎固定为深色(0xFF111116)**，所以气泡底色应配浅色，否则字看不见。

### 3.13 装饰类：primitive_art / surface_art / light_effect
- 归一化图层 + 颜色 / 发光。可覆盖：`color` / `opacity` / `glow` / 图层参数。

---

## 4. mode（页面模式）—— 不是只有 scene

| mode | 定位 | 特性 |
|---|---|---|
| `scene` | 全屏场景 | 多页、多面板，page_router 切换 |
| `opening` | 开场白弹窗 | 开场全屏，确认后进入 |
| `extra_companion` | **伴生 UI** | 内嵌最新 AI 气泡（≤212 宽），适合附属面板/状态条 |
| `extra_sticky` | **常驻 UI** | 悬浮小窗，可折叠，适合常驻状态/快捷入口 |

> **AI 应该根据卡的类型选择 mode**：附属信息（状态/好友/任务）可用伴生 UI，
> 而不必都用 scene 全屏页。

---

## 5. 样式 style → 实际配色

`style` 目前映射到一套主题（引擎 `UiVisualTheme`）。AI 可选择并知晓大致观感：

| style | 背景 | 文字 | 进度条填充 |
|---|---|---|---|
| dark | 深色 0xFF15161A | 亮色 | 蓝 0xFF4FA3D1 |
| parchment | 深棕 0xFF2A1E14 底，面板 0xFFEFE0C3 羊皮纸 | 深棕文字 | 金 0xFFB8860B |
| cyber | 深蓝黑 0xFF0A0E1A | 亮蓝白 | 霓虹青 0xFF00E5FF |
| light | 浅灰 0xFFF5F5F7 | 深灰 | 蓝 0xFF0A84FF |

> **若某页背景是深棕(parchment)，文字必须是浅色；背景是浅色，文字必须是深色。**
> 避免「文本与背景同色」。

---

## 6. 交互与事件

- **按钮按压反馈**：`linker` scheme `click_to_surface_press`（按钮 → surface 底板按压动画）。
- **页面跳转**：`page_router` 组件（`route:{targetPageId, action:switch_base_page/open_overlay}`）
  + `linker` scheme `button_to_page_route`。
- **打开聊天设置**：chrome `settingsButton`（需配 surface 底板 + 齿轮图标，否则不可见）。
- 完整 linker scheme 清单（50+）：`click_to_surface_press` / `click_to_switch_toggle/_set_true/_set_false` /
  `click_to_input_clear` / `click_to_slider_reset` / `click_to_timer_toggle/_reset` / `click_to_math_trigger` /
  `input_commit_to_text` / `input_live_to_text` / `input_to_progress` / `input_to_slider` /
  `input_nonempty_to_button_enable` / `input_valid_to_button_enable` / `input_validity_to_indicator` /
  `input_length_to_indicator` / `input_submit_to_text_clear` / `input_value_to_select_filter/_match` /
  `select_to_text` / `select_value_to_switch` / `select_value_to_surface_visible` /
  `slider_to_progress` / `slider_to_text` / `slider_commit_to_text/_math_param` /
  `progress_to_text` / `progress_to_math_param` / `progress_threshold_to_switch/_button_enable` /
  `bool_result_to_progress/_text` / `bool_to_text` / `boolean_to_enabled/_visible/_frozen/_locked/_timer_running` /
  `event_to_animation` / `event_to_indicator` / `indicator_color_to_switch/_text/_visible/_enabled/_frozen/_locked` /
  `timer_tick_to_progress_increment/_decrement` / `timer_tick_to_switch_toggle` / `timer_value_to_text` /
  `text_match_to_switch` / `text_nonempty_to_button_enable` / `text_extract_to_math_param` /
  `name_to_text` / `sum_to_display` / `pool_to_allocation` / `result_to_progress/_text` /
  `value_to_math_param` / `click_to_math_trigger` / `button_to_message_action` / `button_to_page_route`。

---

## 7. 数据绑定（数据通道）

- 组件绑定 `dataChannel`：`targetKind:"status_field"`（状态字段，LLM 可读写）。
- `llmWritePolicy`：
  - `suggest_delta`（数值：LLM 只给增量，引擎 clamp 到 min/max）
  - `suggest_replace`（文本：LLM 给新值整值替换）
- `llmReadPolicy`：`prompt`（值注入 prompt）或 `ui_only`（仅界面）。
- `targetKind` 5 种：`status_field` / `session_var` / `card_entry` / `local_ui_state` / `user_profile`。
- 进度条绑数值（HP/MP/XP）、文本绑文本字段，才能运行时实时更新。

---

## 8. 引擎默认兜底行为（AI 需知晓，主动规避）

| 情况 | 引擎行为 | 建议 |
|---|---|---|
| 页面没声明 messageFlow | 可能按默认渲染消息流 | 纯内容页也**显式声明 chrome** 控制 |
| 页面没声明 input | 可能按默认补输入框 | 不需要输入就显式声明控制 |
| 没写 pcbHeight | 用默认高度 | **总显式写 pcbHeight** |
| button 没配 surface | 按钮不可见 | **每个按钮配 surface 底板** |
| 没写 style | 默认 dark | 每页显式选 style |
| 文本没写 color | 用 style 默认文字色 | 确认与背景不同色 |
| `pcbHeight` 与实际渲染可能被等比替换 | 按屏幕缩放 | 控制设计高度在合理范围 |

---

## 9. AI 使用原则

1. **为每张卡量身定制**，不要套固定模板——不同卡用不同 mode / style / 布局。
2. **显式覆盖默认**：每个关键字段（pcbHeight / style / chrome / 按钮底板 / 颜色）都写出来。
3. **按钮必须有 surface 底板**，否则不可见。
4. **文本色与背景色对比**，避免同色。
5. **长文本用 scroll** 固定高度，不撑 PCB。
6. **数值绑数据通道**，运行时实时更新。
7. 完成布局后**自查坐标**：x+width≤360，矩形不重叠。

---

## 10. 交互链路完整写法（照抄即可用的最小示例）

### 10.1 按钮跳转页面（button → page_router）

**需要 3 个元素**：一个可点的 `button`（配 surface 底板）、一个逻辑 `page_router`、一条 `linker` 连线。

```json
{
  "type": "button",
  "properties": { "sendsMessage": false }
}
```
```json
{
  "type": "page_router",
  "properties": {
    "route": { "targetPageId": "quests", "action": "switch_base_page" }
  }
}
```
```json
{
  "type": "linker",
  "properties": {
    "linker": {
      "scheme": "button_to_page_route",
      "sourceModuleId": "<button元素id>",
      "targetModuleId": "<page_router元素id>",
      "sourceGesture": "tap",
      "enabled": true
    }
  }
}
```

> `action`: `switch_base_page`(平级切页) / `open_overlay`(打开叠加层)。
> `transition`/`durationMs` 可省略（引擎按 action 给默认：切页 base_slide，叠加层 overlay_fade）。
> 按钮必须配 surface 底板才可见，见 3.3。

### 10.2 按钮按压反馈（click_to_surface_press）

把按钮点击连到底板 surface 的按压动画：

```json
{
  "type": "linker",
  "properties": {
    "linker": {
      "scheme": "click_to_surface_press",
      "sourceModuleId": "<button元素id>",
      "targetModuleId": "<surface底板元素id>",
      "sourceGesture": "tap",
      "enabled": true
    }
  }
}
```

---

## 11. 动画系统（`__anim`）

动画挂在**元素**的 `properties.__anim` 上（不是连线上）。参数：类型/时长/曲线/强度/颜色。

```json
{
  "type": "text",
  "properties": {
    "text": "HP 100",
    "__anim": {
      "type": "number_pop",
      "durationMs": 260,
      "curve": "easeInOut",
      "intensity": 1.0
    }
  }
}
```

**动画类型**（`type`）与建议时长：

| type | 含义 | 建议 durationMs |
|---|---|---|
| `press` | 按压凹陷 | 150 |
| `ripple` | 水波扩散 | 300 |
| `flash` | 短暂高亮 | 300 |
| `number_pop` | 数值跳动（目标值变化时放大回弹） | 260 |
| `glow_pulse` | 发光脉冲（外发光呼吸） | 600 |
| `particle_burst` | 粒子迸发 | 700 |

**曲线**（`curve`）：`easeInOut` / `easeOut` / `easeIn` / `linear` / `bounceOut` / `elasticOut`。

**触发**：
- 按钮按压动画：用 `click_to_surface_press` 连线，或直接在 surface 上配 `__anim` 的 `press`；
- 数值跳动：给 progress/text 配 `__anim` 的 `number_pop`，值变化时自动播放；
- 发光/粒子：配 `__anim`，可用 `event_to_animation` 连线触发或值变化自动播放。

---

## 12. 数据通道完整写法（dataChannel）

让组件被 LLM 读写、运行时实时更新。写在组件 `properties.dataChannel`：

```json
{
  "type": "text",
  "properties": {
    "text": "木剑",
    "dataChannel": {
      "semanticLabel": "武器",
      "semanticPath": "武器",
      "sourceComponentId": "<元素id>",
      "sourcePort": "text",
      "targetKind": "status_field",
      "targetId": "sf_武器",
      "llmReadPolicy": "prompt",
      "llmWritePolicy": "suggest_replace",
      "fieldType": "text"
    }
  }
}
```

- **数值字段**（progress）：`llmWritePolicy:"suggest_delta"`（LLM 只给增量，引擎 clamp 到 min/max）+ `fieldType:"number"`；
- **文本字段**（text）：`llmWritePolicy:"suggest_replace"`（LLM 给新值整值替换）+ `fieldType:"text"`。

**`targetKind` 5 种**：
| targetKind | 说明 |
|---|---|
| `status_field` | 置顶状态栏字段，注入 prompt，LLM 可读写 |
| `session_var` | 会话变量 |
| `card_entry` | 角色卡条目字段 |
| `local_ui_state` | 本地 UI 状态（仅界面内） |
| `user_profile` | 玩家档案 |

**`llmReadPolicy`**：`prompt`(值注入 prompt 供 LLM 读) / `ui_only`(仅界面)。

> 进度条绑数值（HP/MP/XP）用 suggest_delta，文本绑字段用 suggest_replace，
> 否则运行时就显示死值，不随剧情更新。

---

## 13. 动态选项（message_flow 的 onclick）

`message_flow` 组件**运行时解析 AI 消息里的 `onclick="send('...')"`** 指令，渲染成可点按钮：

- AI 输出消息里含 `onclick` → 消息流把指令 + 标签渲染成按钮；
- **只在最新一条 AI 消息下方显示**（历史消息不显示，防误触）；
- 点击把指令发回 LLM；
- AI 可在对话中更新/新增选项（动态）。

**对转译 AI 的意义**：原卡的「动作选项 / 玩家后续可选项」（如 `onclick="send('调查房间')"`）可以**保留在开场白/消息原文里**，由运行时 message_flow 自动变成按钮——**不需要转译 AI 为每个选项单独建 button 组件**。设计时只要确保主页面有 message_flow，选项就会自然出现。

---

## 14. 页面手势（gestures）

页面可配 `gestures` 数组，实现滑动切页（引擎原生支持，不依赖按钮）：

```json
{
  "id": "main",
  "name": "主界面",
  "gestures": [
    { "direction": "swipe_left",  "action": "switch_base_page", "targetPageId": "quests" },
    { "direction": "swipe_right", "action": "switch_base_page", "targetPageId": "friends" }
  ]
}
```

- `direction`: `swipe_left` / `swipe_right` / `swipe_up` / `swipe_down`；
- `action`: `switch_base_page`；
- 叠加层可用 `open_overlay` + `targetPageId`。

---

## 15. 逻辑组件

### 15.1 math_node 计算节点
- 运算：`set` / `+` / `-` / `*` / `/`（除零兜底）/ 比较 `>` `<` `>=` `<=` `==`。
- 配合 `value_to_math_param` / `click_to_math_trigger` 等连线。

### 15.2 timer 定时器
- 周期脉冲。可配合 `timer_tick_to_progress_increment/_decrement`（定时增减进度）、
  `timer_tick_to_switch_toggle`、`click_to_timer_toggle/_reset` 等连线。

### 15.3 linker 完整 scheme 清单
见第 6 节 + 第 10 节示例。核心交互：
- `button_to_page_route` 页面跳转
- `click_to_surface_press` 按压反馈
- `event_to_animation` 事件→动画
- `timer_tick_to_progress_increment` 定时→进度
- `input_commit_to_text` 输入→文本
- `progress_to_text` 进度→文本
- `text_match_to_switch` 文本匹配→开关
