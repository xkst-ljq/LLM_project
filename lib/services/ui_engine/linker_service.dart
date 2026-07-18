import 'dart:async';

import 'linker_event_bus.dart';
import 'linker_matrix_engine.dart';
import 'math_node_engine.dart';
import 'ui_models.dart';

/// Linker 目标组件的统一运行期控制状态。
class LinkerTargetControlState {
  final bool visible;
  final bool enabled;
  final bool locked;
  final bool frozen;

  const LinkerTargetControlState({
    this.visible = true,
    this.enabled = true,
    this.locked = false,
    this.frozen = false,
  });

  bool get isInteractive => enabled && !locked;
}

/// LinkerService（联动器服务）
class LinkerService {
  /// 全局元素快照：elementId → UIModule
  static final Map<String, UIModule> _elementModules = {};

  static StreamSubscription<LinkerPulseEvent>? _pulseSubscription;

  /// 初始化脉冲事件总线监听器（连接按钮点击/定时器脉冲触发真实状态改写）
  /// 判断某组件指定手势端口（tap / double_tap / long_press）是否已有生效连线
  static bool hasConnectedPort(String elementId, String portName) {
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final lkData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (lkData == null || lkData['enabled'] == false) continue;

      final srcId = lkData['sourceModuleId']?.toString();
      final srcPort = lkData['sourcePort']?.toString() ?? 'output';

      if (srcId == elementId) {
        if (portName == 'tap' && (srcPort == 'tap' || srcPort == 'output' || srcPort == 'current')) {
          return true;
        }
        if (srcPort == portName) {
          return true;
        }
      }
    }
    return false;
  }

  static void initEventBusListener(List<UIElement> elements, void Function() onStateChanged) {
    _pulseSubscription?.cancel();
    _pulseSubscription = LinkerEventBus().onPulse.listen((event) {
      bool needRefresh = false;

      for (final el in elements) {
        if (el.isComposite || el.module?.type != 'linker') continue;
        final lk = (el.module?.properties['linker'] as Map?)?.cast<String, dynamic>();
        if (lk == null || lk['enabled'] == false) continue;

        final srcId = lk['sourceModuleId']?.toString();
        final srcPort = lk['sourcePort']?.toString() ?? 'output';
        final tgtId = lk['targetModuleId']?.toString();
        final scheme = lk['scheme']?.toString();
        if (scheme == null || !LinkerMatrixEngine.isSchemeSelectable(scheme)) {
          continue;
        }

        final bool isGestureEvent = event.eventType == 'tap' ||
            event.eventType == 'double_tap' ||
            event.eventType == 'long_press';

        bool isMatch = false;
        if (srcId == event.sourceModuleId) {
          if (isGestureEvent) {
            isMatch = (srcPort == event.eventType ||
                (event.eventType == 'tap' && (srcPort == 'output' || srcPort == 'current' || srcPort == 'tap')));
          } else {
            isMatch = true;
          }
        }

        if (isMatch && tgtId != null) {
          needRefresh = true;
          final tgtIdx = elements.indexWhere((e) => e.id == tgtId);
          if (tgtIdx != -1) {
            final targetEl = elements[tgtIdx];
            if (!targetEl.isComposite && targetEl.module != null) {
              final props = Map<String, dynamic>.from(targetEl.module!.properties);
              final schemeParams = (lk['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};

              if (scheme == 'click_to_switch_toggle' || scheme == 'timer_tick_to_switch_toggle') {
                final cur = props['value'] == true;
                props['value'] = !cur;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_switch_set_true') {
                props['value'] = true;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_switch_set_false') {
                props['value'] = false;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_input_clear') {
                props['text'] = '';
                props['value'] = '';
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_slider_reset') {
                final defVal = (props['defaultValue'] as num?)?.toDouble() ??
                    ((props['min'] as num?)?.toDouble() ?? 0.0);
                props['current'] = defVal;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_surface_press' || scheme == 'click_to_surface_ripple') {
                props['anim_trigger'] = scheme;
                props['anim_duration'] = (schemeParams['durationMs'] as num?)?.toInt() ?? 300;
                props['anim_radius'] = (schemeParams['rippleRadius'] as num?)?.toDouble() ?? 150.0;
                props['anim_timestamp'] = DateTime.now().millisecondsSinceEpoch;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'timer_tick_to_progress_increment') {
                final step = (schemeParams['step'] as num?)?.toDouble() ?? 5.0;
                final cur = (props['current'] as num?)?.toDouble() ?? 0.0;
                final max = (props['max'] as num?)?.toDouble() ?? 100.0;
                final min = (props['min'] as num?)?.toDouble() ?? 0.0;
                props['current'] = (cur + step).clamp(min, max);
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              }
            }
          }
        }
      }

      if (needRefresh) {
        onStateChanged();
      }
    });
  }

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
    if (_elementModules.containsKey(targetModule.id)) {
      return targetModule.id;
    }
    for (final entry in _elementModules.entries) {
      if (identical(entry.value, targetModule)) {
        return entry.key;
      }
    }
    return null;
  }

  /// 解析源模块的动态生效属性（支持递归溯源与环路检测）
  static dynamic _getEffectivePropertyValue(
      UIModule sourceModule, String propKey, Set<String> visitedSet) {
    if (sourceModule.type == 'math_node' &&
        (propKey == 'current' || propKey == 'value' || propKey == 'result')) {
      return resolveMathNodeResult(sourceModule, visited: visitedSet);
    }
    if (propKey == 'current' || propKey == 'value') {
      final incoming = resolveTargetValue(sourceModule, visitedSet);
      if (incoming != null) return incoming;
    }
    return sourceModule.properties[propKey];
  }

  /// 读取 Math Node 的动态参数口值；每条 value_to_math_param 可覆盖一个参数口。
  static Map<String, double> resolveMathNodeParameters(
    UIModule mathModule, {
    Set<String>? visited,
  }) {
    final params = <String, double>{
      'paramA': MathNodeEngine.toNumber(mathModule.properties['paramA']),
      'paramB': MathNodeEngine.toNumber(mathModule.properties['paramB']),
      'paramC': MathNodeEngine.toNumber(mathModule.properties['paramC']),
    };
    final targetElId = _findElementIdForModule(mathModule);
    if (targetElId == null) return params;

    final visitedSet = visited != null ? Set<String>.from(visited) : <String>{};
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;
      if (linkerData['targetModuleId']?.toString() != targetElId ||
          linkerData['scheme'] != 'value_to_math_param') {
        continue;
      }

      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId == null || !_elementModules.containsKey(sourceId)) continue;
      final sourceModule = _elementModules[sourceId]!;
      final rawValue = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
          _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
          sourceModule.properties['text'] ??
          sourceModule.properties['defaultValue'];
      final targetParam = (linkerData['schemeParams'] as Map?)?['targetParam']
              ?.toString() ??
          'paramA';
      if (params.containsKey(targetParam)) {
        params[targetParam] = MathNodeEngine.toNumber(rawValue);
      }
    }
    return params;
  }

  /// 返回当前 Math Node 有序启用的参数口。顺序即减法、除法等运算顺序。
  static List<String> resolveMathNodeActiveParams(UIModule mathModule) {
    const allowed = {'paramA', 'paramB', 'paramC'};
    final stored = mathModule.properties['activeParams'];
    final active = stored is List
        ? stored.map((value) => value.toString()).where(allowed.contains).toList()
        : <String>[];
    if (active.isNotEmpty) return active.toSet().toList();
    return const ['paramA', 'paramB'];
  }

  /// 计算 Math Node V1 的当前输出。计算链通过 [visited] 防止递归闭环。
  static dynamic resolveMathNodeResult(
    UIModule mathModule, {
    Set<String>? visited,
  }) {
    final mathId = _findElementIdForModule(mathModule);
    final visitedSet = visited != null ? Set<String>.from(visited) : <String>{};
    if (mathId != null && visitedSet.contains(mathId)) return null;
    if (mathId != null) visitedSet.add(mathId);

    final controls = resolveTargetControlState(mathModule);
    final fallback = MathNodeEngine.toNumber(mathModule.properties['fallbackValue']);
    if (controls.frozen || mathModule.properties['calculationMode'] == 'manual') {
      return mathModule.properties['lastResult'] ?? fallback;
    }

    final operation = mathModule.properties['operation']?.toString() ?? '+';
    final params = resolveMathNodeParameters(mathModule, visited: visitedSet);
    final activeParams = resolveMathNodeActiveParams(mathModule);
    final operands = activeParams.map((param) => params[param] ?? 0).toList();
    return MathNodeEngine.evaluate(
      operation: operation,
      operands: operands,
      fallbackValue: fallback,
    );
  }

  /// 获取目标模块上游连接源的属性上下文（用于模板表达式解析）
  static Map<String, dynamic>? getSourceContextForTarget(UIModule targetModule) {
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) return null;

    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;

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
      if (linkerData == null || linkerData['enabled'] != true) continue;

      final targetId = linkerData['targetModuleId']?.toString();
      if (targetId == null || targetId != targetElId) continue;

      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId == null || !_elementModules.containsKey(sourceId)) continue;

      final sourceModule = _elementModules[sourceId]!;
      final scheme = linkerData['scheme']?.toString();
      if (scheme == null || !LinkerMatrixEngine.isSchemeSelectable(scheme)) continue;

      final schemeParams = (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};

      // 仅保留当前注册表中有完整运行端支持的方案。
      if (scheme == 'result_to_text' ||
          scheme == 'text_to_text' ||
          scheme == 'slider_to_text' ||
          scheme == 'progress_to_text' ||
          scheme == 'select_to_text') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            sourceModule.properties['text'] ??
            sourceModule.properties['defaultValue'] ??
            sourceModule.name;
        if (rawVal != null) {
          final template = schemeParams['template']?.toString() ?? '{{value}}';
          final precision = (schemeParams['precision'] as num?)?.toInt() ?? 0;
          final strVal = rawVal is num
              ? rawVal.toStringAsFixed(precision)
              : rawVal.toString();
          return template.replaceAll('{{value}}', strVal);
        }
      } else if (scheme == 'bool_result_to_text' || scheme == 'bool_to_text') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            true;
        final bool boolVal = rawVal is bool
            ? rawVal
            : rawVal.toString().toLowerCase() == 'true';
        final trueText = schemeParams['trueText']?.toString() ?? '开启/通过';
        final falseText = schemeParams['falseText']?.toString() ?? '关闭/未通过';
        return boolVal ? trueText : falseText;
      } else if (scheme == 'result_to_progress' ||
          scheme == 'slider_to_progress' ||
          scheme == 'input_to_progress' ||
          scheme == 'input_to_slider') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'text', visitedSet) ??
            0.0;
        final double doubleVal = rawVal is num
            ? rawVal.toDouble()
            : (double.tryParse(rawVal.toString()) ?? 0.0);
        if (targetModule.type == 'progress' || targetModule.type == 'slider') {
          final mode = schemeParams['mappingMode']?.toString() ?? 'ratio';
          final double srcMin =
              (sourceModule.properties['min'] as num?)?.toDouble() ?? 0.0;
          final double srcMax =
              (sourceModule.properties['max'] as num?)?.toDouble() ?? 100.0;
          final double tgtMin =
              (targetModule.properties['min'] as num?)?.toDouble() ?? 0.0;
          final double tgtMax =
              (targetModule.properties['max'] as num?)?.toDouble() ?? 100.0;
          if (mode == 'ratio') {
            final double ratio = srcMax > srcMin
                ? ((doubleVal - srcMin) / (srcMax - srcMin)).clamp(0.0, 1.0)
                : 0.0;
            return tgtMin + ratio * (tgtMax - tgtMin);
          }
          return doubleVal.clamp(tgtMin, tgtMax);
        }
        return doubleVal;
      } else if (scheme == 'bool_result_to_progress') {
        final rawVal =
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ?? true;
        final bool boolVal = rawVal is bool
            ? rawVal
            : rawVal.toString().toLowerCase() == 'true';
        final max = (targetModule.properties['max'] as num?)?.toDouble() ?? 100.0;
        final min = (targetModule.properties['min'] as num?)?.toDouble() ?? 0.0;
        return boolVal ? max : min;
      } else if (scheme == 'to_string') {
        final val = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'currentVal', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'defaultValue', visitedSet) ??
            sourceModule.properties['text'] ??
            sourceModule.name;
        if (val != null) {
          return val is num ? val.toStringAsFixed(0) : val.toString();
        }
      } else if (scheme == 'name_to_text') {
        return sourceModule.name;
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

  /// 汇总目标组件的运行期控制状态。
  ///
  /// 现阶段已接入 [bool_to_visibility]；其他布尔控制 scheme 会在其
  /// 来源协议开放后复用同一解析器，无需再修改各目标组件的渲染逻辑。
  static LinkerTargetControlState resolveTargetControlState(
    UIModule targetModule,
  ) {
    bool visible = targetModule.properties['visible'] != false;
    bool enabled = targetModule.properties['enabled'] != false;
    bool locked = targetModule.properties['locked'] == true;
    bool frozen = targetModule.properties['frozen'] == true;
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) {
      return LinkerTargetControlState(
        visible: visible,
        enabled: enabled,
        locked: locked,
        frozen: frozen,
      );
    }

    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;
      if (linkerData['targetModuleId']?.toString() != targetElId) continue;

      final scheme = linkerData['scheme']?.toString();
      final sourceId = linkerData['sourceModuleId']?.toString();
      if (scheme == null ||
          sourceId == null ||
          !_elementModules.containsKey(sourceId)) {
        continue;
      }

      final sourceModule = _elementModules[sourceId]!;
      final rawValue = sourceModule.properties['value'];
      final bool? sourceValue = rawValue is bool
          ? rawValue
          : rawValue == null
              ? null
              : rawValue.toString().toLowerCase() == 'true';
      if (sourceValue == null) continue;

      switch (scheme) {
        case 'bool_to_visibility':
        case 'boolean_to_visible':
          visible = visible && sourceValue;
          break;
        case 'boolean_to_enabled':
          enabled = enabled && sourceValue;
          break;
        case 'boolean_to_locked':
          locked = locked || sourceValue;
          break;
        case 'boolean_to_frozen':
          frozen = frozen || sourceValue;
          break;
        default:
          break;
      }
    }

    return LinkerTargetControlState(
      visible: visible,
      enabled: enabled,
      locked: locked,
      frozen: frozen,
    );
  }

  /// 兼容现有渲染入口；新代码应直接使用 [resolveTargetControlState]。
  static bool isTargetHiddenBySwitch(String targetElId) {
    final targetModule = _elementModules[targetElId];
    return targetModule != null && !resolveTargetControlState(targetModule).visible;
  }
}
