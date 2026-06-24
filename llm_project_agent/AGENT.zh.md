# AGENT.md - LLM_Project AI 代理工作守则

> 规范正本：英文版 `AGENT.md` 为准。本文为中文参考版，如有冲突以英文版为准。
> 补丁工具：`tools/patch/apply_patch_multi.html`（浏览器版，免安装）/ `tools/patch/apply_patch_multi.py`（命令行版）

## 0. 总则

- **Think in English. Respond in Chinese.**
  内部推理、变量命名、代码注释用英文；给用户的解释、报告、UI 文案用中文
  搜代码优先英文符号名，中文 UI 文案作为二次确认

---

## 1. 工作模式

```
[讨论模式]  默认
  允许：read_file / grep / bash(只读) / web_search / 推理
  禁止：write_file / edit_file / 任何文件写入

[编辑模式]  仅在用户明确说 "开始编辑" / "动手改" / "执行" / "go edit" 后进入
  允许：所有工具
  退出：必须切回讨论模式，并交付 补丁 + 改动总结
```

用户还在聊需求时，禁止偷偷改文件。

---

## 2. 编辑前铁律

### R1. 先调研，后编码
- 写任何业务代码前：
  1. clone / read 仓库
  2. 并行读 3~5 个相关文件：data model、现有导入导出、真实 JSON 结构
  3. 用中文汇报：我理解的项目结构 + 本次交付物是什么 / 不做什么
- 调研完成前，0 行业务代码输出

### R2. 禁止幻觉
- 任何 `old_text` / SEARCH 块必须是文件中逐字复制的真实代码
- 禁止：`$1` / `...` / `// 保留原样` / `/* 其余不变 */` 等任何占位符
- 缺版本号 / 参考文件必须先问，禁止 "assume based on description"
- 文件 >1500 行，必须分块读完目标区域前后 80 行

### R3. 难点先验证
- 文件格式解析 / 二进制读取 / 第三方映射 → 先写最小可运行原型验证，再写正式代码

---

## 3. 编辑时铁律

### R4. Flutter / Dart 零低级错误
- 必须通过：`dart format .` 和 `flutter analyze --no-fatal-infos`，0 error / 0 warning
- const 能加就加
- BuildContext 禁止跨 async gap，不加 `if (!mounted) return` 不许用
- Null safety 完整
- 无重复 Key

### R5. 防溢出 / 防冲突检查清单（每次 edit 前过一遍）
- [ ] 布局：Row/Column 用 Expanded/Flexible，文本 `overflow: TextOverflow.ellipsis`，长列表限定高度
- [ ] 状态：setState 前检查 mounted，不在 build() 里改状态
- [ ] ID/Key：用项目 ID 工具生成，不手写时间戳，不重复 Key
- [ ] 兼容：360px 小屏和 1200px 宽屏都检查
- [ ] 数据结构：entries_json / CharacterCard 以 `character_edit_page.dart` 为准，不擅自改字段

### R6. 工具纪律
- 定位：grep -n → read 对应区间 → 复制 old_text
- 编辑：一次只改一个逻辑点（一个 SEARCH/REPLACE 块）
- 验证：改完 read 回来确认
- 工具连续失败 2 次立刻停下来汇报，禁止第 3 次盲试
- 中文 grep 0 结果立刻切英文符号名

---

## 4. 编辑后交付

### R7. 补丁优先交付

**默认输出：Multi-File SEARCH/REPLACE 总补丁**

1. **补丁格式** — 一个代码块包含本次所有改动的文件：
```
--- File: lib/pages/ui_studio_page.dart
<<<<<<< SEARCH
// 旧代码，从原文件逐字复制，带 3~5 行上下文，确保匹配唯一
=======
 // 新代码
>>>>>>> REPLACE

--- File: lib/tools/new_helper.dart (new)
<<<<<<< SEARCH
=======
 // 新文件全部内容
>>>>>>> REPLACE

--- File: lib/old_unused.dart (delete)
```
- `--- File: 路径` — 每个文件一条
- `(new)` 后缀 = 新建文件，SEARCH 体为空
- `(delete)` 后缀 = 删除文件，无需 SEARCH 块
- 单个文件内可放多个 SEARCH/REPLACE 块，按从上到下顺序应用
- `old` 文本必须是原文件逐字复制，带足够上下文确保唯一匹配
- 本次任务所有改动的文件，打包进 **一个总补丁**

