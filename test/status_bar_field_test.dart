import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/models/status_bar_field.dart';

void main() {
  group('copyWith 上下限', () {
    final base = StatusBarField(
      id: 'f',
      name: '金币',
      type: 'number',
      initialValue: '100',
      minValue: 0,
      maxValue: 100,
    );

    test('可以把上限改到远大于默认值', () {
      // 编辑页里「初始值 500 / 最大值 9999」这类配置必须能保存下来。
      final next = base.copyWith(initialValue: '500', maxValue: 9999);
      expect(next.initialValue, '500');
      expect(next.maxValue, 9999);
    });

    test('不传参数时保留原值', () {
      final next = base.copyWith(name: '钱袋');
      expect(next.minValue, 0);
      expect(next.maxValue, 100);
    });

    test('clearMaxValue 显式清空上限', () {
      // 仅传 maxValue: null 无法与「不修改」区分，必须用 clear 标记。
      final next = base.copyWith(clearMaxValue: true);
      expect(next.maxValue, isNull);
      expect(next.minValue, 0);
    });

    test('clearMinValue 显式清空下限', () {
      final next = base.copyWith(clearMinValue: true);
      expect(next.minValue, isNull);
      expect(next.maxValue, 100);
    });
  });

  group('归属与主语', () {
    StatusBarField f(String owner) => StatusBarField(
        id: 'f', name: '金钱数量', type: 'number', owner: owner);

    test('玩家属性带「玩家的」主语', () {
      expect(f('player').qualifiedName, '玩家的金钱数量');
    });

    test('角色属性带「你的」主语', () {
      expect(f('char').qualifiedName, '你的金钱数量');
    });

    test('中立字段不加主语，避免别扭表述', () {
      expect(f('neutral').qualifiedName, '金钱数量');
    });

    test('默认归属为玩家', () {
      expect(StatusBarField(id: 'f', name: '金钱').owner, 'player');
    });

    test('旧卡片缺少 owner 时回落为玩家', () {
      final parsed = StatusBarField.fromJson({
        'id': 'f',
        'name': '金钱',
        'type': 'number',
      });
      expect(parsed.owner, 'player');
    });

    test('非法 owner 值回落为玩家', () {
      final parsed = StatusBarField.fromJson({
        'id': 'f',
        'name': '金钱',
        'owner': 'nonsense',
      });
      expect(parsed.owner, 'player');
    });

    test('owner 参与序列化往返', () {
      final original = StatusBarField(id: 'f', name: '钱包', owner: 'char');
      expect(StatusBarField.fromJson(original.toJson()).owner, 'char');
    });
  });

  group('链式编辑', () {
    test('连续修改多个字段不会互相覆盖', () {
      // 复现编辑页的操作序列：先改初始值，再改最大值。
      // 修复前第二次修改会写进过期对象，导致最大值丢失。
      var field = StatusBarField(
        id: 'f',
        name: '',
        type: 'number',
        initialValue: '0',
        minValue: 0,
        maxValue: 100,
      );

      field = field.copyWith(name: '金币');
      field = field.copyWith(initialValue: '500');
      field = field.copyWith(maxValue: 9999);

      expect(field.name, '金币');
      expect(field.initialValue, '500');
      expect(field.maxValue, 9999);
    });
  });
}
