import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as fhtml;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md hide Text;

import '../../models/text_highlight_rule.dart';
import '../text_highlight_engine.dart';

/// A11-2：Assembly 组件的富文本渲染。
///
/// 消息流与可滚动长文本共用同一套渲染（用户要求一起接，避免重复工作）：
/// readme 说明需要标题 / 加粗 / 列表，LLM 回复里也常带 Markdown。
///
/// 与聊天页 `_buildMarkdownWidget` 的关系：
/// 判定与降级策略刻意保持一致，让同一段文本在原生气泡和 Assembly 组件里
/// 长得一样。但**不复用**那份实现——它绑在 `_ChatPageState` 上，
/// 依赖 `_renderPromptTemplate`（宏替换需要角色/用户名）与
/// `_handleMarkdownAction`（重试 / 编辑等聊天动作），
/// 这两样在 Assembly 运行时都不存在，硬搬过来只会带进一堆空实现。
///
/// 三档降级（从重到轻）：
///   1. 含 HTML 标签 → `flutter_html`
///   2. 含复杂 Markdown（表格 / 代码块 / 列表 / 标题 / 链接）→ `MarkdownBody`
///   3. 其余 → 对白高亮的富文本（引号 / 括号 / 书名号着色）
///
/// 第 3 档不是「纯文本」：角色扮演文本绝大多数属于这一类，
/// 走一遍轻量着色比直接 `Text` 观感好得多，且开销远低于跑一次 Markdown 解析。
/// 着色规则由 [highlightRules] 提供（作者可在角色卡里自定义），
/// 不传时用 [TextHighlightRule.defaults]。
class AssemblyRichText extends StatelessWidget {
  final String text;

  /// 正文基准样式。标题 / 引用等由各渲染器在此基础上派生。
  final TextStyle baseStyle;

  final TextAlign textAlign;

  /// 是否允许长按选中复制。长文说明需要，消息气泡里不需要
  /// （会与滚动、点击抢手势）。
  final bool selectable;

  /// 正则着色规则。null 表示用内置默认。
  ///
  /// 只作用于第 3 档（对白高亮）——Markdown / HTML 有自己的语法着色，
  /// 再叠一层正则会互相打架（比如规则里的 `*` 与 Markdown 的强调冲突）。
  final List<TextHighlightRule>? highlightRules;

