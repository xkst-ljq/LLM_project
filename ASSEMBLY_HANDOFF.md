# Assembly 开发交接摘要

> 用于开启新对话时快速恢复上下文。
> 当前分支：`arena/019f9cee-llm-project`
> 当前远端同步到：本提交（`complete assembly override binding persistence`）

---

## 1. 当前已完成的阶段

### A2 基础版：已完成
已做：
- PCB 画布骨架
- PCB 高度可调、可保存、可恢复
- 资产栏基础拖放
- 复合组件限制在 PCB 内
- 越界兜底校验
- 非法返回保护
- 底部状态显示 PCB 尺寸 / 越界项

### A6 基础版：已完成
已做：
- `pagesJson` 多页面结构接入
- `AssemblyPage` / `AssemblyPageGesture` 模型
- 旧 `elementsJson` 兼容迁移
- 当前页面切换
- 图层面板基础版
- 主菜单固定化（不可改名、不可拖动）
- 平级页 / 叠加页显示
- 长按拖动同级排序
- 叠加页换父层：阶段性实现为“弹窗选择父层”
- overlay 页祖先层灰化显示

### A3-1：已完成
已做：
- `PropertyOverride`
- `AssemblyBinding`
- `AssemblyPage.propertyOverrides`
- 当前活动页的 `_activePropertyOverrides` 运行态容器
- 覆写容器的同步 / 清洗 / upsert / remove 辅助能力

### A3-2：已完成
已做：
- 复合组件实例点击选中
- 双击打开实例覆写入口
- 黑盒高亮 + `实例黑盒` 标签
- 覆写槽位创建 / 移除入口

### A3-3：已完成
已做：
- 基础覆写字段编辑器：
  - `text`
  - `progress.current`
  - `switch.value`
- 覆写值实时反映到当前实例显示
- 不影响模板，不影响其他实例
- 修复覆写项数实时刷新问题
- 修复覆写编辑弹窗在输入法未确认时的崩溃问题
- 修复 `PropertyOverride` 深拷贝时 `_Map<dynamic, dynamic>` 类型问题

### A3-4：已完成
已做：
- 覆写 patch 随活动页写回 `pagesJson`
- 切页 / 退出 / 重新进入时保留实例覆写
- 覆写入口区分“空槽位 / 字段覆写 / binding”状态
- 补最小 binding 挂载位编辑入口：状态键 / 字段类型 / 同步方向
- binding 保存到 `PropertyOverride.binding`，不影响模板

---

## 2. 当前推荐继续做的下一步

### A7 页面路由器最小版：基础版完成，测试通过
已做：
- 资产栏新增“页面路由器”逻辑组件
- 可拖入 `page_router` 逻辑节点
- 双击配置切换平级页 / 打开叠加页
- 目标页候选按当前层级过滤
- 点击路由器可在编辑态测试跳转
- 路由配置随页面元素保存

### A7.5 / A5-0 Assembly 资产区最小补全：基础版 + 体验收口完成，待本地测试
已做：
- 资产库改为底部分类栏 + 横向抽屉
- 分类包含：逻辑组件 / 基础交互 / 基础显示 / 复合组件
- 横向抽屉支持左右滑动浏览
- 底部抽屉拖出生成改为“向上竖直位移超过阈值”
- 资产栏打开时仍允许拖动画布
- HUD 改为顶栏下方左对齐紧凑胶囊
- 底部资产栏与横向抽屉改为半透明拟磨砂样式
- 资产抽屉高度、资产卡片与新拖入原子默认尺寸已压缩
- button 默认外观改为灰色框风格并去掉本体文字，linker 默认高度进一步压低
- 底部资产标题栏与展开抽屉合并为同一个悬浮窗式毛玻璃面板
- 最小开放：页面路由器、联动器、按钮、面板、文本、进度条、已暴露端口复合组件
- 当前 linker 只完成拖入 / 移动 / 保存恢复；接线能力归 A5 实现

### A4 暴露端口体验增强：基础回归完成，测试通过
已做：
- 用户反馈边轨 + 晶体方案与创作页认知不一致，已回退为旧版 / 创作页更接近的小圆点端口
- 端口颜色沿用 customColor 或子组件类型默认色
- 左侧输入 / 右侧输出仍按原位置显示
- Tooltip 显示输入/输出与子组件名称
- 边轨 / 晶体 / 大感应区方案后置，不作为当前默认样式

### A5 Assembly 内 linker 连线：配置式 MVP 完成，待本地测试
已做：

