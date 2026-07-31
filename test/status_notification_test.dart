import 'package:flutter_test/flutter_test.dart';
import 'package:llm_project/services/ui_engine/status_notification.dart';

/// 4.3b 状态变化通知系统。
///
/// 核心语义修正：**废除否决权**。旧的 applyPolicy 里 confirm 会弹卡片
/// 让玩家逐条勾选、勾掉就不写；用户判断数据变化本身不该让玩家拒绝，
/// 该做的是把重要变化告知他。notifyStyle 只决定要不要通知、用什么形式。

StatusNotification _n(
  String label, {
  StatusNotifyStyle style = StatusNotifyStyle.toast,
  String oldValue = '1',
  String newValue = '2',
  String template = '',
}) =>
    StatusNotification(
      label: label,
      oldValue: oldValue,
      newValue: newValue,
      style: style,
      template: template,
    );

void main() {
  group('StatusNotifyStyle 解析', () {
    test('识别三种取值', () {
      expect(StatusNotifyStyle.parse('silent'), StatusNotifyStyle.silent);
      expect(StatusNotifyStyle.parse('toast'), StatusNotifyStyle.toast);
      expect(StatusNotifyStyle.parse('dialog'), StatusNotifyStyle.dialog);
    });

    test('未知值与 null 回落 silent', () {
      // 旧卡里存的是 confirm / auto_low_risk / never，
      // 全部回落静默——它们的语义已由别处承担。
      for (final raw in [null, '', 'confirm', 'auto_low_risk', 'never', 'x']) {
        expect(StatusNotifyStyle.parse(raw), StatusNotifyStyle.silent,
            reason: '$raw');
      }
    });

    test('storageValue 可往返', () {
      for (final s in StatusNotifyStyle.values) {
        expect(StatusNotifyStyle.parse(s.storageValue), s);
      }
    });
  });

  group('文案渲染', () {
    test('留空用默认格式', () {
      final n = _n('等级', oldValue: '3', newValue: '4');
      expect(n.message, '等级：3 → 4');
    });

    test('三个占位符都被替换', () {
      final n = _n('等级',
          oldValue: '3', newValue: '4', template: '{name} 从 {old} 升到 {new}');
      expect(n.message, '等级 从 3 升到 4');
    });

    test('同一占位符出现多次全部替换', () {
      final n = _n('等级', oldValue: '3', newValue: '4', template: '{new}{new}');
      expect(n.message, '44');
    });

    test('只写固定文字也可以', () {
      final n = _n('等级', template: '恭喜升级！');
      expect(n.message, '恭喜升级！');
    });

    test('自定义文案时仍保留变化明细', () {
      // 弹窗副行用它——「恭喜升级」看不出具体数值。
      final n = _n('等级', oldValue: '3', newValue: '4', template: '恭喜升级！');
      expect(n.changeDetail, '3 → 4');
    });

    test('纯空白模板视为留空', () {
      final n = _n('等级', oldValue: '3', newValue: '4', template: '   ');
      expect(n.message, '等级：3 → 4');
    });
  });

  group('队列：弹窗优先于浮窗', () {
    test('弹窗未清空时不放浮窗', () {
      // 一边点弹窗、一边有浮窗在旁边冒，注意力会被撕成两半。
      final q = StatusNotificationQueue();
      q.enqueue([
        _n('升级', style: StatusNotifyStyle.dialog),
        _n('金钱'),
        _n('好感'),
      ]);
      expect(q.currentDialog?.label, '升级');
      expect(q.visibleToasts, isEmpty);
      expect(q.pendingToastCount, 2);
    });

    test('弹窗清空后浮窗才上屏', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        _n('升级', style: StatusNotifyStyle.dialog),
        _n('金钱'),
      ]);
      q.dismissCurrentDialog();
      expect(q.currentDialog, isNull);
      expect(q.visibleToasts.length, 1);
    });

    test('浮窗已上屏后又来弹窗，不影响已在屏的', () {
      final q = StatusNotificationQueue();
      q.enqueue([_n('金钱')]);
      expect(q.visibleToasts.length, 1);
      q.enqueue([_n('升级', style: StatusNotifyStyle.dialog)]);
      expect(q.visibleToasts.length, 1, reason: '不该把已显示的收回去');
      expect(q.currentDialog?.label, '升级');
    });
  });

  group('队列：弹窗堆叠逐个查看', () {
    test('按入队顺序依次露出', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        for (final n in ['A', 'B', 'C'])
          _n(n, style: StatusNotifyStyle.dialog),
      ]);
      final seen = <String>[];
      while (q.currentDialog != null) {
        seen.add(q.currentDialog!.label);
        q.dismissCurrentDialog();
      }
      expect(seen, ['A', 'B', 'C']);
    });

    test('pendingDialogCount 反映剩余条数', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        for (final n in ['A', 'B']) _n(n, style: StatusNotifyStyle.dialog),
      ]);
      expect(q.pendingDialogCount, 2);
      q.dismissCurrentDialog();
      expect(q.pendingDialogCount, 1);
    });

    test('队列空时点掉不抛异常', () {
      final q = StatusNotificationQueue();
      expect(q.dismissCurrentDialog, returnsNormally);
    });
  });

  group('队列：浮窗上限与补位', () {
    test('同屏最多 5 个', () {
      final q = StatusNotificationQueue();
      q.enqueue([for (var i = 0; i < 8; i++) _n('T$i')]);
      expect(q.visibleToasts.length, 5);
      expect(q.pendingToastCount, 3);
    });

    test('消失一个补一个，不批量放出', () {
      // 等第一个消失后把剩下的一次性放出来会爆屏。
      final q = StatusNotificationQueue();
      q.enqueue([for (var i = 0; i < 8; i++) _n('T$i')]);
      q.dismissToast(q.visibleToasts.first);
      expect(q.visibleToasts.length, 5);
      expect(q.pendingToastCount, 2);
      expect(q.visibleToasts.map((e) => e.label).toList(),
          ['T1', 'T2', 'T3', 'T4', 'T5']);
    });

    test('新的排在末尾（视图从上往下＝旧到新）', () {
      final q = StatusNotificationQueue();
      q.enqueue([_n('旧')]);
      q.enqueue([_n('新')]);
      expect(q.visibleToasts.map((e) => e.label).toList(), ['旧', '新']);
    });

    test('上限可配置', () {
      final q = StatusNotificationQueue(maxVisibleToasts: 2);
      q.enqueue([for (var i = 0; i < 5; i++) _n('T$i')]);
      expect(q.visibleToasts.length, 2);
    });

    test('移除不在屏上的浮窗是空操作', () {
      final q = StatusNotificationQueue();
      q.enqueue([_n('A')]);
      expect(() => q.dismissToast(_n('不存在')), returnsNormally);
      expect(q.visibleToasts.length, 1);
    });
  });

  group('队列：silent 与杂项', () {
    test('silent 直接忽略，不进任何队列', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        _n('静默', style: StatusNotifyStyle.silent),
        _n('浮窗'),
      ]);
      expect(q.visibleToasts.length, 1);
      expect(q.visibleToasts.single.label, '浮窗');
    });

    test('全 silent 时队列保持空', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        for (var i = 0; i < 3; i++)
          _n('S$i', style: StatusNotifyStyle.silent),
      ]);
      expect(q.hasAnything, isFalse);
    });

    test('clear 清空全部三条队列', () {
      final q = StatusNotificationQueue();
      q.enqueue([
        _n('D', style: StatusNotifyStyle.dialog),
        for (var i = 0; i < 8; i++) _n('T$i'),
      ]);
      q.clear();
      expect(q.hasAnything, isFalse);
      expect(q.currentDialog, isNull);
      expect(q.visibleToasts, isEmpty);
    });

    test('入队会通知监听者', () {
      final q = StatusNotificationQueue();
      var calls = 0;
      q.addListener(() => calls++);
      q.enqueue([_n('A')]);
      expect(calls, 1);
    });

    test('全 silent 入队不触发通知', () {
      final q = StatusNotificationQueue();
      var calls = 0;
      q.addListener(() => calls++);
      q.enqueue([_n('S', style: StatusNotifyStyle.silent)]);
      expect(calls, 0, reason: '没有任何变化就不该触发重建');
    });
  });
}
