import 'dart:convert';

import 'package:dio/dio.dart';

import 'conversion_models.dart';

/// 开场白 / 描述等文本里的外链图片下载内嵌服务。
///
/// 理念（与主项目本地优先一致）：第三方卡的开场白常含 `<img src="https://图床/x.gif">`，
/// 图片在别人服务器上、会失效、有隐私风险。转译时把它们下载下来、改写成卡内资产引用
/// （assets/embedded/N.ext），写卡时打包进卡，导入后落地为本地文件、运行时不再联网。
///
/// 这是「转换之后的独立异步后处理」：不污染同步的 CharacterCardMapper.map()，
/// 失败不影响主转换（保留原 <img>，App 端显示占位，并在报告里说明）。
class ImageEmbedService {
  /// 匹配 <img ... src=...>，src 支持双引号 / 单引号 / 无引号三种写法
  /// （酒馆卡大量使用无引号属性，如 <img src=https://x.png />）。
  static final RegExp _imgSrc = RegExp(
    r'''<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s">]+))''',
    caseSensitive: false,
    dotAll: true,
  );

  /// 匹配 CSS background-image:url(...) 里的图片地址（含引号 / 无引号）。
  static final RegExp _cssUrl = RegExp(
    r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]+))\s*\)''',
    caseSensitive: false,
  );

  /// 对转换结果做图片下载内嵌。返回新的结果（含 embeddedImages 与改写后的文本）。
  ///
  /// [maxImages] 单卡最多下载数（防止恶意卡塞几百张图）。
  /// [maxBytesPerImage] 单图最大字节（防超大文件）。
  static Future<CardConversionResult> process(
    CardConversionResult result, {
    int maxImages = 20,
    int maxBytesPerImage = 8 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final character = result.characterData;
    if (character == null) return result;

    // 收集所有外链图片 URL（开场白 + 描述）。先扫描，确定要下哪些。
    final greetingsRaw = character['opening_greetings'] as String? ?? '[]';
    List<dynamic> greetings;
    try {
      greetings = jsonDecode(greetingsRaw) as List<dynamic>;
    } catch (_) {
      greetings = [];
    }

    final description = character['description'] as String? ?? '';

    // URL -> 卡内资产路径（同一 URL 只下一次）。
    final urlToAsset = <String, String>{};
    final embedded = <String, List<int>>{};
    final notes = <ConversionNote>[...result.notes];
    int downloaded = 0;
    int failed = 0;
    int index = 0;

    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      responseType: ResponseType.bytes,
      followRedirects: true,
      validateStatus: (s) => s != null && s >= 200 && s < 400,
    ));

    // 全部文本：开场白各条 + 描述。
    final allText = [
      for (final g in greetings)
        if (g is Map && g['content'] is String) g['content'] as String,
      description,
    ].join('\n');

    // 收集所有外链 URL（<img src> + CSS url()），去重保序。
    final urls = <String>[];
    void collect(RegExp re) {
      for (final m in re.allMatches(allText)) {
        final src = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
        if (_isExternal(src) && !urls.contains(src)) urls.add(src);
      }
    }

    collect(_imgSrc);
    collect(_cssUrl);

    for (final url in urls) {
      if (downloaded >= maxImages) {
        notes.add(ConversionNote.warning(
            '外链图片超过 $maxImages 张，超出部分未下载，保留为外链。'));
        break;
      }
      try {
        final resp = await dio.get<List<int>>(url);
        final data = resp.data;
        if (data == null || data.isEmpty) {
          failed++;
          continue;
        }
        if (data.length > maxBytesPerImage) {
          failed++;
          notes.add(ConversionNote.warning('图片过大已跳过：$url'));
          continue;
        }
        final ext = _extFromUrlOrContentType(
            url, resp.headers.value('content-type'));
        final assetPath = 'assets/embedded/img_${index++}$ext';
        embedded[assetPath] = data;
        urlToAsset[url] = assetPath;
        downloaded++;
      } catch (_) {
        failed++;
      }
    }

    if (urlToAsset.isEmpty) {
      // 没有成功下载任何图片：若本来就有外链，提示一下。
      if (urls.isNotEmpty) {
        notes.add(ConversionNote.warning(
            '开场白 / 描述含 ${urls.length} 张外链图片，均未能下载（图床失效/超时/无效），'
            '已保留原链接，导入后显示为占位。'));
        return result.copyWith(notes: notes);
      }
      return result;
    }

    // 直接按 URL 字符串全局替换（同时覆盖 <img src> 与 CSS url()，
    // 引号 / 无引号均可，因为 URL 本身唯一且足够长，不会误伤）。
    String rewrite(String text) {
      var t = text;
      urlToAsset.forEach((url, asset) {
        t = t.replaceAll(url, asset);
      });
      return t;
    }

    // 改写开场白与描述里的图片地址。
    final newGreetings = [
      for (final g in greetings)
        if (g is Map && g['content'] is String)
          {...g, 'content': rewrite(g['content'] as String)}
        else
          g,
    ];
    final newCharacter = {
      ...character,
      'opening_greetings': jsonEncode(newGreetings),
      'description': rewrite(description),
    };

    if (failed > 0) {
      notes.add(ConversionNote.warning(
          '外链图片：成功内嵌 $downloaded 张，$failed 张未能下载（保留为外链占位）。'));
    } else {
      notes.add(ConversionNote.info('外链图片：已下载内嵌 $downloaded 张。'));
    }

    return result.copyWith(
      characterData: newCharacter,
      notes: notes,
      embeddedImages: embedded,
    );
  }

  static bool _isExternal(String src) =>
      src.startsWith('http://') || src.startsWith('https://');

  static String _extFromUrlOrContentType(String url, String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('png')) return '.png';
    if (ct.contains('gif')) return '.gif';
    if (ct.contains('webp')) return '.webp';
    if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
    // 退而求其次：从 URL 扩展名猜。
    final lower = url.toLowerCase();
    for (final e in ['.png', '.gif', '.webp', '.jpg', '.jpeg']) {
      if (lower.contains(e)) return e == '.jpeg' ? '.jpg' : e;
    }
    return '.img';
  }
}
