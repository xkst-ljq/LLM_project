# 转译工具 · UI 生成与引擎移植 施工计划

> 本文档对标 `ASSEMBLY_IMPLEMENTATION_TRACKER.md` 的形态：
> 记录**为什么这么做**、**已确认的约束**、**分步施工顺序**、**每步的验收标准**。
>
> 适用范围：`ToolofPC/llm_card_converter`（PC 端转译工作台）。
>
> 状态图例：`⬜ 未开始` / `🟡 进行中` / `✅ 已完成` / `❌ 已废弃`

---

## 一、目标与背景

### 1.1 用户原话（需求源头，不要曲解）

> 酒馆作为 web 端应用，可以支持气泡渲染一些高级语言的 UI，
> 我就是想让转译 AI 识别卡片里面的高级语言，明白其渲染出来大抵是什么样子的，
> 再做成 UI，如果是在角色后面跟着的一些状态栏，就改成我们设计的状态栏。
> **原版就没有的当然就不去设计。**

> 我想将 UIengine 移植的主要原因是可以做一个 AI 来帮我设计 UI 甚至带有 UI 的角色卡。
> 而且转译好的 UI 也好预览查看效果。

### 1.2 这不是「按模板生成 UI」

一个必须先厘清的区别——两种做法的性质完全不同：

| | 凭空生成（❌ 不采用） | 语义迁移（✅ 本方案） |
|---|---|---|
| AI 的任务 | 「这张卡该配什么 UI」 | 「原卡这段 HTML 渲染出来是什么样」 |
| 依据 | 无，只能猜 | 原卡的 HTML/CSS 片段 |
| 出错方式 | 捏造出作者根本不想要的东西 | 最多是还原度不足 |
| 原卡没 UI 时 | 仍会硬造一个 | **不生成**（用户明确要求） |

**核心原则：有则译，无则不译。** 还原度不足可以迭代，凭空捏造是方向性错误。

### 1.3 为什么要移植 UIengine

最初评估「生成 JSON 需不需要引擎」，答案是**不需要**——
生成 JSON 只要知道键名与结构，不需要渲染器。

但用户的真实目标有两条是必须真渲染的：

1. **预览**：转译出的 UI 要能立刻看到效果，否则是盲盒；
2. **AI 设计工作台**：让 AI 帮忙设计 UI，没有即时预览就无法迭代。

因此结论修正为：**必须移植，但用 path 依赖而非复制源码**（见 2.3）。

---

## 二、已确认的技术事实（施工前的勘察结论）

> 以下每条都经过实际查证，不是推测。改动前若与现实不符，先更新本节。

### 2.1 渲染闭包：25 个文件 / 12819 行，且很干净

从 `UIAssemblyRuntimeView` 递归求 import 闭包：

```
lib/models/          card_entry_target · character_entry · session_state
                     status_bar_field · text_highlight_rule · ui_assembly_info
lib/services/        text_highlight_engine
lib/services/ui_engine/
                     assembly_rich_text · avatar_scope · data_channel_service
                     element_animation · linker_event_bus · linker_matrix_engine
                     linker_service · math_node_engine · message_action
                     message_flow_scope · ripple_shader · select_option
                     text_highlight_scope · text_value_extractor · ui_models
                     ui_renderer · ui_semantic_role
lib/widgets/         ui_assembly_runtime_view
```

**关键结论**：闭包内**没有**数据库、聊天页、路由、应用级服务。
唯一与应用层耦合的 `ui_asset_service.dart`（编辑器资产库）**不在渲染链路内**。

→ 渲染引擎是自包含的，可移植。

### 2.2 工具侧缺少的依赖

| 包 | 用途 |
|---|---|
| `flutter_markdown` / `markdown` | 富文本渲染（text / message_flow） |
| `flutter_html` | HTML 渲染 |
| `flutter_colorpicker` | 取色器（AI 工作台要用） |

均为纯 Flutter 包，Windows 桌面端无障碍。

### 2.3 共享方式：path 依赖，**绝不复制源码**

工具位于 `ToolofPC/llm_card_converter/`，与主项目在**同一个 git 仓库**内，
这是决定性的有利条件：

```yaml
dependencies:
  llm_project:
    path: ../../        # 直接引用主项目
```

**为什么不能复制**：本项目栽过最多次的坑就是「静默失效」——
两份拷贝一旦漂移，工具按旧规则生成、引擎按新规则读，
**不报错、只是不生效**，排查成本极高（见 HANDOFF 3.5j）。

