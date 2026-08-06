# UIEngine 能力审计（给转译 AI / API 设计用）

> 来源：`packages/llm_ui_engine/lib/src`、`lib/pages/character_assembly_page/*`、`lib/widgets/chat_assembly_mount.dart`、`lib/pages/chat_page.dart`。
> 目标：避免转译 AI 因知识不足把已有能力误判为“不支持”，也避免凭空发明引擎没有的能力。

## 1. 运行模式与生命周期

| mode | 生命周期 / 位置 | 关键职责 | 适合转译 |
| --- | --- | --- | --- |
| `opening` | 开场白全屏 UI，确认后销毁 / 关闭 | `button + keyAction=true` = 确认并关闭；可带 `targetBranchIndex` 切换开场分支 | 一次性的身份选择、开局分支、玩家档案输入 |
| `scene` | 全屏接管聊天页，原生消息列表和原生输入框不渲染 | `button + keyAction=true` = 打开聊天设置 / 菜单；非故事动作 | 原卡把正文、状态、选项包在一个沉浸式终端 / 面板里 |
| `extra_sticky` | 常驻悬浮 UI | `button + keyAction=true` = 折叠界面 | 快捷工具、轻量状态条 |
| `extra_companion` | 伴生 UI，嵌入 AI 消息气泡周围，宽度上限 212 | 无硬性 keyAction | 小型状态面板、角色徽章；不适合承载完整正文 |

关键关系：

- `opening` 可以与后续 `scene` / `extra_sticky` / `extra_companion` 共存。开场关闭后，后续 UI 继续运行。
- `scene` 与 `extra_companion` 在运行时互斥：scene 接管后没有原生消息气泡，伴生 UI 没有宿主。
- 开场分支不依赖 opening UI 本身；`SessionState.branchIndex` 决定当前分支。
- `UIAssemblyInfo.branchVariants` 支持不同开场分支使用不同 `pagesJson`；状态字段也支持 `branch_initial_values`。

## 2. 尺寸与 PCB

- 普通全屏类默认 `360 × 800`，宽度范围 `120~600`，高度 `64~2000`。
- `extra_companion` 宽度上限为 `212`，默认 `212 × 200`。
- PCB 圆角 `pcbRadius` 上限 `40`。
- 运行端会等比缩小超出屏幕的 PCB，不会非等比拉伸。
- 转译编译器当前把 `pcbColor` 作为外框 / 外层材质，把主 `surface` 以内缩方式放在 PCB 内部，保留外框可见。

## 3. 页面系统

`AssemblyPage` 支持：

- `type: base | overlay`
- `parentPageId`
- `sortOrder`
- `elements`
- `gestures`
- `propertyOverrides`

页面跳转能力：

- `page_router` 逻辑节点 + `button_to_page_route` linker。
- route 参数：`targetPageId`、`action` (`switch_base_page` / `open_overlay` / `close_overlay`)、`transition`、`durationMs`。
- 手势换页：`AssemblyPageGesture` 支持 `swipe_left` / `swipe_right` / `swipe_up` / `swipe_down`。
- overlay 可通过空白点击关闭（运行时有对应逻辑）。

## 4. 可见组件

### `surface` / `base_box`

- 视觉面板 / 背景 / 卡片 / 按钮底板。
- `material`: `glass` / `solid` / `gradient` / `outline`（内部 JSON 用 enum index）。
- `shape`: `rectangle` / `rounded` / `capsule` / `circle` / `heart` / `star5` / `star4`（内部 JSON 用 enum index）。
- `color`: ARGB int。
- `opacity`、`borderRadius`。
- 可承载动画配置，按压反馈常由 `click_to_surface_press` 触发。

### `text`

- 属性：`text`、`fontSize`、`overflow`、`textAlign`、`richText`、`contentPadding`。
- `overflow`: `ellipsis` / `clip` / `scroll`。
- `textAlign`: `left` / `center` / `right`。
- `scroll` 模式：顶部开始、可选中复制、带滚动条，默认富文本。
- `richText=true` 时支持 Markdown / HTML 富文本渲染。
- 可配置 `displayExpression` 和 `dataChannel`。

