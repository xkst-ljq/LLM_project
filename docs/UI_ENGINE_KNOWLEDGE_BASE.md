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

| 策略 | 说明 |
|---|---|
| `suggest_delta` | 数值：LLM 只返回增量，引擎 clamp(旧值+增量, min, max) |
| `suggest_replace` | 文本：LLM 返回新值整值替换 |

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
| `click_to_input_clear` | 点击清空输入 |
| `input_length_to_indicator` | 输入长度 → 指示器 |
| `input_nonempty_to_button_enable` | 输入非空才启用按钮 |

### 4.3 开关 / 滑块 / 进度
| scheme | 作用 |
|---|---|
| `click_to_switch_toggle` / `_set_true` / `_set_false` | 点击切换/置位开关 |
| `click_to_slider_reset` | 点击重置滑块 |
| `bool_result_to_progress` / `bool_to_text` / `bool_to_text_...` | 布尔 → 进度/文本 |
| `boolean_to_enabled` / `_frozen` / `_locked` / `_visible` / `_timer_running` | 条件控制 |

### 4.4 逻辑 / 动画
| scheme | 作用 |
|---|---|
| `click_to_math_trigger` | 点击触发计算 |
| `click_to_timer_toggle` / `_reset` | 点击开关/重置定时器 |
| `event_to_animation` | 事件 → 动画 |
| `event_to_indicator` / `indicator_color_to_*` | 事件 → 指示器 / 指示器颜色控制 |

---

## 5. 页面模式（mode）

| mode | 定位 | 特点 |
|---|---|---|
| `scene` | 场景 UI | 全屏接管聊天页，可多页、多面板 |
| `opening` | 开场白弹窗 | 开场全屏，确认后进入 |
| `extra_companion` | 伴生 UI | 内嵌最新 AI 气泡（≤212px 宽） |
| `extra_sticky` | 常驻 UI | 悬浮小窗，可折叠 |

---

## 6. 转译 AI 的使用原则

1. **AI 出「设计意图」，代码出「JSON」**（避免静默错误）
2. 优先用数据通道让数值实时更新（还原原卡动态）
3. 面板识别靠语义（字段特征），不靠脚本数量
4. 还原原卡为主，优化为辅；原卡没有的不硬造
5. 思考过程写入日志
