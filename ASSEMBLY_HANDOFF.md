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

### A10 进度：A10-0/1/2/4/5 完成并测试通过
剩 A10-3（extra_companion 伴生）未做。

#### scene 接管的两条硬规则（A10-5 测试后确立）

**a) 接管 = 停止渲染，不是 IgnorePointer**
`IgnorePointer` 只禁交互，元素仍然可见。scene 语义是「顶替聊天页」，
状态栏、消息列表（含头像与气泡）、输入栏都必须**不渲染**。

**例外：常驻 UI（extra_sticky）不隐藏，且要叠在 scene 之上。**
初版把它一起隐藏了，理由是「场景已是完整界面，挂件语义重复」——判断错误。
常驻挂件是始终可用的工具层（背包、快捷面板），场景再全屏也不该埋掉它。
主 Stack 顺序：scene → 常驻 UI → 开场白。
聊天背景图保留，另加 `alpha: 0.32` 压暗蒙版——
背景是场景观感的一部分，不要做成不透明。

**b) 接管层要跟随设置面板一起左移**
设置面板在「聊天主体 + 右侧面板」那个 `Positioned` 内部，
而 scene 层排在它之后，不同步位移就会把面板整个盖住。
同时主体的 `IgnorePointer` 要写成
`_sceneTakesOver && _animController.value < 0.5`，
否则进了设置页所有条目都点不动。

#### 取作用域必须用 Builder（通用规则，踩过一次）

在 `build` 里包了 InheritedWidget 之后，子树读取该作用域
**必须用 `Builder` 拿新的 context**，不能沿用外层的 `context`——
外层 context 位于 InheritedWidget 之上，
`dependOnInheritedWidgetOfExactType` 永远返回 null。

`ui_assembly_runtime_view.dart` 的 `_buildRuntimeElement` 就栽在这里：
消息流永远读不到 `MessageFlowScope`，一直显示占位示例。
同理适用于 `UILinkerSnapshotScope` / `UISceneModeScope`。

配套原则：**运行时的兜底不能是假数据**。
编辑器（`isStudio`）显示示例消息是为了让作者看排版；
运行时拿不到数据只能显示「暂无消息」，绝不能让玩家看见假对话。

#### scene 内禁用页面级横向拖动

聊天页根部「右滑打开设置」与 PCB 翻页手势方向相同，必然误触。
**设置页的唯一入口收敛为「打开聊天设置」关键职责按钮。**
做法：scene 层最外层 `GestureDetector` 用空实现吃掉 `onHorizontalDrag*`。
子级 HorizontalDrag 赢过根部同类识别器从而截断冒泡；
PCB 内部翻页走 `Listener`（不参与竞技场），不受影响。

### A10 已全部收口（0/1/2/2.5/3/4/5 均测试通过）

#### 伴生 UI（extra_companion）的三条设计约束

**a) 内嵌进气泡，不是浮在气泡下面的独立层。**
与正文同属一个气泡容器。这样撤回 / 删除消息时，
该消息携带的数据记录一并消失，不需要任何清理逻辑。

**b) 只有最新一条 AI 消息可交互。**
历史实例仍渲染（否则翻看历史会看到一堆空气泡），
但 `IgnorePointer` + 0.55 透明度。
所有实例共享同一份 `SessionState`——允许操作历史实例
等于让玩家回到过去改当前状态。

**c) 宽度必须塞进气泡：`companionMaxPcbWidth = 212`。**
由气泡尺寸倒推（`360 * 0.7 - 20 - 20`）。
用 `UIAssemblyInfo.maxPcbWidthFor(mode)` 而非全局上限。
编辑器手柄 / 挂载 / 运行时各 clamp 一次，兜住约束加入前的旧数据。
高度不限——内容长了由气泡撑高，随列表滚动，天然「跟随滚动」。

#### mode 互斥要双向拦截

scene 与 extra_companion 互斥（scene 不渲染消息列表，伴生没有宿主）。
曾只拦了单向，导致「先做伴生再加 scene」能造出无效组合。
**新增互斥关系时记得两个方向都补。**

数据层**不做删除**：已有卡片不该因规则变化被静默删掉方案，
只在运行时用条件判断兜底。

### A13 已全部收口（1/2/3 均测试通过）

玩家可在 UI 里填写角色档案、分配属性点，数据进会话副本、
以 `[玩家档案]` 段注入 systemPrompt 层级。**做进通用模板，所有 mode 可用**
（用户要求，不限定 opening）。

#### 三条不要违反的规则

**1. 只写会话副本，绝不改角色卡。**
角色卡可分享，玩家 A 填的内容不能带给玩家 B；
清空聊天记录即回到作者的原始设定。

**2. 玩家未填时整条不注入。**
不能覆盖成「（未设置）」——那会把作者写的默认设定抹掉。
档案项的语义是「玩家做出的选择」，没选就让母版继续生效。

**3. 冲突时以玩家档案为准，且要在措辞里明说。**
仅靠分段顺序不足以让模型知道该听谁的。

#### 配额分配的白名单标准（两边正好相反）

- **来源 = 玩家改不了的组件**（text / progress / math_node）。
  总量能被玩家自己改，配额约束就失去意义。
- **目标 = 玩家能操作的组件**（slider / input）。
  progress 没有任何手势，作分配项纯属摆设。

初版两头都放宽了，是同类错误的两个相反方向。

#### 渲染函数只读不写（重要）

配额归零最初写在渲染时，需要一个「是否已初始化」的持久标记，
而它会被 `_persistAssemblyElements` 存进角色卡——既污染产物，
又导致作者事后改初始值不再生效。
改为**在配置连线时归零**。这条对整个 UI 引擎都成立。

#### 数据流向反过来的方案要改三处

`pool_to_allocation` 是**源被目标影响**（拖分配项 → 池子剩余数变），
而引擎默认「源驱动目标」。首轮测试暴露的问题全部源于此：
- **取值**：`_poolTotalOf` 要读源组件自身内容（不是渲染后的显示串，
  否则每帧递减）；
- **刷新**：`initEventBusListener` 只认 `srcId == 事件源`，
  需为该方案补一条 `tgtId == 事件源` 的分支；
- **渲染**：编辑态分支也要单独处理，别只改运行态。

### A14-1 画布元素操作（已完成，测试通过）

选中 + 左侧操作栏（半锁 / 全锁 / 复制 / 上移 / 下移 / 删除）。

#### 几条不要再踩的坑

**1. 加画布操作前先确认有没有「选中态」。**
Assembly 原本只有 `_selectedCompositeId`，且仅用于展开复合组件的
覆写槽位——**原子组件根本没有选中状态**。
盘点时只对比「有没有删除功能」会漏掉这个前提。

**2. 锁定用模型已有的 `layoutLocked` / `sealed`，不要自造字段。**
Studio 侧一直在用这两个。自造 `properties['locked']` 会导致
方案在两个编辑器间迁移时锁定状态丢失。
- `layoutLocked`（半锁）：位置 / 形变 / 旋转
- `sealed`（全锁）：以上 + 联动连线（连不上、不可断开、配置时跳过）

**3. 复制元素必须走 `jsonEncode/Decode`。**
`_deepCloneValue` 对嵌套 Map 返回 `Map<dynamic, dynamic>`，
而 `UIElement.fromJson` 里 `json['offset'] as Map<String, dynamic>?`
是硬类型转换，会直接抛 `_TypeError`。
另外 `UIElement.copyWith` **不接受 id**（final），要在 JSON 层换。

**4. 层级顺序：`_elements` 越靠后越上层，「上移」= 索引 +1。**
很容易写反，有测试守着。

**5. 删除要连带清理联动器与覆写槽位。**
悬空连线在运行端表现为「配了但没反应」，比直接删掉更难排查。

**6. 选中框用 `DashedSelectionBorderPainter`（按组件形状描边）。**
放在 `services/ui_engine/`，Studio 的 `painters.dart` 是
`part of`，Assembly 导不了，但两边选中框必须一致。

#### 布局：不要照搬 Studio 的两侧悬浮按钮

Studio 有 10 个按钮分列画布左右。Assembly 不行——
PCB 有固定边界且作者要频繁贴边摆元件，两侧会压住工作区；
PCB 的形变把手又在右侧与下侧，**左侧是唯一空闲的边**。

