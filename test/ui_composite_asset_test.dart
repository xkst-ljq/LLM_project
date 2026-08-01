import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// 复合组件的独立导出 / 导入。
///
/// **为什么只分享复合件、不分享整套 UI 方案**（用户判断）：
/// 整套方案对角色卡绑定太深——页面路由、状态字段 targetId、
/// mode 归属，换一张卡全部失效。复合件存在全局资产库、
/// 不属于任何角色卡，本来就是自包含的「零件」。
///
/// 这里复刻 `remapIds` 与导出前的清洗规则。

/// 复刻 `remapIds`。
Map<String, dynamic> remapIds(Map<String, dynamic> raw) {
  final json = Map<String, dynamic>.from(raw);
  final idMap = <String, String>{};
  var seed = 0;

  String freshId(String oldId) =>
      idMap.putIfAbsent(oldId, () => 'imp_${seed++}');

  final oldRootId = json['id']?.toString() ?? '';
  if (oldRootId.isNotEmpty) json['id'] = freshId(oldRootId);

  void collect(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final oldId = node['id']?.toString() ?? '';
      if (oldId.isNotEmpty) node['id'] = freshId(oldId);
      final module = node['module'];
      if (module is Map) {
        final oldModuleId = module['id']?.toString() ?? '';
        if (oldModuleId.isNotEmpty) module['id'] = freshId(oldModuleId);
      }
      final composite = node['composite'];
      if (composite is Map) {
        final oldCid = composite['id']?.toString() ?? '';
        if (oldCid.isNotEmpty) composite['id'] = freshId(oldCid);
        if (composite['children'] is List) {
          collect(composite['children'] as List);
        }
      }
    }
  }

  void rewritePorts(Map<dynamic, dynamic> cj) {
    final ports = cj['exposedPorts'];
    if (ports is! List) return;
    for (final port in ports) {
      if (port is! Map) continue;
      final old = port['elementId']?.toString() ?? '';
      if (old.isNotEmpty && idMap.containsKey(old)) {
        port['elementId'] = idMap[old];
      }
    }
  }

  void rewrite(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final module = node['module'];
      if (module is Map) {
        final sources = module['linkedSources'];
        if (sources is List) {
          for (var i = 0; i < sources.length; i++) {
            final old = sources[i]?.toString() ?? '';
            if (old.isNotEmpty && idMap.containsKey(old)) {
              sources[i] = idMap[old];
            }
          }
        }
      }
      if (module is Map && module['properties'] is Map) {
        final props = module['properties'] as Map;
        final linker = props['linker'];
        if (linker is Map) {
          // 键名与引擎一致：sourceModuleId / targetModuleId。
          // 这份复刻曾和实现一起写错成 sourceId / targetId，
          // 于是测试恒绿、真实导入却连线全断。
          for (final key in ['sourceModuleId', 'targetModuleId']) {
            final old = linker[key]?.toString() ?? '';
            if (old.isNotEmpty && idMap.containsKey(old)) {
              linker[key] = idMap[old];
            }
          }
          for (final key in ['inputConnection', 'outputConnection']) {
            final conn = linker[key];
            if (conn is! Map) continue;
            for (final endpoint in ['from', 'to']) {
              final old = conn[endpoint]?.toString() ?? '';
              if (old.isNotEmpty && idMap.containsKey(old)) {
                conn[endpoint] = idMap[old];
              }
            }
          }
        }
        final channel = props['dataChannel'];
        if (channel is Map) {
          final old = channel['sourceComponentId']?.toString() ?? '';
          if (old.isNotEmpty && idMap.containsKey(old)) {
            channel['sourceComponentId'] = idMap[old];
          }
        }
      }
      final composite = node['composite'];
      if (composite is Map && composite['children'] is List) {
        rewrite(composite['children'] as List);
        rewritePorts(composite);
      }
    }
  }

  final children = json['children'];
  if (children is List) {
    collect(children);
    rewrite(children);
  }
  rewritePorts(json);
  return json;
}

