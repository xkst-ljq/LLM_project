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

  // 提供开箱即用的默认丰富积木，避免新用户或清空缓存时列表空白
  void _initDefaultAssets() {
    // 1. 状态进度条 (生命、法力、好感度)
    final hpModule = UIModule(
      id: 'std_bar_hp',
      name: '生命值栏 (HP)',
      type: 'progress',
      color: Colors.redAccent,
      properties: {'min': 0, 'max': 100, 'current': 100},
      boundVariable: 'var.hp',
    );
    final mpModule = UIModule(
      id: 'std_bar_mp',
      name: '法力值栏 (MP)',
      type: 'progress',
      color: Colors.blueAccent,
      properties: {'min': 0, 'max': 100, 'current': 80},
      boundVariable: 'var.mp',
    );
    final apModule = UIModule(
      id: 'std_bar_ap',
      name: '行动力栏 (AP)',
      type: 'progress',
      color: Colors.amberAccent,
      properties: {'min': 0, 'max': 10, 'current': 10},
      boundVariable: 'var.ap',
    );

    // 2. 交互动作按钮
    final btnAttack = UIModule(
      id: 'std_btn_attack',
      name: '战斗动作: 攻击',
      type: 'button',
      color: Colors.deepOrange,
      properties: {'text': '🗡️ 拔剑攻击'},
    );
    final btnTalk = UIModule(
      id: 'std_btn_talk',
      name: '社交动作: 交谈',
      type: 'button',
      color: Colors.purpleAccent,
      properties: {'text': '💬 温柔搭话'},
    );

    // 3. 文本与展示块
    final txtTitle = UIModule(
      id: 'std_txt_title',
      name: '头衔与称号标签',
      type: 'text',
      color: Colors.cyanAccent,
      properties: {'text': '✨ 异世界传说中的勇者'},
    );

    // 4. 用户输入框
    final inputName = UIModule(
      id: 'std_input_name',
      name: '玩家自定称呼',
      type: 'input',
      color: Colors.tealAccent,
      properties: {'label': '告诉对方你的名字'},
    );

    _modules = {
      hpModule.id: hpModule,
      mpModule.id: mpModule,
      apModule.id: apModule,
      btnAttack.id: btnAttack,
      btnTalk.id: btnTalk,
      txtTitle.id: txtTitle,
      inputName.id: inputName,
    };

    // 组合块默认提供一个“基础战斗HUD”和一个“社交交互面板”
    final battleHud = UIComposite(
      id: 'std_comp_battle',
      name: '🛡️ 标准战斗状态面板',
      layoutType: 'column',
      color: Colors.blueGrey,
      children: [
        UIElement(id: 'c_hp', isComposite: false, module: hpModule),
        UIElement(id: 'c_mp', isComposite: false, module: mpModule),
        UIElement(id: 'c_atk', isComposite: false, module: btnAttack),
      ],
    );

    final socialHud = UIComposite(
      id: 'std_comp_social',
      name: '🌸 社交与问候面板',
      layoutType: 'column',
      color: Colors.pink,
      children: [
        UIElement(id: 'c_title', isComposite: false, module: txtTitle),
        UIElement(id: 'c_name', isComposite: false, module: inputName),
        UIElement(id: 'c_talk', isComposite: false, module: btnTalk),
      ],
    );

    _composites = {
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