两档锁定共用一格、全锁**向右**展开：向下插入会把下方按钮整体推移，
手指刚点完半锁，复制键就跑到了原本删除键的位置。

### Studio 与 Assembly 的分工（A14-3 前确立，重要）

用户提出的顾虑：**不能把 Studio 的工作全搬进 Assembly**，
否则 Studio 就没有存在意义了。这条约束优先于「对齐 Studio」。

分工线：

> **Studio = 造零件**（组件的内在行为规则）
> **Assembly = 装机器**（这个零件放哪、填什么、接什么数据）

| 能力 | Studio | Assembly | 依据 |
|---|---|---|---|
| indicator 状态规则引擎 | ✅ | ❌ | 颜色怎么随数值变，是零件自带的行为 |
| 组件精细外观规格（材质 / 光晕 / 主题色） | ✅ | ❌ | 设计零件时定好 |
| select 选项列表 | ✅ | ✅ | **内容**随剧情而定（「向左走 / 向右走」），不是组件设计 |
| 文本内容 / 图片来源 | — | ✅ | 同上，属于「这一个实例填什么」 |
| 实例名称 / 尺寸 / 位置 / 旋转 | — | ✅ | 装配行为 |
| 数据通道 / 联动 / 语义标记 | — | ✅ | 装配行为 |

判定口诀：**改的是「这个零件是什么」→ Studio；
改的是「这一个实例在这张卡里怎么用」→ Assembly。**

因此 Assembly 的实例编辑器**不必也不应**追平 Studio 的行数。
A14 盘点里「Studio 2900 行 editors vs Assembly 一个通用对话框」
这个对比，不能直接当成缺口来补。

### button = 点击热区，不是控件（A14-3 第三步确立）

**button 在运行期完全不显形**，`_buildButton` 直接返回
`SizedBox.expand()` 包在手势 Listener 里。
玩家看到的按压反馈，一律由它联动的 surface 表现
（`click_to_surface_press` / `click_to_surface_ripple`）。
编辑期才画灰色区域 + `touch_app` 图标，让作者知道热区在哪。

推论，改代码时不要违反：

1. **不要给 button 外观编辑**（不在 `_supportsAppearanceEditor` 名单）。
   它不显形，调颜色圆角是白忙。
2. **不要给 button 加文案**。`text` / `showTextOnRuntime`
   是早期遗留，已废弃并在保存时主动 remove。
3. **触发手势属于连线，不属于按钮**。见下条。

### 手势用连线的 sourcePort 表达，不用方案 id（A14-3 第三步）

运行端 `LinkerService.initEventBusListener` 按
`'tap'` / `'double_tap'` / `'long_press'` 三个 `sourcePort` 分派事件。
因此 Assembly 的联动器配置页在来源是 button 时多一栏「触发手势」，
**只覆写 sourcePort**，运行端无需改动。

两条不要走的岔路：

* **不要为「双击触发某某」单开方案 id** —— 方案矩阵会翻三倍，
  且仍做不到「同一按钮三种手势并存」。
  `_schemeSourcePort` 里的 `double_click_` / `long_press_`
  前缀分支是闲置预留，矩阵中并无此类方案。
* **不要在按钮上选「当前手势模式」** —— 那正是被废弃的
  `active_gesture`：一个按钮只能有一种语义，
  还得靠隐藏其他连线来实现，远不如三条连线并存。

覆写守卫：仅当**来源类型为 button 且方案推导端口为 `tap`** 时生效，
防止将来给 button 加值型方案时被手势串改端口。

手感参数 `doubleTapIntervalMs` / `longPressThresholdMs`
归实例编辑器（是按钮的调校，不是某条连线的），
且只在该按钮确实有非单击连线时才显示。

### 死代码要顺着数据流验证，不能只看有没有 UI（A14-3 第三步教训）

Studio 的「手势触发模式」下拉存在已久、界面完整、
还配了「手势通道连接状态」的三色指示灯，看起来很正经，
实际上 `props['active_gesture']` **全仓无人读取**——
作者选了「长按触发」，运行时仍然是单击。

同类的 `showTextOnRuntime` 则相反：它**确实被渲染端读**，
但它控制的功能本身就不该存在。

教训：判断一个字段是否有效，要从**渲染端 / 运行端往回查读取方**，
不能看编辑器里有没有入口。两者都属于
「不影响就留下了」的遗留，越留越难分辨哪个是真功能。

### 连线配色是跨编辑器契约，不能各画各的（A14-4）

Studio 与 Assembly 的连线**必须共用同一套颜色语义**：
接收线青 `0xFF00ACC1` / 输出线绿 `0xFF66BB6A` /
算数操控线橙 `0xFFFFB300` / 复合件粉 `0xFFFF4081` 与浅蓝 `0xFF4FC3F7` /
命中高亮 `0xFF00E676`。

同一条连线在两个编辑器里如果是两个颜色，作者无法建立肌肉记忆，
「对齐 Studio」的意义就丢了一半。

因此 `LinkerConnectionPainter` 与 `LinkerLineColors` 提取到
`services/ui_engine/linker_connection_painter.dart` 共用，
**不要在任一侧另写一份**。

Assembly 画布更挤（PCB 最窄 212），缓解办法是
**减小线宽（2.5→1.4）、降低不透明度（1.0→0.55）、缩小箭头（9→6）**，
不是换颜色。

`LinkerLineColors.resolve` 的优先级
**控制线 > 复合件 > 普通输入/输出** 不能调换：
接入 `gate_in` 的线即使一端在复合件里，也应显示为控制线。

### Assembly 的画布坐标要叠加两个偏移（A14-4 易错点）

Studio 的元素屏幕位置 = `_workspaceOffset + el.offset`。

Assembly 的元素坐标是**相对 PCB** 的，屏幕位置 =
`_canvasOffset + _pcbOffset + el.offset`（见画布里每个元素的
`Positioned`）。算连线端点、命中检测时漏掉 `_pcbOffset`，
整层会错位一个 PCB 的距离。

连线层要插在**元素之下、PCB 之上**：
压在元件上会挡住文本与消息流内容，放到 PCB 之下会被底色整块盖掉。

### IgnorePointer / Opacity 之类的代理盒不能包在 Transform.rotate 外层

**这是 Studio 旋转把手「失效」的真凶，会反复回归，务必记住。**

`RenderTransform.hitTest` 特意**不检查自身尺寸**，而是把落点做逆变换后
直接交给子树——这正是元件旋转后仍能被点中的原因。

但 `IgnorePointer`（以及 `Opacity`、`ColoredBox` 等普通
`RenderProxyBox`）会执行 `_size.contains(position)` 这一步
**轴对齐**边界检查。一旦它包在 `Transform.rotate` 外层，
这个检查就发生在**旋转后**的坐标系里，而它的 size 仍是未旋转的 W×H。

后果：右下角的形变/旋转把手一旦转出那个未旋转的盒子，
点击就在最外层被判未命中，把手看起来像「失效」了。

实测（240×100 的节点，把手在右下角）：

| 角度 | 把手是否仍在未旋转盒内 |
|---|---|
| 0° | ✅ |
| **15°** | ❌ 已经出界 |
| 30° / 45° / 90° | ❌ |

**15° 就失效**，与用户「旋转一定角度后把手就失效」的描述完全吻合。

正确写法是把代理盒放到 `Transform.rotate` **内层**：

```dart
Transform.rotate(
  angle: ...,
  child: IgnorePointer(ignoring: ..., child: rootTree),
)
```

这样边界检查发生在旋转**前**的局部坐标系，把手永远在盒内，
而 `ignoring` 的语义完全不变。

同理，画布里那个 `Positioned(width: el.size.width, ...)`
也是未旋转尺寸，但 `Positioned` 不做命中裁剪，
`Stack` 用的是 `clipBehavior: Clip.none`，所以它不是问题；
**问题只出在带边界检查的代理盒上**。

排查提示：症状是「旋转后能看见但点不到」时，
先从最外层往里数一遍有没有 proxy box 抢在 Transform 前面，
不要先怀疑坐标计算——坐标往往是对的。

### 连线端点画在元件边缘，不是端口圆心（A14-4，别「修」它）

用户问「删掉提示圆点后，接线端点在哪，逻辑上会不会有偏移」。核实结论：

