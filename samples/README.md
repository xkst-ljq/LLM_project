# 示例角色卡与 UI 方案样板

## 文件

| 文件 | 用途 |
|---|---|
| `织_夜航酒保_UI测试卡.llmcard` | 单页 UI 测试卡（三套 UI，各 1 页） |
| `灰港迷雾_跑团卡.llmcard` | **多页面** RPG 跑团卡（scene 含 5 页，纯手势导航） |
| `星轨观测站_图形动画卡.llmcard` | **图形专项**：复合组件 / 网络图片 ×4 / 六种动画 / 按钮换页 |
| `潮汐工坊_交互逻辑卡.llmcard` | **逻辑专项**：单击双击长按分流 / math_node 串联 / 四种数据通道 / 叠加页 |
| `织房夜话_伴生常驻卡.llmcard` | **伴生专项**：伴生 UI + 常驻 UI + 开场白（无 scene，两者互斥） |
| `generate_*.py` | 各卡的生成脚本 |
| `validate_card.py` | **卡片结构校验器**，生成后务必跑一遍 |

```bash
python3 samples/generate_gallery_card.py      # 重新生成
python3 samples/validate_card.py samples/*.llmcard   # 全量校验
```

校验器会检查：PCB 尺寸越界、元素超出 PCB、linker 指向不存在的元素、
换页方案的源不是 button、叠加页缺父页、mode 重复、复合件外框与内容
不符、**缺 keyAction 标记**、**文字对比度不足**。

## 这张卡覆盖了什么

三套 UI，覆盖全部 mode 与主要组件类型：

| mode | 名称 | 尺寸 | 内容 |
|---|---|---|---|
| `extra_sticky` | 状态挂件 | 212×150 | 进度条 / 状态点 / 文本，绑 4 个状态字段 |
| `scene` | 吧台场景 | 360×640 | 消息流 + 滑块 + 下拉 + 开关 + 输入 + 按钮 |
| `opening` | 开场白 | 320×380 | 文本 + 输入 + 下拉 + 确认按钮 |

**状态栏字段 5 个**：数值 3（信任度 / 信用点 / 警戒等级）+ 文本 2（心情 / 时段），
三种 owner（char / player / neutral）都有。

**数据通道 10 条**，覆盖 `status_field` 与 `session_var` 两类，
通知方式 `silent` / `toast` / `dialog` 三档齐全，
其中「玩家身份」故意留成**预绑定**（targetId 为空、pendingName 有值），
用来验证状态栏编辑页的「未创建字段」提示。

---

## 给 LLM 生成 UI 时的硬约束

转译 SillyTavern 卡片时，让模型照这些规则产出，可以避免生成出来的 UI 打不开。

### 1. 结构层级

```
meta.ui_assemblies: [ JSON字符串, ... ]   ← 注意是字符串数组，不是对象数组
  └ { id, name, mode, pages: "JSON字符串", pcbWidth, pcbHeight, ... }
      └ pages: [ { id, name, type, elements: [...], gestures, propertyOverrides } ]
          └ elements: [ { id, offset, size, layerIndex, parentSurfaceId, module } ]
```

`pages` 与 `ui_assemblies` 都是**被 JSON 编码过的字符串**，不是嵌套对象。

### 2. 必须遵守的规则

| 规则 | 说明 |
|---|---|
| **keyAction** | `opening` / `scene` / `extra_sticky` 必须**至少有一个**按钮带 `keyAction: true`，否则玩家会被卡死，运行时会拦截 |
| **元素不出 PCB** | 除 `linker`/`math_node`/`timer`/`page_router` 四种逻辑件外，所有元素必须完全落在 `0,0,pcbWidth,pcbHeight` 内。逻辑件运行时隐形，按第 7 节的「机房区」公式摆在 PCB 左外侧 |
| **容器组连续** | 用了 `parentSurfaceId` 时，父面元素必须排在组员**之前** |
| **PCB 尺寸** | 宽 120~600（`extra_companion` 上限 212）；高 64~2000。超出会被静默 clamp |
| **select 的 current** | 必须是 `options` 里某个 `value`，否则保存时被打回第一项 |
| **sourceComponentId** | 数据通道里这个值必须等于所在元素的 `id` |
| **id 唯一** | 同一张卡内所有元素 id 不得重复 |

