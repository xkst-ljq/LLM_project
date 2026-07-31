# 示例角色卡与 UI 方案样板

## 文件

| 文件 | 用途 |
|---|---|
| `织_夜航酒保_UI测试卡.llmcard` | 可直接导入的测试卡 |
| `generate_sample_card.py` | 生成脚本，改参数即可产出新卡 |

## 这张卡覆盖了什么

三套 UI，覆盖全部 mode 与主要组件类型：

| mode | 名称 | 尺寸 | 内容 |
|---|---|---|---|
| `extra_sticky` | 状态挂件 | 212×150 | 进度条 / 状态点 / 文本，绑 4 个状态字段 |
| `scene` | 吧台场景 | 360×640 | 消息流 + 滑块 + 下拉 + 开关 + 输入 + 按钮 |
| `opening` | 开场白 | 320×380 | 文本 + 输入 + 下拉 + 确认按钮 |

**状态栏字段 5 个**：数值 3（信任度 / 信用点 / 警戒等级）+ 文本 2（心情 / 时段），
三种 owner（char / player / neutral）都有。

**数据通道 10 条**，覆盖 `status_field` 与 `session_var` 两类，
通知方式 `silent` / `toast` / `dialog` 三档齐全，
其中「玩家身份」故意留成**预绑定**（targetId 为空、pendingName 有值），
用来验证状态栏编辑页的「未创建字段」提示。

---

## 给 LLM 生成 UI 时的硬约束

转译 SillyTavern 卡片时，让模型照这些规则产出，可以避免生成出来的 UI 打不开。

### 1. 结构层级

```
meta.ui_assemblies: [ JSON字符串, ... ]   ← 注意是字符串数组，不是对象数组
  └ { id, name, mode, pages: "JSON字符串", pcbWidth, pcbHeight, ... }
      └ pages: [ { id, name, type, elements: [...], gestures, propertyOverrides } ]
          └ elements: [ { id, offset, size, layerIndex, parentSurfaceId, module } ]
```

`pages` 与 `ui_assemblies` 都是**被 JSON 编码过的字符串**，不是嵌套对象。

### 2. 必须遵守的规则

| 规则 | 说明 |
|---|---|
| **keyAction** | `opening` / `scene` / `extra_sticky` 必须**至少有一个**按钮带 `keyAction: true`，否则玩家会被卡死，运行时会拦截 |
| **元素不出 PCB** | 除 `linker`/`math_node`/`timer`/`page_router` 外，所有元素必须完全落在 `0,0,pcbWidth,pcbHeight` 内 |
| **容器组连续** | 用了 `parentSurfaceId` 时，父面元素必须排在组员**之前** |
| **PCB 尺寸** | 宽 120~600（`extra_companion` 上限 212）；高 64~2000。超出会被静默 clamp |
| **select 的 current** | 必须是 `options` 里某个 `value`，否则保存时被打回第一项 |
| **sourceComponentId** | 数据通道里这个值必须等于所在元素的 `id` |
| **id 唯一** | 同一张卡内所有元素 id 不得重复 |

### 3. 数据通道

```json
"dataChannel": {
  "semanticLabel": "信任度",
  "targetKind": "status_field",     // status_field | session_var | card_entry | local_ui_state
  "targetId": "sbf_trust",          // status_field 时必须指向真实字段 id
  "pendingName": "",                // 字段还不存在时填名字、targetId 留空
  "sourceComponentId": "<所在元素id>",
  "llmReadPolicy": "prompt",        // none | prompt | hidden_context
  "llmWritePolicy": "suggest_delta",// none | suggest_delta | suggest_replace
  "notifyStyle": "toast",           // silent | toast | dialog
  "notifyTemplate": "信任 {old} → {new}",  // 可选，支持 {name} {old} {new}
  "promptSection": "ui_data"        // ui_data | core_setting
}
```

**通知方式的选择**：数值频繁小幅变动用 `silent` 或 `toast`；
升级、警戒提升这类玩家要据此做决策的才用 `dialog`（会阻断操作）。

### 4. 各 mode 的推荐尺寸

代码只在 120~600（宽）/ 64~2000（高）范围内做硬约束，
以下是**观感上合适**的取值，样板卡用的就是这组：

| mode | 推荐 | 说明 |
|---|---|---|
| `opening` | 320×380 | 居中弹出，别做满屏 |
| `scene` | 360×640 | 全屏接管，按手机比例 |
| `extra_sticky` | 212×150 | 常驻挂件，越小越好 |
| `extra_companion` | ≤212 宽 | 嵌在消息气泡里，宽度有硬上限 |

### 5. 显示值要与字段初始值对齐

绑定了状态字段的组件，其初始显示值应与字段的 `initial_value` 一致：

- `progress` / `slider` → `current` 等于初始值，且 `min`/`max` 与字段量程相同
- `text` → `text` 等于初始值

不一致也能跑（编辑器打开时会自动同步），但导入后第一眼看到的是错的。

### 6. 常用组件的必填 properties

| 类型 | 必填 |
|---|---|
| `text` | `text`, `fontSize` |
| `progress` | `current`, `min`, `max`, `progressShape` |
| `slider` | `current`, `min`, `max`, `step` |
| `select` | `options`(label/value 数组), `current`, `defaultValue` |
| `switch` | `value` |
| `input` | `placeholder`, `text` |
| `button` | `hitArea: true`；要显示文字加 `showTextOnRuntime: true` + `text` |
| `message_flow` | `historyLimit`, `fontSize`, `showUser`, `showAssistant` |
| `surface` | 作容器时加 `is_overlay_container: true` |
| `indicator` | `dotSize`, `defaultGlow` |

### 7. 图片

`image` 组件的 `assetPath` 若填本地路径，分享时会被自动内联成 data URI。
LLM 生成时**不要编造本地路径**——要么留空，要么用 `https://` 网址。
