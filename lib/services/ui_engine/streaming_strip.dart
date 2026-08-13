/// 流式输出过程中的增量技术标签剥离。
///
/// 状态栏 / 界面数据通道的标签块（`<状态变化>` / `<界面状态变化>`）在流式
/// 分块中会被截成半截标签；直接显示会把技术标记暴露给用户，直接整段正则
/// 剥离又会在闭标签到达前把标签块内容当正文显示。策略：
///   1. 剥离所有完整闭合的标签块；
///   2. 从最后一个「未闭合开标签」起隐藏到末尾（等闭标签到达或流结束）；
///   3. 若末尾只是标签名前缀（`<状态变` / `</状态变`），隐藏该前缀。
///
/// 流结束后由 `_processStatusBarReply` / `_processUIChannelReply` 做完整解析
/// 兜底，这里只负责「流式过程中不暴露技术标记」。
String streamingStrip(String text) {
  if (text.isEmpty) return text;
  var out = text;

  // 1. 完整闭合的标签块 → 剥离。
  out = out.replaceAll(
    RegExp(r'<(?:状态变化|界面状态变化)>.*?</(?:状态变化|界面状态变化)>',
        dotAll: true),
    '',
  );

  // 2. 未闭合开标签（含其后内容）→ 隐藏到末尾，等闭标签到达或流结束。
  final opens = RegExp(r'<(?:状态变化|界面状态变化)>').allMatches(out).toList();
  if (opens.isNotEmpty) {
    final lastOpen = opens.last;
    final after = out.substring(lastOpen.start);
    if (!RegExp(r'</(?:状态变化|界面状态变化)>').hasMatch(after)) {
      out = out.substring(0, lastOpen.start);
    }
  }

  // 3. 半截标签名前缀（分块截断在标签名中间）→ 隐藏。
  //    用正则找最后一个 `<` 或全角 `＜`（全角变体也须识别）。
  final lastLt = out.lastIndexOf(RegExp(r'[<＜]'));
  if (lastLt >= 0) {
    final tail = out.substring(lastLt);
    if (_isPartialTagPrefix(tail)) {
      out = out.substring(0, lastLt);
    }
  }

  // 技术标签独占一行，剥离后残留的行尾换行 / 空格会让气泡底部悬空一个空行。
  // 流式阶段不 trim 整段（会破坏打字效果），只清尾部空白。
  return out.replaceAll(RegExp(r'\s+$'), '');
}

/// 判断流式尾部是否像「技术标签块的前缀」（含容错：全角括号、标签内空格）。
bool _isPartialTagPrefix(String tail) {
  final compact = tail
      .replaceAll('＜', '<')
      .replaceAll('＞', '>')
      .replaceAll(RegExp(r'<\s*'), '<');
  for (final tag in const ['状态变化', '界面状态变化']) {
    if (('<$tag>').startsWith(compact)) return true;
    if (('</$tag>').startsWith(compact)) return true;
  }
  return false;
}