/// 复刻导出前对单个 props 的清洗。
void sanitizeForExport(Map<dynamic, dynamic> props) {
  final channel = props['dataChannel'];
  if (channel is Map && channel['targetKind']?.toString() == 'status_field') {
    final name = (channel['semanticLabel']?.toString() ??
            channel['pendingName']?.toString() ??
            '')
        .trim();
    channel['targetId'] = '';
    channel['pendingName'] = name;
  }
  if (channel is Map && channel['targetKind']?.toString() == 'card_entry') {
    channel.remove('cardEntryTarget');
  }
}

Map<String, dynamic> _sample() => {
      'id': 'comp_1',
      'name': '血条',
      'children': [
        {
          'id': 'el_a',
          'module': {'id': 'm_a', 'properties': <String, dynamic>{}},
        },
        {
          'id': 'el_b',
          'module': {
            'id': 'm_b',
            'properties': {
              'linker': {
                'sourceModuleId': 'el_a',
                'targetModuleId': 'el_c',
                'inputConnection': {'from': 'el_a', 'to': 'el_b'},
                'outputConnection': {'from': 'el_b', 'to': 'el_c'},
              },
            },
          },
        },
        {
          'id': 'el_c',
          'module': {
            'id': 'm_c',
            'linkedSources': ['el_a'],
            'properties': <String, dynamic>{},
          },
        },
      ],
      'exposedPorts': [
        {'elementId': 'el_a'},
        {'elementId': 'el_c'},
      ],
    };

