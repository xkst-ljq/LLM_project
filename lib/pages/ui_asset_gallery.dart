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
    _assetService.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
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
              final element =
                  UIElement(id: m.id, isComposite: false, module: m);
              return SizedBox(
                width: 160,
                child: UILinkerSnapshotScope(
                  snapshot: LinkerSnapshot.fromElements([element]),
                  child: UISceneModeScope(
                    isStudioCreationMode: true,
                    child: IgnorePointer(
                      child: Builder(
                        builder: (ctx) => UIRenderer.render(ctx, element),
                      ),
                    ),
                  ),
                ),
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
              final element =
                  UIElement(id: c.id, isComposite: true, composite: c);
              return SizedBox(
                width: 200,
                child: UILinkerSnapshotScope(
                  snapshot: LinkerSnapshot.fromElements([element]),
                  child: UISceneModeScope(
                    isStudioCreationMode: true,
                    child: IgnorePointer(
                      child: Builder(
                        builder: (ctx) => UIRenderer.render(ctx, element),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