同一份源码则从根本上不存在漂移。

### 2.4 目标 JSON 结构（三层嵌套字符串，极易写错）

```
character.json
└── meta_json                    ← String（整份 meta 是 JSON 字符串）
    └── ui_assemblies            ← List<String>（每个元素又是 JSON 字符串）
        └── {
              id, name, mode,
              elements,          ← String！（顶层元素，通常为空）
              pages,             ← String！解析后才是页面数组
              pcbWidth, pcbHeight, pcbColorValue, pcbRadius, pcbRounded,
              createdAt
            }
            └── pages[] = { id, name, type, parentPageId, sortOrder,
                            elements[], gestures[], propertyOverrides[] }
                └── elements[] = { id, isComposite, offset{x,y}, size{width,height},
                                   layerIndex, parentSurfaceId, rotation,
                                   layoutLocked, sealed, module{...} }
                    └── module = { id, name, type, material, shape, color,
                                   opacity, borderRadius, properties{},
                                   boundVariable, statusFieldMirrorKey,
                                   displayExpression, linkedSources[] }
```

**任何一层忘记 `jsonEncode` → 引擎读不到 → 静默回落默认值。**

### 2.5 字段类型陷阱

| 字段 | 类型 | 说明 |
|---|---|---|
| `material` | **int** | 枚举下标：`0=glass 1=solid 2=gradient 3=outline` |
| `shape` | **int** | `0=rectangle 1=rounded 2=capsule 3=circle 4=heart 5=star5 6=star4` |
| `color` | **int** | ARGB 整数，如 `4279111712`。不是 `#RRGGBB` 字符串 |
| `offset` / `size` | Map | `{x,y}` / `{width,height}`，值为 double |

### 2.6 PCB 尺寸硬约束

```
宽 120 ~ 600（extra_companion 上限 212）
高 64 ~ 2000
```

出处：`lib/models/ui_assembly_info.dart` 的 `minPcbWidth` / `maxPcbWidthFor` 等。

### 2.7 「静默失效」清单（写卡时连栽七次，务必先读）

完整版见 `ASSEMBLY_HANDOFF.md` 3.5j。UI 生成必然会碰到的几条：

| 写错的地方 | 正确写法 | 症状 |
|---|---|---|
| 方案名凭记忆编 | 必须取自 `_schemes.json` 的 68 条 | 连线不生效，但编辑器显示「已配置」 |
| `params` | **`schemeParams`** | 参数读不到，`targetParam` 恒为 paramA |
| 只写 `sourceGesture` | **`sourcePort` 必须同值** | 双击/长按接不通 |
| indicator 写 `isOn`/`onColor` | **`statusRules` + `defaultColor`** | 灯永远是灰的 |
| scene/opening 无 `keyAction` | 必须标一个 | **整层 UI 不渲染** |

### 2.8 现有流水线结构

```dart
enum PipelineStage { rule, aiClassify, refine }
```

- `ConversionPipeline` 通过**注入回调**调用 AI（`AiClassifyFn` / `AiRefineFn`），
  内核不绑定网络库——新增 UI 阶段应沿用这个模式；
- 每阶段产物存入 `stageOutputs`，可单独重跑、可人工修改后作为下一阶段输入；
- `PipelineRunner` 统一调度，`onLog` / `onProgress` 上报。

---

## 三、施工计划

### 阶段 0：引擎移植与渲染验证 ✅ **已完成**

**为什么排第一**：这是「成本最低、风险最高」的一步。
若不通，后面所有工作的前提都不成立。

已识别的风险点：

- `ripple_shader.dart` 依赖 `shaders/` 目录的资源文件，
  **跨项目引用时资源路径大概率要处理**；
- 主项目 `pubspec.yaml` 的 `assets:` / `shaders:` 声明不会自动传递给工具；
- 主项目部分依赖（sqflite 等）在 Windows 桌面端可能无实现——
  虽然渲染闭包用不到，但 `pub get` 阶段仍会解析。

**做法**：加 path 依赖 → 新建一个**独立验证页面**（不动现有转译流程）
→ 硬编码一份 assembly JSON → 看能否渲染。

**验收**：验证页面能渲染出一份含 text / progress / button 的 UI，
且 `flutter run -d windows` 无报错。

**实际结果：直接采用了备选方案。** 探查发现两个阻碍，
使「path 指向整个主项目」不可行：

