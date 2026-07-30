import 'package:flutter/widgets.dart';

/// 消息流组件的一条消息。
///
/// 只保留渲染所需的最小字段——消息流是展示层，
/// 编辑 / 重生成 / 版本切换等操作属于 A11-2 的范围。
class FlowMessage {
  /// 'user' | 'assistant'
  final String role;
  final String content;

  /// 是否为正在流式接收中的消息（用于显示光标等提示）。
  final bool streaming;

  const FlowMessage({
    required this.role,
    required this.content,
    this.streaming = false,
  });

  bool get isUser => role == 'user';
}

/// 编辑器与预览共用的示例对话。
///
/// 两句玩家、两句角色，交替出现——单看一两句分不出气泡样式的差异，
/// 四句才能让作者判断左右对齐、颜色对比与换行效果。
///
/// 文案本身明确标注「示例」与身份，避免作者误以为这是真实历史，
/// 或分不清哪句是谁说的。
const List<FlowMessage> kMessageFlowSampleMessages = [
  FlowMessage(role: 'assistant', content: '［示例·角色］这里是角色的回复，用于预览气泡样式。'),
  FlowMessage(role: 'user', content: '［示例·玩家］这里是玩家发出的消息。'),
  FlowMessage(role: 'assistant', content: '［示例·角色］实际使用时会替换为真实对话，这四句不会出现。'),
  FlowMessage(role: 'user', content: '［示例·玩家］可据此调整字号、配色与显示条数。'),
];

/// 向下传递聊天消息的作用域。
///
/// 消息流组件在 UI 引擎里渲染，但数据源在聊天页。用 InheritedWidget
/// 传递而不是塞进 `module.properties`，原因：
///   - 消息是会话数据，不属于组件配置，写进 properties 会被
///     `_persistAssemblyElements` 一并存进角色卡；
///   - 流式输出时每个 chunk 都要刷新，走 properties 会触发整棵树重建。
///
/// 未提供该作用域时（如 Assembly 编辑器预览），组件会显示占位示例。
class MessageFlowScope extends InheritedWidget {
  final List<FlowMessage> messages;

  /// 这些消息是否来自真实对话。
  ///
  /// 必须显式标记，不能靠「列表是否为空」推断：
  /// 运行时预览与「真实聊天但历史为空」都是空列表，
  /// 前者该显示示例，后者该显示「暂无消息」。
  final bool isLive;

  const MessageFlowScope({
    super.key,
    required this.messages,
    this.isLive = false,
    required super.child,
  });

  static MessageFlowScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MessageFlowScope>();
  }

  @override
  bool updateShouldNotify(MessageFlowScope oldWidget) {
    if (oldWidget.isLive != isLive) return true;
    // 流式输出时最后一条的内容在持续变化，必须逐帧通知。
    if (oldWidget.messages.length != messages.length) return true;
    if (messages.isEmpty) return false;
    return oldWidget.messages.last.content != messages.last.content;
  }
}
