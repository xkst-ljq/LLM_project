import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_ui_engine/llm_ui_engine.dart';

void main() {
  group('HTML 判定', () {
    test('认出常见排版标签', () {
      expect(AssemblyRichText.looksLikeHtml('<div>你好</div>'), isTrue);
      expect(AssemblyRichText.looksLikeHtml('第一行<br>第二行'), isTrue);
      expect(AssemblyRichText.looksLikeHtml('<img src="a.png">'), isTrue);
      expect(AssemblyRichText.looksLikeHtml('<h1>标题</h1>'), isTrue);
    });

    test('不把普通文本里的尖括号误判成标签', () {
      // 角色卡里「HP<50 时触发」这类写法很常见，误判会走 HTML 渲染，
      // 导致后半段内容被当作未闭合标签吞掉。
      expect(AssemblyRichText.looksLikeHtml('当 HP<50 时触发'), isFalse);
      expect(AssemblyRichText.looksLikeHtml('1<2 且 3>2'), isFalse);
      expect(AssemblyRichText.looksLikeHtml('纯文本'), isFalse);
    });
  });

  group('Markdown 判定', () {
    test('认出需要完整解析的结构', () {
      expect(AssemblyRichText.looksLikeComplexMarkdown('# 标题'), isTrue);
      expect(AssemblyRichText.looksLikeComplexMarkdown('- 列表项'), isTrue);
      expect(AssemblyRichText.looksLikeComplexMarkdown('| a | b |'), isTrue);
      expect(AssemblyRichText.looksLikeComplexMarkdown('```dart\nx\n```'), isTrue);
      expect(
        AssemblyRichText.looksLikeComplexMarkdown('见 [文档](https://a.b)'),
        isTrue,
      );
    });

    test('不因加粗 / 斜体星号就走 Markdown', () {
      // 星号在角色扮演文本里被大量用作动作标记，
      // 按 Markdown 解析会把 * 之间的内容吃掉。
      expect(
        AssemblyRichText.looksLikeComplexMarkdown('*他转过身*，没有说话。'),
        isFalse,
      );
      expect(AssemblyRichText.looksLikeComplexMarkdown('“你好。”'), isFalse);
    });

    test('列表判定要求星号后有空格', () {
      expect(AssemblyRichText.looksLikeComplexMarkdown('* 真列表'), isTrue);
      expect(AssemblyRichText.looksLikeComplexMarkdown('*非列表*'), isFalse);
    });
  });

  group('looksRich 汇总', () {
    test('HTML 或复杂 Markdown 都算富内容', () {
      expect(AssemblyRichText.looksRich('<b>x</b>'), isTrue);
      expect(AssemblyRichText.looksRich('# x'), isTrue);
      expect(AssemblyRichText.looksRich('普通一句话'), isFalse);
    });
  });

  group('渲染冒烟', () {
    const style = TextStyle(fontSize: 13, color: Colors.black);

    Future<void> pump(WidgetTester tester, String text,
        {bool selectable = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: SingleChildScrollView(
                child: AssemblyRichText(
                  text: text,
                  baseStyle: style,
                  selectable: selectable,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空文本不渲染任何内容', (tester) async {
      await pump(tester, '');
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('普通文本走对白高亮，不可选中时用 Text.rich', (tester) async {
      await pump(tester, '“你好。”（他笑了笑）');
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('selectable 时改用 SelectableText', (tester) async {
      await pump(tester, '一段普通说明', selectable: true);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('Markdown 与 HTML 均能渲染而不抛异常', (tester) async {
      await pump(tester, '# 标题\n\n- 项目一\n- 项目二');
      expect(tester.takeException(), isNull);

      await pump(tester, '<h2>说明</h2><p>正文</p>');
      expect(tester.takeException(), isNull);
    });

    testWidgets('外链图片降级为占位，不发起网络请求', (tester) async {
      await pump(tester, '<img src="https://example.com/a.png">');
      expect(tester.takeException(), isNull);
      expect(find.text('外链图片（未内嵌）'), findsOneWidget);
    });
  });
}
