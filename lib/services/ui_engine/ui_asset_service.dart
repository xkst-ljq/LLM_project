import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_models.dart';

class UIAssetService {
  static const String _storageKey = 'global_ui_assets_flat_foundation_v2';

  /// 左侧原材料库的唯一内置原子清单与展示顺序。
  /// 用户保存的资产不在此处展示，统一进入右侧完成资产库。
  static const List<String> _foundationModuleOrder = [
    'atom_surface_base', 'atom_image_holder', 'atom_line_multi',
    'atom_text', 'atom_data_bar', 'atom_indicator_basic',
    'atom_logic_input_text', 'atom_select_basic', 'atom_slider_basic',
    'atom_logic_switch_bool', 'atom_logic_button_tap',
    'atom_linker_basic', 'atom_logic_math_node', 'atom_timer_basic',
  ];

  /// 已移除的旧版基础面预设；加载历史资产时不将其误当成用户资产回收展示。
  static const Set<String> _retiredFoundationModuleIds = {
    'atom_surface_capsule',
    'atom_surface_ellipse',
    'atom_surface_outline',
  };

  // 全局原子模组库
  Map<String, UIModule> _modules = {};
  // 全局组合块库
  Map<String, UIComposite> _composites = {};

  UIAssetService() {
    _initDefaultAssets();
    _loadAssets();
  }

  // 提供开箱即用的“扁平化基础原材料”库。
  // 当前默认不再内置复合资产，也不默认暴露玻璃/光效/高级面等风格化原子；
  // 如后续确实需要，再从引擎能力中重新开放。
  void _initDefaultAssets() {
    final dataBar = UIModule(
      id: 'atom_data_bar',
      name: '进度条',
      type: 'progress',
      color: const Color(0xFFFF4081),
      properties: {'min': 0, 'max': 100, 'current': 65},
    );

    final surfaceBase = UIModule(
      id: 'atom_surface_base',
      name: '面板',
      type: 'surface',
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rounded,
      borderRadius: 16,
      properties: {},
    );
    final text = UIModule(
      id: 'atom_text',
      name: '文本',
      type: 'text',
      color: const Color(0xFF111116),
      properties: {'text': '文本'},
    );

    final buttonLogic = UIModule(
      id: 'atom_logic_button_tap',
      name: '按钮',
      type: 'button',
      color: Colors.transparent,
      properties: {
        'action': 'tap',
        'doubleTapIntervalMs': 300,
        'longPressThresholdMs': 500,
      },
    );
    final inputLogic = UIModule(
      id: 'atom_logic_input_text',
      name: '输入框',
      type: 'input',
      color: Colors.transparent,
      properties: {'variable': 'var.input'},
    );

    final switchLogic = UIModule(
      id: 'atom_logic_switch_bool',
      name: '开关',
      type: 'switch',
      color: const Color(0xFF00E676),
      properties: {'value': true, 'variable': 'switch_var'},
    );

    final slider = UIModule(
      id: 'atom_slider_basic',
      name: '滑块',
      type: 'slider',
      color: const Color(0xFF00ACC1),
      properties: {'min': 0, 'max': 100, 'current': 50, 'step': 1},
    );

    final line = UIModule(
      id: 'atom_line_multi',
      name: '分割线',
      type: 'line',
      color: const Color(0xFFB0BEC5),
      properties: {'thickness': 2.0, 'lineStyle': 'solid', 'axis': 'horizontal', 'dashLength': 6.0, 'gapLength': 3.0},
    );

    final imageSlot = UIModule(
      id: 'atom_image_holder',
      name: '图片',
      type: 'image',
      color: const Color(0xFF2979FF),
      properties: {'url': '', 'fit': 'cover', 'shape': 'rectangle', 'borderRadius': 8.0, 'assetPath': ''},
    );

    final mathNodeLogic = UIModule(
      id: 'atom_logic_math_node',
      name: '计算节点',
      type: 'math_node',
      color: const Color(0xFFD1C4E9),
      properties: {
        'operation': '+',
        'paramA': 0.0,
        'paramB': 1.0,
        'paramC': 0.0,
        'activeParams': ['paramA', 'paramB'],
        'fallbackValue': 0.0,
        'calculationMode': 'auto',
        'frozen': false,
      },
    );

    final selectBasic = UIModule(
      id: 'atom_select_basic',
      name: '下拉选择',
      type: 'select',
      color: const Color(0xFF7E57C2),
      properties: {'options': ['选项 1'], 'current': '选项 1', 'variable': 'var.select'},
    );
    final indicator = UIModule(
      id: 'atom_indicator_basic',
      name: '状态指示灯',
      type: 'indicator',
      color: const Color(0xFF4CAF50),
      properties: {
        'currentValue': '',
        'defaultColor': 0xFF9E9E9E,
        'defaultGlow': false,
        'dotSize': 14.0,
        'statusRules': const [],
      },
    );
    final timer = UIModule(
      id: 'atom_timer_basic',
      name: '定时器',
      type: 'timer',
      color: const Color(0xFFFF9100),
      properties: {
        'interval': 1.0,
        'initialDelay': 0.0,
        'maxTicks': 0,
        'isRunning': false,
        'loop': true,
        'pulseType': 'increment',
        'currentVal': 0.0,
      },
    );
    final linker = UIModule(
      id: 'atom_linker_basic',
      name: '联动器',
      type: 'linker',
      color: const Color(0xFF00ACC1),
      properties: {
        'linker': {
          'sourceModuleId': '',
          'sourcePort': '',
          'sourceType': '',
          'targetModuleId': '',
          'targetPort': '',
          'targetType': '',
          'scheme': '未配置',
          'enabled': false,
          'priority': 5,
          'cooldownMs': 0,
          'maxTriggerCount': 0,
        },
      },
    );

    _modules = {
      dataBar.id: dataBar,
      surfaceBase.id: surfaceBase,
      text.id: text,
      buttonLogic.id: buttonLogic,
      inputLogic.id: inputLogic,
      switchLogic.id: switchLogic,
      slider.id: slider,
      line.id: line,
      imageSlot.id: imageSlot,
      mathNodeLogic.id: mathNodeLogic,
      selectBasic.id: selectBasic,
      indicator.id: indicator,
      timer.id: timer,
      linker.id: linker,
    };

    // 默认复合资产清空：复合组件由工作台按需构建。
    _composites = {};
  }

