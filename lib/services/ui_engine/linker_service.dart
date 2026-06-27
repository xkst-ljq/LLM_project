import 'ui_models.dart';

/// LinkerService（联动器服务）
class LinkerService {
  /// 全局元素快照：elementId → UIModule
  static final Map<String, UIModule> _elementModules = {};

  /// 更新元素快照（每次渲染前调用）
  static void updateElementSnapshot(List<UIElement> elements) {
    _elementModules.clear();
    for (final el in elements) {
      if (!el.isComposite && el.module != null) {
        _elementModules[el.id] = el.module!;
      }
    }
  }

  /// 查找目标模块对应的元素 ID
  static String? _findElementIdForModule(UIModule targetModule) {
    for (final entry in _elementModules.entries) {
      if (identical(entry.value, targetModule) || entry.value.id == targetModule.id) {
        return entry.key;
      }
    }
    return null;
  }

  /// 解析源模块的动态生效属性（支持递归溯源与环路检测）
  static dynamic _getEffectivePropertyValue(UIModule sourceModule, String propKey, Set<String> visitedSet) {
    if (propKey == 'current' || propKey == 'value') {
      final incoming = resolveTargetValue(sourceModule, visitedSet);
      if (incoming != null) return incoming;
    }
    return sourceModule.properties[propKey];
  }

  /// 获取目标模块上游连接源的属性上下文（用于模板表达式解析）
  static Map<String, dynamic>? getSourceContextForTarget(UIModule targetModule) {
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) return null;

    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;

      if (linkerData['targetModuleId']?.toString() == targetElId) {
        final scheme = linkerData['scheme']?.toString();
        if (scheme == null || scheme.trim().isEmpty || scheme == '未配置') continue;

        final sourceId = linkerData['sourceModuleId']?.toString();
        if (sourceId != null && _elementModules.containsKey(sourceId)) {
          final sourceMod = _elementModules[sourceId]!;
          final contextDict = Map<String, dynamic>.from(sourceMod.properties);
          final effectiveCur = _getEffectivePropertyValue(sourceMod, 'current', <String>{targetElId});
          if (effectiveCur != null) {
            contextDict['current'] = effectiveCur;
            contextDict['value'] = effectiveCur;
          }
          return contextDict;
        }
      }
    }
    return null;
  }

  /// 解析任一目标模块接收到的联动数值或字面量
  static dynamic resolveTargetValue(UIModule targetModule, [Set<String>? visited]) {
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) return null;

    final visitedSet = visited != null ? Set<String>.from(visited) : <String>{};
    if (visitedSet.contains(targetElId)) return null;
    visitedSet.add(targetElId);

    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;

      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;

      final targetId = linkerData['targetModuleId']?.toString();
      if (targetId == null || targetId != targetElId) continue;

      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId == null || !_elementModules.containsKey(sourceId)) continue;

      final sourceModule = _elementModules[sourceId]!;
      final scheme = linkerData['scheme']?.toString();
      if (scheme == null || scheme.trim().isEmpty || scheme == '未配置') continue;

      if (['current_to_text', 'to_string', 'num_to_current'].contains(scheme)) {
        final val = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            sourceModule.properties['text'];
        if (val != null) {
          if (targetModule.type == 'text') {
            return val is num ? val.toStringAsFixed(0) : val.toString();
          }
          return val is num ? val.toDouble() : double.tryParse(val.toString());
        }
      } else if (scheme == 'max_to_text') {
        final val = sourceModule.properties['max'];
        if (val != null) {
          if (targetModule.type == 'text') {
            return val is num ? val.toStringAsFixed(0) : val.toString();
          }
          return val is num ? val.toDouble() : double.tryParse(val.toString());
        }
      } else if (scheme == 'text_to_text') {
        final val = sourceModule.properties['text'] ?? sourceModule.properties['value'];
        if (val != null) {
          return val.toString();
        }
      }
    }

    return null;
  }

  /// 解析 text 模块的联动值
  static String? resolveLinkedTextValue(UIModule textModule) {
    return resolveTargetValue(textModule)?.toString();
  }

  /// 判断一个模块是否被 linker 链接
  static bool isModuleLinked(String moduleId) {
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData?['sourceModuleId'] == moduleId ||
          linkerData?['targetModuleId'] == moduleId) {
        return true;
      }
    }
    return false;
  }
}
