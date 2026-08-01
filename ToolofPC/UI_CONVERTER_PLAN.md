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

### 阶段 0：path 依赖可行性验证 🟡 **待用户本地验证**

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

---

### 阶段 1：预览面板 ⬜

把渲染接进工具的 `card_preview.dart`：转译完立刻能看效果。

**验收**：
- 拿 `samples/` 里五张示例卡（已知零警告）导入，四种 mode 都能正确显示；
- 与主项目 Assembly 编辑器的运行时预览**外观一致**。

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

#### 3a. 识别层（AI）

从 `description` / `first_mes` / `mes_example` 中提取 HTML/CSS 片段，
让 AI 输出**结构化的意图描述**，而不是直接吐 JSON：

```json
{ "kind": "progress", "label": "好感度",
  "current": 60, "max": 100, "hint": "粉色横向条" }
```

#### 3b. 构建层（纯代码，**绝不交给 AI**）

把意图描述翻译成合法 assembly JSON。

**这一步必须是确定性代码。** 理由：三层嵌套字符串、ARGB 整数、
枚举下标、`schemeParams` 而非 `params`……
人工手写都连栽七次，AI 直接生成必错，且错得静默。

#### 3c. 状态栏映射

用户明确要求：「角色后面跟着的一些状态栏，就改成我们设计的状态栏」。

→ 原卡里的状态条 → 我们的 `StatusBarField` + `extra_sticky` 常驻 UI，
并绑好数据通道（`targetKind: 'status_field'`）。

**验收**：
- 产物过校验器**零警告**才输出；
- 原卡无 UI 时**不生成任何 assembly**（不是生成一个空的）；
- 生成结果能在阶段 1 的预览面板里正确显示。

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
| 0 · path 依赖验证 | ⬜ | **下一步做这个** |
| 1 · 预览面板 | ⬜ | |
| 2 · 契约与校验 | ⬜ | |
| 3 · UI 生成 | ⬜ | |
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
