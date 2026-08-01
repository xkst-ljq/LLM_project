import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/ui_composite_asset_service.dart';
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
    // 用 getUserModules 而非 getAllModules：内置引擎原子（文本、按钮、
    // 滑块……）是所有 UI 的默认元素，作者在工作台左侧「原材料」区
    // 随时能取用，在成品库里再陈列一遍纯属噪音（用户反馈）。
    // 这里只展示作者**自己保存**的资产。
    final modules = _assetService.getUserModules();
    final composites = _assetService.getAllComposites();
    final isEmpty = modules.isEmpty && composites.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 模组库'),
        actions: [
          IconButton(
            tooltip: '导入复合组件',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _importComposite,
          ),
        ],
      ),
      body: isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有保存的资产。\n'
                  '在 UI 工作台拼好积木后点「保存」，就会出现在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888896),
                    height: 1.5,
                  ),
                ),
              ),
            )
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 两个分区都做空判断：只存过复合件时不该留一个空的「自定义模组」
          // 标题杵在上面。
          if (modules.isNotEmpty) ...[
          Text(
            '自定义模组',
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
          ],
          if (composites.isNotEmpty) ...[
          Text(
            '组合块',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UILinkerSnapshotScope(
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF888896),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _exportComposite(c),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.ios_share_rounded,
                                size: 15, color: Color(0xFF00897B)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          ],
        ],
      ),
    );
  }

  /// 导出单个复合组件为 .llmui 文件。
  Future<void> _exportComposite(UIComposite composite) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await UICompositeAssetService.exportComposite(composite);
      final saved =
          await UICompositeAssetService.saveCompositeToDownloads(file);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                ? '已导出到应用目录：${file.uri.pathSegments.last}'
                : '已保存到下载目录：${file.uri.pathSegments.last}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// 导入 .llmui 文件。
  ///
  /// id 由 readCompositeAsset 内部重映射过，不会覆盖已有组件。
  Future<void> _importComposite() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LLM Project 复合组件文件',
      type: FileType.any,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) {
      messenger.showSnackBar(const SnackBar(content: Text('无法读取该文件')));
      return;
    }

    try {
      final composite =
          await UICompositeAssetService.readCompositeAsset(File(path));
      await _assetService.ensureLoaded();
      // addComposite 内部已经 saveAssets()。
      _assetService.addComposite(composite);
      if (!mounted) return;
      setState(() {});
      messenger.showSnackBar(
        SnackBar(content: Text('已导入「${composite.name}」')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }
}
