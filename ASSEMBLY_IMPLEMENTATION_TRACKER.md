# Assembly 实施跟踪档案 v1

> 用途：把 Assembly 页从“设计定稿”拆成“施工步骤 + MVP 完成定义 + 延后增强项 + 灵感备忘”。
> 
> 对应产品蓝图：`ASSEMBLY_GENERIC_TEMPLATE_FINAL.md`
> 
> 使用方式：
> - 每完成一个阶段，就更新“当前状态”与“已完成项”
> - 非阻塞问题优先记入“延后增强 / 灵感池”，避免卡在单一步骤太久
> - 只有阻塞性问题才中断当前步骤单独修复

---

## 一、当前协作规则

### 1.1 开发节奏
- 按步骤做 MVP，不一次性做完整大功能
- 每一步做到“可测试、可提交、可回退”
- 每一步完成后：
  1. commit
  2. push
  3. 本地测试
  4. 收集反馈
  5. 再进入下一步

### 1.2 问题处理原则
- **小问题**：优先并入下一步一起修，不轻易打断节奏
- **严重问题 / 阻塞问题**：单独修复并 push
- **设计灵感 / 非当前阶段必做项**：先记录，不立即打断当前步骤

### 1.3 交互设计变更原则
- 可在测试中调整 **HUD 交互与显示方案**
- 只要不破坏以下核心骨架，表现层可持续迭代：
  - PCB 作为硬边界
  - 多页面 base / overlay 结构
  - 模板 / 实例 / 覆写三层结构
  - SSOT / binding / Prompt 通路

---

## 二、阶段总览（施工地图）

| 阶段 | 名称 | 当前状态 | 是否允许进入下一步 |
|------|------|----------|------------------|
| A2 | 通用画布骨架 + PCB + 资产栏拖放 + 边界约束 | 基础版完成 | ✅ |
| A6 | 多页面数据层 + 图层面板基础 | 基础版完成 | ✅ |
| A3 | Composite 黑盒 + 覆写表单基础 | A3-1 / A3-2 / A3-3 / A3-4 基础版完成 | ✅ |
| A7 | 页面路由器最小版 | 基础版完成，测试通过 | ✅ |
| A7.5 / A5-0 | Assembly 资产区最小补全 | 基础版 + 体验收口完成，待本地测试 | ✅ |
| A4 | 暴露端口体验增强 | 基础回归完成，测试通过 | ✅ |
| A5 | Assembly 内 linker 连线 | 配置式 MVP 完成，待本地测试 | ✅ |
| A8 | 运行时等比缩放与画布约束完善 | 基础版完成，待本地测试 | ✅ |
| A9 | 页面手势配置 + 轻量动画 | MVP 完成，待本地测试 | ✅ |
| A9.5 | 通用模板基础版 | A9.5-5 全部子步骤完成，测试通过 | ✅ |
| A9.6 | SSOT / LLM 数据交互 MVP | A9.6-1~4 全部完成，全链路联调通过 | ✅ |
| A10 | mode 差异逻辑收口 | 全部子步骤完成并测试通过 | ✅ |
| A11 | 消息流窗口 | 全部完成并测试通过 | ✅ |
| A12 | 高级动画 | 未开始，排在 A14 之后 | ⏳ |
| A13 | 玩家参与的会话初始化 | A13-1/2/3 全部完成并测试通过 | ✅ |

> **⚠️ 表中的 ✅ 一律指「该功能点的运行时链路跑通」，不代表编辑体验完整。**
> 绝大多数阶段停在 MVP。Assembly 编辑器（6862 行）与 Studio（11000 行）
> 仍有大量能力差距，见下方「A14：Assembly 编辑器深层交互」。
> 不要因为上表全绿就以为 Assembly 已经可交付。

## A14：Assembly 编辑器深层交互（A14-1/2/3 完成；余 linker 画线、PCB 自定义）

用户指出：前面的阶段大部分只完成了 MVP，编辑器的深层交互几乎没做。
核实属实，下面是与 Studio 的能力差距。

### 完全缺失的能力

| 能力 | Studio 现状 | Assembly |
|---|---|---|
| 删除 / 多选删除 | 有确认弹窗、`sealed` 保护、删除后重整连线 | ❌ 无 |
| 复制 / 复制历史 | 含父子绘制顺序处理 | ❌ 无 |
| 组件锁定 | 有 | ❌ 无 |
| 层级排序 | 上移 / 下移 / 置顶悬浮按钮组 | ❌ 无 |
| 容器归属调整 | 弹窗选父层 | ❌ 无 |
| PCB 自定义 | — | 仅尺寸 / 圆角 / 底色 |
| linker 画线交互 | `linker.dart` 990 行拖拽连线 | ❌ 仅配置对话框 |
| 组件专属编辑器 | `editors/` 7 个文件（indicator 665 行、select 530 行、timer 427 行…） | ❌ 全部共用一个通用参数对话框 |
| 抽屉 / 图层面板 | `drawers.dart` 1014 行 | 仅页面图层 |

### 这不是偶发疏漏

A11-2「方案参数编辑器漏做」、A13-2「三级选择器藏得太深」
都不是独立 bug，而是**同一个根因的症状**：
Assembly 的实例编辑器是一个通用对话框，
每加一种配置就往里塞一段，既容易漏、又越来越难找。

补齐 `editors/` 那一层（按组件类型分文件）大概率是解法，
但这是个大工程，需要单独规划子步骤。

### 盘点结果（已核实，非估计）

#### 1. 资产栏：14/16，缺 2 个逻辑件

Assembly 资产栏实际有 14 项（logic 2 + interaction 5 + display 7），
比印象中完整。但缺两个**已经能渲染、能联动、却拖不出来**的组件：

| 组件 | 渲染 | 尺寸预设 | linker 方案 | 资产栏 |
|---|---|---|---|---|
| `timer` 定时脉冲 | ✅ | ✅ 112×52 | ✅ 多条 | ❌ **缺** |
| `math_node` 数学节点 | ✅ | ✅ 120×56 | ✅ 多条 | ❌ **缺** |

这两个是纯逻辑件（运行时隐形），补进资产栏成本很低，
但没有它们就做不了「定时触发剧情」「属性公式计算」这类玩法。

`primitive_art` / `surface_art` / `light_effect` 三个装饰类
渲染器支持但两边资产栏都没有，属于 Studio 侧的历史遗留，暂不处理。

#### 2. 实例编辑器：通用对话框覆盖 11 种类型

`_showAtomInstanceEditorDialog` 明确排除
`linker` / `page_router` / `math_node` / `timer`
（前两者有专属配置对话框，后两者根本进不来——因为资产栏就没有）。

Studio 侧有 7 个专属编辑器文件：

| 编辑器 | 行数 |
|---|---|
| `indicator_editor` | 665 |
| `select_editor` | 530 |
| `timer_editor` | 427 |
| `math_node_editor` | 388 |
| `image_editor` | 355 |
| `line_editor` | 266 |
| `switch_editor` | 261 |

Assembly 把这些能力压缩进了一个通用对话框的 `if (type == 'xxx')` 分支里，
必然做不到同等深度。

#### 3. 画布操作：全缺

删除 / 复制 / 锁定 / 层级排序 / 容器归属，Assembly 一个都没有。
这是缺失感最强的一类——没有删除键，作者摆错了只能重建整个方案。

#### 4. 灵感池（见第四章）

4.1~4.6 六项延后增强也都还没做。

### 建议的实施顺序

**A14-1 画布基础操作**（删除 / 复制 / 锁定 / 层级 / 容器归属）
理由：缺失感最强，且不依赖任何其他改动。
「没有删除键」是硬伤，优先级明显高于其他项。

#### A14-1a 统一选中机制（已完成，测试通过）

**这是被漏掉的前提**（用户指出）：Assembly 此前只有
`_selectedCompositeId`，且仅用于展开复合组件的覆写槽位——
**原子组件根本没有选中态**，所以「选中后弹出针对性工具」无从谈起。
盘点时只对比了「有没有删除功能」，没检查承载它的选中态。

- `_selectedCompositeId` 泛化为通用选中，新增 `_selectedElementId` /
  `_selectedElement` 访问器；`_selectComposite` 保留为兼容别名。
- 原子组件 tap / 双击 / 拖动开始时都会选中。
- 选中框用 `Positioned.fill` 叠描边，**不给容器加 border**——
  后者会改变布局尺寸，让组件在选中/取消时跳动。
- 点画布空白取消选中（复用已有的 `onTap`）。

#### A14-1b 左侧操作栏（已完成，测试通过）

**不照搬 Studio 的两侧布局**（用户判断，核实后成立）：

Studio 有 10 个 42×42 悬浮按钮分列左右。但 Assembly 的空间账不同——
以 390×844 屏为例，顶部 HUD 约 56、底部资产栏约 150，
PCB 宽 300~360 时左右各只剩 15~45px，
Studio 那套「42 按钮 + 16 边距 = 58px」会直接压在 PCB 上。

更关键的是编辑对象不同：Studio 编辑自由画布上的散装组件，PCB 概念弱；
Assembly 的 PCB 有固定边界，作者要频繁贴边摆元件，
两侧悬浮按钮恰好挡住最需要精确操作的区域。

**放左侧**（用户指定）：PCB 的形变把手在右侧与下侧，左边是唯一空闲的边。
竖列可滚动，整条左边都可用。

当前 5 个按钮：锁定 / 复制 / 上移 / 下移 / 删除。
容器归属留到后续，撤回 / 恢复 / 清空画布 / 批量删除这类
**整体性功能另议位置**（用户提出，不放元素操作栏）。

#### 三条实现要点

**1. 层级顺序容易写反。**
`_elements` 的顺序即 Stack 绘制顺序，**越靠后越上层**，
所以界面上的「上移」对应列表索引 **+1**。初版写成 -1，已修正并加测试。

**2. 删除必须连带清理联动器。**
留着悬空连线比删掉更糟：`isSchemeSelectable` 仍判为合法，
运行端却找不到源/目标，表现为「配了但没反应」，极难排查。
删除前弹窗告知会牵连几条，确认后一并删除。
覆写槽位也要同步清理，否则留下指向不存在组件的孤儿配置。

**3. 锁定分两档，复用模型已有字段。**

初版自造了 `properties['locked']`，是错的——`UIElement` 上本来就有
`layoutLocked` / `sealed` 两个字段，Studio 侧一直在用。
自造字段会导致方案在两个编辑器间迁移时锁定状态丢失。

| 档位 | 字段 | 锁住什么 |
|---|---|---|
| 半锁定 | `layoutLocked` | 位置 / 形变 / 旋转 |
| 全锁定 | `sealed` | 以上 + **联动连线** |

全锁的语义（用户指定，与 Studio 一致）：有连线时不能切换或断开，
没连线时连不上，配置联动器时该元素被跳过。
实现上 `_linkerCandidates` 排除 `sealed` 元素，
且已配好的连线若有一端后来被全锁，打开配置会被拦下——
否则「锁死连线」形同虚设。

开全锁时自动带上半锁（全锁必然包含半锁的约束）；
解除全锁时保留半锁，让作者自己决定要不要一并解开。

两档都只禁拖动与结构操作，仍允许选中与双击编辑。

**两档共用一栏**（用户设计，省一格常驻占位）：

| 状态 | 可见按钮 | 点半锁 | 点全锁 |
|---|---|---|---|
| 未锁 | `[半锁定]` | → 半锁 | — |
| 半锁 | `[已半锁] [全锁定]` | → 未锁 | → 全锁 |
| 全锁 | `[已全锁]` | — | → 半锁 |

默认只露一个按钮，半锁后**向右**追加全锁入口，
全锁时半锁隐藏、全锁顶替其位置。

**向右展开而非向下**（用户指定）：
- 并排更能体现「同一组的两个档位」，向下会被当成与复制 / 删除
  并列的独立功能；
- 向下插入会把下方所有按钮推移一格——手指刚点完半锁，
  复制键就跑到了原本删除键的位置，极易误触。

代价是展开态会临时压住 PCB 左缘约 50~100px（视屏宽与 PCB 宽而定），
但它只在半锁时出现、不是常驻，比整列位移可接受。
间距因此收到 4px。

Column 需显式 `crossAxisAlignment: start`：
锁定那一行展开时变宽，不指定的话其余按钮会跟着居中，整列左右晃动。

未锁状态**不给全锁入口**是有意的：否则作者跳过半锁直接全锁，
解锁时会突然回落到半锁态，显得没来由。
这也让「解除全锁保留半锁」的既定语义前后自洽。

全锁 → 未锁需要两步，但这与上述语义一致，不算绕路。

**4. 选中外框按组件形状描边。**

初版用固定圆角矩形，与 Studio 观感不一致。
改为共用 `DashedSelectionBorderPainter`（灰白交替虚线）——
圆形指示点画圆、开关画胶囊、心形进度条画心形。

该 painter 从 `ui_studio_page/painters.dart` 提取到
`services/ui_engine/`：原文件是 `part of ui_studio_page.dart`，
Assembly 无法导入，而两个编辑器的选中框必须长得一样。
配套的 `_outlineShapeOf` / `_outlineBorderRadiusOf` /
`_isPerfectCircleOutlineOf` 三个纯查表函数直接照搬。

**5. 复制必须走 jsonEncode/Decode，不能用 `_deepCloneValue`。**

后者对嵌套 Map 返回 `Map<dynamic, dynamic>`，而
`UIElement.fromJson` 里 `json['offset'] as Map<String, dynamic>?`
是硬类型转换，会直接抛 `_TypeError`——**首轮测试点复制即崩溃**。
JSON 往返能保证嵌套层的键类型正确。

联动器不支持复制：它的源/目标指向具体元素，
复制出来必然是重复连线，作者要的几乎总是「再连一条新的」。

测试：`test/assembly_element_actions_test.dart`。

**A14-2 补齐 timer / math_node 资产项**（已完成，测试通过）
理由：成本最低（渲染与联动都已就绪，只差资产栏入口），
却能立刻解锁两类玩法。适合穿插在大工程之间做。

实际做下来比预想的多一步：**光加资产栏入口不够**。
`_showAtomInstanceEditorDialog` 明确排除了这两个类型，
拖进画布后双击**什么都不会发生**——参数全部锁死在模板默认值上。

因此各补了一个精简编辑器：

| 编辑器 | 覆盖参数 |
|---|---|
| 定时器 | 间隔 / 首次延迟 / 最多触发次数 / 脉冲类型 / 步长 / 循环 / 初始运行 |
| 计算节点 | 运算方式 / 参数 A·B·C（可各自启停）|

不复用 Studio 的 `editors/*.dart`：那些是 `part of ui_studio_page.dart`，
Assembly 导不了；且 Studio 版还带图层选择与坐标微调，
这两项在 Assembly 里分别由页面图层与直接拖动承担。

#### 三处容易写错的地方

**1. 定时器间隔必须 clamp 到正数。**
填 0 会让它每帧触发，直接卡死界面。保存时 `clamp(0.1, 3600)`。

**2. `activeParams` 要按 A/B/C 固定顺序存，不能按勾选顺序。**
连续减法这类运算的结果与顺序相关，
按勾选顺序存会导致「取消再勾选」改变计算结果。

**3. 「初始为运行状态」只在 manual 模式生效。**
`resolveTimerRunMode` 的逻辑是：接了开关 → `controlled`，
接了按钮的「点击启停」→ `manual`，都没有 → `auto`（一律自动跑）。
`isRunning` 仅在 manual 下被读取。
初版把开关标成「进入运行时自动启动」是错的，已改为说明三种启停方式。

**4. 默认尺寸必须与 Studio 一致（测试后修正）。**

Assembly 原先给 `math_node` 120×56、`timer` 112×52，
而 Studio 是 180×44 / 140×54。

两边**共用 `UIRenderer` 的同一套渲染**，画的是一行公式
（`3 + 5 = 8`）或一行状态文本，**宽而扁**才放得下。
Assembly 那套偏窄偏高，`FittedBox` 会把公式压得很小，
观感与 Studio 差很多。已改为与 Studio 相同。

> 通用规则：**共用渲染器的组件，两边的默认尺寸表也必须同步。**
> 渲染逻辑一致不代表观感一致——尺寸决定了内容如何被缩放。

测试：`test/assembly_logic_atoms_test.dart`。

#### A14-1d 精确几何 / 精确位移（已完成，测试通过）

参照 Studio 的两个既有工具，形态尽量不做差异（用户要求）：

| 工具 | 形态 |
|---|---|
| 精确几何 | 弹窗，X / Y / 宽 / 高 / 旋转五项 |
| 精确位移 | 底部居中 3×3 D-Pad，逐像素挪动 |

沿用 Studio 的尺寸区间：面类 4096（容器可能要铺满甚至超出 PCB），
其余 600×400；进度条下限 12×6（细长条是常见做法，
用通用下限 20 会把它撑胖）。

**位移不限制负坐标**：逻辑件常被特意拖出 PCB 当后台节点。

两处 Assembly 特有的调整：
- D-Pad 抬到 `bottom: 168`——资产栏约 150 高，
  照搬 Studio 的 24 会被压在底下点不到。
- 换选中元素时自动收起 D-Pad：否则手指还停在原处，
  下一次点击会挪动刚选中的另一个组件。
- 中心键显示当前坐标，兼作「正在动哪个组件」的确认。

布局有个易错点：上下行的占位宽必须是 `箭头 40 + 间距 12 = 52`，
否则三行的箭头对不齐；居中偏移取总宽 144 的一半 = 72。有测试锁定。

测试：`test/assembly_geometry_tools_test.dart`。

#### 首轮测试暴露的四个问题（均已修复）

**1. 输入法未确认时关弹窗崩溃**（`controller used after disposed`）
本文件其余弹窗早有 `closeDialog` 约定——先 `unfocus()`、等一帧再 pop。
新加的三个弹窗（几何 / 定时器 / 计算节点）都漏了，
并且 `dispose()` 也要延到 `addPostFrameCallback`：
弹窗退场动画期间 TextField 仍会重建。

> **约定：本文件里任何带 TextField 的弹窗，
> 关闭一律走 `closeDialog`，controller 一律延后一帧释放。**

**2. 键盘弹出时对话框 overflow 近十万像素**
几何弹窗的 Column 没有包 `SingleChildScrollView`。
键盘占掉一半屏高后可用空间骤减，必须可滚动。

**3. 旋转后选中框不跟随 → 修复时又引入「角度翻倍」**
Assembly 的画布**从未在外层应用过 `rotation`**——元素转了，
虚线框还是正的。改为在 `Positioned` 内套 `Transform.rotate`
包住整个节点，边框与徽标就会一起转。

但只做这一步会**转两倍**（用户实测：输入 30° 变 60°，90° 变 180°）：
`UIRenderer.render` 内部**本来就**按 `element.rotation`
包了一层 `Transform.rotate`。

> **规则：旋转在整条链路上只能应用一次。**
> 画布若在外层包 `Transform.rotate`（为了让选中框跟随），
> 传进 `UIRenderer.render` 的副本就必须 `copyWith(rotation: 0.0)`。
> Studio 早就这么做了（`final elNoRot = el.copyWith(rotation: 0.0)`），
> Assembly 照搬外层包裹时漏了这一半。

注意 `_buildReadonlyPageElement`（祖先页只读层）**不要剥离**——
它没有外层包裹，那一次旋转正是它需要的。

**4. 微调键盘离资产栏太远**
初版 `bottom: 168` 是为了避开展开态的资产抽屉。
用户给出更干净的方案：**打开资产抽屉时直接取消选中**——
作者要拖新组件了，本来也不再关心上一个选中项。
于是不必为抽屉预留高度，`bottom` 收到 96
（收起态资产栏顶边约 82，留 14px 间隙）。

#### A14-1e 逻辑件不给几何按钮 + 标签流式排列（已完成，测试通过）

**逻辑件隐藏「几何」按钮**（用户判断）：
`linker` / `page_router` / `math_node` / `timer` 运行时不渲染，
宽高与旋转对它们没有意义，坐标也不需要精确到像素——
拖一下就够了。位置仍可拖动，作者会靠摆放位置给逻辑件分区归类。

**标签改为流式排列**（用户提出「能不能跟在一个标签后面加」）：

原先四个标签各写死一组坐标，其中两个直接重叠：

| 标签 | 原坐标 | 问题 |
|---|---|---|
| 锁定 | `left:2, top:-13` | **与容器面重叠** |
| 容器面 | `left:4, top:-14` | **与锁定重叠** |
| 数据通道 | `right:2, top:-14` | 暂无冲突 |
| 关键职责 | `left:4, bottom:-14` | 暂无冲突 |

一个面板同时被锁定 + 设为容器面时两者就叠在一起，
而且每加一个新标签都要重新找空位——写死坐标的必然结果。

改为**顶部一行、底部一行**，各用 `Wrap` 流式排列：
- `_topBadgesOf`：锁定 → 容器面 → 数据通道（状态类在前、配置类在后）
- `_bottomBadgesOf`：关键职责
- 新增标签直接往列表里加，不用再算坐标
- 用 `Wrap` 而非 `Row`：标签总宽超过组件宽度时换行，不会被裁掉

#### A14-1f 复合选中框 + 消息流示例（已完成，测试通过）

**复合组件去掉「实例黑盒」文字标签**（用户建议），
改用与原子组件同一套虚线框。原标签既占地方、又和其他标签抢位置，
且没有指示实际边界。

删标签时漏了同一分支里**另一处** `if (isSelected)`——
一圈紫色圆角矩形 + 6% 紫底，与新的虚线框叠在一起
（用户测试发现）。同一条件在一个 children 列表里出现两次，
grep 关键词时很容易只改到其中一处。

外框形状**参考复合内部的容器面**（`is_container_boundary`）：
复合是黑盒本身没有形状，但作者摆它时看到的就是那个容器面，
贴合它才不会出现「框是方的、组件是圆的」。
三个 outline helper 都加了这层递归。

**消息流示例改为四句**（用户设计）：
两句玩家、两句角色**交替**出现——单看一两句分不出气泡样式差异，
四句才能判断左右对齐、颜色对比与换行。
每句都带「［示例·玩家］」「［示例·角色］」前缀，
让作者一眼知道这是测试内容且分得清谁是谁。

**预览也显示示例**（原先只有编辑器显示）。

这里有个判定陷阱：**不能靠「消息列表是否为空」区分预览与真实对话**——
运行时预览与「真实聊天但历史为空」都是空列表，
前者该显示示例，后者该显示「暂无消息」。
因此 `MessageFlowScope` 新增显式的 `isLive` 标记，
只有 `ChatAssemblyMount`（真实聊天挂载点）传 true。

#### 用户反馈：微调键盘可反向移植回 Studio

Assembly 版比 Studio 更紧凑（间距 12 vs 16），
且中心键显示实时坐标，兼作「正在动哪个组件」的确认。
Studio 的中心键是纯色方块，无信息。
**待办：把这个形态同步回 `ui_studio_page`。**

#### A14-1c 容器归属（已完成，测试通过）

核心不变式：**`_elements` 里每个组是一段连续块，父面永远在块首**。
因为列表越靠后越上层，父面在块首即为整组最底——规则 3 由此自动成立，
不需要每次比较父子下标。

五条规则的落点：

| 规则 | 实现 |
|---|---|
| 1 组内层级独立 | `_moveMemberWithinGroup` 只在同组兄弟间换位 |
| 2 父面带动整组 | `_moveSurfaceGroupOrder` 整块挪动 |
| 3 子恒高于父 | `_orderedSurfaceGroupElements` 父面置于块首 |
| 4 进出组立即重整 | `_normalizeSurfaceGroupOrder`，在归属变更那一刻调用 |
| 5 出组保留显示层级 | 解除归属时**不移动位置**，只清 `parentSurfaceId` |

