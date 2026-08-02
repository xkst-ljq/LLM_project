# 交接：新对话请先读这份

> 上一轮对话消息过多、平台开始吞消息，故转移。
> 这份文档让新对话能无缝接上，**不需要回看历史**。
>
> 分支 `arena/019fa2fe-llm-project` 与 `main` 已同步到 `113a2a2a`。

---

## 0. 立刻要做的第一件事

**有一个待验证的 analyze 报错，很可能只是本地缓存。**

用户最后一次 analyze 报了 3 条：

```
character_assembly_page.dart:147  branchNames isn't initialized
logic.dart:1638 / 1641           Undefined name '_editingBranch'
```

但仓库里**代码已经是修好的**：

| 报错位置 | 实际内容 |
|---|---|
| `page:147` | 是 `const CharacterAssemblyPage({` 这一行；参数在 **153 行** |
| `logic:1638/1641` | 是**注释行**；真正使用在 1646/1649，定义在 **38 行** |

行号完全对不上 → 分析器读的是旧代码。

请用户 `git pull`；若已最新则**重启 Dart Analysis Server**
（VS Code: `Ctrl+Shift+P` → `Dart: Restart Analysis Server`）。

拉取后若仍报错**且行号变了**，那才是真问题。

---

## 1. 这个项目在做什么

一个 Flutter 的 LLM 角色扮演 App，核心特色是**作者可以给角色卡配可视化 UI**
（血条、状态面板、开场选项等），运行时由引擎渲染，并能与 LLM 双向读写。

两个子系统：

| 系统 | 位置 | 说明 |
|---|---|---|
| **主 App** | `lib/` | 角色卡、聊天、Assembly 编辑器 |
| **UI 引擎** | `packages/llm_ui_engine/` | 抽出的本地 package，两边共用同一份源码 |
| **转译工具** | `ToolofPC/llm_card_converter/` | Windows 桌面应用，把 SillyTavern 卡转成本项目格式 |

**当前主线：转译工具的 UI 生成**（`ToolofPC/UI_CONVERTER_PLAN.md` 必读）。

---

## 2. 本轮 36 个提交做了什么

按时间顺序，五个阶段：

### ① 引擎抽包（提交 1-11）

为了让转译工具能预览 UI，把渲染引擎从主项目抽成
`packages/llm_ui_engine`（25 个文件）。**同一份源码、path 依赖，不是拷贝**
——拷贝必然漂移，而漂移导致静默失效。

抽包时栽了四个坑，全记在 `ASSEMBLY_HANDOFF.md` 3.5m：

1. **改 import 只扫了相对路径**，漏了 52 条 `package:llm_project/...`
   绝对路径 → 2202 条 `Undefined class`
2. **SDK 约束决定语言版本**：包误写 `^3.5.0` 让原有的
   `(_, _, _)` wildcard（Dart 3.7+）突然报 `duplicate_definition`
   ——**源码一个字没改**
3. 跨包资源要加 `packages/<包名>/` 前缀（着色器）
4. Windows 跨盘符（Pub 缓存在 C:、项目在 D:）会让 Kotlin 增量编译崩溃
   → `android/gradle.properties` 加 `kotlin.incremental=false`

### ② 预览面板（提交 12）

`ToolofPC/.../assembly_preview.dart`，用的是主 App 同一个
`UIAssemblyRuntimeView`——**预览效果 = 玩家实际看到的效果**。

接了两处：工作区每张卡的「文本 / UI」标签、引擎验证页的「载入 .llmcard」。

### ③ 契约与校验（提交 13）

- `tools/export_ui_contract.py` 从引擎源码导出 `samples/ui_contract.json`
  （组件类型、枚举下标、PCB 约束等），**机器生成不手抄**
- 校验器补 5 类漏检，`samples/mutation_test.py` 变异测试 **9/9 全抓到**

### ④ 分析真实 ST 卡（提交 14-21）

用户提供 5 张真实卡，**推翻了最初的假设**：
ST 卡的 UI **不写在 `description` 里**，而是靠 `extensions.regex_scripts`
把 LLM 输出的标记替换成 HTML。

详见 `samples/st_reference/ANALYSIS.md`。

### ⑤ UI 生成 + 开场分支体系（提交 22-36）

见下面第 3、4 节。

---

## 3. UI 生成（方案 A：纯代码）

```
stage1 规则转译 → stage2 AI 归类 → stage3 UI 生成 → stage4 检查精修
                                    ↑ 纯代码，不调 AI
```

三个核心文件：

| 文件 | 职责 |
|---|---|
| `regex_ui_extractor.dart` | 从 `regex_scripts` 提取 UI 意图 |
| `ui_assembly_builder.dart` | 构建合法 assembly JSON |
| `greeting_sanitizer.dart` | 剥离开场白的渲染标记 |