### 2.9 两条会让 UI「完全不显示」的硬约束

这两条踩中后**没有任何报错**，UI 直接不渲染或看不清，务必先检查。

### ① scene / opening 必须有 keyAction 标记

`UISemanticRole.blocksWithoutKeyAction` 规定：
`opening` 与 `scene` 缺少关键职责标记时，`ChatAssemblyMount.canRun`
返回 false，**整层 UI 根本不渲染**——表现为「装了卡但界面没出来」。

| mode | 需要的标记 | 缺失后果 |
|---|---|---|
| `opening` | 确认并关闭 | 整层不渲染 |
| `scene` | 打开聊天设置 | 整层不渲染 |
| `extra_sticky` | 折叠界面 | 仅少一个折叠按钮，有内置兜底 |

写法：在某个 button 的 properties 里加 `"keyAction": true`。
多页面 scene 可以每页各放一个（每页都要有出口），但**同一页只放一个**。

另外 scene 接管后原生输入栏不渲染，**必须自己提供发消息的入口**
（button 或 input 标 `"sendsMessage": true`），否则玩家无法说话。

### ② 文字对比度

小字（<14px）按 WCAG **AAA 7:1** 要求，不是 4.5:1——
后者是给 14px+ 正文定的门槛，9~12px 的注释用 4.5:1 实际看不清
（用户实测反馈）。深色主题尤其容易踩：底色越深，中间调的灰蓝
看起来越"够"，实际远远不够。

`samples/validate_card.py` 会自动算每个 text 与其背后 surface 的
对比度并给出警告，生成卡片后跑一遍即可。

**同一个颜色不能既当深底上的文字、又当白字按钮的底色**——
前者要够亮、后者要够暗，方向相反，必须拆成两个色值。

## 3. 数据通道

```json
"dataChannel": {
  "semanticLabel": "信任度",
  "targetKind": "status_field",     // status_field | session_var | card_entry | local_ui_state
  "targetId": "sbf_trust",          // status_field 时必须指向真实字段 id
  "pendingName": "",                // 字段还不存在时填名字、targetId 留空
  "sourceComponentId": "<所在元素id>",
  "llmReadPolicy": "prompt",        // none | prompt | hidden_context
  "llmWritePolicy": "suggest_delta",// none | suggest_delta | suggest_replace
  "notifyStyle": "toast",           // silent | toast | dialog
  "notifyTemplate": "信任 {old} → {new}",  // 可选，支持 {name} {old} {new}
  "promptSection": "ui_data"        // ui_data | core_setting
}
```

**通知方式的选择**：数值频繁小幅变动用 `silent` 或 `toast`；
升级、警戒提升这类玩家要据此做决策的才用 `dialog`（会阻断操作）。

### 4. 各 mode 的推荐尺寸

代码只在 120~600（宽）/ 64~2000（高）范围内做硬约束，
以下是**观感上合适**的取值，样板卡用的就是这组：

| mode | 推荐 | 说明 |
|---|---|---|
| `opening` | 320×380 | 居中弹出，别做满屏 |
| `scene` | 360×640 | 全屏接管，按手机比例 |
| `extra_sticky` | 212×150 | 常驻挂件，越小越好 |
| `extra_companion` | ≤212 宽 | 嵌在消息气泡里，宽度有硬上限 |

### 5. 显示值要与字段初始值对齐

绑定了状态字段的组件，其初始显示值应与字段的 `initial_value` 一致：

- `progress` / `slider` → `current` 等于初始值，且 `min`/`max` 与字段量程相同
- `text` → `text` 等于初始值