运行时作用**已有基础**，不需新建：
`LinkerService.isElementVisibleInSurfaceHierarchy` 早已按
`parentSurfaceId` 递归判定可见性，`UIRenderer` 在非编辑态调用它，
父面隐藏时组内组件一起隐藏。`LinkerSnapshot` 也已带上 parents 映射。

#### 三处容易漏的地方

**1. 「能否移动」的判断要与移动逻辑同分支。**
初版按全局下标判断，组内成员会出现「按钮可点但没反应」——
它在全局还有后继，在组内却已是最后一个。
新增 `_canMoveElementLayer`，与 `_moveElementLayer` 用同一套分支。

**2. 顶层元素跨组时要整组跳过。**
否则顶层元素会卡进别人的组中间，把连续块切断，
破坏「组是连续块」的不变式。

**3. 删除容器面必须清理组员的 `parentSurfaceId`。**
留下悬空父级会让 `isElementVisibleInSurfaceHierarchy`
沿链查不到父级而返回 false——**整组在运行时凭空消失**。
清理后组员就地留在当前层级，与规则 5 一致。

逻辑件不参与归属（`_canAssignSurfaceMembership`）：
它们运行时不渲染，谈不上「在某个面板里」。

测试：`test/assembly_surface_group_test.dart`。

用户明确了这不只是编辑期分组，**要有实际运行时作用**，
且层级规则比 Studio 更严格：

1. **组内层级独立**：变换层级只在组内生效。
2. **父级面变换层级 = 整组一起变换。**
3. **子组件层级恒高于父级面**，只能在父级面之上排序。
4. **进组 / 出组时立即重整层级**——
   Studio 没做这点（`_moveMemberWithinSurfaceGroup` 是事后补救：
   发现 `selectedIndex < parentIndex` 才纠正），
   导致作者必须手动切一次层级才能真正进入组层级。**这次要在进组那一刻就重整。**
5. **出组后保留组内显示层级**，而不是回到进组前的旧层级——
   所见即所得，符合操作直觉。

运行端基础已具备：`LinkerService.isElementVisibleInSurfaceHierarchy`
已按 `parentSurfaceId` 递归判定可见性，父面隐藏时子组件跟着隐藏。

#### A14-3 第一步：数据通道独立成页 + 实例编辑器只留内容（已完成，测试通过）

**前提：先确立 Studio 与 Assembly 的分工**（用户提出）。
不能把 Studio 的工作全搬进 Assembly，否则 Studio 失去意义。
详见 `ASSEMBLY_HANDOFF.md`「Studio 与 Assembly 的分工」：

> Studio = 造零件（组件的内在行为规则）
> Assembly = 装机器（这个零件放哪、填什么、接什么数据）

据此 indicator 的状态规则引擎**只留在 Studio**；
select 的选项列表**两边都能编**（选项内容随剧情而定，属卡片内容）。
「Studio 2900 行 editors vs Assembly 一个对话框」这个对比
**不能直接当缺口来补**。

**数据通道独立成页**（用户设计）：
实例编辑器里只保留「启用开关 + 最终语义预览 + 进入按钮」，
十来项细节（语义来源 / 存放位置 / 卡片三级定位 / 读写策略 /
注入位置…）移到专项页。内容先原样承接，后续再优化。

一个必须注意的坑：**专项页保存后，实例编辑器不能再重建 payload**。
那些 `channelXxx` 状态变量仍是打开对话框那一刻的旧值，
重建会把刚配好的内容覆盖掉。
现在实例编辑器只在「刚打开开关且尚无配置」时落一份最小可用配置。

**实例编辑器去掉宽 / 高**（用户判断「简陋且重复」）：
精确几何已能改 X / Y / 宽 / 高 / 旋转，且带按类型的取值范围与 clamp，
比这里两个裸输入框完整。留着只是重复，还把真正该突出的
内容参数（文本、选项、图片来源…）挤到了下面。

保留的仍是 Assembly 的核心职责：实例名称、各组件内容参数、
圆角 / 透明度、语义标记、数据通道开关。

**A14-3 剩余：实例编辑器分文件 —— 暂不做（结论）**

分工线立起来之后重新评估：Assembly 该管的参数本来就不多
（实例名称 + 若干内容字段 + 标记 + 通道开关），
真正臃肿的数据通道已经独立成页。
再拆成七个文件属于过度设计。

改为**按需拆**：某个组件的参数实际用下来确实挤了，再单独拆它。
理由：工程量最大，但能根治「配置越塞越乱」——
A11-2 漏参数编辑器、A13-2 入口藏太深都是这个根因。
应在 A14-1 之后做，否则一边重构编辑器一边加画布操作容易互相干扰。

**A14-4 linker 画线交互**
理由：独立性最强，可随时插入。当前配置式已能用，只是体验差。

**A14-5 PCB 自定义增强 / 灵感池**
理由：锦上添花，无阻塞。

### A12 / A13 的归属（用户确认）

**A13：功能层面已关闭，不进 A14。**
三条待补项全部完成，属于运行时链路，不受编辑器缺口影响。

唯一遗留是「数据通道入口藏在四层折叠后面」。
它**不是 A13 特有的问题**——A11-2 的方案参数编辑器漏做是同一根因：
通用对话框每加一种配置就往里塞一段，既容易漏又越来越难找。

该遗留**暂时挂起，等 A12 完成后再议归属**（用户决定：
目前没有具体的方案布置）。不要因为它把 A13 重新标为未完成。

**A12：整体排在 A14 之后。**

理由是依赖关系：动画参数（时长、曲线、幅度）必须有地方配置，
而现在的通用对话框已经塞不下了。
在 A14-3 实例编辑器重构前做 A12，
等于往一个正要拆掉的对话框里再塞一堆参数。

A12 内部其实有两类，实施时可区分：
- **增强现有能力**：`click_to_surface_press` / `click_to_surface_ripple`
  两个方案已在跑，A9 也做了页面切换动画（`base_slide` + fade / 220ms）。
  「更高阶页面切换特效」属于在此基础上加强。
- **全新机制**：数值跳动、发光脉冲、粒子反馈，都要从零建。

---

## 三、阶段拆分与完成定义

## A2：通用画布骨架（已完成基础版）

### 已完成
- PCB 画布骨架
- PCB 高度可调
- PCB 高度持久化
- 资产栏基础拖放
- Composite 被限制在 PCB 内
- 越界状态兜底校验
- 保存拦截 / 非法返回保护
- PCB 尺寸与越界计数显示

### 当前完成定义
满足以下条件即可视为 A2 基础版完成：
- 能打开 CharacterAssemblyPage
- 能从资产栏拖复合组件到 PCB 内
- 复合组件不能被拖出 PCB
- PCB 高度可变、可保存、可恢复
- 非法布局不会被默默保存

### A2 留待后期增强
- 红框仅作为异常兜底，不作为常规拖动反馈（后续继续收敛）
- 可后台原子边缘吸附 / 拖出后台化（见“灵感池”）
- PCB 颜色与圆角编辑器 UI

---

## A6：多页面基础（已完成基础版）

### 已完成
- `pagesJson` 持久化模型接入
- `AssemblyPage` / `AssemblyPageGesture` 模型
- 旧 `elementsJson` 兼容迁移
- 当前活动页切换
- 图层面板基础版
- 主菜单固定化（不可重命名 / 不可拖动）
- 平级页 / 叠加页展示
- 长按拖动同级排序
- 叠加页换父层的阶段性实现：弹窗选择归属
- overlay 查看时祖先页灰化显示

### 当前完成定义
满足以下条件即可视为 A6 基础版完成：
- 能创建平级页与叠加页
- 能在页面间切换且内容独立保存
- 图层面板可用
- 主菜单规则稳定
- 同级排序可用
- 叠加页换父层有可用路径

### A6 留待后期增强
- 自动拖动换父级（树状拖放增强版）
- 更高级的拖放落点预判
- 插入动画 / 插入线 / 父层热点提示
- 页面删除 / 复制 / 另存等管理增强

---

## A3：Composite 黑盒 + 覆写表单基础（已完成基础版）

### A3-1：实例覆写数据结构（已完成）
#### 已完成
- `PropertyOverride`
- `AssemblyBinding`
- `AssemblyPage.propertyOverrides`
- 当前活动页的 `_activePropertyOverrides` 运行态容器
- 切页 / 保存 / 恢复时的 overrides 同步
- 基础的 override 清理、查找、upsert/remove 辅助方法

#### 完成定义
- 复合组件实例可拥有独立覆写数据容器
- 不改模板，只改实例
- 保存 / 恢复不丢失覆写容器

### A3-2：Composite 黑盒交互（已完成）
#### 已完成
- 点击选中复合件实例
- 双击打开实例覆写入口对话框
- 黑盒状态明确：选中高亮 + “实例黑盒”标签
- 实例覆写入口可按暴露子项创建 / 移除基础覆写槽位

#### 完成定义
- 复合件实例可被选中
- 双击能进入实例编辑入口
- 明确实例编辑只作用于当前页面当前实例，不影响模板和其他实例

### A3-3：基础覆写表单生成（已完成）
#### 已完成
- 实例覆写入口中对已支持类型开放 `编辑` 按钮
- 当前已支持：
  - `text`
  - `progress`
  - `switch`
- 创建覆写槽位后可立即进入字段编辑
- 覆写值变更会实时写入实例 patch，并反映在当前画布预览中

#### 完成定义
- 表单根据暴露端口自动生成基础字段
- 能改值
- 改动只落在实例 patch，不回写模板

### A3-4：覆写持久化（已完成）
#### 已完成
- patch 写回活动页数据
- 切页 / 退出 / 重新进入时，通过 `pagesJson` 保存恢复覆写数据
- 实例覆写入口区分：
  - 空槽位
  - 字段覆写
  - binding
- 为 binding 提供最小编辑挂载位：状态键 / 字段类型 / 同步方向
- binding 配置写入 `PropertyOverride.binding`，不影响模板

#### 完成定义
- 基础实例覆写可保存恢复
- binding 配置可作为实例级数据保存恢复，供后续状态栏 / SSOT 接入

---

## A7：页面路由器最小版（基础版完成，测试通过）

### 最小目标
- 资产栏可放入“页面路由器”逻辑组件
- 可选择：
  - 切换平级页
  - 打开叠加页
- 目标页候选按当前层级规则过滤

### 已完成
- 资产栏新增“逻辑组件 / 页面路由器”入口
- 页面路由器可作为 `page_router` 逻辑节点拖入 Assembly 页面
- 双击页面路由器可配置：
  - 切换平级页
  - 打开叠加页
- 目标页候选按当前活动页过滤：
  - 切换平级页：列出其他 base 页
  - 打开叠加页：列出当前页的直接 overlay 子页
- 点击页面路由器可在编辑态执行跳转测试
- 路由配置保存到节点 `properties.route`，随页面数据持久化

### 当前完成定义
- 路由器能作为逻辑节点被放入页面
- 能保存目标页配置
- 不要求完整动画，只要求配置结构正确

### 后续增强
- 接入 Assembly linker，让按钮 / 事件触发 route
- 页面切换动画
- 更完整的运行时路由行为
- 删除 / 复制页面时的 route 目标修复

### 阶段性测试入口说明
- A7 阶段曾临时支持“点击页面路由器本体执行跳转”作为编辑态测试入口。
- A5 配置式 linker MVP 完成后，该临时入口已退场。
- 页面切换应通过 `button → linker → page_router` 触发。
- 页面路由器本体保留为编辑器可见 / 可配置的后台逻辑节点。

---

## A7.5 / A5-0：Assembly 资产区最小补全（基础版完成，待本地测试）

### 最小目标
- 将资产库从左侧竖向抽屉改为底部分类栏 + 横向抽屉
- 至少开放 `button / linker / page_router`
- 为后续 `button → linker → page_router` 链路铺路

### 已完成
- 底部固定资产分类栏：
  - 逻辑组件
  - 基础交互
  - 基础显示
  - 复合组件
- 点击分类标题打开底部横向抽屉
- 点击其他分类可切换内容；点击同分类或画布空白可关闭
- 底部抽屉资产横向排列，可左右滑动浏览
- 底部抽屉拖出生成改为“向上竖直位移超过阈值”
- 抽屉展开时右下角 HUD 上移，避免遮挡
- 最小开放资产：
  - 逻辑组件：页面路由器、联动器
  - 基础交互：按钮
  - 基础显示：面板、文本、进度条
  - 复合组件：已暴露端口的复合资产
- 非复合原子 / 逻辑节点可作为 `UIModule` 拖入 Assembly 页面

### 当前完成定义
- 资产库位于底部，分类可切换
- `button / linker / page_router` 都能从资产库拖入
- 横向浏览与向上拖出生成不冲突
- 当前 linker 只要求能拖入 / 移动 / 保存恢复
- 不要求完整 linker 连线，接线与触发能力归 A5 实现

### A7.5-1 体验收口已完成
- 资产栏打开时，画布主体区域仍可拖动平移。
- 右下角 HUD 改为顶栏下方左对齐的紧凑胶囊。
- 底部分类栏与资产抽屉改为半透明拟磨砂样式。
- 横向抽屉高度压缩，资产卡片宽度 / 内边距 / 字号收紧。
- 新拖入原子 / 逻辑节点默认尺寸缩小，减少画布占用。
- button 默认外观改为灰色框风格，并去掉本体文字，减少与 Studio 认知差异。
- linker 默认高度进一步压低，作为后台逻辑节点减少画布占用。
- 底部资产标题栏与展开抽屉合并为同一个悬浮窗式毛玻璃面板，避免上下两块面板割裂。

### 后续增强
- 资产卡片进一步视觉美化，与 Studio 原子视觉继续对齐
- HUD 正式收口：折叠 / 合并到底栏 / 异常优先显示
- 参数 HUD 在图层面板 / 资产面板等遮挡场景下加入淡化消失与恢复动画
- 补充更多基础交互 / 基础显示组件
- 接入 A5 Assembly 内 linker 连线

---

## A4：暴露端口体验增强（基础回归完成，测试通过）

### 目标
- 复用 Studio 的 exposedPorts 渲染逻辑
- 同色晶体
- 触碰高亮
- 边轨端口 / 大感应区体验增强

### 当前完成
- 用户测试反馈“边轨 + 晶体”方案与创作页认知不一致，已回退为旧版 / 创作页更接近的小圆点端口。
- 端口颜色继续沿用 `customColor` 或子组件类型默认色。
- 左侧输入端口 / 右侧输出端口仍按原位置显示。
- 保留轻量 Tooltip，显示输入/输出与子组件名称。

### 后续增强
- 若重新增强端口体验，应优先与 Studio 暴露端口视觉保持一致。
- 边轨 / 晶体 / 大感应区方案暂时后置，不作为当前默认样式。
- 复合组件本体落点弹窗选端口（Studio 已验证过，Assembly 可后接）。
- 端口拖拽接线归后续完整 linker 可视化增强。

---

## A5：Assembly 内 linker 连线（配置式 MVP 完成，待本地测试）

### 最小目标
- 基础连线可建
- 目标页切换 route 可通过 linker 触发
- 遵守同复合件不可自连、非法方案自动断开

### 已完成
- 双击 Assembly 内 `linker` 可打开专用配置弹窗
- 可选择当前页面内的 `button` 作为来源
- 可选择当前页面内的 `page_router` 作为目标
- 保存为 `linker.properties['linker']`，包含：
  - `sourceModuleId`
  - `sourcePort: tap`
  - `targetModuleId`
  - `targetPort: trigger`
  - `scheme: button_to_page_route`
  - `enabled: true`
  - `inputConnection / outputConnection`
- 编辑态点击已连接 button，可经 linker 触发 page_router 跳页
- linker 可清除连接并回到未配置状态

### 当前完成定义
- 不做完整端口拖拽线，只做配置式 MVP
- 能打通 `button.tap → linker → page_router.trigger`
- 配置可保存恢复

### 后续增强
- 可视化线段绘制
- 端口拖拽接线
- 接入完整 LinkerMatrixEngine 方案选择
- 页面删除 / 复制时自动修复失效 route/linker 引用

---

## A8：运行时等比缩放与画布约束完善（基础版完成，待本地测试）

### 核心规则
- PCB 运行时禁止非等比拉伸，只允许等比缩放。
- 设计坐标固定为 `360 × pcbHeight`。
- 缩放比例使用：

```text
scale = min(1.0, availableWidth / 360, availableHeight / pcbHeight)
```

- 缩放后 PCB 中心始终与运行视口中心重合：

```text
renderedWidth = 360 × scale
renderedHeight = pcbHeight × scale
left = (availableWidth - renderedWidth) / 2
top = (availableHeight - renderedHeight) / 2
```

- 禁止为了填满屏幕而使用 `scaleX != scaleY`。
- 当屏幕比例与 PCB 比例不一致时，空白区域由模糊背景层填充。
- A8 MVP 的模糊背景层可先复用同一份 Assembly UI：

```text
backgroundScale = max(availableWidth / 360, availableHeight / pcbHeight)
```

  背景层高斯模糊、降低透明度，并且必须 `IgnorePointer`。

### 最小目标
- 新增可复用运行时渲染组件，按上述规则渲染 `UIAssemblyInfo`。
- 在 Assembly 编辑器内提供运行时预览入口。
- 预览当前 active page，并保留 overlay 祖先灰化显示。
- 保留 PCB 背景色、圆角与实例覆写。
- 非 Studio 模式下隐藏后台逻辑节点，例如 `linker / page_router`。
- 暂不接聊天页运行时，不做页面动画，不做 mode 差异完整收口。

### 已完成
- 新增 `UIAssemblyRuntimeView`，独立解析并渲染 `UIAssemblyInfo`。
- 使用 `scale = min(1.0, width / 360, height / pcbHeight)` 只做等比缩小，最多保持 1:1。
- 缩放后的清晰 PCB 通过 `FittedBox(BoxFit.scaleDown, Alignment.center)` 在布局层居中，避免手动定位偏移。
- 空白区域使用同一份 Assembly UI 的 cover 缩放模糊背景填充。
- 运行时预览层保留 PCB 颜色、圆角、页面元素、overlay 祖先灰化与实例覆写。
- 背景模糊层使用 `IgnorePointer`，不接收交互。
- Assembly 顶栏新增运行时预览入口。
- 预览入口进入同页全屏预览态，而不是弹窗；预览时顶栏 / 参数栏 / 资产栏 / 图层面板隐藏。
- 返回键或右上角关闭按钮退出预览态。
- A8-1 状态宿主修复：`UIAssemblyRuntimeView` 改为 Stateful，内部持有运行时页面副本。
- 预览内接入 LinkerEventBus，slider / linker / progress 等运行时交互可触发整体刷新。
- 模糊背景层使用运行时页面克隆副本渲染，不共享前景可变状态。

### 后续补项
- 当前 A8 预览会跟随 `pcbColorValue / pcbRounded`，但 PCB 颜色与圆角编辑入口仍属 A2/A8 后补 UI。
- 运行时交互组件覆盖测试：slider / switch / input / select / button / timer 等仍需逐项验证。
- 复杂复合组件内部 linker 覆盖测试：button→switch、input→text、select→text、timer→progress、math_node→text 等组合需后续回归。
- 超高 PCB 可读性提示：当运行时 scale 过小，应提示作者该 UI 在小屏上可能不可读 / 不易操作。
- 模糊背景性能优化：复杂 UI 下重复渲染一份模糊背景可能有性能成本，后续可考虑背景图 / 低频截图 / 纯背景降级。

### A8 回归测试方案
1. 基础显示：text / progress / image / surface 在预览中位置、尺寸、颜色稳定。
2. 基础交互：button / slider / switch / input / select 在预览中能响应，且状态刷新正确。
3. 典型 linker：slider→progress、button→switch、input→text、select→text、timer→progress、math_node→text。
4. 复合组件：无 linker、有内部 linker、有实例覆写、有 binding 槽位四类复合组件分别预览。
5. 页面结构：base、overlay、overlay 的 overlay 均能预览，祖先灰化正常。
6. 极端尺寸：普通高度、超高 PCB、窄屏、横屏下均保持等比缩小 / 居中 / 不拉伸。
7. 背景层隔离：模糊背景不接收交互，不与前景运行时状态互相污染。
8. 性能观察：复杂 UI 预览时记录是否出现明显掉帧、发热或操作延迟。

### 当前完成定义
- 不同视口下 PCB 不发生非等比拉伸。
- PCB 过高或过宽时会自动等比缩小完整显示。
- PCB 中心与预览视口中心重合。
- linker / page_router 等后台逻辑节点在运行时预览中隐藏。

---

## A9：页面手势配置 + 轻量动画（MVP 完成，待本地测试）

### MVP 规则
- 页面手势默认作用于整个 PCB。
- 局部 `gesture_zone` 热区后置。
- 手势只在运行时预览中生效，不影响 Assembly 编辑态拖动 / 拖组件。
- 同一页面同一方向只保留一个手势。
- 手势触发路由时使用与 page_router 一致的 route 规则。
- page_router route 数据补充默认 `transition / durationMs`。
- 平级页默认动画：`base_slide`，默认 220ms，表现为 slide + fade。
- 叠加页 route 可打开 overlay，但 overlay 专属动画依赖面原子 / 容器面，当前不再复用平级页整页替换动画。
- 后续再开放更多动画类型。

### 已完成
- 图层面板页面条目新增手势配置入口。
- 支持方向：左滑 / 右滑 / 上滑 / 下滑。
- 支持动作：切换平级页 / 打开叠加页。
- 目标页候选按层级过滤：
  - 切换平级页：其他 base 页。
  - 打开叠加页：当前页直接 overlay 子页。
- 手势配置保存到 `AssemblyPage.gestures`。
- 运行时预览中识别清晰 PCB 区域内的全页 swipe，并切换到目标页。
- 运行时预览中平级页切换使用 `base_slide` 的 slide + fade 动画。
- overlay route 暂只负责进入叠加页；overlay 容器动画待面原子 / 容器面语义补齐后实现。
- 基础显示资产区开放“面板 / 面原子”，默认尺寸对齐创作工作室 `160×80`，作为 overlay 容器基础。
- overlay 页中第一个生成的面原子会自动标记为容器面，并按创作工作室一致的橙黄色外侧标签显示“容器面”。
- Assembly 编辑态与运行时预览中，active page 为 overlay 时，都会在祖先页与 overlay 内容之间显示灰色半透明 PCB 蒙版。
- Assembly 编辑态中，overlay 页没有任何面原子时，会显示橙色警告提示作者拖入“面板”作为弹层容器。
- opening 模式运行时暂不响应页面手势。

### A9-1 / A9-2 修正结论
- 平级页切换动画已修正为 slide + fade，避免只滑入不淡入/不淡出的冲突感。
- overlay 动画不能复用平级页整页替换逻辑，当前不宣称 overlay 专属动画完成。
- overlay 专属动画目标应是面原子 / 容器面及其遮罩层。
- 运行时预览中，当前页为 overlay 时，点击容器面外的 PCB 空白区域会返回父级页面。
- 容器面 hit test 优先使用 `is_overlay_container == true` 的面原子，兜底当前 overlay 的第一个面原子。

