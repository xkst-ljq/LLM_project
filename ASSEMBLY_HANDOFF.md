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
- 最小开放：页面路由器、联动器、按钮、文本、进度条、已暴露端口复合组件
- 当前 linker 只完成拖入 / 移动 / 保存恢复；接线能力归 A5 实现

### A4 暴露端口体验增强：基础版完成，待本地测试
已做：
- Assembly 复合组件暴露端口改为边轨 + 晶体视觉
- 端口颜色沿用 customColor 或子组件类型默认色
- 左侧输入 / 右侧输出分别显示在对应边轨
- 每个端口命中区域扩大到 28×28
- 按下端口时有轻量放大 / 发光高亮
- Tooltip 显示输入/输出与子组件名称

### A5 Assembly 内 linker 连线：配置式 MVP 完成，待本地测试
已做：

- 双击 Assembly 内 `linker` 可打开配置弹窗
- 可选择当前页面内 button 作为来源
- 可选择当前页面内 page_router 作为目标
- 保存为 `button.tap → linker → page_router.trigger`
- 编辑态点击已连接 button 可触发 page_router 跳页
- 可清除 linker 连接

### 下一步建议
- 先本地测试 A4 暴露端口体验增强与 A5 配置式 linker MVP
- 若通过，再进入 A8 运行时缩放

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

> 继续 `ASSEMBLY_HANDOFF.md` 的上下文，当前分支是 `arena/019f9cee-llm-project`，A2/A6/A3-1/A3-2/A3-3/A3-4/A7/A7.5/A5-0 已完成，A4 暴露端口体验增强与 A5 Assembly 内 linker 连线配置式 MVP 已完成待本地测试。通过后继续 A8 运行时缩放。请遵守每一步完成后 commit/push、非阻塞问题并入下一步处理的节奏。