1. **依赖冲突**：`desktop_drop` 主项目 `^0.5.0` vs 工具 `^0.7.1`，版本区间无交集；
2. **无关依赖**：会把 `sqflite` / `image_picker` 等拖进工具，
   而渲染闭包**只需要 3 个第三方包**（`flutter_markdown` / `markdown` / `flutter_html`）。

因此抽出 `packages/llm_ui_engine/`（25 个文件），主项目与工具都依赖它。
**仍是同一份源码，不是拷贝**，不存在漂移。

已完成的改动：

| 项 | 内容 |
|---|---|
| 新建包 | `packages/llm_ui_engine/`，`lib/src/{models,engine,widgets}` + 统一导出 |
| 着色器 | 随包提供，加载路径改为 `packages/llm_ui_engine/shaders/...` |
| 主项目 | 删除原 25 个文件与根目录 `shaders/`，改 `package:` 引用 |
| import | 主项目 + 测试共 46 个文件改写（含 27 个原本靠间接引用的） |
| 工具 | 加 path 依赖 + `engine_probe_page.dart` 验证页，主页放大镜图标进入 |

**验证页覆盖四类渲染路径**：surface（材质/圆角/ARGB）、text（绘制）、
progress（数值量程）、button（交互热区 + keyAction 标记）。
顶部三个指示灯分别报告「模型解析 / 着色器 / 渲染」。

⚠️ 写验证 JSON 时**又踩了一次 3.5j**：keyAction 键名误写成 `is_key_action`，
正确是 `keyAction`（`UISemanticRole.propKey`）。已修正——
这恰好说明阶段 2 的强校验是必需的。

#### 验收结果（用户实测通过）

验证页三个指示灯全绿，深色面板正常渲染（标题 / 说明文本 / 68% 胶囊进度条）。

**着色器绿灯是关键证据**——它证明跨包资源路径
`packages/llm_ui_engine/shaders/ripple_refraction.frag` 生效，
而这是移植中最容易静默失败的一环。

#### 过程中踩的坑（都记在这，别重蹈）

| 问题 | 根因 | 修法 |
|---|---|---|
| 2202 条 `Undefined class` | 52 条 `package:llm_project/...` **绝对路径** import 指向已迁走的文件。我第一轮只改了相对路径 | 批量改指向 `package:llm_ui_engine` |
| `duplicate_definition: '_'` | 包 SDK 误写 `^3.5.0`，**语言版本被压到 3.5**，`(_, _, _)` wildcard（3.7+）失效。**源码没变，是约束变了** | 三方统一 `^3.11.5`；回调另改写为 `(_, __, ___)` 双保险 |
| `RippleShader` 未定义 | 类名实为 `RippleShaderLoader`，我凭记忆写错 | 改调用 |
| `type 'String' is not a subtype of 'num?'` | `createdAt` 要**毫秒时间戳**，我写了 ISO 字符串 | 改为 `1785572774665` |
| Kotlin 增量编译崩溃 | `desktop_drop` 源码在 C: 盘 Pub 缓存、项目在 D: 盘，跨盘相对路径计算失败 | `android/gradle.properties` 加 `kotlin.incremental=false` |

**最值得记住的一条**：`UIAssemblyInfo.fromJson` 的 10 个字段里，
9 个都有 `?? 默认值` 兜底——**类型写错只会静默回落，不报错**。
只有 `createdAt` 是硬转才抛了异常，等于帮我暴露了问题。
若当初写错的是 `pcbWidth`，就会得到一块尺寸不对的面板而毫无提示。

这正是阶段 2「强校验」的必要性依据：**人工核对 JSON 靠不住**，
我在这个项目里已经因手写 JSON 栽过三次（键名 / 类型 / 结构各一次）。

#### 工具

- `tools/check_pkg_wiring.py` —— 一秒判断包有没有挂上
  （直接查 `package_config.json`，不用在上千条报错里翻）

---

### 阶段 1：预览面板 ✅ **已完成**

新增 `lib/ui/assembly_preview.dart`：从角色卡数据里剥出 UI 并渲染。

#### 接入点

| 位置 | 形态 |
|---|---|
| 工作区每张卡的预览区 | 顶部加「文本 / UI」标签切换，逐卡记忆 |
| 引擎验证页 | 加「载入 .llmcard」，可直接看真实卡片 |