不一致也能跑（编辑器打开时会自动同步），但导入后第一眼看到的是错的。

### 6. 常用组件的必填 properties

| 类型 | 必填 |
|---|---|
| `text` | `text`, `fontSize` |
| `progress` | `current`, `min`, `max`, `progressShape` |
| `slider` | `current`, `min`, `max`, `step` |
| `select` | `options`(label/value 数组), `current`, `defaultValue` |
| `switch` | `value` |
| `input` | `placeholder`, `text`；可选 `multiline`(bool)、`textVerticalAlign`(top/center/bottom)、`textHorizontalAlign`(left/center/right) |
| `button` | `hitArea: true`；要显示文字加 `showTextOnRuntime: true` + `text` |
| `message_flow` | `historyLimit`, `fontSize`, `showUser`, `showAssistant` |
| `surface` | 作容器时加 `is_overlay_container: true` |
| `indicator` | `dotSize`, `defaultGlow` |

### 7. 联动：linker 连线 vs 数据通道

**两套机制，用途不同，不要混淆。**

| | 数据通道 | linker 连线 |
|---|---|---|
| 怎么联动 | 共享数据源：A 写 session → B 读 session | 点对点：A 的值直接推给 B |
| 画布上 | **看不见**，靠同名/同 targetId 隐式匹配 | **有一条连线**，因果关系可见 |
| 出错时 | 静默不联动，很难查 | 连线断了一眼看出 |
| 适合 | 要进 Prompt、要存状态、跨页面 | 组件间的即时反馈、事件触发 |

**优先用 linker 表达组件之间的联动**——创作者打开画布就能看懂
「这个数是从哪来的」。数据通道留给「需要 AI 读写」的值。

⚠️ 常见错误：给滑块和进度条各设一个值就以为会联动。
**不会**。必须显式加一条 `slider_to_progress` 的 linker，
或者给两者配**同名**的 `session_var` 数据通道。

#### linker 元件的结构

它就是一个普通元件，`type` 为 `linker`：

```json
{
  "id": "el_lk1",
  "offset": {"x": -224, "y": 0},
  "size": {"width": 132, "height": 44},
  "module": {
    "id": "m_lk1", "name": "浓度→预览条", "type": "linker",
    "properties": {
      "linker": {
        "scheme": "slider_to_progress",
        "sourceModuleId": "<源【元素】id>",
        "targetModuleId": "<目标【元素】id>",
        "enabled": true,
        "priority": 5,
        "params": {"mappingMode": "absolute"}
      }
    }
  }
}
```

`sourceModuleId` / `targetModuleId` 存的是**元素 id**（`element.id`），
不是 module.id——名字有误导性，别填错。

#### ⚠️ button 是透明热区，可见外观要自己垫 surface

`UIRenderer._buildButton` 运行时返回的是 **`SizedBox.expand()`**——
button **自己不显形**，只是一块透明热区。
（`showTextOnRuntime` 只画文字，画不出底色和圆角。）

所以一个「看得见、按得动、有反馈」的按钮需要**三个元素叠起来**：

```
surface（按钮外观：底色 + 圆角）   layer N     ← 按压动画作用在它身上
  text（按钮文字）                layer N+1
    button（透明热区）             layer N+2   ← 必须在最上层才接得到点击
```

三者**几何完全重合**（同 x/y/w/h），然后连一条：

```
click_to_surface_press:  button → 它自己的那块 surface
```

**常见错误**：把 button 连到整页的背景 surface 上。
那样点一下是**整个页面在凹陷**，而不是这个按钮——
方案描述里写的「为透明按钮或图片热区增加按下手感」，
指的就是按钮自己那块底。

跑团卡的 `button_group()` 就是这个模式，10 个按钮全部照此构造。

#### 逻辑件的摆放：PCB 左外侧「机房区」

