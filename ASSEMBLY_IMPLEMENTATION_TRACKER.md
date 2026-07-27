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
| A10 | mode 差异逻辑收口 | 未开始 | ⏳ |
| A11 | 消息流窗口 | 未开始 | ⏳ |
| A12 | 高级动画 | 未开始 | ⏳ |

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

## A11：消息流窗口

### 要点
- 独立组件，不作为普通 text 变体
- 接受用户消息 / LLM 回复
- append + 自动滚到底
- scene / extra_companion 可见

---

## A12：高级动画

### 示例
- 数值跳动
- 发光脉冲
- 粒子反馈
- 更高阶页面切换特效

> 明确属于锦上添花，不阻塞前面主流程完成。

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