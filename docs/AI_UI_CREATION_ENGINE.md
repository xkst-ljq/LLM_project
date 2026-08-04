# AI 深度创作 · UI 转译引擎 设计方案

> 目标：让转译 AI 从「套固定模板」升级为「**深度思考创作**」——
> 在尽可能还原原卡的同时，调用 UI engine 的能力做出高质量、有特色
> 的 UI。这样玩家才有从酒馆转译过来的动力。
>
> 本文档是**设计稿**，确认后按此实现。状态：`🟡 设计中`

---

## 1. 背景与动机

### 1.1 当前问题（为什么必须升级）

现有转译工具的 `runBuildUiStage` 是**纯确定性规则**：

1. `RegexUiExtractor` 提取正则脚本的字段
2. `pickPrimary` **只挑字段最多的那条脚本**做主面板
3. `UiAssemblyBuilder` 用固定模板（状态栏+选项+叠加层）生成

这张表清楚说明了短板（以「异世界公会」为例，13 条脚本）：

| 原卡脚本 | 内容 | 当前转译结果 |
|---|---|---|
| 玩家状态栏 | Name/Level/XP/HP/MP/STR/... | ✅ 被挑出，生成状态栏 |
| 任务界面 ×3 | quest/type/desc/reward/location... | ❌ 被当「换肤」丢弃 |
| 玩家选项栏 ×2 | option1/2/3_text/input_prompt | ❌ 被丢弃 |
| 好友列表 | name1/level1/equip1/... | ❌ 被丢弃 |
| 阅读界面 ×5 | 不同皮肤 | ❌ 被丢弃 |

**根因**：`pickPrimary` 的假设「多条脚本 = 换肤」对黑曜石成立，对
异世界公会这种「**多套不同功能 UI**」的卡不成立。规则无法区分
「换肤」和「不同功能」，需要 **AI 的语义理解**。

### 1.2 用户明确要求

1. **AI 深度思考创作**，可调用 UI engine 的各种工具
2. 尽可能**还原原卡** + 在此之上**优化**
3. AI 先产生**创意**，再在 UI engine 的 **API 库**里思考如何实现
4. **思考过程写入日志**，让用户明晰 AI 是如何思考这张卡的转译的
5. 转译 AI 不再只是「翻译出来」，而是带有 UI engine 的特色

---

## 2. 架构总览：AI 出「意图」，代码出「JSON」

这是整个方案**最重要的一条原则**。

### 2.1 为什么 AI 不能直接生成 assembly JSON

项目代码里反复强调（见 `ui_assembly_builder.dart` 头注释）：
assembly JSON 是**三层嵌套字符串**，有一堆「写错不报错、只是静默失效」的陷阱：

- `elements`/`pages` 是嵌套 JSON 字符串，少一层 encode 就读不到
- `material`/`shape` 是枚举下标 int，写 `'solid'` 会静默回落 0
- `color` 是 ARGB int，不是 `#RRGGBB`
- `createdAt` 是毫秒时间戳
- `keyAction` 键名错 → 整层不渲染

AI 直接生成 JSON 必然出错，且**错得静默**（不报错、不生效、极难排查）。

### 2.2 因此采用「意图 → JSON」两段式

```
原卡正则/HTML
   │
   ▼
┌─────────────────────────────┐
│ Step A · AI 深度思考（LLM）   │
│  - 识别面板（状态栏/任务/...）  │
│  - 产生创意设计意图            │
│  - 查 UI engine API 库定方案   │
│  - 思考过程 → 日志            │
│  输出：结构化的「设计意图」      │
└─────────────┬───────────────┘
              │ (JSON, 校验通过才继续)
              ▼
┌─────────────────────────────┐
│ Step B · 确定性生成（代码）    │
│  - 把「意图」翻译成合法 JSON   │
│  - 算坐标 / 绑数据通道 / 联动器 │
│  输出：完整 ui_assemblies     │
└─────────────────────────────┘
```

**Step A 负责「想」**（AI 出语义化意图，容错宽松）
**Step B 负责「做」**（代码出精确 JSON，杜绝静默错误）

这样既满足「AI 深度创作」，又守住「JSON 不出错」的底线。

---

## 3. UI engine API 库（给 AI 的能力清单）

Step A 的 system prompt 里，把 UI engine 的能力以「API 库」形式给 AI，
让它在创意后据此思考如何实现。这份清单要**准确、完整、可被 AI 使用**。

### 3.1 页面模式（mode）

| mode | 含义 | 特点 |
|---|---|---|
| `scene` | 场景 UI | 全屏接管聊天页，可承载多页、多套面板 |
| `opening` | 开场白弹窗 | 开场时全屏，玩家确认后进入 |
| `extra_companion` | 伴生 UI | 内嵌在最新 AI 气泡里（≤212px 宽） |
| `extra_sticky` | 常驻 UI | 悬浮小窗，可折叠 |

