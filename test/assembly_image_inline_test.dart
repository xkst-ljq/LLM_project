import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// 角色卡导出时 UI 图片的内联。
///
/// 缺口来源：`_inlineLocalImages` 只处理 `opening_greetings` 与
/// `description`，用的是 HTML 正则（`<img src>` / `url()`）。
/// 而 UI 组件把路径直接存在 JSON 的 `assetPath` 里，匹配不到——
/// 对方导入后凡是用了图片的组件全是空白，**而且导入不报错**，
/// 只会以为是原作者没配图。
///
/// 这里复刻 `_inlineAssemblyImages` 的遍历与跳过规则。

const String _fakeUri = 'data:image/png;base64,UE5H';

String? _toDataUri(String path) => path.contains('missing') ? null : _fakeUri;

bool _shouldSkip(String raw) =>
    raw.isEmpty ||
    raw.startsWith('data:') ||
    raw.startsWith('http://') ||
    raw.startsWith('https://') ||
    raw.startsWith('assets/');

/// 复刻 `_inlineAssemblyImages`。
String inlineAssemblyImages(String metaJson) {
  if (metaJson.trim().isEmpty) return metaJson;

  Map<String, dynamic> meta;
  try {
    final decoded = jsonDecode(metaJson);
    if (decoded is! Map) return metaJson;
    meta = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return metaJson;
  }

  final assemblies = meta['ui_assemblies'];
  if (assemblies is! List || assemblies.isEmpty) return metaJson;

  var touched = false;

  void visitProps(Map<dynamic, dynamic> props) {
    final raw = props['assetPath']?.toString().trim() ?? '';
    if (_shouldSkip(raw)) return;
    final uri = _toDataUri(raw);
    if (uri == null) return;
    props['assetPath'] = uri;
    touched = true;
  }

  void visitElements(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final module = node['module'];
      if (module is Map && module['properties'] is Map) {
        visitProps(module['properties'] as Map);
      }
      final composite = node['composite'];
      if (composite is Map && composite['children'] is List) {
        visitElements(composite['children'] as List);
      }
    }
  }

  for (var i = 0; i < assemblies.length; i++) {
    final rawInfo = assemblies[i];
    if (rawInfo is! String || rawInfo.trim().isEmpty) continue;
    Map<String, dynamic> info;
    try {
      final decoded = jsonDecode(rawInfo);
      if (decoded is! Map) continue;
      info = Map<String, dynamic>.from(decoded);
    } catch (_) {
      continue;
    }

    final beforeThisInfo = touched;
    final pagesRaw = info['pages']?.toString() ?? '';
    if (pagesRaw.trim().isEmpty || pagesRaw.trim() == '[]') continue;
    try {
      final pages = jsonDecode(pagesRaw);
      if (pages is! List) continue;
      for (final page in pages) {
        if (page is! Map) continue;
        if (page['elements'] is List) {
          visitElements(page['elements'] as List);
        }
        final overrides = page['propertyOverrides'];
        if (overrides is List) {
          for (final ov in overrides) {
            if (ov is Map && ov['overrides'] is Map) {
              visitProps(ov['overrides'] as Map);
            }
          }
        }
      }
      if (touched != beforeThisInfo) {
        info['pages'] = jsonEncode(pages);
        assemblies[i] = jsonEncode(info);
      }
    } catch (_) {
      continue;
    }
  }

  if (!touched) return metaJson;
  meta['ui_assemblies'] = assemblies;
  return jsonEncode(meta);
}