用的是 `UIAssemblyRuntimeView`——**主 App 聊天页在用的同一个组件**，
所以预览效果 = 玩家实际看到的效果，不存在两套渲染。

#### 几个设计决定

- **UI 单独一栏而非塞进文本预览**：两者信息密度差太多，
  混排会把 UI 挤成一小块，失去「看效果」的意义。
- **舞台只缩不放**：PCB 高度最大 2000，放不下要缩；
  但放大会让 1px 线条发糊，反而看不清真实效果。
- **一张卡多份 UI 用 chip 切换**：实测 `samples/` 里最多 3 份
  （scene + extra_sticky + opening）。
- **「没有 UI」与「UI 坏了」分开提示**：
  前者是预期行为（原卡就没有），后者要排查，混为一谈会误导。

#### 为什么验证页要加「载入 .llmcard」

转译工具**阶段 3 之前产不出带 UI 的卡**，工作区那个标签页暂时只会
显示「这张卡没有 UI」。手动载入 `samples/` 里的现成卡才能真正验证
预览面板本身是否可用。

#### 验收结果（用户实测通过）

样卡全部成功渲染，含最复杂的 `灰港迷雾`（scene 5 页 / 124 元件）
与 `织房夜话`（3 份 UI，含 extra_companion）。

至此**转译产物从不可见变为可见**——这是后续 UI 生成能迭代的前提。

---

### 阶段 2：UI 契约与校验 ⬜

**2a. 契约导出脚本**（主项目侧）

从引擎导出机器可读的规格：组件类型、合法属性键、枚举下标、PCB 约束。
连同已有的 `samples/_schemes.json`（68 条方案）作为唯一事实来源。

**2b. 校验器补强**

`samples/validate_card.py` 目前只有 `check_entries` / `check_contrast` 两个函数，
覆盖面不足以支撑自动生成。需补齐 2.4~2.7 全部检查项。

**验收**：故意造错的卡（假方案名 / `params` 写错 / 缺 keyAction / 三层嵌套漏 encode）
必须全部被拦下。**每条检查都要用「造错→必报→修正→通过」验证**。

---

### 阶段 3：UI 生成（新流水线步骤）⬜

**插入位置**（用户指定）：

```
stage1 规则转译
stage2 AI 归类人物内容
stage3 AI 生成 UI        ← 新增
stage4 AI 自检（含 UI）    ← 原 refine，扩展审计范围
```

**为什么插在中间而不是最后**：
UI 生成依赖 stage2 的产物（状态栏字段、条目内容）；
且放最后会导致自检环节看不到 UI，等于新增部分无人审核。

#### 3a. 识别层（AI）—— **已由真实样本修正设计**

> ⚠️ 下面的设计基于对真实卡 `samples/st_reference/黑曜石·法外特区.json`
> 的分析，推翻了最初「HTML 直接写在 description 里」的假设。

##### 真实机制：正则替换，不是内联 HTML

ST 卡的「UI」几乎不写在 `description` 里，而是靠
`extensions.regex_scripts` 实现：

```
LLM 按提示词输出自定义标签  →  正则匹配捕获  →  替换成一大段 HTML
```

以这张卡为例（`description` 只有 186 字，无任何 HTML）：

| 正则脚本 | 捕获的标签 | 产出 |
|---|---|---|
| 「状态栏」 | 17 个：正文/称号/编号/罪名/**生命/精神/体力/饱腹**/势力/关系/声望/点数/物品/位置/日期/时间/选项 | 5959 字符 HTML |
| 「前端」 | 5 个：终端状态/当前位置/当前时间/正文/选项列表 | 2226 字符 HTML |

**这对识别层是决定性的好消息**：
`findRegex` 里的标签名就是**作者亲手写的语义字段名**，
不需要 AI 从散文里猜「这段文字是不是状态」——直接读标签即可。

##### 视觉形态可直接映射

「状态栏」那条的 `replaceString` 里：

| 原卡写法 | 数量 | 映射到 |
|---|---|---|
| `<div style="width: $5">` 内层条 | 4 | `progress` |
| `display: flex` 横向分栏 | 11 | 元件横向排布 |
| `border-radius` | 7 | `surface.borderRadius` |
| `box-shadow` 发光 | 5 | 外观 / `glowPulse` 动画 |
| `linear-gradient` | 1 | `material: gradient` |