### `progress`

- 属性：`min`、`max`、`current`、`trackColor`、`progressShape`。
- 形态包含常规条、胶囊、圆环、心形、星形等（由 renderer 支持）。
- 适合 HP / MP / XP / 百分比状态。
- 当前运行时以状态字段同步 current；动态 max 需要额外数据通道 / 引擎扩展，不应默认假设。

### `button`

- 透明点击热区，不自带文字或边框。
- 需要放在 `surface` / `text` 之上形成可见按钮。
- 支持 tap / double_tap / long_press 事件。
- 语义键：
  - `keyAction=true`: 由 mode 决定含义。opening=确认关闭；scene=打开聊天设置；sticky=折叠。
  - `sendsMessage=true`: 发送消息（主要用于 scene）。
  - `text`: 发送内容。
  - `targetBranchIndex`: opening 分支索引。

### `input`

- 属性：`placeholder`、`text`、`value`、`committedValue`、`maxLength`、`multiline`、`textVerticalAlign`、`textHorizontalAlign`。
- 单行回车提交，可配 `sendsMessage=true` 发送输入内容。
- 多行输入时回车换行，不自动提交；需另配确认按钮。
- 在 `extra_companion` 中通常不需要，因为聊天页已有主输入框。

### `select`

- 属性：`options`、`current`、`defaultValue`。
- 选项格式：`[{label,value}]`。
- 可被 input 过滤 / 匹配。

### `switch`

- 属性：`value`。
- 可作为布尔状态 / 条件控制源。

### `slider`

- 属性：`min`、`max`、`current`、`step`、`trackColor`。
- 用户可拖动；保存时会 clamp current 到范围内。

### `line`

- 属性：`axis` (`horizontal` / `vertical`)、`lineStyle` (`solid` / `dashed` / `dotted` / `curve` / `double`)、`thickness`、`dashLength`、`gapLength`。
- 用于分割区域、装饰线、终端边界。

### `indicator`

- 状态指示灯。
- 属性：`dotSize`、`defaultGlow`、`defaultColor`、`statusRules`。
- 不使用 `isOn/onColor`，颜色由 `statusRules` 或 linker 输入决定。
- 可用于异常状态、在线状态、条件警告。

### `image`

- 属性：`imageSource` (`custom` / `character_avatar` / `user_avatar`)、`url`、`assetPath`、`fit` (`cover` / `contain` / `fill`)、`borderRadius`。
- 支持 data URI / 网络 / 本地 / 内部资产 / 角色头像 / 用户头像。

### `message_flow`

- 用于在 UI 内显示真实聊天历史 / AI 正文。
- 属性：`historyLimit`、`showUser`、`showAssistant`、`richText`、`fontSize`、`userBubbleColor`、`assistantBubbleColor`、`bubbleRadius`。
- 在 scene 里非常关键：可把原卡“正文包在 UI 内部”的结构转为 `scene + message_flow`。

## 5. 后台逻辑组件

### `page_router`

- 运行时隐形。
- route: `targetPageId`、`action`、`transition`、`durationMs`。

### `linker`

- 运行时隐形。
- properties.linker: `scheme`、`sourceModuleId`、`targetModuleId`、`sourcePort`、`targetPort`、`schemeParams`、`enabled`、`priority`。

### `math_node`

- 运行时隐形。
- 支持表达式计算：`paramA + paramB`、比较、基础代数。
- 可由 click/timer 触发，结果写入 text/progress。

### `timer`

- 可周期 tick。
- 属性包括 interval / maxTicks / mode / direction / step / currentVal / tickCount / isRunning。
- 可驱动 switch / progress / math_node / text。

## 6. 数据通道

数据通道可让 UI 与会话状态 / Prompt 注入连接：

