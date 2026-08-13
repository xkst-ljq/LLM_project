import 'package:flutter_test/flutter_test.dart';

import 'package:llm_project/services/status_bar_engine.dart';
import 'package:llm_project/services/ui_engine/data_channel_update_engine.dart';
import 'package:llm_project/services/ui_engine/streaming_strip.dart';

/// 归一化空白后比较正文：流式剥离只清尾部空白、完整剥离压缩空行，
/// 正文内容应一致（onDone 会用完整解析覆盖流式显示，二者必须收敛）。
String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  group('与完整剥离收敛', () {
    test('状态栏块剥离结果与 onDone 完整解析一致', () {
      const text = '她微微一笑。\n<状态变化>\n好感度:+5\n</状态变化>';
      expect(
        _normalize(streamingStrip(text)),
        _normalize(StatusBarEngine.stripFromReply(text)),
      );
    });

    test('状态栏 + 界面数据双块剥离与完整解析一致', () {
      const text = '她微微一笑。\n<状态变化>\n好感度:+5\n</状态变化>\n'
          '<界面状态变化>回合:+1</界面状态变化>';
      final streamed = streamingStrip(text);
      final full = DataChannelUpdateEngine.stripFromReply(
        StatusBarEngine.stripFromReply(text),
      );
      expect(_normalize(streamed), _normalize(full));
    });

    test('流式渐进到完整的最终结果与完整解析一致', () {
      final chunks = [
        '她微微一笑。',
        '\n<状态变',
        '化>\n好感度:+5',
        '\n</状态变化>',
      ];
      var buf = '';
      for (final c in chunks) {
        buf += c;
      }
      expect(
        _normalize(streamingStrip(buf)),
        _normalize(StatusBarEngine.stripFromReply(buf)),
      );
    });
  });

  group('streamingStrip - 完整标签块', () {
    test('无标签时原样返回', () {
      expect(streamingStrip('你好，世界'), '你好，世界');
    });

    test('完整状态变化块被剥离', () {
      expect(
        streamingStrip('你好\n<状态变化>\n好感度:+5\n</状态变化>'),
        '你好',
      );
    });

    test('完整界面状态变化块被剥离', () {
      expect(
        streamingStrip('正文\n<界面状态变化>回合:+1</界面状态变化>'),
        '正文',
      );
    });

    test('多个完整块全部剥离', () {
      expect(
        streamingStrip('a<状态变化>1</状态变化>b<界面状态变化>2</界面状态变化>c'),
        'abc',
      );
    });
  });

  group('streamingStrip - 未闭合块挂起', () {
    test('开标签已到、内容未闭合 → 从开标签起隐藏', () {
      expect(
        streamingStrip('你好\n<状态变化>好感度:+5'),
        '你好',
      );
    });

    test('半截开标签名前缀 → 隐藏', () {
      expect(streamingStrip('你好\n<状态变'), '你好');
    });

    test('半截闭标签名前缀 → 隐藏', () {
      expect(streamingStrip('你好\n</状态变'), '你好');
    });

    test('界面状态变化的半截前缀同样隐藏', () {
      expect(streamingStrip('你好\n<界面状态变'), '你好');
    });
  });

  group('streamingStrip - 流式渐进', () {
    test('半截标签挂起，补齐闭合后只剩正文', () {
      var buf = '';
      buf += '你好';
      expect(streamingStrip(buf), '你好');
      buf += '\n<状态变';
      expect(streamingStrip(buf), '你好');
      buf += '化>\n好感度:+5';
      expect(streamingStrip(buf), '你好');
      buf += '\n</状态变';
      expect(streamingStrip(buf), '你好');
      buf += '化>';
      expect(streamingStrip(buf), '你好');
    });

    test('完整块剥离 + 末尾新半截块挂起', () {
      expect(
        streamingStrip('正文\n<状态变化>+5</状态变化>\n续写\n<界面状态变'),
        '正文\n\n续写',
      );
    });
  });

  group('streamingStrip - 不误伤正文', () {
    test('普通尖括号文本不被隐藏', () {
      expect(streamingStrip('温度 < 10 度'), '温度 < 10 度');
    });

    test('全角括号变体的前缀也挂起', () {
      expect(streamingStrip('正文\n＜状态变'), '正文');
    });

    test('空输入安全返回', () {
      expect(streamingStrip(''), '');
    });
  });
}