- 双击 Assembly 内 `linker` 可打开配置弹窗
- 可选择当前页面内 button 作为来源
- 可选择当前页面内 page_router 作为目标
- 保存为 `button.tap → linker → page_router.trigger`
- 编辑态点击已连接 button 可触发 page_router 跳页
- 可清除 linker 连接

### A8 运行时等比缩放与画布约束完善：基础版完成，待本地测试
已做：
- 新增 `UIAssemblyRuntimeView` 运行时渲染组件
- 运行时只允许等比缩放，禁止非等比拉伸
- 缩放公式：`scale = min(1.0, width / 360, height / pcbHeight)`，最多保持 1:1，不放大
- 清晰 PCB 通过 `FittedBox(BoxFit.scaleDown, Alignment.center)` 居中显示
- 空白区域用同一份 Assembly UI 的 cover 缩放模糊背景填充
- 保留 PCB 背景色、圆角、overlay 祖先灰化与实例覆写
- 背景模糊层 `IgnorePointer`
- Assembly 顶栏新增运行时预览入口
- 预览入口进入同页全屏预览态，不再使用悬浮弹窗
- 预览时顶栏 / 参数栏 / 资产栏 / 图层面板隐藏
- 返回键或右上角关闭按钮退出预览态
- A8-1 状态宿主修复：`UIAssemblyRuntimeView` 改为 Stateful，内部持有运行时页面副本
- 预览内接入 LinkerEventBus，slider / linker / progress 等运行时交互可触发整体刷新
- 模糊背景层使用运行时页面克隆副本渲染，不共享前景可变状态
- 当前预览跟随 `pcbColorValue / pcbRounded`，但 PCB 颜色与圆角编辑入口仍属后补 UI
- A8 后补风险：运行时交互组件、复杂复合组件内部 linker、超高 PCB 可读性、模糊背景性能仍需后续覆盖测试
- A8 回归重点：slider→progress、button→switch、input→text、select→text、timer→progress、math_node→text；base / overlay / overlay 的 overlay；窄屏 / 横屏 / 超高 PCB

### A9 页面手势配置 + 轻量动画：MVP 完成，待本地测试
已做：
- 图层面板页面条目新增手势配置入口
- 支持左滑 / 右滑 / 上滑 / 下滑
- 支持切换平级页 / 打开叠加页
- 目标页候选按层级过滤
- 手势保存到 `AssemblyPage.gestures`
- 运行时预览中识别清晰 PCB 区域内的全页 swipe 并切页
- 平级页默认 `base_slide`，表现为 slide + fade
- overlay route 暂只负责进入叠加页，overlay 专属动画依赖面原子 / 容器面，后续再完成
- 基础显示资产区已开放“面板 / 面原子”，默认尺寸对齐创作工作室 `160×80`
- overlay 页中第一个生成的面原子会自动标记为容器面，并按创作工作室一致的橙黄色外侧标签显示“容器面”
- Assembly 编辑态与运行时预览中，overlay 都会在祖先页与当前内容之间显示灰色半透明 PCB 蒙版
- Assembly 编辑态中，overlay 页没有任何面原子时，会显示橙色警告提示作者拖入“面板”作为弹层容器
- 运行时预览中点击 overlay 容器面外的 PCB 空白区域会返回父级页面
- opening 模式运行时暂不响应页面手势

### A9.5 通用模板基础版：A9.5-3 文档完成，待按样板回归
定位：A10 mode 差异化之前的前置阶段。先把所有模式共用的通用模板 / 通用运行时底座做稳，不急着分化 opening / scene / extra。

统一架构规则：
- 后续不为 opening / scene / extra_sticky / extra_companion 分别制作独立工作室。
- 所有模式共用 `CharacterAssemblyPage`、`UIAssemblyInfo`、`AssemblyPage`、`UIElement`、route、gesture、binding、实例覆写等模板数据结构。
- `mode` 是运行时外壳策略，不是不同工作室。
- 后续差异化应做成 runtime shell：OpeningRuntimeShell / SceneRuntimeShell / ExtraStickyRuntimeShell / ExtraCompanionRuntimeShell。
- 禁止把资产栏、PCB、多页面、route、gesture、binding 复制成多套 mode 专用代码。

A9.5-2 已开放基础原子入口：
- 基础交互：输入框、开关、滑块、下拉
- 基础显示：图片、状态点、分割线
- 默认落地尺寸参考 Studio，先保证能拖入 / 移动 / 保存 / 预览

通用模板样板建议：
- 主菜单 base
- 状态面板 overlay
- 设置面板 overlay
- 第二个 base 页

样板应验证：
- base 切换
- overlay 打开 / 空白关闭
- button → linker → page_router
- 页面手势
- 面原子容器面
- 运行时等比缩放
- 复合组件实例覆写
- binding 挂载位
- 内部 linker

