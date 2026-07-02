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

      if (['current_to_text', 'to_string', 'num_to_current', 'select_to_text', 'str_to_select', 'str_to_indicator', 'num_to_indicator', 'bool_to_indicator'].contains(scheme)) {
        final val = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'currentVal', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'defaultValue', visitedSet) ??
            sourceModule.properties['text'] ??
            sourceModule.name;
        if (val != null) {
          if (targetModule.type == 'text' || targetModule.type == 'input' || targetModule.type == 'select' || targetModule.type == 'indicator') {
            return val is num ? val.toStringAsFixed(0) : val.toString();
          }
          return val is num ? val.toDouble() : double.tryParse(val.toString());
        }
      } else if (scheme == 'max_to_text') {
        final val = sourceModule.properties['max'];
        if (val != null) {
          if (targetModule.type == 'text' || targetModule.type == 'input') {
            return val is num ? val.toStringAsFixed(0) : val.toString();
          }
          return val is num ? val.toDouble() : double.tryParse(val.toString());
        }
      } else if (scheme == 'text_to_text') {
        final val = sourceModule.properties['text'] ?? sourceModule.properties['value'] ?? sourceModule.name;
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

  /// 将所有带有 boundVariable 或连线语义驱动设定的控件传导值写入 SessionState.vars
  static void syncToSessionState(Map<String, String> sessionVars) {
    for (final module in _elementModules.values) {
      String? varKey;
      final explicitVar = module.boundVariable ?? module.properties['variable']?.toString() ?? module.properties['label']?.toString();
      if (explicitVar != null && explicitVar.trim().isNotEmpty) {
        final rawKey = explicitVar.trim();
        varKey = rawKey.startsWith('var.') ? rawKey.substring(4) : rawKey;
      } else if (module.type == 'input') {
        for (final lkMod in _elementModules.values) {
          if (lkMod.type != 'linker') continue;
          final lk = (lkMod.properties['linker'] as Map?)?.cast<String, dynamic>();
          if (lk?['targetModuleId'] == module.id) {
            final srcId = lk?['sourceModuleId']?.toString();
            if (srcId != null && _elementModules.containsKey(srcId)) {
              final srcMod = _elementModules[srcId]!;
              if (srcMod.type == 'text') {
                varKey = srcMod.properties['text']?.toString() ?? srcMod.name;
              }
            }
          }
        }
      }

      if (varKey == null || varKey.trim().isEmpty) continue;
      final key = varKey.trim();

      dynamic val;
      if (module.type == 'text') {
        val = resolveLinkedTextValue(module) ?? module.properties['text'];
      } else if (module.type == 'progress' || module.type == 'slider') {
        val = resolveTargetValue(module) ?? module.properties['current'];
      } else if (module.type == 'input') {
        val = resolveTargetValue(module) ?? module.properties['text'] ?? module.properties['value'] ?? '';
      } else if (module.type == 'switch') {
        val = resolveTargetValue(module) ?? module.properties['value'] ?? true;
      } else if (module.type == 'select') {
        val = resolveTargetValue(module) ?? module.properties['current'] ?? module.properties['defaultValue'] ?? '';
      } else if (module.type == 'indicator') {
        val = resolveTargetValue(module) ?? module.properties['currentValue'] ?? '';
      } else if (module.type == 'timer') {
        val = resolveTargetValue(module) ?? module.properties['currentVal'] ?? 0;
      }

      if (val != null) {
        final strVal = val is num ? val.toStringAsFixed(0) : val.toString();
        sessionVars[key] = strVal;
      }
    }
  }

  /// 判断一个目标组件运行期是否被上游关闭的布尔开关折叠驱动显隐
  static bool isTargetHiddenBySwitch(String targetElId) {
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final lk = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (lk == null || lk['enabled'] == false) continue;
      if (lk['targetModuleId'] == targetElId && lk['scheme'] == 'bool_to_visibility') {
        final srcId = lk['sourceModuleId']?.toString();
        if (srcId != null && _elementModules.containsKey(srcId)) {
          final srcMod = _elementModules[srcId]!;
          if (srcMod.type == 'switch' && srcMod.properties['value'] == false) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
