# ST 卡「UI」机制图谱（5 张真实样本实测）

> 结论来自 `samples/st_reference/` 下 5 张卡的实际解析，不是推测。
> 阶段 3 识别层的设计依据。

## 一句话结论

**ST 卡的 UI 不写在 `description` 里，而是靠 `extensions.regex_scripts`
把 LLM 输出的结构化标记替换成 HTML。**

5 张卡里 `description` 的内联 HTML 数量：**全部为 0**。

## 样本概览

| 卡 | 大小 | 世界书 | 正则脚本 | UI 机制 |
|---|---|---|---|---|
| 黑曜石·法外特区 | 199KB | 30 | 2 | `tag_capture` 17 字段 |
| 玲茹 | 67KB | 14 | 3 | `bar_capture` 12 字段 |
| 异世界公会 | 184KB | 22 | 13 | `bar_capture` + 装饰壳 |
| 丧尸末日系统 | 44KB | 8 | **0** | 纯文本，无 UI |
| WuWa Solaris-3 | 3.4MB | 426 | 14 | **MVU 插件**（外部 JS） |

## 四种模式（识别层必须分类处理）

### ① `tag_capture` —— 自定义 XML 标签

```regex
<正文>(.*?)<\/正文>.*?<生命>(.*?)<\/生命>.*?<精神>(.*?)<\/精神>...
```

**标签名即语义字段名**，作者已替我们标注好，不需要 AI 猜。

黑曜石一条正则捕获 17 个字段：
正文/称号/编号/罪名/生命/精神/体力/饱腹/势力/关系/声望/点数/物品/位置/日期/时间/选项。

### ② `bar_capture` —— 竖线分隔（**信息最丰富**）

```regex
\[日期地点:(.*?)\|性欲值:(\d+).*?\|当前进度:(\d+)\/\d+\|...\]
{PlayerStatus\|Name:(.+?)\|Level:(\d+)\|XP:(\d+)\/(\d+)\|HP:(\d+)\/(\d+)\|...}
```

**自带类型信息**，比 ① 更好用：

| 捕获写法 | 含义 | 映射到 |
|---|---|---|
| `(\d+)` | 数值 | `progress` / `text` |
| `(.*?)` `(.+?)` | 文本 | `text` |
| `(\d+)\/(\d+)` | **当前/最大** | `progress` 的 current + max |

`XP:(\d+)/(\d+)` 这种直接给出量程，无需推断。

### ③ `placeholder` —— 纯装饰壳

```regex
<Alliance>          →  一大段带 border/gradient 的 div，无数据槽
```

**只换外观、不承载数据。这类不应转成 UI 组件**，
它等价于排版样式，硬转只会生成一个空壳。

### ④ `cleanup` —— `replaceString` 为空

`[隐藏]去除变量更新`、`[杀八股]清除多余标点` 等。
**纯粹删文本，与 UI 无关，必须跳过。**
样本里 34 条脚本有 12 条属于此类，占比不低。

## 视觉形态可直接映射

以黑曜石「状态栏」的 `replaceString`（5959 字符）为例：

| 原卡写法 | 数量 | 对应我们的 |
|---|---|---|
| `<div style="width: $5">` 内层条 | 4 | `progress` |
| `display: flex` | 11 | 横向排布 |
| `border-radius` | 7 | `surface.borderRadius` |
| `box-shadow` 发光 | 5 | 外观 / `glowPulse` |
| `linear-gradient` | 1 | `material: gradient` |

作者常用 HTML 注释标出功能分区，**等于自带布局说明**：

```
顶部警戒条 / 正文 / 监控仪表盘 / 资产社交 / 物品栏 / 决策引导 / 底部位置
```

## 交互：`onclick="send('...')"`

```html
<div onclick="send('选择开场1：新人入狱')">[01] 新人入狱</div>
```

`send()` 是 ST 内置函数，点击即发送该字符串为用户消息。
**正好对应我们的 `button` + `sendsMessage` 标记。**

## MVU 插件卡：明确不支持

`WuWa Solaris-3` 依赖外部 JS：

```
https://.../MagVarUpdate/artifact/bundle.js
https://.../tavern_resource/dist/util/mvu_zod.js
```

6 个 tavern_helper 脚本全部启用，状态栏 HTML 达 **77595 字符**，
变量模型定义在世界书 `[initvar]` 条目里（YAML 格式的嵌套结构）。

这类卡的 UI 是**运行时由 JS 动态生成**的，静态分析拿不到最终形态。

**处理策略：识别出来 → 明确告知「依赖外部插件，UI 无法转译」→
只转文本内容。** 不要硬转出一个半残的界面。

检测特征：
- `extensions.tavern_helper` 存在且含 `"type": "script"`
- 脚本 `content` 里有 `import 'https://...'`

## 对识别层的直接指导

**输入优先级：**

1. `extensions.regex_scripts` 中 `replaceString` 非空的条目 —— 主要来源
2. `first_mes` 里的 `onclick="send(...)"` —— 交互意图
3. 内联 HTML —— 5 张卡里为 0，兜底即可
4. 纯文本 —— **不生成 UI**（用户明确要求「原版没有的不去设计」）

**AI 的任务不是「从散文里找 UI」**，而是：

- 读 `findRegex` 拿到字段名与类型（这步**纯代码即可**，不用 AI）
- 读 `replaceString` 判断每个字段的视觉形态（这步需要 AI 理解 CSS）
- 输出结构化意图描述，交给代码去生成合法 JSON

**丧尸末日系统**（0 条正则）证明「无 UI 的卡」真实存在且不罕见，
识别层必须能干脆地返回「不生成」。
