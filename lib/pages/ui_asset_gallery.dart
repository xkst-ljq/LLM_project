import 'package:flutter/material.dart';

import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

class UIAssetGallery extends StatefulWidget {
  const UIAssetGallery({super.key});

  @override
  State<UIAssetGallery> createState() => _UIAssetGalleryState();
}

class _UIAssetGalleryState extends State<UIAssetGallery> {
  final UIAssetService _assetService = UIAssetService();

  @override
  void initState() {
    super.initState();
    _initTestAssets();
  }

  void _initTestAssets() {
    // 模组库预览页只注入基础原材料示例，不再自动注入复合资产。
    _assetService.addModule(UIModule(
      id: 'test_progress',
      name: '数据条原子预览',
      type: 'progress',
      color: Colors.redAccent,
      properties: {'min': 0, 'max': 100, 'current': 65},
      boundVariable: 'var.value',
    ));

    _assetService.addModule(UIModule(
      id: 'test_surface',
      name: '表面原子预览',
      type: 'surface',
      color: Colors.deepPurpleAccent,
      material: UIModuleMaterial.gradient,
      shape: UIModuleShape.capsule,
      properties: {},
    ));

    _assetService.addModule(UIModule(
      id: 'test_slider',
      name: '滑块原子预览',
      type: 'slider',
      color: const Color(0xFF00ACC1),
      properties: {'min': 0, 'max': 100, 'current': 50},
    ));

    _assetService.addModule(UIModule(
      id: 'test_button_logic',
      name: '点击逻辑区预览',
      type: 'button',
      color: Colors.transparent,
      properties: {'action': 'tap'},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final modules = _assetService.getAllModules();
    final composites = _assetService.getAllComposites();

    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 模组库'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'UI 模组预览',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: modules.map((m) {
              return SizedBox(
                width: 160,
                child: UIRenderer.render(context, UIElement(id: m.id, isComposite: false, module: m)),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text(
            '组合块预览',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black38,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: composites.map((c) {
              return SizedBox(
                width: 200,
                child: UIRenderer.render(context, UIElement(id: c.id, isComposite: true, composite: c)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
