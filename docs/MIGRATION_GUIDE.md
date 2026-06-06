# 从其他角色卡格式迁移到 LLM Project

> 适用于 Demo 1.2.5 及之后版本。  
> 本文主要说明如何将 SillyTavern 等其他工具中的角色卡内容，半自动迁移到 LLM Project。

当前 LLM Project **暂不支持直接导入 SillyTavern 角色卡**。  
原因是不同软件的角色卡结构、世界书逻辑、高级命令、宏、脚本和预设系统并不一致，直接兼容容易导致导入后效果偏差。

不过，你可以通过下面的流程，将其他角色卡中的核心内容整理后迁移到 LLM Project。

---

## 目录

- [1. 迁移前需要知道的事](#1-迁移前需要知道的事)
- [2. 迁移整体流程](#2-迁移整体流程)
- [3. 从 SillyTavern 角色卡中提取内容](#3-从-sillytavern-角色卡中提取内容)
- [4. 导出 LLM Project 的空白角色卡模板](#4-导出-llm-project-的空白角色卡模板)
- [5. 把内容交给 AI 整理](#5-把内容交给-ai-整理)
- [6. 将整理结果填入 LLM Project](#6-将整理结果填入-llm-project)
- [7. 世界书迁移方法](#7-世界书迁移方法)
- [8. 破甲 / 预设 / 高级命令应该放在哪里](#8-破甲--预设--高级命令应该放在哪里)
- [9. 常见问题](#9-常见问题)

---

## 1. 迁移前需要知道的事

### 1.1 LLM Project 为什么不直接导入 SillyTavern 卡？

SillyTavern 的角色卡常常包含：

```text
角色名
描述
性格
场景
开场白
备用开场白
示例对话
System Prompt
世界书 / Lorebook
扩展字段
宏命令
正则规则
脚本
预设
```

其中基础文本内容可以迁移，但高级功能并不能直接等价迁移。

例如：

```text
{{user}}
{{char}}
{{random::A::B}}
Regex 脚本
Quick Reply
STScript
特殊扩展字段
```

这些内容依赖原平台的运行环境。  
如果直接导入到 LLM Project，可能会出现：

```text
字段不对应
高级命令失效
世界书触发逻辑不同
角色表现和原平台不一致
部分脚本无法执行
```

因此当前阶段更推荐：

```text
提取基础文本内容 → 交给 AI 整理 → 手动填入 LLM Project
```

---

### 1.2 SillyTavern 的 PNG 角色卡不能直接改成 zip 解压

请注意：

```text
SillyTavern 的 PNG 角色卡通常不是压缩包。
```

所以直接把：

```text
xxx.png
```

改成：

```text
xxx.zip
```

大概率打不开。

SillyTavern 通常是把角色卡 JSON 数据藏在 PNG metadata 中。  
你需要通过 SillyTavern 本身或相关工具把里面的文本字段提取出来。

相反，LLM Project 的：

```text
.llmcard
```

本质是压缩包，可以改成 `.zip` 解压查看内部结构。

---

## 2. 迁移整体流程

整体流程如下：

```text
1. 从 SillyTavern 或其他工具中提取角色卡文本内容
2. 在 LLM Project 中新建一张空白角色卡
3. 导出这张空白角色卡为 .llmcard
4. 将 .llmcard 改名为 .zip 并解压
5. 取出 data/character.json 作为 LLM Project 模板
6. 把“原角色卡内容”和“LLM Project 模板”一起发给 AI
7. 让 AI 按 LLM Project 的结构整理内容
8. 手动复制整理结果到 LLM Project 的角色卡编辑页
9. 如果有世界书，再按世界书模板迁移
```

---

## 3. 从 SillyTavern 角色卡中提取内容

### 3.1 如果你可以打开 SillyTavern

这是最推荐的方式。

操作步骤：

```text
1. 打开 SillyTavern
2. 导入你想迁移的角色卡
3. 进入角色编辑页面
4. 复制角色卡中的关键字段
```

建议复制这些字段：

```text
name
角色名

 description
描述

 personality
性格

 scenario
场景

 first_mes
第一条开场白

 alternate_greetings
备用开场白

 system_prompt
系统提示词

 post_history_instructions
后置指令

 mes_example
示例对话

 creator_notes
作者备注，如果有用

 character_book / lorebook / world info
世界书内容，如果有
```

如果 ST 里可以导出 JSON，也可以直接把 JSON 内容复制出来。

---

### 3.2 如果你只有一张 ST PNG 图片卡

不要直接把图片发给 AI。  
AI 通常只能看到图片表面，看不到隐藏在 PNG metadata 里的角色卡数据。

你可以选择下面几种方法：

```text
方法 1：用 SillyTavern 导入这张图片，再从编辑页复制字段
方法 2：使用 Tavern 角色卡查看器 / 提取工具读取 PNG 内的 chara 数据
方法 3：让能打开 SillyTavern 的朋友帮你导出 JSON
```

你最终需要拿到的是文本内容或 JSON，而不是只有图片表面。

---

## 4. 导出 LLM Project 的空白角色卡模板

为了让 AI 理解 LLM Project 的字段结构，可以先导出一张空白角色卡作为模板。

### 操作步骤

1. 打开 LLM Project。
2. 进入角色库。
3. 点击右上角 `+`。
4. 选择：

```text
新建角色卡
```

5. 给它随便填一个名字，例如：

```text
迁移模板
```

6. 保存后，选中这张角色卡。
7. 点击导出按钮。
8. 选择：

```text
导出完整角色卡文件
```

9. 得到一个文件：

```text
迁移模板_xxx.llmcard
```

10. 把这个文件复制到电脑上。
11. 将后缀改成：

```text
.zip
```

例如：

```text
迁移模板_xxx.llmcard
```

改成：

```text
迁移模板_xxx.zip
```

12. 解压后会看到类似：

```text
manifest.json
data/character.json
assets/
```

其中最重要的是：

```text
data/character.json
```

这个文件就是 LLM Project 的角色卡结构模板。

> 注意：你不需要手动修改这个 JSON。  
> 它主要是给 AI 看，让 AI 理解 LLM Project 的字段结构。

---

## 5. 把内容交给 AI 整理

你需要准备两部分内容：

### 第一部分：原角色卡内容

来自 SillyTavern 或其他工具，例如：

```text
name
description
personality
scenario
first_mes
alternate_greetings
system_prompt
mes_example
world info
```

或者完整 JSON。

### 第二部分：LLM Project 模板

也就是刚刚解压出来的：

```text
data/character.json
```

---

## 5.1 推荐给 AI 的提示词

你可以复制下面这段给 AI，然后把原角色卡内容和 LLM Project 模板贴在后面。

```text
我现在要把一张 SillyTavern 角色卡手动迁移到 LLM Project。

下面我会提供两部分内容：

1. SillyTavern 角色卡提取出的原始字段或 JSON。
2. LLM Project 导出的角色卡 data/character.json 模板。

请你帮我把 SillyTavern 角色卡内容整理成适合 LLM Project 手动填写的内容。

要求：
1. 不要编造原卡没有的信息。
2. 保留角色名称、描述、性格、背景、关系、说话风格、开场白。
3. first_mes 转为开场白 1。
4. alternate_greetings 转为更多开场白。
5. system_prompt 和 post_history_instructions 整理到 system prompt 或自定义条目“回复规则”中。
6. personality 主要整理到“心理数据”。
7. scenario 和 description 主要整理到“背景数据”或“简短描述”。
8. mes_example 整理为自定义条目“示例对话”。
9. 如果有 character_book / lorebook / world info，请整理为世界书条目，每个条目包含标题、关键词、是否常驻、内容。
10. 如果遇到 SillyTavern 高级命令、宏、脚本或正则，不要尝试执行，只把能读懂的文本规则整理出来。
11. 输出结果要方便我复制进 LLM Project 的编辑界面，而不是只输出代码。
12. 如果某些字段无法判断，请留空或标注“原卡未明确提供”。
```

然后继续输入：

```text
【SillyTavern 原始内容】
在这里粘贴 ST 角色卡内容

【LLM Project character.json 模板】
在这里粘贴 data/character.json 内容
```

---

## 5.2 希望 AI 输出成什么样？

建议让 AI 输出下面这种结构，方便你手动复制。

```md
# LLM Project 迁移结果

## 角色卡类型
人物卡 / 系统卡

## 角色名称
...

## 简短描述
...

## System Prompt
...

## 简单介绍

### 名称
姓：
名：
其他：

### 与用户关系
...

## 详细设定

### 身体数据
种族：
性别：
年龄：
身高：
体重：
三围：
其他：

### 心理数据
性格：
思想：
兴趣/爱好/癖好：

### 背景数据
出身背景：
经历事件：
当前背景：

## 自定义条目

### 回复规则
...

### 示例对话
...

## 开场白

### 开场白 1
...

### 开场白 2
...

## 世界书条目

### 条目 1
标题：
关键词：
常驻：是 / 否
递归：是 / 否
内容：
```

---

## 6. 将整理结果填入 LLM Project

AI 整理好后，在 LLM Project 中新建或编辑角色卡。

### 6.1 填入基础信息

在角色卡编辑页填写：

```text
角色卡名称
简短描述
头像
卡片封面
人物卡 / 系统卡
```

### 6.2 填入 System Prompt

如果 AI 输出了 System Prompt，复制到角色卡的系统提示词编辑页。

System Prompt 适合放：

```text
角色扮演规则
回复风格
不跳出角色
不代替用户行动
语言风格
破甲/回复约束的纯文本部分
```

### 6.3 填入角色设定条目

按照 AI 输出的内容填写：

```text
名称
与用户关系
身体数据
心理数据
背景数据
自定义条目
```

如果某些字段原卡没有，就留空。

### 6.4 填入开场白

将：

```text
first_mes
```

填入：

```text
开场白 1
```

将：

```text
alternate_greetings
```

填入更多开场白。

---

## 7. 世界书迁移方法

如果原卡包含世界书 / Lorebook / Character Book，可以让 AI 整理成下面格式。

```md
# LLM Project 世界书迁移结果

## 世界书名称
...

## 简短描述
...

## 条目

### 条目 1
标题：
关键词：
常驻：是 / 否
递归：是 / 否
内容：

### 条目 2
标题：
关键词：
常驻：是 / 否
递归：是 / 否
内容：
```

然后在 LLM Project 中：

```text
世界书库 → 新建世界书 → 添加条目
```

填入整理后的内容。

完成后回到角色卡编辑页，绑定该世界书。

---

## 8. 破甲 / 预设 / 高级命令应该放在哪里

当前版本暂时没有独立的 Prompt 预设库 / 破限库。

如果原卡包含破甲、回复规则、预设内容，可以按下面方式临时迁移。

### 8.1 适合放入 System Prompt 的内容

```text
角色扮演规则
回复风格
禁止跳出角色
不代替用户行动
不代替用户思考
叙事视角
语言风格
输出格式
```

### 8.2 适合放入自定义条目的内容

```text
说话习惯
特殊规则
角色禁忌
示例对话
剧情约束
行为风格
```

### 8.3 适合放入世界书常驻条目的内容

```text
长期生效的世界观规则
系统规则
背景设定
通用限制
场景规则
```

### 8.4 不建议直接迁移的内容

```text
STScript
Quick Reply 脚本
复杂 Regex 自动化
依赖原平台变量系统的宏命令
无法理解含义的扩展字段
```

这些内容可以先保留为普通文本备注，但不建议期待它们自动生效。

---

## 9. 常见问题

### Q：我可以直接导入 SillyTavern 的 PNG 角色卡吗？

当前不支持。

SillyTavern 的 PNG 角色卡通常将角色数据写在 PNG metadata 中，而 LLM Project 使用自己的资产格式。  
当前版本不会直接读取 SillyTavern 的卡片数据。

---

### Q：把 ST 的 PNG 改成 zip 可以解压吗？

通常不可以。

ST PNG 角色卡一般不是压缩包。  
LLM Project 的 `.llmcard` 才是压缩包，可以改成 `.zip` 解压查看。

---

### Q：我可以直接把图片发给 AI，让 AI 帮我迁移吗？

不推荐。

AI 通常只能看到图片表面，看不到 PNG metadata 里隐藏的角色卡 JSON。  
你需要先从 ST 或工具里提取文本字段，再交给 AI 整理。

---

### Q：高级命令和宏能不能自动转换？

当前不能。

可以让 AI 尝试把其中能读懂的文本规则整理成普通设定，但不要期待它们像在原平台一样自动执行。

---

### Q：迁移后的角色效果会和原平台完全一致吗？

不保证。

不同平台的 Prompt 拼接方式、世界书触发方式、高级命令支持程度不同。  
迁移的目标是保留角色核心设定和开场体验，而不是完全复刻原平台行为。

---

## 10. 推荐迁移顺序

如果你要迁移一张复杂角色卡，建议按下面顺序：

```text
1. 先迁移角色名、简短描述、开场白
2. 再迁移 System Prompt
3. 再迁移身体 / 心理 / 背景设定
4. 再迁移示例对话和回复规则
5. 最后迁移世界书条目
6. 进入聊天页测试
7. 根据实际回复效果微调设定
```

不要一次性把所有内容乱塞进同一个字段，否则模型可能难以理解。

---

## 11. 总结

当前推荐迁移方式是：

```text
提取原角色卡文本
+
导出 LLM Project 空白模板
+
交给 AI 整理
+
手动填入 LLM Project
```

这不是完全自动化，但比逐字手动迁移轻松很多，也能避免高级字段不兼容导致的混乱。

后续版本可能会提供更方便的迁移辅助工具，但当前阶段以稳定和可控为优先。