`linker` / `math_node` / `timer` / `page_router` 运行时**隐形**，
但在编辑器里占位置。它们也是少数**允许摆在 PCB 外**的类型。

不给规则的话，AI 会把它们堆在同一个坐标上重叠成一团，
作者打开看到一堆糊在一起的方块，比不画连线更糟。
用这套公式排（机械可执行，不需要审美判断）：

```
列宽 200      # 最宽逻辑件 math_node(180) + 余量
行高 64       # 最高 timer(54) + 间距 10
每列 8 个，满了往左再起一列

第 i 个逻辑件：
  col, row = divmod(i, 8)
  x = -224 - col * 212
  y = row * 64
```

**每套 UI 各自从 0 开始编号**，不要跨 assembly 累加。

逻辑件默认尺寸：`linker` 132×44、`math_node` 180×44、
`timer` 140×54、`page_router` 124×56。

逻辑件**不要**设 `parentSurfaceId`——它们不属于任何容器组。

#### 全部 66+ 条方案

源 / 目标写成 `a/b/c` 的表示只接受这几种类型（比 `any` 严格）。
`isPulse` 类方案由点击或 tick 触发，不是持续同步。

| scheme | 源 → 目标 | 说明 | 参数 |
|---|---|---|---|
| `button_to_page_route` | button → page_router | button 点击触发页面路由器，切换平级页或打开叠加页 | — |
| `button_to_message_action` | button → message_flow | button 点击对消息流中最新一条 AI 消息执行重生成 / 编辑 / 删除等操作 | `action` |
| `pool_to_allocation` | text/progress/math_node → slider/input | 把一个组件当作「可分配总量」，其余组件从中分配。总量直接取来源组件的内容——文本里写「1… | `total`, `initialValue`, `precision`, `template` |
| `sum_to_display` | slider/progress/input/math_node/timer → text/progress/slider | 把多个数值加起来显示在一处。用法：每个来源各连一条本方案到【同一个】目标组件，目标就会显… | `total`, `overflowMode`, `precision`, `template` |
| `click_to_surface_press` | button → surface | button 点击脉冲触发 surface 的按下凹陷反馈 | `durationMs` |
| `click_to_switch_toggle` | button → switch | 每次点击脉冲，switch 状态翻转一次 (true ↔ false) | — |
| `click_to_switch_set_true` | button → switch | 每次点击脉冲，强制将 switch 设为 true | — |
| `click_to_switch_set_false` | button → switch | 每次点击脉冲，强制将 switch 设为 false | — |
| `click_to_input_clear` | button → input | 点击脉冲清空 input 当前内容 | — |
| `click_to_slider_reset` | button → slider | 点击脉冲将滑块恢复至默认值 | — |
| `click_to_timer_toggle` | button → timer | 每次点击在启动与停止 Timer 之间切换 | — |
| `click_to_timer_reset` | button → timer | 点击脉冲停止 Timer 并清空当前值与 Tick 计数 | — |
| `click_to_math_trigger` | button → math_node | 点击脉冲使目标 Math Node 立即计算并更新 lastResult | — |
| `result_to_text` | math_node → text | 计算结果实时覆盖文本原子的模板输出 | `template`, `precision` |
| `bool_result_to_text` | math_node → text | 根据计算结果真假，显示条件文案 | `trueText`, `falseText` |
| `result_to_progress` | math_node → progress | 计算结果驱动进度条数值，支持比例归一化与绝对值截断 | `mappingMode` |
| `bool_result_to_progress` | math_node → progress | true 跳至 100%，false 跳至 0% | — |
| `value_to_math_param` | any → math_node | 将来源当前值转换为数值并注入目标计算节点的指定参数口 | `targetParam` |
| `bool_to_text` | switch → text | 根据开关开启/关闭渲染对应文案 | `trueText`, `falseText` |
| `boolean_to_visible` | switch → surface/surface_art/primitive_art/text/progress/slider/input/button/switch/select/indicator | 开关开启时显示目标组件，关闭时在预览和运行时隐藏 | — |
| `boolean_to_enabled` | switch → button/input/slider/switch/select/indicator | 开关开启时允许目标交互，关闭时禁用并淡化 | — |
| `boolean_to_locked` | switch → button/input/slider/switch/select | 开关开启时锁定目标编辑，关闭时解除锁定 | — |
| `boolean_to_frozen` | switch → progress/math_node | 开关开启时冻结目标的外部数值更新，关闭时恢复更新 | — |
| `boolean_to_timer_running` | switch → timer | 开关开启时 Timer 运行，关闭时 Timer 停止 | — |
| `input_live_to_text` | input → text | 每次输入立即更新目标文本 | — |
| `input_commit_to_text` | input → text | 输入法完成、回车或失焦后更新目标文本，保留输入框内容 | — |
| `input_submit_to_text_clear` | input → text | 提交值写入目标文本后立即清空输入框，适合快速记录与短指令 | — |
| `input_nonempty_to_button_enable` | input → button | 输入去除空白后有内容时启用按钮，无内容时禁用 | — |
| `input_valid_to_button_enable` | input → button | 输入通过 required 与 maxLength 校验时启用按钮 | — |
| `input_validity_to_indicator` | input → indicator | 向状态灯传入 empty、valid 或 invalid，由状态规则决定颜色 | — |
| `input_length_to_indicator` | input → indicator | 向状态灯传入当前字符长度，由范围规则决定颜色 | — |
| `input_value_to_select_match` | input → select | 输入内容与选项完全匹配时自动切换 Select；不匹配时保持当前选项 | — |
| `input_value_to_select_filter` | input → select | 输入关键词实时过滤 Select 菜单；清空输入后恢复全部选项 | — |
| `input_to_progress` | input → progress | 尝试解析输入的数值，驱动进度条变化 | — |
| `input_to_slider` | input → slider | 解析输入的数值，驱动滑块滑动 | — |
| `slider_to_text` | slider → text | 滑块当前数值实时渲染到文本模板 | `template` |
| `slider_to_progress` | slider → progress | 滑块当前数值实时同步到进度条，支持比例折算与绝对值截断 | `mappingMode` |
| `slider_commit_to_text` | slider → text | 只在点击结束或拖动松手后将最终值写入 Text | `template`, `precision` |
| `slider_commit_to_math_param` | slider → math_node | 只在点击结束或拖动松手后将最终值注入 Math Node 参数口 | `targetParam` |
| `select_to_text` | select → text | 单选组件选中的 Value/Label 输出到文本模板 | `template` |
| `select_value_to_surface_visible` | select → surface/surface_art/primitive_art | 选中值匹配时显示目标 Surface，不匹配时隐藏 | `triggerValue` |
| `select_value_to_switch` | select → switch | 选中值匹配时开启 Switch，不匹配时关闭 | `triggerValue` |
| `progress_to_text` | progress → text | 输出当前值、最大值、百分比或范围文本 | `sourceField`, `precision`, `template` |
| `progress_to_math_param` | progress → math_node | 将当前值或最大值注入 Math Node 指定参数口 | `sourceField`, `targetParam` |
| `progress_threshold_to_button_enable` | progress → button | 进度满足阈值条件时启用按钮，否则禁用 | `operator`, `threshold` |
| `progress_threshold_to_switch` | progress → switch | 进度满足阈值条件时开启 Switch，否则关闭 | `operator`, `threshold` |
| `text_extract_to_math_param` | text → math_node | 从纯数值、首个数、第 N 个数或关键字字段中提取数值 | `targetParam`, `extractMode`, `numberIndex`, `key`, `parseFailBehavior` |
| `text_match_to_switch` | text → switch | 文本匹配时开启 Switch，不匹配时关闭 | `triggerText` |
| `text_nonempty_to_button_enable` | text → button | 文本去除空白后有内容时启用按钮 | — |
| `text_match_to_button_enable` | text → button | 文本匹配时启用按钮，不匹配时禁用 | `triggerText` |
| `text_value_to_select_match` | text → select | 文本与选项完全匹配时切换 Select，不匹配时保持当前选项 | — |
| `timer_tick_to_switch_toggle` | timer → switch | 每到一次定时 Tick，驱动目标 switch 翻转一次 | — |
| `timer_tick_to_switch_set_true` | timer → switch | 每到一次定时 Tick，强制将目标 switch 设为 true | — |
| `timer_tick_to_switch_set_false` | timer → switch | 每到一次定时 Tick，强制将目标 switch 设为 false | — |
| `timer_tick_to_progress_increment` | timer → progress | 每到一次定时 Tick，驱动进度条增加固定步长 | `step`, `boundaryBehavior` |
| `timer_tick_to_progress_decrement` | timer → progress | 每到一次定时 Tick，驱动进度条减少固定步长 | `step`, `boundaryBehavior` |
| `timer_tick_to_math_trigger` | timer → math_node | 每次 Timer Tick 使目标 Math Node 重算并更新 lastResult | — |
| `timer_value_to_text` | timer → text | 输出当前值、Tick 次数或步长，由 Text 负责格式化展示 | `sourceField`, `precision` |
| `event_to_animation` | button/timer → text/progress/slider/switch/select/input/image/surface/base_box/indicator/message_flow | 按钮点击或定时器触发时，让目标组件播放它配置好的动画。动画类型与时长在目标组件的「外观 … | — |
| `event_to_indicator` | button/timer → indicator | Button 点击或 Timer Tick 使状态灯短暂闪烁，随后恢复原状态 | `flashColor`, `durationMs` |
| `indicator_color_to_switch` | indicator → switch | 当前激活颜色匹配时开关为 true，不匹配时为 false | `triggerColor` |
| `indicator_color_to_text` | indicator → text | 当前激活颜色匹配时显示匹配文案，否则显示未匹配文案 | `triggerColor`, `matchText`, `mismatchText` |
| `indicator_color_to_enabled` | indicator → button/input/slider/switch/select/indicator | 当前激活颜色匹配时启用目标，不匹配时禁用 | `triggerColor` |
| `indicator_color_to_locked` | indicator → button/input/slider/switch/select | 当前激活颜色匹配时锁定目标编辑，不匹配时解除锁定 | `triggerColor` |
| `indicator_color_to_frozen` | indicator → progress/math_node | 当前激活颜色匹配时冻结 Progress 或 Math Node，不匹配时恢复 | `triggerColor` |
| `indicator_color_to_visible` | indicator → surface/surface_art/primitive_art/text/progress/slider/input/button/switch/select/indicator | 当前激活颜色匹配时显示目标，不匹配时隐藏目标 | `triggerColor` |
| `name_to_text` | surface → text | 源组件标识名称回写为目标文本 | — |
| `to_string` | any → indicator | 将上游原始值交给状态灯自身的状态规则解释 | — |

