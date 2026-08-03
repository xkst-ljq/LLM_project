# 交接：新对话请先读这份

> 本轮对话经历了重大的技术突破和架构升级。
> 这份文档让新对话能无缝接上，**不需要回看历史**。
>
> 当前分支 `arena/019fc30b-llm-project` 已经与远端完全同步，编译与 `analyze` 100% 全绿无警告。

---

## 0. 启动新对话的唯一口令

新对话只需对 AI 说这一句：

***「读 `HANDOFF_NEXT.md`，继续。」***

*(注：上轮分析器缓存报错等问题均已彻底解决，如本地编辑器仍有残余红字提示，执行 `Ctrl+Shift+P` → `Dart: Restart Analysis Server` 重启 Dart 分析服务即可完全清空。)*

---

## 1. 我们的项目是什么

一个 Flutter 的 LLM 角色扮演 App，其核心特色是**作者可以通过可视化界面（UI Assembly）为角色卡配置动态面板（如血条、状态面板、开场选项、背包等）**，在运行时由引擎渲染，并能与大模型通过数据通道（Data Channels）执行双向读写。

三大子系统：

| 系统 | 目录位置 | 说明 |
|---|---|---|
| **主 App** | `lib/` | 负责角色卡列表、聊天交互、会话副本维护以及可视化编辑器。 |
| **UI 引擎** | `packages/llm_ui_engine/` | 本地独立的渲染 package，主 App 和转译器通过 path 依赖共用同一套源码。 |
| **转译工具** | `ToolofPC/llm_card_converter/` | PC 端转译工作台，负责将第三方酒馆/ST 角色卡一键转译为本项目专属的 `.llmcard` 格式。 |

---

## 2. 本轮对话的核心技术突破

我们在此轮对话中，针对 **“运行时交互断层”** 和 **“212px 极窄消息气泡排版拥挤”** 两个决定性的体验难题，进行了极其深度的重构与全链路闭环实现：

### ① P1-3 消息流动态抉择按钮支持（运行时）
*   **设计逻辑**：大模型在对话过程中生成的选项（例如 `<div onclick="send('选择1')">...</div>`）不能作为静态数据在转译期配置。
*   **实现机制**：我们在 **`packages/llm_ui_engine/lib/src/engine/ui_renderer.dart`** 中部署了运行期动态选项解析引擎：
    *   **提取与净化**：通过高鲁棒性的正则表达式动态抽离助理消息中的 `onclick` 指令与其对应的 Label 文本，并使用 `RegExp` 自动剥除 HTML 噪声及变空的自定义外层包裹标签（如 `<选项>`、`<choices>`），保持气泡正文 pristine 纯净。
    *   **回合活跃控制**：**只在当前最新一条 AI 消息（Active Turn）下方渲染原生交互按钮组**。往期的历史消息自动净化多余 HTML 标签，留存干净正文，完全防止了历史死选项被误触，保障交互流转顺畅。
    *   **回调接通**：在 `MessageFlowScope` 及聊天页挂载点补齐了缺失的 `onSendMessage` 消息发送回调，点击抉择按钮立刻将指令发送回对话流中，完美推进剧情。

### ② P2 自适应多页面多页签伴生控制台（转译期 ➔ 运行期）
*   **痛点**：消息伴生气泡（`extra_companion` 模式）的物理宽度被硬性限制为 **`212px`**。在此前版本中，17 个属性字段全部堆叠在一起，即便单列排布也显得极其冗长臃肿，毫无游戏卡设计的美感。
*   **重构设计**：
    我们直接动用了引擎的 **多页面与 `page_router` 联动机制**，将伴生面板重构为一个精致的 **多页签自适应控制台**：
    *   **分类分流**：卡片属性被自动划分为 3 个物理页面（Page 1 `📊 属性` 显示红/紫/绿/橙多彩进度条；Page 2 `📁 档案` 规整单列显示角色文本字段；Page 3 `🎯 选项` 专属放置原卡提取出的开局预设动作）。
    *   **原生 Tab Bar 切换**：每一页顶部动态画入三个微型 Tab 切换按钮。当前页面的 Tab 呈高亮主色，非当前页面通过透明的点击热区按钮与后台 `page_router` 连线接通，玩家点击页签，面板即可以极高水准的平滑动画来回跳转，空间释放达 300%！
    *   **外框高度完美对齐 (Auto Height Syncer)**：计算多页的最大高度打补丁，切换页签时面板大小绝对恒定。

### ③ 开场选择卡（Opening UI）的高密度大卡片整合
*   **优化设计**：之前的开场选择页只含孤立按钮，剥离出的欢迎词却被盖在底层遮罩中，缺乏沉浸感。
*   **整合机制**：我们在 `UiAssemblyBuilder._buildOpeningPage` 中，**在选项按钮正上方插入了一个带 15% 透明度的「开场叙述底板」卡片（高 110px，圆角 8px）**，将欢迎正文完美嵌套在里面，下方紧跟两列并排的居中大选项按钮，完美还原了酒馆一整块包裹聊天流的开端仪式感。