A9.5-3 通用模板测试样板已写入 tracker。它是模板级集成测试，不是单点功能回归。重点验证多个已完成能力组合后是否稳定、不互相污染、不依赖临时入口。

样板结构：
- 主菜单 base
- 状态面板 overlay
- 设置面板 overlay
- 第二 base 页

专属测试要点：
- 完整制作流程：从空白 Assembly 到完成样板，不手改 JSON。
- route 与 gesture 共存：按钮路由与滑动手势指向同一目标时互不污染。
- 多 overlay 独立性：状态面板与设置面板互不串页。
- 页面重命名稳定性：route / gesture 绑定 page id，不受显示名变化影响。
- 组件状态隔离：不同 overlay 的 slider/input/select/switch 不互相污染。
- overlay 容器缺失修复流程：缺面警告、拖入面板后自动容器面、第二面不抢占。
- 运行时缩放完整性：普通高度、超高 PCB、窄屏、横屏均稳定。
- 无临时入口依赖：运行时只靠按钮、手势、空白点击操作，不依赖 page_router 本体点击。

样板重点验证：
- base 切换、overlay 打开、overlay 空白关闭
- button → linker → page_router
- 页面手势
- 面原子容器面
- slider → progress、button → switch、input → text、select → text
- 运行时等比缩放、实例覆写、binding 挂载位、内部 linker

A10 进入条件：
- 通用运行时预览稳定
- 通用模板样板完整跑通
- 常用基础原子可拖入 / 保存 / 预览
- overlay 容器面、蒙版、空白关闭稳定
- button/linker/page_router 与 gesture 路由稳定
- 至少一轮通用模板回归测试通过

### A9.5-5 Assembly 组件实例编辑器基础迁移：A9.5-5-1 ~ A9.5-5-4 全部完成，测试通过
目标：统一 Assembly 双击编辑语义，为后续数据通道内嵌做前置准备。

核心规则：
- 双击组件 = 编辑当前实例。
- 原子组件打开原子实例编辑器。
- 复合组件打开复合组件实例编辑器。
- Studio 编辑模板，Assembly 编辑实例，Assembly 默认不得回写资产库模板。
- 数据通道已在 A9.5-5-4 内嵌进组件实例编辑器，A9.6-1 的独立弹窗临时入口已移除。

迁移参考：
- Studio 已有画布内复合组件实例编辑器 `_showCompactCompositeEditorDialog`。
- 位置：`lib/pages/ui_studio_page/dialogs/compact_editors_dialogs.dart`。
- 该编辑器只修改当前画布实例快照，不污染资产库模板，适合作为 Assembly 复合实例编辑器参考。

A9.5-5-1 已完成：
- 双击普通原子打开实例编辑器。
- 第一批支持 text / surface / progress / button / line。
- 通用可编辑：实例名称、宽度、高度。
- text：文本内容、字号。
- surface：圆角、透明度。
- progress：最小值、最大值、当前值。
- button：按钮文字。
- line：方向、线型、粗细。
- 编辑器内保留“数据通道”入口作为过渡。

A9.5-5-2 已完成：
- 双击复合组件打开“复合组件实例编辑器”。
- 原有覆写入口已包装进实例编辑器。
- 新增实例信息区：模板名、实例 ID、所在页面、尺寸 / 位置。
- 保留暴露项覆写与 binding 逻辑。
- 新增数据通道占位区。
- 新增高级占位区，说明后续重置覆写、查看模板来源、另存为模板等能力。
- 明确只修改当前实例，不回写资产库模板。

A9.5-5-3 已完成（测试通过）：
- 第二批原子：input / switch / slider / select / indicator / image。
- input：占位提示、默认文本、最大字数。
- switch：默认开启。
- slider：最小 / 最大 / 当前值 / 步长，自动纠正非法区间。
- select：多行选项（`显示文本` 或 `显示文本|值`）、默认选中值。
- indicator：状态点直径、默认发光。
- image：网络地址、本地/内部资产路径、填充方式、圆角。

A9.5-5-4 已完成（测试通过）：
- 原子实例编辑器内嵌数据通道区（启用开关 + 全部策略字段 + 最终语义预览），随“保存”一起提交。
- 复合组件暴露项新增“通道”按钮，通道写入 `PropertyOverride.overrides['dataChannel']`。
- 已删除独立的 `_showDataChannelDialog` 临时入口。
- 共用方法：`_buildDataChannelFormFields` / `_resolveDataChannelName` / `_buildDataChannelPayload`。