### 后续增强
- 局部 `gesture_zone` 热区。
- 手势与 slider / input / select 等交互组件的精确命中排除。
- overlay 容器面识别、遮罩、空白点击返回父级。
- overlay 专属动画：容器面淡入 / 上滑 / 缩放，遮罩淡入淡出。
- 更多动画类型：无动画 / fade / slide / scale / overlay slide-up 等。
- 手势返回上一页 / 关闭 overlay / opening 销毁等动作。

---

## A9.5：通用模板基础版（规划完成，下一步）

### 阶段定位
A9.5 是 A10 mode 差异化之前的前置阶段。它不做 `opening / scene / extra_sticky / extra_companion` 的差异化逻辑，而是先把所有模式共用的“通用模板 / 通用运行时底座”做稳。

当前已经具备 PCB、多页面、overlay、page_router、button/linker、手势、运行时预览、面原子、容器面、蒙版等局部能力；A9.5 的目标是把这些能力整理为一套可复用、可测试、可作为 A10 分化基础的通用模板。

### 统一编辑器 / 统一模板数据 / mode runtime shell
后续不为 `opening / scene / extra_sticky / extra_companion` 分别制作独立工作室。所有模式共用同一个 Assembly 编辑器、同一套模板数据结构，再通过运行时外壳表现差异。

统一层：
- 编辑器：`CharacterAssemblyPage`。
- 模板数据：`UIAssemblyInfo / AssemblyPage / UIElement / PropertyOverride / AssemblyBinding / AssemblyPageGesture`。
- 通用能力：PCB、多页面、overlay、route、gesture、binding、实例覆写、运行时缩放、通用原子渲染。

差异层：
- `opening`：全屏弹窗壳，确认后销毁当前会话实例，清空聊天后可重置。
- `scene`：全屏接管壳，替代普通聊天 UI，并保留设置入口。
- `extra_sticky`：聊天页上方浮动壳，可折叠 / 展开。
- `extra_companion`：消息气泡下挂壳，按消息容器宽度缩放并跟随滚动。

架构原则：
- `mode` 是运行时外壳策略，不是不同工作室。
- 模板应尽量可以在不同 mode 间迁移或复用。
- A10 只能在通用模板稳定后实现差异化 runtime shell。
- 禁止把相同的资产栏、PCB、多页面、route、gesture、binding 逻辑复制成多套 mode 专用代码。

### 通用运行时页面模型
通用模板运行结构先按以下模型理解：

```text
RuntimeViewport
├─ blurred backdrop
├─ centered PCB
│  ├─ base page
│  ├─ overlay mask
│  ├─ overlay page
│  └─ interactive elements
└─ preview-only controls / debug info
```

通用规则：
- base 页是基础页面层。
- overlay 压在父页面上显示，父页面保留但被蒙版压暗。
- overlay 必须有容器面，容器面由面原子提供。
- 点击 overlay 容器面外的 PCB 空白区域返回父级。
- route 可由 `button → linker → page_router` 或页面手势触发。
- 通用运行时必须先稳定，才能进入 mode 差异。

### 通用模板样板建议
A9.5 至少要能搭出一个用于回归的通用样板：

```text
主菜单 base
状态面板 overlay
设置面板 overlay
第二个 base 页
```

该样板用于验证：
- base 页切换
- overlay 打开
- overlay 空白关闭
- button → linker → page_router
- 页面手势切换
- 面原子作为容器面
- 运行时等比缩放
- 复合组件实例覆写
- binding 挂载位
- 内部 linker

### 通用资产区补齐计划
当前开放资产：
- 页面路由器
- 联动器
- 按钮
- 输入框
- 开关
- 滑块
- 下拉
- 面板
- 文本
- 进度条
- 图片
- 状态点
- 分割线
- 已暴露端口复合组件

A9.5 建议补齐已有基础原子入口：
- 图片
- 输入框
- 开关
- 滑块
- 下拉
- 状态点
- 分割线

A9.5-2 的最小目标不是完善每个原子的高级编辑器，而是先保证：

```text
能拖入 → 能移动 → 能保存 → 能预览
```

### A9.5 分步建议
#### A9.5-1：通用模板规则文档（当前）
- 定义通用模板与 mode 差异的边界。
- 定义通用页面运行模型。
- 定义通用模板测试样板。
- 定义 A10 的进入条件。

#### A9.5-2：资产区补齐基础原子（已完成，待本地测试）
- 已开放图片、输入框、开关、滑块、下拉、状态点、分割线。
- 基础交互分类新增：输入框、开关、滑块、下拉。
- 基础显示分类新增：图片、状态点、分割线。
- 默认落地尺寸参考 Studio `_initialSizeForModule`：
  - slider `150×34`
  - input `140×34`
  - switch `100×36`
  - select `140×34`
  - indicator `36×36`
  - image `80×80`
  - line `120×20`
- 暂不做复杂编辑器，只保证基本落地和预览。

#### A9.5-3：通用模板测试样板（已完成文档，待按样板回归）
- 搭建或人工定义一套“主菜单 + overlay + 第二 base 页”的测试样板。
- 用样板覆盖通用运行时链路。

##### A9.5-3 专属测试定位
A9.5-3 不是重新测试“按钮能不能拖入”“overlay 能不能打开”等单点功能，而是模板级集成测试。它要验证多个已完成能力组合成一个通用模板后，是否仍然稳定、不互相污染、不依赖临时入口。

专属测试关注：
- 组合稳定性：button/linker/page_router、gesture、overlay、容器面、运行时预览同时存在时是否冲突。
- 模板可复用性：页面重命名、保存恢复、目标页 id、容器面标记是否稳定。
- 作者工作流：从空白 Assembly 到完成一个通用样板，是否不需要手改 JSON、不需要知道内部 id。
- 运行时完整性：只通过按钮、手势、空白点击等最终入口操作，不依赖点击 page_router 本体等临时调试入口。

##### 专属测试 1：完整制作流程
从空白 Assembly 开始，按顺序完成：
1. 创建主菜单 base。
2. 创建第二 base 页。
3. 在主菜单下创建状态面板 overlay。
4. 在主菜单下创建设置面板 overlay。
5. 在每个 overlay 中拖入第一个面板，确认自动成为容器面。
6. 在主菜单中放置打开 overlay / 切换 base 的按钮。
7. 配置 page_router。
8. 配置 linker。
9. 配置手势。
10. 保存退出并重新进入。

预期：
- 全流程无需手动改 JSON。
- 不要求创作者理解内部 page id。
- 每一步都有可见反馈。
- 保存后页面、overlay、route、gesture、容器面均保留。

##### 专属测试 2：route 与 gesture 共存
同一个目标页同时配置：
- `button → linker → page_router`
- `swipe → 同一个 targetPage`

预期：
- 点击按钮能切页 / 打开 overlay。
- 滑动手势也能切页 / 打开 overlay。
- 两者互不污染。
- 保存重进后都有效。

##### 专属测试 3：多 overlay 独立性
主菜单下创建两个 overlay：
- 状态面板 overlay。
- 设置面板 overlay。

预期：
- 打开状态面板不会打开设置面板。
- 打开设置面板不会打开状态面板。
- 两个 overlay 的容器面独立。
- 空白点击只关闭当前 overlay，返回主菜单。
- overlay 内组件不串到另一个 overlay。

##### 专属测试 4：页面重命名稳定性
配置 route / gesture 后重命名目标页面，再保存重进。

预期：
- route / gesture 仍有效。
- 内部使用 page id，不受页面显示名变化影响。
- UI 上显示新名称。

##### 专属测试 5：组件状态隔离
在状态面板 overlay 放置 slider / progress / switch / 状态点；在设置面板 overlay 放置 input / select / text。

预期：
- 状态面板交互不影响设置面板。
- 设置面板交互不影响状态面板。
- 模糊背景不污染前景状态。
- 切回主菜单再打开 overlay，状态表现稳定。

##### 专属测试 6：overlay 容器缺失修复流程
1. 新建 overlay，不放面板。
2. 查看缺容器面警告。
3. 拖入面板。
4. 查看警告消失，容器面标签出现。
5. 再拖入第二个面板。

预期：
- 缺容器面时有明确警告。
- 第一个面原子自动成为容器面。
- 第二个面原子不自动抢容器面。

##### 专属测试 7：运行时缩放下的模板完整性
用同一个完整样板测试普通高度、超高 PCB、窄屏、横屏。

预期：
- 样板整体等比缩小，不拉伸。
- 页面结构不乱。
- overlay 容器仍在正确位置。
- 点击容器面外关闭在缩放后仍准确。
- 组件不会错位或溢出。

##### 专属测试 8：无临时入口依赖
在运行时预览中只通过最终入口操作：
- 按钮。
- 手势。
- overlay 空白点击。

预期：
- 样板可以完整操作。
- 不依赖点击 page_router 本体。
- 不依赖调试标签。
- 不需要手动切图层才能完成运行时流程。

##### 样板页面结构
```text
主菜单 base
├─ 状态面板 overlay
├─ 设置面板 overlay
└─ 第二 base 页
```

##### 主菜单 base 组件清单
- 面板：作为主菜单背景 / 内容区。
- 文本：`主菜单`。
- 按钮：打开状态面板。
- 按钮：打开设置面板。
- 按钮：切换到第二 base 页。
- 进度条：用于显示一个状态值。
- 状态点：用于显示一个布尔 / 枚举状态。

##### 状态面板 overlay 组件清单
- 容器面：第一个面原子，必须显示 `容器面` 标签。
- 文本：`状态面板`。
- 滑块。
- 进度条。
- 开关。
- 状态点。
- 分割线。

验证重点：
- slider → progress。
- switch → indicator / 状态点。
- 点击容器面内部不关闭 overlay。
- 点击容器面外的 PCB 灰色蒙版区域返回父级。

##### 设置面板 overlay 组件清单
- 容器面：第一个面原子，必须显示 `容器面` 标签。
- 文本：`设置面板`。
- 输入框。
- 下拉。
- 按钮。
- 分割线。

验证重点：
- input → text。
- select → text。
- 基础交互组件在运行时预览中可显示 / 可交互。

##### 第二 base 页组件清单
- 文本：`第二页`。
- 图片。
- 按钮：返回主菜单。

验证重点：
- base 页切换。
- 图片显示。
- button → linker → page_router 返回主菜单。

##### 页面路由清单
- 主菜单按钮 → 状态面板 overlay。
- 主菜单按钮 → 设置面板 overlay。
- 主菜单按钮 → 第二 base 页。
- 第二 base 页按钮 → 主菜单。

##### 页面手势清单
- 主菜单左滑 → 第二 base 页。
- 第二 base 页右滑 → 主菜单。
- 主菜单上滑 → 状态面板 overlay。
- overlay 关闭当前先靠容器面外空白点击，手势返回后置。

##### 通用联动清单
当前可作为目标测试或后续增强记录：
- slider → progress。
- button → switch。
- input → text。
- select → text。

如果某条联动当前无法在 Assembly 内配置，则标记为 A5 / A9.6 后续增强，不阻塞样板结构本身。

##### 运行时预览回归清单
- PCB 只等比缩小，不放大、不拉伸。
- 清晰 PCB 居中。
- overlay 显示灰色半透明 PCB 蒙版。
- 容器面内点击不关闭 overlay。
- 容器面外点击返回父级。
- 模糊背景不污染前景状态。
- 保存退出后重新进入，页面 / 原子 / route / gesture 均恢复。

#### A9.5-4：通用运行时问题收口
- 根据样板测试修复运行时预览与联动问题。
- 覆盖 slider/progress、button/switch、input/text、select/text、timer/progress、math_node/text 等典型链路。

#### A9.5-5：Assembly 组件实例编辑器基础迁移（新增规划）
A9.5-5 用于统一 Assembly 内组件双击编辑语义，并为数据通道卡片正式内嵌做前置准备。

##### 核心原则
- 双击组件 = 编辑当前实例。
- 原子组件打开“原子实例编辑器”。
- 复合组件打开“复合组件实例编辑器”。
- Studio 编辑模板，Assembly 编辑实例，二者不能混淆。
- Assembly 默认不得回写资产库模板。
- 当前数据通道独立弹窗只是 MVP 过渡入口，后续应内嵌到组件实例编辑器。

##### Studio 迁移参考
Studio 中已经存在画布内复合组件实例编辑器：

```text
lib/pages/ui_studio_page/dialogs.dart
  if (el.isComposite) _showCompactCompositeEditorDialog(el)

lib/pages/ui_studio_page/dialogs/compact_editors_dialogs.dart
  _showCompactCompositeEditorDialog
```

该编辑器明确只修改当前画布实例快照，不修改资产库模板。因此它是 Assembly 复合组件实例编辑器的重要参考。

需要区分：
- Studio / 资产库卡片点击：编辑复合组件模板。
- Studio / 画布复合组件双击：编辑复合组件实例。
- Assembly / 画布复合组件双击：也应编辑当前角色 UI 中的复合组件实例。

##### 复合组件实例编辑器目标结构
```text
复合组件实例编辑器
├─ 实例信息
│  ├─ 模板名
│  ├─ 实例 ID
│  ├─ 当前页面
│  └─ 尺寸 / 位置
├─ 实例规格
│  ├─ 尺寸
│  ├─ 旋转
│  ├─ 布局锁定
│  └─ 后续：拆解为原子
├─ 暴露项覆写
│  ├─ text
│  ├─ progress
│  ├─ switch
│  └─ 后续 input / slider / select / image / indicator
├─ 数据通道
│  ├─ 暴露项数据通道
│  └─ AI 读写策略
├─ Binding
│  └─ A3-4 既有 binding 挂载位
└─ 高级
   ├─ 重置覆写
   ├─ 查看模板来源
   └─ 后续：另存为新模板
```

当前 Assembly 的“实例覆写入口”不删除，而是升级为复合组件实例编辑器中的“暴露项覆写 / Binding”区块。

##### 原子实例编辑器目标结构
```text
原子实例编辑器
├─ 基础属性
├─ 原子专属属性
├─ 数据通道
└─ 高级
```

##### 分步建议
###### A9.5-5-1：原子实例编辑器第一批（已完成，测试通过）
优先迁移简单原子：
- text
- surface / 面板
- progress
- button
- line

已完成：
- 双击普通原子打开实例编辑器。
- 通用基础属性：实例名称、宽度、高度。
- text：文本内容、字号。
- surface / 面板：圆角、透明度。
- progress：最小值、最大值、当前值。
- button：按钮文字、是否显示文字按文本是否为空自动判断。
- line：方向、线型、粗细。
- 编辑结果只作用于当前 Assembly 实例。
- 编辑器内保留“数据通道”入口作为过渡；后续 A9.5-5-4 再正式内嵌。

###### A9.5-5-2：复合组件实例编辑器迁移（已完成，测试通过）
- 参考 Studio `_showCompactCompositeEditorDialog`。
- 已将当前 Assembly 覆写入口包装为“复合组件实例编辑器”。
- 已增加实例信息区：模板名、实例 ID、所在页面、尺寸 / 位置。
- 保留现有暴露项覆写和 binding 逻辑。
- 已增加数据通道占位区。
- 已增加高级占位区，说明重置覆写、查看模板来源、另存为模板等后续开放。
- 不修改模板本体。

###### A9.5-5-3：原子实例编辑器第二批（已完成，测试通过）
继续迁移复杂原子，全部已接入 `_showAtomInstanceEditorDialog`：
- input：占位提示、默认文本、最大字数（留空不限制）
- switch：默认开启
- slider：最小值 / 最大值 / 当前值 / 步长（自动纠正 max<min、step<=0、current 越界）
- select：选项列表（每行 `显示文本` 或 `显示文本|值`）、默认选中值（无效则回落第一项）
- indicator：状态点直径（8~28）、默认发光
- image：网络图片地址、本地/内部资产路径、填充方式（cover / contain / fill）、圆角

约束不变：只写当前 Assembly 实例的 `module.properties`，不回写资产库模板。

###### A9.5-5-4：数据通道内嵌（已完成，测试通过）
- 原子实例编辑器内嵌完整数据通道区：启用开关 + 名称来源 / 名称 / 保存到 / 玩家可见性 / LLM 读策略 / LLM 写策略 / AI 更新应用方式 + 最终语义预览。
  - 通道随“保存”一起写入 `module.properties['dataChannel']`。
  - 关闭开关或最终语义为空时，保存会清除该组件的 `dataChannel`。
- 复合组件实例编辑器中，每个已创建覆写槽位的暴露项新增“通道”按钮。
  - 暴露项通道写入 `PropertyOverride.overrides['dataChannel']`，属于实例覆写，不回写资产库模板。
  - 卡片内显示通道摘要，槽位状态文本新增“已配通道”。
  - 渲染时 `dataChannel` 键不会被当作字段覆写下发给子组件属性。
- 已移除“普通原子双击直接打开独立数据通道弹窗”的 A9.6-1 临时入口，`_showDataChannelDialog` 已删除。
- 表单逻辑抽为共用方法：`_buildDataChannelFormFields` / `_resolveDataChannelName` / `_buildDataChannelPayload`。
- 行为不变：仍然只保存元数据，不写 SessionState、不注入 Prompt。

### A10 进入条件
进入 A10 前，应满足：
1. 通用运行时预览稳定。
2. 通用模板样板可以完整跑通。
3. 常用基础原子可拖入 / 保存 / 预览。
4. overlay 容器面、蒙版、空白关闭稳定。
5. button/linker/page_router 与 gesture 路由稳定。
6. 至少一轮通用模板回归测试通过。

### A9.5 不做
- 不做 opening 确认后销毁。
- 不做 scene 完全接管聊天页。
- 不做 extra_sticky 悬浮球。
- 不做 extra_companion 消息下挂。
- 不接聊天页真实运行时。
- 不做 Prompt / SSOT 状态注入。
- 不做高级动画系统。

---

## A9.6：SSOT / LLM 数据交互 MVP（规划中，A10 前置）

### 阶段定位
A9.6 是 A10 mode 差异化之前的关键前置阶段。它负责打通 UIengine 与会话状态、Prompt、LLM 回复之间的数据通路。没有 A9.6，opening / scene / extra 的差异化只会是视觉壳，无法真正影响后续对话。

目标链路：

```text
UI 输入 / 选择 / 滑动
→ SessionState.vars 或 SessionState.statusValues
→ Prompt 注入
→ LLM 回复
→ 状态更新解析
→ UI 刷新
```

### 前置依赖
- A9.5 通用模板基础版至少完成基础原子入口与通用样板测试方案。
- Binding 名称解析与预绑定规则已在文档中确认。
- `SessionState.vars` / `SessionState.statusValues` 已存在模型基础。

### A9.6 分步建议
#### A9.6-0：SSOT / LLM 数据交互设计文档（当前设计）

##### 设计目标
A9.6-0 先定义数据通路，不急着写业务代码。核心目标是让 UIengine 不再只是可视界面，而是能成为会话副本 Prompt 的可控输入层。

最终闭环：
```text
UI 原子交互
→ AssemblyBinding / Route / Gesture
→ SessionState.vars 或 SessionState.statusValues
→ Prompt 渲染 / 状态段注入
→ LLM 回复
→ 结构化状态更新建议
→ 用户确认 / 引擎校验
→ SessionState 更新
→ UI 刷新
```

##### SSOT 边界
A9.6 的单一事实源分两层：

1. `CharacterMeta.statusBarFields`
   - 存放状态栏字段定义。
   - 包括 id、name、type、initialValue、min/max、排序等。
   - 属于角色卡母版的一部分，随卡导入导出。

2. `SessionState`
   - `vars`：普通会话变量，例如主角名、已选择技能、opening 选项。
   - `statusValues`：状态栏字段当前值，key 使用 `StatusBarField.id`。
   - `overrides`：后续动态设定演化的结构化覆盖层，本期预留。

规则：
- UI 不直接改角色卡母版。
- UI 写入会话副本 `SessionState`。
- 清空聊天记录后，会话状态可以重置，回到母版初始值。
- Prompt 每轮从母版 + SessionState 重新组装。

##### 默认交互：数据通道卡片
A9.6 统一采用“数据通道卡片”作为默认操作模型，不同时维护三套入口。LLM 数据节点与端口级 LLM 标记可作为后续高级可视化，但不作为 MVP 主交互。

创作者操作流程：
```text
选中组件
→ 打开“数据通道”
→ 添加 / 编辑一张数据通道卡片
→ 填写数据名称与语义来源
→ 选择保存位置
→ 选择玩家可见 / LLM 可读 / LLM 可写 / 应用策略
→ 保存
```

数据通道卡片需要在一个界面内表达：
- 这个组件代表什么数据。
- 数据值来自组件哪个端口，例如 `text / current / value / selected`。
- 语义标签是什么。
- 所属语义路径是什么。
- 保存到 `local_ui_state / session_var / status_field` 中哪一类。
- 玩家是否可见。
- 是否发送当前值给 LLM。
- 是否允许 LLM 建议修改。
- LLM 修改方式是增量还是替换。
- 更新是否需要用户确认。

画布上可用小 chip 显示数据通道摘要，例如：
```text
好感度 · AI↕
主角姓名 · AI↑
当前 tab · UI
```

##### 数据通道语义：LLM 不接收裸值
LLM 不应该收到无语义裸值，例如：
```text
45
true
精灵森林
```

LLM 应收到带语义路径的数据，例如：
```text
角色状态 / 好感度：45
场景控制 / 当前地点：精灵森林
战斗面板 / 狂暴状态：开启
```

因此每个会进入 LLM 的数据通道必须能解析出：
```text
semanticLabel: 数据自身名称，例如“好感度”
semanticPath: 所属路径，例如“角色状态 / 好感度”
```

##### 语义来源优先级
数据通道的语义来源按以下优先级解析：
1. 数据通道卡片中手动填写的名称。
2. 显式选择的 Text 标签，例如 `Text("好感度")`。
3. 父级容器 / 面板标题递归，例如 `角色状态 / 好感度`。
4. 组件自身 name。
5. 组件类型兜底，例如“未命名数值”。

系统可以自动建议，但不能自动强绑定。例如系统可提示：
```text
检测到附近文本“好感度”，是否作为数据名称？
```
但绑定目标、是否给 LLM 看、是否允许 LLM 修改，必须由创作者确认。

##### Label Text 与父级连接递归
创作者通常会在 UI 中放置文字标题解释数据条含义。因此 A9.6 允许 Text 组件作为数据通道的语义标签来源。

MVP 交互：
- 在数据通道卡片中选择“名称来源：文本标签”。
- 从同页面 / 同容器内选择一个 Text 组件作为标签。
- 系统读取该 Text 的文案作为 `semanticLabel`。

后续高级可视化：
- 可在画布上显示淡语义线，例如 `Text("好感度") --label--> Progress`。
- 父级容器标题可以递归参与 `semanticPath`。

父级递归示例：
```text
Text("角色状态") labels Surface Panel
Text("好感度") labels Progress(45)
```

Prompt 中生成：
```text
[角色状态]
好感度：45
```
或：
```text
角色状态 / 好感度：45
```

##### 组件 name 的定位
组件 name 只是语义兜底，不是首选来源。若 UI 上已有可见 Text 标签，应优先使用 Text 标签，避免创作者重复输入同一语义。

##### Binding 目标类型
现有 `AssemblyBinding.statusKey` 只是 A3-4 MVP 挂载位。A9.6 后续建议升级为明确目标结构：

```text
targetKind: status_field | session_var
targetId: 已解析的状态栏字段 id / 会话变量 key
pendingName: 未解析时用户输入的预绑定名称
displayNameSnapshot: 绑定时的显示名快照
fieldType: string | number | bool
direction: none | upload_only | bidirectional
```

