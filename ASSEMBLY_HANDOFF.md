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

### A9.5 通用模板基础版：A9.5-2 完成，测试通过
定位：A10 mode 差异化之前的前置阶段。先把所有模式共用的通用模板 / 通用运行时底座做稳，不急着分化 opening / scene / extra。

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

A9.5-3 通用模板测试样板已写入 tracker，样板结构：
- 主菜单 base
- 状态面板 overlay
- 设置面板 overlay
- 第二 base 页

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

### A9.6 SSOT / LLM 数据交互 MVP：A10 前置
定位：打通 UIengine 与会话状态、Prompt、LLM 回复之间的数据通路。目标链路为：

```text
UI 输入 / 选择 / 滑动
→ SessionState.vars 或 SessionState.statusValues
→ Prompt 注入
→ LLM 回复
→ 状态更新解析
→ UI 刷新
```

建议顺序：
- A9.6-0：SSOT / LLM 数据交互设计文档
- A9.6-1：Binding 名称解析 / 预绑定机制
- A9.6-2：UI 写入 SessionState MVP
- A9.6-3：SessionState 注入 Prompt MVP
- A9.6-4：LLM 回复更新状态预留

### 下一步建议
- 先按 A9.5-3 样板做一轮通用模板回归
- 将问题并入 A9.5-4 通用运行时问题收口
- 然后进入 A9.6-0：SSOT / LLM 数据交互设计文档

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

> 继续 `ASSEMBLY_HANDOFF.md` 的上下文，当前分支是 `arena/019f9cee-llm-project`，A2/A6/A3-1/A3-2/A3-3/A3-4/A7/A7.5/A5-0/A4/A5/A8/A9 已完成，A9.5 通用模板基础版规划、A9.5-2 基础原子入口、A9.5-3 通用模板测试样板文档已完成。下一步按样板做通用模板回归并进入 A9.5-4 通用运行时问题收口，随后进入 A9.6-0 SSOT / LLM 数据交互设计文档。请遵守每一步完成后 commit/push、非阻塞问题并入下一步处理的节奏。