### A9.6 SSOT / LLM 数据交互 MVP：A9.6-1 数据通道卡片 MVP 完成，待本地测试
定位：打通 UIengine 与会话状态、Prompt、LLM 回复之间的数据通路。目标链路为：

```text
UI 输入 / 选择 / 滑动
→ SessionState.vars 或 SessionState.statusValues
→ Prompt 注入
→ LLM 回复
→ 状态更新解析
→ UI 刷新
```

A9.6-0 已写入设计：
- SSOT 边界：`CharacterMeta.statusBarFields` 负责字段定义，`SessionState.vars/statusValues` 负责会话当前值。
- 默认交互采用“数据通道卡片”，不同时维护 LLM 节点、端口标记、绑定面板三套主入口。
- 数据通道卡片负责配置：数据名称、语义来源、保存位置、玩家可见性、LLM 读权限、LLM 写权限、更新应用策略。
- LLM 不接收裸值，必须通过 `semanticLabel / semanticPath` 注入，例如 `角色状态 / 好感度：45`。
- 语义来源优先级：手动名称 > 显式 Text 标签 > 父级容器标题递归 > 组件 name > 组件类型兜底。
- Binding 目标类型：`local_ui_state / session_var / status_field`，并支持 `targetId / pendingName / displayNameSnapshot`。
- 数据存在、玩家可见、LLM 可见、LLM 可修改互相独立，默认不发送给 LLM，也不允许 LLM 修改。
- 支持“LLM 不读取当前值，但允许给出增量建议”的隐藏状态场景。
- UI 原子写入 MVP：input/select 写 vars，switch 写 vars 或 statusValues，slider 写 statusValues。
- Prompt 注入：支持 `{{var.xxx}} / {{status.xxx}}` 或结构化 `[当前状态]` 段落。
- LLM 状态更新：预留 `status_updates / vars_updates` 结构化格式。
- 安全规则：UI 主动操作可直接写入；LLM 自动更新优先作为待确认建议。

A9.6-1 已完成 MVP：
- 顶层普通原子组件双击打开“数据通道”卡片。
- 支持名称来源：手动填写 / 文本标签 / 组件名称。
- 支持保存到：UI 内部状态 / 会话变量 / 状态字段。
- 支持玩家可见性、LLM 读策略、LLM 写策略、AI 更新应用方式。
- 保存到 `module.properties['dataChannel']`，并在画布上显示 chip。
- 当前不写 SessionState、不注入 Prompt、不做状态栏反向创建。

### A9.6-1 增强：状态字段名称匹配与 pendingName 预绑定（已完成，测试通过）
- `CharacterAssemblyPage(statusFields: ...)` 只读接收角色卡 `meta.statusBarFields`。
- 数据通道选择「状态字段」时实时提示匹配结果；命中写 `targetId` + 卡片字段类型，未命中记 `pendingName`。
- 进入 Assembly 时 `_reconcileStatusChannelBindings()` 双向对齐（后建字段自动补绑，字段删除回退待创建）。
- 待创建状态在画布 chip 与暴露项摘要中显示「状态待建」，橙色标识。

### A9.6-2：UI 写入 SessionState MVP（已完成，测试通过）
- 新增 `lib/services/ui_engine/data_channel_service.dart`，负责 UI → SessionState 单向写入。
- 可写原子：input / select / switch / slider（progress 只做显示，不作输入源）。
- `local_ui_state` 永不进会话副本；`status_field` 未匹配（pendingName）时跳过；数值字段按卡片 min/max clamp。
- `UIAssemblyRuntimeView` 新增 `sessionState` / `statusFields` / `onSessionStateChanged` / `showDataChannelDebug`。
- Assembly 预览用本地临时副本 + 顶部调试浮层，可验证但不落盘。
- 单测：`test/data_channel_service_test.dart`。

### A9.6-3：SessionState 注入 Prompt MVP（已完成，测试通过）
- 新增 `lib/services/ui_engine/data_channel_prompt_builder.dart`，在 `chat_page._buildFinalSystemPrompt()` 接线。
- 结构化注入 `[界面数据]` / `[可建议更新的隐藏状态]` / `[界面数据更新格式]`。
- 新增占位符 `{{ui.语义名}}`，受 `llmReadPolicy` 约束，不可读一律替换为空串。
- 安全红线：不注入裸值、local_ui_state 永不注入、pendingName 跳过、可写不可读只注入规则。
- 更新标签 `界面状态变化`，与状态栏 `状态变化` 区分。
- 单测：`test/data_channel_prompt_builder_test.dart`。