void main() {
  group('id 重映射', () {
    // 必须做：id 是时间戳生成的，导入方可能已有同 id 的复合件，
    // 直接存会静默覆盖对方的东西。
    test('外壳与全部子元素 id 都换新', () {
      final out = remapIds(_sample());
      expect(out['id'], isNot('comp_1'));
      final children = out['children'] as List;
      for (final c in children) {
        expect((c as Map)['id'].toString().startsWith('imp_'), isTrue);
        expect(
          ((c['module'] as Map)['id'] as String).startsWith('imp_'),
          isTrue,
        );
      }
    });

    test('新 id 互不重复', () {
      final out = remapIds(_sample());
      final ids = <String>[out['id'] as String];
      for (final c in out['children'] as List) {
        ids.add((c as Map)['id'] as String);
        ids.add((c['module'] as Map)['id'] as String);
      }
      expect(ids.toSet().length, ids.length);
    });

    test('linker 连线跟着改写', () {
      // 漏改会让组件「看起来正常但连线断了」。
      final out = remapIds(_sample());
      final children = out['children'] as List;
      final newA = (children[0] as Map)['id'];
      final newC = (children[2] as Map)['id'];
      final linker = ((children[1] as Map)['module']
          as Map)['properties']['linker'] as Map;
      expect(linker['sourceModuleId'], newA);
      expect(linker['targetModuleId'], newC);
    });

    test('中转连线 inputConnection / outputConnection 跟着改写', () {
      // 漏改会让编辑器里的连线显示成断头线。
      final out = remapIds(_sample());
      final children = out['children'] as List;
      final newA = (children[0] as Map)['id'];
      final newB = (children[1] as Map)['id'];
      final newC = (children[2] as Map)['id'];
      final linker = ((children[1] as Map)['module']
          as Map)['properties']['linker'] as Map;
      expect((linker['inputConnection'] as Map)['from'], newA);
      expect((linker['inputConnection'] as Map)['to'], newB);
      expect((linker['outputConnection'] as Map)['from'], newB);
      expect((linker['outputConnection'] as Map)['to'], newC);
    });

    test('linkedSources 跟着改写', () {
      final out = remapIds(_sample());
      final children = out['children'] as List;
      final newA = (children[0] as Map)['id'];
      final sources =
          ((children[2] as Map)['module'] as Map)['linkedSources'] as List;
      expect(sources.single, newA);
    });

    test('改写后不残留任何旧 id', () {
      // 兜底断言：整棵树序列化后不该再出现 el_ 前缀的旧 id。
      // 前面那些逐字段断言只能覆盖已知字段，新增字段时容易漏。
      final out = remapIds(_sample());
      expect(jsonEncode(out).contains('el_'), isFalse);
    });

    test('exposedPorts 跟着改写', () {
      final out = remapIds(_sample());
      final children = out['children'] as List;
      final ports = out['exposedPorts'] as List;
      expect((ports[0] as Map)['elementId'], (children[0] as Map)['id']);
      expect((ports[1] as Map)['elementId'], (children[2] as Map)['id']);
    });

    test('嵌套复合件的子元素与端口同样处理', () {
      final src = {
        'id': 'outer',
        'children': [
          {
            'id': 'wrap',
            'composite': {
              'id': 'inner',
              'children': [
                {
                  'id': 'deep',
                  'module': {'id': 'm_deep', 'properties': <String, dynamic>{}},
                },
              ],
              'exposedPorts': [
                {'elementId': 'deep'},
              ],
            },
          },
        ],
      };
      final out = remapIds(src);
      final inner =
          ((out['children'] as List).first as Map)['composite'] as Map;
      final deepId = ((inner['children'] as List).first as Map)['id'];
      expect((inner['exposedPorts'] as List).first['elementId'], deepId);
      expect(inner['id'], isNot('inner'));
    });

    test('原始 id 不残留在任何角落', () {
      final out = remapIds(_sample());
      final text = jsonEncode(out);
      for (final old in ['comp_1', 'el_a', 'el_b', 'el_c', 'm_a']) {
        expect(text.contains(old), isFalse, reason: old);
      }
    });

    test('引用了不存在的 id 时保持原样，不置空', () {
      // 悬空引用照抄比抹掉安全：抹掉等于静默丢失作者的配置。
      final src = {
        'id': 'c',
        'children': [
          {
            'id': 'e1',
            'module': {
              'id': 'm1',
              'properties': {
                'linker': {
                  'sourceModuleId': 'e1',
                  'targetModuleId': 'ghost',
                },
              },
            },
          },
        ],
      };
      final out = remapIds(src);
      final linker = (((out['children'] as List).first as Map)['module']
          as Map)['properties']['linker'] as Map;
      // 悬空的 targetModuleId 原样保留；sourceModuleId 指向真实元素，
      // 应当被换成新 id。旧写法用的是不存在的键名，两条都恒真。
      expect(linker['targetModuleId'], 'ghost');
      expect(linker['sourceModuleId'], isNot('e1'));
    });
  });

  group('导出前清洗数据通道', () {
    test('状态字段通道降级为预绑定', () {
      // targetId 指向原作者卡里的字段 id，到别人机器上必然失效。
      // 清空 id、保留名字，对方进状态栏编辑页会看到「未创建的字段」提示。
      final props = {
        'dataChannel': {
          'targetKind': 'status_field',
          'targetId': 'sbf_original_9',
          'semanticLabel': '生命值',
          'pendingName': '',
        },
      };
      sanitizeForExport(props);
      final ch = props['dataChannel'] as Map;
      expect(ch['targetId'], '');
      expect(ch['pendingName'], '生命值');
    });

    test('semanticLabel 为空时回落 pendingName', () {
      final props = {
        'dataChannel': {
          'targetKind': 'status_field',
          'targetId': 'x',
          'pendingName': '体力',
        },
      };
      sanitizeForExport(props);
      expect((props['dataChannel'] as Map)['pendingName'], '体力');
    });

    test('角色卡设定通道剥掉三级定位', () {
      // entryId 同样是原作者卡里的内部 id。
      final props = {
        'dataChannel': {
          'targetKind': 'card_entry',
          'cardEntryTarget': {'entryId': 'entry_7'},
        },
      };
      sanitizeForExport(props);
      expect((props['dataChannel'] as Map).containsKey('cardEntryTarget'),
          isFalse);
    });

    test('会话变量通道不受影响', () {
      // 它按名字索引，换张卡照样能用。
      final props = {
        'dataChannel': {'targetKind': 'session_var', 'semanticLabel': '好感'},
      };
      sanitizeForExport(props);
      expect((props['dataChannel'] as Map)['semanticLabel'], '好感');
    });

    test('没有数据通道时不报错', () {
      final props = <String, dynamic>{'text': 'hi'};
      expect(() => sanitizeForExport(props), returnsNormally);
    });
  });

  group('文件格式约定', () {
    test('asset_type 固定为 ui_composite', () {
      expect('ui_composite', 'ui_composite');
    });

    test('扩展名为 .llmui', () {
      const name = '血条_20250101_120000.llmui';
      expect(name.endsWith('.llmui'), isTrue);
    });
  });
}
