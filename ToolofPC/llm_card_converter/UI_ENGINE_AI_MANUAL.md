# LLM Project · UI 引擎与转译 AI 实操指南 (UI_ENGINE_AI_MANUAL)

> 本文档为转译 AI（包括 Stage 2 AI 智能归类、Stage 3b AI 视觉特征提取、Stage 4 AI 自检精修）的唯一、权威**背景能力手册**。
> 转译 AI 在进行任何决策、分析、审计或意图分类前，必须完全对齐并遵循本手册。

---

## 第一部分：UI 引擎（llm_ui_engine）原语与逻辑芯片契约

本项目采用「数据-模板分离」的声明式 UI 架构。AI 只需提取设计意图（Design Tokens）和协议连线（Linkers），禁止手动捏造复杂的 PCB 几何坐标。

### 1.1 可见物理原语 (Visual Primitives)

所有的可见原语均支持 **ARGB 32位整数颜色表示**（如 `#010409` 必须转换为 `0xFF010409`），不支持任何 `#RRGGBB` 字符串。

*   **`surface` (面板容器)**
    *   **材质 (material)**：`0=glass` (高斯模糊毛玻璃), `1=solid` (实色不透明), `2=gradient` (线性双色渐变), `3=outline` (纯边框)。
    *   **形状 (shape)**：`0=rectangle`, `1=rounded` (圆角矩形，默认), `2=capsule` (胶囊形), `3=circle` (圆形)。
    *   **属性**：`borderRadius` (0.0 ~ 32.0 像素); `opacity` (0.0 ~ 1.0)。
    *   **容器属性**：支持 `is_overlay_container: true`（标记为叠加弹仓容器，当被 page_router 弹出时可作为弹窗底板）。
*   **`text` (文本块)**
    *   **属性**：`fontSize` (8.0 ~ 24.0); `textAlign` ('left' / 'center' / 'right'); `overflow` ('ellipsis' / 'wrap'); `richText` (布尔，启用 Markdown 渲染)。
*   **`progress` (进度条)**
    *   **属性**：`min` (缺省 0), `max` (缺省 100), `current` (当前值), `trackColor` (底槽轨道色)。支持各种 shape (如胶囊、心形、星形)。
*   **`button` (点击热区)**
    *   **定位**：**运行期彻底隐形**，仅作为点击热区。外观完全依靠其背后的 `surface` 或 `text` 承载。
    *   **属性**：`sendsMessage` (布尔，点击直接发送文本至对话流); `keyAction` (布尔，开场白确认入口); `messageText` (点击时要发送的特定文本)。
*   **`line` (分割线)**
    *   **属性**：`thickness` (1.0 ~ 32.0 像素); `lineStyle` ('solid' 实线 / 'dashed' 虚线 / 'dotted' 点线); `axis` ('horizontal' / 'vertical')。

---

### 1.2 后台逻辑芯片件 (Logic Primitives)

这些组件在运行期**彻底隐形** (`SizedBox.shrink`)，不占用物理像素，仅存放于 PCB 坐标之外（如负 X 轴后台区），充当逻辑与数据总线。

*   **`page_router` (页面路由器)**
    *   **职责**：负责控制平级页面（Base Pages）的切换，或弹出、关闭叠加页面（Overlay Pages）。
    *   **路由配置 (route)**：`targetPageId` (目标页ID); `action` ('switch_base_page' 平级切换 / 'open_overlay' 打开弹层 / 'close_overlay' 关闭弹层); `transition` ('base_slide' 平移 / 'overlay_fade' 遮罩渐变); `durationMs` (过渡时长，默认 180~220ms)。
*   **`math_node` (算术计算节点)**
    *   **职责**：提供无 JS 运行环境下的数学公式与代数逻辑计算，用纯原生算法**完美平替**酒馆 cards 的 JS 加减逻辑。
    *   **属性**：`expression` (支持 `paramA + paramB`, `paramA - paramB`, `paramA * paramB`, `paramA / paramB` 等代数式，支持逻辑比较及括号优先级); `paramA`, `paramB`, `paramC`。