### 7.5 发送消息：让 input 自己发，不要指望按钮带内容

**引擎里没有 `input → button` 的取值方案。** 所有指向 button 的方案
（`input_nonempty_to_button_enable` 等）都只控制**启用/可见**，
传不了值。

`_resolveSendText` 对 button 的逻辑是：先查 linker 联动值，
查不到就回落 `properties['text']`。所以：

```
❌ input 写内容 + button 标 sendsMessage
   → 点按钮只发出按钮上那几个字，输入框内容根本没上传

✅ input 自己标 sendsMessage
   → 回车即发送框内文字，发完自动清空
```

```json
{"type": "input", "properties": {
  "placeholder": "写下你的行动，回车发送",
  "text": "", "committedValue": "",
  "sendsMessage": true          ← 标在 input 上
}}
```

#### 那按钮还能做什么

按钮适合发**固定指令**（选项式剧情：「向左走」「攻击」）。
需要携带数值时，把数值配成**数据通道**进 Prompt，
按钮文案写成半句话让 AI 去补：

```
滑块「购买数量」→ dataChannel(session_var, read: prompt)
按钮文案「按当前数量向店主买下灯油」
系统提示里写明：具体数值从界面数据段读，不要反问玩家
```

⚠️ `slider_commit_to_math_param` 读的是 **`committedValue`**，
拖动过程中只有 `current` 在变——**松手提交后**参数才更新。