### 3.2 组件原语（21 种）

| 组件 | 用途 |
|---|---|
| `surface` / `base_box` | 底板 / 面板容器 |
| `text` | 文本（可绑数据通道 / 富文本 / 滚动） |
| `progress` | 进度条（量程 / 轨道 / 胶囊） |
| `button` | 点击热区（sendsMessage / keyAction） |
| `input` | 文本输入框（回车提交） |
| `select` | 下拉选择 |
| `switch` | 开关 |
| `slider` | 滑块 |
| `indicator` | 指示点 / 状态灯 |
| `image` | 图片（本地 / 内联） |
| `line` | 分割线 |
| `linker` | 逻辑连线（数据流 / 控制流） |
| `page_router` | 页面路由（切页 / 打开叠加层） |
| `math_node` | 计算节点 |
| `timer` | 定时器 |
| `message_flow` | 内嵌消息流 |
| `primitive_art` / `surface_art` / `light_effect` | 装饰 / 光效 |

### 3.3 联动器方案（linker scheme，摘选）

- `button_to_page_route`：按钮 → 切页 / 打开叠加层
- `click_to_surface_press`：按钮 → 表面按压动画
- `click_to_switch_toggle` / `_set_true` / `_set_false`：按钮 → 开关
- `click_to_input_clear` / `click_to_slider_reset`：重置输入/滑块
- `input_commit_to_text` / `input_live_to_text`：输入 → 文本
- `bool_to_visible` / `boolean_to_enabled`：条件显隐 / 启用
- `event_to_animation` / `event_to_indicator`：事件 → 动画 / 指示
- `input_nonempty_to_button_enable`：输入非空才可点按钮

### 3.4 数据通道（Data Channel）

- 组件绑定 `status_field`，LLM 可**读写**（实时更新数值）
- 数值字段：`suggest_delta`（增量更新）
- 文本字段：`suggest_replace`（整值替换）
- 这是「数据值实时更新」的实现机制

### 3.5 富文本

- `text` 组件 `richText: true` → 渲染 HTML/Markdown
- `overflow: scroll` → 长文滚动

---

## 4. 数据结构：AI 输出的「设计意图」

AI 的 Step A 输出一个结构化 JSON（`UiCreationIntent`），这是「意图层」，
不直接是 assembly JSON。

```json
{
  "panels": [
    {
      "kind": "status_bar",        // 面板类型
      "title": "冒险者状态",
      "page": "status",            // 放到哪页
      "fields": [
        {"name": "HP", "type": "number", "display": "progress"},
        {"name": "MP", "type": "number", "display": "progress"}
      ]
    }
  ],
  "scene": {
    "mode": "scene",
    "pages": [
      {"id": "status", "name": "状态"},
      {"id": "quests", "name": "任务"}
    ],
    "activePage": "status",
    "style": "fantasy_parchment"   // 可选：风格提示
  },
  "layout": "如：状态页顶部角色名，左列进度条，右列属性"
}
```

**意图层只表达「有什么面板、什么字段、放哪、大概怎么排」**，
具体的坐标、JSON 嵌套、ARGB 颜色、枚举下标都由 Step B 代码计算。

### 4.1 面板类型（kind）识别维度

AI 依据字段名/正则结构判断面板类型：

| kind | 字段特征（举例） |
|---|---|
| `status_bar` | HP/MP/XP/STR/AGI/INT 等数值 + Name/Class/Weapon 文本 |
| `quest_list` | quest/type/desc/reward/location/time 等 |
| `option_bar` | option1_text/option2_text/input_prompt 等 |
| `friend_list` | name1/level1/equip1/status1 等 |
| `read_skin` | 纯皮肤（阅读界面），无数据槽 → 不转 |
| `unknown` | 无法判断 → 保守不转 |

---

## 5. 代码流程

### 5.1 Step A · AI 深度思考（新文件 `ai_ui_designer.dart`）

```
输入：提取结果（脚本/字段/原始HTML）+ UI engine API 库清单 + 卡名
  ↓
LLM 调用（system prompt = 创作角色 + API 库；user prompt = 原卡脚本摘要）
  ↓ 输出
解析 `UiCreationIntent`（JSON）
  ↓ 校验
字段合法（kind 已知、page 存在、display 支持）
  ↓
把 AI 的思考过程写入日志（见 §6）
```

### 5.2 Step B · 确定性生成（扩展现有 `UiAssemblyBuilder`）

新增一个 `buildSceneFromIntent(UiCreationIntent)`：

- 按 `intent.scene` 创建 scene 的 pages
- 按 `intent.panels` 在每个 page 摆放元素（progress/text/surface/button/input）
- 绑定数据通道（数值 → suggest_delta，文本 → suggest_replace）
- 加 page_router 切换 + 顶部 Tab
- 复用现有的 `_element/_module/_text/_progress/_button/_channel` 等工厂
  （保证 JSON 正确性）