### A9.6-4：LLM 回复更新界面状态（已完成，待本地测试）
- 新增 `lib/services/ui_engine/data_channel_update_engine.dart`，`chat_page` 主回复链路接线。
- 解析 `<界面状态变化>` 块 → 权限校验 → delta + clamp → 按 applyPolicy 分流。
- `auto_low_risk` 直接应用；`confirm` 弹逐条勾选卡片；`never` / 不可写 / 未知名一律丢弃。
- `suggest_delta` 拒绝绝对值赋值；同项重复只取第一条。
- 重新生成 / 续写路径只剥离标记、不重复算账。
- 单测：`test/data_channel_update_engine_test.dart`。

#### 状态回滚（数据一致性）
- `messages.state_snapshot`（DB v4）存每条 AI 消息**结算前**的 SessionState 快照。
- 入库时必须「先取快照、后结算」，顺序颠倒会存成结算后的值，回滚就失效了。
- 删除消息时调 `_rollbackSessionStateFor()`，取最早那条的快照还原。
- 新增任何删除消息的入口时，记得一并接入回滚，否则状态又会残留。

#### 聊天页挂载 Assembly UI（A10-1/2）
- 统一入口 `ChatAssemblyMount`（`lib/widgets/chat_assembly_mount.dart`），
  新增其他 mode 时复用它，不要各自解析 `uiAssemblies`。
- 挂载时必须传 `sessionState` + `onSessionStateChanged`，
  否则反向同步（A9.6-5）不会生效，UI 不会跟着 LLM 的状态更新刷新。
- 折叠 / 隐藏时不要卸载 `UIAssemblyRuntimeView`，否则组件内部状态丢失。
- 空方案要跳过，否则聊天页会多出一块看不见的空白占位。
- **挂件必须关掉 `enablePageGestures`**：运行时那层全屏 `Listener`
  在 `translucent` 下会抢走内部 slider / 输入框的拖动手势。
  只有全屏类 mode（opening/scene）才需要页面滑动手势。
- 要让挂件可拖动，加独立的拖动把手，不要让整块内容都能拖——
  会和内部组件的手势打架。
- **手势竞技场的坑（踩过两次）**：聊天页根部有 `onHorizontalDrag*`（滑出侧栏）。
  专用识别器（HorizontalDrag）优先于通用识别器（Pan），**与嵌套深浅无关**。
  因此挂件内任何需要拖动的组件都不能用 `onPanStart`，
  必须用 `RawGestureDetector` 显式声明同类型识别器才能竞争成功。
- 写 `RawGestureDetector` 的识别器初始化回调时，用 `instance.onXxx = (d) {...};`
  块体逐条赋值，不要用箭头体 + 级联：回调返回 void 或其他类型时，
  级联会接到错误的对象上，报错信息还很有迷惑性。
- **可拖动浮层必须驱动 `Positioned` 的真实坐标，不要用 `Transform.translate`**。
  Transform 只移动绘制；命中测试自上而下先查父盒子边界，
  盒子没动就收不到触摸，表现为「拖走了样貌但点不到」。
- **「点击有效但拖动无效」= 竞技场竞争失败，不是命中测试问题**。
  命中不到的话点击也会失效；能点说明触摸到了，只是拖动被外层抢走。
  解法是让内层识别器在 `addAllowedPointer` 里立即 `resolve(accepted)`
  （见 `_EagerHorizontalDragRecognizer`），而不是继续调层级。
- **浮层拖动要用低阈值识别器**：默认 Pan 的 18px 阈值既不跟手，
  又会在等待期被外层 HorizontalDrag 抢走（时灵时不灵）。
  用 `_EagerPanRecognizer`（阈值 6px）抢先拿下竞技场。
  注意**不要**在 `addAllowedPointer` 里直接 accept——
  那会淘汰同竞技场的 Tap，「点击展开」就失效了。
- **挂件要自己吸收水平拖动**：聊天页根部有滑出侧栏的 `onHorizontalDrag*`，
  不吸收就会穿透触发。用 `deferToChild` 的空 `onHorizontalDrag*` 即可，
  内部更深层的组件仍能赢过它。

#### Stack 子节点的条件渲染（踩过一次）
`Stack` 的尺寸由**非定位子组件**决定。作为 Stack 直接子节点做条件渲染时：
- 要么 `if (cond) Positioned(...)`，隐藏时完全不加入 children；
- 要么**始终返回 `Positioned`**，用内部条件控制画不画。

绝不能在「Positioned」和「裸 SizedBox」之间切换——
后者会成为唯一的非定位子组件，把整个 Stack 压成 0×0，
表现为**整页黑屏**（开场白关闭后就这么炸过）。