作者还用 HTML 注释标出了 9 个功能分区
（顶部警戒条 / 正文 / 监控仪表盘 / 资产社交 / 物品栏 / 决策引导 / 底部位置），
**等于自带布局说明**。

##### 交互：`onclick="send('...')"`

`first_mes` 里的选项列表：

```html
<div onclick="send('选择开场1：新人入狱')">[01] 新人入狱 - ...</div>
```

`send()` 是 ST 的内置函数，点击即把字符串作为用户消息发出。
这**正好对应**我们的 `button` + `sendsMessage` 标记。

##### 因此识别层的输入应该是

优先级从高到低：

1. **`extensions.regex_scripts`** —— 最可靠。标签名 = 语义字段名，
   `replaceString` = 视觉形态。有它就不用猜。
2. **`first_mes` 里的 `onclick="send(...)"`** —— 明确的交互意图。
3. **内联 HTML**（`<div style=...>`）—— 少见但要兜住。
4. 纯文本 —— **不生成 UI**（用户明确要求）。

##### 识别层输出的意图描述示例

```json
{ "kind": "progress", "label": "生命", "sourceTag": "生命",
  "hint": "红色发光横条，与精神并排", "max": 100 }
```

AI 只产出这种结构化描述，**不直接吐 assembly JSON**。

##### 待确认（需要更多样本）

- 这张卡的 `tavern_helper` 里有个被禁用的 MVU 脚本
  （`import 'https://.../MagVarUpdate/bundle.js'`）——
  说明有些卡靠**外部 JS 插件**做变量系统。这类超出静态识别范围，
  应明确**不支持**并给出提示，而不是硬转。
- 需要 2~3 张不同风格的卡验证「正则 = 主要机制」这个结论的普适性。


##### 已实现：`lib/core/regex_ui_extractor.dart`（纯代码，不调 AI）

五张真实卡实测通过：

| 卡 | 判定 | 结果 |
|---|---|---|
| 黑曜石·法外特区 | ✅ 可转译 | 状态栏 17 字段（4 进度条）+ 前端 5 字段 + 开场按钮 5 个 |
| 玲茹 | ✅ 可转译 | 12 字段（4 数值） |
| 异世界公会 | ✅ 可转译 | 8 条脚本，玩家状态栏 15 字段（10 数值） |
| 丧尸末日系统 | ○ 无 UI | 0 条正则，不生成 |
| WuWa Solaris-3 | ⛔ 插件依赖 | 3 个外部 JS，只转文本 |

##### 三个实测才发现的坑

**1. `enabled:false` 的插件不算依赖。**
黑曜石带了个关闭的 MVU 残留，它的 UI 完全靠正则、可以正常转。
只要见 `import` 就拒绝会**误杀好卡**。必须递归找 `type:script` 且
`enabled:true` 的条目。

**2. URL 正则不能用非贪婪。**
`[^\s]+?\.js` 会在域名 `testingcf.jsdelivr.net` 的 `.js` 处截断，
得到 `https://testingcf.js` 这种假地址。

**3. 字段类型必须结合 CSS 回填。**
黑曜石的「生命/精神/体力/饱腹」在 `findRegex` 里写的是 `(.*?)`（文本），
但 `replaceString` 里有 `width: $5`~`width: $8`
——**它们其实是百分比进度条**。

只看 `findRegex` 会把 4 个进度条全判成文本。
回填后 4/4 精确命中，故新增 [UiFieldType.percent]。

##### 输出的数据结构

```
UiExtraction
  ├─ pluginDependent / pluginUrls   ← 为真时不生成 UI
  ├─ openingActions[]               ← onclick="send('...')" 的文案
  └─ scripts[]
       ├─ kind        tagCapture / barCapture / decoration / cleanup
       ├─ fields[]    { name, type, captureIndex, maxCaptureIndex }
       ├─ visuals     { progressBars, flexRows, gradient, ... }
       ├─ sections[]  作者写的 HTML 注释（自带布局说明）
       └─ rawReplace  原始 CSS，交给 AI 判断视觉形态
```

`fields` 的 `captureIndex` 与 `replaceString` 里的 `$N` 一一对应，
这是把「字段」和「HTML 里的位置」对上的关键。

#### 3b. 构建层（纯代码，**绝不交给 AI**）

把意图描述翻译成合法 assembly JSON。

**这一步必须是确定性代码。** 理由：三层嵌套字符串、ARGB 整数、
枚举下标、`schemeParams` 而非 `params`……
人工手写都连栽七次，AI 直接生成必错，且错得静默。