### ST 卡的四种 UI 模式（必须分类，否则转出垃圾）

| 模式 | 例子 | 能否转译 |
|---|---|---|
| `barCapture` | `\|性欲值:(\d+)\|XP:(\d+)/(\d+)\|` | ✅ **最好用**，自带类型与量程 |
| `tagCapture` | `<生命>(.*?)</生命>` | ✅ |
| `decoration` | `<Alliance>` → 纯装饰壳 | ❌ 无数据槽，转了是空壳 |
| `cleanup` | `replaceString` 为空 | ❌ 与 UI 无关（34 条里占 12 条） |

**关键**：`findRegex` 给字段名，`replaceString` 给真实形态
——`width: $5` 说明第 5 个捕获组是进度条。**两边都要读**。

黑曜石卡的「生命/精神/体力/饱腹」在正则里写的是 `(.*?)`（文本），
靠 CSS 回填才判出是进度条，4/4 精确命中。

### 实测结果（5 张卡，产物全部零错误）

| 卡 | 结果 |
|---|---|
| 黑曜石·法外特区 | extra_sticky（14 字段）+ opening（5 按钮） |
| 玲茹 | extra_sticky（12 字段） |
| 异世界公会 | extra_sticky（15 字段，10 数值） |
| 丧尸末日系统 | **不生成**（原卡无 UI，正确行为） |
| WuWa Solaris-3 | **不生成**（依赖外部 JS 插件） |

依赖外部 JS（MVU 等）的卡明确不支持 UI 转译，只转文本
——那些界面由 JS 运行时生成，静态分析拿不到最终形态。

---

## 4. 开场分支体系（本轮重点）

### 用户的设计（原话摘录）

> 总确认和分支确认只是相对而言的。只是当没有额外分支时才叫总确认。
> **不同的开场白本身就是平级关系，不存在谁父谁子。**

> 如果没有 openingUI 就不代表只有一个主支路方案，
> **以角色卡界面的开场白为参考**，开场白条数 ≤1 就只有主支路，
> \>1 就有分支路方案。

> 切换时可以选择**清空画布或者继承主支路**，
> 来实现不同的选择有完全不同的 UI 或者相同 UI 不同的初始数据。

> 如果没有设计分支方案，**所有的分支方案就照搬主方案**。

### 已打通的链路

```
转译工具解析开场白里的 <精神>84%</精神> → branchPresets
    ↓
status_bar_fields.branch_initial_values  { "0":"84", "1":"90", "3":"96" }
    ↓
编辑器可为每个分支单独设计 UI（继承主线 / 空白画布）
    ↓
玩家切开场白 → SessionState.branchIndex 更新并落盘
    ↓
运行时按分支渲染 UI + 套用该分支初值
```

### 实现位置

| 层 | 文件 | 内容 |
|---|---|---|
| 模型 | `session_state.dart` | `branchIndex`（计入 `isEmpty`，清空聊天要回主支路） |
| 模型 | `status_bar_field.dart` | `branchInitialValues` + `initialValueForBranch()` |
| 模型 | `ui_assembly_info.dart` | `branchVariants` + `pagesJsonForBranch()` |
| 编辑器 | `logic_branch.dart` | 切换器（继承/空白）+ `buildBranchIndicator()` |
| 编辑器 | `logic.dart:38` | `_editingBranch`（必须在根 mixin，见教训） |
| 聊天页 | `chat_page.dart` | `_switchGreeting()` + `_applyBranchInitialValues()` |

### 几个落地细节

- **只覆盖未被改动过的字段**：玩家翻看别的开场白时，
  对话中已变化的数值不该被重置。判据是当前值仍等于某个分支预设。
- **只认正则里声明过的字段名**，否则正文里随便一个 `<某某>`
  都会被当成状态数据。
- **数值清洗避开中文数量词**：`200万+ pts` 取第一段数字会得到 `200`，
  差一万倍。带「万亿千百」的一律保留原文。
- **量程超 0~100 的字段降级为文本**：「点数」从 0 到 1000 再到 200万，
  塞进百分比进度条会永远满格。

---

## 5. 下一步待办

### P1-3 原卡的动态选项没实现 ⬜

原卡每轮对话输出 `<选项>` 列表让玩家点选推进剧情。
当前只转了开场那一次的按钮，**后续轮次完全没做**。
需要 `message_flow` + 动态按钮，改动较大。

### P2 UI 过于朴素 ⬜（= 方案 B，AI 视觉层）

用户原话「非常简单的 UI」。当前是纯代码骨架：
深色底板 + 标签 + 进度条，没有还原原卡的配色、渐变、发光、分区布局。

**用户已明确顺序**：「AI 可以自建 UI 后再同步原卡的 UI」
——先有骨架，AI 再往上美化。方案 A 正好是对照基线。