#### 制作与预览严格分离（产品规则）
编辑器里**不执行任何联动效果**，包括页面跳转。
理由：编辑时的点击 / 拖动极易误触发，而组件运行时状态
（switch 开合、slider 数值、surface 动画戳）会被 `_persistAssemblyElements`
一并存盘，污染最终产物。得不偿失。
- 切页用图层面板，效果一律进运行时预览验证。
- 别再为了「方便」在编辑态加执行逻辑——这条已经试过并撤回。

#### Assembly 联动器
- 与 Studio **共用** `LinkerMatrixEngine` 的方案矩阵，不要各自维护一份。
- 新增方案时必须登记进 `_schemeRegistry`，否则 `isSchemeSelectable()`
  判为非法，运行端会静默跳过（`button_to_page_route` 就漏登记过）。
- Assembly 没有拖拽连线，端口由方案 id 推导；运行端按 `scheme` 分发行为，
  端口只需自洽即可。

#### 状态字段归属（owner）
- `owner`（player/char/neutral）决定注入 Prompt 时的主语。
  没有主语时 LLM 无法判断增减方向——实测商贩剧情里玩家花钱被写成 `+600`。
- 只有**显示文字**用 `qualifiedName`；标签里的键必须是原始 `name`，
  否则 `applyFromReply` 匹配不上，解析会全部失效。
- 想让角色也有自己的属性，就再建一个 `char` 归属的字段。

#### SSOT 归属规则（架构约束，不要违反）
状态字段可能同时被状态栏和 UI 数据通道引用，但**同一字段只能由一套机制注入与解析**：
- `targetKind == 'status_field'` → 一律由 `StatusBarEngine` 负责，用 `<状态变化>` 标签。
- `targetKind == 'session_var'` → 由 `DataChannelPromptBuilder` / `DataChannelUpdateEngine`
  负责，用 `<界面状态变化>` 标签。
- 数据通道里配的读写策略通过 `collectStatusFieldPolicies()` 传给状态栏执行，
  否则「可写不可读」会被状态栏的注入从侧面绕过。

违反这条会导致：同一字段注入两次、模型面对两个标签两套格式而不执行，
以及隐藏值泄漏。这个坑已经踩过一次，见 TRACKER 对应章节。

#### 遵从度调优记录（重要经验）
`<界面状态变化>` 这类结构化输出，格式约束的措辞直接决定成败：
- 不要写「无变化则不输出该块」——模型会每回合判定无变化，永远不输出。
  应要求每回合都输出标签，无变化时输出空标签（引擎侧对空块做了安全处理）。
- 格式约束要放在 PHI（对话历史之后），不要只放 system prompt 开头。
- 沉浸式扮演场景可再加一行贴在 user 消息尾部的短提醒作为补强。
- 解析侧要容错代码围栏 / 全角尖括号 / 标签内空格，语义对了就不该因格式丢弃。
- **不要假设「一行一项」**：模型经常把多项写在同一行，而文本字段的取值贪婪到行尾，
  会把后面的数值项整个吞掉（表现为「好感度的增量跑到心情上去」）。
  解析前必须用 `StatusBarEngine.splitSegments()` 按已知字段名切分。
- **格式示例里不要写具体数值**，模型会当标准答案每回合照抄，造成数值漂移；
  示例应使用空标签块。格式占位符（如 `名称:+N`）不受影响，可以保留。
- 「每回合必须输出」和「不要过度触发」是一对平衡，必须同时说：
  先立「空结算是常态」的预期，再给判定门槛（拿不准就不写）和幅度约束。
- 设计取向：宁可漏报也不误报。漏报只是少一次更新；
  误报会数值失控，且用户每次都要处理确认弹窗。

### A9.6 状态：全链路联调已通过
UI 交互 → SessionState → Prompt → LLM → 解析算账 → 确认 → 状态栏刷新，
以及撤回消息时的状态回滚，均已实测通过。

### A9.6-5 反向同步（已完成，待本地测试）
- `DataChannelService.applySessionToElements()` 把会话副本回填到组件。
- 与 `readModuleValue()` 严格互逆，往返一致性有单测守——
  两个方向取值口径不一致会造成静默丢值，改动任一侧都要同步另一侧。
- 触发点：`initState`（首帧显示真实状态）与 `didUpdateWidget`
  （外部 sessionState 被替换时刷新）。
- `local_ui_state` 与未匹配的状态字段不回填。
- **当前只在 Assembly 编辑器预览里生效**：`UIAssemblyRuntimeView` 全项目仅此一处调用，
  聊天页还没有渲染 Assembly UI（只读取数据通道配置注入 Prompt）。
  聊天页挂载属于 A10 范围；A10 做完后传入 `sessionState` /
  `onSessionStateChanged` 即可让反向同步在真实会话里生效。