##### 方案 A 实测结果（纯代码，未调 AI）

五张卡产物**全部通过 `validate_card.py` 零错误**：

| 卡 | 结果 |
|---|---|
| 黑曜石 | extra_sticky 300×456（30 元件）+ opening 320×282（17 元件，5 个按钮） |
| 玲茹 | extra_sticky 300×400（26 元件，12 状态字段） |
| 异世界公会 | extra_sticky 300×456（30 元件） |
| 丧尸末日 | 不生成（原卡无 UI） |
| WuWa | 不生成（插件依赖） |

##### 一个实测才发现的选择 bug

一张卡常有多条 UI 脚本（换肤版本），要挑一条做主面板。
最初按**字段数量**挑，结果异世界公会选错了：

| 脚本 | 字段 | 数值 |
|---|---|---|
| 好友列表 | 20 | **0** |
| 玩家状态栏 | 15 | **10** |

「好友列表」字段更多，但那是 `name1/level1/equip1...` 三个好友的重复条目，
全是文本；真正的状态面板是「玩家状态栏」。

改为**数值字段数优先**后选对了。状态面板的本质是数值，不是字段多。

##### 布局策略：朴素但可靠

这一版不追求还原原卡外观，只保证「信息不丢、结构正确、能渲染」：

```
标题
生命  ▓▓▓░░      ← 数值字段：标签 + progress + 数据通道
精神  ▓▓▓▓░
称号：囚犯        ← 文本字段：标签 + text + 数据通道
```

**每个字段都绑了数据通道**（`targetKind: status_field`），
数值用 `suggest_delta`、文本用 `suggest_replace`——
没有这层，UI 就只是静态装饰，LLM 读不到也写不了。

字段上限 14 个：PCB 高度上限 2000，字段太多会生成巨型面板。
超出部分丢弃并在 notes 说明。

##### 接线陷阱：`runAll` 不是实际入口

方案 A 首次实测时**所有卡都显示「这张卡没有 UI」**。
原因不是提取或构建出错，而是**新阶段没被调用**：

```
ConversionPipeline.runAll()      ← 我加了 runBuildUiStage
PipelineRunner.run()             ← 工作区实际用的是这个，逐个手动调阶段
```

两条入口并存，只改一处等于没改。

同时踩到第二个点：`_runAiStages` 里有 `if (!aiOn) return;`。
UI 生成是**纯代码**，必须放在这条 return **之前**，
否则没配 API 的用户永远拿不到 UI。

流水线日志现在是四步：
`规则转译 → AI 归类 → UI 生成 → 检查精修`。

##### 真实转译验收（黑曜石·法外特区）

用户用工具实际转出 `.llmcard`，逐项核对：

| 项 | 结果 |
|---|---|
| `ui_assemblies` | ✅ 2 份（extra_sticky 300×456 / opening 320×282） |
| `status_bar_fields` | ✅ 14 个（4 数值 + 10 文本） |
| 数值字段映射 | ✅ 生命/精神/体力/饱腹 → progress，与原卡 `width:$5~$8` 完全对应 |
| 数据通道 | ✅ 14 个元件全部绑定，LLM 可读写 |
| 开场按钮 | ✅ 5 个，全带 `sendsMessage`，首个带 `keyAction` |
| 世界书 | ✅ 30 条 / 49666 字，与源卡**一字不差** |
| 校验器 | ✅ 零错误 |

##### 补上的一个疏漏：extra_sticky 的折叠按钮

首次产物有一条警告：`extra_sticky: 没有任何 keyAction 标记`。

这不会导致不渲染（`blocksWithoutKeyAction` 只含 opening / scene），
但**玩家没法收起常驻栏**——它会一直占着消息流顶部。
引擎给这个 mode 定义的关键职责就是「折叠界面」。

已在标题行右侧加一个 `▾` 折叠按钮并标 `keyAction`。
修后五张卡重跑：零错误**零警告**。

#### 3c. 状态栏映射

用户明确要求：「角色后面跟着的一些状态栏，就改成我们设计的状态栏」。

→ 原卡里的状态条 → 我们的 `StatusBarField` + `extra_sticky` 常驻 UI，
并绑好数据通道（`targetKind: 'status_field'`）。

**验收**：
- 产物过校验器**零警告**才输出；
- 原卡无 UI 时**不生成任何 assembly**（不是生成一个空的）；
- 生成结果能在阶段 1 的预览面板里正确显示。