**垂直方向零偏移。** 渲染器的 linker 端口是
`Positioned(top: (size.height - portSize) / 2)`，圆心 y = height/2；
`_assemblyPortOffset` 取 `elTop + height/2`，精确重合。

**水平方向差 13.5px，且是刻意的。** 渲染器把端口内缩了 6px
（`Positioned(left: 6)`，portSize=15），圆心 x = 13.5；
而连线端点取元件**边缘** x = 0。

照搬 Studio 的 `_resolvePortGlobalOffset`，两边一致；
观感上也更合理——接到圆心会让线有一截压在元件内部、
从圆点底下穿出来。**看到这个差值不要当成 bug 去「修」。**

### 各组件的 portSize 不是同一个值（我在这里算错过一次）

| 组件 | portSize | 出处 |
|---|---|---|
| linker | **15.0** | `ui_renderer.dart` 第 1318 行附近 |
| math_node | **9.0** | 第 1470 行附近 |

我曾用 linker 的 15.0 去算 math_node 的 gate 口，得出圆心 y=10.0、
误判「与代码里的 7.0 差了 3px」，还据此让用户做了选择。

正确算法：`top: 2.5 + 9.0/2 = 7.0`，与 `_assemblyPortOffset` 里
gate_in 用的 `elTop + 7.0` **完全一致，零偏差**。

教训：跨组件引用常数前先确认它属于哪一段作用域，
`ui_renderer.dart` 里同名的 `const double portSize` 有多个。
相关断言已固化在 `assembly_linker_wire_test.dart`
的「端点与渲染器实际端口的对应关系」组。

### 改尺寸必须同时修正 offset，否则旋转后图形乱窜（A14-1g）

`Transform.rotate` 绕**中心**旋转，而 `UIElement.offset` 定义的是
**左上角**。改尺寸时若只动 `size` 不动 `offset`，中心会跟着移动，
旋转后的图形等于绕着一个正在移动的中心转——用户描述为
「形变没有锚点，图形会到处跑」。

**未旋转时中心也在动**，只是增长方向恰好与屏幕轴对齐、
左上角看着没变，所以这个 bug 长期没暴露。

修法：让把手对角（局部左上角）在屏幕上保持不动，反推 offset。

```
anchor    = offset + (w/2, h/2) + rot(-w/2, -h/2)
newOffset = offset - (dW, dH) + rot(dW, dH)
            其中 dW = (nw - w) / 2, dH = (nh - h) / 2
```

0° 时 `rot` 是恒等变换，两项抵消、offset 不变，向后兼容。

两边实现方式不同但**必须等价**（变换是线性的，增量可叠加）：
* Assembly：每帧以**当前**尺寸为基准增量修正
  （用起点尺寸会把偏移重复累加）
* Studio：以拖动起点快照一次性修正

`resize_handle_test.dart` 里有一条专门断言两者结果一致，
以免日后两边手感分叉。

**排查提示**：凡是「旋转后位置不对」的问题，先分清是
*旋转中心*还是*形变锚点*——这是两码事。
A14-1g 第一轮我验了「四周等量扩张所以旋转中心不变」，
那句话本身没错，但完全没覆盖形变锚点，于是漏掉了这个 bug。

### 手势进行中不能改变自身所在的树结构（已踩两次）

**症状各异，根因相同**，第三次再遇到请直接查这里。

| 次数 | 症状 | 触发链 |
|---|---|---|
| 1 | 双击断开连线崩溃 | `onPointerDown` 起拖 → setState → linker 子树重建 → 双击识别器 dispose |
| 2 | 未选中的元件拖不动 | `onPanStart` 里选中 → setState → pad 由 0 变 12 → **返回的 widget 结构变了** → GestureDetector 重建 → pan 被取消 |

第 2 次的具体错误：`_buildElementWidget` 曾按「是否选中」返回两种结构
（直接 body / SizedBox+Stack）。结构一变，Flutter 认定不是同一个
widget，就会销毁重建，正在进行的手势随之取消。

| 3 | 未选中的 linker 拖动被打断 | 选中框是**条件子节点且排在手势节点之前** → 插入后其余子节点索引后移 → GestureDetector 重建 |

第 3 次尤其隐蔽：其他元件的 `GestureDetector` 是**最外层包裹**，
内部子节点怎么增减都不影响它；只有 linker 把手势放在 `Stack` 内部
（三段式布局需要），才会被前面插入的兄弟节点顶掉索引。
用户观察到「已选中时拖动就正常」——正因为那时节点已存在、索引不变。

**规则：凡是在手势回调里 setState 的路径，必须保证 build 出来的
树结构不变**，只允许改数值或增减「不影响手势节点」的子节点。

推论：**条件子节点务必排在手势节点之后**；
若手势节点本身在 Stack 内部，前面就不该有任何 `if (...)` 子节点。

具体做法：
* padding 恒定撑开（`_handlePaddingOf` 恒返回 12），
  不按选中状态在 0/12 之间跳
* 把手作为 Stack 的可选子节点追加，body 恒为 `children[0]`
* 渲染器里 `Transform.rotate` / `Transform.scale` 即使参数为
  恒等值也保留包裹（`ui_renderer` 里早有同样的注释）

### linker 不画选中虚线框

与 Studio 一致（它的 `isTransformationActive && !isLinker` 明确排除）。
linker 本身就是有边框的卡片，再套一圈虚线只是噪声。
这同时消除了上面第 3 类手势中断。

### 复合件缩放后，选中虚线框的圆角要乘缩放比

容器面被 `Transform.scale` 一起缩放，它的**视觉**圆角是
`原始值 × scale`；而虚线框画在**未缩放**的外框上。
不乘系数就会出现「边框不贴合容器面」（用户反馈）。

只有 `UIModuleShape.rounded` 受影响——`rectangle` / `circle` /
`capsule` / `heart` / `star` 的路径都由 `rect` 自适应推导
（capsule 用 `shortestSide/2`、circle 用 `min(w,h)`），跟着盒子走。

因为复合件强制等比缩放，`natural × scale == el.size`，
内容恰好填满外框，边框与内容之间不会留空隙。

### 复合件的连线连的是「暴露子元素」，不是外壳

复合是黑盒，外壳没有 `module`，方案矩阵拿它算不出任何东西。
制作复合件时勾选的 `exposedPorts` 就是它与外界的唯一接口。

因此：
* `_linkerCandidates` 把复合件**展开为它暴露的子元素**加入候选
* 连线里存的是**子元素 id**（存外壳 id 会让运行端找不到 module、静默失效）
* 但**画线锚点要回落到外壳**（`_wireAnchorElementById`）——
  子元素的 offset 相对复合件，直接当画布坐标会错位一整个复合件
* 命中复合件时若有多个暴露端口，**必须让作者选**，
  静默取第一个会让「连错端口」变成查不出来的问题

### 复合件缩放要缩内容，不只是外框

`_renderComposite` 用**绝对坐标**摆子元素，改外框 `size` 内部纹丝不动。
必须按内容包围盒（`UIRenderer.compositeNaturalSize`）算比例，
再用 `Transform.scale(alignment: topLeft)` 整体缩放。

用 `Transform.scale` 而非 `FittedBox`：后者的 contain 会自动居中，
把作者摆好的左上留白吃掉。

复合件的形变**必须等比**（它是搭好的成品，单独拉宽会让内部比例失真），
且夹取比原子件更严：
* 上限 = PCB 尺寸（溢出画布运行时会被裁或等比缩小，编辑器里的比例就白费了）
* 下限 = 包围盒 × `kMinCompositeScale`(0.45)，保证内部文字仍可辨认

夹取顺序：先夹宽度 → 由宽度推高度 → 若高度越界再由高度反推宽度。
两个维度独立夹取会破坏比例。

### 键盘弹出时的布局策略：不能一刀切

用户反馈「输入法弹出挤压的区域会算进可用屏幕，UI 被压缩」。
全仓此前**没有任何一处**设置 `resizeToAvoidBottomInset`，
全部走 Flutter 默认的 `true`。

但**不能全部关掉**——聊天页的输入框必须跟着键盘上移。按类型区分：