/// 复刻渲染端 `_decodeDataUri`。
List<int>? decodeDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma == -1) return null;
  try {
    return base64Decode(uri.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

String _meta(List<Map<String, dynamic>> pages) => jsonEncode({
      'ui_assemblies': [
        jsonEncode({'id': 'a1', 'pages': jsonEncode(pages)}),
      ],
    });

List<dynamic> _readElements(String metaJson) {
  final meta = jsonDecode(metaJson) as Map;
  final info = jsonDecode((meta['ui_assemblies'] as List).first as String);
  final pages = jsonDecode((info as Map)['pages'] as String) as List;
  return (pages.first as Map)['elements'] as List;
}

Map<String, dynamic> _imageNode(String assetPath) => {
      'module': {
        'properties': {'assetPath': assetPath},
      },
    };

void main() {
  group('需要内联的路径', () {
    test('本地绝对路径被替换为 data URI', () {
      final out = inlineAssemblyImages(
        _meta([
          {'elements': [_imageNode('/data/user/0/pic.png')]},
        ]),
      );
      final props =
          (_readElements(out).first as Map)['module']['properties'] as Map;
      expect(props['assetPath'], _fakeUri);
    });

    test('复合组件内部的子元素也被遍历', () {
      final out = inlineAssemblyImages(
        _meta([
          {
            'elements': [
              {
                'composite': {
                  'children': [_imageNode('/data/user/0/inner.png')],
                },
              },
            ],
          },
        ]),
      );
      final children = ((_readElements(out).first as Map)['composite']
          as Map)['children'] as List;
      expect(
        ((children.first as Map)['module'] as Map)['properties']['assetPath'],
        _fakeUri,
      );
    });

    test('复合件暴露项的覆写也被遍历', () {
      final out = inlineAssemblyImages(
        _meta([
          {
            'elements': <dynamic>[],
            'propertyOverrides': [
              {
                'overrides': {'assetPath': '/data/user/0/ov.png'},
              },
            ],
          },
        ]),
      );
      final meta = jsonDecode(out) as Map;
      final info = jsonDecode((meta['ui_assemblies'] as List).first as String);
      final pages = jsonDecode((info as Map)['pages'] as String) as List;
      final ov = ((pages.first as Map)['propertyOverrides'] as List).first;
      expect((ov as Map)['overrides']['assetPath'], _fakeUri);
    });
  });

  group('必须跳过的路径', () {
    test('网络地址不动', () {
      for (final url in ['http://a.com/x.png', 'https://a.com/x.png']) {
        expect(_shouldSkip(url), isTrue, reason: url);
      }
    });

    test('打包资产不动', () {
      expect(_shouldSkip('assets/builtin.png'), isTrue);
    });

    test('已内联的不重复处理', () {
      // 重复 base64 会让文件体积指数膨胀。
      expect(_shouldSkip('data:image/png;base64,AAAA'), isTrue);
    });

    test('空路径不动', () => expect(_shouldSkip(''), isTrue));

    test('普通本地路径不跳过', () {
      expect(_shouldSkip('/data/user/0/pic.png'), isFalse);
    });

    test('url 字段不受影响', () {
      final out = inlineAssemblyImages(
        _meta([
          {
            'elements': [
              {
                'module': {
                  'properties': {'url': 'https://a.com/x.png'},
                },
              },
            ],
          },
        ]),
      );
      final props =
          (_readElements(out).first as Map)['module']['properties'] as Map;
      expect(props['url'], 'https://a.com/x.png');
      expect(props.containsKey('assetPath'), isFalse);
    });
  });

  group('容错', () {
    test('meta_json 为空原样返回', () {
      expect(inlineAssemblyImages(''), '');
    });

    test('meta_json 解析失败原样返回', () {
      // 图片内联是锦上添花，不该因为它让整张卡导不出去。
      const broken = '{不是合法 JSON';
      expect(inlineAssemblyImages(broken), broken);
    });

    test('没有 ui_assemblies 时原样返回', () {
      const src = '{"name":"x"}';
      expect(inlineAssemblyImages(src), src);
    });

    test('无图片的方案原样返回', () {
      final src = _meta([
        {
          'elements': [
            {
              'module': {
                'properties': {'text': 'hi'},
              },
            },
          ],
        },
      ]);
      expect(inlineAssemblyImages(src), src);
    });

    test('图片文件读取失败时跳过该条，不中断其余', () {
      final out = inlineAssemblyImages(
        _meta([
          {
            'elements': [
              _imageNode('/data/user/0/missing.png'),
              _imageNode('/data/user/0/ok.png'),
            ],
          },
        ]),
      );
      final els = _readElements(out);
      expect(((els[0] as Map)['module'] as Map)['properties']['assetPath'],
          '/data/user/0/missing.png');
      expect(((els[1] as Map)['module'] as Map)['properties']['assetPath'],
          _fakeUri);
    });
  });

  group('渲染端解码', () {
    test('合法 data URI 能解出字节', () {
      final bytes = decodeDataUri(_fakeUri);
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!), 'PNG');
    });

    test('缺少逗号返回 null', () {
      expect(decodeDataUri('data:image/png;base64'), isNull);
    });

    test('base64 损坏返回 null 而不是抛异常', () {
      // 抛出去会让整个 UI 树崩掉，只该退化成占位图。
      expect(decodeDataUri('data:image/png;base64,@@@@'), isNull);
    });
  });
}
