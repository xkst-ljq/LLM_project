/// 从 SillyTavern 卡的 `extensions.regex_scripts` 里提取 UI 意图。
///
/// ## 为什么是纯代码，不用 AI
///
/// 实测 5 张真实卡（见 `samples/st_reference/ANALYSIS.md`）后发现：
/// **ST 卡的 UI 不写在 `description` 里**，而是靠正则把 LLM 输出的
/// 结构化标记替换成 HTML。而 `findRegex` 里已经写明了字段名与类型：
///
/// ```
/// <生命>(.*?)</生命>        → 字段「生命」，文本
/// |性欲值:(\d+)|            → 字段「性欲值」，数值
/// |XP:(\d+)/(\d+)|          → 字段「XP」，数值 + 自带量程
/// ```
///
/// 作者已经替我们标注好了，**不需要 AI 从散文里猜**。
/// AI 只在下一步用得上——判断 `replaceString` 里那几千字符 CSS
/// 对应什么视觉形态。
///
/// ## 四种模式（必须分类，否则会转出垃圾）
///
/// | 模式 | 特征 | 处理 |
/// |---|---|---|
/// | [UiRegexKind.tagCapture] | `<字段>(.*?)</字段>` | ✅ 抽字段 |
/// | [UiRegexKind.barCapture] | `\|字段:(\d+)\|` | ✅ 抽字段（**自带类型**） |
/// | [UiRegexKind.decoration] | `<Alliance>` 无捕获组 | ❌ 纯装饰壳，无数据 |
/// | [UiRegexKind.cleanup] | `replaceString` 为空 | ❌ 只删文本，与 UI 无关 |
///
/// 样本里 34 条脚本有 **12 条是 cleanup**（`[杀八股]清除多余标点` 之类）。
/// 不识别出来就会把「删标点的正则」当成 UI 去生成。
///
/// ## 插件卡直接拒绝
///
/// `tavern_helper` 里 `import 'https://...'` 的卡（如 MVU），
/// UI 由外部 JS 运行时生成，**静态分析拿不到最终形态**。
/// 硬转会产出半残界面，比不转更糟——识别出来后明确告知用户。

/// 正则脚本的用途分类。
library;

import 'greeting_sanitizer.dart';

enum UiRegexKind {
  /// `<字段>(.*?)</字段>` —— 自定义 XML 标签。
  tagCapture,

  /// `|字段:(\d+)|` —— 竖线分隔，自带类型信息，最好用。
  barCapture,

  /// 无捕获组的纯样式替换（`<Alliance>` → 一大段 div）。
  ///
  /// 只换外观、不承载数据。转成 UI 只会得到一个空壳，
  /// 它等价于排版样式而非界面组件。
  decoration,

  /// `replaceString` 为空——只删文本。
  cleanup,

  /// 认不出来的写法。保守起见不转，但要报告给用户。
  unknown,
}

/// 字段的值类型，由捕获组写法推断。
enum UiFieldType {
  /// `(\d+)` —— 纯数字。
  number,

  /// `(\d+)/(\d+)` —— 当前值 + 上限，直接对应 progress 的量程。
  ranged,

  /// `(.*?)` / `(.+?)` —— 任意文本。
  text,

  /// 捕获的是文本，但 HTML 里被用作 `width: $N`
  /// ——即百分比进度条（`width: 72%`）。
  ///
  /// 这类字段光看 `findRegex` 判不出来，必须结合 `replaceString`。
  /// 实测黑曜石卡的「生命/精神/体力/饱腹」正是如此：
  /// 捕获写的是 `(.*?)`，但 CSS 里 `width: $5`~`width: $8` 泄露了真实用途。
  percent,
}

/// 从正则里抽出的一个语义字段。
class UiField {
  const UiField({
    required this.name,
    required this.type,
    required this.captureIndex,
    this.maxCaptureIndex,
  });

  /// 字段名（作者写的，如「生命」「XP」）。
  final String name;

  final UiFieldType type;

  /// 对应第几个捕获组（1-based，与 `$1` `$2` 一致）。
  ///
  /// [UiRegexKind.tagCapture] 的 `replaceString` 用 `$N` 引用捕获组，
  /// 要靠这个下标把「字段」和「HTML 里的位置」对上。
  final int captureIndex;

