import 'dart:async';
import 'dart:ui';

import 'linker_event_bus.dart';
import 'ui_models.dart';

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

        if (isMatch && tgtId != null && scheme != null) {
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

      final schemeParams = (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};

      // === 动态解析全量 Scheme 方案 ===

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

          final strVal = (rawVal is num)
              ? rawVal.toStringAsFixed(precision)
              : rawVal.toString();

          return template.replaceAll('{{value}}', strVal);
        }
      } else if (scheme == 'bool_result_to_text' || scheme == 'bool_to_text') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            true;

        final bool boolVal = (rawVal is bool) ? rawVal : (rawVal.toString().toLowerCase() == 'true');
        final trueText = schemeParams['trueText']?.toString() ?? '开启/通过';
        final falseText = schemeParams['falseText']?.toString() ?? '关闭/未通过';
        return boolVal ? trueText : falseText;
      } else if (scheme == 'result_to_progress' ||
          scheme == 'slider_to_progress' ||
          scheme == 'num_to_current' ||
          scheme == 'math_to_current' ||
          scheme == 'input_to_progress' ||
          scheme == 'input_to_slider') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'text', visitedSet) ??
            0.0;

        double doubleVal = (rawVal is num) ? rawVal.toDouble() : (double.tryParse(rawVal.toString()) ?? 0.0);

        if (targetModule.type == 'progress' || targetModule.type == 'slider') {
          final mode = schemeParams['mappingMode']?.toString() ?? 'ratio';

          final double srcMin = (sourceModule.properties['min'] as num?)?.toDouble() ?? 0.0;
          final double srcMax = (sourceModule.properties['max'] as num?)?.toDouble() ?? 100.0;

          final double tgtMin = (targetModule.properties['min'] as num?)?.toDouble() ?? 0.0;
          final double tgtMax = (targetModule.properties['max'] as num?)?.toDouble() ?? 100.0;

          if (mode == 'ratio') {
            final double ratio = (srcMax > srcMin)
                ? ((doubleVal - srcMin) / (srcMax - srcMin)).clamp(0.0, 1.0)
                : 0.0;
            return tgtMin + ratio * (tgtMax - tgtMin);
          } else {
            return doubleVal.clamp(tgtMin, tgtMax);
          }
        }
        return doubleVal;
      } else if (scheme == 'bool_result_to_progress') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ?? true;
        final bool boolVal = (rawVal is bool) ? rawVal : (rawVal.toString().toLowerCase() == 'true');
        final max = (targetModule.properties['max'] as num?)?.toDouble() ?? 100.0;
        final min = (targetModule.properties['min'] as num?)?.toDouble() ?? 0.0;
        return boolVal ? max : min;
      } else if (scheme == 'threshold_to_switch') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            0.0;
        final double numVal = (rawVal is num) ? rawVal.toDouble() : (double.tryParse(rawVal.toString()) ?? 0.0);

        final op = schemeParams['operator']?.toString() ?? '>';
        final threshold = (schemeParams['threshold'] as num?)?.toDouble() ?? 0.0;

        const double epsilon = 1e-9;
        switch (op) {
          case '>':
            return numVal > threshold;
          case '<':
            return numVal < threshold;
          case '>=':
            return numVal >= threshold - epsilon;
          case '<=':
            return numVal <= threshold + epsilon;
          case '==':
            return (numVal - threshold).abs() < epsilon;
          default:
            return numVal > threshold;
        }
      } else if (scheme == 'select_to_switch') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'defaultValue', visitedSet) ??
            '';
        final matchValue = schemeParams['matchValue']?.toString() ?? '';
        return rawVal.toString() == matchValue;
      } else if (scheme == 'bool_result_to_switch' || scheme == 'indicator_state_to_switch') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ?? true;
        return (rawVal is bool) ? rawVal : (rawVal.toString().toLowerCase() == 'true');
      } else if (scheme == 'threshold_to_indicator' || scheme == 'slider_to_indicator') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            50.0;
        final double numVal = (rawVal is num) ? rawVal.toDouble() : (double.tryParse(rawVal.toString()) ?? 0.0);

        final minThresh = (schemeParams['thresholdLower'] as num?)?.toDouble() ?? 30.0;
        final maxThresh = (schemeParams['thresholdUpper'] as num?)?.toDouble() ?? 80.0;

        final colorLower = (schemeParams['colorLower'] as num?)?.toInt() ?? 0xFFFF5252;
        final colorMid = (schemeParams['colorMid'] as num?)?.toInt() ?? 0xFF69F0AE;
        final colorUpper = (schemeParams['colorUpper'] as num?)?.toInt() ?? 0xFFFFD740;

        if (numVal < minThresh) {
          return Color(colorLower);
        } else if (numVal <= maxThresh) {
          return Color(colorMid);
        } else {
          return Color(colorUpper);
        }
      } else if (scheme == 'str_to_indicator') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'text', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            '';
        final matchStr = schemeParams['matchString']?.toString() ?? '正常';
        return (rawVal.toString() == matchStr) ? const Color(0xFF69F0AE) : const Color(0xFFFF5252);
      } else if (scheme == 'bool_result_to_indicator' || scheme == 'bool_to_indicator') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ?? true;
        final bool boolVal = (rawVal is bool) ? rawVal : (rawVal.toString().toLowerCase() == 'true');
        return boolVal ? const Color(0xFF69F0AE) : const Color(0xFFFF5252);
      } else if (scheme == 'threshold_to_button_enable') {
        final rawVal = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ?? 0.0;
        final double numVal = (rawVal is num) ? rawVal.toDouble() : (double.tryParse(rawVal.toString()) ?? 0.0);
        final thresh = (schemeParams['threshold'] as num?)?.toDouble() ?? 100.0;
        return numVal >= thresh;
      } else if (['current_to_text', 'to_string', 'str_to_select', 'num_to_indicator'].contains(scheme)) {
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
      } else if (['name_to_text', 'name_to_select', 'name_to_label', 'name_to_button_text'].contains(scheme)) {
        return sourceModule.name;
      } else if (scheme == 'bounds_to_text') {
        final w = sourceModule.properties['width'] ?? 200;
        final h = sourceModule.properties['height'] ?? 100;
        return "$w x $h px";
      } else if (['size_to_max', 'width_to_max', 'width_to_line_length', 'size_to_viewport_content'].contains(scheme)) {
        final w = sourceModule.properties['width'] ?? 300.0;
        return (w as num).toDouble();
      } else if (['surface_to_button_enable', 'surface_to_input_enable', 'surface_to_progress_enable', 'surface_to_switch_enable', 'surface_to_select_enable', 'surface_to_indicator_state', 'bool_to_button_enable', 'bool_to_input_enable', 'input_to_button_enable', 'math_to_button_enable', 'indicator_state_to_button_enable'].contains(scheme)) {
        return sourceModule.properties['isActive'] != false && sourceModule.properties['value'] != false;
      } else if (scheme == 'math_to_text') {
        final val = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            '0';
        return val.toString();
      }
    }

    return null;
  }

  /// 解析组件被上游底面联动绑定的主题颜色
  static Color? resolveTargetColor(UIModule targetModule) {
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) return null;

    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;
      if (linkerData['targetModuleId']?.toString() != targetElId) continue;
      final scheme = linkerData['scheme']?.toString();
      if (scheme == null || !scheme.startsWith('color_to_')) continue;
      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId != null && _elementModules.containsKey(sourceId)) {
        return _elementModules[sourceId]!.color;
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