解释：
- `status_field`：绑定角色状态栏字段，运行时写入 `SessionState.statusValues[targetId]`。
- `session_var`：绑定普通会话变量，运行时写入 `SessionState.vars[targetId]`。
- `pendingName`：允许 UI 先设计，状态块后创建。
- `displayNameSnapshot`：字段删除 / 失效时用于提示用户原绑定对象。

##### 普通创作者体验
Binding 入口不应要求用户手填内部 id。

普通模式：
- 输入 / 搜索“状态块名称”或“变量显示名”。
- 若匹配已有状态栏字段，系统保存内部 id。
- 若重名，弹出候选让用户选择。
- 若找不到，保存为 pendingName，并显示“尚未创建该状态块”的提示。

高级模式：
- 可折叠显示内部 id / key。
- 仅供调试和高级作者使用。

##### 数据存在、玩家可见、LLM 可见、LLM 可修改互相独立
系统不得根据字段名称、控件类型或状态栏归属自动判断是否发送给 LLM 或是否允许 LLM 修改。以下配置相互独立：

```text
targetKind: local_ui_state | session_var | status_field
visibility: ui_only | player_visible | system_hidden
llmReadPolicy: none | prompt | hidden_context
llmWritePolicy: none | suggest_delta | suggest_replace | suggest_any
llmUpdateApplyPolicy: never | confirm | auto_low_risk
```

默认值必须安全：
```text
visibility = ui_only
llmReadPolicy = none
llmWritePolicy = none
llmUpdateApplyPolicy = confirm
```

常见组合：
- 主角姓名：玩家可见，发送给 LLM，只读，不允许 LLM 修改。
- 好感度：玩家可见，发送给 LLM，允许 LLM 建议增量，用户确认后应用。
- 敌方警觉度：系统隐藏，不发送当前值给 LLM，但允许 LLM 根据剧情建议增量。
- 当前 tab：UI 内部，不发送给 LLM，不允许 LLM 修改。

Prompt 注入只读取 `llmReadPolicy != none` 的数据。LLM 更新建议只允许出现在 `llmWritePolicy != none` 的数据通道中。

##### LLM 可写但不可读的场景
允许存在“不发送当前值给 LLM，但允许 LLM 提供变化/增量”的数据通道。

示例：
```text
敌方警觉度：当前值隐藏，不注入 Prompt。
LLM 只知道“可根据剧情建议敌方警觉度 +N/-N”。
App 本地根据当前隐藏值执行 delta + clamp。
```

这类数据的 Prompt 可只注入写入规则，而不注入当前值：
```text
[可建议更新的隐藏状态]
敌方警觉度：只可输出 +N/-N，不要在正文中提及当前值。
```

##### UI 原子写入 SessionState 的 MVP 映射
优先支持四类输入原子：

```text
input  → SessionState.vars
select → SessionState.vars
switch → SessionState.vars 或 SessionState.statusValues
slider → SessionState.statusValues
```

建议规则：
- input 默认适合写 `vars`，如 `protagonist_name`。
- select 默认适合写 `vars`，如 `selected_skill`。
- switch 可写 bool 型 `vars`，也可写 bool/status 型状态字段。
- slider 默认适合写 number 型 `statusValues`，如 `affection`。
- progress 默认作为显示状态，不优先作为用户输入源，但可显示 `statusValues`。

A9.6-2 只要求 UI → SessionState 单向写入稳定；双向同步可后续扩展。

##### Prompt 注入格式
A9.6-3 建议同时支持两种最小注入方式。

1. 模板占位符：
```text
{{var.protagonist_name}}
{{status.affection}}
{{status.mood}}
```

2. 结构化状态段：
```text
[当前会话变量]
主角姓名：林
已选技能：剑术

[当前状态]
好感度：45
心情：放松
地点：教室
```

MVP 先实现一种稳定格式即可。推荐优先实现结构化状态段，因为它更容易调试，也不要求用户在每条设定里手动写占位符。

##### LLM 回复更新状态的预留格式
第一版不做自然语言自由解析，避免误判和不可控写入。建议让 LLM 可选择输出一个结构化状态更新块：

```json
{
  "status_updates": {
    "affection": "+3",
    "mood": "放松",
    "location": "教室"
  },
  "vars_updates": {
    "selected_skill": "剑术"
  }
}
```

规则：
- number 状态字段推荐使用 delta，例如 `+3` / `-2`。
- 引擎执行 `旧值 + delta`，再按 min/max clamp。
- LLM 不应直接覆盖数值字段绝对值，除非用户明确开启高级模式。
- text 状态字段可直接替换。
- bool 状态字段只能接受 true/false 或明确映射值。

##### 用户确认与安全规则
LLM 状态更新不应静默覆盖重要状态。

MVP 建议：
- UI → SessionState 的用户主动操作可直接生效。
- LLM → SessionState 的自动更新先进入“待确认建议”。
- 用户确认后写入 SessionState。
- 被拒绝的建议不写入。
- 所有自动状态更新应可在日志 / 调试报告中追溯。

后续可分级：
- 低风险状态，如 mood/location，可自动应用。
- 高风险状态，如 affection/relationship/stage，默认需要确认。

##### 与 mode 的关系
A9.6 是 A10 的前置：
- opening 需要把用户输入 / 选择写入 SessionState，确认后影响后续 Prompt。
- scene 需要把状态面板 UI 与 SessionState / Prompt 持续同步。
- extra_sticky 需要显示并更新常驻状态。
- extra_companion 需要读取上下文并随消息流显示。

因此 mode 差异化不应在数据通路之前完成，否则只是视觉壳。

##### A9.6-0 不做
- 不实现 UI 写入 SessionState 的业务代码。
- 不实现 Prompt 拼装代码。
- 不实现 LLM 回复解析器。
- 不接聊天页真实运行时。
- 不做状态版本管理。

A9.6-0 只确认设计、边界和后续实现顺序。

#### A9.6-1：数据通道卡片 / Binding 名称解析 MVP（已完成，待本地测试）
- 顶层普通原子组件可双击打开“数据通道”卡片。
- 当前不对 linker / page_router / math_node / timer 开放数据通道。
- 支持名称来源：手动填写、使用文本标签、使用组件名称。
- 支持保存位置：UI 内部状态、会话变量、状态字段。
- 支持玩家可见性：只控制界面、玩家可见、系统隐藏。
- 支持 LLM 读策略：不发送、发送到 Prompt、隐藏上下文。
- 支持 LLM 写策略：不允许、建议增量、建议替换。
- 支持 AI 更新应用方式：用户确认、低风险自动应用、永不应用。
- 当前保存到组件 `module.properties['dataChannel']`，并在画布上显示数据通道 chip。
- 当前只保存数据通道元数据，不写入 SessionState、不注入 Prompt。
#### A9.6-1 增强：状态字段名称匹配与 pendingName 预绑定（已完成，测试通过）
- `CharacterAssemblyPage` 新增只读入参 `statusFields`，由 `UIAssemblyListPage` 从 `meta.statusBarFields` 传入。Assembly 不修改角色卡字段本体。
- 数据通道「保存到」选择状态字段时，表单实时显示匹配提示：
  - 命中：显示字段名、内部 id、数值 / 文本类型。
  - 未命中：橙色提示将记为待创建字段，并列出角色卡当前可用字段名。
  - 角色卡无任何状态字段时给出单独提示。
- 保存逻辑：
  - 命中则写入 `targetId`，`pendingName` 清空，`fieldType` 以角色卡字段类型为准。
  - 未命中则 `targetId` 为空，`pendingName` 记录名称，等待字段创建。
- 进入 Assembly 时执行 `_reconcileStatusChannelBindings()` 重新对齐：
  - 先写通道、后建同名字段 → 自动补绑 `targetId`。
  - 字段被删除 → 回退为 pendingName 待创建状态。
  - 覆盖顶层原子、复合子元素与 `PropertyOverride.overrides['dataChannel']`。
- 画布 chip 与暴露项摘要对待创建状态显示「状态待建」，chip 用橙色区分。
- 仍不写 SessionState、不注入 Prompt（留给 A9.6-2 / A9.6-3）。

修复：复合组件实例编辑器布局溢出
- 现象：暴露项较多或按钮增至四个时，弹窗内 `Column` 底部溢出（RenderFlex overflowed）。
- 处理：
  - 弹窗内容改为 `SizedBox(width 430) + ConstrainedBox(maxHeight 屏高 70%) + SingleChildScrollView`，整体可滚动。
    - 注意：`AlertDialog` 内部用 `IntrinsicWidth` 测量内容，`content` 必须给确定宽度，只用 `ConstrainedBox(maxWidth:)` 会导致 `RenderBox was not laid out` / `hasSize` 断言。
  - 暴露项列表由 `ListView.separated` 改为 `Column + Builder` 逐项构建，间距用 `margin` 处理。
    - 原因同上：`ListView` 不支持 intrinsic 尺寸，放进 `AlertDialog.content` 会在 paint 阶段抛 `hasSize` 断言。
  - 覆写槽位的「编辑 / 绑定 / 通道 / 移除」从名称同一行移到独立 `Wrap` 行，可自动换行；未创建槽位时「创建」仍留在名称行。

#### A9.6-2：UI 写入 SessionState MVP（已完成，测试通过）
新增 `lib/services/ui_engine/data_channel_service.dart`。

可写类型（progress 为显示型，不作为输入源）：
- input / select / switch / slider

取值口径：
- input：`committedValue` > `text` > `value`
- select：`current` > `defaultValue`
- switch：`value != false`，输出 `'true'` / `'false'`
- slider：`committedValue` > `current`，整数不带小数尾巴

写入规则：
- `session_var` → 以 semanticLabel 为键写 `SessionState.vars`
- `status_field` 且已匹配 targetId → 写 `SessionState.statusValues[targetId]`
- `status_field` 但仍是 pendingName → **跳过**，不凭空造字段
- `local_ui_state` → **永不进入** SessionState
- 数值状态字段按角色卡 `minValue` / `maxValue` 执行 clamp
- 值未变化时不报告 changed，避免无谓落盘

运行时接线：
- `UIAssemblyRuntimeView` 新增 `sessionState` / `statusFields` / `onSessionStateChanged` / `showDataChannelDebug`。
- 每次 LinkerEventBus 事件后调用 `_syncDataChannels()`，单向 UI → SessionState。
- 未传 `sessionState` 时使用本地临时副本，Assembly 预览可验证但不落盘、不污染真实会话。
- 复合组件暴露项的 `PropertyOverride.overrides['dataChannel']` 一并参与收集。
- Assembly 运行时预览开启 `showDataChannelDebug`，顶部浮层实时显示写入的键值。

测试：`test/data_channel_service_test.dart` 覆盖取值、收集、跳过规则、clamp 与幂等。

仍不注入 Prompt（留给 A9.6-3）。

#### A9.6-3：SessionState 注入 Prompt MVP（已完成，测试通过）
新增 `lib/services/ui_engine/data_channel_prompt_builder.dart`，在 `chat_page._buildFinalSystemPrompt()` 里接线。

采用结构化状态段（更易调试，作者不必手写占位符），同时保留占位符方式。

注入结构：
```text
[界面数据]
以下是界面当前数据（由玩家操作界面产生）：
- 好感度：45（范围 0~100）
- 主角姓名：林

[可建议更新的隐藏状态]
以下数据当前值对你隐藏，你只能根据剧情建议其变化：
- 敌方警觉度：只可输出 +N/-N，不要在正文中提及当前值。

[界面数据更新格式]
<界面状态变化>
好感度:+N 或 好感度:-N（只给变化量）
心情=新内容（直接给变化后的内容）
</界面状态变化>
```

安全红线（均有单测覆盖）：
- LLM 绝不接收裸值，每行都带 semanticLabel。
- 只有 `llmReadPolicy != none` 才注入当前值。
- 只有 `llmWritePolicy != none` 才进入可更新清单。
- `local_ui_state` 通道永不注入。
- 状态字段仍是 pendingName（未匹配）时跳过，没有可靠取值来源。
- 支持「可写不可读」：只注入更新规则，当前值绝不出现在 Prompt 里。
- 同一目标重复配置去重。

占位符：
- 新增 `{{ui.语义名}}`，在 `_renderPromptTemplate` 中渲染。
- 受 `llmReadPolicy` 约束：不可读或不存在的占位符一律替换为空串，不残留原文、不泄漏受保护值。
- 原有 `{{var.xxx}}` 行为不变。

其他：
- 每轮构建 Prompt 时重新解析通道，作者改完 Assembly 无需重启会话即可生效。
- 更新标签用 `界面状态变化`，与状态栏引擎的 `状态变化` 区分，避免解析串台。
- 本步只做注入，不解析 LLM 回复（留给 A9.6-4）。

测试：`test/data_channel_prompt_builder_test.dart`。

#### A9.6-4：LLM 回复更新界面状态（已完成，测试通过）
新增 `lib/services/ui_engine/data_channel_update_engine.dart`，在 `chat_page` 主回复链路接线。

沿用「LLM 只当裁判给变化量，引擎确定性算账」的既定模式，并在其上加一层数据通道权限校验。

解析流程：
```text
LLM 回复
→ 提取 <界面状态变化> 块
→ 语义名匹配数据通道
→ 权限校验（写策略 / 应用策略）
→ 引擎算账（delta + clamp）
→ 按 llmUpdateApplyPolicy 分流
   ├─ auto_low_risk → 直接写入 SessionState
   ├─ confirm       → 弹确认卡片，用户逐条勾选
   └─ never         → 丢弃
→ 剥离技术标记后展示
```

安全红线（均有单测覆盖）：
- 通道 `llmWritePolicy == none` → 拒绝，哪怕 LLM 输出了该项。
- 通道 `llmUpdateApplyPolicy == never` → 拒绝。
- LLM 编造的未知语义名 → 丢弃。
- `suggest_delta` 通道拒绝 `名称=绝对值` 赋值语法，只接受 +N/-N。
- 数值更新一律由引擎执行 delta + clamp，LLM 不能直接覆盖绝对值。
- 同一项重复输出只取第一条，避免叠加算账。
- 值无实际变化时不产生更新记录。

确认交互：
- `confirm` 策略弹出「界面状态更新」卡片，逐条显示 `好感度：45 → 48（+3）`。
- 默认全部勾选，但必须用户点「应用所选」才生效；「全部忽略」或关闭视为全部拒绝。

标签与既有机制隔离：
- 使用 `界面状态变化`，与状态栏引擎的 `状态变化` 完全分开，两套解析互不干扰。
- 重新生成 / 续写路径只剥离标记、不重复算账（与状态栏既有策略一致）。

测试：`test/data_channel_update_engine_test.dart`。

修复：数值属性读取与预览实时刷新
- `select` 的 `current` 存的是选项 value（String），旧代码统一 `as num?` 强转，
  导致双击下拉单选打开实例编辑器时抛 `type 'String' is not a subtype of type 'num?'`。
  改为宽容读取 `_numProp` / `_intProp`：num 直取、String 尝试解析、其余回落默认值。
  同一问题在复合覆写编辑器的 min / max / current 上一并修掉。
- 运行时预览的数据通道调试浮层只在 LinkerEventBus 事件后刷新，
  而滑块拖动 / 输入 / 开关是直接改写 `module.properties`，不一定发事件，
  因此浮层不跟随操作更新。改为 300ms 低频轮询兜底 + 抬手即同步一次，
  仅在摘要实际变化时 setState，避免无谓重建。

修复：模型不输出 `<界面状态变化>` 标签块
- 现象：Prompt 注入正常（第四步核对通过），但模型实际回复里没有标签块，导致 A9.6-4 无从触发。
- 根因：更新格式约束原本写在 system prompt 开头，长对话中容易被淡忘。
- 处理：
  - 拆出 `DataChannelPromptBuilder.buildUpdateFormatInstruction()`，
    把格式约束改为**历史后注入（PHI）**，追加到对话历史之后，与酒馆 PHI 同理。
  - `buildInjection()` 只保留 `[界面数据]` / `[可建议更新的隐藏状态]` 当前值部分。
  - 约束文案强化：标题加「必须遵守」，明确「不要用代码块包裹」「不要输出未列出的项」。
