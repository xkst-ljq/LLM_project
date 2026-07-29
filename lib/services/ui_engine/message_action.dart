/// A11-2：消息操作动作。
///
/// 原生气泡上的重生成 / 继续 / 编辑 / 删除 / 版本切换按钮，
/// 在 scene 接管聊天页后全部消失。与其在 `message_flow` 里内置一排小图标
/// （外观不可控、必然与作者的美术风格冲突），不如让作者用普通 button
/// 通过 linker 连到消息流上——与「发送消息」标记同一条原则：
/// **作者用通用组件表达意图，外观完全自定**。
///
/// 作用对象固定为**最新一条 AI 消息**（用户确认），与原生气泡的功能键一致。
/// 因此 `message_flow` 不需要引入「选中态」，实现与心智负担都最小。
enum MessageAction {
  /// 重新生成：产生一个新版本，可用 version_prev/next 切回旧版本。
  regenerate,

  /// 继续写：在当前回复后面接着生成。
  continueWrite,

  /// 编辑：进入编辑态，由聊天页弹出输入界面。
  edit,

  /// 撤回：删除该轮对话（用户消息 + 其后的 AI 回复），并回滚状态变化。
  delete,

  /// 切换到上一个版本。
  versionPrev,

  /// 切换到下一个版本。
  versionNext;

  /// 方案参数里存的字符串值。
  ///
  /// 用显式字符串而非 `enum.name`：参数值会随角色卡序列化，
  /// 将来重命名枚举项不该让老卡片的配置失效。
  String get key {
    switch (this) {
      case MessageAction.regenerate:
        return 'regenerate';
      case MessageAction.continueWrite:
        return 'continue';
      case MessageAction.edit:
        return 'edit';
      case MessageAction.delete:
        return 'delete';
      case MessageAction.versionPrev:
        return 'version_prev';
      case MessageAction.versionNext:
        return 'version_next';
    }
  }

  /// 编辑器里给作者看的名字。用大白话，不用「重生成脉冲」这类术语。
  String get label {
    switch (this) {
      case MessageAction.regenerate:
        return '重新生成';
      case MessageAction.continueWrite:
        return '继续写';
      case MessageAction.edit:
        return '编辑';
      case MessageAction.delete:
        return '撤回这轮对话';
      case MessageAction.versionPrev:
        return '上一个版本';
      case MessageAction.versionNext:
        return '下一个版本';
    }
  }

  /// 补充说明，解释「按下去会发生什么」。
  String get description {
    switch (this) {
      case MessageAction.regenerate:
        return '让角色重新回答上一句，旧回复保留为历史版本。';
      case MessageAction.continueWrite:
        return '在当前回复的末尾继续往下写。';
      case MessageAction.edit:
        return '修改最新一条回复的内容。';
      case MessageAction.delete:
        return '删除最近一轮对话（玩家的话与角色的回复），并回滚这轮产生的状态变化。';
      case MessageAction.versionPrev:
        return '切回上一次生成的回复。只有重新生成过才有多个版本。';
      case MessageAction.versionNext:
        return '切到下一次生成的回复。';
    }
  }

  /// 从方案参数里存的字符串还原；无法识别时返回 null。
  ///
  /// 返回 null 而不是回落到某个默认动作：认不出来说明配置有问题，
  /// 静默执行「重新生成」会让玩家莫名其妙丢掉一条回复。
  static MessageAction? fromKey(String? raw) {
    if (raw == null) return null;
    final key = raw.trim();
    for (final action in MessageAction.values) {
      if (action.key == key) return action;
    }
    return null;
  }

  /// 方案参数下拉里的全部取值，顺序即展示顺序。
  static List<String> get allKeys =>
      MessageAction.values.map((a) => a.key).toList();
}
