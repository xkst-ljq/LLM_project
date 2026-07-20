import 'dart:async';

import 'linker_event_bus.dart';
import 'linker_matrix_engine.dart';
import 'math_node_engine.dart';
import 'select_option.dart';
import 'text_value_extractor.dart';
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

/// Input 在运行时的校验快照，供 Button 与 Indicator 通路共用。
class InputValidationState {
  final String text;
  final bool isEmpty;
  final bool isValid;
  final int length;

  const InputValidationState({
    required this.text,
    required this.isEmpty,
    required this.isValid,
    required this.length,
  });

  String get status => isEmpty ? 'empty' : (isValid ? 'valid' : 'invalid');
}

/// Indicator 根据本地 statusRules 解析出的当前颜色通道路由状态。
class IndicatorActiveState {
  final int colorValue;
  final bool glow;
  final double glowRadius;

  const IndicatorActiveState({
    required this.colorValue,
    required this.glow,
    required this.glowRadius,
  });
}

/// LinkerService（联动器服务）
class LinkerService {
  /// 全局元素快照：elementId → UIModule
  static final Map<String, UIModule> _elementModules = {};
  static final Map<String, String?> _elementSurfaceParents = {};

  static int _linkerPriority(UIModule linkerModule) {
    final data = (linkerModule.properties['linker'] as Map?)?.cast<String, dynamic>();
    return ((data?['priority'] as num?)?.toInt() ?? 5).clamp(1, 10);
  }

  static int _linkerUpdateStamp(UIModule linkerModule) {
    final data = (linkerModule.properties['linker'] as Map?)?.cast<String, dynamic>();
    return (data?['runtimeUpdatedAt'] as num?)?.toInt() ?? 0;
  }

  static List<UIModule> _sortedLinkersForTarget(String targetId) {
    final entries = _elementModules.entries
        .where((entry) {
          if (entry.value.type != 'linker') return false;
          final data = (entry.value.properties['linker'] as Map?)?.cast<String, dynamic>();
          return data?['targetModuleId']?.toString() == targetId &&
              data?['enabled'] == true;
        })
        .toList();
    entries.sort((a, b) {
      final priority = _linkerPriority(b.value).compareTo(_linkerPriority(a.value));
      if (priority != 0) return priority;
      final stamp = _linkerUpdateStamp(b.value).compareTo(_linkerUpdateStamp(a.value));
      if (stamp != 0) return stamp;
      return b.key.compareTo(a.key);
    });
    return entries.map((entry) => entry.value).toList();
  }

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