### 零散

- `check_mixins.py` **不检测字段**跨 mixin 访问（只查方法调用），
  这次 `_editingBranch` 就是这么漏掉的。加检测容易误报，暂记。
- 角色编辑页首帧 RenderFlex 溢出（冷启动首次出现，无法复现，纯警告）。
- `文件传输toARENA/` 是用户传样本卡的目录，已在 `.gitignore` 里。
  样本卡因体积（最大 3.4MB）与 NSFW 内容不入库，
  分析结论见 `samples/st_reference/ANALYSIS.md`。

---

## 6. 协作方式（用户明确要求）

- **每完成一步就 commit + push**，用户才能拉取测试
- 用户测试通过后再进入下一步
- 用户用中文，回复也用中文
- **判断错误时必须明确承认并纠正**
- 不确定处用 `ask_user` 问，不要瞎猜着改
- 用户不需要兼容老数据：「都是开发版本，可以直接删干净」

### 用户的特点

观察极准，反馈常常直接点破根因。例如：

- 「是不是默认高级字段被降级的缘故？」——实际是我漏接了流水线入口，
  但他的怀疑方向促使我去查数据链路
- 「UI 的名称过长会挤占右侧 UI」——附完整堆栈，一次定位
- 主动用另一个 agent 跑诊断并把结论给我，其中「`RippleShader` 类不存在」
  确实是我凭记忆写错了类名

**他的反馈值得认真核实，不要急着辩解。**

### 沙箱限制

- **没有 Flutter/Dart SDK**，无法运行 `flutter analyze` / `flutter test`
- 只能用 `python3` 做括号平衡检查 + 逻辑复刻验证
- 提交前必须提醒用户本地跑 analyze

### git 推送流程（历史反复莫名截断）

```bash
git add -A && git commit -q -m "..."
git fetch -q origin arena/019fa2fe-llm-project
git reset -q --soft FETCH_HEAD   # 必须 --soft
git commit -q -m "..." && git push -q origin arena/019fa2fe-llm-project
```

合并到 main（不切分支，会话绑定在 arena 分支上）：

```bash
git push origin HEAD:refs/heads/main
```

**绝不能用 `git reset --hard`**（曾丢失全部改动），
**绝不能用 `git checkout <file>` 回退**（同样丢过）。

---

## 7. 工具箱

| 脚本 | 用途 |
|---|---|
| `tools/check_mixins.py` | part/mixin 五项结构检查，**改 mixin 前后必跑** |
| `tools/check_pkg_wiring.py` | 一秒判断 `llm_ui_engine` 包有没有挂上 |
| `tools/export_ui_contract.py` | 从引擎导出 `samples/ui_contract.json` |
| `samples/validate_card.py` | 卡片校验器，**转译产物必须零错误** |
| `samples/mutation_test.py` | 变异测试，验证校验器真能抓错（9/9） |

括号平衡脚本每次新 context 要重建：

```python
import sys
def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i]
        if c=='/' and i+1<n and src[i+1]=='/':
            while i<n and src[i]!='\n': i+=1
        elif c=='/' and i+1<n and src[i+1]=='*':
            i+=2
            while i+1<n and not(src[i]=='*' and src[i+1]=='/'): i+=1
            i+=2
        elif c in '"\'':
            q=c;i+=1
            while i<n:
                if src[i]=='\\': i+=2;continue
                if src[i]==q: i+=1;break
                if src[i]=='\n': break
                i+=1
        else:
            out.append(c);i+=1
    return ''.join(out)
s=strip(open(sys.argv[1]).read())
for a,b in [('(',')'),('{','}'),('[',']')]:
    print(a,s.count(a)-s.count(b))
```

**已知误判基线**（改动前后净变化为 0 才安全）：

| 文件 | 基线 | 误判原因 |
|---|---|---|
| `chat_page.dart` | `( -1  { 0  [ -1` | 字符串内的括号 |
| `logic_linker.dart` | `( 0  { -1  [ 0` | 嵌套字符串插值 |
| `regex_ui_extractor.dart` | `( 1  { 0  [ 0` | 三引号原始字符串 |
| 其余 | 全 0 | |

---

## 8. 血泪教训（务必先读）

完整版见 `ASSEMBLY_HANDOFF.md` 的 3.5b~3.5m。最要命的几条：

### ① 静默失效是本项目的头号杀手

写错键名/类型 → 引擎读不到 → 用默认值 → **不报错、界面还显示「已配置」**。

本轮又踩了三次：

| 错误 | 后果 |
|---|---|
| `createdAt` 写 ISO 字符串（应为毫秒时间戳） | 直接抛异常（算走运，暴露了） |
| `keyAction` 写成 `is_key_action` | opening 整层不渲染 |
| **`branchVariants['\$branch']`** | 反斜杠把插值转义成字面量，**所有分支永远回落主支路，零报错** |