---

### 3d. 方案 A 实测暴露的缺陷（用户导入主 App 后反馈）

> 结构合法 ≠ 好用。以下全部经过复核确认，按优先级排列。

#### P0-1 开场白的初始数据全丢了 ⬜

**这是最严重的一条。** 原卡 5 个开场白**各带一套不同的初始状态**：

| 开场 | 精神 | 体力 | 饱腹 | 势力 | 点数 |
|---|---|---|---|---|---|
| 1 新人入狱 | 84% | 92% | 60% | 无 | 0 pts |
| 2 狱警入职 | 90% | 90% | 80% | 管理局 | 1000 pts |
| 3 全员迪化 | 89% | 90% | 61% | 无 | 0 pts |
| 4 特区大佬 | 96% | 98% | 90% | 自定义 | 200万+ pts |

数据就写在 `alternate_greetings` 里的 `<精神>84%</精神>` 这类标签中，
**可以直接解析**。当前实现把所有字段的 `initial_value` 一律设成 `0` / 空，
等于把作者精心设计的开局差异全抹平了。

修法：解析每个 `alternate_greetings` 的标签值 → 存为「开局预设」。
（需要先确认引擎侧如何表达「选了某开场白就套用某组初值」。）

#### P0-1 进展：引擎地基已就位 🟡

按用户设计落地，**分支之间是平级关系**（没有父子，
"总确认"只是「只有一个分支时」的习惯叫法，标记只需一种）。

已完成：

| 改动 | 位置 | 作用 |
|---|---|---|
| `SessionState.branchIndex` | 引擎 | 记住玩家当前选了第几个开场分支，随会话落盘 |
| `StatusBarField.branchInitialValues` | 引擎 | 分支下标 → 初值；空表不落盘，单开场卡零影响 |
| `_switchGreeting()` | 聊天页 | 切开场白时写入分支并套用该分支初值 |
| `UiExtraction.branchPresets` | 转译工具 | 从开场白解析各分支初始状态 |

关键设计：

- **分支不依赖 opening UI**。判据是开场白条数：≤1 只有主支路，
  >1 则每条开场白 = 一个平级分支。这样没做 opening 页的卡也能用。
- **未设计的分支照搬主支路**（`initialValueForBranch` 回落 `initialValue`）。
- **只覆盖未被改动过的字段**。玩家翻看别的开场白时，
  对话中已变化的数值不该被重置——判据是当前值仍等于某个分支预设。
- **只认正则里声明过的字段名**，否则正文里随便一个 `<某某>`
  都会被当成状态数据。

已完成（续）：

| 改动 | 作用 |
|---|---|
| 构建层写入 `branch_initial_values` | 各分支初值落进 `status_bar_fields` |
| `_cleanNumber` | `84%`→`84`、`1000 pts`→`1000` |
| `_fitsPercentBar` | 量程超 0~100 的字段降级为文本 |

黑曜石实测（4 个开场分支）：

```
生命  {0:100, 1:100, 2:100, 3:100}   → progress
精神  {0: 84, 1: 90, 2: 89, 3: 96}   → progress
体力  {0: 92, 1: 90, 2: 90, 3: 98}   → progress
饱腹  {0: 60, 1: 80, 2: 61, 3: 90}   → progress
点数  {0:  0, 1:1000, 2: 0}          → 降级文本
势力  {0:无, 1:管理局, 3:（自定义）}     → 文本
```

**两个避坑点：**

1. **带中文数量词的值不洗**。`200万+ pts` 取第一段数字会得到 `200`，
   与原意差一万倍。**错误的数比缺失的数更难发现**，宁可保留原文。
2. **量程超 0~100 的字段退回文本**。「点数」在 0~100 的条里会永远满格，
   反而失真。

待办：
- [ ] 编辑器的分支切换器（含清空/继承主支路）
- [ ] 找个空位常驻显示「当前编辑哪个分支」（用户提出，防止改错地方）

#### P0-2 转译后的开场白仍带渲染标记 ⬜

产物里的 `opening_greetings` 原样保留了
`<终端状态>ONLINE</终端状态><正文>...` 这些标记。

在 ST 里它们会被正则替换成 HTML；在我们这边**没有对应机制**，
玩家会直接看到一堆尖括号。

修法：既然已经把标签内容提取进 UI 了，正文就该**剥离标记只留 `<正文>` 段**。