  /// 是否存在要求该 Input 在提交后清空自身的输出通路。
  static bool shouldClearInputAfterCommit(String inputElementId) {
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;
      if (linkerData['sourceModuleId']?.toString() == inputElementId &&
          linkerData['scheme'] == 'input_submit_to_text_clear') {
        return true;
      }
    }
    return false;
  }

  /// 是否存在有效的 Input 精确匹配通路控制该 Select 的当前选择。
  static bool isSelectInputControlled(UIModule selectModule) {
    final targetId = _findElementIdForModule(selectModule);
    if (targetId == null) return false;
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;
      if (linkerData['targetModuleId']?.toString() != targetId ||
          linkerData['scheme'] != 'input_value_to_select_match') {
        continue;
      }
      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId != null && _elementModules[sourceId]?.type == 'input') {
        return true;
      }
    }
    return false;
  }

  /// 若 Timer 被有效的系统布尔通路控制，返回该运行状态；否则返回 null。
  /// Timer 根据当前连接拓扑自动推导运行方式。
  static String resolveTimerRunMode(UIModule timerModule) {
    if (resolveTimerSystemRunning(timerModule) != null) return 'controlled';
    final timerId = _findElementIdForModule(timerModule);
    if (timerId == null) return 'auto';
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final data = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data?['enabled'] != true ||
          data?['targetModuleId']?.toString() != timerId ||
          data?['scheme'] != 'click_to_timer_toggle') {
        continue;
      }
      final sourceId = data?['sourceModuleId']?.toString();
      if (sourceId != null && _elementModules[sourceId]?.type == 'button') {
        return 'manual';
      }
    }
    return 'auto';
  }

  /// Timer 是否连接了可能造成高频状态抖动或计算风暴的输出通路。
  static bool timerHasHighRiskOutputs(UIModule timerModule) {
    final timerId = _findElementIdForModule(timerModule);
    if (timerId == null) return false;
    const highRiskSchemes = {
      'timer_tick_to_switch_toggle',
      'timer_tick_to_math_trigger',
    };
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final data = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data?['enabled'] == true &&
          data?['sourceModuleId']?.toString() == timerId &&
          highRiskSchemes.contains(data?['scheme'])) {
        return true;
      }
    }
    return false;
  }

  static bool? resolveTimerSystemRunning(UIModule timerModule) {
    final timerId = _findElementIdForModule(timerModule);
    if (timerId == null) return null;
    bool? running;
    for (final module in _elementModules.values) {
      if (module.type != 'linker') continue;
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null || linkerData['enabled'] != true) continue;
      if (linkerData['targetModuleId']?.toString() != timerId ||
          linkerData['scheme'] != 'boolean_to_timer_running') {
        continue;
      }
      final sourceId = linkerData['sourceModuleId']?.toString();
      final source = sourceId == null ? null : _elementModules[sourceId];
      if (source?.type == 'switch') running = source!.properties['value'] == true;
    }
    return running;
  }

  /// 返回最高优先级 Input → Select filter 通路的查询文本；无通路时为 null。
  static String? resolveSelectFilterQuery(UIModule selectModule) {
    final targetId = _findElementIdForModule(selectModule);
    if (targetId == null) return null;
    for (final linker in _sortedLinkersForTarget(targetId)) {
      final data = (linker.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (data?['scheme'] != 'input_value_to_select_filter') continue;
      final sourceId = data?['sourceModuleId']?.toString();
      final source = sourceId == null ? null : _elementModules[sourceId];
      if (source?.type == 'input') {
        return source!.properties['text']?.toString() ?? '';
      }
    }
    return null;
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
          final definition = LinkerMatrixEngine.getSchemeDefinition(scheme);
          if (definition?.isPulse == true) {
            final now = event.timestamp.microsecondsSinceEpoch;
            final cooldownMs = (lk['cooldownMs'] as num?)?.toInt() ?? 0;
            final lastTriggeredAt = (lk['runtimeLastTriggeredAt'] as num?)?.toInt() ?? 0;
            final maxTriggerCount = (lk['maxTriggerCount'] as num?)?.toInt() ?? 0;
            final triggerCount = (lk['runtimeTriggerCount'] as num?)?.toInt() ?? 0;
            if ((cooldownMs > 0 && now - lastTriggeredAt < cooldownMs * 1000) ||
                (maxTriggerCount > 0 && triggerCount >= maxTriggerCount)) {
              continue;
            }
            lk['runtimeLastTriggeredAt'] = now;
            lk['runtimeTriggerCount'] = triggerCount + 1;
          }
          lk['runtimeUpdatedAt'] = event.timestamp.microsecondsSinceEpoch;
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
              } else if (scheme == 'click_to_switch_set_true' ||
                  scheme == 'timer_tick_to_switch_set_true') {
                props['value'] = true;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_switch_set_false' ||
                  scheme == 'timer_tick_to_switch_set_false') {
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
              } else if (scheme == 'click_to_math_trigger' ||
                  scheme == 'timer_tick_to_math_trigger') {
                final mathModule = targetEl.module!.copyWith(properties: props);
                props['lastResult'] = calculateMathNodeNow(mathModule);
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_timer_toggle') {
                props['isRunning'] = props['isRunning'] != true;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'click_to_timer_reset') {
                props['isRunning'] = false;
                props['currentVal'] = 0.0;
                props['tickCount'] = 0;
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
              } else if (scheme == 'event_to_indicator') {
                props['eventFlashColor'] =
                    (schemeParams['flashColor'] as num?)?.toInt() ?? 0xFFFFA726;
                final flashDuration =
                    (schemeParams['durationMs'] as num?)?.toInt() ?? 300;
                props['eventFlashDurationMs'] = flashDuration;
                props['eventFlashTimestamp'] =
                    DateTime.now().millisecondsSinceEpoch;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
                Future<void>.delayed(
                  Duration(milliseconds: flashDuration),
                  onStateChanged,
                );
              } else if (scheme == 'click_to_surface_press' || scheme == 'click_to_surface_ripple') {
                props['anim_trigger'] = scheme;
                props['anim_duration'] = (schemeParams['durationMs'] as num?)?.toInt() ?? 300;
                props['anim_radius'] = (schemeParams['rippleRadius'] as num?)?.toDouble() ?? 150.0;
                props['anim_timestamp'] = DateTime.now().millisecondsSinceEpoch;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'timer_tick_to_progress_increment' ||
                  scheme == 'timer_tick_to_progress_decrement') {
                final step = (schemeParams['step'] as num?)?.toDouble() ?? 5.0;
                final cur = (props['current'] as num?)?.toDouble() ?? 0.0;
                final max = (props['max'] as num?)?.toDouble() ?? 100.0;
                final min = (props['min'] as num?)?.toDouble() ?? 0.0;
                final behavior =
                    schemeParams['boundaryBehavior']?.toString() ?? 'stop';
                final defaultDirection =
                    scheme == 'timer_tick_to_progress_increment' ? 1.0 : -1.0;
                final direction =
                    (lk['runtimeDirection'] as num?)?.toDouble() ?? defaultDirection;
                var next = cur + step.abs() * direction;
                if (next > max || next < min) {
                  if (behavior == 'loop') {
                    next = next > max ? min : max;
                  } else if (behavior == 'pingPong') {
                    final reversed = -direction;
                    lk['runtimeDirection'] = reversed;
                    next = (cur + step.abs() * reversed).clamp(min, max);
                  } else {
                    next = next.clamp(min, max);
                  }
                }
                props['current'] = next;
                elements[tgtIdx] = targetEl.copyWith(
                  module: targetEl.module!.copyWith(properties: props),
                );
              } else if (scheme == 'input_value_to_select_match' &&
                  srcId != null &&
                  _elementModules[srcId]?.type == 'input') {
                final inputValue =
                    _elementModules[srcId]!.properties['text']?.toString().trim() ?? '';
                final options = SelectOption.parseList(props['options']);
                final matched = options.where(
                  (option) => inputValue.isNotEmpty &&
                      (option.value == inputValue || option.label == inputValue),
                );
                if (matched.isNotEmpty) {
                  props['current'] = matched.first.value;
                  elements[tgtIdx] = targetEl.copyWith(
                    module: targetEl.module!.copyWith(properties: props),
                  );
                }
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
    _elementSurfaceParents.clear();
    for (final el in elements) {
      if (!el.isComposite && el.module != null) {
        _elementModules[el.id] = el.module!;
        _elementSurfaceParents[el.id] = el.parentSurfaceId;
      }
    }
  }

  /// 元素的有效可见性：自身可见，且所有所属 Surface 祖先均可见。
  static bool isElementVisibleInSurfaceHierarchy(UIElement element) {
    var parentId = element.parentSurfaceId;
    final visited = <String>{element.id};
    while (parentId != null && parentId.isNotEmpty) {
      if (!visited.add(parentId)) return false;
      final parentModule = _elementModules[parentId];
      if (parentModule == null ||
          !['surface', 'surface_art', 'primitive_art', 'base_box']
              .contains(parentModule.type) ||
          !resolveTargetControlState(parentModule).visible) {
        return false;
      }
      parentId = _elementSurfaceParents[parentId];
    }
    return true;
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

  static String _textSourceValue(UIModule textModule, [Set<String>? visited]) {
    return resolveLinkedTextValue(textModule) ??
        textModule.properties['text']?.toString() ??
        textModule.name;
  }

  static double _progressFieldValue(UIModule progressModule, String field) {
    final current = (progressModule.properties['current'] as num?)?.toDouble() ?? 0.0;
    final max = (progressModule.properties['max'] as num?)?.toDouble() ?? 100.0;
    return field == 'max' ? max : current;
  }

  static bool _matchesThreshold(double value, String operator, double threshold) {
    switch (operator) {
      case '>':
        return value > threshold;
      case '<':
        return value < threshold;
      case '>=':
        return value >= threshold;
      case '<=':
        return value <= threshold;
      case '==':
        return (value - threshold).abs() < 1e-9;
      default:
        return value >= threshold;
    }
  }

  /// 统一解析 Input 的当前文本、必填与长度校验状态。
  static InputValidationState resolveInputValidationState(UIModule inputModule) {
    final text = inputModule.properties['text']?.toString() ?? '';
    final isEmpty = text.trim().isEmpty;
    final required = inputModule.properties['required'] == true;
    final maxLength = (inputModule.properties['maxLength'] as num?)?.toInt();
    final valid = (!required || !isEmpty) &&
        (maxLength == null || text.length <= maxLength);
    return InputValidationState(
      text: text,
      isEmpty: isEmpty,
      isValid: valid,
      length: text.length,
    );
  }

  /// 统一解析 Indicator 当前激活的颜色通道，供渲染器与下游 Linker 共用。
  static IndicatorActiveState resolveIndicatorActiveState(UIModule indicatorModule) {
    final props = indicatorModule.properties;
    final currentValue =
        (resolveTargetValue(indicatorModule) ?? props['currentValue'] ?? '')
            .toString()
            .trim();
    var colorValue = (props['defaultColor'] as int?) ?? 0xFF9E9E9E;
    var glow = props['defaultGlow'] == true;
    var glowRadius = 12.0;
    final rules = (props['statusRules'] as List?) ?? const [];

    for (final raw in rules) {
      if (raw is! Map) continue;
      final rule = Map<String, dynamic>.from(raw);
      final matchType = rule['matchType']?.toString() ?? 'exact';
      var matched = false;
      if (matchType == 'exact') {
        final expected = rule['matchValue']?.toString().trim() ?? '';
        matched = expected.isNotEmpty && currentValue == expected;
      } else if (matchType == 'bool') {
        final expected = rule['matchValue']?.toString().toLowerCase() == 'true';
        final actual = currentValue.toLowerCase() == 'true' ||
            currentValue == '1' ||
            currentValue == '开启';
        matched = currentValue.isNotEmpty && actual == expected;
      } else if (matchType == 'range') {
        final actual = double.tryParse(currentValue);
        final expected = double.tryParse(rule['matchValNum']?.toString() ?? '');
        final op = rule['matchOp']?.toString() ?? '>';
        if (actual != null && expected != null) {
          matched = switch (op) {
            '>' => actual > expected,
            '<' => actual < expected,
            '>=' => actual >= expected,
            '<=' => actual <= expected,
            '==' => actual == expected,
            _ => false,
          };
        }
      }

      if (matched) {
        colorValue = (rule['color'] as int?) ?? colorValue;
        glow = rule['isGlow'] == true;
        glowRadius = (rule['glowRadius'] as num?)?.toDouble() ?? 12.0;
        break;
      }
    }

    return IndicatorActiveState(
      colorValue: colorValue,
      glow: glow,
      glowRadius: glowRadius,
    );
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
    for (final module in _sortedLinkersForTarget(targetElId)) {
      final linkerData =
          (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;
      if (linkerData['targetModuleId']?.toString() != targetElId ||
          !['value_to_math_param', 'progress_to_math_param', 'text_extract_to_math_param', 'slider_commit_to_math_param']
              .contains(linkerData['scheme'])) {
        continue;
      }

      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId == null || !_elementModules.containsKey(sourceId)) continue;
      final sourceModule = _elementModules[sourceId]!;
      final scheme = linkerData['scheme']?.toString();
      final paramsData = (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};
      dynamic rawValue;
      if (sourceModule.type == 'progress' &&
          scheme == 'progress_to_math_param') {
        rawValue = _progressFieldValue(
          sourceModule,
          paramsData['sourceField']?.toString() ?? 'current',
        );
      } else if (sourceModule.type == 'slider' &&
          scheme == 'slider_commit_to_math_param') {
        rawValue = sourceModule.properties['committedValue'] ?? 0.0;
      } else if (sourceModule.type == 'text' &&
          scheme == 'text_extract_to_math_param') {
        final extracted = TextValueExtractor.extract(
          text: _textSourceValue(sourceModule, visitedSet),
          mode: paramsData['extractMode']?.toString() ?? 'whole',
          numberIndex: (paramsData['numberIndex'] as num?)?.toInt() ?? 0,
          key: paramsData['key']?.toString() ?? '',
        );
        if (extracted == null &&
            paramsData['parseFailBehavior']?.toString() == 'keep') {
          continue;
        }
        rawValue = extracted ?? 0.0;
      } else {
        rawValue = _getEffectivePropertyValue(sourceModule, 'current', visitedSet) ??
            _getEffectivePropertyValue(sourceModule, 'value', visitedSet) ??
            sourceModule.properties['text'] ??
            sourceModule.properties['defaultValue'];
      }
      final targetParam = paramsData['targetParam']?.toString() ?? 'paramA';
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

  /// Math Node 是否存在控制端口或手动触发通路。
  static bool hasMathManualControl(UIModule mathModule) {
    final targetId = _findElementIdForModule(mathModule);
    if (targetId == null) return false;
    for (final linker in _sortedLinkersForTarget(targetId)) {
      final data = (linker.properties['linker'] as Map?)?.cast<String, dynamic>();
      final scheme = data?['scheme']?.toString();
      if (data?['targetPort'] == 'gate_in' ||
          scheme == 'click_to_math_trigger' ||
          scheme == 'timer_tick_to_math_trigger') {
        return true;
      }
    }
    return false;
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
    final manualMode = hasMathManualControl(mathModule);
    if (controls.frozen || manualMode) {
      return mathModule.properties['lastResult'] ?? fallback;
    }
    return calculateMathNodeNow(mathModule, visited: visitedSet);
  }

  /// 无视 manual 模式立即计算 Math Node；按钮与 Timer trigger 使用此入口。
  static dynamic calculateMathNodeNow(
    UIModule mathModule, {
    Set<String>? visited,
  }) {
    final controls = resolveTargetControlState(mathModule);
    final fallback = MathNodeEngine.toNumber(mathModule.properties['fallbackValue']);
    if (controls.frozen) return mathModule.properties['lastResult'] ?? fallback;
    final operation = mathModule.properties['operation']?.toString() ?? '+';
    final params = resolveMathNodeParameters(mathModule, visited: visited);
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

    for (final module in _sortedLinkersForTarget(targetElId)) {
      final linkerData = (module.properties['linker'] as Map?)?.cast<String, dynamic>();
      if (linkerData == null) continue;

      final targetId = linkerData['targetModuleId']?.toString();
      if (targetId == null || targetId != targetElId) continue;

      final sourceId = linkerData['sourceModuleId']?.toString();
      if (sourceId == null || !_elementModules.containsKey(sourceId)) continue;

      final sourceModule = _elementModules[sourceId]!;
      final scheme = linkerData['scheme']?.toString();
      if (scheme == null || !LinkerMatrixEngine.isSchemeSelectable(scheme)) continue;

      final schemeParams = (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};

      // Input 协议：实时值、提交值与状态值分别输出。
      if (sourceModule.type == 'input') {
        final inputState = resolveInputValidationState(sourceModule);
        switch (scheme) {
          case 'input_live_to_text':
            return inputState.text;
          case 'input_commit_to_text':
          case 'input_submit_to_text_clear':
            return sourceModule.properties['committedValue']?.toString() ?? '';
          case 'input_validity_to_indicator':
            return inputState.status;
          case 'input_length_to_indicator':
            return inputState.length.toString();
          case 'input_value_to_select_match':
            final inputValue = inputState.text.trim();
            final options = SelectOption.parseList(targetModule.properties['options']);
            for (final option in options) {
              if (inputValue.isNotEmpty &&
                  (option.value == inputValue || option.label == inputValue)) {
                return option.value;
              }
            }
            return null;
        }
      }

      if (sourceModule.type == 'slider' && scheme == 'slider_commit_to_text') {
        final value = (sourceModule.properties['committedValue'] as num?)?.toDouble() ??
            0.0;
        final precision = ((schemeParams['precision'] as num?)?.toInt() ?? 0)
            .clamp(0, 6)
            .toInt();
        final template = schemeParams['template']?.toString() ?? '{{value}}';
        return template.replaceAll('{{value}}', value.toStringAsFixed(precision));
      }

      if (sourceModule.type == 'text') {
        final textValue = _textSourceValue(sourceModule, visitedSet);
        if (scheme == 'text_match_to_switch') {
          final triggerText = schemeParams['triggerText']?.toString() ?? '';
          return triggerText.isNotEmpty && textValue == triggerText;
        }
        if (scheme == 'text_value_to_select_match') {
          final options = (targetModule.properties['options'] as List?)
                  ?.map((option) => option.toString())
                  .toList() ??
              const <String>[];
          return options.contains(textValue) ? textValue : null;
        }
      }

      if (sourceModule.type == 'progress') {
        final current = _progressFieldValue(sourceModule, 'current');
        final max = _progressFieldValue(sourceModule, 'max');
        if (scheme == 'progress_to_text') {
          final field = schemeParams['sourceField']?.toString() ?? 'current';
          final precision = ((schemeParams['precision'] as num?)?.toInt() ?? 0)
              .clamp(0, 6)
              .toInt();
          final raw = switch (field) {
            'max' => max.toStringAsFixed(precision),
            'percentage' => (max == 0 ? 0.0 : current / max * 100)
                .toStringAsFixed(precision),
            'range' => '${current.toStringAsFixed(precision)} / ${max.toStringAsFixed(precision)}',
            _ => current.toStringAsFixed(precision),
          };
          final template = schemeParams['template']?.toString() ?? '{{value}}';
          return template.replaceAll('{{value}}', raw);
        }
        if (scheme == 'progress_threshold_to_switch') {
          final operator = schemeParams['operator']?.toString() ?? '>=';
          final threshold = (schemeParams['threshold'] as num?)?.toDouble() ?? 100.0;
          return _matchesThreshold(current, operator, threshold);
        }
      }

      if (sourceModule.type == 'timer' && scheme == 'timer_value_to_text') {
        final field = schemeParams['sourceField']?.toString() ?? 'currentVal';
        final precision = ((schemeParams['precision'] as num?)?.toInt() ?? 0)
            .clamp(0, 6)
            .toInt();
        if (field == 'tickCount') {
          return (sourceModule.properties['tickCount'] as num?)?.toInt().toString() ?? '0';
        }
        final value = field == 'stepValue'
            ? (sourceModule.properties['stepValue'] as num?)?.toDouble() ?? 0.0
            : (sourceModule.properties['currentVal'] as num?)?.toDouble() ?? 0.0;
        return value.toStringAsFixed(precision);
      }

      if (sourceModule.type == 'select' && scheme == 'select_to_text') {
        final current = sourceModule.properties['current']?.toString() ??
            sourceModule.properties['defaultValue']?.toString() ?? '';
        final matches = SelectOption.parseList(sourceModule.properties['options'])
            .where((item) => item.value == current)
            .toList();
        return matches.isEmpty ? current : matches.first.label;
      }

      if (sourceModule.type == 'select' && scheme == 'select_value_to_switch') {
        final triggerValue =
            schemeParams['triggerValue']?.toString() ?? '';
        final selectedValue = sourceModule.properties['current']?.toString() ??
            sourceModule.properties['defaultValue']?.toString() ??
            '';
        return triggerValue.isNotEmpty && selectedValue == triggerValue;
      }

      // Indicator 颜色通道路由：用当前 activeColor 驱动下游。
      if (sourceModule.type == 'indicator' &&
          ['indicator_color_to_switch', 'indicator_color_to_text'].contains(scheme)) {
        final triggerColor = (schemeParams['triggerColor'] as num?)?.toInt() ??
            0xFF4CAF50;
        final matches =
            resolveIndicatorActiveState(sourceModule).colorValue == triggerColor;
        if (scheme == 'indicator_color_to_switch') return matches;
        return matches
            ? schemeParams['matchText']?.toString() ?? '已激活'
            : schemeParams['mismatchText']?.toString() ?? '';
      }

      // 仅保留当前注册表中有完整运行端支持的方案。
      if (scheme == 'result_to_text' ||
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
  /// Switch 布尔控制与 Indicator 颜色通道均复用该解析器，
  /// 后续来源协议无需再修改各目标组件的渲染逻辑。
  static LinkerTargetControlState resolveTargetControlState(
    UIModule targetModule,
  ) {
    final baseVisible = targetModule.properties['visible'] != false;
    final baseEnabled = targetModule.properties['enabled'] != false;
    var locked = targetModule.properties['locked'] == true;
    var frozen = targetModule.properties['frozen'] == true;
    final enabledSignals = <bool>[];
    final visibleSignals = <bool>[];
    final targetElId = _findElementIdForModule(targetModule);
    if (targetElId == null) {
      return LinkerTargetControlState(
        visible: baseVisible,
        enabled: baseEnabled,
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
      if (sourceModule.type == 'text') {
        final textValue = _textSourceValue(sourceModule);
        if (scheme == 'text_nonempty_to_button_enable') {
          enabledSignals.add(textValue.trim().isNotEmpty);
          continue;
        }
        if (scheme == 'text_match_to_button_enable') {
          final triggerText =
              (linkerData['schemeParams'] as Map?)?['triggerText']?.toString() ?? '';
          enabledSignals.add(triggerText.isNotEmpty && textValue == triggerText);
          continue;
        }
      }
      if (sourceModule.type == 'progress' &&
          scheme == 'progress_threshold_to_button_enable') {
        final progressParams =
            (linkerData['schemeParams'] as Map?)?.cast<String, dynamic>() ?? {};
        enabledSignals.add(_matchesThreshold(
          _progressFieldValue(sourceModule, 'current'),
          progressParams['operator']?.toString() ?? '>=',
          (progressParams['threshold'] as num?)?.toDouble() ?? 100.0,
        ));
        continue;
      }
      if (sourceModule.type == 'input') {
        final inputState = resolveInputValidationState(sourceModule);
        switch (scheme) {
          case 'input_nonempty_to_button_enable':
            enabledSignals.add(!inputState.isEmpty);
            continue;
          case 'input_valid_to_button_enable':
            enabledSignals.add(inputState.isValid);
            continue;
        }
      }
      if (sourceModule.type == 'select' &&
          scheme == 'select_value_to_surface_visible') {
        final triggerValue =
            (linkerData['schemeParams'] as Map?)?['triggerValue']?.toString() ?? '';
        final selectedValue = sourceModule.properties['current']?.toString() ??
            sourceModule.properties['defaultValue']?.toString() ??
            '';
        visibleSignals.add(
          triggerValue.isNotEmpty && selectedValue == triggerValue,
        );
        continue;
      }
      if (sourceModule.type == 'indicator') {
        final triggerColorValue =
            (linkerData['schemeParams'] as Map?)?['triggerColor'];
        final triggerColor =
            (triggerColorValue as num?)?.toInt() ?? 0xFF4CAF50;
        final matches =
            resolveIndicatorActiveState(sourceModule).colorValue == triggerColor;
        switch (scheme) {
          case 'indicator_color_to_enabled':
            enabledSignals.add(matches);
            continue;
          case 'indicator_color_to_locked':
            locked = locked || matches;
            continue;
          case 'indicator_color_to_frozen':
            frozen = frozen || matches;
            continue;
          case 'indicator_color_to_visible':
            visibleSignals.add(matches);
            continue;
        }
      }

      final rawValue = sourceModule.properties['value'];
      final sourceValue = rawValue is bool
          ? rawValue
          : rawValue == null
              ? null
              : rawValue.toString().toLowerCase() == 'true';
      if (sourceValue == null) continue;

      switch (scheme) {
        case 'boolean_to_visible':
          visibleSignals.add(sourceValue);
          break;
        case 'boolean_to_enabled':
          enabledSignals.add(sourceValue);
          break;
        case 'boolean_to_locked':
          locked = locked || sourceValue;
          break;
        case 'boolean_to_frozen':
          frozen = frozen || sourceValue;
          break;
      }
    }

    bool combine(bool base, List<bool> signals, String mode) {
      if (!base || signals.isEmpty) return base;
      return mode == 'or' ? signals.any((value) => value) : signals.every((value) => value);
    }

    return LinkerTargetControlState(
      visible: combine(
        baseVisible,
        visibleSignals,
        targetModule.properties['visibleCombineMode']?.toString() ?? 'and',
      ),
      enabled: combine(
        baseEnabled,
        enabledSignals,
        targetModule.properties['enabledCombineMode']?.toString() ?? 'and',
      ),
      locked: locked,
      frozen: frozen,
    );
  }


}