### 8. 多页面与页面跳转

`灰港迷雾_跑团卡.llmcard` 演示了这一块。页面结构：

```
scene 一套 UI 内含 5 页
  主菜单(base) ⇄ 角色卡(base) ⇄ 日志(base)
       ⇅
     行囊(base)
       └ 骰子面板(overlay，挂在主菜单下)
```

#### 运行时支持三种跳转方式

已核实源码（`ui_assembly_runtime_view.dart`）：

1. **滑动手势** —— `page.gestures` 里配 `direction → targetPageId`
2. **点叠加页外部** —— 自动回父页，无需配置
3. **按钮换页** —— `button --linker(button_to_page_route)--> page_router`

第 3 条曾长期只登记在方案表里、**没有运行时消费方**（连线保存成功但
点了没反应），已补齐。用法：

```
button 元素  --linker: button_to_page_route-->  page_router 元素
                                                  └ properties.route = {
                                                      action: switch_base_page | open_overlay,
                                                      targetPageId: "pg_xxx",
                                                      transition: base_slide | base_fade | overlay_fade,
                                                      durationMs: 260 }
```

linker 上可写 `sourceGesture: tap | double_tap | long_press`
指定用哪种点击触发，缺省为 `tap`。
`page_router` 是逻辑件，摆在 PCB 外的机房区，默认尺寸 124×56。