  const AssemblyRichText({
    super.key,
    required this.text,
    required this.baseStyle,
    this.textAlign = TextAlign.left,
    this.selectable = false,
    this.highlightRules,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    if (looksLikeHtml(text)) return _buildHtml(context);
    if (looksLikeComplexMarkdown(text)) return _buildMarkdown();
    return _buildStyledText();
  }

  // ---------------------------------------------------------------
  // 判定
  // ---------------------------------------------------------------

  /// 粗略判断是否含 HTML 标签。
  ///
  /// 只认常见的块 / 图片 / 排版标签，避免把普通文本里的 `<` `>` 误判
  /// （例如「1<2」「HP<50 时触发」——后者在角色卡里相当常见）。
  static bool looksLikeHtml(String text) {
    return RegExp(
      r'<\s*(img|div|span|h[1-6]|p|br|b|i|strong|em|a|ul|ol|li|center|font|hr|table)'
      r'(\s[^>]*)?/?\s*>',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// 是否值得动用完整 Markdown 解析。
  ///
  /// 只看「用 Text 画不出来」的结构（表格 / 代码块 / 列表 / 标题 / 链接）。
  /// 不检测 `**加粗**` `*斜体*`：星号在角色扮演文本里被大量用作动作标记
  /// （`*他转过身*`），按 Markdown 解析会把内容吃掉。
  static bool looksLikeComplexMarkdown(String text) {
    final trimmed = text.trim();
    return trimmed.contains('|') ||
        trimmed.contains('```') ||
        trimmed.contains(RegExp(r'^\s*[-*+]\s+', multiLine: true)) ||
        trimmed.contains(RegExp(r'^\s*#{1,6}\s+', multiLine: true)) ||
        trimmed.contains(RegExp(r'\[[^\]]+\]\([^)]+\)'));
  }

  /// 该文本是否会走 Markdown / HTML 渲染。
  ///
  /// 供编辑器提示作者「这段内容开启富文本后会有变化」。
  static bool looksRich(String text) =>
      looksLikeHtml(text) || looksLikeComplexMarkdown(text);

  // ---------------------------------------------------------------
  // 档位 1：HTML
  // ---------------------------------------------------------------

  Widget _buildHtml(BuildContext context) {
    var html = text;
    // 规范化无引号属性：第三方卡常写 <img src=data:...>，
    // 解析器遇到无引号值里的 ; : , 会截断，导致 data URI / 内联样式失效。
    html = _quoteUnquotedAttrs(html);
    // 裸换行转 <br>：作者常用 \n 换行，但 HTML 不认。
    // 标签之间的 \n 属于排版空白，先去掉以免多出空行。
    html = html.replaceAll(RegExp(r'>\s*\n\s*<'), '><');
    html = html.replaceAll('\n', '<br>');

    final size = baseStyle.fontSize ?? 13.0;
    final color = baseStyle.color ?? const Color(0xFF111116);

    return fhtml.Html(
      data: html,
      // 本地优先：不跳转外部浏览器，只提示地址。
      onLinkTap: (url, attributes, element) {
        if (url == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('该链接指向外部网站，已忽略：$url'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      extensions: [
        fhtml.TagExtension(
          tagsToExtend: {'img'},
          builder: (ctx) => buildLocalImage(ctx.attributes['src'] ?? ''),
        ),
      ],
      style: {
        'body': fhtml.Style(
          margin: fhtml.Margins.zero,
          padding: fhtml.HtmlPaddings.zero,
          fontSize: fhtml.FontSize(size),
          lineHeight: fhtml.LineHeight(baseStyle.height ?? 1.35),
          color: color,
        ),
        // 标题默认很大很占高度，在 PCB 这种小画布上必须压扁。
        'h1': fhtml.Style(
          fontSize: fhtml.FontSize(size * 1.36),
          margin: fhtml.Margins.symmetric(vertical: 4),
          lineHeight: fhtml.LineHeight(1.2),
        ),
        'h2': fhtml.Style(
          fontSize: fhtml.FontSize(size * 1.2),
          margin: fhtml.Margins.symmetric(vertical: 3),
          lineHeight: fhtml.LineHeight(1.2),
        ),
        'h3': fhtml.Style(
          fontSize: fhtml.FontSize(size * 1.08),
          margin: fhtml.Margins.symmetric(vertical: 2),
        ),
        'p': fhtml.Style(margin: fhtml.Margins.symmetric(vertical: 3)),
        'hr': fhtml.Style(margin: fhtml.Margins.symmetric(vertical: 4)),
        'a': fhtml.Style(
          color: const Color(0xFFE8833A),
          textDecoration: TextDecoration.none,
        ),
      },
    );
  }

  /// 给 src= / style= 等属性的无引号值补上双引号。
  static String _quoteUnquotedAttrs(String html) {
    final re = RegExp(
      r'''\b(src|style|href|width|height)\s*=\s*(?!["'])([^\s>]+)''',
      caseSensitive: false,
    );
    return html.replaceAllMapped(re, (m) => '${m.group(1)}="${m.group(2)}"');
  }

  /// 图片：本地路径 / data URI 正常显示；外链降级为占位。
  ///
  /// 与聊天页同一条**本地优先**原则：运行时不联网加载外链，
  /// 既避免离线时长时间白框，也不向第三方泄露使用痕迹。
  static Widget buildLocalImage(String src, {double maxHeight = 240}) {
    final s = src.trim();

    Widget wrap(Widget img) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: img,
          ),
        );

    if (s.startsWith('data:image')) {
      final idx = s.indexOf('base64,');
      if (idx != -1) {
        try {
          return wrap(
            Image.memory(base64Decode(s.substring(idx + 7)),
                fit: BoxFit.contain),
          );
        } catch (_) {
          return _imagePlaceholder('图片数据无法解码');
        }
      }
    }

    String? localPath;
    if (s.startsWith('file://')) {
      localPath = Uri.tryParse(s)?.toFilePath();
    } else if (s.isNotEmpty &&
        !s.startsWith('http://') &&
        !s.startsWith('https://') &&
        !s.startsWith('data:')) {
      localPath = s;
    }

    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        return wrap(Image.file(file, fit: BoxFit.contain));
      }
    }

    return _imagePlaceholder('外链图片（未内嵌）');
  }

  static Widget _imagePlaceholder(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withAlpha(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 16, color: Colors.black.withAlpha(120)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.black.withAlpha(140)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // 档位 2：Markdown
  // ---------------------------------------------------------------

  Widget _buildMarkdown() {
    final size = baseStyle.fontSize ?? 13.0;
    return MarkdownBody(
      data: text,
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        // 标题按基准字号派生，作者调小字号时整体跟着缩，
        // 不会出现「正文 10px、标题 24px」的割裂。
        h1: baseStyle.copyWith(
            fontSize: size * 1.36, fontWeight: FontWeight.w700),
        h2: baseStyle.copyWith(
            fontSize: size * 1.2, fontWeight: FontWeight.w700),
        h3: baseStyle.copyWith(
            fontSize: size * 1.08, fontWeight: FontWeight.w600),
        listBullet: baseStyle,
        code: baseStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: size * 0.92,
          backgroundColor: Colors.black.withAlpha(14),
        ),
        blockquote: baseStyle.copyWith(color: const Color(0xFF6A5A78)),
        a: const TextStyle(
          color: Color(0xFFE8833A),
          decoration: TextDecoration.none,
        ),
        // 各块间距压紧：PCB 画布通常比聊天气泡还窄。
        pPadding: const EdgeInsets.symmetric(vertical: 2),
        h1Padding: const EdgeInsets.symmetric(vertical: 3),
        h2Padding: const EdgeInsets.symmetric(vertical: 3),
        h3Padding: const EdgeInsets.symmetric(vertical: 2),
        blockSpacing: 6,
      ),
    );
  }

  // ---------------------------------------------------------------
  // 档位 3：对白高亮
  // ---------------------------------------------------------------

  Widget _buildStyledText() {
    final rules = highlightRules ?? TextHighlightRule.defaults();
    final root = TextHighlightEngine.buildSpan(text, rules, baseStyle);
    if (selectable) {
      return SelectableText.rich(root, textAlign: textAlign);
    }
    return Text.rich(root, textAlign: textAlign);
  }
}
