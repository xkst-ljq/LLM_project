import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_models.dart';

class UIAssetService {
  static const String _storageKey = 'global_ui_assets';

  // 全局原子模组库
  Map<String, UIModule> _modules = {};
  // 全局组合块库
  Map<String, UIComposite> _composites = {};

  UIAssetService() {
    _initDefaultAssets();
    _loadAssets();
  }

  // 提供开箱即用的默认积木。这里刻意把“原子”和“复合”拆开：
  // - 原子模组只做一种功能；
  // - 带文字按钮、带标签进度条、视觉输入框、HUD 面板等都放入组合块库。
  void _initDefaultAssets() {
    // 1. 纯原子：进度条只是一根条，不内置名称/数值。
    final hpModule = UIModule(
      id: 'std_bar_hp',
      name: '红色进度条原子',
      type: 'progress',
      color: Colors.redAccent,
      properties: {'min': 0, 'max': 100, 'current': 100},
      boundVariable: 'var.hp',
    );
    final mpModule = UIModule(
      id: 'std_bar_mp',
      name: '蓝色进度条原子',
      type: 'progress',
      color: Colors.blueAccent,
      properties: {'min': 0, 'max': 100, 'current': 80},
      boundVariable: 'var.mp',
    );
    final apModule = UIModule(
      id: 'std_bar_ap',
      name: '黄色进度条原子',
      type: 'progress',
      color: Colors.amberAccent,
      properties: {'min': 0, 'max': 10, 'current': 10},
      boundVariable: 'var.ap',
    );
    final greenBar = UIModule(
      id: 'std_bar_green',
      name: '绿色进度条原子',
      type: 'progress',
      color: const Color(0xFF00C853),
      properties: {'min': 0, 'max': 100, 'current': 60},
    );

    // 2. 纯原子：视觉表面，只负责画形状/底板。
    final surfacePanel = UIModule(
      id: 'std_surface_panel_glass',
      name: '玻璃面板表面原子',
      type: 'surface',
      color: Colors.white,
      material: UIModuleMaterial.glass,
      shape: UIModuleShape.rounded,
      borderRadius: 18,
      opacity: 0.78,
      properties: {},
    );
    final surfaceDark = UIModule(
      id: 'std_surface_dark',
      name: '深色面板表面原子',
      type: 'surface',
      color: const Color(0xFF263238),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rounded,
      borderRadius: 16,
      opacity: 0.92,
      properties: {},
    );
    final surfaceButtonOrange = UIModule(
      id: 'std_surface_btn_orange',
      name: '橙色胶囊表面原子',
      type: 'surface',
      color: Colors.deepOrange,
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.capsule,
      properties: {},
    );
    final surfaceButtonPurple = UIModule(
      id: 'std_surface_btn_purple',
      name: '紫色胶囊表面原子',
      type: 'surface',
      color: Colors.purpleAccent,
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.capsule,
      properties: {},
    );
    final surfaceInput = UIModule(
      id: 'std_surface_input',
      name: '输入框底板表面原子',
      type: 'surface',
      color: const Color(0xFFEBEBF1),
      material: UIModuleMaterial.solid,
      shape: UIModuleShape.rounded,
      borderRadius: 10,
      properties: {},
    );
    final surfaceCircle = UIModule(
      id: 'std_surface_circle',
      name: '椭圆 / 正圆表面原子',
      type: 'surface',
      color: const Color(0xFFFF4081),
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.circle,
      properties: {},
    );
    final surfaceOutline = UIModule(
      id: 'std_surface_outline',
      name: '描边面板表面原子',
      type: 'surface',
      color: const Color(0xFF00ACC1),
      material: UIModuleMaterial.outline,
      shape: UIModuleShape.rounded,
      borderRadius: 14,
      properties: {},
    );

    // 3. 纯原子：逻辑热区。它们透明，不负责外观。
    final buttonLogic = UIModule(
      id: 'std_logic_button',
      name: '按钮点击逻辑区原子',
      type: 'button',
      color: Colors.transparent,
      properties: {'action': 'tap'},
    );
    final inputLogic = UIModule(
      id: 'std_logic_input',
      name: '输入触发逻辑区原子',
      type: 'input',
      color: Colors.transparent,
      properties: {'variable': 'var.input'},
    );

    // 4. 纯原子：文本只显示文字。
    final txtTitle = UIModule(
      id: 'std_txt_title',
      name: '黑色文本原子',
      type: 'text',
      color: const Color(0xFF111116),
      properties: {'text': '文本'},
    );
    final txtWhite = UIModule(
      id: 'std_txt_white',
      name: '白色文本原子',
      type: 'text',
      color: Colors.white,
      properties: {'text': '白色文字'},
    );
    final txtAccent = UIModule(
      id: 'std_txt_accent',
      name: '强调色文本原子',
      type: 'text',
      color: const Color(0xFF00ACC1),
      properties: {'text': '强调文字'},
    );

    _modules = {
      hpModule.id: hpModule,
      mpModule.id: mpModule,
      apModule.id: apModule,
      greenBar.id: greenBar,
      surfacePanel.id: surfacePanel,
      surfaceDark.id: surfaceDark,
      surfaceButtonOrange.id: surfaceButtonOrange,
      surfaceButtonPurple.id: surfaceButtonPurple,
      surfaceInput.id: surfaceInput,
      surfaceCircle.id: surfaceCircle,
      surfaceOutline.id: surfaceOutline,
      buttonLogic.id: buttonLogic,
      inputLogic.id: inputLogic,
      txtTitle.id: txtTitle,
      txtWhite.id: txtWhite,
      txtAccent.id: txtAccent,
    };

    // --- 复合模板：用原子拼出来的“可直接使用”的部件 ---
    UIModule textAtom(String id, String text, {Color color = const Color(0xFF111116)}) {
      return UIModule(
        id: id,
        name: text,
        type: 'text',
        color: color,
        properties: {'text': text},
      );
    }

    final hpLabel = textAtom('std_txt_hp_label', '生命值');
    final hpValue = textAtom('std_txt_hp_value', '100/100');
    final mpLabel = textAtom('std_txt_mp_label', '法力值');
    final mpValue = textAtom('std_txt_mp_value', '80/100');
    final attackText = textAtom('std_txt_attack', '🗡️ 攻击', color: Colors.white);
    final talkText = textAtom('std_txt_talk', '💬 交谈', color: Colors.white);
    final placeholderText = textAtom('std_txt_input_placeholder', '请输入称呼...', color: const Color(0xFF888896));
    final titleText = textAtom('std_txt_social_title', '✨ 异世界传说中的勇者', color: const Color(0xFF00ACC1));

    final attackButton = UIComposite(
      id: 'std_comp_attack_button',
      name: '🗡️ 带文字攻击按钮',
      layoutType: 'stack',
      color: Colors.transparent,
      opacity: 0.0,
      children: [
        UIElement(id: 'atk_surface', isComposite: false, module: surfaceButtonOrange, size: const Size(140, 44)),
        UIElement(id: 'atk_text', isComposite: false, module: attackText, size: const Size(140, 44)),
        UIElement(id: 'atk_logic', isComposite: false, module: buttonLogic, size: const Size(140, 44)),
      ],
    );

    final talkButton = UIComposite(
      id: 'std_comp_talk_button',
      name: '💬 带文字交谈按钮',
      layoutType: 'stack',
      color: Colors.transparent,
      opacity: 0.0,
      children: [
        UIElement(id: 'talk_surface', isComposite: false, module: surfaceButtonPurple, size: const Size(140, 44)),
        UIElement(id: 'talk_text', isComposite: false, module: talkText, size: const Size(140, 44)),
        UIElement(id: 'talk_logic', isComposite: false, module: buttonLogic, size: const Size(140, 44)),
      ],
    );

    final inputBox = UIComposite(
      id: 'std_comp_input_box',
      name: '⌨️ 带占位文字输入框',
      layoutType: 'stack',
      color: Colors.transparent,
      opacity: 0.0,
      children: [
        UIElement(id: 'input_surface', isComposite: false, module: surfaceInput, size: const Size(210, 42)),
        UIElement(id: 'input_placeholder', isComposite: false, module: placeholderText, size: const Size(210, 42)),
        UIElement(id: 'input_logic', isComposite: false, module: inputLogic, size: const Size(210, 42)),
      ],
    );

    final battleHud = UIComposite(
      id: 'std_comp_battle',
      name: '🛡️ 标准战斗状态面板',
      layoutType: 'column',
      color: Colors.blueGrey,
      children: [
        UIElement(id: 'c_hp_label', isComposite: false, module: hpLabel, size: const Size(180, 24)),
        UIElement(id: 'c_hp', isComposite: false, module: hpModule, size: const Size(180, 14)),
        UIElement(id: 'c_hp_value', isComposite: false, module: hpValue, size: const Size(180, 22)),
        UIElement(id: 'c_mp_label', isComposite: false, module: mpLabel, size: const Size(180, 24)),
        UIElement(id: 'c_mp', isComposite: false, module: mpModule, size: const Size(180, 14)),
        UIElement(id: 'c_mp_value', isComposite: false, module: mpValue, size: const Size(180, 22)),
        UIElement(id: 'c_atk', isComposite: true, composite: attackButton, size: const Size(170, 62)),
      ],
    );

    final socialHud = UIComposite(
      id: 'std_comp_social',
      name: '🌸 社交与问候面板',
      layoutType: 'column',
      color: Colors.pink,
      children: [
        UIElement(id: 'c_title', isComposite: false, module: titleText, size: const Size(210, 34)),
        UIElement(id: 'c_name', isComposite: true, composite: inputBox, size: const Size(230, 54)),
        UIElement(id: 'c_talk', isComposite: true, composite: talkButton, size: const Size(170, 62)),
      ],
    );

    _composites = {
      attackButton.id: attackButton,
      talkButton.id: talkButton,
      inputBox.id: inputBox,
      battleHud.id: battleHud,
      socialHud.id: socialHud,
    };
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