最后一条最险：功能等于没做，但测试时不会有任何异常。

→ **所有手写 JSON 必须过 `validate_card.py`。**

### ② mixin 的坑（连栽五轮）

**静态成员不参与 mixin 继承**，`on` 子句只带来实例成员：

| 写法 | 结果 |
|---|---|
| `mixin B on A` 里裸写 `_fooStatic`（定义在 A） | ❌ `Undefined name` |
| `A._fooStatic` 但常量被搬到 B | ❌ `isn't defined for the type 'A'` |
| `A._fooStatic` 但常量已提到库顶层 | ❌ 要去掉 `A.` 前缀 |

**字段同理**：`_editingBranch` 定义在下游 mixin，
上游 `logic.dart` 用不了——必须提到依赖链根部。

跨组共享的常量一律提到**库顶层**。

### ③ 两条入口，只改一条等于没改

`ConversionPipeline.runAll()` 和 `PipelineRunner.run()` 并存，
工作区实际调的是后者。我只在 `runAll` 里加了 UI 生成阶段，
结果所有卡都显示「这张卡没有 UI」。

→ **加新阶段时要找到真正的调用入口。**

### ④ 数值清洗别造假数据

`200万+ pts` 取第一段数字会得到 `200`，**差一万倍**。
**错误的数比缺失的数更难发现。**

### ⑤ 文本级校验证明不了 Dart 语法成立

拆 part 文件时，括号平衡 + 逐行 diff 全过，但代码根本不能编译
（part 不能续写另一个 part 里打开的类体）。

→ 涉及结构改动时，明确告诉用户「这条只有 analyze 能验」。

---

## 9. 关键文件地图

```
packages/llm_ui_engine/               UI 引擎（主项目与工具共用同一份源码）
  lib/llm_ui_engine.dart                统一导出（25 个文件）
  src/models/ui_assembly_info.dart      branchVariants / pagesJsonForBranch
  src/models/status_bar_field.dart      branchInitialValues
  src/models/session_state.dart         branchIndex
  src/engine/ui_renderer.dart           渲染器（4137 行）
  src/engine/linker_matrix_engine.dart  68 条联动方案（纯数据表）
  src/widgets/ui_assembly_runtime_view.dart  运行时视图

lib/pages/character_assembly_page/    Assembly 编辑器（10 个 part）
  logic.dart          根 mixin（_editingBranch 在这，1662 行）
  logic_branch.dart   分支切换器 + 顶栏指示器
  logic_canvas.dart   画布交互
  logic_editors.dart  各类专项编辑器
  logic_linker.dart   联动器
  logic_page.dart     页面路由
  logic_elements.dart 元件操作
  logic_composite.dart / composite_child_editor.dart  复合件
  atom_field_groups.dart  13 种原子类型的字段组

ToolofPC/llm_card_converter/
  lib/core/regex_ui_extractor.dart    从 regex_scripts 提取 UI 意图
  lib/core/ui_assembly_builder.dart   构建 assembly JSON
  lib/core/greeting_sanitizer.dart    剥离开场白渲染标记
  lib/pipeline/pipeline.dart          四阶段流水线定义
  lib/pipeline/pipeline_runner.dart   **实际入口**（不是 runAll）
  lib/ui/assembly_preview.dart        UI 预览面板
  lib/ui/engine_probe_page.dart       引擎验证页（可载入 .llmcard）

文档
  HANDOFF_NEXT.md                     本文件
  ToolofPC/UI_CONVERTER_PLAN.md       转译工具施工计划（必读）
  ASSEMBLY_HANDOFF.md                 引擎踩坑记录 3.5b~3.5m
  ASSEMBLY_IMPLEMENTATION_TRACKER.md  Assembly 施工档案
  samples/st_reference/ANALYSIS.md    5 张真实 ST 卡的机制图谱
  samples/README.md                   卡片硬约束清单
```

### 目标 JSON 结构（三层嵌套，极易写错）

```
character.json
└── meta_json                    ← String（整份 meta 是 JSON 字符串）
    ├── ui_assemblies            ← List<String>（每个元素又是 JSON 字符串）
    │   └── { mode, elements(String!), pages(String!), pcbWidth, ... }
    │       └── pages[] = { id, name, type, elements[], gestures[], ... }
    │           └── elements[] = { offset{x,y}, size{w,h}, module{...} }
    └── status_bar_fields        ← List<Map>（含 branch_initial_values）
```

**类型陷阱**：`material`/`shape` 是**枚举下标 int**，
`color` 是 **ARGB int**（不是 `#RRGGBB`），
`createdAt` 是**毫秒时间戳**（不是 ISO 字符串）。
