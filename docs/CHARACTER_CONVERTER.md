# 第三方角色卡转换工具（005）

> 目标：把 SillyTavern / TavernAI 角色卡（非高级指令部分）转换为 LLM Project
> 角色卡（`.llmcard`），先在 PC 上做稳定，再裁剪整合进移动端。

本工具不执行酒馆脚本 / 正则 / 扩展插件，只做**解析 + 规则映射 + 保留**。

---

## 模块结构

转换核心是**纯 Dart**（不依赖 Flutter / dart:io），PC 与移动端共用：

```text
lib/tools/character_converter/
  conversion_models.dart        # 结果 / 报告数据结构
  png_chara_reader.dart         # 读取 PNG tEXt/zTXt/iTXt 中的 chara/ccv3
  third_party_card_detector.dart# 识别 PNG / ZIP(.llmcard) / V1 / V2
  character_card_mapper.dart    # ST/Tavern 字段 -> LLM Project 结构
  conversion_service.dart       # 对外入口：单份 / 批量转换
  conversion_writer.dart        # 平台层：写 .llmcard + 报告（用 dart:io / archive）
```

UI（Flutter）：

```text
lib/pages/character_converter_page.dart   # 设置页 → 角色卡转换工具
```

测试：

```text
test/character_converter_test.dart
```

---

## 字段映射（V1 / V2 → LLM Project）

| 源字段 | 去向 | 说明 |
| --- | --- | --- |
| `name` | `name` + 名称条目 | 必需，缺失则转换失败 |
| `description` | `description` + 背景数据.origin | 启用 |
| `personality` | 心理数据.personality | 有内容则启用 |
| `scenario` | 自定义条目「当前场景」 | 启用 |
| `mes_example` | 自定义条目「示例对话」 | 启用 |
| `first_mes` | 开场白[0] | |
| `alternate_greetings` | 开场白[1..] | |
| `system_prompt` | `system_prompt` | |
| `post_history_instructions` | 自定义条目「后置指令」 | 默认**不启用**，需用户确认 |
| `creator` / `character_version` / `spec` / `tags` | 自定义条目「来源信息」 | 默认不启用（不注入 Prompt） |
| `creator_notes` | 自定义条目「作者备注」 | 默认不启用 |
| `character_book` | LLM Project 世界书，并绑定到角色 | 高级触发规则降级为关键词 |
| 原始 JSON 整体 | 自定义条目「原始第三方角色卡数据」 | 默认不启用，便于以后重转 |

### 世界书条目映射（character_book.entries）

| 源 | 去向 |
| --- | --- |
| `keys` + `secondary_keys` | `keyword`（逗号拼接） |
| `content` | `content` |
| `comment` / `name` | `title` |
| `constant` | `always_active` |
| `enabled` | （默认启用） |
| `priority` / `insertion_order` / `position` / `depth` / `probability` / `selective` / `case_sensitive` | **降级**，报告中提示 |

### 不支持 / 仅保留（不执行）

`extensions`、`regex_scripts`、`depth_prompt`、`talkativeness`、群聊、表情立绘、voice/TTS。
这些会在转换报告里标注，原始数据保留在「原始第三方角色卡数据」条目中。

---

## 输出

批量转换会在输出基目录下新建时间戳目录：

```text
<Downloads 或 文档目录>/LLM Project/Converted Cards/YYYYMMDD_HHMMSS/
  角色名.llmcard
  角色名 (1).llmcard      # 重名自动去重
  conversion_report.json
  conversion_report.txt
```

生成的 `.llmcard` 与 `CharacterCardAssetService` 的格式一致，可直接被本应用的
「导入角色卡」识别（导入时会重新分配 id、处理重名、重映射世界书绑定）。

---

## 运行 / 打包

### 开发调试

```bash
flutter pub get
flutter test test/character_converter_test.dart   # 验证转换核心
flutter run -d windows                             # 桌面
flutter run                                        # Android
```

### 启用桌面平台

仓库当前只有 `android/`。要做 PC 工具，先生成桌面平台脚手架：

```bash
flutter create --platforms=windows,linux,macos .
```

桌面拖拽依赖 `desktop_drop`（移动端不生效，已做平台判断）。

### Windows Release 打包

```bash
flutter build windows --release
# 产物：build/windows/x64/runner/Release/  整个文件夹打包成 zip 分发
```

### Android Release 打包

```bash
flutter build apk --release
# 或分架构：flutter build apk --split-per-abi
```

---

## 后续（按讨论的三道工序）

当前已完成**第一道：规则解析 + 映射 + 输出 + 报告**。

后续增强（可选，需用户 API）：

1. **第二道 AI 智能归类**：把混在一个字段里的多类设定拆分归类，
   允许最小必要改写（补主语、换代词、调语序），**禁止新增事实**，
   每段输出带 `source_refs` + `transform_type` + `risk`。
2. **第三道 AI 检查精修**：覆盖检查（漏转）、忠实性检查、新增事实检查、
   重复归类检查，输出结构化修正建议。
3. **源文对照视图**：左原始字段 / 右转换结果 / 来源关系 + 改写类型 + 风险等级。

移动端整合：在「导入角色卡」时自动识别第三方格式并调用同一套核心，
仅做单文件 / 简单多文件，不做文件夹扫描与大对照视图。
