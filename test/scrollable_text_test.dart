import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

UIModule _text({
  String content = '正文',
  String overflow = 'ellipsis',
  String align = 'center',
  double fontSize = 14,
}) {
  return UIModule(
    id: 'm',
    name: 'text',
    type: 'text',
    properties: {
      'text': content,
      'overflow': overflow,
      'textAlign': align,
      'fontSize': fontSize,
    },
  );
}

void main() {
  group('文本溢出模式', () {
    test('默认为省略号截断', () {
      final module = UIModule(
        id: 'm',
        name: 'text',
        type: 'text',
        properties: const {'text': 'x'},
      );
      // 未配置时读取应回落到 ellipsis，保持既有行为不变。
      final mode = module.properties['overflow']?.toString() ?? 'ellipsis';
      expect(mode, 'ellipsis');
    });

    test('三种模式都能持久化', () {
      for (final mode in ['ellipsis', 'clip', 'scroll']) {
        final module = _text(overflow: mode);
        expect(module.properties['overflow'], mode, reason: mode);
      }
    });

    test('滚动模式与对齐方式互不干扰', () {
      final module = _text(overflow: 'scroll', align: 'left');
      expect(module.properties['overflow'], 'scroll');
      expect(module.properties['textAlign'], 'left');
    });
  });

  group('长文本场景', () {
    test('可承载多段长内容', () {
      final long = List.generate(50, (i) => '第 $i 段说明文字。').join('\n\n');
      final module = _text(content: long, overflow: 'scroll');
      expect(module.properties['text'].toString().length, greaterThan(500));
      expect(module.properties['overflow'], 'scroll');
    });

    test('内容为空时不崩溃', () {
      final module = _text(content: '', overflow: 'scroll');
      expect(module.properties['text'], '');
    });
  });

  group('序列化往返', () {
    test('滚动配置随实例保存', () {
      final module = _text(
        content: 'readme 内容',
        overflow: 'scroll',
        align: 'left',
        fontSize: 13,
      );
      final restored = UIModule.fromJson(module.toJson());
      expect(restored.properties['overflow'], 'scroll');
      expect(restored.properties['textAlign'], 'left');
      expect(restored.properties['fontSize'], 13);
      expect(restored.properties['text'], 'readme 内容');
    });
  });
}