### A10 进度：A10-0/1/2 完成并测试通过
常驻 UI 已能在真实聊天里显示、拖动、交互，并与 SessionState 双向同步。
A9.6 的完整闭环至此在真实会话中跑通：
LLM 更新状态 → SessionState → 常驻 UI 组件刷新；
玩家操作组件 → SessionState → 状态栏与 Prompt。

剩余：A10-3 伴生 / A10-5 场景（A10-4 开场白已完成待测）。
A10-1 的挂载基础设施可直接复用，主要工作是各自的形态差异。

### 待后期统一处理的优化（用户已提出，暂缓）
1. **长按 PCB 拖动挂件**（取代内置拖动把手）—— 方案已定，待实现。

   用户决策：不用「空白区域拖动」，改为**长按后拖动**。
   理由：空白区域随作者摆放而变化，摆满组件后就无处可拖；
   长按则在任何位置都可用，也不会与普通点击 / 滑动打架。

   **必须排除 button 控制的区域**（用户特别指出）：
   button 自身有 `long_press` 事件（`ui_renderer.dart` 会
   `emit(elementId, 'long_press')`，作者可用它接 linker），
   两者会直接冲突。排除范围要包含**复合组件内部的 button**，
   不能只看顶层元素。

   实现要点：
   - 命中检测需要递归遍历元素树，判断长按落点是否在任一 button 的
     矩形范围内（注意元素可能有 rotation，以及运行时的等比缩放换算）。
   - 拖动手势仍要处理与 slider 抢占式识别器的竞争，
     参考 `_EagerPanRecognizer` 的做法。
   - 完成后即可开放 `UISemanticRole.dragHandle` 角色，
     或直接移除内置把手。

   当前状态：仍使用内置拖动把手（左上角 `⤧`），功能正常。
2. ~~**用 button 语义标记实现折叠 / 退出 / 确认**~~ —— 已在 A10-2.5 完成。
   要点：**一种 mode 只有一个关键职责**，作者只需点亮一个标签，
   不要做成「所有 UI 共用一组角色下拉」（初版这么做过，是过度设计）。
   新增 mode 时在 `ui_semantic_role.dart` 里补 `actionLabelOf` /
   `missingHintOf` / `colorOf` 三处即可。
   拦截分级：接管型（opening/scene）缺标记就不执行；
   常驻只提示并保留内置兜底按钮。
   方向正确，符合「作者用通用组件表达意图」的原则。
   暂缓原因：需要新增一套语义标记机制（类似 `is_overlay_container`），
   涉及数据模型、编辑器入口、运行时识别三处；
   而 scene 的退出、opening 的确认也需要同一套能力，
   一起设计比分三次做划算。

### 下一步建议
- 「根据剧情自动判断状态变化」的效果验证：
  当前只验证了「用户明确要求修改」，自动判断的准确度与触发频率还没系统性测过。
  测之前建议先固定一组剧情样本，否则结果不可复现。
- 仍不要进入 A10 mode 差异。

---

## 3. 已确认的产品规则（不要丢）

### 3.1 PCB / 前后台规则
- **复合组件在所有模式下都不允许放在 PCB 外**
- PCB 外未来只允许：
  - `linker`
  - `math_node`
  - `timer`
  - 显式标记为后台的原子组件

### 3.2 红框使用规则
- 红框保留，但主要用于**异常非法状态兜底**
- 不作为常规拖动反馈的最终方案

### 3.3 后台原子创意（重要，后续再做）
> 对允许后台化的原子组件：
- 靠近 PCB 内壁时自动吸附在边界内侧
- 再继续往外拖超过第二阈值后，脱离吸附并切换为后台
- 避免长期停留在“半进半出”状态

这是一个保留创意，**当前不做**，但后面实现原子资产库时要记得。

### 3.4 图层面板规则
- 选中某图层后，**图层面板不要自动关闭**
- 点击空白区域才关闭
- 主菜单固定为第一平级页，不允许改名和拖动
- 自动拖动换父级先不做；当前阶段性实现是“弹窗选择父层”

### 3.5 Binding 名称解析与预绑定规则
- 普通创作者不应被要求手填内部 ID。
- Binding 入口后续应优先输入 / 搜索“状态块名称”或“变量显示名”。
- 若匹配到已有状态栏字段，系统保存其内部 `id`；之后改名不影响绑定。
- 若未匹配到状态块，允许保存为“预绑定名称”，并显示未解析警告但不阻止。
- 后续进入状态栏编辑页新建状态块时，应提示这些预绑定名称；选择后自动填入名称，并在创建后把预绑定更新为内部 id 绑定。
- 该机制不阻塞 A7，但在状态栏 / SSOT / Prompt 通路真正接入前需要实现。