  void _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data != null) {
        final Map<String, dynamic> decoded = jsonDecode(data);
        
        // 加载原子模组 (与默认模组合并)
        final modulesJson = decoded['modules'] as Map<String, dynamic>? ?? {};
        modulesJson.forEach((k, v) {
          // 内置原材料由当前引擎版本维护，不能被旧草稿中的历史默认样式覆盖。
          if (!_foundationModuleOrder.contains(k) &&
              !_retiredFoundationModuleIds.contains(k)) {
            _modules[k] = UIModule.fromJson(v);
          }
        });
        
        // 加载组合块 (与默认组合块合并)
        final compositesJson = decoded['composites'] as Map<String, dynamic>? ?? {};
        compositesJson.forEach((k, v) {
          _composites[k] = UIComposite.fromJson(v);
        });
      }
    } catch (_) {
      // 解析出错则保留默认初始化
    }
  }

  Future<void> saveAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'modules': _modules.map((k, v) => MapEntry(k, v.toJson())),
      'composites': _composites.map((k, v) => MapEntry(k, v.toJson())),
    });
    await prefs.setString(_storageKey, data);
  }

  // --- 原子模组操作 ---
  void addModule(UIModule module) {
    _modules[module.id] = module;
    saveAssets();
  }

  UIModule? getModule(String id) => _modules[id];
  List<UIModule> getAllModules() => _modules.values.toList();

  /// 右侧完成资产库使用：排除内置基础原子与已废弃的历史基础预设。
  List<UIModule> getUserModules() => _modules.values
      .where((module) =>
          !_foundationModuleOrder.contains(module.id) &&
          !_retiredFoundationModuleIds.contains(module.id))
      .toList();

  /// 工作室左侧“原材料”只展示白名单内的引擎原子，并严格保持创作顺序。
  List<UIModule> getFoundationModules() => _foundationModuleOrder
      .map((id) => _modules[id])
      .whereType<UIModule>()
      .toList();

  void removeModule(String id) {
    _modules.remove(id);
    saveAssets();
  }

  // --- 组合块操作 ---
  void addComposite(UIComposite composite) {
    _composites[composite.id] = composite;
    saveAssets();
  }

  UIComposite? getComposite(String id) => _composites[id];
  List<UIComposite> getAllComposites() => _composites.values.toList();

  void removeComposite(String id) {
    _composites.remove(id);
    saveAssets();
  }
}