  /// `ranged` 类型的上限所在捕获组。
  final int? maxCaptureIndex;

  /// 适合渲染成 progress 的字段。
  bool get isNumeric =>
      type == UiFieldType.number ||
      type == UiFieldType.ranged ||
      type == UiFieldType.percent;

  UiField withType(UiFieldType t) => UiField(
        name: name,
        type: t,
        captureIndex: captureIndex,
        maxCaptureIndex: maxCaptureIndex,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'captureIndex': captureIndex,
        if (maxCaptureIndex != null) 'maxCaptureIndex': maxCaptureIndex,
      };

  @override
  String toString() => '$name(${type.name}@$captureIndex)';
}

/// 一条正则脚本的解析结果。
class UiRegexScript {
  const UiRegexScript({
    required this.scriptName,
    required this.kind,
    required this.fields,
    required this.replaceLength,
    required this.visuals,
    this.sections = const [],
    this.rawReplace = '',
  });

  final String scriptName;
  final UiRegexKind kind;
  final List<UiField> fields;

  /// `replaceString` 的长度。几千字符通常意味着一个完整面板。
  final int replaceLength;

  /// 从 CSS 里数出来的视觉特征，供后续判断组件形态。
  final UiVisualHints visuals;

  /// 作者用 HTML 注释标出的功能分区。
  ///
  /// 实测很多卡会写 `<!-- 监控仪表盘 -->` 这类注释，
  /// **等于自带布局说明**，比从 CSS 反推可靠。
  final List<String> sections;

  /// 原始 `replaceString`。交给 AI 判断视觉形态时要用。
  final String rawReplace;

  bool get usable =>
      kind == UiRegexKind.tagCapture || kind == UiRegexKind.barCapture;

  Map<String, dynamic> toJson() => {
        'scriptName': scriptName,
        'kind': kind.name,
        'fields': fields.map((f) => f.toJson()).toList(),
        'replaceLength': replaceLength,
        'visuals': visuals.toJson(),
        'sections': sections,
      };
}

/// 从 `replaceString` 的 CSS 里数出来的视觉线索。
class UiVisualHints {
  const UiVisualHints({
    this.progressBars = 0,
    this.flexRows = 0,
    this.borderRadius = 0,
    this.boxShadow = 0,
    this.gradient = 0,
    this.clickable = 0,
  });

  /// `width: $N` 的内层 div —— 这是 HTML 里画进度条的标准手法。
  final int progressBars;

  final int flexRows;
  final int borderRadius;
  final int boxShadow;
  final int gradient;

  /// `onclick="send('...')"` —— 对应我们的 button + sendsMessage。
  final int clickable;

  Map<String, dynamic> toJson() => {
        'progressBars': progressBars,
        'flexRows': flexRows,
        'borderRadius': borderRadius,
        'boxShadow': boxShadow,
        'gradient': gradient,
        'clickable': clickable,
      };
}

/// 开场白分支里的一个「接下来做什么」动作选项。
///
/// 原版卡（如黑曜石·法外特区）会在每个开场白正文末尾写一段 `<选项>`：
///
/// ```text
/// <选项>
/// 1.🤐【保持沉默】默不作声地按照指示上前，配合登记流程。
/// 2.🤝【尝试交涉】趁上前扫过登记台与周围狱警的配置...
/// 3.👊【确立威慑】故意拖慢了脚步...
/// 4.🏃【突然暴起】假装顺从地靠近登记台...
/// </选项>
/// ```
///
/// 每个动作由「序号 + emoji + 【标题】 + 描述」组成。
/// 点击后发送**整行原文**作为用户消息（原版在 ST 里通过
/// 状态栏的「💊 AVAILABLE ACTIONS」区展示，且 AI 可在对话中更新选项）。
class ActionOption {
  const ActionOption({
    required this.raw,
    required this.label,
    this.message,
  });

  /// 整行原文（`1.🤐【保持沉默】默不作声地按照指示上前，配合登记流程。`）。
  ///
  /// 点击动作按钮时发送的就是它。
  final String raw;

  /// 展示用标题（`【保持沉默】` / `保持沉默`）。
  final String label;

  /// 发送给 LLM 的动作文本。缺省时用 [raw]。
  final String? message;