- 支持读取/写入类型：`input`、`select`、`switch`、`slider`、`progress`、`text`。
- targetKind：`local_ui_state` / `session_var` / `status_field` / `card_entry` / `user_profile`。
- 状态字段绑定：`targetKind=status_field` + `targetId`。
- LLM 读写策略：`llmReadPolicy`、`llmWritePolicy`。
- 通知方式：`notifyStyle`。
- number 字段通常使用 delta 策略；text 字段使用 replace。
- `branch_initial_values` 支持不同开场分支不同初值。

## 7. 语义角色

- `keyAction`: mode 关键职责。
  - opening: 确认并关闭。
  - scene: 打开聊天设置。
  - extra_sticky: 折叠界面。
- `sendsMessage`: 发送消息触发器。主要用于 scene，因为 scene 禁用原生输入框。
- `targetBranchIndex`: opening 选择按钮可写入当前开场分支。

## 8. Linker 方案总览

已注册 68 条方案，常用类别：

- 页面与消息操作：`button_to_page_route`、`button_to_message_action`。
- 点击控制：`click_to_surface_press`、`click_to_switch_toggle`、`click_to_input_clear`、`click_to_slider_reset`、`click_to_timer_toggle`、`click_to_math_trigger`。
- 数学计算：`value_to_math_param`、`click_to_math_trigger`、`result_to_text`、`result_to_progress`、`bool_result_to_text`。
- 可见/启用/锁定：`boolean_to_visible`、`boolean_to_enabled`、`boolean_to_locked`、`boolean_to_frozen`。
- 输入联动：`input_live_to_text`、`input_commit_to_text`、`input_submit_to_text_clear`、`input_nonempty_to_button_enable`、`input_valid_to_button_enable`、`input_value_to_select_match`、`input_value_to_select_filter`、`input_to_progress`、`input_to_slider`。
- 选择 / 滑块 / 进度：`slider_to_text`、`slider_to_progress`、`slider_commit_to_text`、`select_to_text`、`select_value_to_surface_visible`、`progress_to_text`、`progress_threshold_to_button_enable`、`progress_threshold_to_switch`。
- 文本提取：`text_extract_to_math_param`、`text_match_to_switch`、`text_nonempty_to_button_enable`、`text_match_to_button_enable`、`text_value_to_select_match`。
- 定时器：`timer_tick_to_switch_toggle`、`timer_tick_to_progress_increment`、`timer_tick_to_progress_decrement`、`timer_tick_to_math_trigger`、`timer_value_to_text`。
- 动画/指示灯：`event_to_animation`、`event_to_indicator`、`indicator_color_to_switch`、`indicator_color_to_text`、`indicator_color_to_visible`。
- 聚合与配额：`sum_to_display`、`pool_to_allocation`。

## 9. 动画与视觉效果

`ElementAnimation` 支持：

- 按压反馈（press）。
- 发光 / 闪烁类效果。
- 水波折射 shader（资源路径 `packages/llm_ui_engine/shaders/ripple_refraction.frag`）。
- 动画由元件外观配置 + `event_to_animation` 或 `click_to_surface_press` 等触发。

限制：

- 不支持完整 CSS / JS / hover 伪类。
- 可以近似转译 glow、press、ripple、flash，但不能逐像素还原 CSS 动画。

## 10. 对 SillyTavern 转译的直接建议

1. 原卡“开场分支选择”应优先输出 `opening` assembly；后续状态 / 正文再输出 `scene` 或 companion。
2. 原卡把正文、状态、选项包在一个终端 / 羊皮纸 / 档案卡里时，优先考虑 `scene + message_flow`。
3. 原卡只是小状态条时，使用 `extra_companion`。
4. 原卡消息内临时卡片（quest、好友列表、战斗结算）如果没有常驻意图，不要硬塞进 companion；可标记为 `unsupported` 或等待 per-message template API。
5. 同结构不同开场初值，用 `branchInitialValues`。
6. 真正不同布局的开场分支，目前应标记为 notes/unsupported，除非转译层实现 `branchVariants`。
7. 长文本要用 `text.overflow=scroll`。
8. 选择项若原卡只是纯文本，不要擅自变按钮；若明确有 `onclick=send` 或制作者确认“可点击”，才生成 action/button。