### 3.6 页面路由器触发规则
- A7 阶段的 `page_router` 本体点击跳转只是临时编辑态测试入口，A5 后已退场。
- 页面切换应通过 `button → linker → page_router` 触发。
- `page_router` 本体长期应作为编辑器可见、运行时隐藏的后台逻辑节点。
- `page_router` 本体保留双击配置与拖动，不再承担点击跳转。

### 3.7 资产库底栏 / 横向抽屉方案
- A7.5 / A5-0 已完成底部分类栏 + 横向抽屉基础版。
- 分类：逻辑组件 / 基础交互 / 基础显示 / 复合组件。
- 点击分类标题后弹出横向抽屉，可左右滑动；点击其他分类切换，点击同分类或画布空白关闭。
- 底部横向抽屉不遮住顶部标题栏。
- 拖出生成逻辑已从“水平位移阈值”改为“竖直向上位移阈值”，避免和横向滑动浏览冲突。
- 当前 HUD 已移到顶栏下方左侧紧凑显示；后续仍需正式美化 / 折叠 / 合并到底栏。
- 参数 HUD 在图层面板 / 资产面板等遮挡场景下，后续应加入淡化消失与恢复动画。

### 3.8 页面手势与路由动画规则
- A9 MVP 中页面手势作用于整个 PCB；局部 `gesture_zone` 热区后置。
- 手势只在运行时预览中生效，不影响 Assembly 编辑态。
- 同一页面同一方向只保留一个手势。
- 手势路由复用 page_router 的 route 规则：切换平级页 / 打开叠加页。
- 平级页默认 `base_slide`，表现为 slide + fade。
- overlay route 暂只负责进入叠加页；overlay 专属动画依赖面原子 / 容器面和遮罩层，后续再完成。
- 面板 / 面原子是 overlay 容器与空白点击返回父级的基础。
- 后续再开放更多动画类型和手势优先级规则。

---

## 4. 当前临时测试/调试信息

这些不是最终产品 UI，后面要评估删除：

1. 底部状态里的 `覆写 N 项`
2. 复合件选中态的 `实例黑盒` 标签

### 建议删除时机
- A7 开始后继续评估
- 原则：一旦正式 UI 足够表达这些信息，就删掉临时调试信息

---

## 5. 协作节奏（非常重要）

后续继续开发时，遵守以下规则：

- 每一步按 MVP 做，不一次性做太多
- 每一步完成后：
  1. commit
  2. push
  3. 本地测试
  4. 收集反馈
  5. 再进入下一步

### 问题处理原则
- **小问题**：优先并入下一步一起修，不打断节奏
- **严重阻塞问题**：单独修复并 push

---

## 6. 关键文件

### 已在仓库中的文档
- `ASSEMBLY_IMPLEMENTATION_TRACKER.md`  
  施工跟踪档案，记录阶段状态 / MVP / 灵感池 / 调试信息清理规则

### 关键代码文件
- `lib/models/ui_assembly_info.dart`
- `lib/pages/character_assembly_page.dart`
- `lib/pages/character_assembly_page/logic.dart`

---

## 7. 最近关键提交

- `e88a476` fix assembly override editor ime handling
- `4c3a978` add assembly basic override field editors
- `a73ea28` refresh assembly override count immediately
- `901d9cc` fix assembly property override map cloning
- `39774fc` add assembly composite override entry interaction
- `f70d9b7` add assembly property override model foundation
- `eb7a137` fix assembly move-parent icon
- `649248d` refine assembly hierarchy editing behavior
- `541328a` refine assembly layer panel interactions
- `4ad2b78` add assembly page model and layer panel basics
- `0422552` add assembly pcb sizing and bounds validation

---

## 8. 新对话里建议直接说明的话

可以在新对话一开始直接说：

> 继续 `ASSEMBLY_HANDOFF.md` 的上下文，当前分支是 `arena/019f9cee-llm-project`，A2/A6/A3-1/A3-2/A3-3/A3-4/A7/A7.5/A5-0/A4/A5/A8/A9 已完成，A9.5 通用模板基础版规划、A9.5-2 基础原子入口、A9.5-3 通用模板测试样板文档已完成，A9.6-0 SSOT / LLM 数据交互设计文档与 A9.6-1 数据通道卡片 MVP 已完成，A9.5-5-1 原子实例编辑器第一批已完成，A9.5-5-2 复合组件实例编辑器迁移已完成待本地测试。通过后进入 A9.5-5-3 原子实例编辑器第二批。请遵守每一步完成后 commit/push、非阻塞问题并入下一步处理的节奏。
