import 'package:flutter/material.dart';

/// 状态变化的通知方式。
///
/// **替代原来的 `llmUpdateApplyPolicy`**。旧字段的 `confirm` 会弹卡片
/// 让玩家逐条勾选、勾掉就不写，那是「否决权」——用户判断这个语义不对：
///
/// > 数据变化本身就不应该让用户可以拒绝，不过像等级升级或者什么，
/// > 需要告知用户这类重要的变化，就弹窗提醒主角。
///
/// 「拒绝」和「知情」是两件事，这里要的是后者：值一律写入，
/// 只决定要不要、以什么形式告诉玩家。
///
/// 旧值的去向：
/// - `never`          → 由「允许 AI 更新 = 不允许」承担，本就重复
/// - `confirm`        → 废除否决权
/// - `auto_low_risk`  → 就是现在的 [silent]
enum StatusNotifyStyle {
  /// 静默写入，不打扰玩家。默认。
  silent,

  /// 顶部浮窗，几秒后自消，不阻断操作。
  toast,

  /// 居中弹窗，需要玩家点「知道了」。适合升级这类需要据此做决策的变化。
  dialog;

  static StatusNotifyStyle parse(Object? raw) {
    switch (raw?.toString()) {
      case 'toast':
        return StatusNotifyStyle.toast;
      case 'dialog':
        return StatusNotifyStyle.dialog;
      default:
        return StatusNotifyStyle.silent;
    }
  }

  String get storageValue => switch (this) {
        StatusNotifyStyle.silent => 'silent',
        StatusNotifyStyle.toast => 'toast',
        StatusNotifyStyle.dialog => 'dialog',
      };

  bool get isSilent => this == StatusNotifyStyle.silent;
}

/// 一条待展示的状态变化通知。
///
/// 值**已经写入**才会产生它——通知就是通知，不是预告。
class StatusNotification {
  const StatusNotification({
    required this.label,
    required this.oldValue,
    required this.newValue,
    required this.style,
    this.template = '',
  });

  /// 字段显示名，如「等级」。
  final String label;

  final String oldValue;
  final String newValue;
  final StatusNotifyStyle style;

  /// 作者自定义文案，支持 `{name}` `{old}` `{new}` 三个占位符。
  /// 留空则用默认的「等级：3 → 4」。
  final String template;

  /// 渲染后的正文。
  ///
  /// 弹窗要显示「旧值 → 新值」，固定住那一刻的信息——
  /// 值是先写的，玩家点掉第一个弹窗时背后的数字可能已经全变完了。
  String get message {
    final tpl = template.trim();
    if (tpl.isEmpty) return '$label：$oldValue → $newValue';
    return tpl
        .replaceAll('{name}', label)
        .replaceAll('{old}', oldValue)
        .replaceAll('{new}', newValue);
  }

  /// 默认格式的变化摘要，即使用了自定义文案也保留，供弹窗副行展示。
  String get changeDetail => '$oldValue → $newValue';
}

/// 通知队列的编排规则。
///
/// 规则由用户定：
///
/// ```
/// 弹窗：堆叠。确认一个露出下一个，逐个查看
/// 浮窗：新的把旧的向上顶，同屏最多 5 个
///       满了之后消失一个补一个，不批量放出（避免爆屏）
/// 优先级：弹窗全部确认完 → 才开始生成浮窗
/// ```
class StatusNotificationQueue extends ChangeNotifier {
  StatusNotificationQueue({this.maxVisibleToasts = 5});

  /// 同屏浮窗上限。超出的排队等待，**消失一个补一个**，
  /// 不能等第一个消失后把剩下的一次性放出来——那样会爆屏。
  final int maxVisibleToasts;

  final List<StatusNotification> _pendingDialogs = [];
  final List<StatusNotification> _pendingToasts = [];
  final List<StatusNotification> _visibleToasts = [];

  /// 当前应当展示的弹窗；null 表示没有。
  StatusNotification? get currentDialog =>
      _pendingDialogs.isEmpty ? null : _pendingDialogs.first;

  /// 当前在屏上的浮窗。**索引 0 是最旧的**，新的追加在末尾；
  /// 视图层从下往上排列即可实现「新的把旧的向上顶」。
  List<StatusNotification> get visibleToasts =>
      List.unmodifiable(_visibleToasts);

  int get pendingDialogCount => _pendingDialogs.length;
  int get pendingToastCount => _pendingToasts.length;

  bool get hasAnything =>
      _pendingDialogs.isNotEmpty ||
      _pendingToasts.isNotEmpty ||
      _visibleToasts.isNotEmpty;

  /// 入队一批通知。silent 的会被直接忽略。
  void enqueue(Iterable<StatusNotification> items) {
    var touched = false;
    for (final item in items) {
      switch (item.style) {
        case StatusNotifyStyle.silent:
          continue;
        case StatusNotifyStyle.dialog:
          _pendingDialogs.add(item);
          touched = true;
        case StatusNotifyStyle.toast:
          _pendingToasts.add(item);
          touched = true;
      }
    }
    if (!touched) return;
    _pump();
    notifyListeners();
  }

  /// 玩家点掉当前弹窗。
  void dismissCurrentDialog() {
    if (_pendingDialogs.isEmpty) return;
    _pendingDialogs.removeAt(0);
    _pump();
    notifyListeners();
  }

  /// 某条浮窗自然消失或被划走。
  void dismissToast(StatusNotification item) {
    if (!_visibleToasts.remove(item)) return;
    // 空出位置后补一条，而不是等全部消失再批量放出。
    _pump();
    notifyListeners();
  }

  void clear() {
    if (!hasAnything) return;
    _pendingDialogs.clear();
    _pendingToasts.clear();
    _visibleToasts.clear();
    notifyListeners();
  }

  /// 推进队列：弹窗未清空时不放浮窗。
  void _pump() {
    // 优先级：弹窗全部确认完，才开始生成浮窗。
    // 否则玩家一边点弹窗、一边有浮窗在旁边冒，注意力被撕成两半。
    if (_pendingDialogs.isNotEmpty) return;
    while (_visibleToasts.length < maxVisibleToasts &&
        _pendingToasts.isNotEmpty) {
      _visibleToasts.add(_pendingToasts.removeAt(0));
    }
  }
}