*   **`timer` (定时脉冲器)**
    *   **职责**：周期性发出 Tick 脉冲。支持启动、暂停，可用于数值的自动流逝与回复计算（如体力、时间变化）。

---

### 1.3 中央联动矩阵 (Linkers Scheme Registry)

我们沉淀了多达 **68 条通用协议连线**，将物理组件与数据逻辑完全打通。以下为转译 AI 必须最优先调用的高级方案：

| 方案 ID | 源组件 ➔ 目标组件 | 功能描述与典型用途 |
|---|---|---|
| **`button_to_page_route`** | `button` ➔ `page_router` | **页签与弹层切换**：点击按钮触发路由器换页或弹出 Overlay 遮罩。 |
| **`click_to_surface_press`** | `button` ➔ `surface` | **按压动画反馈**：解决 button 隐形无反馈的痛点，给底板增加下陷反馈。 |
| **`value_to_math_param`** | `any` ➔ `math_node` | **数值代数注入**：将进度条、滑块或输入框的当前值送入计算节点。 |
| **`result_to_progress`** | `math_node` ➔ `progress` | **公式驱动进度条**：将代数式计算结果实时反映到血条/精力条上。 |
| **`progress_threshold_to_switch`** | `progress` ➔ `switch` | **属性阈值触发**：HP < 20% 时，自动开启某个隐形开关（驱动警报）。 |
| **`sum_to_display`** | `any` ➔ `any` | **多源数值聚合**：将力量、敏捷、智力多个滑块汇总，自动限制配额点数。 |
| **`event_to_animation`** | `any` ➔ `any` | **动画唤醒**：按钮点击、数值变动时，让目标组件播放水波纹或发光动画。 |

---

## 第二部分：AI 视觉特征提取 (Stage 3b) ➔ 物理编译器契约

当进入 Stage 3b（AI 视觉特征提取）时，AI 的任务是**阅读原卡 CSS/HTML，输出扁平的设计标记（Design Tokens）JSON，绝对不直接生成坐标或嵌套树**。

### 2.1 AI 提取输入
*   原卡主正则脚本的 `replaceString` (通常包含大量的 `div`, `background`, `border-radius`, `box-shadow` 等 CSS 样式表)。

### 2.2 AI 输出契约 (Visual JSON)
AI 必须且只能输出以下扁平结构的 JSON：
```json
{
  "pcbColor": "#RRGGBB",        // 提取原卡的外层 wrapper/背景底色
  "panelColor": "#RRGGBB",      // 提取原卡的主面板色
  "titleColor": "#RRGGBB",      // 提取原卡的标题文字色
  "labelColor": "#RRGGBB",      // 提取原卡的字段标签字色
  "valueColor": "#RRGGBB",      // 提取原卡的数值/文本读数字色
  "barFillColor": "#RRGGBB",    // 提取原卡的进度条前景色
  "barTrackColor": "#RRGGBB",   // 提取原卡的进度条槽位背景色
  "accentColor": "#RRGGBB",     // 提取原卡的交互色/按钮色
  "buttonBgColor": "#RRGGBB",   // 提取原卡按钮背景色
  "borderRadius": 12.0,         // 提取原卡面板边框圆角大小（0.0 ~ 32.0 px）
  "glow": true                  // 原卡是否有 glowing 变色、box-shadow、发光或脉冲动效
}
```

### 2.3 物理编译器（代码层）自适应策略
代码编译器（`UiAssemblyBuilder`）读取 AI 提取的 `UiVisualTheme` 后，执行以下自适应绘制：
*   **开场选择页 (Opening UI)**：
    *   在顶部开辟 `110px` 的大剧情叙事文本卡片，完美收纳开场白正文，营造出包裹聊天流的宏大开局仪式感。
    *   下方自动平铺双列并排的**居中大动作按钮网格**，切分宽度与间距。
*   **常驻面板 (Companion UI / Scene UI)**：
    *   物理宽度硬性约束在 **`212px` (Companion)** 或 **`360px` (Scene)**。
    *   **布局建议（而非强制）**：为了兼顾视觉的极简舒展和多维丰富属性，建议采用多页签或叠加页结构。
    *   **智能分流参考**：
        *   核心展示：高对比度展示属性进度条（生命红、精神紫、体力绿、饱腹橙），装饰 Emojis。
        *   档案详情：展示称号、编号、罪名等信息。
        *   交互选项：集中放置该卡片提取到的所有交互动作，让玩家在后续所有轮次中能随时点击。
    *   **页签对齐**：若使用多页签，建议统一各底板尺寸，确保换页时面板大小恒定。

