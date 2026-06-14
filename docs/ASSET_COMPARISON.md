# 酒馆角色卡 vs LLM Project 资产 —— 对照与迁移策略

> 目的：把 SillyTavern / TavernAI 角色卡尽可能**无损**迁移过来。
> 结论先行：真正的难点不是「字段名对不上」，而是**注入行为差异**和**少量缺口**。

---

## 一、酒馆卡有什么（排除高级脚本）

V2 (`chara_card_v2`) 的 `data`：

| 字段 | 作用 | 酒馆注入时机 |
| --- | --- | --- |
| name | 角色名 | 常驻 |
| description | 核心人设（最重要） | 常驻 |
| personality | 性格 | 常驻 |
| scenario | 场景 | 常驻 |
| first_mes | 开场白 | 首条 |
| alternate_greetings[] | 备用开场白 | 可切换 |
| mes_example | 对话示例 | 常驻 / 按需 |
| system_prompt | 覆盖系统提示 | 系统位 |
| post_history_instructions | 历史之后指令 | 对话历史**之后** |
| creator_notes / tags / creator / character_version | 元信息 | 不注入 |
| character_book{} | 内嵌世界书 | 关键词触发 |
| extensions / regex / depth_prompt | 脚本扩展 | 高级（范围外） |

V1：顶层 name/description/personality/scenario/first_mes/mes_example。

---

## 二、我们有什么

- **CharacterCard**：name / description / systemPrompt / worldBookId /
  cardType / entriesJson / openingGreetings / userDetailSetting / backgroundId /
  **metaJson（批1新增）**
- **条目 entriesJson**（人物卡）：
  - 核心（每轮常驻）：`name_entry`、`relationship`
  - 详细（周期注入）：`body`、`psychology`、`background`、自定义条目
- **WorldBook**：title / content / keyword(逗号分隔) / alwaysActive(=constant) / recursive
- **PromptSettings**：角色扮演规则、连续性提醒、summaryInterval(默认3)、
  fullDetailInterval(默认12)、worldBookScanDepth(默认4)

### 实际 system prompt 组装顺序（chat_page `_buildFinalSystemPrompt`）

```
systemPrompt字段(基底, 每轮常驻)
 + [角色扮演规则]
 + [世界设定]        ← 世界书激活条目
 + [当前用户名称]
 + [核心角色设定]     ← 每轮: name_entry / relationship
 + [连续性提醒]
 + [周期性摘要设定]   ← 每 summaryInterval 轮(截断)
 + [周期性完整设定]   ← 每 fullDetailInterval 轮: body/psychology/background + 自定义
```

> 关键事实：`CharacterCard.description` 字段**不进 prompt**，只用于详情展示。

---

## 三、三类差异

### A. 能对上（基本无损）
name、first_mes + alternate_greetings(→开场白)、system_prompt、
character_book(→世界书，基础字段)、creator/notes/version/tags(→ meta_json 保留)。

### B. 冲突（字段对得上，行为不同）⚠️
1. **description 不进 prompt** —— 酒馆里它常驻；直接对存等于丢。
2. **常驻 vs 周期** —— description/personality/scenario 在酒馆常驻；放进我们详细条目后变每 12 轮一次。
3. **条目是结构化 JSON** —— 我们 `{"origin":...}`，酒馆是自由文本，无法精确拆分。

### C. 缺失（我们没有）
1. ~~**历史后注入位**（post_history_instructions）——真缺口。~~ ✅ 批3 已补齐。
2. **标签系统**（tags）。
3. **世界书高级触发**（次关键词/优先级/位置/深度/概率/防递归）——只能降级。
4. **示例对话专门位**（mes_example）。
5. 高级能力（正则/扩展/depth_prompt/表情/语音）——只保留不执行。

---

## 四、迁移策略（最终落到我们的逻辑，体验/信息识别与酒馆无差）

- **缺失（C）**：逐批补齐（见下方批次计划）。批1 已用 `meta_json` 统一承载，
  标签 / 作者 / 来源 / post_history / mes_example 先入库保留，UI 与注入按批开放。
- **冲突（B）**：交由后续转换工具（005-B AI 智能归类 + 005-C 精修对照）处理，
  规则阶段先兜底（结构化字段用单字段填充，不硬拆）。
- **高级（A 之外）**：保留原始第三方 JSON（禁用条目）+ 转换报告提示。

---

## 五、补缺失功能 —— 批次计划

| 批次 | 内容 | 改动面 | 状态 |
| --- | --- | --- | --- |
| 批1 | `meta_json` + 详情展示元信息 | 模型 / DB(v3) / 详情页 / 转换器 / 备份 / 资产 | ✅ 已完成 |
| 批2 | 标签筛选（角色库）+ 编辑页编辑标签 | 角色库 / 编辑页 | ✅ 已完成 |
| 批3 | 历史后注入位（post_history_instructions） | prompt 引擎 / 编辑页 / Prompt 策略 | ✅ 已完成 |
| 批4 | 示例对话注入位（mes_example） | prompt 引擎 / 编辑页 | 待做 |
| 世界书高级触发 | 概率/位置/深度/防递归等 | 世界书引擎（= Roadmap 1.3.6） | 靠后，转换降级 |

工具开发顺序：**先 PC 端做到完美，再删减移植到移动端项目。**

---

## 六、meta_json 结构

存放在 `characters.meta_json`（默认 `{}`），由 `CharacterMeta` 解析：

```json
{
  "tags": ["oc", "tsundere"],
  "creator": "someone",
  "creator_notes": "推荐温度 0.9",
  "character_version": "1.1",
  "source_format": "SillyTavern / Character Card V2",
  "post_history_instructions": "...",
  "mes_example": "..."
}
```

默认不注入 Prompt；批3 / 批4 会让 post_history / mes_example 进入注入链。