  String get sendText => (message == null || message!.isEmpty) ? raw : message!;

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'label': label,
        if (message != null && message!.isNotEmpty) 'message': message,
      };
}

/// 整张卡的 UI 提取结果。
class UiExtraction {
  const UiExtraction({
    required this.scripts,
    required this.pluginDependent,
    required this.pluginUrls,
    required this.openingActions,
    required this.branchPresets,
    required this.branchActions,
    required this.notes,
    required this.cleanFirstMes,
  });

  final List<UiRegexScript> scripts;

  /// 是否依赖外部 JS 插件（MVU 之类）。
  ///
  /// 为真时**不要生成 UI**：那些界面由 JS 在运行时拼出来，
  /// 静态分析看到的只是模板骨架。
  final bool pluginDependent;

  final List<String> pluginUrls;

  /// `first_mes` 里 `onclick="send('...')"` 的文案。
  ///
  /// 这是明确的交互意图，对应 button + sendsMessage。
  final List<String> openingActions;

  /// 各开场分支的初始状态：分支下标 -> (字段名 -> 初值)。
  ///
  /// ## 数据从哪来
  ///
  /// `first_mes` 与 `alternate_greetings` 里就写着，例如：
  ///
  /// ```
  /// <精神>84%</精神><体力>92%</体力><势力>无</势力>
  /// ```
  ///
  /// 不同开场白往往给出**不同的起始值**——「新人入狱」精神 84%、
  /// 「狱警入职」精神 90%。这是作者精心设计的开局差异，
  /// 只取一套会把它们全抹平。
  ///
  /// 分支 0 = `first_mes`，之后依次是 `alternate_greetings`。
  final Map<int, Map<String, String>> branchPresets;

  /// 各开场分支的「接下来做什么」动作列表：分支下标 -> [ActionOption]。
  ///
  /// 原版每个开场白分支末尾各有一段 `<选项>`，动作互不相同
  /// （「新人入狱」和「狱警入职」的可选动作就完全不一样）。
  /// 转译时把这些动作作为该分支首条 AI 消息的一部分，
  /// 由引擎运行期的 message_flow 动态选项解析渲染成按钮，
  /// AI 也能在对话中更新选项。
  final Map<int, List<ActionOption>> branchActions;

  /// 净化的第一条消息文本，供 openingUI 整合卡内气泡显示。
  final String cleanFirstMes;

  /// 给用户看的说明（为什么某些脚本被跳过）。
  final List<String> notes;

  /// 可用于生成 UI 的脚本。
  List<UiRegexScript> get usableScripts =>
      scripts.where((s) => s.usable).toList();

  bool get hasUi => !pluginDependent && usableScripts.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'hasUi': hasUi,
        'pluginDependent': pluginDependent,
        'pluginUrls': pluginUrls,
        'openingActions': openingActions,
        'branchPresets': branchPresets
            .map((k, v) => MapEntry(k.toString(), v)),
        'branchActions': branchActions.map(
            (k, v) => MapEntry(k.toString(), v.map((a) => a.toJson()).toList())),
        'scripts': scripts.map((s) => s.toJson()).toList(),
        'notes': notes,
      };
}

/// 提取器本体。
class RegexUiExtractor {
  const RegexUiExtractor._();

