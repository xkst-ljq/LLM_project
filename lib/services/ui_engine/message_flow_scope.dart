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

  const MessageFlowScope({
    super.key,
    required this.messages,
    required super.child,
  });

  static List<FlowMessage>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MessageFlowScope>()
        ?.messages;
  }

  @override
  bool updateShouldNotify(MessageFlowScope oldWidget) {
    // 流式输出时最后一条的内容在持续变化，必须逐帧通知。
    if (oldWidget.messages.length != messages.length) return true;
    if (messages.isEmpty) return false;
    return oldWidget.messages.last.content != messages.last.content;
  }
}