#### P1-1 开场按钮缺「确认」语义 ⬜

5 个开场按钮只有第一个标了 `keyAction`（为了满足 opening 的渲染要求）。
但用户指出：**每个开场都该是一个「确认」入口**，
点哪个就用哪个开局，而不是「第一个特殊、其余普通」。

#### P1-2 button → surface 按压动画没做 ⬜

引擎有现成方案 `click_to_surface_press`（68 条方案表里）。
当前生成的按钮点下去毫无反馈——按钮本身是不显形的热区，
必须靠联动器连到 surface 才有视觉响应。

这是**引擎已有能力但没用上**，成本很低。

#### P1-3 原卡的选项交互没实现 ⬜

原卡每轮对话都会输出 `<选项>` 列表让玩家点选推进剧情。
当前只转了开场那一次的 5 个按钮，**后续轮次的动态选项完全没做**。

这需要 `message_flow` + 动态按钮，属于较大改动。

#### P2 UI 过于朴素 ⬜

用户原话：「非常简单的 UI」。
当前是纯代码生成的骨架——深色底板 + 标签 + 进度条，
没有还原原卡的配色、渐变、发光、分区布局。

这正是**方案 B（AI 视觉层）**要解决的，
现在有了基线可以直接对比提升幅度。

---

### 阶段 4：AI 自检扩展 ⬜

原 `refine` 阶段增加 UI 维度的审计：
- 生成的 UI 是否覆盖了原卡的所有可视元素；
- 有无遗漏 / 过度设计；
- 与原卡观感的差距。

**仍然只给建议、不自动改**（沿用现有 refine 的设计）。

---

### 阶段 5：AI UI 设计工作台 ⬜

用户的最终目标：让 AI 从零帮忙设计 UI，甚至设计带 UI 的完整角色卡。

前四阶段完成后，这一步的基础设施已经齐备：
渲染能力（阶段 0-1）、合法性保证（阶段 2）、AI 生成管线（阶段 3）。

具体形态待前面跑通后再定。

---

## 四、贯穿全程的约束

### 4.1 产物必须过校验器

**写进工具本身，不靠事后人工检查。** 校验不过就不输出。

### 4.2 校验器用 Python，工具用 Dart —— 不要重写

工具应**调用外部 `validate_card.py`**，而不是用 Dart 重写一份。
理由同 2.3：两份实现必然漂移，而漂移导致静默失效。

### 4.3 AI 只做「理解」，不做「构造」

- AI 负责：看懂 HTML → 描述意图；审计产物 → 给建议
- 代码负责：把意图变成 JSON；保证结构合法

违反这条会直接踩进 2.7 的静默失效清单。

### 4.4 沙箱限制（协作方式）

- 沙箱**没有 Flutter/Dart SDK**，无法运行 `flutter analyze` / `flutter test`；
- 每步完成后由用户本地跑 analyze 验证；
- 涉及 part/mixin 结构改动时，提交前跑 `tools/check_mixins.py`。

---

## 五、当前状态

| 阶段 | 状态 | 备注 |
|---|---|---|
| 0 · 引擎移植与渲染验证 | ✅ | 三灯全绿，面板正常渲染 |
| 1 · 预览面板 | ✅ | 样卡全部正确渲染 |
| 2 · 契约与校验 | ⬜ | **下一步做这个** |
| 3 · UI 生成 | 🟡 | 方案A 骨架可用，6 项缺陷待补（见 3d） |
| 4 · 自检扩展 | ⬜ | |
| 5 · AI 设计工作台 | ⬜ | |

**已完成的前置工作**（转译工具侧，用户自行完成）：
文本内容转译（stage1~stage3）已可用。

---

## 六、相关文档

| 文档 | 用途 |
|---|---|
| `ASSEMBLY_HANDOFF.md` 3.5j | **静默失效清单**，写 UI JSON 前必读 |
| `ASSEMBLY_HANDOFF.md` 3.5k | 资产库模板 ≠ 实例快照 |
| `ASSEMBLY_IMPLEMENTATION_TRACKER.md` | 主项目 Assembly 施工档案 |
| `samples/README.md` | 卡片硬约束清单 · 固定条目结构 |
| `samples/_schemes.json` | 68 条联动方案（含类型约束） |
| `samples/validate_card.py` | 卡片校验器（**待补强**，见阶段 2b） |
| `tools/check_mixins.py` | part/mixin 结构检查器 |