| 页面类型 | 策略 | 理由 |
|---|---|---|
| 编辑画布（Assembly / Studio） | `resizeToAvoidBottomInset: false` | 画布有自己的平移缩放，压缩后正在编辑的元件跑出可视区 |
| 全屏运行时预览 | 同上 | `UIAssemblyRuntimeView` 按 `constraints.maxHeight` **等比缩放整张 PCB**，body 一缩整个 UI 变小 |
| 聊天页 | 保持默认 `true`，但**补偿场景层** | 输入框要跟键盘走；scene 是全屏接管的 UI，不该跟着缩 |
| 普通表单 | 保持默认 | 本来就该让输入框可见 |

**场景层的补偿手法**：它用 `top: 0, bottom: 0` 绑定 body 高度，
body 缩多少就用负 bottom 撑回多少：

```dart
final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
Positioned(top: 0, bottom: -keyboardInset, ...)
```

⚠️ 常驻 / 伴生挂件**不需要**这个补偿——
它们用绝对 `top` 定位、高度自适应内容，不受 body 收缩影响。
盲目给所有图层加补偿会让它们往下跑出屏幕。

### 沙箱验不出「缺 import」，提交前用脚本扫一遍

括号平衡检查发现不了未定义标识符。`math.sin` / `Offset` /
`RenderRepaintBoundary` 这类漏 import 只有 analyze 才报，
而沙箱没有 Dart SDK——已经因此让用户多跑了几轮 analyze。

提交前跑这个扫描（要点：**排除 `part of` 文件**，
它们继承父库的 import，否则全是误报）：

```python
# 对每个非 part-of 的 .dart：
#   用到 math.*            -> 必须 import 'dart:math'
#   用到 Offset/Size/Rect  -> 必须 import flutter/material|widgets|painting
#   用到 ui.*              -> 必须 import 'dart:ui'
#   用到 RenderRepaintBoundary -> 必须 import 'flutter/rendering.dart'
```

新写的**测试文件**最容易漏——它们不像 lib 里的文件那样
早就有一堆 import 垫底。

### RenderRepaintBoundary 需要单独导入 rendering.dart（已犯两次）

`material.dart` 转出了 `RenderBox` / `RenderObject`，
但**不转出 `RenderRepaintBoundary`**。

漏掉 `import 'package:flutter/rendering.dart';` 会一次报三个错，
而且后两个具有误导性：

```
The name 'RenderRepaintBoundary' isn't defined
The property 'debugNeedsPaint' can't be unconditionally accessed
The method 'toImageSync' can't be unconditionally invoked
```

后两条看着像空安全问题，实际是因为 `obj is! RenderRepaintBoundary`
里的类型未定义，**类型收窄失效**，`obj` 保持 `RenderObject?`。
只要补上 import，三个错一起消失——不要去加 `!` 或 `?`。

凡是要用 `toImageSync` / `toImage` 抓取组件纹理的文件都会遇到。
方案 C 和方案 A 各犯过一次。

### 视觉特效必须先验证「链路是否真的在执行」（A12 最大教训）

水波动画改了六版才成功，其中**两版的失败与效果无关，是代码压根没跑**：

| 版本 | 症状 | 真实原因 |
|---|---|---|
| 网格变形（方案 C） | 「看不出任何变化」 | 捕获纹理的回调只写字段、**从不 setState**，变形结果从未被绘制 |
| 着色器首版 | 「就是普通的变换值，没有动画」 | GLSL 缺 `#extension GL_GOOGLE_include_directive`，编译失败后**静默**退回原样显示 |

两次我都在「效果不好」的假设下反复调参数，浪费了好几轮测试。

**规则：**
1. 新做视觉特效时，**先做一个不可能看错的最小验证**
   （比如让它画个纯色块），确认链路通了再堆细节。
2. 任何「失败就静默降级」的路径**必须留下 debug 输出**。
   `RippleShaderLoader.lastError` 就是补的这一课——
   有它才能区分「没加载」与「效果差」。
3. 沙箱能验证数学，**验证不了链路**。凡是我说「数学已校验」的，
   都只代表公式对，不代表它被执行了。

### 动画有两条独立通路，改任何一处都要同时检查（A12）

| 通路 | 触发源 | 时间戳 |
|---|---|---|
| `_wrapWithAnimation` | 连线（button/timer） | props 里有真实值 |
| `_wrapWithValueChangeAnimation` | 值自己变了 | **恒为 0**（渲染函数不能写 props）|

**拖 slider 走的是后者。** 已经因此栽过两次：
* 进度条波浪边界用 `isActiveAt(timestamp)` 判断 → 后者永远 false；
* 边缘喷射粒子只在前者跳过通用层 → 后者照样叠加中心爆发盖住它。

### 几何特效在纯色区域天然无效（A12）

折射 / 位移 / 网格变形都只**搬运**像素、不**创造**梯度。
进度条内部是大片纯色，采样偏移 5px 取到的还是同一个颜色，
所以用户只在两色交界处看得到扰动。

**加强强度解决不了**，只会让交界处抖得更厉害。
想让纯色组件有反应，必须叠加**颜色或形状**的变化——
`_WavyProgressBar` 把填充边缘画成波浪线就是这个思路。

### 「不打断」不等于「排队」（A12）

为了避免连续变值把动画掐死在第一帧，最初实现成
「播放期间不重启，播完再补一轮」。那是**串行**：
实测 500ms 连续拖动、duration 600ms 时**只播 1 次**，其余全在等待，
用户反馈「每次的动画等待时间太长」。

正解是**多波次并发**：新变化立刻起一道新波与旧波叠加，
各自走完生命周期。同样条件下播 6 次、并发峰值 3。

配套两个约束：并发上限（3，超出淘汰最老的）、
最小间隔（90ms，否则每帧起波会瞬间堆满且相位雷同）。

⚠️ 连续相位的动画（波浪线）可以直接重启；
**离散的动画（粒子）必须每批各持一个控制器**，
重启会让上一批瞬间消失。

### A14-1 / A14-2 / A14-3 已完成（均测试通过）

A14-3 的结论值得记一笔：**「实例编辑器分文件」最终判定为不做**。

盘点期我把「Studio 2900 行 editors vs Assembly 一个通用对话框」
列成了缺口，但分工线立起来之后这个对比不成立——
Assembly 该管的参数本来就不多，真正臃肿的数据通道已独立成页。
再拆七个文件是过度设计。改为**按需拆**。

> 教训：**盘点出的「差距」要先过一遍分工，再决定是不是缺口。**
> 两个工具职责不同，能力不对等是正常的。

画布操作、逻辑件资产项、精确几何、容器归属都已到位。
剩 A14-3 实例编辑器分文件、A14-4 linker 画线、A14-5 PCB 自定义。

#### 容器归属的核心不变式（A14-1c）

**`_elements` 里每个组是一段连续块，父面永远在块首。**
列表越靠后越上层，父面在块首即整组最底——
「子组件恒高于父级面」由此自动成立，不必每次比较父子下标。

配套三条：
- **「能否移动」必须与移动逻辑同分支**。按全局下标判断会让组内成员
  出现「按钮可点却没反应」——它在全局还有后继，在组内已是最后一个。
- **顶层元素跨组时整组跳过**，否则会卡进别人组中间切断连续块。
- **删除容器面必须清理组员的 `parentSurfaceId`**。悬空父级会让
  `isElementVisibleInSurfaceHierarchy` 沿链查不到父级而返回 false，
  **整组在运行时凭空消失**。

进出组在**变更那一刻**重整（Studio 是事后补救，要作者手动切一次层级）。
出组时**不移动位置**，保留组内显示层级——所见即所得。

#### 几处反复踩到的坑

**1. 带 TextField 的弹窗，关闭走 `closeDialog`、controller 延后一帧释放。**
先 `unfocus()` 再等一帧 pop，`dispose` 放进 `addPostFrameCallback`。
否则输入法未确认时关闭会崩（`controller used after disposed`）。
弹窗内容还要包 `SingleChildScrollView`，键盘弹出会挤到 overflow。

**2. 旋转在整条链路只能应用一次。**
`UIRenderer.render` 内部已按 `element.rotation` 包了 `Transform.rotate`。
画布若在外层再包（为了让选中框跟随），传进渲染器的副本必须
`copyWith(rotation: 0.0)`，否则角度翻倍。
但 `_buildReadonlyPageElement` 没有外层包裹，**不要**剥离。

