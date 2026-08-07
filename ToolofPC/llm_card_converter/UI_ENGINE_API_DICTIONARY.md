# UIEngine API Dictionary

> 机器可读版本：`lib/core/ui_engine_api/ui_engine_api_dictionary.dart`。
>
> 本文件说明“字典式 API”的使用方式。完整事实源以 Dart 常量为准，避免 Flutter asset 配置和 JSON 解析带来的额外复杂度。

## 目标

转译 AI 不再靠一次性背完整 UIEngine 文档，而是按以下流程工作：

1. 先阅读能力索引，知道有哪些 mode / component / linker / layout pattern。
2. 需要使用某个组件时，查询字典路径，例如：
   - `components.text`
   - `components.progress`
   - `components.message_flow`
   - `modes.scene`
   - `semanticRoles.keyAction`
   - `layoutPatterns.opening_then_scene`
3. 根据查到的详细 API 输出 `UiDesignPlan`。
4. Validator / 编译器使用同一份字典做合法性约束。

## 字典结构

```text
UiEngineApiDictionary.root
├── modes
│   ├── opening
│   ├── scene
│   ├── extra_sticky
│   └── extra_companion
├── components
│   ├── surface
│   ├── text
│   ├── progress
│   ├── button
│   ├── input
│   ├── select
│   ├── switch
│   ├── slider
│   ├── line
│   ├── indicator
│   ├── image
│   └── message_flow
├── logicComponents
│   ├── page_router
│   ├── linker
│   ├── math_node
│   └── timer
├── semanticRoles
│   ├── keyAction
│   └── sendsMessage
├── dataChannel
├── linkerSchemes
├── layoutPatterns
└── limitations
```

## 代码查询示例

```dart
final textApi = UiEngineApiDictionary.lookup('components.text');
final overflow = UiEngineApiDictionary.lookup(
  'components.text.properties.overflow',
);
final scene = UiEngineApiDictionary.lookup('modes.scene');
final component = UiEngineApiDictionary.component('base_box'); // alias -> surface
```

## 给 AI 的 compact prompt

`UiEngineKnowledgeService.compactPrompt()` 会调用：

```dart
UiEngineApiDictionary.compactReferenceForTranslator()
```

生成压缩版能力说明，包含：

- mode 关键语义；
- 所有主要可见组件及 properties 索引；
- 逻辑组件；
- linker scheme 分组；
- 已知限制；
- scene/message_flow 与 overlay 页面转译约束。

## Scene 与 overlay 转译约束

- `scene` 会抑制原生聊天列表，所以如果要接管聊天页，`layout.pages` 必须至少有一个 `role: "story" | "message" | "narrative" | "content" | "log"` 的 base 页面；编译器据此插入 `message_flow`。
- 只在 `notes` 里写“建议使用 message_flow”不会生成组件。
- 低频详情页可用：`{"title":"任务板", "role":"tasks", "type":"overlay", "parentPage":"公会大厅"}`。编译器会在父页面生成打开叠加页的入口按钮。
- overlay 仍然在同一 PCB 内渲染，不能设计成放不下内部字段的小浮窗；编译器会用 overlay 内容高度和 scene 最小高度扩展 PCB，并把 story 页的 `message_flow` 拉伸填满，长任务/好友文本应继续用 `overflow=scroll`。
- 正文页应保留 `message_flow`、当前选项按钮和自由输入；完整状态栏、任务板、羁绊名录等拥挤内容应优先放入 overlay。

## 后续扩展方式

新增组件 / 属性 / linker 时，优先修改：

```text
lib/core/ui_engine_api/ui_engine_api_dictionary.dart
```

然后再视需要更新：

```text
UI_ENGINE_CAPABILITY_AUDIT.md
UiDesignPlan schema
UiPlanValidator
UiAssemblyBuilder
```

这样可以保证：

```text
AI 知识库
Validator
编译器
人类文档
```

不会互相漂移。