#### 手势的结构

写在 `page.gestures` 数组里，不是元素：

```json
"gestures": [
  {"direction": "swipe_right", "action": "switch_base_page",
   "targetPageId": "<目标页id>", "transition": "base_slide", "durationMs": 220},
  {"direction": "swipe_up", "action": "open_overlay",
   "targetPageId": "<叠加页id>", "transition": "overlay_fade", "durationMs": 180}
]
```

`direction` 四选一：`swipe_left` / `swipe_right` / `swipe_up` / `swipe_down`。

#### 多页面必须自查的四件事

| 检查项 | 说明 |
|---|---|
| **每页都能回主菜单** | 否则玩家滑进去就出不来。叠加页靠点外部返回，不用配 |
| **左右手势互逆** | A 右滑到 B，B 就该能左滑回 A，否则手感错乱 |
| **每个 base 页都要有 keyAction 按钮** | scene 接管全屏，每页都得有出口 |
| **叠加页必须有容器面** | 带 `is_overlay_container: true` 的 surface。点它以外的区域才会关闭；没有它就关不掉 |
| **不要占用 swipe_up** | 消息流通常在页面中段，玩家上滑是想看历史记录，占用它必然误触（实测反馈）。叠加页用 `swipe_down` 打开 |

叠加页的容器面**不要铺满 PCB**——铺满了就没有「外部」可点，
玩家会被困住。跑团卡里骰子面板是 300×340，居中留出四周空白。

#### 页面字段

```json
{
  "id": "pg_xxx", "name": "角色卡", "type": "base",   // base | overlay
  "parentPageId": null,     // overlay 必须指向它挂靠的 base 页
  "sortOrder": 1,
  "elements": [...], "gestures": [...], "propertyOverrides": []
}
```

**叠加页只能挂在平级页下，不能嵌套叠加页**（叠加层不能变成子叠加层）。

### 9. 图片

`image` 组件的 `assetPath` 若填本地路径，分享时会被自动内联成 data URI。
LLM 生成时**不要编造本地路径**——要么留空，要么用 `https://` 网址。