**3. 共用渲染器的组件，两边默认尺寸表也要同步。**
`math_node` / `timer` 曾因 Assembly 给 120×56 而 Studio 给 180×44，
同一套渲染画出来观感差很多——尺寸决定内容如何被 FittedBox 缩放。

**4. 同一条件在一个 children 列表里可能出现多次。**
删「实例黑盒」标签时漏了同分支另一处 `if (isSelected)`，
留下一圈紫框与新虚线框叠在一起。改 UI 前先数一遍出现次数。

**5. 标签用流式排列，不要写死坐标。**
`_topBadgesOf` / `_bottomBadgesOf` + `Wrap`。
原先四个标签各写死坐标，锁定与容器面直接重叠，
且每加一个都要重找空位。

### 方案设计的两条通用规则（A13-3 踩出来的）

**1. 换目标类型只能改变呈现形式，不能改变语义。**
`sum_to_display` 初版对文本目标做 clamp、对进度条却不做，
同一份配置两种结果，作者无法预期。
数值目标与文本目标必须共用同一个算好的值。

**2. 用法与众不同的方案，必须在 UI 上明说。**
`sum_to_display` 是目前唯一「同一目标可接多条」的方案，
只靠一句抽象描述，作者只会连一条然后以为坏了。
需要：描述里给操作步骤 + 完整示例、参数区加提示条、
标注哪些参数只需填一次、哪些参数仅对特定目标生效。

### 新增 linker 方案的完整清单（踩过两次）

Assembly 与 Studio **共用方案矩阵，但编辑器是两套**。
新增方案时三处都要动，漏任一处都表现为「配了没用」：

1. **登记进 `_schemeRegistry`** —— 漏了 `isSchemeSelectable` 判非法，
   运行端静默跳过（`button_to_page_route` 栽过）。
2. **Assembly 侧能配置其参数** —— 漏了作者只能吃默认值，
   带 choice 参数的方案等于只有一个选项
   （`button_to_message_action` 栽过）。
3. **运行端解析** —— 注意区分「参数缺失」与「参数非法」：
   缺失应回落方案默认值（否则老数据完全失效），
   非法才返回 null（静默执行别的动作更危险）。

### A11 进度：A11-1 / 长文本 / A11-2 富文本 + 正则着色均测试通过
剩余：消息操作（重新生成 / 编辑 / 删除 / 版本切换 / 头像）。

#### 富文本三档降级（`assembly_rich_text.dart`）
HTML → Markdown → 正则着色。消息流与可滚动长文本共用。

**不复用聊天页的 `_buildMarkdownWidget`**：它绑在 `_ChatPageState` 上，
依赖 `_renderPromptTemplate` 与 `_handleMarkdownAction`，
这两样在 Assembly 运行时都不存在。判定与降级策略保持一致即可。

**两个判定边界不要改（有测试守着）**：
- 不检测 `**加粗**` / `*斜体*`——星号在角色扮演文本里是动作标记
  （`*他转过身*`），按 Markdown 解析会把内容吃掉。
  列表判定要求星号后必须有空格。
- HTML 只认白名单标签——否则「当 HP<50 时触发」会被当成未闭合标签。

**默认值按用途分档**：message_flow 开 / 滚动 text 开 / 其他 text 关。
最后一档默认关是因为它多被 linker 指向显示数值，解析无收益还会误判。

#### 正则着色规则（`text_highlight_rule.dart` + `text_highlight_engine.dart`）

作者可自定义，存 `CharacterMeta.textHighlightRules`，
聊天页原生气泡与 Assembly 组件共用同一套。

**只着色，不改写文本。** 与酒馆 `regex_scripts` 的本质区别，
也是这套设计敢开放给作者的前提：规则写坏了最多是难看，
不会污染存档，也不会让模型收到错误输入。**不要**在此基础上加替换能力。

**非法正则跳过而非抛异常。** 作者边写边预览必然出现半成品状态
（刚敲 `(` 还没敲 `)`），抛异常会让整个消息列表白屏。

**顺序即优先级，部分重叠整条丢弃**——半截着色比不着色更糟。

**空列表 = 没配过 → 回落内置默认**，不等于「不要着色」。
想完全关闭需留一条停用的空规则。

**切分后拼回必须等于原文**，测试守着这条：漏字是内容丢失，
比着色错误严重得多。

**只作用于第 3 档**：Markdown / HTML 有自己的语法着色，叠加会打架。

Assembly 侧走 `TextHighlightScope`（InheritedWidget），
不走 `module.properties`——规则是角色卡级配置，
写进 properties 会被 `_persistAssemblyElements` 复制进每个组件。

### A10 早期进度：A10-0/1/2 完成并测试通过
常驻 UI 已能在真实聊天里显示、拖动、交互，并与 SessionState 双向同步。
A9.6 的完整闭环至此在真实会话中跑通：
LLM 更新状态 → SessionState → 常驻 UI 组件刷新；
玩家操作组件 → SessionState → 状态栏与 Prompt。

剩余：A10-3 伴生（A10-4 开场白、A10-5 场景均已测试通过）。
A10-1 的挂载基础设施可直接复用，主要工作是各自的形态差异。

### 待后期统一处理的优化（用户已提出，暂缓）
1. ~~**长按 PCB 拖动挂件**（取代内置拖动把手）~~ —— **已完成**。

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

   **实现结果**：
   - 命中判定放在 `UIAssemblyRuntimeView._blocksLongPress`——
     只有这里同时掌握 pcbRect、缩放系数与活动页元素树，
     透传出去既啰嗦又容易算错。
   - 排除集合 `_longPressBlockingTypes = _gestureGreedyTypes + button`
     （用户决策：沿用手势白名单那一套，不只排除 button）。
   - 复用已有的 `_hitsTypedElement` 递归命中（原
     `_hitsGestureGreedyElement` 重构为它的一个特例），
     天然覆盖复合组件内部的 button。
   - **坑**：`onLongPressMoveUpdate` 的 `offsetFromOrigin` 是**累计**位移，
     而调用方按增量累加。直接传会导致位移平方级放大，
     必须自己算帧间增量。
   - 内置把手已移除（用户决策）。拖动时用 `AnimatedScale` 1.04 +
     投影给反馈——长按没有可见触发点，必须让玩家确认「抓起来了」。
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

### 3.1 PCB / 前后台规则（✅ 已完整实施）

出 PCB 是**三态分类**，由 `_requiresPcbContainment` 统一裁决：

| 类别 | 类型 | 规则 |
|---|---|---|
| 原生后台节点 | `linker` / `math_node` / `timer` / `page_router` | 随便摆，运行时本就 `SizedBox.shrink` |
| 可后台化白名单 | `text` / `switch` / `progress` / `indicator` / `input` | 走 4.1 双阈值滞回，出去 = 转后台 |
| **其余原子 + 复合件** | `button` / `slider` / `select` / `surface` / `image` / ... | **必须留在 PCB 内**，硬夹取 |

第三类曾长期没有任何约束（用户发现）：它们运行时照常渲染，
拖出 PCB 等于**静默丢失**——编辑器里看得见，一进运行时就没了。

约束的统一入口是 `_applyPlacementConstraints`，
拖动 / 资产投放 / 方向键微调三条路径都必须走它，
否则会出现「拖不出去但按方向键能挪出去」。

**旋转元件必须按旋转后包围盒夹取**（`_rotatedBounds`），否则死锁：
`_isElementInsidePcb` 按旋转后四角判定，而夹取若按未旋转的 w×h 算，
贴边后四角仍探在外面 → 退出时被拦「请先移回可视区域」，
可作者已经拖到头了，移不动，卡死无法保存。

### 3.2 红框使用规则
- 红框保留，但主要用于**异常非法状态兜底**
- 不作为常规拖动反馈的最终方案

### 3.3 后台原子：拖出 PCB 自动后台化（✅ 已实现）
对允许后台化的原子组件：
- 靠近 PCB 内壁时自动吸附在边界内侧（夹到内壁贴边）
- 继续往外拖越过 **56px** 后脱离吸附，跟手自由拖动
- 松手落定 `runtimePlacement = 'background'`

**双阈值必须不相等**：脱离 56 / 回吸 24。相等的话元件会在边界
每帧来回抖——越界一点点被吸回内壁，下一帧手指还在外面又越界。
这就是滞回（hysteresis）：进和出走两条不同的线。