  static UiExtraction extract(Map<String, dynamic> sourceJson) {
    // V3 卡的正文在 data 里，V2 直接在顶层。
    final data = sourceJson['data'] is Map
        ? Map<String, dynamic>.from(sourceJson['data'] as Map)
        : sourceJson;
    final ext = data['extensions'] is Map
        ? Map<String, dynamic>.from(data['extensions'] as Map)
        : <String, dynamic>{};

    final notes = <String>[];

    // ── 插件依赖检测 ──
    // 先判这个：依赖外部 JS 时后面的分析都没意义。
    final pluginUrls = _detectPluginUrls(ext);
    final pluginDependent = pluginUrls.isNotEmpty;
    if (pluginDependent) {
      notes.add('这张卡依赖外部 JS 插件（${pluginUrls.length} 个），'
          'UI 由脚本在运行时生成，静态分析无法还原——只转文本内容。');
    }

    // ── 逐条解析正则 ──
    final raw = ext['regex_scripts'];
    final scripts = <UiRegexScript>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        scripts.add(_parseScript(Map<String, dynamic>.from(item)));
      }
    }

    final cleanup =
        scripts.where((s) => s.kind == UiRegexKind.cleanup).length;
    if (cleanup > 0) {
      notes.add('跳过 $cleanup 条纯文本清理脚本（replaceString 为空，与 UI 无关）。');
    }
    final deco = scripts.where((s) => s.kind == UiRegexKind.decoration).length;
    if (deco > 0) {
      notes.add('跳过 $deco 条纯装饰脚本（只换外观、不含数据槽，'
          '转成组件只会得到空壳）。');
    }

    // ── 各开场分支的初始状态 ──
    //
    // 只在确实有多个字段时才收，避免把普通正文里的尖括号误当数据。
    final knownFields = <String>{
      for (final s in scripts)
        if (s.usable)
          for (final f in s.fields) f.name,
    };
    final branchPresets = _extractBranchPresets(data, knownFields);
    if (branchPresets.length > 1) {
      notes.add('识别到 ${branchPresets.length} 个开场分支，'
          '各自带不同的初始状态，已分别记录。');
    }

    // ── first_mes 里的可点击选项 ──
    final actions = _extractSendActions(data['first_mes']?.toString() ?? '');
    if (actions.isNotEmpty) {
      notes.add('开场消息里有 ${actions.length} 个可点击选项，'
          '可转为按钮（button + sendsMessage）。');
    }

    // ── 各开场分支的「接下来做什么」动作列表 ──
    //
    // 原版在每个开场白正文末尾写一段 `<选项>`（如
    // `1.🤐【保持沉默】...`），不同分支动作各不相同。
    // 这些动作转成该分支首条 AI 消息里的 onclick 结构，
    // 由引擎运行期 message_flow 动态选项解析渲染成按钮，AI 可更新。
    final branchActions = _extractBranchActions(data);
    if (branchActions.isNotEmpty) {
      final total = branchActions.values.fold<int>(
          0, (acc, list) => acc + list.length);
      notes.add('识别到 ${branchActions.length} 个开场分支的动作选项'
          '（共 $total 个），已转为动态按钮。');
    }

    if (!pluginDependent && scripts.every((s) => !s.usable)) {
      notes.add('没有找到可转译的 UI —— 原卡本来就没有界面，不生成。');
    }

    final rawFirstMes = data['first_mes']?.toString() ?? '';
    final cleanFirstMes = GreetingSanitizer.sanitize(rawFirstMes, knownTags: knownFields);

    return UiExtraction(
      scripts: scripts,
      pluginDependent: pluginDependent,
      pluginUrls: pluginUrls,
      openingActions: actions,
      branchPresets: branchPresets,
      branchActions: branchActions,
      notes: notes,
      cleanFirstMes: cleanFirstMes,
    );
  }

  /// 从开场白里抽各分支的初始状态。
  ///
  /// 分支 0 = `first_mes`，其后依次为 `alternate_greetings`
  /// ——与聊天页开场白左右切换的顺序一致。
  ///
  /// [knownFields] 是正则里声明过的字段名。只认这些，
  /// 否则正文里随便一个 `<某某>` 都会被当成状态数据。
  static Map<int, Map<String, String>> _extractBranchPresets(
    Map<String, dynamic> data,
    Set<String> knownFields,
  ) {
    if (knownFields.isEmpty) return const {};
    final texts = <String>[
      data['first_mes']?.toString() ?? '',
      ...?(data['alternate_greetings'] as List?)?.map((e) => e.toString()),
    ];
    final out = <int, Map<String, String>>{};
    for (var i = 0; i < texts.length; i++) {
      final found = <String, String>{};
      for (final name in knownFields) {
        final m = RegExp('<${RegExp.escape(name)}>(.*?)</${RegExp.escape(name)}>',
                dotAll: true)
            .firstMatch(texts[i]);
        if (m == null) continue;
        final v = m.group(1)!.trim();
        if (v.isNotEmpty) found[name] = v;
      }
      if (found.isNotEmpty) out[i] = found;
    }
    return out;
  }

  /// 从各开场分支的正文里抽「接下来做什么」动作列表。
  ///
  /// 分支 0 = `first_mes`，其后依次为 `alternate_greetings`
  /// ——与聊天页开场白左右切换的顺序一致。
  ///
  /// 每个分支正文末尾常有一段 `<选项>`，内容是该分支专属的
  /// 可选动作（如黑曜石「新人入狱」的 4 个动作与「狱警入职」不同）。
  static Map<int, List<ActionOption>> _extractBranchActions(
    Map<String, dynamic> data,
  ) {
    final texts = <String>[
      data['first_mes']?.toString() ?? '',
      ...?(data['alternate_greetings'] as List?)?.map((e) => e.toString()),
    ];
    final out = <int, List<ActionOption>>{};
    for (var i = 0; i < texts.length; i++) {
      final opts = _parseActionOptions(texts[i]);
      if (opts.isNotEmpty) out[i] = opts;
    }
    return out;
  }

  /// 解析一条开场白正文里的 `<选项>...</选项>` 动作块。
  ///
  /// 每行动作的常见形态：
  ///
  /// ```text
  /// 1.🤐【保持沉默】默不作声地按照指示上前，配合登记流程。
  /// 2.🤝【尝试交涉】趁上前扫过登记台...
  /// ```
  ///
  /// 动作行匹配 `序号. emoji【标题】描述`。点击发送整行原文；
  /// 展示标题优先取 `【标题】`，取不到就回退整行。
  static List<ActionOption> _parseActionOptions(String raw) {
    final block = RegExp(
      r'<选项>(.*?)</选项>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(raw);
    if (block == null) return const [];
    final body = block.group(1)!.trim();
    if (body.isEmpty) return const [];

    final options = <ActionOption>[];
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      // 1.🤐【保持沉默】默不作声地...  →  分组：序号. | 内容
      final m = RegExp(r'^\s*\d+[.、]\s*(.*)$', dotAll: true).firstMatch(t);
      final content = m?.group(1) ?? t;
      // 标题：取 【...】 里的内容
      final titleM = RegExp(r'【([^】]+)】').firstMatch(content);
      final label = titleM != null
          ? titleM.group(1)!
          : (content.length > 12 ? content.substring(0, 12) : content);
      options.add(ActionOption(raw: t, label: label));
    }
    return options;
  }

  // ───────────────────────── 内部实现 ─────────────────────────

  /// 检测**启用中**的外部 JS 插件。
  ///
  /// 两个实测到的坑：
  ///
  /// 1. **必须看 `enabled`**。黑曜石那张卡带了个 `enabled: false` 的
  ///    MVU 残留，但它的 UI 完全由正则实现、可以正常转译。
  ///    只要见到 `import` 就拒绝的话，会把好卡误杀。
  /// 2. **URL 正则不能用非贪婪**。`[^\s]+?\.js` 会在域名
  ///    `testingcf.jsdelivr.net` 的 `.js` 处提前截断，
  ///    得到 `https://testingcf.js` 这种假地址。
  static List<String> _detectPluginUrls(Map<String, dynamic> ext) {
    final helper = ext['tavern_helper'];
    if (helper == null) return const [];

    final enabledScripts = <String>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final e in node) {
          walk(e);
        }
      } else if (node is Map) {
        if (node['type'] == 'script' && node['enabled'] == true) {
          enabledScripts.add(node['content']?.toString() ?? '');
        }
        for (final v in node.values) {
          walk(v);
        }
      }
    }

    walk(helper);
    final joined = enabledScripts.join('\n');
    if (!joined.contains('import')) return const [];
    return RegExp(r"https?://[^\s\\\x22']+\.js")
        .allMatches(joined)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
  }

  static UiRegexScript _parseScript(Map<String, dynamic> s) {
    final name = s['scriptName']?.toString() ?? '(未命名)';
    final find = s['findRegex']?.toString() ?? '';
    final replace = s['replaceString']?.toString() ?? '';

    if (replace.trim().isEmpty) {
      return UiRegexScript(
        scriptName: name,
        kind: UiRegexKind.cleanup,
        fields: const [],
        replaceLength: 0,
        visuals: const UiVisualHints(),
      );
    }

    final visuals = _scanVisuals(replace);
    final sections = RegExp(r'<!--\s*(.*?)\s*-->')
        .allMatches(replace)
        .map((m) => m.group(1)!.trim())
        .where((x) => x.isNotEmpty && x.length < 40)
        .toList();

    // 优先试 bar_capture：它自带类型，比 tag_capture 信息更全。
    var fields = _parseBarCapture(find);
    var kind = UiRegexKind.barCapture;
    if (fields.isEmpty) {
      fields = _parseTagCapture(find);
      kind = UiRegexKind.tagCapture;
    }
    if (fields.isEmpty) {
      // 有替换内容但没有捕获组 → 纯装饰壳。
      kind = _hasCaptureGroup(find)
          ? UiRegexKind.unknown
          : UiRegexKind.decoration;
    }

    // ── 用 CSS 回填字段类型 ──
    // `width: $5` 说明第 5 个捕获组是百分比进度条。
    // 这是唯一能识别「文本捕获但实为进度条」的信号。
    final widthRefs = RegExp(r'width:\s*\$(\d+)')
        .allMatches(replace)
        .map((m) => int.tryParse(m.group(1)!) ?? -1)
        .toSet();
    if (widthRefs.isNotEmpty) {
      fields = fields
          .map((f) => widthRefs.contains(f.captureIndex) &&
                  f.type == UiFieldType.text
              ? f.withType(UiFieldType.percent)
              : f)
          .toList();
    }

    return UiRegexScript(
      scriptName: name,
      kind: kind,
      fields: fields,
      replaceLength: replace.length,
      visuals: visuals,
      sections: sections,
      rawReplace: replace,
    );
  }

  /// `<字段>(.*?)</字段>` 形式。
  static List<UiField> _parseTagCapture(String find) {
    final out = <UiField>[];
    // 捕获组编号按出现顺序递增，与 replaceString 里的 $N 对应。
    var index = 0;
    final re = RegExp(r'<([^/>()\\\s]{1,20})>\s*\(([^)]*)\)');
    for (final m in re.allMatches(find)) {
      index++;
      out.add(UiField(
        name: m.group(1)!,
        type: _typeOf(m.group(2)!),
        captureIndex: index,
      ));
    }
    return out;
  }

  /// `|字段:(\d+)|` 与 `{Xxx|字段:(\d+)|...}` 形式。
  ///
  /// 关键优势：`(\d+)/(\d+)` 能直接读出「当前/上限」，
  /// 省去猜 progress 量程的麻烦。
  static List<UiField> _parseBarCapture(String find) {
    if (!find.contains('|') && !find.contains(r'\|')) return const [];
    final out = <UiField>[];
    var index = 0;
    // 字段名允许中文、英文、数字、下划线。
    final re = RegExp(r'([\u4e00-\u9fa5A-Za-z_][\u4e00-\u9fa5\w]{0,19})'
        r'\s*:\s*\(([^)]*)\)'
        r'(\s*\\?/\s*\(([^)]*)\))?');
    for (final m in re.allMatches(find)) {
      index++;
      final first = m.group(2)!;
      final hasSecond = m.group(3) != null;
      if (hasSecond) {
        final maxIdx = ++index;
        out.add(UiField(
          name: m.group(1)!,
          type: UiFieldType.ranged,
          captureIndex: index - 1,
          maxCaptureIndex: maxIdx,
        ));
      } else {
        out.add(UiField(
          name: m.group(1)!,
          type: _typeOf(first),
          captureIndex: index,
        ));
      }
    }
    return out;
  }

  static bool _hasCaptureGroup(String find) {
    // 排除转义括号 \( \)
    final stripped = find.replaceAll(r'\(', '').replaceAll(r'\)', '');
    return stripped.contains('(');
  }

  static UiFieldType _typeOf(String captureBody) {
    final b = captureBody.trim();
    if (b == r'\d+' || b == r'[0-9]+' || b == r'\d*') {
      return UiFieldType.number;
    }
    return UiFieldType.text;
  }

  static UiVisualHints _scanVisuals(String css) {
    int count(String pattern) =>
        RegExp(pattern, caseSensitive: false).allMatches(css).length;
    return UiVisualHints(
      // `width: $5` 的内层 div 是 HTML 画进度条的标准写法。
      progressBars: count(r'width:\s*\$\d'),
      flexRows: count(r'display:\s*flex'),
      borderRadius: count(r'border-radius'),
      boxShadow: count(r'box-shadow'),
      gradient: count(r'linear-gradient'),
      clickable: count(r'onclick'),
    );
  }

  /// 从文本里解析 `{Xxx|key1:value1|key2:value2|...}` 格式的结构化标记值。
  ///
  /// 酒馆卡常把运行时状态写在这种标记里（如 `{PlayerStatus|Name:...|
  /// Level:1|HP:100/100|...}`），LLM 输出、正则替换成 HTML。转译时
  /// 从这里能拿到各字段的**初始值**，供 UI 字段填充（而非占位符）。
  ///
  /// 返回 字段名 -> 值（去掉 `:cur/max` 的量程尾巴，只留当前值）。
  static Map<String, String> extractBarFieldValues(String text) {
    final out = <String, String>{};
    // 先把 `{{...}}` 模板占位符（如 {{user}}）替换成无花括号的哨兵，
    // 否则内层的 `}` 会把 `[^}]*` 截断，导致整块后半段（Level/HP/...）
    // 全部丢失——这正是异世界公会状态栏字段全空的根因。
    final sentinel = <String, String>{};
    var counter = 0;
    final cleaned = text.replaceAllMapped(
      RegExp(r'\{\{[^}]*\}\}'),
      (m) {
        final key = '__TPL${counter++}__';
        sentinel[key] = m.group(0)!;
        return key;
      },
    );

    // 匹配 `{...}` 块（内部不再含花括号）。
    final re = RegExp(r'\{([^}]*)\}', dotAll: true);
    for (final m in re.allMatches(cleaned)) {
      final body = (m.group(1) ?? '').trim();
      if (body.isEmpty) continue;

      String rest = body;
      final ci = body.indexOf(':');
      final pi = body.indexOf('|');
      if (pi >= 0 && (ci < 0 || pi < ci)) {
        // `{Block|key:val|...}`：块名后直接是 `|`，其余都是 key:value
        rest = body.substring(pi + 1);
      } else if (ci > 0) {
        // `{key:val|key2:val|...}`：第一个 `:` 前是块名（即字段名），
        // 其后到下一个 `|` 是它的值。
        final leadingKey = body.substring(0, ci).trim();
        final pipe = body.indexOf('|', ci);
        final firstVal =
            pipe < 0 ? body.substring(ci + 1) : body.substring(ci + 1, pipe);
        _putBarValue(out, leadingKey, firstVal, sentinel);
        rest = pipe < 0 ? '' : body.substring(pipe + 1);
      } else {
        continue;
      }

      for (final part in rest.split('|')) {
        final idx = part.indexOf(':');
        if (idx <= 0) continue;
        final key = part.substring(0, idx).trim();
        final value = part.substring(idx + 1).trim();
        _putBarValue(out, key, value, sentinel);
      }
    }
    return out;
  }

  /// 写入一条 bar 值：还原哨兵、去掉 `cur/max` 量程尾巴。
  ///
  /// 同名键**保留第一次出现的值**（同一段正文里有 5 个 quest 块、
  /// 2 个选项块，后写的会覆盖前面的——取第一个更贴近开场引导）。
  static void _putBarValue(
    Map<String, String> out,
    String key,
    String value,
    Map<String, String> sentinel,
  ) {
    if (key.isEmpty || value.isEmpty) return;
    for (final e in sentinel.entries) {
      value = value.replaceAll(e.key, e.value);
    }
    // 去掉 "cur/max" 的量程尾巴：HP:100/100 -> 100
    final slash = value.indexOf('/');
    if (slash > 0 &&
        RegExp(r'^\d+$').hasMatch(value.substring(0, slash))) {
      value = value.substring(0, slash);
    }
    if (value.isNotEmpty) out.putIfAbsent(key, () => value);
  }

  /// 抽 `onclick="send('文案')"` 里的文案。
  ///
  /// 用三引号原始字符串是因为要同时匹配单引号和双引号两种写法，
  /// 普通字符串会陷入转义地狱。
  /// （附带一提：这行会让简易括号检查脚本误报不平衡，源码本身是对的。）
  static List<String> _extractSendActions(String html) {
    final re = RegExp(r"""send\(\s*['"](.+?)['"]\s*\)""");
    return re
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((x) => x.isNotEmpty)
        .toList();
  }
}
