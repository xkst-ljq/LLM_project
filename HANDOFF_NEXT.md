# 交接：新对话请先读这份

> 上一轮对话消息过多、平台开始吞消息，故转移。
> 这份文档让新对话能无缝接上，**不需要回看历史**。

---

## 0. 立刻要做的第一件事

**当前有一个待验证的 analyze 报错，很可能只是本地缓存。**

用户最后一次 analyze 报了 3 条错误：

```
character_assembly_page.dart:147  branchNames isn't initialized
logic.dart:1638 / 1641           Undefined name '_editingBranch'
```

但仓库里**代码已经是修好的**，对照如下：

| 报错位置 | 实际内容 |
|---|---|
| `page:147` | 是 `const CharacterAssemblyPage({` 这一行；参数在 **153 行** |
| `logic:1638/1641` | 是**注释行**；真正使用在 1646/1649，定义在 **38 行** |

→ 请用户先 `git pull`，若已最新则**重启 Dart Analysis Server**
（VS Code: `Ctrl+Shift+P` → `Dart: Restart Analysis Server`）。

拉取后若仍报错且行号变了，那才是真问题。

---

## 1. 当前进度

分支 `arena/019fa2fe-llm-project`，HEAD = `a4207998`（本地=远端，工作区干净）。

### 主线任务：SillyTavern 卡片转译工具的 UI 生成

工具在 `ToolofPC/llm_card_converter`（Flutter Windows 桌面应用）。
完整计划见 **`ToolofPC/UI_CONVERTER_PLAN.md`**（必读）。

| 阶段 | 状态 |
|---|---|
| 0 · 引擎移植（`packages/llm_ui_engine`） | ✅ |
| 1 · 预览面板 | ✅ |
| 2 · 契约导出 + 校验器补强 | ✅ |
| 3 · UI 生成（方案 A：纯代码） | 🟡 主体完成，余 P1-3 / P2 |
| 4 · AI 自检扩展 | ⬜ |
| 5 · AI UI 设计工作台 | ⬜ |

### 刚完成的：开场分支体系

用户设计（原话）：**不同开场白 = 平级分支**，各自可有不同初始数据、
甚至不同 UI。「总确认/分支确认只是相对而言，不存在谁父谁子」。

已打通的链路：

```
转译工具解析各开场白的 <精神>84%</精神> → branchPresets
    ↓
status_bar_fields.branch_initial_values
    ↓
编辑器可为每个分支单独设计 UI（继承主线 / 空白画布）
    ↓
玩家切开场白 → SessionState.branchIndex 更新
    ↓
运行时按分支渲染 + 套用该分支初值
```

关键约定：
- **分支不依赖 opening UI**：判据是开场白条数，≤1 只有主支路
- **未设计的分支照搬主支路**（`pagesJsonForBranch` 回落 `pagesJson`）
- 顶栏有 `buildBranchIndicator()` 常驻显示当前编辑哪个分支

---

## 2. 下一步待办

按优先级：

### P1-3 原卡的动态选项没实现 ⬜
原卡每轮对话输出 `<选项>` 列表让玩家点选推进剧情。
当前只转了开场那一次的按钮，后续轮次完全没做。
需要 `message_flow` + 动态按钮，**改动较大**。

### P2 UI 过于朴素 ⬜（= 方案 B）
用户原话「非常简单的 UI」。当前是纯代码骨架：深色底板 + 标签 + 进度条，
没有还原原卡的配色、渐变、发光、分区布局。

用户已明确顺序：**「AI 可以自建 UI 后再同步原卡的 UI」**
——先有骨架，AI 再往上美化。现在方案 A 正好是对照基线。

### 其它
- `check_mixins.py` 不检测**字段**跨 mixin 访问（只查方法调用），
  这次 `_editingBranch` 就是这么漏掉的。加检测容易误报，暂记。
- 角色编辑页首帧 RenderFlex 溢出（冷启动首次出现，无法复现，纯警告）。

---

## 3. 协作方式（用户明确要求）