白名单 `text / switch / progress / indicator / input`
是**跨编辑器契约**，Assembly 与 Studio 必须逐字一致。
复合件按 3.1 永远不许出 PCB。

改这块时注意：`_beginBackstageDragTracking` 必须在**每次**
`onPanStart` 调用。不重置的话上一次拖动的「已脱离」会泄漏到
下一次，刚起手就直接判后台。

### 3.4 图层面板规则
- 选中某图层后，**图层面板不要自动关闭**
- 点击空白区域才关闭
- 主菜单固定为第一平级页，不允许改名和拖动
- **叠加层无论如何都不能变成子叠加层**（用户明确规则）。
  叠加页恒为平级页的直接子级，**深度恒为 1**。
  「换父级」= 在不同平级页之间切换挂靠，不是嵌套。
  首版 4.2 做成了树状嵌套拖放，是理解错误；
  且 `_createPage` 早先就允许嵌套建到 3 层，整条链路都基于错误前提，已一并修正。
- 自动拖动换父级 ✅ **已实现**（灵感池 4.2）：
  平级页保留同级排序，叠加页改为 `LongPressDraggable` 拖到**平级页**上换父。
  按页面类型分流即可，因为平级页没有父级只需排序、
  叠加页同级顺序不影响打开只需换父——**每种页面只有一种拖动行为**。
  弹窗入口保留作为兜底。
  拖放判据 `_canDropPageInto` 必须与弹窗的
  `_reparentCandidatesForPage` 逐条对齐，两者漂移会让规则显得随机。
  规则收紧后**不需要防环**：落点恒为平级页，平级页没有父级，构不成环。

### 3.5 Binding 名称解析与预绑定规则（✅ 已完整实现）
- 普通创作者不应被要求手填内部 ID。
- 数据通道的名称输入框右侧有「从状态栏字段中选择」按钮
  （`SuggestibleNameField`）。**只由按钮触发**，聚焦与输入都不弹出——
  自动弹出会在作者正打字时挡住视线。
- 若匹配到已有状态栏字段，系统保存其内部 `id`；之后改名不影响绑定。
- 若未匹配到状态块，保存为“预绑定名称”（`pendingName`），显示警告但不阻止。
- 状态栏编辑页顶部列出全部预绑定，点击即按 UI 组件当前值创建字段
  （`collectPendingStatusBindings`）。创建后回 Assembly 由
  `_reconcileStatusChannelBindings` 自动补绑成真实 targetId。

#### 初始值同步方向（用户明确）

| 场景 | 源 |
|---|---|
| 状态栏已有该字段，UI 绑定它 | 状态栏 → UI |
| UI 有预绑定、状态栏还没建，新建时 | UI → 状态栏 |
| 绑定成立后改任一侧 | 双向，以最后保存的一侧为准 |

**量程必须与值一起同步**。只同步值会出事：状态栏「等级」70、量程 0~100，
作者按十级制把进度条量程设成 0~10，70 写进组件时被 `clamp` 静默截断成 10；
启用反写后，作者什么都没干直接退出就会把状态栏的 70 改成 10。
两边量程一致从根源消除截断。**先同步量程再写值**，反了值会被旧量程截断。

**反写只针对作者真正改过的**：进入编辑器并完成一次同步后记快照，
退出时只回写与快照有差异的。快照必须在同步之后记——在之前记的话，
同步本身造成的改动会被当成作者改的，形成「打开就同步、退出就回写」的自激循环。

**绑定往往在页面运行中才建立**，不能只在 `initState` 同步一次。
`_syncStatusFieldForElement` / `_syncStatusFieldForOverride` 在绑定
建立或变更后立即同步并**登记基线**；不登记基线，刚同步进来的值
会被当成作者改动写回状态栏，把作者设的初始值冲掉。

**复合件暴露项的通道配置不在 elements 上**，而在
`AssemblyPage.propertyOverrides[].overrides['dataChannel']`。
两条路径都要处理，只遍历 elements 会让复合件里的绑定完全不同步。

### 3.5b 「双写覆盖」陷阱（本轮连栽四次，务必先读）

**症状**：从对话框进入子页面，子页面保存后回到对话框，
改动看起来没生效；点了对话框的保存反而把子页面配好的内容盖掉。

**根因**：同一字段有两个编辑入口时，对话框的 state / controller
仍是**打开那一刻**的旧值。子页面写的是 `_elements`，两者互不知情。

本轮四次表现，全是同一个病根：

| 次数 | 症状 | 漏刷的东西 |
|---|---|---|
| 1 | 「最终语义」预览不变 | `channelSource` / `channelNameController` |
| 2 | 开关仍显示关闭 | `channelEnabled`；且回读用了闭包捕获的旧 `module` |
| 3 | min/max/current 要重开才对 | 那三个 `TextEditingController` |
| 4 | 文本内容不同步 | `textController` / `selectDefaultController` / `switchValue` |

**三条铁律**：

1. **子页面返回后，必须把对话框的全部相关状态重新读一遍。**
   漏掉任何一个，保存时它就会用旧值把结果覆盖回去。

2. **回读不能用闭包捕获的 `module`。**
   保存走 `copyWith(properties:)` 生成**新对象**放进 `_elements`，
   旧对象的 properties 从未被改动，读它永远是打开那一刻的状态。
   要按 id 从 `_elements` 重新取。

3. **子页面不要自己落盘。**
   落盘后对话框的「取消」就收不回它，与「先改动、再决定确认还是退回」
   的常识相悖。正确做法是子页面返回配置对象
   （如 `DataChannelPageResult`），由对话框的保存 / 取消统一裁决。
   曾经给这个错误设计打过补丁——把按钮文案改成「取消其余修改」，
   那是在为不合理行为找说法，而不是修正它。

**自检清单**：新增「对话框 → 子页面」入口时，列出子页面可能改动的
每一个 props 键，逐一确认对话框里承载它的 state/controller 都会被回读。

### 3.5c 会话副本（SessionState）的同步陷阱

4.3b 期间在这条链上连栽三次，都值得记。

#### 一、`identical` 判不出原地修改

`UIAssemblyRuntimeView.didUpdateWidget` 原本只用
`!identical(incoming, _session)` 判断会话有没有变。但聊天页是
**原地修改** `_sessionState.statusValues[...]`，对象身份从头到尾不变，
`identical` 恒为 true，反向同步永远不触发。

症状：**Prompt 里数值已经变了，界面纹丝不动。**

解法：加 `sessionVersion`，在 `_saveSessionState()` 里统一递增。
放那个函数是因为所有会话写入最终都汇到它——逐个改调用点必然会漏
（与 `_persistAssemblyElements` 同理）。

**透传链有三层**：`chat_page` → `ChatAssemblyMount` → `UIAssemblyRuntimeView`。
只加两层会报 "The named parameter isn't defined"。

#### 二、300ms 轮询会覆盖外部写入

`_syncDataChannels` 每 300ms 跑一次，其中 `applyWrites`
**无条件用组件当前值覆盖 session**。LLM 写入后组件还没刷新，
新值在 300ms 内就被旧值顶掉。

症状：数值看着是变了（Prompt 侧读的 session），
但**通知不弹**——通知依据的变化量已经被抹平。

解法：`_suppressNextWriteBack`。外部写入后抑制紧随的那一轮回写，
只让 UI 追上 session；下一轮组件已是新值，回写不再造成倒退。

**这条通用**：任何「组件 ⇄ session」双向同步的地方，
外部写入后都必须先让 UI 追上，否则回写会把外部改动吃掉。

#### 三、消息回滚会抹掉会话级的一次性事实

`_rollbackSessionStateFor` 用消息快照**整体替换** session。
快照是每条 AI 消息结算前拍的，可能早于玩家确认开场白，
覆盖后 `openingUIDismissed` 回到 false，开场白又弹出来。

**判据**：某个标记描述的是「玩家做过一次的事」还是「剧情状态」？
前者（开场白已确认、引导已看过）属于会话级事实，回滚时要单独保留；
后者（等级、好感度）才该跟着消息一起回滚。

只有清空聊天记录（`_sessionState = SessionState()` 整个重建）
才该让这类标记复位。

### 3.5d 首帧空窗：异步初始化的通病（本轮连修三次）

同一个根因换了三副面孔，全都是**「进页面时该显示的东西晚了一拍」**。