2. **Workspace**
   - 完整文件始终写入 workspace，可下载
   - 补丁工具：`tools/patch/apply_patch_multi.html` / `tools/patch/apply_patch_multi.py`

3. **聊天输出顺序**
   ```
   1. 改动总结 (R8)
   2. 总补丁 — Multi-File SEARCH/REPLACE
   3. Workspace 文件路径
   4. 验证步骤
   ```

4. **全文兜底**
   - 新建文件 < 500 行 → 可直接贴全文
   - 用户说 "贴全文" → 必须立刻贴出完整文件，>800 行分多条发，截断前先警告
   - 禁止静默遗漏

**为什么补丁优先：** 相比全文粘贴省 ~90% token，用户一键工具合并，零遗漏风险。

### R8. 改动总结（每次编辑完必须给）
```
本次改动：
- 文件 A: 做了什么，为什么
- 文件 B: 做了什么，为什么
- 新增/删除: ...

如何验证：
1. flutter analyze
2. flutter run -d ...
3. 打开 xx 页面，检查 xx

预期结果：xxx
受影响文件：path/to/a.dart, path/to/b.dart
```

### R9. 分层 + 可追溯
- models / parser / mapper 分文件
- 优先纯 Dart，无 Flutter 依赖，方便测试
- 不支持字段降级保存，不丢失，输出 converted / unsupported 清单
- 提供 toReport() / toPlainText()

---

## 5. 输出前自检

- [ ] 读到完整目标区域了吗？
- [ ] SEARCH 的 old_text 是复制的吗？有占位符吗？
- [ ] flutter analyze 过了吗？0 error / 0 warning？
- [ ] 溢出/冲突清单过过了吗？
- [ ] 总补丁包含本次所有改动文件了吗？路径正确？`(new)` / `(delete)` 标记对了吗？
- [ ] 改动总结 + 验证步骤写了吗？
- [ ] Workspace 文件更新了吗？

有一项 NO 就不许提交。

---

## 6. LLM_Project 专用锚点

- `ui_studio_page.dart` > 2500 行，原子预览卡片在 ~1740–1830，搜索关键词 `_buildPreviewDraggableCard`，禁止搜中文 UI 文案
- `CharacterCard.entries_json` 结构以 `lib/pages/character_edit_page.dart` 为准
- ID 生成：`IdUtils.timestampId()` — `lib/utils/id_utils.dart`
- 第三方角色卡转换器：`lib/tools/character_converter/`，保持纯 Dart
- 补丁工具：`tools/patch/apply_patch_multi.html`（拖入项目文件夹 + 粘贴补丁 → 下载 ZIP）

---

## 7. 补丁格式速查

**修改已有文件：**
```
--- File: lib/pages/example.dart
<<<<<<< SEARCH
  final name = data['name'];
  if (name.isEmpty) return;
=======
  final name = (data['name'] ?? '').toString().trim();
  if (name.isEmpty) {
    notes.add('name missing');
    return;
  }
>>>>>>> REPLACE
```

**新建文件：**
```
--- File: lib/tools/my_helper.dart (new)
<<<<<<< SEARCH
=======
import 'dart:convert';
/// My helper
...
>>>>>>> REPLACE
```

**删除文件：**
```
--- File: lib/old_file.dart (delete)
```

**单文件多处修改：** 多个 SEARCH/REPLACE 块，按从上到下顺序堆叠。

**给 LLM 的提示：**
- SEARCH 块包含 3~5 行上下文，确保匹配唯一
- 每个 SEARCH 块只改一个逻辑点
- 本次任务所有文件打进一个总补丁
- 生成补丁前先跑 `flutter analyze`

---

此文件放在仓库根目录，所有 Agent 必须遵守。
