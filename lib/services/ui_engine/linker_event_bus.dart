import 'dart:async';

/// 脉冲事件定义模型
class LinkerPulseEvent {
  final String sourceModuleId;
  final String eventType; // 'tap', 'tick', 'submit', 'clear', 'focus'
  final dynamic payload;
  final DateTime timestamp;

  LinkerPulseEvent({
    required this.sourceModuleId,
    required this.eventType,
    this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 联动器双轨事件总线 (LinkerEventBus)
class LinkerEventBus {
  static final LinkerEventBus _instance = LinkerEventBus._internal();
  factory LinkerEventBus() => _instance;
  LinkerEventBus._internal();

  final StreamController<LinkerPulseEvent> _controller =
      StreamController<LinkerPulseEvent>.broadcast();

  /// 事件订阅流
  Stream<LinkerPulseEvent> get onPulse => _controller.stream;

  /// 发射脉冲事件 (例如按钮点击、定时器 Tick、输入框提交)
  void emit(String sourceModuleId, String eventType, [dynamic payload]) {
    _controller.add(LinkerPulseEvent(
      sourceModuleId: sourceModuleId,
      eventType: eventType,
      payload: payload,
    ));
  }
}