**症状家族**
1. 开场白先闪一下再消失
2. 修完闪现后，开场白要等半秒才出来
3. 聊天页背景先铺一帧默认浅蓝→浅紫渐变，再换成真背景

**三条判据**

**(1) 状态没读完就渲染 → 闪现。**
`_setCurrentCharacter` 里 `_currentCharacter = char` 之后立刻 `setState`，
但此时 `_openingDismissed` 还是上一个角色的值。
解法是加**就绪闸门**（`_sessionReady`），副本读完前判定一律返回 false。

**(2) 闸门挂在最慢的一步后面 → 空等。**
闸门只依赖 `_loadSessionState()`（单行 `where id = ?`），
它却排在 `_loadUser()`（`getAllCharacters()` 全表扫 + 逐字段重建卡）后面。
**规则：决定「首帧画什么」的查询，必须排在初始化链的最前面。**
注意提前之后，后面若有刷新 `_currentCharacter` 的步骤（`_loadUser`），
要在其后补一次 `_invalidateAssemblyCaches()`，
因为判定缓存按角色 id 存，同一张卡改了内容不会自动失效。

**(3) `FutureBuilder` 写在 build 里 → 必然闪一帧。**
```dart
FutureBuilder(future: _loadXxx(), ...)   // ✗ 每次 build 新建 future
```
两个后果：首帧 snapshot 是 waiting（`data == null`）走进兜底分支；
以及聊天页有多个 AnimationController 在 setState，
动画期间**每帧**都重跑一次数据库查询。
**解法：查询移出 build，结果缓存到 state 字段，配 `_xxxLoaded` 标志区分
「还没查」和「查完确实没有」——前者绝不能画兜底样式。**

**(4) 换个兜底颜色不算修好。**
把默认渐变换成纯黑，只是把闪烁换了个颜色。
必须消灭空窗本身：让数据在**首帧同步可得**。

**同步缓存范式**（`BackgroundService` 是模板）
```
_cache / _cachedCurrentId   内存缓存
isWarm                      缓存是否就绪
peekCurrent() / peekById()  同步读，未就绪返回 null
warmUp()                    main() 里 await，顺带做掉冷启动大头
_refreshCache()             所有写入口走它：先重建缓存再 bump versionNotifier
```
适用条件：数据量小、全进程共用、写入口可枚举。背景、预设这类都符合。

**冷启动开销藏在哪**（一次查询看着轻，前面挂着三段）
- `DatabaseService.database` 首次 → `openDatabase` + 建表 + migration
- `SharedPreferences.getInstance()` 首次 → 读整个 xml/plist
- `ensureBackgroundsTable()` → 每次都查一遍 `sqlite_master`

把这些代价 `await` 在 `main()` 里（记在启动画面上），
比留给每个页面首帧去付要好。
用户对此的判断：**「在角色库等待一会问题不大」**——
启动慢一点可以接受，进页面闪一下不能接受。

### 3.5e 全屏运行时 UI 的键盘避让（本轮连栽三次）

**需求**：scene / 开场白里靠底部的输入框会被键盘盖住。

**三次失败的尝试，每次的错法都不同：**

**① 让 Scaffold 收缩** —— `UIAssemblyRuntimeView` 按可用高度算
`safeContainScale` 等比缩放整张 PCB。可用高度一变，作者摆好的界面
在打字时整体缩小。用户原话：「剪掉屏幕可渲染范围很差，会将整个界面给缩小」。

**② `bottom: -keyboardInset` 把高度补回去** —— 界面确实不缩了，
但输入框照样被盖住，等于没解决。而且这段代码**从来没生效过**，见 ③。

**③ 在 body 内部读 `MediaQuery.viewInsetsOf`** —— 读到的恒为 **0**。
Scaffold 在 `resizeToAvoidBottomInset: true` 下会**消费掉 viewInsets**：
body 被塞进矮一个键盘高度的空间，同时向下传递的 MediaQuery 里
`viewInsets.bottom` 被清零。所以 body 内的任何组件都测不到键盘。
→ 必须在**进入 Scaffold 之前**取值，存进字段再往下传。

**④ 让背景 `bottom: -inset` 溢出去盖住缝隙** —— 外层 `Stack` 默认
`clipBehavior: Clip.hardEdge`，溢出部分被裁掉，黑边照旧。

**最终正确解法（两条腿）：**

1. **源头不压缩**：`resizeToAvoidBottomInset: !_sceneTakesOver && !_shouldShowOpeningAssembly`。
   这两种模式下原生输入栏本就不渲染，没有任何东西需要跟着键盘上移，
   压缩 body 纯属有害。关掉后 body 恒为全屏高度，
   `safeContainScale` 全程不变，底部也不再产生缝隙。
2. **平移而非缩放**：`KeyboardAvoidingStage`（`lib/widgets/`）用
   `Transform.translate` 整体上移。平移**不参与布局**，
   碰不到 PCB 重算缩放那条链路。

**`KeyboardAvoidingStage` 的两个必踩点：**

- **`keyboardInset` 必须由外部传入**，组件内部不能自己读 MediaQuery（理由见 ③）。
  参数驱动要挂 `didUpdateWidget`，只写 `didChangeDependencies` 收不到参数变化。
- **`localToGlobal` 返回的是已平移之后的坐标**。算目标偏移时要加回
  `_offset + _manualOffset` 还原，否则第二次计算会把已推上去的量再算一遍，
  越推越多。

**用户想要的交互形态（原话）**：
> 可以采用平移，不过可以手指滑动来向上翻。感觉上类似给整个渲染屏幕
> 又添加了一段输入法高度的空白渲染区域

即：自动推到刚好露出焦点组件（不多推一像素），
额外允许手指在 `[0, 键盘高度]` 范围内手动上翻。

**排查这类「底部露黑边」的通用顺序**：
先看 Scaffold 是否在压缩 body → 再看外层 Stack 是否 clip 了溢出 →
最后才怀疑绘制层本身。别一上来就给绘制层打补丁。

### 3.5f 聊天页重建收敛（AnimatedBuilder 的正确用法）

**背景**：`_ChatPageState.build` 有 1285 行，而 `_animController` /
`_inputAnimController` / `_fanSnapController` 三个 controller 都挂着
无条件 `setState`，任何动画播放期间整棵树每帧全量重建。

**三种情况要分开处理，用错就出 bug：**

**① 纯视觉属性（位移 / 透明度 / 缩放）** → `AnimatedBuilder` + `child`
把重体积子树作为 `child` 传入只构建一次，builder 里只包薄薄一层。
聊天主体那 750+ 行就是这么剥离的。

**② 子树内部还引用动画值** → 必须**单独再套一层 AnimatedBuilder**
这是最容易漏的：一旦子树作为静态 `child` 被缓存，写在它里面的
`_animController.value` 就**冻结在初始值**，再也不刷新。
聊天主体内层那个 `ignoring: value > 0.5` 就是这种情况。
**重构后务必全文搜一遍子树内是否残留动画值引用。**

**③ 条件渲染（决定 widget 存不存在）** → `AnimatedBuilder` 无能为力
`if (_animController.value < 0.1) Positioned(...)` 这种写法决定的是
**元素在不在树上**，不是它长什么样，只能整树重建。
解法是**阈值节流**：把连续的动画值映射成离散「区间」，
只在跨区间时 setState：

```dart
final bucket = v < 0.1 ? 0 : (v < 0.5 ? 1 : 2);
if (bucket == _animBucket) return;
_animBucket = bucket;
setState(() {});
```

一次 300ms 抽屉动画约 37 帧，全树重建从 37 次降到 **4 次（-89%）**。
注意分桶边界必须与条件判据**完全一致**（这里都是 0.1 / 0.5），
否则条件渲染的时机会偏。

**④ 已有 AnimatedBuilder 却还挂着全局 setState** → 等于白圈
`_inputAnimController` 的两个消费点本来就套了 AnimatedBuilder，
外面又挂了个 `setState`，整棵树照样每帧重建。
**加 AnimatedBuilder 的同时一定要把对应的全局监听摘掉**，否则毫无收益。

**其他已修的同类隐患：**
- `FutureBuilder(future: _getXxx())` 写在 build 里 → future 每帧新建，
  首帧必定走 loading 分支（背景闪烁的真凶），且每帧重跑一次数据库查询。
  **正确做法**：查询结果缓存进 state，build 只读缓存。
