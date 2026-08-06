/// 剥离开场白里的「渲染标记」，只留玩家该看到的正文。
///
/// ## 为什么需要
///
/// SillyTavern 卡的开场白常带一堆自定义标签：
///
/// ```
/// <终端状态>ONLINE - 监控中</终端状态>
/// <当前位置>浅层-L2 - 监控室</当前位置>
/// <正文>
/// 滋...滋...这里是黑曜石特区。
/// </正文>
/// <选项列表>
/// <div onclick="send('选择开场1')">[01] 新人入狱</div>
/// </选项列表>
/// ```
///
/// 在 ST 里这些标签会被 `regex_scripts` 替换成 HTML 面板。
/// 但**我们这边没有那套正则**——照搬过来玩家就会看到满屏尖括号。
///
/// 而且标签里的数据会被 AI UI 理解阶段确认后编译进 UI
/// （`<生命>84%</生命>` → progress 的初值），
/// 正文里再留一份既重复又难看。
///
/// ## 处理策略
///
/// 按可靠性从高到低：
///
/// | 情况 | 处理 |
/// |---|---|
/// | 有 `<正文>` / `<content>` 之类的正文标签 | 只取那一段 |
/// | 没有正文标签，但有其它已知标签 | 删掉已知标签块，留其余文本 |
/// | 完全没有标签 | 原样返回 |
///
/// **保守原则**：认不出来就不动。宁可留几个尖括号，
/// 也不要把作者写的正文误删——后者是不可逆的信息损失。
library;

/// 开场白净化器。
class GreetingSanitizer {
  const GreetingSanitizer._();

  /// 常见的「正文」标签名。
  ///
  /// 命中任一即认为找到了正文段，其余标签全是渲染用的元数据。
  static const Set<String> _bodyTags = {
    '正文',
    '内容',
    '叙述',
    '描述',
    'content',
    'body',
    'text',
    'narration',
  };

  /// 净化一条开场白。
  ///
  /// [knownTags] 是从 `regex_scripts` 里提取到的字段名。
  /// 只删这些标签——**不认识的标签一律保留**，
  /// 因为它们可能是作者故意写给玩家看的内容。
  static String sanitize(String raw, {Set<String> knownTags = const {}}) {
    if (raw.trim().isEmpty) return raw;

    // ① 优先找正文标签。这是最可靠的信号：
    //    作者明确划出了「哪一段是给玩家读的」。
    for (final tag in _bodyTags) {
      final m = RegExp(
        '<${RegExp.escape(tag)}>(.*?)</${RegExp.escape(tag)}>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(raw);
      if (m != null) {
        final body = m.group(1)!.trim();
        // 正文段空的话说明这张卡的结构不是我们想的那样，别乱删。
        if (body.isNotEmpty) return body;
      }
    }

    // ② 没有正文标签 → 删掉已知的数据标签块，留下其余文本。
    if (knownTags.isEmpty) return raw;
    var out = raw;
    for (final tag in knownTags) {
      if (_bodyTags.contains(tag.toLowerCase())) continue;
      out = out.replaceAll(
        RegExp(
          '<${RegExp.escape(tag)}>.*?</${RegExp.escape(tag)}>\\s*',
          dotAll: true,
          caseSensitive: false,
        ),
        '',
      );
    }

    // ③ 顺手清掉 onclick 选项块——那些已经转成按钮了，
    //    留在正文里是一串没有交互能力的裸 HTML。
    out = out.replaceAll(
      RegExp(r'<div[^>]*onclick[^>]*>.*?</div>\s*', dotAll: true),
      '',
    );
    // 包裹选项的容器标签（<选项列表> 之类）此时已经空了，一并去掉。
    out = out.replaceAll(
      RegExp(r'<([\u4e00-\u9fa5A-Za-z_]{1,12})>\s*</\1>\s*', dotAll: true),
      '',
    );

    final trimmed = out.trim();
    // 删完什么都不剩 → 说明判断有误，退回原文。
    // 玩家看到几个尖括号，总好过看到一片空白。
    return trimmed.isEmpty ? raw : trimmed;
  }

  /// 批量净化，并报告改动了几条。
  static ({List<String> greetings, int changed}) sanitizeAll(
    List<String> raws, {
    Set<String> knownTags = const {},
  }) {
    var changed = 0;
    final out = <String>[];
    for (final r in raws) {
      final s = sanitize(r, knownTags: knownTags);
      if (s != r) changed++;
      out.add(s);
    }
    return (greetings: out, changed: changed);
  }
}