- 解析容错 `_normalize()`：模型语义正确但格式走样时不应丢弃更新，现已兼容
  - ```` ``` ```` 代码围栏包裹标签块
  - 全角尖括号 `＜界面状态变化＞`
  - 标签内多余空格 `< 界面状态变化 >`
  - 归一化同样作用于 `stripFromReply`，避免走样标记残留在聊天气泡里。

修复：模型「被要求时会输出、日常对话不主动输出」
- 现象：直接命令模型输出标签块可以成功，说明链路正常；但正常对话时它不主动执行。
- 根因：原文案写的是「如果确有变化才输出变化块，没有变化则完全不输出该块」。
  这给了模型一个极易滑落的台阶——它每回合都倾向判定为「无变化」，于是永远不输出。
- 处理（三层递进，均不影响正文质量）：
  1. **取消省略台阶**：改为每回合都必须输出一对 `<界面状态变化>` 标签，
     即使无变化也要输出空标签。空标签块解析后安全返回空结果，不产生任何更新。
  2. **文案定性**：标题改为「每回合必须执行」，明确「这是系统协议，不是可选项，
     也不需要用户提出要求」，并附一行具体示例降低格式歧义。
  3. **回合级提醒**：`buildTurnReminder()` 在最后一条 user 消息尾部追加一行极短提醒。
     PHI 解决「离得远被淡忘」，这行解决「沉浸扮演时忽略系统层要求」；
     长度控制在 120 字符内（有单测约束），不干扰角色扮演质量。
- 无可写通道时，PHI 约束与回合提醒都不生成，不打扰模型。

调优：抑制过度触发（与上一条是一对平衡）
- 背景：「每回合必须输出结算块」在解决不输出问题的同时，会推高另一个风险——
  模型为了让结算块「有内容」而在两三句闲聊后就给出好感度变化。
- 三个诱因与处理：
  1. **示例值被当标准答案照抄**：原示例写的是 `好感度:+2`，模型模仿倾向极强，
     每回合都照着输出 `+2`。改为示例一律使用**空标签块**，
     标题也从「输出示例」改为「默认输出（本回合无事发生时，也是最常见的情况）」。
  2. **只讲必须输出、没讲空块是常态**：在可结算项之前先立预期——
     「绝大多数回合都应该是空结算块。数据只在剧情中真正发生了对应事件时才变化，
     日常对话、寒暄、单纯的信息交流一律不产生变化。」
  3. **缺少变化门槛**：补充判定与幅度规则——
     「拿不准时，一律不写」「普通互动最多小幅变动，大幅变化只保留给重大转折」
     「不要为了让结算块有内容而制造变化」「同一项连续多回合反复变化是不正常的」。
- 回合提醒同步调整措辞：「无变化则输出空标签」→「本回合无对应事件就输出空标签」，
  把判断锚点从主观的「有没有变化」移到客观的「有没有发生对应事件」。
- 设计取向：宁可漏报也不误报。漏报只是少一次状态更新，
  误报会让数值失控漂移，且用户每次都要处理确认弹窗，体验更差。

修复：状态字段被两套机制重复注入（架构级）
- 现象：好感度配了「建议增量」但正常对话不触发；直接说「好感加3」却能触发。
- 根因（不是遵从度问题）：状态字段是 SSOT，会同时被两套机制注入——
  - `StatusBarEngine` 注入 `[状态栏]` + `<状态变化>` 标签
  - `DataChannelPromptBuilder` 注入 `[界面数据]` + `<界面状态变化>` 标签
  同一个「好感度」出现两次，两个标签、两套格式，模型面对矛盾指令时
  往往只执行先出现的那套或干脆都不做。用户直接下命令时才被迫响应。
- 附带的安全问题：`[可建议更新的隐藏状态]` 声明敌方警觉度当前值对 LLM 隐藏，
  但 `[状态栏]` 仍把 `敌方警觉度：0` 原样印出，A9.6-3 的读策略红线被状态栏绕过。
- 处理（确立 SSOT 归属，同一字段只由一套机制负责）：
  - **状态字段统一由 `StatusBarEngine` 注入与解析**，沿用既有 `<状态变化>` 标签。
  - `DataChannelPromptBuilder.buildInjection` / `buildUpdateFormatInstruction` /
    `buildTurnReminder` 全部跳过 `targetKind == 'status_field'`，只处理会话变量。
  - `DataChannelUpdateEngine.parse` 同样跳过状态字段，避免两套引擎重复算账。
  - 新增 `StatusFieldPolicy` 与 `collectStatusFieldPolicies()`：
    把数据通道里配置的读写策略传给状态栏，由状态栏统一执行。
  - `StatusBarEngine.buildInjection` 按策略分组：
    可读的进 `[状态栏]`，可写不可读的进 `[可建议更新的隐藏状态]`（不含当前值），
    并在末尾显式列出「可更新的项」，避免模型输出未授权字段。
  - `StatusBarEngine.applyFromReply` 排除不可写字段，LLM 输出了也不生效。
  - 同一状态字段被多个通道引用时，读写权限取并集。
- 测试：新增 `test/status_bar_engine_policy_test.dart`，
  覆盖值不泄漏、不可写不生效、全禁用不注入等红线。

修复：状态字段移交状态栏后确认弹窗消失（本次改动引入的回归）
- 现象：好感度配的是「用户确认」，但 AI 更新时不再弹卡片，值被直接改掉。
- 根因：把状态字段移交 `StatusBarEngine` 时只传了读写策略，
  **漏传了 `llmUpdateApplyPolicy`**。状态栏原本的行为是解析即写入，
  没有确认环节，于是 confirm 策略被静默降级成了自动应用。
  A9.6-4 的确认卡片只在 `DataChannelUpdateEngine` 里，而状态字段已不走那条路径。
- 处理：
  - `StatusBarEngine.applyFromReply` 新增 `commit` 参数，
    为 false 时只算账不写入 `values`，供确认弹窗预览。
  - `_processStatusBarReply` 按 `applyPolicy` 把字段分两批：
    confirm 批走 `commit: false` + 确认卡片，用户勾选后再写回；
    其余走原有的直接写入。
  - 未被数据通道引用的字段（如纯状态栏的「心情」）默认进自动批，
    状态栏原有行为完全不变，向后兼容。
  - 新增 `_confirmStatusChanges()` 卡片，逐条显示 `好感度：45 → 48`，
    默认全选，必须点「应用所选」才生效。
- 经验：把一个字段的职责从 A 模块移交给 B 模块时，
  必须核对 A 模块支持的**全部**策略维度在 B 模块都有对应实现，
  只迁移一部分会造成静默降级——这类回归比崩溃更难发现。

修复：同行多项时数值增量跑进文本字段（既有解析缺陷）
- 现象：好感度的增量有时会「跑到心情上去」。
- 复现：模型把两项写在同一行时，例如
  `心情=平静，好感度:+3`
  解析器按「等号后的全部内容」取文本值，于是
  心情 = `平静，好感度:+3`，而好感度纹丝不动。
- 根因：解析器假设「一行一项」，但这个假设从未向模型强制过，
  而文本字段的取值是贪婪到行尾的，必然吞掉同行后续的数值项。
- 处理：新增 `StatusBarEngine.splitSegments()`，在解析前把每行切成多个片段。
  - 只在**已知字段名**且其后紧跟 `=` / `:` / `：` 的位置切分，
    因此文本值里的普通逗号（`心情=有点复杂，说不清`）不会被误伤，
    文本值里提到的字段名（`心情=我在想好感度这件事`）也不会误切。
  - 片段尾部的分隔标点（`，,、;；`）会被清理。
  - `DataChannelUpdateEngine` 存在同样缺陷，复用同一方法一并修复。
- 测试：新增同行多项切分与端到端回归用例，覆盖误切/漏切两个方向。

修复：状态栏缺少遵从度机制，模型口头声称已修改但不输出标签块
- 现象：读取状态很流畅，但要求修改时模型常在正文里说「好感度已上升至20」，
  而状态栏纹丝不动（截图实测：状态栏 10%，模型自称 20）。
- 根因：SSOT 重构把状态字段移交给状态栏时，**只搬了注入内容，没搬遵从度机制**。
  当时为数据通道建立的两层强化（PHI 末尾约束 + 回合级提醒）没有对应到状态栏：
  - 状态栏的格式约束仍留在 system prompt 开头——正是已被证明会被长对话淡忘的位置。
  - 更糟的是 `buildUpdateFormatInstruction` 跳过所有状态字段，
    而多数卡片没有可写的会话变量通道，导致整个 PHI 分支根本不执行。
  模型因此只在正文里「表演」修改，并把上轮读到的当前值脑补成修改后的结果。
- 处理：
  - 新增 `StatusBarEngine.buildUpdateFormatInstruction()` 与 `buildTurnReminder()`，
    与数据通道侧完全对等。
  - `buildInjection()` 只保留当前值，格式约束整体移交 PHI。
  - `_withPostHistoryInstructions` 同时注入状态栏与数据通道两套约束，
    回合提醒合并后贴在最后一条用户消息尾部。
  - 约束文案针对本次失败模式补了最关键一条：
    「只有输出标签块才会真正改变状态；仅在正文里说『已修改』是无效的。」
    并补充「每项单独占一行」，配合上一条同行多项修复。
- 经验：迁移职责时，除了核对策略维度，还要核对**为旧路径建立的所有强化机制**
  是否都有对应实现。否则新路径会退回到优化之前的状态，且表现为「功能还在，
  只是不好使」，比直接报错更难定位。

修复：模型口头报出的数值与状态栏对不上（读取侧脑补）
- 现象：写入已全部成功（实测 10 → +16 → -10 → 状态栏 16，正确），
  但模型回答「当前好感度」时报 22。
- 根因（与写入无关，是读取侧问题）：
  1. 模型没有「查询状态」的能力，回答时是**从对话历史推算**——
     看到自己说过「已加16」「已减10」就自行做算术，一旦历史里有歧义
     （如「测试，添加16」未说明对象）就会取错基数。
  2. 存在无法回避的时序：注入的是**本轮开始时**的快照，
     而本轮变化在**回复之后**才结算，模型永远拿不到结算后的值，
     想报「变化后的新值」只能靠猜。
- 处理（不改数据流，只约束表达）：
  - `buildInjection` 在值列表后声明：这些数值是唯一权威来源，
    用户询问时直接照抄，不要根据对话历史自行推算或累加。
  - `buildUpdateFormatInstruction`（PHI，遵从度最高的位置）补一段
    「关于在正文里提到数值」：禁止自行累加、说明本轮变化在回复后才结算、
    因此不要在正文里声称变化后的新数值。
- 保留模型口头报数的能力（用户选择），只要求它照抄注入值而非自行计算。

修复：模型宣称「无法读取状态值」（上一版约束措辞过度）
- 现象：问「读取当前状态值」时，模型回答「当前状态值对我不透明，无法直接读取」，
  但 [状态栏] 段落里明明给了当前值。
- 根因：上一版为防脑补连加了三条**全否定句**的约束
  （不要推算 / 你的推算通常是错的 / 不要声称变化后的新数值）。
  模型把这些泛化成了「我无权读取状态」，甚至把隐藏字段
  （[可建议更新的隐藏状态]）的规则套用到了所有可读字段上。
  问题出在只讲了「不准做什么」，没讲「该做什么」。
- 处理：把措辞从否定句改为肯定句为主。
  - 注入段：先明确「你可以看到下面这些数值」，再要求「直接读出对应数字」。
  - PHI：改为「[状态栏] 已给出所有可见状态的当前值，你能够看到它们」
    「用户询问时请如实回答」「不需要自己累加，系统会在你回复之后自动结算」。
  - 显式划出例外边界：只有 [可建议更新的隐藏状态] 里的项才需要说明无法得知，
    防止规则被泛化到可读字段。
- 经验：约束模型行为时，纯否定句容易被过度泛化成「这件事我不能做」。
  应当「先肯定能力边界，再约束具体做法」，并显式标出例外范围。

修复：撤回消息后状态变化残留（数据一致性）
- 现象：让 AI 加 5 点好感度后撤回该消息，对话没了但状态栏的 +5 仍在，
  导致状态栏与对话历史长期不一致，越用偏得越多。
- 根因：删除消息只删了 `messages` 表记录，完全没有回滚 `SessionState`。
- 处理（消息级状态快照）：
  - 数据库升级到 v4，`messages` 表新增 `state_snapshot` 列，
    存该消息**结算之前**的 SessionState JSON。
  - AI 回复入库时先取快照再结算，顺序不能颠倒。
  - 新增 `DatabaseService.getStateSnapshots()` 批量读取快照。
  - 新增 `_rollbackSessionStateFor()`：取被删消息中 id 最小（最早）那条的快照，
    还原会话状态并落盘。其后的所有变化都由这批被删消息产生，因此还原到它即可。
  - 两条删除路径（编辑用户消息重发、删除单轮对话）都接入回滚。
  - 重新生成路径不接入：它本就不重复算账，状态以首次回复为准。
  - 旧数据（升级前入库、无快照）找不到快照时保持现状，不猜值。

工具：Prompt 预览页展示完整请求
- 背景：预览页原本只渲染 `systemPrompt`，不渲染 `messages`，
  而 PHI / 结算约束 / 回合提醒都是以 message 形式发送的。
  这个缺陷两次误导排查方向（以为约束没发出去、以为注入值有误）。
- 处理：预览页拆成三段展示——System Prompt（开头）、对话历史、历史后注入（PHI）。
  PHI 段橙色高亮；信息卡增加「消息条数」；复制全部会导出三段完整内容。
  拆分逻辑（从末尾往前取连续 system 消息）有单测覆盖，含「中间的 system
  不被误判为 PHI」等边界，避免这个工具自身成为新的误导源。

修复：模型报数采信历史旧值而非注入值
- 借助完整预览定位：注入的 `[状态栏]` 是「好感度：4」，UI 也是 4%，
  **代码完全正确**；且「清零后 0 → 4」证明每轮 +1 的结算一直正常，
  写入链路健康。问题只在读数环节——模型报了 5 / 3，都是它自己上文说过的数。
- 根因：
  1. **距离**：`[状态栏]` 在 system prompt 结尾，前面压着整个世界书
     （实测总长 2228 tokens）。模型报数时，近处对话历史里自己说过的旧数字
     比远处的权威值更容易被采信。
  2. **污染**：一旦报错一次，错误答案进入对话历史，成为后续轮次的「证据」，
     形成自我强化。
- 处理：在 PHI 里**重述一份当前值**（PHI 紧邻本回合，遵从度已验证最高），
  并明确「如果你在更早的对话里说过不同的数字，那是过时或错误的，
  一律以上面这份为准，不要沿用历史消息里的旧数字」。
  不可读字段（可写不可读）不在此处暴露当前值，红线不变，有单测守。

修复：模型把注入值当起点，重复累加已结算的变化
- 现象：实际 50，模型报 75，并自述「初始好感度50，加上你之前要求的25，得75」。
- 定位：PHI 重述当前值的机制**已生效**（它确实读到了 50），
  但它把 50 理解成「本轮变化之前的起点」，又把历史里看到的 +25 补加了一遍。
- 根因：措辞歧义。原文「不需要自己累加，本回合的变化会由系统在你回复之后自动结算」
  被理解为「历史变化已算过，但我刚答应的这次还没算，需要我自己补上」。
  从未明说过一句关键事实：**注入值已经包含了此前所有轮次的结算结果**。
- 处理：
  - 标题由「当前状态值」改为「最新状态值（已包含此前所有回合的结算结果）」，
    从名称上就排除「起点」的解读。
  - 补充：「这些数字**已经包含**了此前每一轮的变化，包括你上一条回复里
    刚刚结算的那次。不要再把历史消息里出现过的变化量加到它们上面。」
  - 补充自校验：「如果你的计算结果和上面的数字不一致，
    一定是你算错了或重复计算了，请以上面的数字为准。」
  - 明确本回合新变化的处理：「只需写进结算块，系统会自动累加，
    不需要在正文里预告结果。」
  - `buildInjection` 的 `[状态栏]` 段同步改为「最新状态值，已包含……」。
- 经验：给模型的数据要说清**语义**而不只是数值。
  「当前值」是歧义词——可以理解为起点也可以理解为结果；
  「已包含所有历史结算的最新结果」才是无歧义的表述。

设计：撤回历史后状态与认知脱节时的处理原则
- 问题本质（用户提出）：LLM 的认知来源是对话历史，状态的真相在 SessionState。
  一旦历史被撤回或编辑，两者必然脱节——历史里没有那次 +25 了，
  但数值确实变了。模型面对无法解释的数字，就会编造一个理由。
  这是「外部状态 + 对话历史」架构的固有矛盾，提示词无法根治。
- 分层处理：
  1. **治本**：撤回时回滚状态（见上文 DB v4 消息级快照），
     让历史与状态同步消失，模型看到的始终是自洽的。
     注意仅对升级后新产生的消息生效。
  2. **治标**：约束模型在冲突时的行为（本次改动）。
- 本次采用的原则（用户定）：**保留推理能力，但事实以系统为准**。
  - 不禁止模型推导——完全禁止会让对话变机械。
  - 推算与系统值冲突时，一律以系统值为准，
    不得为自圆其说而修改数值或编造推导过程。
  - 明确告知「推不出来是正常的，历史可能被撤回或编辑过」，
    给模型一个合理的「未知」出口，而不是逼它编。
  - **允许它提出质疑**：有充分理由怀疑系统数据有误时，
    可简短说出疑问与推算依据，但仍以系统数字为准。
- 附带价值：把分歧显式化之后，模型的质疑反而成了排查信号——
  若它报告「我的推算与系统不符」，有可能是引擎侧真的算错了。

修复：进入聊天页 LateInitializationError（既有隐患，非本次引入）
- 现象：`Field '_currentCharacter' has not been initialized`，
  栈顶为 `_loadPromptSettings` ← `initState`。
- 根因：`_currentCharacter` 声明为 `late CharacterCard?`，
  但 `initState` 中 `_loadPromptSettings()`（读取该字段）执行在
  `_currentCharacter = widget.character` 赋值**之前**，构成读早于写。
  该声明自 `b4490dd` 起就存在，属于既有隐患，只是此前未必每次都命中。
- 处理：改为普通可空字段 `CharacterCard? _currentCharacter`，默认 null。
  `late` 对可空类型本就没有收益（可空字段无需延迟初始化即可满足空安全），
  且全项目已按可空语义使用它（`_currentCharacter?.` / `_currentCharacter!`），
  因此改动不影响既有调用点。

### A9.6 不做
- 不做完整自动状态解析器。
- 不做复杂 Prompt 分频策略。
- 不做聊天页所有 mode 接入。
- 不做状态自动演化版本管理。

### A10 进入补充条件
除 A9.5 的通用模板条件外，进入 A10 前还应满足：
1. UI 至少能把 input / select / switch / slider 写入 SessionState。
2. SessionState 至少能以一种稳定格式进入 Prompt。
3. Binding 名称解析不会强迫普通创作者手填内部 ID。
4. LLM 状态更新格式已有预留方案。

---

## A10：mode 差异逻辑收口

### 要收口的能力
- opening：确认后销毁
- scene：完全接管 + 设置入口 + extra 强制常驻
- extra_sticky：折叠开关 / 悬浮球
- extra_companion：伴生消息下挂

---

## A11：消息流窗口（提前到 scene 之前 / 同步进行）

### 排期调整
原计划排在 A10 之后。但 scene 完全顶替聊天页后，
原生消息气泡被禁用，**没有消息流组件就只能做实时交互类**，
做不了 galgame 那种需要历史对话的类型——而后者是主要用例之一。
因此 A11 提前，与 A10-5 同步或先行。

### 要点
- 独立组件，不作为普通 text 变体
- 接受用户消息 / LLM 回复
- append + 自动滚到底
- scene / extra_companion 可见

### A11-1：骨架（已完成，测试通过）

#### 复用而非重写
排查发现聊天页的渲染管线已经很完整，`_buildMarkdownWidget` 会自动分流：
HTML → `flutter_html`；复杂 Markdown → `MarkdownBody`；
普通文本 → `_buildStyledRoleplayText`。流式追加也是现成的
（`aiResponseContent += chunk; setState()`）。
因此 A11-1 是接线，富文本能力后续可直接接上（见 A11-2）。

#### 数据链路
```
chat_page._messages（含 id / versions 等编辑态字段）
  ↓ _flowMessages：只取 role + content
ChatAssemblyMount(messages:)
  ↓
UIAssemblyRuntimeView(messages:)
  ↓ MessageFlowScope 包住整个设计面
UIRenderer 渲染 message_flow
  ↓ MessageFlowScope.maybeOf(context)