- `File(path).existsSync()` 写在 build 里 → 同步磁盘 IO，
  头像那几处同一路径每帧要 stat 2~3 次。加 `_fileExistsCache` 缓存，
  在 `_loadUser()` 里失效。

### 3.5g 四种 mode 全是单例（曾有静默失效缺口）

`ChatAssemblyMount.resolveAssembly(meta, mode)` 按 mode 线性查找，
**命中第一个就 return**。所以同一 mode 建了多个，第二个及之后
永远不会被挂载。

**曾经的缺口**：`character_assembly_list_page._addNewUI` 只给
`opening` / `scene` 加了 `if (!hasXxx)` 拦截，
`extra_sticky` / `extra_companion` 无条件加入选项。
作者可以建任意多个常驻 UI，做完却发现它根本不出现，且**没有任何提示**。

用户提问点破：「常驻 UI 的折叠图标只有一个，有多个常驻 UI 怎么办？
进入对话会不会打架？折叠后怎么区分？两者重叠了怎么弄？」
——答案是不会打架也不会重叠，因为第二个根本没被挂载，
代价是作者的劳动被静默吞掉。

**用户决策**：限制为单个。
> 好吧，就限制为单个，用叠加页也可以实现多页面显示

**已修**：
1. 四种 mode 一律 `if (!hasXxx)` 拦截，「已达上限」提示由
   `_existingModeLabels()` 统一生成（原来只硬编码了 opening/scene 两种组合）。
2. 列表页对**历史数据**里的重复项显式标注：头像置灰 +
   副标题红字「不会生效：已有同类型 UI」。
   新建入口堵死不代表旧数据干净，不标出来作者会以为 UI 坏了。

**以后新增 mode 时记得**：`_addNewUI` 的拦截、`_existingModeLabels`
的标签、以及列表页的配色三处都要补。

### 3.5h 输入法未确认就关弹窗 → Duplicate GlobalKeys

**报错**：
```
Duplicate GlobalKeys detected in widget tree.
- [LabeledGlobalKey<_OverlayEntryWidgetState>#...]
The specific parent that did not update ... *Theater(skipCount: 4 ...)
```

**触发路径**：改图层名时**不点输入法的「确认」**，
直接点对话框按钮 / 点遮罩 / 按返回键。

**成因**：输入法的候选栏、放大镜等是挂在 `Overlay`（`Theater`）上的
`OverlayEntry`，每个带 `GlobalKey`。对话框被 pop 时若焦点仍在 TextField 上，
框架会在同一帧里既销毁对话框、又把这些 OverlayEntry 重新挂载到新位置，
于是同一个 GlobalKey 在一帧内出现两次。

**原先的错误做法**（在每个按钮里各贴一次）：
```dart
FocusManager.instance.primaryFocus?.unfocus();
await Future<void>.delayed(const Duration(milliseconds: 16));
if (!ctx.mounted) return;
Navigator.pop(ctx, value);
```
两个洞：
1. **只覆盖按钮**。点遮罩（`barrierDismissible`）、系统返回键、
   输入法自带的「完成」全都绕过按钮。
2. **延迟不够**。16ms 只有一帧，键盘收起动画是 200~300ms。

**正确做法**：`lib/widgets/keyboard_safe_dialog.dart` 的
`showKeyboardSafeDialog()`，与 `showDialog` 同签名。
它在对话框内容外套一层 StatefulWidget，在**自己的 `dispose`** 里
`FocusScope.of(context).unfocus()`——无论从哪个出口关闭，
子树被拆时 dispose 必定执行，天然覆盖所有路径。

用 `FocusScope` 而不是 `FocusManager.instance.primaryFocus`：
后者可能已指向对话框之外的节点，误摘会让用户回到页面后发现别处失焦。

**但 scope 必须在 `didChangeDependencies` 里缓存，不能在 dispose 里现取。**
`FocusScope.of(context)` 内部走 `dependOnInheritedWidgetOfExactType`，
会注册一条 InheritedWidget 依赖；在 dispose 阶段元素正被停用，
于是触发框架断言：

```
'package:flutter/src/widgets/framework.dart':
Failed assertion: line 6268 pos 12: '_dependents.isEmpty': is not true.
```

（用户实测路径：开场白 UI 里点开叠加页编辑，再点空白处必现。）

**通用规则：dispose 里禁止任何 `XxxTheme.of(context)` /
`Scaffold.of(context)` / `MediaQuery.of(context)` 之类的 `of()` 调用**，
一律在 `didChangeDependencies` 提前缓存。
缓存的节点可能已随路由销毁，调用时要套 try。

**凡是内容里有 TextField 的 showDialog，一律改用这个包装。**
已替换：assembly 编辑器 8 处 + Studio 的 math_node_editor 1 处。

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

## 7. 最近关键提交（倒序）

**4.3b 状态变化通知**
- `fdf56e2` 修弹窗不出现（轮询覆盖 LLM 写入）+ openingUI 被回滚重现
- `378688b` 补 ChatAssemblyMount 的 sessionVersion 透传
- `7dff266` 修 identical 判不出原地修改 + notifyStyle 被 silent 吃掉
- `cc84396` 通知系统主体（废除否决权 + 弹窗/浮窗队列）

**状态栏 ⇄ UI 同步**
- `9ba93fd` 文本/开关/下拉的内容也随绑定同步
- `d4ad321` 修 min/max/current 输入框不随绑定刷新，且保存时反向覆盖同步结果
- `f3e34ac` 数据通道专项页改为不落盘，由实例编辑器统一裁决
- `1097939` 修专项页保存后外层不刷新、且保存时会删掉配置
- `cf4d06b` 修新建绑定时不同步、反而把状态栏值冲掉
- `e8dc5e6` 修同步不生效：漏了复合件覆写项 + 撤销栈被污染
- `9db3e40` UI 改动反写回状态栏 + 量程一并同步
- `720f9f8` 状态栏与 UI 的初始值双向同步 + 预绑定词条提示

**4.3 HUD**
- `67025db` 名称输入框加状态字段建议 + 段落标题改正式
- `254761a` 数据通道页三段重排 + 平铺控件 + 圆角下拉

**灵感池 4.1 / 4.2**
- `5a7c7b7` 修正 4.2：叠加层不能变成子叠加层
- `647e6fb` 叠加页拖放换父级
- `28578b2` 普通原子也必须留在 PCB 内（补齐三态分类 + 旋转死锁修复）
- `b83259b` 拖出 PCB 自动后台化（双阈值滞回）

**聊天页首帧空窗（详见 3.5d）**
- `0fec4fc` 背景加同步缓存 + 启动预热，聊天页首帧即有背景
- `6af8a45` 背景查询移出 build，缓存到 state（修默认渐变闪一帧）
- `d48186c` 会话副本提到初始化链首读（修开场白要等半秒）
- `98ac344` 加 `_sessionReady` 闸门（修开场白先闪后消失）
- `d985253` 开场白判定加快速标记 + 缓存（消除每帧 JSON 解析）
- `86d29ef` 关闭开场白改为先隐藏再落盘

**聊天页**
- `c49041c` 修键盘弹出遮挡底部气泡

---

## 8. 新对话里建议直接说明的话

可以在新对话一开始直接说：

> 继续 `ASSEMBLY_HANDOFF.md` 的上下文，分支 `arena/019fa2fe-llm-project`。
> A2~A14 主线全部完成并测试通过，灵感池 4.1（拖出 PCB 后台化）、
> 4.2（叠加页拖放换父）、4.3（数据通道页重构）、
> 4.3b（状态变化通知系统）也已完成，
> 状态栏 ⇄ UI 初始值双向同步已打通。
> 灵感池六项已全部处理完毕（4.2 判定不做后被推翻并实现、
> 4.4 转为开发约定、4.5/4.6 早已实现）。
> 下一步方向待定，可问用户。
> 请遵守每一步完成后 commit/push、非阻塞问题并入下一步的节奏；
> 沙箱没有 Flutter SDK，提交前提醒我本地跑 analyze/test。

**动手前务必先读 `3.5b 「双写覆盖」陷阱` 与 `3.5c 会话副本同步陷阱`**
——这两处各自连栽了三四次。