### 5.3 流水线接入（`pipeline.dart`）

`runBuildUiStage` 改造：

1. 先跑 `RegexUiExtractor` 提取
2. 若有可识别脚本 → 调 `AiUiDesigner.design(...)`（Step A）
3. 拿到意图 → `UiAssemblyBuilder.buildSceneFromIntent(...)`（Step B）
4. Step A 失败（未配置 AI / 解析失败）→ **回退**到现有确定性模板
   （不破坏流程，和 ai_classifier 的回退策略一致）

### 5.4 与现有「动作叠加层」的关系

- 黑曜石这类「有 `<选项>` 动作」的卡：仍走现有动作叠加层逻辑
- 异世界这类「多套面板」的卡：走 AI 创作引擎
- 两者不冲突：AI 创作引擎负责「多面板 scene」，动作叠加层负责「动作选项」

---

## 6. 思考日志（AI 如何思考这张卡）

每次转译，把 AI 的思考过程写入转换日志（`CardConversionResult.notes` 或单独
`thinkingLog` 字段），格式：

```text
── UI 生成 · AI 思考日志 ──
1. 识别：这张卡有 13 条正则脚本
2. 分类：玩家状态栏 → status_bar（含 HP/MP/XP/STR 等数值）
         任务界面 ×3 → quest_list（quest/desc/reward）
         玩家选项栏 ×2 → option_bar
         阅读界面 ×5 → read_skin（纯皮肤，跳过）
3. 决策：采用 scene 全屏，分「状态 / 任务」两页
4. 布局：状态页顶部角色名，左列 HP/MP/XP 进度条（绑数据通道，
          LLM 实时更新），右列核心属性文本
5. 选型：HP/MP/XP 用 progress（量程 0-100），属性用 text（绑通道），
         页间用 button_to_page_route 切换
6. 还原度：覆盖原卡状态栏 + 任务列表；选项栏原卡无按钮形态，省略
```

用户能看到 AI 每一步的思考，增强可信度。

---

## 7. 异世界公会 · 完整示例

### 7.1 AI 识别（Step A 输出意图）

```json
{
  "scene": {"mode": "scene", "pages": [
    {"id": "status", "name": "状态"},
    {"id": "quests", "name": "任务"}
  ], "activePage": "status"},
  "panels": [
    {
      "kind": "status_bar", "page": "status",
      "title": "XKST · Lv.1 冒险者(E级)",
      "fields": [
        {"name": "HP", "type": "number", "display": "progress", "min": 0, "max": 100},
        {"name": "MP", "type": "number", "display": "progress", "min": 0, "max": 100},
        {"name": "XP", "type": "number", "display": "progress", "min": 0, "max": 100},
        {"name": "STR", "type": "number", "display": "text"},
        {"name": "AGI", "type": "number", "display": "text"}
      ]
    },
    {
      "kind": "quest_list", "page": "quests",
      "fields": ["quest", "type", "desc", "reward"]
    }
  ]
}
```

### 7.2 代码生成（Step B 输出 scene JSON）

- 状态页：progress×3（HP/MP/XP 绑数据通道）+ text×若干（属性/装备）
- 任务页：surface 卡片 ×N，内含 quest/desc/reward 文本
- 两页间 page_router 切换 + 顶部 Tab

### 7.3 日志

见 §6 示例。

---

## 8. 风险与兜底

| 风险 | 对策 |
|---|---|
| AI 返回非法 JSON | 解析失败 → 回退现有确定性模板 |
| AI 识别错误面板 | 意图校验（kind 白名单），非法 kind 丢弃 |
| AI 想要的布局代码不支持 | 代码只支持已实现的原语，超出则跳过并记日志 |
| 未配置 AI | 直接走现有确定性模板（不依赖 AI） |
| AI 静默生成坏 JSON | 两段式：AI 只出语义化意图，JSON 由代码生成 |

---

## 9. 实施步骤（确认后）

1. **新建 `ai_ui_designer.dart`**：Step A，AI 识别 + 创意 + 意图输出 + 日志
2. **扩展 `ui_assembly_builder.dart`**：`buildSceneFromIntent`，Step B
3. **改 `pipeline.dart`**：`runBuildUiStage` 接 Step A/B，失败回退
4. **UI engine API 库清单**：沉淀为常量，供 Step A prompt 引用
5. **异世界公会验证**：跑通全链路，看还原度 + 日志
6. **文档回填**：把实现结果写回本文档状态

---

## 10. 待确认点

- [ ] 两段式「AI 出意图 / 代码出 JSON」是否符合预期？
- [ ] 面板类型（status_bar/quest_list/option_bar/friend_list）维度是否够？
- [ ] 思考日志放 `notes` 还是独立 `thinkingLog` 字段？
- [ ] 场景页数上限？（scene 支持多页，建议 ≤5 页，避免过度复杂）
- [ ] 优先做 scene 还是也支持 extra_companion 的 AI 创作？
