import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_models.dart';

class UIAssetService {
  static const String _storageKey = 'global_ui_assets_foundation_v1';

  // 全局原子模组库
  Map<String, UIModule> _modules = {};
  // 全局组合块库
  Map<String, UIComposite> _composites = {};

  UIAssetService() {
    _initDefaultAssets();
    _loadAssets();
  }

  // 提供开箱即用的“基础原材料”库。
  // 当前默认不再内置任何复合资产；复合组件应由复合工作台基于这些
  // 原材料重新拼装，避免“生命条/攻击键”等具体语义污染基础层。
  void _initDefaultAssets() {
    final dataBarNeutral = UIModule(
      id: 'atom_data_bar_neutral',
      name: '数据条原子 / 中性',
      type: 'progress',
      color: const Color(0xFF607D8B),
      properties: {'min': 0, 'max': 100, 'current': 65},
    );
    final dataBarAccent = UIModule(
      id: 'atom_data_bar_accent',
      name: '数据条原子 / 强调',
      type: 'progress',
      color: const Color(0xFFFF4081),
      properties: {'min': 0, 'max': 100, 'current': 65},
    );
    final dataBarCool = UIModule(
      id: 'atom_data_bar_cool',
      name: '数据条原子 / 冷色',
      type: 'progress',
      color: const Color(0xFF00E5FF),
      properties: {'min': 0, 'max': 100, 'current': 65},
    );

    final surfaceGlass = UIModule(
      id: 'atom_surface_glass_panel',
      name: '面原子 / 玻璃',
      type: 'surface',
      color: Colors.white,
      material: UIModuleMaterial.glass,
      shape: UIModuleShape.rounded,
      borderRadius: 18,
      opacity: 0.78,
      properties: {},
    );
    final surfaceSolid = UIModule(
      id: 'atom_surface_solid_panel',
      name: '面原子 / 实色',
      type: 'surface',
      color: const Color(0xFF263238),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rounded,
      borderRadius: 16,
      opacity: 0.92,
      properties: {},
    );
    final surfaceCapsule = UIModule(
      id: 'atom_surface_capsule',
      name: '面原子 / 胶囊',
      type: 'surface',
      color: const Color(0xFF651FFF),
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.capsule,
      properties: {},
    );
    final surfaceEllipse = UIModule(
      id: 'atom_surface_ellipse',
      name: '面原子 / 椭圆',
      type: 'surface',
      color: const Color(0xFFFF4081),
      material: UIModuleMaterial.gradient,
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

    final textDark = UIModule(
      id: 'atom_text_dark',
      name: '文本原子 / 深色',
      type: 'text',
      color: const Color(0xFF111116),
      properties: {'text': '文本'},
    );
    final textLight = UIModule(
      id: 'atom_text_light',
      name: '文本原子 / 浅色',
      type: 'text',
      color: Colors.white,
      properties: {'text': '文本'},
    );
    final textAccent = UIModule(
      id: 'atom_text_accent',
      name: '文本原子 / 强调色',
      type: 'text',
      color: const Color(0xFF00ACC1),
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

    final slider = UIModule(
      id: 'atom_slider_basic',
      name: '交互原子 / 通用滑块',
      type: 'slider',
      color: const Color(0xFF00ACC1),
      properties: {'min': 0, 'max': 100, 'current': 50, 'step': 1},
    );

    final line = UIModule(
      id: 'atom_line_divider',
      name: '装饰原子 / 分隔线',
      type: 'primitive_art',
      color: const Color(0xFFB0BEC5),
      properties: {
        'layers': [
          UIPrimitiveLayer(
            id: 'line_0',
            kind: 'line',
            offset: const Offset(0, 0.5),
            size: const Size(1, 0),
            color: const Color(0xFFB0BEC5),
            properties: {'width': 1.2},
          ).toJson(),
        ],
      },
    );

    final softGlow = UIModule(
      id: 'atom_light_soft_glow',
      name: '光效原子 / 柔光块',
      type: 'light_effect',
      color: const Color(0xFF7C4DFF),
      properties: {
        'layers': [
          UIPrimitiveLayer(
            id: 'glow_0',
            kind: 'glow',
            offset: const Offset(0.08, 0.08),
            size: const Size(0.84, 0.84),
            color: const Color(0xFF7C4DFF),
            opacity: 0.45,
            shape: UIModuleShape.circle,
            properties: {'blur': 24, 'blendMode': 'plus'},
          ).toJson(),
          UIPrimitiveLayer(
            id: 'glow_core',
            kind: 'surface',
            offset: const Offset(0.25, 0.25),
            size: const Size(0.5, 0.5),
            color: const Color(0xFFB388FF),
            opacity: 0.34,
            shape: UIModuleShape.circle,
          ).toJson(),
        ],
      },
    );

    final layeredSurface = UIModule(
      id: 'atom_surface_art_glass_highlight',
      name: '面原子 / 高光玻璃',
      type: 'surface_art',
      color: Colors.white,
      properties: {
        'composeMode': 'edgeBlend',
        'layers': [
          UIPrimitiveLayer(
            id: 'base',
            kind: 'surface',
            offset: Offset.zero,
            size: const Size(1, 1),
            color: const Color(0xFF651FFF),
            opacity: 0.70,
            shape: UIModuleShape.rounded,
            borderRadius: 20,
          ).toJson(),
          UIPrimitiveLayer(
            id: 'highlight',
            kind: 'highlight',
            offset: const Offset(0.06, 0.05),
            size: const Size(0.88, 0.36),
            color: Colors.white,
            opacity: 0.45,
            shape: UIModuleShape.rounded,
            borderRadius: 18,
            properties: {'blendMode': 'screen'},
          ).toJson(),
          UIPrimitiveLayer(
            id: 'stroke',
            kind: 'stroke',
            offset: const Offset(0.01, 0.01),
            size: const Size(0.98, 0.98),
            color: Colors.white,
            opacity: 0.55,
            shape: UIModuleShape.rounded,
            borderRadius: 20,
            properties: {'width': 1.1},
          ).toJson(),
        ],
      },
    );

    _modules = {
      dataBarNeutral.id: dataBarNeutral,
      dataBarAccent.id: dataBarAccent,
      dataBarCool.id: dataBarCool,
      surfaceGlass.id: surfaceGlass,
      surfaceSolid.id: surfaceSolid,
      surfaceCapsule.id: surfaceCapsule,
      surfaceEllipse.id: surfaceEllipse,
      surfaceOutline.id: surfaceOutline,
      textDark.id: textDark,
      textLight.id: textLight,
      textAccent.id: textAccent,
      buttonLogic.id: buttonLogic,
      inputLogic.id: inputLogic,
      slider.id: slider,
      line.id: line,
      softGlow.id: softGlow,
      layeredSurface.id: layeredSurface,
    };

    // 按用户当前阶段要求：默认复合资产清空。
    // 复合工作台后续只基于基础原材料重新生成通用完型组件。
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

  // --- 组合块操作 ---
  void addComposite(UIComposite composite) {
    _composites[composite.id] = composite;
    saveAssets();
  }

  UIComposite? getComposite(String id) => _composites[id];
  List<UIComposite> getAllComposites() => _composites.values.toList();
}