_MessageFlowList 滚动列表
```

**消息走 `InheritedWidget` 而不是 `module.properties`**，两个原因：
- 消息是会话数据而非组件配置，写进 properties 会被
  `_persistAssemblyElements` 一并存进角色卡；
- 流式输出每个 chunk 都要刷新，走 properties 会触发整棵树重建。

#### 滚动（用户明确为必做）
作者固定窗口尺寸后，内容必须能在其中滚动，否则长对话被裁掉且无法查看。
- 新消息 / 流式追加自动滚到底；
- **用户向上翻看历史时不硬拽回底部**（距底 80px 内才跟随）。

#### 可配置项
- 显示条数：留空 = 全部，填 N = 最近 N 条（两种都支持，用户要求）
- 字号、玩家/角色消息各自的显示开关
- 气泡配色与圆角

#### 样式决策（用户选择）
先做**固定气泡**，作者只调颜色 / 字号 / 圆角。
「作者用复合组件自定义气泡模板」留到以后按实际需求再定——
那需要一套模板实例化机制，工作量大很多。

#### 编辑器占位
无 `MessageFlowScope` 时（Assembly 编辑器预览）显示三条示例消息，
让作者能看到排版效果，而不是面对一块空白。

测试：`test/message_flow_test.dart` 覆盖更新通知（含流式追加）、
条数限制语义（保留最近而非最早）、角色过滤。

### A11 附带：可滚动长文本（已完成，测试通过）

#### 需求
用户提出：滚动窗口不只对话记录有用，复杂角色卡还需要
**readme 式的详细说明**，以及**获得道具时弹出的长文描述**。

#### 做法：扩展 text 而非新增组件（用户决定）
`text` 本来就是显示文字的，加一个「可滚动」开关即可，
不必新增组件类型，作者也不用学新概念。

`overflow` 属性原本就有 `scroll` 值，但实现过于简陋
（居中对齐、无滚动条、粗体、不能选中），不适合长文。已重写为
`_ScrollableTextBlock`：
- **从顶部开始**，不像消息流那样自动滚到底——它是一整块静态内容；
- 带滚动条（`thumbVisibility`），让玩家知道还有内容；
- 可选中复制；
- 正常字重 + 1.5 行距（粗体长文读起来很累）；
- 内容被 linker / 数据通道换成另一段时**自动回到顶部**，
  否则玩家会从上一段的滚动位置开始看新内容。

#### 内容来源（两者都支持）
- 作者预先写好：`properties['text']`，编辑器在滚动模式下把输入框
  扩展为 6~10 行，方便写长文；
- 运行时动态注入：linker / 数据通道，走 `resolveLinkedTextValue`，
  这条路本来就通，无需额外改动。
  → 「获得道具时弹出说明」用 linker 触发即可。

#### 编辑器
新增「超出显示区时」（省略号 / 裁切 / 可滚动）与「对齐方式」两个下拉，
选中滚动模式时给出用途说明。

测试：`test/scrollable_text_test.dart`。

### A11-2：富文本（已完成，测试通过）

`lib/services/ui_engine/assembly_rich_text.dart`，消息流与可滚动长文本共用。

#### 三档降级
1. 含 HTML 标签 → `flutter_html`
2. 含复杂 Markdown（表格 / 代码块 / 列表 / 标题 / 链接）→ `MarkdownBody`
3. 其余 → 正则着色（见下）

第 3 档不是「纯文本」：角色扮演文本绝大多数属于这一类，
轻量着色比直接 `Text` 观感好得多，开销也远低于跑一次 Markdown 解析。

#### 为什么不复用聊天页的 `_buildMarkdownWidget`
它绑在 `_ChatPageState` 上，依赖 `_renderPromptTemplate`（宏替换要
角色 / 用户名）与 `_handleMarkdownAction`（重试 / 编辑等聊天动作），
这两样在 Assembly 运行时都不存在。判定与降级策略刻意保持一致，
让同一段文本在原生气泡与 Assembly 组件里长得一样。

#### 两个刻意的判定边界（有测试守着）
- **不检测 `**加粗**` / `*斜体*`**：星号在角色扮演文本里大量用作
  动作标记（`*他转过身*`），按 Markdown 解析会把内容吃掉。
  列表判定要求星号后必须有空格。
- **HTML 只认白名单标签**：否则「当 HP<50 时触发」会被当成
  未闭合标签，后半段全被吞。

#### 默认值按用途分三档
| 组件 | 默认 | 理由 |
|---|---|---|
| message_flow | 开 | LLM 回复带 Markdown 是常态 |
| text（滚动模式） | 开 | readme / 道具说明几乎必然带标题和列表 |
| text（其他模式） | 关 | 多被 linker 指向显示数值，解析无收益还会误判 |

作者显式设过就以存档为准，切换显示模式不会被默认值覆盖。

图片沿用**本地优先**原则：data URI 与本地路径正常显示，
外链降级为占位不联网。

测试：`test/assembly_rich_text_test.dart`。

### A11-2 附带：正则着色规则可自定义（已完成，测试通过）

原本四条着色规则写死在 `chat_page._styleForRoleplayToken` 里
（引号 / 括号 / 书名号 / 方括号）。改为数据驱动——
不同卡片的写作约定差异很大，有人用 `**` 包动作，有人用 `[]` 包旁白，
写死的四条覆盖不了。

- `lib/models/text_highlight_rule.dart` —— 规则模型，存进
  `CharacterMeta.textHighlightRules`，随卡片导入导出。
- `lib/services/text_highlight_engine.dart` —— 切分与着色。
- `lib/pages/text_highlight_rules_edit_page.dart` —— 编辑页，带即时预览。
- 入口在角色编辑页「状态栏 / UI 拼装」下方。

#### 设计要点

**只着色，不改写文本。** 这是有意的安全边界，与酒馆的 `regex_scripts`
不同——后者会改写内容。我们只影响显示，发给 LLM 与存库的始终是原文，
因此规则写坏了最多是难看，不会污染存档或让模型收到错误输入。

**规则顺序即优先级。** 靠前的先占位，后面的规则不能与已占区间重叠。
部分重叠时**整条丢弃**而非半截着色——半截着色比不着色更糟。

**非法正则跳过而非抛异常。** 作者边写边预览必然出现半成品状态
（刚敲下 `(` 还没敲 `)`），抛异常会让整个消息列表白屏。
编辑页用红字提示「这条不会生效」。

**空列表 = 没配过，回落内置默认**，不等于「不要着色」。
保证老卡片升级后观感不变。想完全关闭需留一条停用的空规则。

**防御灾难性回溯**：单条规则每段文本最多匹配
`TextHighlightEngine.maxMatchesPerRule`（500）次。

**作用范围**：聊天页原生气泡与 Assembly 组件共用同一套规则（用户要求）。
Assembly 侧通过 `TextHighlightScope` 传递——规则是角色卡级配置，
写进 `module.properties` 会被 `_persistAssemblyElements` 复制进每个组件。

**只作用于第 3 档**：Markdown / HTML 有自己的语法着色，
再叠一层正则会互相打架。

测试：`test/text_highlight_engine_test.dart`。

### A11-2 消息操作与头像（已完成，测试通过）

原计划是在 `message_flow` 里内置一排功能小图标。用户否决并给出更好的方案：
**用 button 通过 linker 连到消息流**，头像**用 image 组件同步**。

理由成立且与既有原则一致——「作者用通用组件表达意图，外观完全自定」。
内置图标的外观不可控，必然与作者的美术风格冲突。

#### 消息操作：`button_to_message_action` 方案

走 linker 而非语义标记，因为它**需要携带参数**（执行哪个动作）。
语义标记是「是 / 否」的单一职责，表达不了六种动作的选择。

六个动作（`MessageAction`）：
`regenerate` / `continue` / `edit` / `delete` / `version_prev` / `version_next`

**作用对象固定为最新一条 AI 消息**（用户确认），与原生气泡的功能键一致。
因此 `message_flow` **不需要引入选中态**，实现与心智负担都最小。

实现要点：
- `MessageAction.key` 用**显式字符串**而非 `enum.name`：
  参数值随角色卡序列化，重命名枚举项不该让老卡片的配置失效。
- `fromKey` 认不出时返回 null，**不回落默认动作**——
  静默执行「重新生成」会让玩家莫名其妙丢掉一条回复。
- 聊天页 `_handleMessageAction` **复用已有方法**
  （`_regenerateMessage` / `_continueMessage` / `_deleteUserMessage`）：
  数据库写入、状态回滚、版本记录都已在那些方法里处理妥当，
  平行实现必然漏掉某一步。
- **编辑走弹窗**而不是 `_startEdit`：后者把内容送进底部输入栏，
  而 scene 接管时输入栏根本不渲染，玩家会看到「点了没反应」。
- 撤回时先从 AI 下标往前找到本轮的提问——
  `_deleteUserMessage` 的入口是 user 消息。
- 版本切换要**同步 `msg['id']`**：后续编辑 / 删除都按 id 落库，
  不同步会把改动写到别的版本上。
- 无多版本 / 已到边界时给 toast 提示，不静默无反应——
  玩家按了没动静会以为 UI 坏了。

#### 头像：image 组件的「图片来源」下拉

选「角色头像 / 用户头像」后路径由运行时提供（`AvatarScope`），
作者填的静态地址被忽略并置灰。

- 走 InheritedWidget 而非 `module.properties`：
  头像是**运行时数据**，写进 properties 会被 `_persistAssemblyElements`
  把某台设备上的本地路径固化进可分享的角色卡。
- 头像未设置时**不回落到作者填的静态图**：
  作者选了「显示角色头像」，却显示一张无关图片会更让人困惑。
- 用户头像取值优先级：角色卡的 `userAvatar` > 全局用户设定，
  作者可为单张卡指定专属玩家形象。
- `_buildImageBlock` 外包 `Builder`——
  又一次「取作用域必须用新 context」（见上文通用规则）。

#### 首轮测试暴露的问题

**1. Assembly 联动器配置页缺方案参数编辑器（主因）**
`_showAssemblyLinkerConfigDialog` 只做了「选源 → 选目标 → 选方案」，
**没有把 Studio 侧的参数编辑器搬过来**。
后果：带参数的方案保存后只能吃默认值，作者无从配置——
表现就是「只有一种操作，切不了别的动作」。

补上 `_buildAssemblySchemeParamEditors`，支持
choice / number / doubleVal / text / boolean。
Studio 侧还有 color，Assembly 暂无带颜色参数的方案，等出现再补。

配套的三条状态维护：
- 换方案 / 换源目标时**清空 schemeParams**——
  留着会把上一个方案的键带进新方案；
- 保存时用方案声明的默认值补齐缺省项，运行端不必各自兜底；
- 清除连接时一并 `remove('schemeParams')`。

**2. 运行端对缺失参数过于严格**
`_resolveMessageAction` 原本参数缺失就返回 null，按钮完全没反应。
改为区分两种情况：
- **参数缺失**（老数据 / 跳过配置）→ 回落方案声明的默认动作；
- **参数值非法**（认不出来）→ 仍返回 null，静默执行别的动作更危险。

**3. 「只能退回旧版本」的排查结论**
`_switchVersion` 本身是对称的，`version_prev` / `version_next`
两个动作也都已登记。实际原因是问题 1——
作者只能保存出默认的 `regenerate`，根本选不到 `version_next`。
参数编辑器补上后即可正常双向切换。

> 教训：**新增带参数的方案时，务必确认 Assembly 侧也能配置该参数。**
> Assembly 与 Studio 共用方案矩阵，但**编辑器是两套**，
> 只在矩阵里登记不等于作者能用上。这与 `button_to_page_route`
> 漏登记是同类问题的两个不同环节。

测试：`test/message_action_test.dart`。

### A11-2 剩余（待做）
- 头像之外的消息元信息（时间戳等），暂无需求

### 关键区分（用户明确）
消息流是否显示**纯粹是玩家侧的展示选择**：
- 实时交互类游戏可以不放这个组件；
- galgame 类必须放。

但**LLM 始终获取完整历史**，与组件是否存在无关。
不要把「不显示」实现成「不发送」。

---

## A10-3：extra_companion 伴生 UI（已完成，测试通过）

### 定位（用户确认）
**内嵌进 AI 消息气泡的最下方**，与正文同属一个气泡容器。
不是「浮在气泡下面的独立层」——这个区别带来两个实际好处：

1. 省掉气泡外围一套功能按钮的排布空间；
2. **撤回 / 删除消息时，这条消息携带的数据记录一并消失**，
   不需要任何额外的清理逻辑。

### 只有最新一条 AI 消息可交互
历史消息里的伴生 UI **仍然渲染**（否则翻看历史会看到一堆空气泡），
但用 `IgnorePointer` 禁止操作，并压到 0.55 透明度让「不能点」一眼可见。

理由：所有实例共享同一份 `SessionState`。允许操作历史实例
等于让玩家回到过去修改当前状态，语义混乱。

### 宽度上限：必须塞进气泡
`UIAssemblyInfo.companionMaxPcbWidth = 212`，由气泡尺寸倒推：

```
气泡宽 = 屏宽 * 0.7 - 20      （已有的气泡约束）
可用宽 = 气泡宽 - 10 * 2       （气泡内边距）
以设计基准宽 360 折算 → 360 * 0.7 - 40 = 212
```

新增 `UIAssemblyInfo.maxPcbWidthFor(mode)`，只有伴生比通用上限窄。
编辑器的宽度手柄走 `_clampPcbWidth`，已随之变成 mode 感知；
挂载与运行时也各 clamp 一次，兜住宽度约束加入之前存下的旧数据。

**高度不做多大限制**（用户设计）：内容长了由气泡自身撑高，
随聊天列表一起滚动，天然就是「跟随滚动」，不需要额外的同步逻辑。

### 不给关键职责标记
`UISemanticRole` 里伴生保持「无要求」，也不给折叠语义。
它嵌在气泡里没有需要主动退出的状态，加了只是徒增作者负担
与实现工作量（用户判断）。

### 与 scene 互斥（补齐双向拦截）
scene 接管后不渲染原生消息列表，伴生失去宿主气泡。

原先只拦了一个方向（有 scene 时不能建伴生），
现在补上反向：**有伴生时不能建 scene**，
并给禁用项写明具体原因而不是笼统的「已达上限」。

数据层**不做删除**：已有卡片不该因规则变化被静默删掉方案。
`_buildCompanionAssembly` 里再判一次 `_sceneTakesOver` 作为防御，
兜住补齐拦截之前可能已存在的无效组合。

测试：`test/companion_assembly_test.dart`。

---

## A10-5：scene 场景 UI（已完成，测试通过）

### 定位（用户确认）
**完全顶替聊天页**，而非「换个背景的聊天页」：
- 原生消息气泡、输入框全部禁用；
- 聊天页只作为 UI 的背景蒙版；
- **底层逻辑上无法关闭**，只能删除该组装 UI；
- 因此关键职责标记是「打开聊天设置」而非「退出场景」。

### 聊天设置菜单保留
`scene` 替代不了系统级功能——重置对话、用户设定、Prompt 预览
仍在原设置菜单里。关键职责按钮打开的就是它。
（未来若需要，可把标记细化为「专指其中某一页」。）

### 输入与交互（用户澄清，避免过度设计）
**不新增「输入框模式」配置**。现有 linker 已能组合出所需能力：

```
input --linker--> text --数据通道--> 注入 Prompt
```

- 回车提交时更新 text 内容；
- text 若无需显示，可拖出 PCB 作为纯后台数据载体。

因此「对话模式 / 数据模式」不需要专门的开关，作者用连线自行组合。

### 唯一的能力缺口：发送消息
上述方案缺的是「回车时把内容作为 user 消息**发出去**」。
这与数据通道有本质区别：

| | 数据通道（已有） | 发送消息（待做） |
|---|---|---|
| 时机 | 每轮构建 Prompt 时读取 | 玩家提交的那一刻 |
| 语义 | 静态设定的一部分 | 一条 user 消息 |
| 效果 | 影响 LLM **怎么回答** | **触发** LLM 回答 |

实现方向：复用关键职责标记体系，新增一个「发送消息」动作，
挂在 button 或 input 上，触发时调用聊天页现有的 `_sendMessage` 链路。

### 实现要点

#### 接管条件
`_sceneTakesOver` = 有 scene 方案 **且** 已标记「打开聊天设置」。
缺标记时**不接管**——否则玩家进不了设置页，
连重置对话都做不到，等于被彻底锁死。

#### 层级顺序（主 Stack，后者盖前者）
```
1. 背景图层
2. 消息列表 + 状态栏   ← scene 接管时不渲染（含头像与气泡）
3. 输入栏             ← scene 接管时不渲染
4. scene 场景 UI      ← 半透明蒙版 + 全屏铺满
5. 常驻 UI            ← 叠在场景之上，scene 下**照常显示**
6. 开场白 UI          ← 仍在最上（先看开场白，确认后进场景）
```

**常驻 UI 排在 scene 之后（用户反馈后修正，已测试通过）。**
初版把常驻 UI 排在 scene 之前并在接管时整个隐藏，理由是
「场景已是完整界面，再浮一个挂件既遮挡又语义重复」——这个判断是错的。
常驻挂件是**始终可用的工具层**（背包、快捷面板这类），
场景再全屏也不该把它埋掉。玩家实测反馈即为「常驻 UI 都被盖住了」。

仍排在开场白之前：开场白要求玩家先确认再进场景，中途不该被挂件干扰。

实现上抽出了 `_buildStickyAssemblyLayer`，与开场白 / scene 同规矩——
**始终返回 `Positioned`**，隐藏时返回 `Positioned.fill(IgnorePointer(SizedBox()))`，
不能返回裸 widget（会成为主 Stack 唯一非定位子组件，整页黑屏）。

#### 首轮测试暴露的四个问题（均已修复）

**1. 消息流永远显示三句示例对话**
两处叠加：
- `_buildMessageFlowBlock` 的兜底写成
  `live ?? (isStudio || live == null ? 示例 : 空)`，
  运行时拿不到作用域也会回落到示例；
- **根因**：`_buildRuntimeElement(context, ...)` 传的是 `State.build`
  的 context，它位于 `MessageFlowScope` **之上**，
  `dependOnInheritedWidgetOfExactType` 永远返回 null。

> **通用规则**：在 `build` 里包了 InheritedWidget 之后，
> 子树取作用域必须用 `Builder` 拿新的 context，
> 不能沿用外层的 `context`。这条对 `UILinkerSnapshotScope` /
> `UISceneModeScope` 同样成立。

修复后运行时兜底改为「拿不到就显示暂无消息」，
**绝不回落示例**——玩家不该看见假对话。

**2. 缺背景蒙版**
scene 层原来只有 `ChatAssemblyMount`，PCB 等比缩放留出的信箱区
直接透出聊天背景图，观感像「UI 浮在聊天上」。
加了一层压暗蒙版，`alpha: 0.32`——
不用不透明：作者选的背景图本身是场景观感的一部分，
全遮住反而丢信息，只需压到不与 PCB 内容抢视线。

**3. 状态栏 / 头像 / 气泡仍然可见**
原来只做了 `IgnorePointer`（禁交互）而没有停止渲染。
改为 scene 接管时状态栏整块不渲染、消息 `ListView` 整条不渲染
（头像和气泡都在这条列表里）。

**4. 聊天设置页被压在 PCB 下方**
设置面板在「聊天主体 + 右侧面板」那个 `Positioned` 里，
而 scene 层排在它之后，必然被盖住。
改为 scene 层跟随 `_animController` **同步左移**，面板滑出时一起让开；
同时主体的 `IgnorePointer` 改为「设置页滑出过半即恢复交互」，
否则进了设置页所有条目都点不动。

#### scene 内禁用页面级横向拖动

聊天页根部的「右滑打开设置」与 PCB 的翻页手势方向完全相同，
同时存在必然误触。**设置页的唯一入口收敛为关键职责按钮。**

实现：scene 层最外层包一个 `GestureDetector`，
用空实现吃掉 `onHorizontalDrag*`。这是手势竞技场规则的正向利用——
子级的 HorizontalDrag 识别器会赢过根部的同类识别器，从而截断冒泡；
而 PCB 内部翻页走的是 `Listener`（不参与竞技场），不受影响。

#### 新增能力：发送消息
这是 scene 唯一需要的新机制（其余都是接线）。

- `UISemanticRole.sendKey`（`sendsMessage`）与关键职责标记**并列而非合并**——
  scene 里「打开设置」和「发送消息」是两个不同的按钮，各自独立标记。
- 仅 scene 支持该标记：其余 mode 的原生输入框仍在，不需要。
- 可标记类型：
  - `button`：点击发送（选项式剧情），内容取 linker 联动值，
    无联动则用按钮文字；
  - `input`：回车提交发送，内容取提交值，**发送后自动清空**，
    避免玩家重复提交同一句。
- 运行端复用既有脉冲（`tap` / `input_commit`），不改渲染器，
  被标记的组件仍可正常参与 linker。
- 聊天页新增 `_sendMessageFromAssembly(text)`：
  与 `_sendMessage` 的区别是文本来自 UI 组件而非输入框控制器。

#### 编辑器
按钮 / 输入框实例编辑页的标题栏出现绿色「点击发送 / 回车发送」标签，
仅在 scene 方案下显示。

测试：`test/scene_takeover_test.dart` 覆盖职责语义、标记独立性、
可标记类型限制、序列化。

### 不做准入拦截（用户决定）
scene 缺少输入组件时**不拦截**，仅由作者自行负责。

理由：选项驱动的剧情游戏是完全合理的形态——
玩家只需判断不需输入，由 LLM 每轮给出新选项。
硬性要求输入框会挡掉一整类玩法。
（与 opening 缺确认按钮不同：那会把玩家卡死，属于必须拦截的情形。）

---

## A13：玩家参与的会话初始化（已完成，测试通过）

### 需求来源
完成 A10-4 后，用户提出 opening UI 的主要用途其实是：
介绍角色卡、**让玩家编辑自己的角色档案**、选择场景、分配初始属性点。
这类内容不能只当会话数据发给 LLM，必须进入系统级设定。

典型场景：世界卡作者留空角色档案，改由 opening UI 让玩家自建，
甚至提供角色卡编辑页没有的玩法（如给定点数自行分配属性）。

### 核心判断：不要真的改 systemPrompt
这不是「修改角色卡」，而是「让玩家参与会话的初始化」。

角色卡是可分享的——玩家 A 填的档案不能写进卡里带给玩家 B。
而且该数据本就应随「清空历史」一起重置（与开场白重新出现同步）。

因此：**数据存会话副本，但注入位置提升到 systemPrompt 层级**，
与 `[核心角色设定]` 并列，而不是塞进 `[界面数据]`。

三层数据模型：

| 层 | 存储 | 生命周期 | 谁能改 |
|----|------|----------|--------|
| 角色卡母版 | `characters` 表 | 永久、跨会话 | 作者（编辑页） |
| **会话初始化** | **← A13 补这层** | 随会话，清空即重置 | **玩家（opening UI）** |
| 会话状态 | `SessionState` | 随会话 | UI 交互 / LLM |

### 已具备的基础
`SessionState.vars` + `{{var.xxx}}` 占位符渲染已经可用。
作者今天就能这么做：设定里写 `{{var.主角姓名}}`，
opening 的 input 配数据通道写入同名会话变量。

### 作用范围：做进通用模板，所有 mode 可用（用户确认）

问过「scene 是否也需要写系统级设定」，用户答：暂时想不到具体例子，
但**以防万一先做进通用模板**，不限定 mode。

因此实现上不引入任何 mode 判断——数据通道本来就是所有 mode 共用的机制，
在它上面加一个「注入位置」维度是最小改动，也天然对所有 UI 生效。

### A13-1：注入位置可选（已完成，测试通过）

数据通道新增 `promptSection` 字段：

| 取值 | 注入到 | 语义 |
|---|---|---|
| `ui_data`（默认） | `[界面数据]` | 玩家操作界面产生的运行时数据 |
| `core_setting` | `[玩家档案]` | 本次会话的初始设定，与核心角色设定并列 |

**为什么必须分段**，而不是都塞进 `[界面数据]`：
玩家填的姓名 / 职业 / 属性本质是**角色设定的一部分**，
不是「界面上的一个数值」。混在界面数据里，模型会把它当成
可有可无的运行时状态而弱化处理——「玩家填的姓名被无视」
是最典型的症状。

措辞也刻意区分：档案段写「属于角色设定的一部分，在整场对话中
保持有效」，而不是界面数据那句「以下是界面当前数据」。
这句措辞直接决定模型在长对话里是否持续遵守，是这一步的全部意义。

实现要点：
- **缺省回落 `ui_data`**，老卡片行为完全不变。
- 档案段**排在界面数据之前**——设定先于运行时数据。
- 下拉只在「发送当前值给 AI」不为「不发送」时出现：
  不发送的通道谈注入位置没有意义。
- **读策略优先于注入位置**：选了档案但设为不发送，仍然不注入。
- 未填写的档案项显示「（未设置）」而非静默消失——
  模型需要知道「这项玩家没填」。
- 原子实例编辑器与复合暴露项编辑器**两处都要接**
  （共用 `_buildDataChannelFormFields`，但状态变量是各自的）。

测试：`test/player_profile_section_test.dart`。

### A13-2：结构化档案 = 直接指向角色卡条目（已完成，测试通过）

原方案是「另建一套档案字段」。用户提出了更好的思路：
**数据通道直接指向角色卡已有的设定条目**，三级定位：

```
一级 group    简单介绍 / 详细设定
二级 entryId  条目（身体数据 / 心理数据 / 自定义条目…）
三级 fieldKey 子字段（种族 / 性别 / 年龄…）
```

好处是不必发明第二套字段体系——作者在角色卡里怎么组织设定，
玩家就往哪几格里填，语义天然对齐。

#### 用户确认的三条规则

**a) 只写会话副本，不改角色卡。**
角色卡可分享，玩家 A 填的内容不能带给玩家 B；
清空聊天记录即回到作者的原始设定。

**b) 冲突时玩家值覆盖。**
作者写的相当于「预设值」。注入措辞明确写
「若与前文的角色设定有冲突，以此处为准」——
仅靠分段顺序不足以让模型知道该听谁的。

**c) 自定义条目也有第三级 = 标题输入。**
用户在讨论中修正了最初的判断：自定义条目默认名都是「新条目」，
第三级用来写标题，这样才能同时存在多个自定义条目。
且**选择「添加自定义条目」不等于立即新建**——
玩家输入并提交后才真正产生。

#### 关键实现细节

- `sessionKey` 带 `card:` 前缀（`card:detail:body:race`），
  与普通会话变量隔开——作者可能起同名变量，不隔开会互相覆盖。
- 自定义条目按**标题**成键：同标题视为同一条目，重复填写是覆盖而非新增。
- **玩家未填时整条不注入**。这条最关键：
  档案项语义是「玩家做出的选择」，没选就该让母版里作者写的原值继续生效，
  覆盖成「（未设置）」等于把作者的设定抹掉了。
- 二级只列**作者已启用**的条目——关掉的条目不参与 Prompt，
  让玩家填了也不生效，摆出来只会造成「填了没用」的困惑。
- 子字段列表从条目自身的 JSON 内容里读，**不硬编码**：
  作者可能改过结构，硬编码会与实际数据脱节。
- 纯文本条目（如「与用户关系」）没有三级，整条即目标。
- `card_entry` **自动归入玩家档案**，不需要作者再选一次注入位置。
- 显示名是「身体数据 · 种族」而非裸语义名，
  让模型理解它在设定体系里的位置。
- 聊天页取条目时**不过滤 enabled**：条目被关掉后玩家此前填的值仍在，
  显示名要能正常解析，否则退化成裸的内部 id。

数据链路：角色编辑页 `_entries` → UIAssemblyListPage → CharacterAssemblyPage
→ 数据通道表单（三级选择器）。

测试：`test/card_entry_target_test.dart`。

### A13-3 改版：配额分配（`pool_to_allocation`，已完成，测试通过）

求和方案上手后用户提出了更好的形态，已采纳为**首选方案**：

> 用一个固定总量作为数据源，其余组件连上后自动归零，
> 总分配量增加时总量组件显示的剩余数就减少。

**为什么这个更好**：它把「总量」放回了一个**实际存在的组件**上，
而不是散落在每条连线的参数里。作者看到的是「10 点可分配」这个实体，
拖滑块时它自己减少——不需要在脑子里做求和再对照。

**数据流向的合法性**（用户主动辩护，判断成立）：
源提供的是**可分配总数**（作者设定后固定不变），
显示剩余只是它的呈现方式，并非被目标改写——
就像进度条的 current 变化不代表它的 max 被改了。

| 维度 | 取值 |
|---|---|
| 来源（池） | text / progress / math_node |
| 目标（分配项） | slider / input |
| 参数 | 可分配总量、分配组件初始值、小数位、显示模板 |

#### 白名单的取舍标准（用户测试后收严）

初版两头都放宽了，其实两边各有一条硬标准：

**来源 = 玩家改不了的组件。** 总量一旦能被玩家自己拖动或输入，
配额约束就失去意义——因此 **slider / input 移出来源**（用户指出）。
`text` 最推荐（写「10」即 10 点，还能显示剩余数），
`progress` 适合做配额条，`math_node` 用于总量需要计算的场景。

**目标 = 玩家能操作的组件。** 配额约束是在玩家改值时生效的，
而 `progress` 没有任何手势、玩家改不了它的值，
放在这里纯属摆设——因此**移出目标**，并补上 `input`。

`input` 作分配项的两处适配：
- `poolUsedAmount` / `allocationCeilingFor` 的取值口径要覆盖
  `text` / `committedValue`，input 不存 `current`，
  否则统计恒为 0；
- 提交时按剩余额度**截断**而非拒绝：玩家输入 99 就给他能给的最大值，
  比整条丢弃、输入框莫名清空好理解。非数字与负数按 0 处理。

#### 关键实现细节

- **上限 = 剩余额度 + 自己已占用的部分**。加回自己是必须的：
  否则已分配 5 点的滑块想调到 6，会因「剩余只有 3」被卡在 3，
  等于只能往下调、调不回去。
- **归零用独立标记 `__poolInit`**，不能判断 `current == 0`：
  玩家可能确实分配了 0 点，每帧重置会让滑块拖不动。
- 分配组件**不走 `resolveTargetValue`**：它的值由玩家拖动决定，
  引擎只管归零与限额。
- `poolUsedAmount` 直接读目标的 `current`，
  不能走 `resolveTargetValue`——那会绕回本方案造成无限递归。
- 总量参数留 0 时**回退读取来源组件自身数值**，
  方便直接拿一个进度条当池子。
- 超额时上限收敛到 0 而非负数（兜旧数据）。

#### 首轮测试暴露的三个问题（均已修复）

**1. 总量只能在方案编辑器里填，text 的值用不上**
初版把 `total` 参数当作首选、组件自身数值当回退，方向反了。
作者摆一个写着「10」的文本当池子，改文本就该改总量——这才是直觉。

改为**优先读来源组件自身内容**：文本读 `text`（允许「10 点」这类
带单位写法，取第一个数字），数值组件读 `current` / `value`；
读不出数字才回退连线参数。`total` 参数降级为「备用」，默认 0。

> 注意：只读作者配置的**原始值**，不能读渲染后的显示串——
> 池文本渲染出来是「剩余 7」，拿它当总量会造成每帧递减的反馈循环。
> 有测试守着这一点。

**2. 剩余数不实时更新**
`initEventBusListener` 的匹配逻辑是 `srcId == event.sourceModuleId`，
而配额分配的数据流向**与众不同**——变化发生在**目标**
（玩家拖动分配滑块），要刷新的却是**源**（池子的剩余数）。
于是拖动分配项永远匹配不上，池子不刷新。

补一条前置分支：`scheme == 'pool_to_allocation' && tgtId == 事件源`
时直接标记需要刷新。

**3. 编辑态不归零，只有预览才归零**
`_buildSlider` 的 `isStudio` 分支在归零逻辑**之前**就 return 了。
作者连好线后画布上滑块仍停在旧位置，看起来像没生效。
编辑态分支补上同样的归零处理。

**4. 连上线池子就凭空少 50**
`poolUsedAmount` 累加的是各分配组件的 `current`，而 slider 模板
默认 `current = 50`。初版的归零只改了渲染时的显示值、没写回属性，
于是统计仍读到 50。

改为**在配置连线时归零**（`_zeroAllocationTarget`），
把 `current` 与 `committedValue` 一起写成初始值。

> 为什么不在渲染时写属性：那需要一个「是否已初始化」的持久标记，
> 而它会被 `_persistAssemblyElements` 存进角色卡，
> 既污染产物，又导致作者事后改初始值不再生效。
> **渲染函数应该只读不写**——这条对整个 UI 引擎都成立。

#### 黑名单需要为显式白名单方案放行

`text → slider` 在 `_blacklistMap` 里（通常是误连），
但这恰恰是本方案最主要的用法。
改为：黑名单只屏蔽**没有显式声明该目标白名单**的方案；
显式白名单视为作者已确认该通路合法。
有测试守着「黑名单对未声明白名单的方案依然生效」。

测试：`test/pool_allocation_test.dart`。

### A13-3 初版：数值求和汇总（保留，测试通过）

`sum_to_display` **不删除**——它解决的是另一类问题：
「多个数值汇总到一处显示」，与是否存在配额无关
（如统计总战力、合计花费）。配额分配请用 `pool_to_allocation`。


需求来源是「点数分配」（给定初始点数让玩家分配属性）。
但用户要求**做成通用聚合方案**而非配额专用容器：
「让文本或者数据条的数值与所连接的 slider 数值总数一致，
而且这个方案可以用在其他的数据组件的连接方案上」。

方案 id `sum_to_display`：

| 维度 | 取值 |
|---|---|
| 来源 | slider / progress / input / math_node / timer |
| 目标 | text / progress / slider |
| 参数 | 配额总量、超额策略、小数位、显示模板 |

模板占位符：`{{value}}` 汇总值、`{{total}}` 总量、`{{remain}}` 剩余。

#### 与其他方案的根本区别：同一目标可接多条

普通方案在 `resolveTargetValue` 里遍历到**第一条**匹配就 return
（按优先级取胜者），而聚合必须把连到同一目标的**所有**连线一起算。

因此单独走 `_resolveSumAggregate`，在主循环**之前**处理并直接返回。
这也意味着：一旦目标上有聚合连线，它会吃掉该目标的取值权
——这是有意的，混用聚合与普通赋值本身就是矛盾配置。
有测试守着「没有聚合连线时不影响普通方案」。

#### 两种超额策略（用户要求给创作选择）

- `allow`：允许超出，`{{remain}}` 显示为负数。
  作者自行决定怎么提示「超支」，比引擎硬拦更灵活。
- `clamp`：汇总值不超过总量。

#### 其他实现要点

- **配额参数只需在任一条连线上填写**：给每条都配一遍太繁琐，
  容易配漏配错。运行端取第一个填了的值。
- **数值型目标返回数字而非模板字符串**：
  progress / slider 收到「共 9 点」这种带单位的串会解析失败。
- 未设总量时 `{{remain}}` 为 0，不显示成负数。

#### 首轮测试暴露的两个问题（均已修复）

**1. 换个目标类型行为就变**（用户反馈「用不同的目标还效果不一样」）
初版给数值目标直接返回原始和，**跳过了 clamp**，且让 progress 用
自身 min/max 渲染。结果：同一份配置下 text 显示 `10/10`（clamp 生效），
progress 却按 13 去套自己的 max=100。

修法：数值目标走 `numericFor()`，与文本目标共用同一个已 clamp 的值，
并**把「配额总量」当作目标的满值**做等比换算——
作者填总量 10、已分配 7，进度条就该是 70%，
而不是拿 7 去套 max=100 变成 7%。

> 通用规则：**同一份方案配置换目标类型只能改变「呈现形式」，
> 不能改变「语义」。** 否则作者无法预期结果。

**2. 方案说明太抽象，不知道要连多条**
这是**第一个「同一目标可接多条」的方案**，用法与其余方案完全不同，
但卡片描述只写了一句抽象说明。作者只会连一条然后以为方案坏了。

修法：描述里直接给出操作步骤与完整示例；
参数区顶部加绿色提示条说明「这个方案要连多条」；
`total` 标注「多条连线中只需填一次」；
`template` 标注「仅文本目标」。

测试：`test/sum_aggregate_test.dart`。

### 待补的另一件事
1. ~~**结构化档案条目**~~ —— 已在 A13-2 完成，形态改为直接指向角色卡条目：
   ```
   [玩家档案]
   姓名：林
   职业：剑士
   力量 8 / 敏捷 6 / 智力 4
   ```
2. ~~**注入位置可选**~~ —— 已在 A13-1 完成。
3. ~~**点数分配玩法**~~ —— 已在 A13-3 完成，形态改为通用求和聚合方案。

### 形态决策（用户确认）
采用**结构化档案**：作者预先定义字段，玩家只填值。
不做自由文本——作者无法预知格式，注入质量不可控。

用户追问的「作者为玩家准备的额外补充设定字段」**仍属结构化档案**：
它只是某个字段的类型为长文本，字段本身依然由作者定义。
渲染成多行输入、注入时单独成段即可，不需要另设机制。

### 排期理由（A10 收口后）
- A10 未完成时插入跨模块改动，容易两边都乱。
- scene 大概率也需要写系统级设定（如切换场景后改变世界观描述）。
  等 opening 与 scene 的需求都清楚，抽象才不会歪——
  与「关键职责标记」同样的判断：一次做对好过做三次。
- 该功能涉及数据模型、注入链路、编辑器入口、配额约束，
  规模不亚于 A9.6，值得独立一步。

---

## A12：高级动画（未开始，排在 A14 之后）

### 示例
- 数值跳动
- 发光脉冲
- 粒子反馈
- 更高阶页面切换特效

> 明确属于锦上添花，不阻塞前面主流程完成。

### 为什么排在 A14 之后（用户确认）

动画参数（时长、曲线、幅度）需要配置入口，
而当前的通用实例编辑器已经塞不下了。
必须等 A14-3 把编辑器拆分到位，否则做出来也没法好好配。

### 已有基础 vs 全新机制

| 类别 | 现状 |
|---|---|
| Surface 按压 / 涟漪 | 已有方案在跑（`click_to_surface_press` / `_ripple`） |
| 页面切换动画 | A9 已做 `base_slide` + fade / 220ms |
| 数值跳动 | ❌ 全新 |
| 发光脉冲 | ❌ 全新 |
| 粒子反馈 | ❌ 全新 |

前两项是「增强」，后三项是「从零建」，实施时可分两批。

---

## 四、延后增强 / 灵感池

> 放这里的内容不是被否定，而是“确认有价值，但当前阶段不优先实现”。

### 4.1 可后台原子边缘吸附 / 拖出后台化
#### 设想
针对允许后台化的原子（未来原子资产库开放后）：
- 靠近 PCB 内壁时自动吸附在边界内侧
- 再继续往外拖超过第二阈值后，脱离吸附并切换为后台
- 避免组件长期停留在“半进半出”的尴尬状态

#### 建议机制
- 双阈值 / 滞回
  - 吸附阈值
  - 脱离阈值
- 轻微震动 / 边缘高亮 / 后台标签

#### 当前结论
- 创意保留
- 暂不进入当前步骤
- 适合在原子资产库与后台原子交互真正上线时实现

### 4.2 自动拖动换父级
#### 当前状态
- 已有阶段性实现：弹窗选择父层

#### 未来增强
- 树状拖放自动 reparent
- 拖放热点区 / 插入提示线 / 父层收纳区

#### 当前结论
- 延后到 A3 / A7 之后再做更合适

### 4.3 HUD 显示与交互方案测试中调整
- 图层面板样式
- 顶栏信息布局
- 端口提示样式
- 消息流窗口呈现方案
- scene / extra 的 HUD 视觉细节

#### 当前结论
- 可在测试中反复调
- 不影响核心骨架

### 4.4 统一几何坐标原则
#### 背景
Studio / Assembly 的端口、旋转、选中外框、连线吸附曾出现坐标不统一问题。

#### 开发原则
以后凡是涉及：
- 端口
- 旋转
- 外框
- 吸附点
- 命中区域

都尽量采用统一模型：
- 局部坐标
- 中心点
- 旋转变换
- 全局偏移

#### 当前结论
- 作为长期开发约定保留

### 4.5 Binding 状态块名称解析 / 预绑定机制
#### 背景
A3-4 已提供实例级 binding 挂载位，但当前 MVP 仍偏工程化：用户需要手动输入状态键。
对于普通创作者来说，内部 ID / key 学习成本过高；Binding 入口应优先面向“状态块名称”或“变量显示名”，由系统负责解析稳定 ID。

#### 体验目标
- 普通创作者在 Binding 弹窗中输入“好感度 / 心情 / 地点”等可读名称。
- 系统搜索当前角色卡已有状态栏字段：
  - 找到唯一匹配时，保存字段内部 `id`，并显示“已匹配状态块”。
  - 找到多个同名字段时，弹出候选列表让用户选择。
  - 找不到时，不阻止保存，而是保存为“预绑定名称”。
- 一旦成功绑定内部 `id`，后续状态块改名不影响绑定关系。
- 如果 UI 先于状态栏设计，可以先保存预绑定名称；后续进入状态栏编辑页新建字段时，系统提示可使用这些预绑定名称。

#### 建议数据结构方向
现有 `AssemblyBinding.statusKey` 可作为 MVP 兼容字段；后续建议升级为更明确的结构：

```text
targetKind: status_field | session_var
targetId: 已解析的状态栏字段 id / 会话变量 key
pendingName: 未解析时用户输入的预绑定名称
displayNameSnapshot: 绑定时的显示名快照
fieldType: string | number | bool
direction: none | upload_only | bidirectional
```

#### 状态栏编辑页联动
当状态栏编辑页新建状态块时：
- 名称输入框旁展示当前 UI 中尚未解析的预绑定名称。
- 用户点击某个预绑定名称后，自动填入该名称。
- 创建状态块并生成内部 id 后，系统可提示：
  - 将所有同名预绑定 UI 自动绑定到该状态块；或
  - 暂不处理。
- MVP 可先支持“全部绑定 / 暂不处理”，逐个选择后置。

#### 边界规则
- 状态块重名：禁止静默自动绑定，必须让用户选择。
- 已绑定状态块被删除：保留 `displayNameSnapshot`，提示“原状态块已删除，请重新绑定或转为预绑定”。
- 改名后显示：优先根据内部 id 显示最新名称，找不到时再显示快照。
- 普通模式隐藏内部 id；高级模式可折叠显示 / 手动输入内部 id 或变量 key。

#### 当前结论
- 方案确认保留。
- 不阻塞 A7 页面路由器最小版。
- 在真正接入状态栏 / SSOT / Prompt 通路前，应回头实现该机制，避免把内部 ID 暴露给普通创作者。

### 4.6 Assembly 资产库底栏 / 横向抽屉方案
#### 背景
当前 Assembly 资产库仍沿用左侧竖向抽屉，且资产内容只开放了页面路由器与复合组件。后续需要补齐逻辑组件、基础交互、基础显示与复合组件的统一入口。移动端上，底侧资产栏更适合拇指操作，也能给画布留出更完整的左右空间。

#### 初步方案
- 将资产库入口移动到屏幕底侧。
- 底侧固定显示分类标题栏：
  - 逻辑组件
  - 基础交互
  - 基础显示
  - 复合组件
- 点击某一分类后，从底部弹出横向资产抽屉。
- 抽屉内容横向排列，可左右滑动。
- 抽屉不能遮住顶部标题栏 / 顶部 HUD。
- 点击其他分类标题时，切换显示对应资产列表。
- 再次点击同一分类标题，或点击画布空白处，关闭抽屉。

#### 拖出生成交互调整
- 旧竖向抽屉：长按后以“水平位移超过阈值”判定生成组件。
- 新底部横向抽屉：长按后应改为以“竖直位移超过阈值”判定生成组件。
- 推荐规则：向上拖出超过阈值后，在画布生成组件；水平滑动仍用于浏览资产，不应误触发生成。

#### 与 HUD 的冲突
当前右下角信息 HUD 会与底部资产抽屉发生空间冲突，尤其包括：
- 模式标签
- 部件数量
- PCB 尺寸
- 越界计数
- 覆写计数

候选处理方式：
1. 资产抽屉展开时，右下角 HUD 自动上移到抽屉上方。
2. 资产抽屉展开时，右下角 HUD 临时折叠为小图标 / 小胶囊。
3. 将 HUD 合并到底栏右侧，底栏关闭时显示完整信息，打开时只显示关键异常信息。
4. 后续正式 HUD 设计阶段统一重做，当前仅保证不遮挡核心操作。

#### 当前结论
- 方案确认保留，适合作为 A7.5 / A5-0 的资产区改造候选。
- 不阻塞 A7 已完成测试。
- 在接入 `button → linker → page_router` 前，建议先做“资产区最小补全”，至少开放：
  - button
  - linker
  - page_router
- 页面路由器本体点击跳转只作为编辑态测试入口，后续应通过按钮 / linker 触发。

---

## 五、阻塞等级定义

### P0：立即阻塞，单独修复
- 编译错误
- 页面无法进入
- 数据无法保存 / 恢复
- 会破坏后续步骤数据结构的错误

### P1：当前步骤必须修
- 当前步骤核心功能不成立
- 当前步骤无法稳定测试
- 操作必现严重异常

### P2：并入下一步一起修
- 小交互瑕疵
- 局部视觉问题
- 非阻塞警告
- 阶段性实现可接受但需后补

### P3：记录到灵感池
- 明显有价值但当前阶段不急
- 需要跨步联动依赖完成后再做
- 更适合后期打磨的体验升级

---

## 六、当前建议的推进顺序

### 已完成基础
- A2 基础版
- A6 基础版
- A3-1 / A3-2 / A3-3 / A3-4 基础版
- A7 页面路由器最小版
- A7.5 / A5-0 Assembly 资产区最小补全

### A9.6 全链路联调结果（已通过）
实测确认以下环节全部打通：
- UI 交互 → SessionState 写入
- SessionState → Prompt 注入（含读写策略与隐藏字段红线）
- LLM 回复 → 解析 → 引擎算账（delta + clamp）
- 应用策略分流（confirm 弹卡片 / auto_low_risk 直接应用）
- 用户确认 → SessionState → 状态栏 UI 刷新
- 撤回消息 → 状态回滚（DB v4 消息级快照）

已知边界（非缺陷，属当前架构的固有特性）：
- 模型「主动要求修改」已稳定；「根据剧情自动判断变化」尚未系统性验证。
- 注入的是本轮开始时的快照，本轮变化在回复之后结算，
  因此同一轮内既要求修改又要求报数时，报的是修改前的值。
- 撤回升级前（DB v4 之前）产生的消息不会回滚，因其无状态快照。

#### A9.6-5：反向同步 SessionState → UI（已完成，待本地测试）
此前只有 UI → SessionState 单向，LLM 更新状态后 Assembly 里的
slider / progress 等组件不会跟着变（状态栏是独立渲染的，所以看起来在动）。

新增能力：
- `DataChannelService.readableTypes`：可显示会话数值的类型，
  比可写类型多了 `progress` 与 `text`——它们不作输入源但适合展示状态。
- `applyValueToModule()`：把值写回组件属性，与 `readModuleValue()` 互为逆操作。
  - slider / progress 按组件自身 `min`/`max` clamp，不会推出轨道。
  - switch 识别 `true` / `1` / `开启` 多种真值写法。
  - 非数值写入数值组件时忽略，不破坏原值。
  - 值未变化时返回 false，避免无谓重建。
- `applySessionToElements()`：遍历元素树（含复合子元素与暴露项覆写通道）回填。
  - 只回填 `session_var` / `status_field`；`local_ui_state` 无外部数据源，跳过。
  - 状态字段仍是 pendingName（未匹配）时跳过。
  - 会话里没有该键时保持组件原值，不清空成空串。

触发时机（`UIAssemblyRuntimeView`）：
- `initState`：先回填再建联动，保证首帧显示真实状态而非模板默认值。
- `didUpdateWidget`：外部 `sessionState` 被替换时（LLM 更新、撤回回滚）刷新界面。

测试：`applyValueToModule` 与 `readModuleValue` 的**往返一致性**有专门用例覆盖
（六种类型逐一验证写进去的和读出来的是同一个值），
避免两个方向取值口径不一致导致静默丢值。

**当前生效范围（重要）**：
反向同步目前只在 **Assembly 编辑器的运行时预览**里生效。
排查后确认：`UIAssemblyRuntimeView` 全项目仅有一处调用
（`character_assembly_page.dart` 的预览），**聊天页尚未渲染任何 Assembly UI**。
聊天页只使用 `uiAssemblies` 读取数据通道配置来注入 Prompt。

因此「LLM 更新状态后聊天页里的 UI 组件实时刷新」这个效果，
缺的不是参数接线，而是「在聊天页挂载 Assembly UI」这块功能本身——
它属于 A10 的范围（各 mode 的挂载位置与形态差异）。
反向同步的能力已就绪且有单测，A10 挂载完成后接上 `sessionState`
与 `onSessionStateChanged` 即可直接生效。

修复：状态栏编辑页改了上限却存不进去
- 现象：新建字段时把初始值设成大于 100 的数，即使同时调高最大值，
  保存后再进编辑页仍是旧值。
- 根因（与「100」无关，是编辑丢失）：`_buildFieldCard(i)` 在 build 时捕获了
  `final f = _fields[i]`，而各输入框的 onChanged 走了两条不同路径——
  - 初始值 / 名称：`_fields[i] = f.copyWith(...)` → 生成**新对象**
  - 最小值 / 最大值：`_fields[i].minValue = ...` → 直接改**旧对象** `f`
  一旦先改了初始值，`_fields[i]` 已换成新对象，此后对 `f` 的写入全部丢失。
  新建字段默认 max 恰好是 100，所以只有需要调高上限时才暴露。
- 处理：
  - 四处 onChanged 统一改为基于 `_fields[i]` 的最新对象做 `copyWith`，
    不再使用闭包捕获的 `f`，也不再直接改字段。
  - `StatusBarField.copyWith` 增加 `clearMinValue` / `clearMaxValue`：
    仅靠 `minValue: null` 无法与「不修改」区分，清空上下限需要显式标记。
  - `ListView.builder` 的 item 补 `ValueKey(field.id)`：
    此前没有 key，增删字段会让 `TextFormField` 的 State 错位复用，
    输入内容可能串到别的字段上。
- 测试：`test/status_bar_field_test.dart` 覆盖链式编辑不互相覆盖、
  上限可改到远大于默认值、以及 clear 标记的清空语义。

审查：状态栏编辑页系统性排查（发现 3 个真 bug + 1 个非缺陷）
用户反馈「文本字段有时存不上」「字段有时只能建 2~4 个」「有时又正常」。
「有时正常」是关键线索——指向状态相关的偶发问题，逐一定位如下。

**Bug 1：返回键丢弃全部编辑（最主要原因）**
- `AppBar` 只有右上角保存按钮，未拦截返回。用系统返回键或返回箭头退出时
  `Navigator.pop()` 返回 null，父页 `if (result != null)` 不成立，
  于是全部编辑被静默丢弃，且无任何提示。
- 这解释了「有时好有时坏」：点保存就正常，按返回就全丢。
- 修复：`PopScope` 拦截返回，有未保存修改时弹三选一
  （继续编辑 / 放弃修改 / 去保存）；无修改则直接放行。
  新增 `_isDirty` 逐字段比对判断是否有改动。

**Bug 2：无名称字段被静默丢弃（对应「文本字段存不上」）**
- `_save()` 用 `if (f.name.trim().isEmpty) continue;` 过滤，
  但不给任何提示。用户先改类型、填了初始值却忘填名称时，
  保存后该字段消失，看起来就是「存不上」。
- 修复：保存前检测「有内容但无名称」的字段并弹确认，
  提示这些字段不会被保存，可选择返回填写。

**Bug 3：id 冲突导致加不进字段（对应「只能建 2~4 个」）**
- `_newId()` 仅用 `microsecondsSinceEpoch`。连续快速点击「添加字段」
  可能落在同一微秒，产生重复 id。而列表用 `ValueKey(field.id)` 作 key，
  重复 key 会让 Flutter 抛错或 State 错乱，表现为字段加不进去。
- 点击慢时不触发，这是「有时又没问题」的另一个来源。
- 修复：id 改为「时间戳 + 自增序号」，并与现有 id 查重后才使用。

**非缺陷：聊天页固定显示上限**
- `_statusPinnedMax = 3` 限制的是**长条上每侧固定显示的数量**（左右各 3），
  属于展示层设计，不限制字段创建数量。若用户观察到的「2~4 个」
  是指长条显示，则符合预期。

修复：LLM 无法判断数值增减方向（商贩测试暴露）
- 现象：初始金钱 8000，玩家花 600 买戒指后变成 **8600** 而非 7400。
- 定位：8000 + 600 = 8600，符号反了。模型输出了 `金钱数量:+600`，
  它站在商贩视角认为「我收了 600」。
- 这次测试同时验证了三件好事：模型**主动**输出标签块、
  **自动判断**出成交该结算、金额精确等于售价——链路与判断力都正常，
  唯一错的是方向。
- 根因：字段名「金钱数量」**没有主语**。角色设定是商人，
  模型自然理解成自己的收入。这不是模型的错——该字段名本身无法判断归属。
  好感度也有同样隐患，只是它通常只增不减，方向错了不易被发现。
- 处理（架构层，所有字段受益）：
  - `StatusBarField` 新增 `owner`：`player` / `char` / `neutral`，默认 `player`；
    旧卡片与非法值都回落为 `player`，向后兼容。
  - 新增 `qualifiedName`：按归属加主语（「玩家的金钱数量」/「你的钱包」），
    中立字段不加主语，避免「环境的时间」这种别扭表述。
  - Prompt 注入的**显示文字**使用 `qualifiedName`；
    但**标签里的键必须保持原始 `name`**——`applyFromReply` 按 name 匹配，
    改成带主语会导致解析全部失效。有专门回归用例守这一点。
  - PHI 增加方向判定规则：以归属方为准，玩家付出/消耗时用负号。
  - 状态栏编辑页增加「归属」下拉，并说明它会影响 AI 的增减判断。
- 关于角色自身属性：作者若想让角色也有钱包，自行再建一个 `char` 归属的字段即可。
  归属是每个字段独立的属性，不是全局设定。

## A10：mode 差异逻辑收口（进行中）

A9.6 全链路联调通过后，六条进入条件已全部满足，正式启动 A10。

### 分步计划
先做共性基础设施，再逐个补形态差异。不四种并行——挂载点、
sessionState 双向绑定、生命周期、性能这些是共用的，趟通一次即可。

```
A10-0  PCB 尺寸差异化          ← 已完成，测试通过
A10-1  聊天页挂载基础设施（共性）← 已完成，测试通过
A10-2  extra_sticky（含折叠悬浮球）← 已完成，测试通过
A10-3  extra_companion（消息下挂 + 滚动跟随）← 已完成，测试通过
A10-4  opening（全屏 + 确认销毁）← 已完成，测试通过
A10-5  scene（全屏接管）← 已完成，测试通过
```

选 sticky 打头阵的理由：位置固定不涉及滚动同步、不接管聊天页、
常驻可见便于观察反向同步是否实时生效。scene 放最后——
它要处理输入框、消息流、退出方式，独立问题最多。

#### A10-0：PCB 尺寸差异化（已完成，待本地测试）
必须排在挂载之前：先定画布尺寸，作者才能按正确比例摆元件；
反过来做会导致所有已摆好的常驻 UI 返工。

原先宽度硬编码 360（`_defaultPcbSize` / `designWidth` 两处常量，
且 `UIAssemblyInfo` 只存 `pcbHeight` 没有宽度），
常驻悬浮窗按全屏宽度起步不合理。

- `UIAssemblyInfo` 新增 `pcbWidth`，参与序列化；
  缺失时回落 `defaultPcbWidth`（360）。
- 新增 `defaultPcbSizeFor(mode)` 按 mode 给默认画布：
  - `extra_sticky` 300×120（悬浮窗，小而扁）
  - `extra_companion` 320×200（宽度接近气泡）
  - `opening` / `scene` 360×800（全屏维持原样）
- 尺寸范围放宽为 120~600（宽）/ 64~2000（高），由作者自行决定；
  超出屏宽时运行时等比缩小兜底，不会溢出。
- 编辑器新增**右侧宽度手柄**（原先只有底部高度手柄），
  拖动即时生效并随元素一起持久化。
- `UIAssemblyRuntimeView` 的 `designWidth` 由常量改为读 `pcbWidth`，
  调试浮层同步显示实际设计尺寸。
- 测试：`test/ui_assembly_pcb_size_test.dart` 覆盖各 mode 默认值、
  序列化往返、字段缺失回落、以及默认值都落在允许范围内。

注：按用户决定，开发阶段不考虑旧数据迁移，已有 UI 可删除重建。

#### A10-1：聊天页挂载基础设施（已完成，测试通过）
新增 `lib/widgets/chat_assembly_mount.dart`。各 mode 的差异只在
「挂在哪、长什么样」，以下部分是共用的，先一次做好：
- `resolveAssembly(meta, mode)`：从角色卡取出该 mode 的 UI 方案。
  - 损坏 JSON 跳过而不是崩溃。
  - **空方案不挂载**（页面与旧版元素都为空），否则聊天页会多出一块空白。
- `hasAssembly()` / `assemblyDesignSize()`：供调用方判断与预留布局空间。
- `ChatAssemblyMount` widget：接好 `sessionState` / `statusFields` /
  `onSessionStateChanged`，并按 PCB 设计尺寸预留空间，
  宽度不足时等比缩小（不拉伸）。
- `chat_page` 新增 `_onAssemblySessionChanged()`：
  玩家操作 UI 导致会话副本变化时统一落盘并刷新。

至此 A9.6-5 的反向同步在真实会话里生效：
LLM 更新状态 → SessionState → UI 组件显示同步刷新。

#### A10-2：extra_sticky 常驻 UI（已完成，测试通过）
- 挂载位置：状态栏正下方，与状态栏同处一个 `Column`，
  随状态栏展开一起下移，不会互相遮挡。
- 可折叠为右上角悬浮球，点击球恢复。
  折叠只影响显示，**不卸载运行时**——卸载会丢失组件内部状态。
- 宽度上限为屏宽减 16（两侧留白），超出由运行时等比缩小。
- 未配置常驻 UI 的角色卡不显示任何东西，也不占位。

测试：`test/chat_assembly_mount_test.dart` 覆盖 mode 匹配、空方案跳过、
损坏数据容错、尺寸 clamp。

##### A10-2 反馈修复（已修复，测试通过）
1. **挂件吃掉了内部组件的手势**
   - 现象：常驻 UI 里的 slider 只能点击跳转，拖不动。
   - 根因：`UIAssemblyRuntimeView` 有一层 `Positioned.fill` 的 `Listener`，
     `behavior: translucent` 让它持续参与命中测试，抢走了内部组件的拖动。
     该层的用途是整页滑动手势（切换平级页 / 打开叠加页）。
   - 处理：新增 `enablePageGestures` 开关，`ChatAssemblyMount` 默认 **false**。
     关闭时该 `Listener` 改用 `deferToChild` 且不注册 `onPointerDown`，
     不再拦截内部手势。挂件通常只有一页，页面手势本就没有意义
     （与用户「常驻 UI 去掉手势切换页」的判断一致）。
   - 附注：slider **本来就支持拖动**（`onPanStart/Update/End` 一直都在），
     `onTapDown` 跳到点击位置是刻意设计，与系统滑块行为一致，予以保留。
2. **常驻 UI 不可拖动**
   - 左上角新增拖动把手（与右上角折叠按钮分开）。
     只有把手能拖动整个挂件——直接拖内容会与内部 slider 冲突。
   - 双击把手复位。
   - 偏移只存在于本次会话，不写进角色卡：位置属于临时观感。
   - 手势归属见下一条修复（初版判断有误）。

##### A10-2 反馈修复 · 第二轮（已修复，测试通过）
1. **拖动一次后整个挂件失去交互**
   - 根因：`Transform.translate` 只做**视觉**位移，命中测试仍受父容器
     边界裁剪。挂件原先塞在状态栏的 `Positioned(top:8,left:6,right:6)` 里，
     一旦被拖出那条窄区域，触摸就落在父容器之外，全部失效。
   - 处理：常驻 UI 独立成层（`Positioned.fill` + 内部 `Stack`），
     在整个聊天区都能接收触摸。
   - 注意不能给这层包 `IgnorePointer`：它铺满聊天区，
     包了会挡住下方消息列表滚动。`Stack` 默认只在子组件实际占位处命中，
     空白区域自然穿透。
   - 代价：挂件不再随状态栏展开自动下移，由用户自行拖开。
2. **slider 始终拖不动（与挂件是否被拖动无关）**
   - 根因（上一轮判断错误，此处更正）：聊天页根部有
     `onHorizontalDrag*` 用于滑出侧栏。手势竞技场中
     **专用识别器（HorizontalDrag）优先于通用识别器（Pan）**，
     水平移动达阈值时 HorizontalDrag 立即宣告胜利，而 Pan 仍在
     等待方向判定，于是父级总是抢走手势。**与嵌套深浅无关**——
     上一轮「层级更深会赢」的说法是错的。
   - 处理：slider 改用 `RawGestureDetector` 显式声明
     `HorizontalDragGestureRecognizer`。同为专用识别器时，
     命中路径更深的子节点优先，slider 得以胜出。
     `TapGestureRecognizer` 保留，点击轨道跳转的行为不变。
   - 挂件的拖动把手同理改用 `RawGestureDetector` + `PanGestureRecognizer`，
     否则也会被根部的水平拖动抢走。
   - 编译修正：`GestureRecognizerFactoryWithHandlers` 的初始化回调里
     **不能用箭头体 + 级联**。
     - `updatePosition` / `commitValue` 返回 `void`，
       `..onStart = (d) => updatePosition(...)` 会报「使用 void 值」。
     - `..onStart = (d) => _stickyDragStart = d.globalPosition` 更隐蔽：
       箭头体返回 `Offset`，后续 `..onUpdate` 会级联到 `Offset` 上，
       报「onUpdate isn't defined for Offset」。
     - 统一改为 `instance.onXxx = (d) { ... };` 块体逐条赋值。

##### A10-2 反馈修复 · 第三轮（已修复，测试通过）
用户描述极准确：「感觉只是拖动了它的样貌，而没有拖走它的可交互区域」。
1. **拖动后交互区不跟随（第二轮的修复不彻底）**
   - 根因：`Transform.translate` 只移动**绘制**与自身内部的命中坐标，
     外层布局盒子仍留在原处。而命中测试是**自上而下**的——
     父容器先判断触摸点在不在自己的盒子里，不在就根本不往下传。
     所以挂件被拖到别处后，那里的触摸压根到不了它。
   - 第二轮虽然把挂件提为独立层，但仍用 Transform 做位移，
     盒子依然停在 `top: _stickyTopAnchor` 处，问题只是范围变大了没根治。
   - 处理：**彻底弃用 Transform**，改为直接驱动 `Positioned` 的
     `left` / `top` 真实坐标，布局盒子与视觉一起移动。
2. **在挂件上右滑会触发滑出编辑页**
   - 根因：`enablePageGestures: false` 让挂件不再拦截手势后，
     水平滑动一路穿透到聊天页根部的 `onHorizontalDrag*`（滑出侧栏）。
   - 处理：给挂件外层套一个只吸收水平拖动的 `GestureDetector`
     （与状态栏同样的做法）。根部因此收不到；
     而挂件内部的 slider 层级更深，仍能在竞技场中赢过这层吸收器。

##### A10-2 反馈修复 · 第四轮（已修复，测试通过）
1. **折叠 / 拖动按钮离挂件很远**
   - 根因：挂载层的 `Positioned` 给了 `width: screenWidth`（用于确定水平基准），
     导致内部 `Stack` 被撑满整屏，而两个按钮用 `top:-6 / left:-6 / right:-6`
     定位在 Stack 的角上——于是被拉到了整屏的边角。
   - 处理：`Positioned` 内部加 `Align(alignment: topCenter)` 收缩到挂件自身宽度，
     Stack 重新贴合挂件，按钮回到它的四角。
2. **slider 仍只能点击不能拖动**
   - 关键线索：**点击有效说明触摸确实到达了 slider**，
     因此不是命中测试问题，而是水平拖动的竞技场竞争失败。
   - 根因：竞争者有三层——聊天页根部（滑出侧栏）、挂件的水平拖动吸收器、
     slider 自身。三者都是 `HorizontalDrag`，
     单靠「层级更深」并不能保证 slider 稳定胜出。
   - 处理：新增 `_EagerHorizontalDragRecognizer`，
     在 `addAllowedPointer` 阶段立即 `resolve(accepted)` 抢先关闭竞技场。
     滑块本来就该独占自己区域内的水平拖动，这是安全的。
   - 点击不受影响：`Tap` 与 `HorizontalDrag` 是不同类型识别器，
     各自独立判定。按下不动时位移未超 slop，`onStart` 不触发，
     `Tap` 正常回调；水平移动时 `Tap` 自动取消、拖动接管。
   - 注：不直接在工厂回调里调 `instance.resolve()`——那是 protected 成员，
     应当通过子类覆写实现。

#### A10-2 增强：折叠悬浮球交互（已完成，测试通过）
- **自由拖动 + 实时吸边**：松手立即吸附到最近一侧，
  不会停在屏幕中间（此前折叠时球会直接生成在中间）。
  纵向限制在状态栏下方到输入栏上方之间。
- **停靠 3 秒后缩进**：向屏幕外偏移半个球宽（露出一半），
  透明度降到 0.45，减少对聊天内容的干扰。拖动期间不缩进。
- **两段式点击**：缩进态点击先「冒出来」恢复完整显示，
  再点一次才展开 UI。冒出后重新计时，3 秒无操作再次缩进。
- **展开位置跟随球**：`_stickyOffsetForBall()` 按球所在象限选择方向——
  球在左半屏则挂件左对齐、右半屏则右对齐；
  下方空间不足时改为向上展开。已验算四种极端位置均不会超出屏幕。

设计取舍记录：
- 两段式点击的风险是「点了没反应」的错觉，因此冒出必须有明显动画反馈
  （`AnimatedOpacity` + 位移）。若实测仍觉得别扭，可退回「点击即展开」。
- 展开位置选择跟随球而非回到默认位置，保证操作的空间连续性。

##### 悬浮球 / 把手拖动跟手度修复（已完成，测试通过）
- 现象：拖动「有时没反应、有时可以」，且要先拖一段距离才触发。
- 根因（两个症状同源）：
  - 默认 `PanGestureRecognizer` 要移动超过 `kTouchSlop`（18px）才确认手势，
    起手位移被吞掉 → 不跟手。
  - 外层的 `HorizontalDragGestureRecognizer`（滑出侧栏、挂件吸收器）
    同样在 18px 判定，两者几乎同时到达阈值；
    而专用识别器优先于通用 Pan，外层常常先赢 → 时灵时不灵。
- 处理：新增 `_EagerPanRecognizer`，把自身判定阈值降到 **6px**，
  抢在外层的 18px 之前拿下竞技场。把手与悬浮球都改用它。
- **关键取舍**：没有在 `addAllowedPointer` 里直接 `resolve(accepted)`。
  那样虽然更彻底，但会立刻淘汰同竞技场的 `TapGestureRecognizer`，
  悬浮球的「点击展开」将永久失效。
  保留阈值判定后：静止 → Tap 获胜；移动超 6px → 拖动获胜，两者共存。
  （slider 那处可以用抢占式，是因为它内部没有需要并存的点击-展开语义，
  且其 Tap 与 Drag 分属不同竞技场。）

#### A10-2.5：组件关键职责标记（已完成，测试通过）
A10-4 的「确认后关闭」与 A10-5 的「打开聊天设置」都需要作者指定
哪个按钮承担该职责。三处各做一次不如先做一套通用能力，故提前到此。

新增 `lib/services/ui_engine/ui_semantic_role.dart`。

核心设计（按用户意见定稿）：
- **一种 mode 只有一个关键职责**，因此作者不从列表里挑角色，
  只在按钮编辑页点亮一个标签（是 / 否）。
  初版做成「所有 UI 共用一组语义角色下拉」是过度设计，已废弃。
- 标记含义由所在 UI 的 mode 决定，同一个 `keyAction` 值：
  - opening → 确认并关闭
  - scene → 打开聊天设置
  - extra_sticky → 折叠界面
  - extra_companion → 无要求（嵌在消息流里，没有需要主动退出的状态）
- 不新增专用组件类型；标记存 `module.properties['keyAction']`，
  随实例保存，不回写资产库模板。

强制策略（按 mode 分级，用户决定）：

| mode | 需标记 | 缺则拦截 | 缺标记时的表现 |
|------|--------|----------|----------------|
| opening | 是 | 是 | 不执行该 UI |
| scene | 是 | 是 | 不执行该 UI |
| extra_sticky | 是 | 否 | 正常运行 + 内置按钮兜底 |
| extra_companion | 否 | 否 | 无要求 |

- opening / scene 会接管界面，缺出口按钮会把玩家**卡死**，必须拦截。
- 常驻 UI 缺折叠按钮只是少一个功能，界面本身仍可用，
  直接不显示反而更糟，因此保留内置兜底按钮。

编辑器交互：
- 按钮实例编辑页的**标题栏右侧**放一个标签，点击点亮／熄灭，
  点亮后配色与所属 UI 模式一致（opening 紫、scene 青、常驻深紫）。
- 仅对 `button` 且该 mode 需要标记时才显示，避免无关组件出现该入口。
- 画布上给已标记组件打小徽标，作者一眼看出哪个按钮承担了职责。
- 缺标记提示是与顶部参数栏**并排的独立橙色胶囊**（不是塞进参数栏内）。
  混在参数里会被当成又一个数值读数而被忽略，独立成块才够醒目；
  但仍不弹窗、不遮挡画布——作者常常先摆界面、后补功能。
  实现上两者放进同一个 `Row`，各用 `Flexible` 分配宽度；
  为此移除了参数栏自身的 `maxWidth` 约束，否则它会独占全宽把警告挤出屏幕。
- 提示语用大白话讲后果，不用术语：
  「还没有指定折叠按钮，玩家将无法收起这个界面。」

运行时接线：
- `UIAssemblyRuntimeView` 新增 `onDismissRequested`，
  复用 button 已有的 `tap` 脉冲识别标记，**不改渲染器**——
  被标记的按钮仍可正常参与 linker 等既有配置。
- `ChatAssemblyMount.canRun()` 对接管型 mode 做准入判断。

顺带修复：HUD 里的 PCB 尺寸此前硬编码显示 360，现已改为实际宽度。

测试：`test/ui_semantic_role_test.dart` 覆盖标记读写、各 mode 的职责定义、
拦截分级、提示语措辞、配色区分、复合组件内部查找。

#### A10-4：opening 开场白 UI（已完成，测试通过）
全屏覆盖在聊天之上，玩家确认后销毁，本轮会话不再出现。

与既有「开场白消息」的关系：那是一条 assistant 消息（`openingGreetings`），
这是一层可交互界面，两者互不影响，可以并存。

一次性状态：
- 存在 `SessionState.overrides['openingUIDismissed']`，
  不单独建表。理由：
  - 随会话副本一起持久化，重启 App 不会重复弹出；
  - 清空聊天记录时一并清除，开场白重新出现——
    这与「开场白属于本轮会话的开端」的语义一致，无需额外代码。
- `markDismissed()` 在已标记时返回 false，避免无谓落盘。

生命周期：

| 操作 | 结果 |
|------|------|
| 首次进入聊天 | 显示 |
| 点作者的确认按钮 | 关闭并落盘 |
| 退出重进 / 重启 App | 不再显示 |
| 清空聊天记录 | 重新显示 |

交互细节：
- 遮罩吸收所有点击，玩家在确认前无法操作下方聊天。
- **点遮罩不关闭**——必须走作者指定的确认按钮，避免误触跳过开场白。
- 挂在主 Stack 最末尾，层级高于输入栏（它要接管整个界面）。
- 保留页面手势（`enablePageGestures: true`），支持多页开场白翻页。

准入拦截：
- 作者未标记「确认并关闭」时 `canRun` 为 false，**连遮罩都不铺**。
  若只让 `ChatAssemblyMount` 渲染成空而遮罩仍在，
  会出现一块点不掉的黑幕把玩家卡死。

测试：`test/chat_assembly_mount_test.dart` 新增一次性状态与准入用例。

##### 修复：关闭开场白后聊天页黑屏（已修复，测试通过）
- 现象：点确认按钮关闭 opening 后整个聊天页变黑，内容全部消失。
- 根因：`_buildOpeningAssembly` 是主 `Stack` 的直接子节点，
  显示时返回 `Positioned.fill`，关闭后却返回裸的 `SizedBox.shrink()`。
  **`Stack` 的尺寸由「非定位子组件」决定**——主 Stack 里其余子节点
  全是 `Positioned`（不参与尺寸计算），于是那个 0×0 的 `SizedBox`
  成了唯一的非定位子组件，整个 Stack 塌缩成 0×0，所有内容被裁掉。
- 处理：**始终返回 `Positioned.fill`**，隐藏时返回
  `Positioned.fill(child: IgnorePointer(child: SizedBox()))`，
  显示与否由内部条件决定。判断逻辑抽为 `_shouldShowOpeningAssembly`。
- 教训：作为 `Stack` 直接子节点的条件渲染，
  要么用 `if (cond) Positioned(...)` 完全不加入 children，
  要么**始终返回同一种布局语义**；
  绝不能在「Positioned」与「裸 widget」之间切换。
  （常驻 UI 那层用的是前一种写法，因此不受影响。）

#### A5 补完：Assembly 联动器接入完整方案矩阵（已完成，测试通过）
此前 Assembly 的 linker 只硬编码了 `button → page_router` 一条通路
（A5 阶段的测试级实现），导致大量组合无法配置。最直接的后果：
**button 本身不显形**，必须联动 surface 才能做出按下反馈，而这条路走不通。

排查发现：**运行端引擎其实已经完整支持所有方案**
（`LinkerService` 里 `click_to_surface_press`、`click_to_switch_toggle`
等分支一应俱全），缺的只是 Assembly 的配置入口。因此本次是接线而非重写。

改动：
- 配置对话框改为通用形态：来源 / 目标可选画布上任意非 linker 组件，
  选定后调用 `LinkerMatrixEngine.getAvailableSchemes()` 列出可用方案，
  **与 Studio 共用同一份矩阵**，两边能选到的方案完全一致。
- 方案以卡片列表呈现（含名称与用途说明），替代原先无选择余地的固定文案。
- 换源 / 换目标后若旧方案不再适用，自动清空选择，避免存下非法组合。

端口推导：
- Studio 的端口来自拖拽连线落点，Assembly 没有连线交互，
  改为由方案 id 推导（`_schemeSourcePort` / `_schemeTargetPort`）。
- 运行端实际是按 `scheme` 分发行为的，端口只需自洽；
  但仍按语义推导，便于调试与后续接入端口拖拽。
- 两处易错点已单独处理：
  - `*_to_surface_visible` 走 `visible` 而非 `anim`（前者改可见性，后者放动画）。
  - 提交类方案（`input_submit_*` / `slider_commit_*`）取 `committedValue`
    而非实时值——实时值会在输入过程中反复触发，语义不同。

顺带修复：`button_to_page_route` **此前未登记在方案矩阵里**。
它是 Assembly 专属（Studio 没有多页面概念），但 `isSchemeSelectable()`
会把未登记的方案判为非法并让运行端直接跳过。改用通用矩阵后，
不补登记会导致页面跳转彻底失效。现已补入注册表。

**制作与预览严格分离**（用户决策，已撤销中途的便利改动）：
- 一度让编辑态点击 button 直接 `emit('tap')`，好处是画布上就能看到
  surface 按压等效果，不必进预览。但代价更大——
  编辑时的点击 / 拖动极易误触发，而组件状态（switch 开合、slider 数值、
  surface 动画时间戳）会被 `_persistAssemblyElements` 一并存盘，
  污染最终产物。
- 现已彻底移除编辑态的联动执行，**包括原有的页面跳转**：
  - 单击 button → 只弹提示，不执行任何效果。
  - 切页改用图层面板（那里本来就能选页）。
  - 所有效果统一在运行时预览中验证。
- 随之删除了仅供编辑态执行使用的 `_executePageRouter`、
  `_isPageRouteLinker` 与 `_pageRouteLinkerScheme`。
  方案本身仍登记在矩阵里——运行端需要它。

暂缓：连线动画与端口拖拽交互（用户同意先搁置），当前用下拉选择。

测试：`test/assembly_linker_scheme_test.dart` 覆盖方案矩阵可用性
（含 button→surface 这条动因用例）、端口推导规则、页面路由登记。

#### A10-2 复盘：手势与命中测试的四轮排查
这一步返工四次，值得记录教训——四个现象其实是**四个不同的根因**，
每次只修掉一个，剩下的继续掩盖真相：

| 现象 | 根因 | 修法 |
|------|------|------|
| slider 只能点不能拖 | 运行时全屏 `Listener` 用 translucent 持续命中，抢走内部手势 | `enablePageGestures=false`，挂件不吃页面手势 |
| 拖动后整块失去交互 | `Transform.translate` 只移动绘制，布局盒子留在原处 | 改为驱动 `Positioned` 真实坐标 |
| 在挂件上右滑触发编辑页 | 不拦截手势后穿透到根部的滑出侧栏 | 挂件外层套水平拖动吸收器 |
| slider 仍拖不动 | 三层都注册 `HorizontalDrag`，层级深不保证胜出 | `_EagerHorizontalDragRecognizer` 抢占式 accept |

关键判断依据（下次可直接套用）：
- **点击有效但拖动无效** → 触摸到达了，是竞技场竞争失败，别再调层级。
- **完全点不到** → 命中测试问题，查父容器边界与 `Transform`。
- 我在第二轮误判「层级更深会赢」，事实是：
  专用识别器优先于通用识别器；同类型之间靠层级，但不保证稳定胜出。

### 下一步候选
- A10 mode 差异逻辑收口（其中包含聊天页挂载 Assembly UI，
  完成后反向同步可立即接上，见 A9.6-5 的「当前生效范围」）
- 「根据剧情自动判断状态变化」的效果验证与阈值调优
  （需先固定一组剧情样本，否则结果不可复现）

---

## 七、临时测试工具与调试信息清理规则

> 目的：避免“为了开发可见性临时加入的小工具”长期遗留在正式成品里。

### 7.1 可以暂时保留的调试信息
- 当前阶段用户看不到底层结构变化时，用于辅助测试的计数器
- 数据容器是否接入成功的轻量可视反馈
- 仅对当前步骤验证有价值的状态标签

### 7.2 默认退场时机
以下任一条件满足时，应评估删除：
1. 已经有正式 UI 能表达同一信息
2. 当前阶段结束，下一阶段不再依赖它做验证
3. 对最终用户没有直接价值，只会增加界面负担

### 7.3 当前已登记的临时工具
- 右下角的 `覆写 N 项`
  - 用途：A3-1 / A3-2 / A3-3 阶段验证实例覆写容器是否接通
  - 建议删除评估时机：**A3-4 覆写持久化与入口稳定后**
- 复合件选中态的 `实例黑盒` 标签
  - 用途：A3-2 阶段强化黑盒语义，帮助测试“当前选中的是实例而不是模板内部结构”
  - 建议删除评估时机：**A3-4 完成后**，若正式 UI 已足够表达黑盒语义，则可删除或弱化

---

## 八、简短执行口令（给后续协作用）

当继续开发时，优先按以下问题问自己：
1. 这是不是当前步骤的 MVP 必需项？
2. 这是不是阻塞后续步骤的数据结构问题？
3. 这是 P0 / P1，还是其实只是 P2 / P3？
4. 能否先用阶段性实现保证节奏，再在增强阶段补完？
5. 这个临时调试信息在当前步骤之后是否还需要存在？

---

> 这份档案不是替代设计稿，而是把设计稿转成“可施工、可追踪、可延后、可裁剪”的执行地图。