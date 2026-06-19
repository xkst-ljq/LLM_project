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
    _assetService.addModule(UIModule(
      id: 'test_progress',
      name: '生命值',
      type: 'progress',
      color: Colors.redAccent,
      properties: {'min': 0, 'max': 100},
      boundVariable: 'var.hp',
    ));

    _assetService.addModule(UIModule(
      id: 'test_button',
      name: '快速发送',
      type: 'button',
      color: Colors.deepPurpleAccent,
      properties: {'text': '发送 lOVE'},
    ));

    _assetService.addComposite(UIComposite(
      id: 'test_composite',
      name: '基础面板',
      layoutType: 'column',
      children: [
        UIElement(id: 'e1', isComposite: false, module: _assetService.getModule('test_progress')),
        UIElement(id: 'e2', isComposite: false, module: _assetService.getModule('test_button')),
      ],
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
