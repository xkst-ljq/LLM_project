import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_models.dart';

class UIAssetService {
  static const String _storageKey = 'global_ui_assets_flat_foundation_v2';

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
      name: '数据条原子',
      type: 'progress',
      color: const Color(0xFFFF4081),
      properties: {'min': 0, 'max': 100, 'current': 65},
    );

    final surfaceBase = UIModule(
      id: 'atom_surface_base',
      name: '面原子 / 矩形',
      type: 'surface',
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rounded,
      borderRadius: 16,
      properties: {},
    );
    final surfaceCapsule = UIModule(
      id: 'atom_surface_capsule',
      name: '面原子 / 胶囊',
      type: 'surface',
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.capsule,
      properties: {},
    );
    final surfaceEllipse = UIModule(
      id: 'atom_surface_ellipse',
      name: '面原子 / 椭圆',
      type: 'surface',
      color: const Color(0xFFFF4081),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.circle,
      properties: {},
    );
    final surfaceOutline = UIModule(
      id: 'atom_surface_outline',
      name: '面原子 / 描边',
      type: 'surface',
      color: const Color(0xFF00ACC1),
      material: UIModuleMaterial.outline,
      shape: UIModuleShape.rounded,
      borderRadius: 14,
      properties: {},
    );

    final text = UIModule(
      id: 'atom_text',
      name: '文本原子',
      type: 'text',
      color: const Color(0xFF111116),
      properties: {'text': '文本'},
    );

    final buttonLogic = UIModule(
      id: 'atom_logic_button_tap',
      name: '逻辑原子 / 点击热区',
      type: 'button',
      color: Colors.transparent,
      properties: {'action': 'tap'},
    );
    final inputLogic = UIModule(
      id: 'atom_logic_input_text',
      name: '逻辑原子 / 输入热区',
      type: 'input',
      color: Colors.transparent,
      properties: {'variable': 'var.input'},
    );

    final switchLogic = UIModule(
      id: 'atom_logic_switch_bool',
      name: '逻辑原子 / 布尔开关',
      type: 'switch',
      color: const Color(0xFF00E676),
      properties: {'value': true, 'variable': 'switch_var'},
    );

    final slider = UIModule(
      id: 'atom_slider_basic',
      name: '滑块原子',
      type: 'slider',
      color: const Color(0xFF00ACC1),
      properties: {'min': 0, 'max': 100, 'current': 50, 'step': 1},
    );

    final line = UIModule(
      id: 'atom_line_multi',
      name: '多功能线段原子',
      type: 'line',
      color: const Color(0xFFB0BEC5),
      properties: {'thickness': 2.0, 'lineStyle': 'solid', 'axis': 'horizontal', 'dashLength': 6.0, 'gapLength': 3.0},
    );

    final imageSlot = UIModule(
      id: 'atom_image_holder',
      name: '静态位图插槽原子',
      type: 'image',
      color: const Color(0xFF2979FF),
      properties: {'url': '', 'fit': 'cover', 'shape': 'rectangle', 'borderRadius': 8.0, 'assetPath': ''},
    );

    final mathNodeLogic = UIModule(
      id: 'atom_logic_math_node',
      name: '逻辑原子 / 算术计算节点',
      type: 'math_node',
      color: const Color(0xFFD1C4E9),
      properties: {
        'operation': '+',
        'value': 1.0,
        'extractMethod': 'first',
        'extractKey': '',
        'extractIndex': 0,
        'delimiter': '/',
      },
    );

    final selectBasic = UIModule(
      id: 'atom_select_basic',
      name: '交互原子 / 下拉单选框',
      type: 'select',
      color: const Color(0xFF7E57C2),
      properties: {'options': ['选项 1'], 'current': '选项 1', 'variable': 'var.select'},
    );

    _modules = {
      dataBar.id: dataBar,
      surfaceBase.id: surfaceBase,
      surfaceCapsule.id: surfaceCapsule,
      surfaceEllipse.id: surfaceEllipse,
      surfaceOutline.id: surfaceOutline,
      text.id: text,
      buttonLogic.id: buttonLogic,
      inputLogic.id: inputLogic,
      switchLogic.id: switchLogic,
      slider.id: slider,
      line.id: line,
      imageSlot.id: imageSlot,
      mathNodeLogic.id: mathNodeLogic,
      selectBasic.id: selectBasic,
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
          _modules[k] = UIModule.fromJson(v);
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