### ④ 术语全面汉化纠偏
*   全面清除了 `character_edit_page.dart` 和 `logic_branch.dart` 等所有用户可见地方残存的“主线”、“分支”、“主支路”等开发用词。
*   **统一汉化为 「开场白 1」、「开场白 2」、「开场白 3」** 等通俗用语，完全吻合创作者的心智。
*   在编辑器中，如果某个开场按钮启用了“确认并关闭”标签，会在实例属性下方动态渲染一个深蓝色的 **「选项点击行为配置卡片（Dropdown 选择框）」**，供作者手动指引此按钮点击后通往哪一条具体的开场白场景。

---

## 3. 血泪教训与设计避坑指南（新接手的人必读）

### ① 属性键错位杀手：`'text'` vs `'messageText'`（本轮致命踩坑）
*   **错误现象**：转译出的开场按钮或预设选项按钮点击后，回调触发了、正文提取也正确，但是点击后无法向 LLM 成功发送并推进剧情。
*   **原因剖析**：
    *   我们在转译器中，错误地将 button 要发送的消息写入了 `properties['messageText']` 键；
    *   但在 UI 引擎的逻辑层（`_resolveSendText`）中，对普通 button，它只认 **`properties['text']`** 键！
    *   这导致引擎读不到 `'messageText'`，无奈回落到了默认的按钮实例 ID（如 `'选项_1'`）并发送。聊天页在接收到 `'选项_1'` 时无法对齐场景，直接拦截，导致发送失效。
*   **修法**：已全部纠正为 `'text': message` 属性键，引擎得以完美读取并发送。

### ② 数据与模板的分离设计：状态栏是如何随开场白数值变动的？
*   状态栏（`extra_companion`）作为静态的视觉模板，**不为每个开场白独立维护多套状态栏视觉布局**。
*   **核心逻辑**：状态栏上的进度条只定义数据通道（指向 `sf_精神`）。
*   当玩家切换开场白（`_switchGreeting`）时，聊天页改写会话副本中的数值（例如将 `_sessionState.statusValues['sf_精神']` 从 84 改为 90）。
*   会话更新版本号，反向同步激活，进度条组件监听到新数值重绘，自动拉伸至 90%。这体现了**“数据驱动 UI”**的解耦精髓，极具架构优雅性。

---

## 4. 保留下一步待办（Roadmap）

### P3 引擎级「循环重复件 (Repeater / Dynamic Grid)」设计 (P2 阶)
*   **背景需求**：当 RPG 卡片中拥有像“背包道具栏”这种在对话中被 LLM 动态增删物品的容器时，由于绝对坐标布局无法计算动态网格的流式换行与块删除缩进，目前只能依靠 `AssemblyRichText`（HTML/CSS 自流排渲染器）执行展示。
*   **未来方案**：在后续的 `1.3.x` 阶段中，为引擎引入 `repeater` 逻辑原语：
    *   绑定 `boundArray`（如 `vars['bag']` JSON 数组）。
    *   作者设计好单格槽位模板（`itemTemplate`）。
    *   在运行时，引擎根据数组长度在内存中动态拷贝并排列物理位置，从而实现原生级、带“按动反馈/点击弹出详情 Overlay 弹窗”的动态网格物品栏。

---

## 5. 关键文件地图与类型速查

```
packages/llm_ui_engine/
  lib/src/engine/message_flow_scope.dart  <-- 拓宽注入 onSendMessage 发送回调
  lib/src/engine/ui_renderer.dart         <-- _MessageFlowList 动态选项抽取、正文净化及按钮渲染
  lib/src/widgets/ui_assembly_runtime_view.dart  <-- opening 模式下点击按键自动改写并套用 branchIndex

lib/pages/
  chat_page.dart                          <-- 挂接开场、伴生 mode 下的 onSendMessage 实发送回调
  character_edit_page.dart                <-- 重塑 _branchNameOf 生成器为「开场白 1/2/3」

lib/pages/character_assembly_page/
  logic_branch.dart                       <-- opening 模式下硬约束不分平级分支，主菜单改名「开场白 1」
  logic_editors.dart                      <-- 实例配置卡片设计、DropdownButtonFormField 废弃属性警告消除

ToolofPC/llm_card_converter/lib/core/
  regex_ui_extractor.dart                 <-- 提取欢迎正文 ex.cleanFirstMes 字段定义
  ai_visual_extractor.dart                <-- P2 AI 视觉主题分析提取器
  ui_assembly_builder.dart                <-- 伴生 UI (212px) 属性分页编译、Tab 按钮路由拼装
```