---

## 第三部分：高级平替案例 ➔ 鸣潮 Solaris-3 变量插件卡

在没有 JS 运行环境的沙箱限制下，AI 必须深度思考，如何动用我们的**逻辑芯片（Math Node, Timer）**来进行对等平替还原：

### 3.1 原卡逻辑 (JS)
1.  原卡包含一个 `[共鸣度]` 属性，起始为 0。
2.  开场选项点击 `[执行高强度战斗]` ➔ 执行 JS：`character.vars.resonance += 15; if (character.vars.resonance >= 100) trigger_critical();`。
3.  时间机制：随着现实时间推移，共鸣度会以每秒 `0.5` 点的频率自动消退。

### 3.2 AI 芯片化平替设计
AI 拒绝 JS，并在转译配置中优雅声明以下原生联动件：
1.  **添加计算芯片**：在 Page 1 之外的逻辑位画一个 `math_node` (ID: `calc_resonance_add`)，公式为 `paramA + 15`，`paramA` 绑定“共鸣度”进度条。
2.  **绑定按钮触发**：
    *   将 `[执行高强度战斗]` 按钮的点击（`tap`），通过 `click_to_math_trigger` 方案连线到该 `math_node` 触发口。
    *   计算结果通过 `result_to_progress` 写入“共鸣度”进度条。
3.  **添加时间芯片**：
    *   在后台逻辑区画一个 `timer`，配置 Ticking 间隔为 `1000ms`。
    *   从 `timer` 连一条 `timer_tick_to_progress_decrement` 协议线到“共鸣度”进度条，参数 `step` 设为 `0.5`，边界行为设为 `stop` (到 0 停止)。
4.  **添加阈值开关**：
    *   从“共鸣度”进度条连线一条 `progress_threshold_to_switch` 到一个隐性开关 `switch_resonance_overflow`，条件设为 `>= 100`。
    *   开关打开时，利用 `boolean_to_visible` 自动让常驻警告面板 `[共鸣溢出]` 闪红显现，并触发 event_to_animation 发光动画。

*这在移动端安全线程上运行，零安全风险、免 JS 损耗，完美实现甚至超越了酒馆 MVU 卡的动态控制体验。*

---

## 第四部分：Stage 4 AI 智能自检与精修审计契约 (Audit Protocol)

在 Stage 4 中，AI 质检助手不仅要审查文本设定，更要针对我们最新的 **多页签自适应布局 (Tab-bar Layout)** 进行深度的视觉和交互审计。

### 4.1 审计重点关注清单 (Checklist)

1.  **Contrast & Accessibility (对比度审查)**：
    *   大卡片中的小字、页签文字和进度条标签的颜色，是否与底色卡板（`panelColor` / `pcbColor`）有足够的对比度？WCAG AAA 7:1 门槛。
2.  **Missing Properties (属性漏转审查)**：
    *   原卡正则中所有的 `findRegex` 数据字段，是否被 100% 正确编入了 Page 1（属性）和 Page 2（档案）中？有没有漏转导致数据静默丢失？
3.  **Overcrowding Check (拥挤度与换行审查)**：
    *   检查 Page 2 和 Page 3 中的长选项文案。如果选项超过 3 个字且处于多列排版，强烈建议重构为单列流式布局，防范多页签下的文字溢出与堆叠。
4.  **Linkers Integrity (连线与跳转契约审计)**：
    *   检查多页签 Tab 栏中所有的未激活 Tab。它们背后的 `_button` 热区是否都完美连结了专门指向该 Page ID 的 `page_router` 逻辑芯片？

### 4.2 自校正输出
发现问题时，质检 AI 不得捏造假代码，而必须吐出精修清单（`refineIssues`），如果发现致命缺陷（如连线断开），自动拦截产物并喂回重算，实现**转译器内部的 100% 物理闭环**。