- **每完成一步就 commit + push**，用户才能拉取测试
- 用户测试通过后再进入下一步
- 用户用中文，回复也用中文
- **判断错误时必须明确承认并纠正**
- 不确定处用 `ask_user` 问，不要瞎猜着改
- 用户不需要兼容老数据：「都是开发版本，可以直接删干净」

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

**绝不能用 `git reset --hard`**（曾丢失全部改动），
**绝不能用 `git checkout <file>` 回退**（同样丢过）。

---

## 4. 工具箱

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

| 文件 | 基线 |
|---|---|
| `chat_page.dart` | `( -1  { 0  [ -1` |
| `logic_linker.dart` | `( 0  { -1  [ 0` |
| `regex_ui_extractor.dart` | `( 1  { 0  [ 0` |
| 其余 | 全 0 |

---

## 5. 血泪教训（务必先读）

完整版见 `ASSEMBLY_HANDOFF.md` 的 3.5b~3.5m。最要命的几条：

### 静默失效是本项目的头号杀手

写错键名/类型 → 引擎读不到 → 用默认值 → **不报错、界面还显示「已配置」**。

本轮又踩了两次：
- `createdAt` 写 ISO 字符串（应为毫秒时间戳）
- **`branchVariants['\$branch']`** —— 反斜杠把插值转义成字面量，
  导致所有分支永远回落主支路。**功能等于没做，但零报错**。

→ 所有手写 JSON **必须过 `validate_card.py`**。

### mixin 的坑（连栽五轮）

**静态成员不参与 mixin 继承**，`on` 子句只带来实例成员。
跨组共享的常量一律提到**库顶层**。

字段也一样：`_editingBranch` 定义在下游 mixin，上游 `logic.dart`
用不了——必须提到依赖链根部。

### 数值清洗别造假数据

`200万+ pts` 取第一段数字会得到 `200`，**差一万倍**。
带中文数量词的一律不洗，保留原文。
**错误的数比缺失的数更难发现。**

---

## 6. 关键文件地图

```
packages/llm_ui_engine/          UI 引擎（主项目与工具共用同一份源码）
  src/models/ui_assembly_info.dart    branchVariants / pagesJsonForBranch
  src/models/status_bar_field.dart    branchInitialValues
  src/models/session_state.dart       branchIndex

lib/pages/character_assembly_page/    Assembly 编辑器（9 个 part）
  logic.dart          根 mixin，_editingBranch 在这
  logic_branch.dart   分支切换器 + 顶栏指示器
  logic_canvas / editors / linker / page / elements / composite
  atom_field_groups.dart   13 种原子类型的字段组

ToolofPC/llm_card_converter/
  lib/core/regex_ui_extractor.dart    从 regex_scripts 提取 UI 意图
  lib/core/ui_assembly_builder.dart   构建 assembly JSON
  lib/core/greeting_sanitizer.dart    剥离开场白渲染标记
  lib/pipeline/pipeline.dart          四阶段流水线
  lib/pipeline/pipeline_runner.dart   **实际入口**（不是 runAll）
  lib/ui/assembly_preview.dart        UI 预览面板

samples/st_reference/ANALYSIS.md      5 张真实 ST 卡的机制图谱
```

### ST 卡的 UI 机制（阶段 3 的核心依据）

**不写在 `description` 里**，而是靠 `extensions.regex_scripts`
把 LLM 输出的标记替换成 HTML。四种模式：

| 模式 | 例子 | 能否转译 |
|---|---|---|
| `barCapture` | `\|性欲值:(\d+)\|XP:(\d+)/(\d+)\|` | ✅ 最好用，自带类型 |
| `tagCapture` | `<生命>(.*?)</生命>` | ✅ |
| `decoration` | `<Alliance>` → 纯装饰壳 | ❌ 无数据槽 |
| `cleanup` | `replaceString` 为空 | ❌ 与 UI 无关 |

`findRegex` 给字段名，`replaceString` 给真实形态（`width: $5` = 进度条）
——**两边都要读**。

依赖外部 JS（MVU 等）的卡明确**不支持** UI 转译，只转文本。
